# Blocked-input cancellation ordering repair

Date: 2026-10-26. Scope: shared supervisor only.

## Problem and change

Lua reported global846: Windows cancellation awaited stdin close before its tree
termination command. Buffered input to a non-reading child can keep that close
pending. The production change observes stdin close immediately, dispatches the
existing tree command or direct fallback first, then awaits input settlement
before releasing cancellation ownership. POSIX retains its bounded close grace.
Public signatures and fallback selection are unchanged.

Three new fake Windows controls cover acknowledged tree termination, an
unavailable tree command and a throwing tree command. Each holds actual queued
input. Termination must start before that input settles. Natural root exit and
completed tree command cannot release ownership while input remains pending.
Existing lifecycle assertions remain intact.

## Actual verification

Fresh grant C-supervisor-input-20261026-01, global858, was accepted and launched
in one root tool invocation. Original execsession49738 returned actual terminal
exit0 through poll55c9b9. All three exact retained process identities were
terminal exit0 with Job active0 and checked handle closure. No forced cleanup,
HOLD, cleanup error or source drift occurred. Runner elapsed8.120seconds.

- Immutable format check: PASS, zero changed files.
- Scoped Flutter analysis: PASS.
- process_supervisor_test.dart: 9/9 PASS, including three new controls.

Global859 release append was79.232seconds after grant publication. Its original
publisher tool067df6 returned actual terminal0. The outer terminal and publisher
results were directly observed by root. The report records exact PID/FILETIME,
raw streams, before/after hashes and selected launcher identities.

Tested source SHA256:
095de8c17c66dc206fe170b3f99b7447d8660f183085ecb338f97484ff0e5bfc.
Test SHA256:
8da86730e70b6b8d29b00aabf76cef3962af10bcf3b88efbcd2a00e800509b78.
Runner SHA256:
7ba6c9e2945afd6c730a90c4868d32e21ae982913c4256a551403281ea996447.

## Remaining limits

These fake controls prove ordering and retained ownership while input is pending.
They do not prove actual Windows descendant identities or containment. The
legacy PID-based Boolean tree command and root-only fallback remain. Failed
cancel futures remain cached. Those retry and conservative-completion contracts
need a separate change. Lua owns its adapter and real blocked-input regression.
The historical residual conhost/bash attribution remains probable, not proven.
No native rebuild, OHOS package or installed-device execution occurred.
SDK internals and external Pub-cache bytes are outside this hash inventory.
