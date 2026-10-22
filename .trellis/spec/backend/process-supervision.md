# Managed process cancellation

## Scope

`lib/services/process_supervisor.dart` owns processes created through
`ProcessSupervisor.start`. Preserve registration before asynchronous startup,
idempotent cancellation/shutdown, actual exit status and draining both output
streams. No command-name matching, global kill commands or negative process-group
IDs may be used for descendant cleanup.

## POSIX escalation and completion

Close stdin with a bounded wait, send TERM, and allow 500 ms of graceful exit.
Escalate surviving owned processes to KILL, then bound the actual exit and stream
drain waits to two seconds each. A timeout throws; it must not declare the live
process cleaned up or unregister it. The background observer continues until the
actual owned processes and pipes finish. Kernel uninterruptible waits cannot be
turned into successful cancellation by a timer.

Keep stdout/stderr subscriptions active during cancellation. After actual exit,
drain both streams before cleanup and completing the managed exit future. TERM
traps and waiting shells may emit their last text during this interval.

## Platform capability boundary

| Platform | Actual cancellation behavior |
| --- | --- |
| Windows | Existing `taskkill /PID <owned pid> /T /F`, with the existing direct process-handle fallback. |
| Linux with libc `pidfd_open` / `pidfd_send_signal`, kernel support and readable procfs | Verified, identity-pinned descendants plus parent; TERM then KILL. |
| Other POSIX, older Linux libc/kernel, inaccessible procfs | Bounded parent-handle TERM/KILL only; no descendant-tree guarantee. |
| Injected process starter | Parent handle only, so fake/foreign numeric PIDs never become native descendant targets. |

Keep `dart:ffi` in `process_identity_ffi.dart`, selected through a
`dart.library.ffi` conditional import. `process_identity_stub.dart` exposes the
same optional handle API without importing FFI, preserving the supervisor's Web
compile compatibility. This does not add browser process execution support.
Native loading is Linux-only; opening the handle and a signal-zero capability
probe must both succeed. Close handles idempotently and reject sends after close.
Never substitute numeric-PID signalling when a handle is unavailable.

Linux acquires a pidfd for the actual root immediately after startup. Before
signalling a descendant, verify its physical parent relation in procfs and its
start-time identity before/after acquiring its pidfd. Signals use only that pidfd,
never a bare descendant PID. PID reuse after acquisition cannot retarget a signal.

Freeze owned parent thread groups with STOP while enumerating every task's
children list; a fork may originate from a thread other than the main thread.
Resume every process stopped by inspection in `finally`, including error paths.
Retain acquired descendant identities across reparenting, allow waiting parents to
reap children, and close all pidfds on cleanup. Bound tree discovery to 512 owned
processes and each STOP acknowledgement to 200 ms. A live child whose identity
cannot be acquired fails cancellation rather than silently claiming full cleanup.

This is not a sandbox or containment for intentionally detached daemons. A child
that already left the observed ancestry before inspection is not safely
identifiable. Do not compensate by scanning command names or signalling an
unowned process group. Natural parent exit still waits for inherited stdio to
close; cancellation times out honestly if an unowned writer retains those pipes.

## Verification

Run `flutter test --no-pub test/process_supervisor_test.dart` for registration,
idempotency, ignored TERM escalation, output delivery and both Windows tree/fallback
branches. Run `tool/verify_process_supervisor.dart` with a native Linux Dart SDK for
real TERM-ignoring shells, `sleep 60 & wait`, a TERM-ignoring descendant and final
stdout/stderr emitted by TERM traps. The script asserts disappearance of the
actual child's procfs entry and survival of a separate sibling process. A parent
exit alone does not pass. Other hosts explicitly skip the Linux descendant checks.

No OHOS/device support may be inferred from these host checks. Device acceptance
requires its own process capability and lifecycle evidence.

Verified on 2026-10-23: 48 focused Flutter tests passed, scoped analysis reported
no issues, baseline and final standalone JS consumers both compiled, and all four
real Linux checks passed. Actual output is saved in the core repository's
`build/process-supervisor-{tests,analyze,js-before,js-after,linux}.log`; the task
research records exact commands, environment and results.
