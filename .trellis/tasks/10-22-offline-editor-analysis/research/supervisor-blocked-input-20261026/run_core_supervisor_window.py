"""Narrow, grant-required supervisor checks. No SDK runs on import."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
CORE = Path("D:/MyNewProjects/qfli_studio_core")
HELPER = ROOT / "build/baseline_200_owned_job.py"
HELPER_SHA = "5c3dc4d0bdaaa26233212560968b58d02e215eb27c29e9e88be4c99d212ce116"
DART = Path("D:/ProgramFiles/flutter_ohos/bin/cache/dart-sdk/bin/dart.exe")
FLUTTER = Path("D:/ProgramFiles/flutter_ohos/bin/flutter.bat")
SOURCES = ("lib/services/process_supervisor.dart", "test/process_supervisor_test.dart")
FATAL = (b"out of memory", b"exhausted heap space", b"dart compiler exited unexpectedly",
         b"fatal error", b"unhandled exception")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("grant", help="Fresh, concrete root-issued window name")
    args = parser.parse_args()
    if not args.grant.strip():
        parser.error("grant must be nonempty")
    began = time.monotonic()
    payload_deadline = began + 90
    cleanup_deadline = began + 105
    work = ROOT / "build" / ("core-supervisor-window-" +
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    work.mkdir()
    record = {"grant": args.grant, "startedAt": datetime.now(timezone.utc).isoformat(),
              "payloadBudgetSeconds": 90, "cleanupAllowanceSeconds": 15,
              "rootGrantBudgetSeconds": 150, "steps": [], "allJobsTerminalAndEmpty": True,
              "allHandlesClosed": True, "sdkOnly": True, "deviceExecuted": False,
              "outerTerminalObservation": "Required from root tool; not asserted by runner",
              "passed": False, "hashChecks": [], "everHold": False,
              "budgetIsHardExitGuarantee": False}
    inputs = {"source:" + p: CORE / p for p in SOURCES}
    inputs.update({"runner": Path(__file__).resolve(), "helper": HELPER,
                   "dart": DART, "flutter": FLUTTER})
    baseline = None

    def write():
        record["elapsedSeconds"] = round(time.monotonic() - began, 3)
        temp = work / "report.json.tmp"
        temp.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        temp.replace(work / "report.json")

    def check_hashes(stage):
        values = {name: sha(path) for name, path in inputs.items()}
        check = {"stage": stage, "hashes": values, "stable": values == baseline}
        record["hashChecks"].append(check)
        if not check["stable"]:
            raise RuntimeError("Immutable input hash mismatch at " + stage)

    def scan(step):
        matches = []
        for channel in ("stdout", "stderr"):
            path = work / (step["name"] + "." + channel)
            if path.exists():
                data = path.read_bytes().lower()
                matches.extend({"channel": channel, "signature": sig.decode("ascii")}
                               for sig in FATAL if sig in data)
        if matches:
            step["fatalSignatures"] = matches
        return bool(matches)

    try:
        baseline = {name: sha(path) for name, path in inputs.items()}
        record["inputPaths"] = {name: str(path) for name, path in inputs.items()}
        record["initialHashes"] = baseline
        if baseline["helper"] != HELPER_SHA:
            raise RuntimeError("Reviewed OwnedJob helper hash mismatch")
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("supervisor_owned_job", HELPER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        commands = [
            ("format", [str(DART), "format", "--output=none", "--set-exit-if-changed", *SOURCES]),
            ("analyze", ["cmd.exe", "/d", "/c", str(FLUTTER) +
                         " analyze --no-pub " + " ".join(SOURCES)]),
            ("test", ["cmd.exe", "/d", "/c", str(FLUTTER) +
                      " test --no-pub --concurrency=1 test/process_supervisor_test.dart"]),
        ]
        write()
        for name, command in commands:
            check_hashes("before-" + name)
            if time.monotonic() >= payload_deadline:
                raise TimeoutError("Shared 90-second payload budget exhausted")
            step = {"name": name, "command": command, "cleanupErrors": [],
                    "terminalAndEmpty": False, "handlesClosed": False}
            record["steps"].append(step)
            job = None
            stop_attempted = False

            def verify_identity():
                if job.process is None:
                    if job.record:
                        raise RuntimeError("Owned root process handle missing")
                    return
                stamps = [module.W.FILETIME() for _ in range(4)]
                job.check(job.k.GetProcessTimes(job.process, *(module.C.byref(s) for s in stamps)))
                created = str((stamps[0].dwHighDateTime << 32) | stamps[0].dwLowDateTime)
                if (job.k.GetProcessId(job.process) != job.record["pid"] or
                        created != job.record["creationFiletime100ns"]):
                    raise RuntimeError("Retained root PID/FILETIME mismatch")
                step["rootIdentityVerified"] = True

            def stop_owned():
                nonlocal stop_attempted
                if not stop_attempted:
                    step["forcedTerminationAttempted"] = True
                    job.stop()
                    stop_attempted = True
                    step["terminationRequested"] = True

            try:
                job = module.OwnedJob()
                with (work / (name + ".stdout")).open("wb") as out, \
                        (work / (name + ".stderr")).open("wb") as err:
                    job.start(command, CORE, dict(os.environ), out, err)
                    step["retainedRootHandle"] = int(job.process)
                    step["retainedJobHandle"] = int(job.job)
                    verify_identity()
                    while True:
                        empty = job.empty()
                        fatal = scan(step)
                        if fatal:
                            step["failureReason"] = "fatal-output"
                            if not empty:
                                stop_owned()
                            break
                        if empty:
                            break
                        if time.monotonic() >= payload_deadline:
                            step["failureReason"] = "payload-timeout"
                            stop_owned()
                            break
                        time.sleep(.1)
            except BaseException as error:
                step["error"] = repr(error)
            finally:
                if job is not None:
                    drain_deadline = min(time.monotonic() + 15, cleanup_deadline)
                    cleanup_proof = False
                    while not step["handlesClosed"]:
                        try:
                            if not cleanup_proof:
                                verify_identity()
                                step["terminalAndEmpty"] = job.empty()
                                step["job"] = dict(job.record)
                                if step["terminalAndEmpty"]:
                                    cleanup_proof = True
                                    step["exactCleanupProof"] = True
                                else:
                                    stop_owned()
                                    if time.monotonic() >= drain_deadline:
                                        step["everHold"] = True
                                        record["everHold"] = True
                                        step["holdReason"] = "Cleanup observation exceeded allowance"
                            if cleanup_proof:
                                # Keep each handle until its individual close succeeds.
                                # Never call helper.close(): it clears failed-close handles.
                                for field in ("process", "job"):
                                    handle = getattr(job, field, None)
                                    if handle:
                                        job.check(job.k.CloseHandle(handle))
                                        setattr(job, field, None)
                                        step[field + "HandleClosed"] = True
                                step["handlesClosed"] = True
                        except BaseException as error:
                            step["everHold"] = True
                            record["everHold"] = True
                            message = repr(error)
                            if message not in step["cleanupErrors"]:
                                step["cleanupErrors"].append(message)
                            step["cleanupErrorObservations"] = step.get("cleanupErrorObservations", 0) + 1
                            step["job"] = dict(job.record)
                        record["allJobsTerminalAndEmpty"] = all(
                            item["terminalAndEmpty"] for item in record["steps"])
                        record["allHandlesClosed"] = all(
                            item["handlesClosed"] for item in record["steps"])
                        record["releaseEvidence"] = ("ROOT_OUTER_TERMINAL_REQUIRED" if
                            record["allJobsTerminalAndEmpty"] and record["allHandlesClosed"] else "HOLD")
                        try:
                            write()
                            if not step["handlesClosed"]:
                                time.sleep(.1)
                        except BaseException as error:
                            # Reporting failure or interruption must not discard live handles.
                            step["everHold"] = True
                            record["everHold"] = True
                            message = "Report/poll: " + repr(error)
                            if message not in step["cleanupErrors"]:
                                step["cleanupErrors"].append(message)
                else:
                    # No OwnedJob was returned, so no child process was started.
                    step["terminalAndEmpty"] = True
                    step["handlesClosed"] = True
                record["allJobsTerminalAndEmpty"] &= step["terminalAndEmpty"]
                record["allHandlesClosed"] &= step["handlesClosed"]
                scan(step)
                for channel in ("stdout", "stderr"):
                    path = work / (name + "." + channel)
                    if path.exists():
                        step[channel + "Sha256"] = sha(path)
                        step[channel + "Bytes"] = path.stat().st_size
                write()
            check_hashes("after-" + name)
            step["passed"] = (step.get("job", {}).get("exitCode") == 0 and
                              step["terminalAndEmpty"] and step["handlesClosed"] and
                              step.get("rootIdentityVerified", False) and
                              not step["cleanupErrors"] and not step.get("error") and
                              not step.get("failureReason") and not step.get("fatalSignatures") and
                              not step.get("forcedTerminationAttempted") and not step.get("everHold"))
            write()
            if not step["passed"]:
                break
        check_hashes("final")
        record["passed"] = (not record["everHold"] and len(record["steps"]) == 3 and
                            all(step.get("passed", False) for step in record["steps"]))
    except BaseException as error:
        record["error"] = repr(error)
    finally:
        if baseline is not None:
            try:
                check_hashes("finally")
            except BaseException as error:
                record["finalHashError"] = repr(error)
                record["passed"] = False
        record["releaseEvidence"] = ("ROOT_OUTER_TERMINAL_REQUIRED" if
            record["allJobsTerminalAndEmpty"] and record["allHandlesClosed"] else "HOLD")
        write()
    print(json.dumps({"work": str(work), **record}, indent=2))
    if not record["allJobsTerminalAndEmpty"] or not record["allHandlesClosed"]:
        return 2
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
