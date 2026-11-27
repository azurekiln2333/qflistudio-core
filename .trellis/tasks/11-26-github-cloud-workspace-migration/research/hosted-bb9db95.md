# Green hosted checkpoint bb9db95

Exact Core `bb9db95eaf0cfbb0e41119e2e3f2091386c33d8d`, tree
`c6c13c3015cff73201b4333272b6ffa4bbc259d5`, passed the shared publication
gate at 2026-11-28 05:04:41. Per brain wave-2 item 6, this CI-only repair does
not require consumers to leave `8e031313ffc8d531c5a6b4d131f721f35da04c86`.

## Exact hosted results, attempt 1

Core-check run `46067891398` completed successfully at
`2026-11-27T21:13:11Z`. All seven jobs passed:

| Job | Evidence |
| --- | --- |
| check 140737537926 | Formatting, analysis and complete suite success |
| canonical 140737537961 | Analysis and complete suite success |
| legacy 140737537996 | Analysis and complete suite success |
| relocated 140737537845 | Analysis and complete suite success |
| screenshots 140737537515 | Screenshot job success |
| missing-app-root 140737537991 | Intentional negative boundary success |
| invalid-java-root 140737537855 | Intentional negative boundary success |

Complete suite counts were not re-extracted for this green run; the preceding
`8e03131` counts must not be relabeled as `bb9db95` counts.

Core-consumer-check run `46067891354` completed successfully at
`2026-11-27T21:06:41Z`. Both jobs passed:

| Job | Executed SDK | Executed checks |
| --- | --- | --- |
| OHOS 140737537381 | 3.41.10-ohos-1.0.1, `adaf911c35c9136a7d18fc424d714c9ec7724e60`, Dart 3.11.5 | 8 preparation unit tests; analysis without issues; 2 Flutter smoke tests |
| official 140737537765 | 3.50.1, `ae9b586f34a8443573f82ef57c3bf914a908cbf7`, Dart 3.14.0 | 8 preparation unit tests; analysis without issues; 2 Flutter smoke tests |

Both resolved re_editor and xterm to the same Core checkout's vendor trees with
no consumer xterm override. Official preparation reports changed=true and native
view preserved=false. OHOS reports changed=false and native view preserved=true.
No skipped smoke count was shown. This proves the narrow hosted compiler/API
contract, not native packaging, signing, device login or a universal SDK claim.

## Artifact metadata

All nine artifacts were unexpired at inspection; contents were not downloaded.
Names use the full exact SHA above. Core verification (`15231338973`) and
workbench screenshots (`15231706910`) expire `2027-02-25T21:04:45Z`.
The five `interop-path-{mode}-{SHA}-1` artifacts expire on 2026-12-11:
canonical `15231079474` at 21:10:42Z, legacy `15231179638` at 21:13:04Z,
relocated `15232221164` at 21:10:26Z, missing-app-root `15231028606` at
21:05:14Z, invalid-java-root `15231482689` at 21:05:16Z.
Consumer artifacts `core-consumer-official-{SHA}-1` (`15231482755`) and
`core-consumer-ohos-{SHA}-1` (`15231452841`) expire on 2026-12-11 at
21:05:38Z and 21:06:36Z respectively.

## New issue after this checkpoint

Web owner-retained exact evidence at Core `8e03131`, Web
`de9558b607a7935262beda84f2eaf754de0b1485`, App run `46069023876`, job
`140741314086`, executed Flutter prefix `244a0e8`: the sole remaining test
`320px desktop keeps workbench navigation with2x text` reports bottom44px
RenderFlex overflow at `local_content_pages.dart:1536:18`, Column, constrained
to 168x104 with parent padding offset16,16. Timestamp
`2026-11-27T21:19:58.0148867Z`; no creator chain is supplied. Full consumer
result is 310 passed, 1 failed, 6 skipped. Earlier narrow title and phone cases
passed; missing finders were repaired in Web's path fixture.

The green Core checkpoint above does not validate this newly assigned large-screen
card repair. Preserve every assertion and full text scale; a behavior change needs
a new brain-coordinated consumer wave. No local product tooling, downloads or
cleanup occurred during this observer lane.
