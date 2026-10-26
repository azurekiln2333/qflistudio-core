# Attached terminal output failure repair

The shared terminal can leave running=true after a stdout/stderr error skips normal completion. This blocks Run and Debug even after actual exit. Preserve the umbrella scope and existing single-writer ownership.

Implement one attachment identity, register exit observation immediately, retain the first stream/observer error, wait for real exit before finalizing, and retain failed cleanup for Stop retries. Observe failing futures in void process adapters. An exceptional exit future alone must remain unproven and blocked; no fabricated exit status.

Validation planned: eleven in-memory regression scenarios plus the full existing terminal_pane_test.dart suite and scoped analysis. Source-only candidate was reviewed before applying. No compiler, native build or device claim. Candidate source SHA1f069305e368f9eaa419b56924c092bce9d5d6b1403dff5cc1d03ef589cfbf64 and tests429ddecaea06153f733baa38772fa1dc036695288a74c93f0775c3a905ee3f4e.

## Verified checkpoint

Fresh window C-terminal-errors-20261026-10 (global797, final801) passed format, scoped analysis and all47 terminal widget tests (36 existing and11 new). Original outer69439 exited0. All exact child Jobs were terminal, active0 and closed. Runner15.570 seconds does not establish the full publication budget: grant797 to release801 was370.202 seconds, exceeding110. This is a scoped code/test success and a publication-budget failure.

Tested source SHA256:7bf7d36524eb4db8b4d57d10aace5227446769f95622879af80ac7216d6beffd. Tested file SHA256:295e39012868cc7e3a593e7c3288f6849cded9e264d54332727a9724867ce100.

Early attempts are retained in the C umbrella research/terminal-recovery-20261026 directory. One compiler OOM and multiple fixture hangs were failures, not acceptance. Controllers closed after subscription cancellation may return a root-zone singleton completion future. Capture controller.done while the fixture is created, before injecting errors, and pump before observing completion. This resolved the fixture hang while retaining lifecycle assertions.

The repair does not invent process-exit proof. Exceptional exit futures remain blocked/unproven. Failed cleanup retains Stop retry ownership. Production API signatures are unchanged. Host widget tests do not prove current OHOS package/device or all-product acceptance.
