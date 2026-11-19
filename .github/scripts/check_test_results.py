"""比较 flutter test 的 JSON 结果与已知失败清单。

出现清单外的失败（含加载失败）时退出码为 1。清单内的测试已经通过时只提示，
方便以后从清单里删掉。没有跑任何测试也算失败。
"""
import json
import sys

results_path, known_path = sys.argv[1], sys.argv[2]
known = {
    line.strip()
    for line in open(known_path, encoding="utf-8")
    if line.strip() and not line.startswith("#")
}
suites, tests, failed, passed = {}, {}, set(), 0
for raw in open(results_path, encoding="utf-8", errors="replace"):
    raw = raw.strip()
    if not raw.startswith("{"):
        continue
    event = json.loads(raw)
    kind = event.get("type")
    if kind == "suite":
        suites[event["suite"]["id"]] = event["suite"].get("path") or ""
    elif kind == "testStart":
        test = event["test"]
        path = suites.get(test.get("suiteID"), "").split("qflistudio-core/")[-1]
        tests[test["id"]] = f"{path}: {test['name']}"
    elif kind == "testDone" and not event.get("hidden") and not event.get("skipped"):
        name = tests.get(event["testID"], str(event["testID"]))
        if event.get("result") == "success":
            passed += 1
        else:
            failed.add(name)
    elif kind == "error":
        failed.add(tests.get(event.get("testID"), "unknown test"))

new = sorted(failed - known)
fixed = sorted(known - failed)
print(f"passed={passed} failed={len(failed)} known={len(known)} new={len(new)}")
for name in fixed:
    print(f"::notice::known failure now passes: {name}")
for name in new:
    print(f"::error::new test failure: {name}")
sys.exit(1 if new or passed == 0 else 0)
