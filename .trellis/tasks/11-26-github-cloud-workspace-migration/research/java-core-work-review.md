# Java core-work authored snapshot review

Date: 2026-11-27. Planning/research only; no implementation or cleanup acceptance.

## Scope and evidence

Java w5W:p1 reported 21 authored Dart snapshots mixed with helpers and private/generated evidence under `D:/MyNewProjects/qfli_java/build/core-work`. Its source inventory is documented in `.trellis/tasks/11-26-github-cloud-migration/cleanup.md`, section `Core-work source comparison and disposition`. Java owns preservation and any later relocation. Core has not copied, moved, overwritten or deleted these files.

Four Pi in the source Herdr workspace performed disjoint text/history reviews: w63:p2 animation/editor, w63:p3 content/filters, w63:p4 dialog-cancel/restore-layout, and w63:p5 helpers/provenance. Their new sessions and model displays were verified as `gpt-6.1-sol`; review results were read through Herdr. No builds, tests, analyzers, dependency installs, helper execution, Git mutation, or WSL access was authorized or reported. The coordinator wrote this durable summary after collecting their results.

All comparisons below refer to immutable published baseline `476a30acee21dc486ee2849dd8064a7be665e4d5`, abbreviated P. Paths in the first column are relative to Java's `build/core-work`; counterpart paths omit the first group component. Static presence of a test assertion is not an executed test result. Earlier completion/handoff prose is historical provenance, not fresh validation.

Disposition vocabulary:

- **Covered candidate**: collected source/history evidence identifies corresponding behavior or assertions in P. Preserve the original as provenance; do not replay it over newer source. This is not permission to delete the mixed tree.
- **Duplicate**: matching published content is established for the reviewed file. This does not clear neighboring data.
- **Retain unresolved**: preserve the exact variant and document the missing equivalence/intent evidence. Do not treat it as disposable or as an approved new feature.

## Per-file ledger

| Snapshot | Disposition | Evidence and remaining boundary |
| --- | --- | --- |
| `animation/lib/editor/retained_editor_host.dart` | Retain unresolved | Ancestor `665febb` incorporates retained animation/session behavior. Snapshot opacity runs 0.94 to 1; P uses 0 to 1 (`lib/editor/retained_editor_host.dart:677`). Timing, reversal, retained identity, reduced motion and interaction guards remain, but intentional retirement of the shallow-fade variant was not proved. |
| `animation/test/retained_editor_animation_test.dart` | Covered candidate | P retains open/Back/resume, rapid reversal/project switching, and reduced-motion cases (`test/retained_editor_animation_test.dart:17`); published test matches `665febb` and adds zero-opacity/frame/API checks. No useful unique scenario was identified. |
| `editor/lib/app.dart` | Covered candidate | Differences from ancestor `a56dc26` were formatting only. P retains controller ownership/disposal and host integration, with later phone/workbench routing (`lib/app.dart:183`). |
| `editor/lib/editor/editor_page.dart` | Covered candidate | Differences from `a56dc26` were formatting/equivalent bracing. P retains queued opens, selection/scroll restoration, minimize and dirty-confirmed close (`lib/editor/editor_page.dart:600`, `:819`, `:5321`). |
| `editor/lib/editor/retained_editor_host.dart` | Covered candidate | Formatting variant of `a56dc26`; P retains same-project reuse, independent Navigators, minimize/close distinction, child-Back routing and restoration, with later animation/workspace support (`lib/editor/retained_editor_host.dart:184`, `:509`, `:734`). |
| `editor/lib/pages/home_page.dart` | Covered candidate | Retained opening through `openEditorPage` from `a56dc26` remains in P (`lib/pages/home_page.dart:2057`). The snapshot lacks the later shared repository cache; no useful unique behavior was identified in this variant. |
| `editor/lib/widgets/code_snippet.dart` | Covered candidate | Formatting variant of `a56dc26`; P resumes retained editing at the imported path and adds later focus/import handling (`lib/widgets/code_snippet.dart:235`). |
| `editor/test/retained_editor_test.dart` | Covered candidate | Six authored scenarios and preservation assertions remain in P (`test/retained_editor_test.dart:343`, `:733`). Later source adds messenger isolation, bounded pumping, cancellation and workbench coverage. |
| `content/lib/content/asset_content_repository.dart` | Covered candidate | P retains cached catalog loading, concurrent reads, background parsing, filtering and fallback behavior. Related history: `72dca42`, `93a45e1`; published blob prefix `d84fc48`. No useful unique behavior was identified. |
| `content/lib/pages/local_content_pages.dart` | Retain unresolved | P uses the merged content page introduced by `3df651c`; snapshot has separate tutorial/example tabs and lifecycle/reload behavior. Much browsing behavior is replaced, but complete separate-tab lifecycle/integration equivalence was not established. Snapshot/published blob prefixes: `d69578f` / `44e5df2`. |
| `content/test/asset_content_performance_test.dart` | Covered candidate | P has corresponding shared-load, parse/error, filtering/model and fallback assertions; related history `93a45e1`. Snapshot/published blob prefixes: `891c95a` / `1d737f5`. No additional useful coverage identified statically. |
| `content/test/home_content_repository_test.dart` | Retain unresolved | P tests repository sharing through the merged page rather than the snapshot's separate retained tabs. Preserve the original until the replaced lifecycle/acceptance behavior is explicitly accounted for; published blob prefix `07ca652`. |
| `content/test/local_content_lazy_catalog_test.dart` | Covered candidate; exact history exists | Snapshot blob prefix `7f47816` occurs in core history including `ef34591` and `30e920d`. P retains lazy-list/final-item coverage and adds filtering/header assertions; published blob prefix `e6769e9`. |
| `content/test/support/content_catalog_fixture.dart` | Duplicate | Reviewed snapshot and P share blob prefix `408f6bc`; history includes `93a45e1`. Java's initial newline-normalized comparison also identified this as the one current duplicate. |
| `filters/lib/pages/home_page.dart` | Retain unresolved as a whole file | Reviewed filtering area is covered in P: project scopes, offline cloud exclusion and language chips. The broader Home file was not fully compared in this lane; do not claim whole-file supersession. Published blob prefix `f332593`. |
| `filters/test/home_project_scope_test.dart` | Covered candidate | Corresponding scope/chip assertions exist in P's broader matrix; related history `ad17f35`, `854bd1a`, published blob prefix `7283831`. Tests were not executed. |
| `dialog-cancel/lib/editor/new_file_dialog.dart` | Covered candidate | P retains Java-aware suffix ordering, persistence/normalization and dialog-owned text-controller lifecycle through dismissal, represented by `89da310` / `601a176`. Snapshot blob `68aede16958f811c1a163bb74a57658ab31f668f`; P blob `3d3ac8f3a52078befa5de9e9f63c5e871ccb190e`. |
| `dialog-cancel/test/new_file_dialog_test.dart` | Covered candidate | P retains cancel-exit pumping, navigator liveness, normalization, nested custom-suffix cancel/add and no-error assertions; history `89da310`. Snapshot blob `979903fee15eeb0b78e685389432899e3c8a3121`; P blob `455f9d9b34ddbdd531eb201089d5d1c25f6c5f47`. |
| `dialog-cancel/test/retained_editor_test.dart` | Covered candidate | P retains the Explorer new-file cancellation case preserving the live editor and dirty buffer, with repeated cancellation/no-file assertions and broader coverage. Snapshot blob `f560750c2314519b7773fda05980998ee473a333`; P blob `2f2fe3377282baa56993e0cebf6594fbb0cffd90`. |
| `restore-layout/lib/editor/retained_editor_host.dart` | Retain unresolved | Restore/session/menu behavior is represented in P and `7768b91`, but whole-file animation equivalence is unproved. Collected snapshot uses 0-to-1 fade, easeOutCubic, 180 ms forward/140 ms reverse; the animation group's 0.94 floor was not observed here. Collected published excerpts do not prove all curve/duration/slide details match. P additionally extracts the restore control and changes keyboard/popup handling. Snapshot blob `dea5cc7fc572e66b1bd169a02ca3dfb97576157f`. |
| `restore-layout/test/retained_editor_test.dart` | Covered candidate for reviewed restore assertions | P contains narrow-screen safe-rect, FAB-overlap, long-name selector and same-controller restoration assertions associated with `7768b91`. Exact staging-variant lineage, complete coverage equivalence and visual-animation parity remain unproved. No runtime/layout verification was performed by this audit. |

Most reviewed variants have no byte-identical match established in the bounded locally reachable history scan. That is not proof they never appeared in any history. Semantic inclusion and exact-blob provenance are separate claims; no count of differing files is used as a count of missing features.

## Helpers and surrounding provenance

| Source | Disposition |
| --- | --- |
| `apply_editor.py` | Retain as non-executed integration provenance. The Home routing glue is present in `a56dc26` and P (`home_page.dart:2123`); copied payloads are addressed by the editor rows above. Never replay against the current shared root: copies occur before helper assertions and can partially overwrite newer files. |
| `apply_home_content_cache.py` | Its lazy shared-repository/factory behavior is incorporated by `93a45e1` and remains at `home_page.dart:80`; `3df651c` later merged tutorial/example pages. Retain source provenance; no pending patch is inferred from its old two-tab recipe. |
| `fix_editor_tests.py` | Its messenger-isolation and bounded-pump effects are present in P (`test/retained_editor_test.dart:580`, `:923`) and `a56dc26`. Retain as provenance; no additional useful test coverage identified. |
| Group `handoff.md`, ownership/completion/research notes | Preserve authored rationale. Integration-related ancestors include `a56dc26`, `93a45e1`, `665febb`, `ad17f35`, `89da310`, and `7768b91`. Their existence does not prove every snapshot variant or old acceptance claim is satisfied. |
| `floating-about/commit-{about,floating,backup,anchor-fix}.txt` | Normalized full text matches commit messages for `84f68a7`, `40d9251`, `104dc5f`, `0d479b4`, all ancestors of P. Duplicate commit-message provenance, not missing implementation. |
| Remaining plans/prompts/ready/deployment material, screenshots/logs | Keep under Java's private preservation control. Do not publish verbatim or execute historical instructions. Raw captures and deployment-report bodies were not reviewed in this lane. |

No byte-identical helper blob was established in the inspected reachable history. Effects/provenance are assessed separately from exact helper storage. No broad archive-only or deletion clearance applies to the complete mixed directory.

## Commit identities

Coordinator resolved each revision below to a full commit and confirmed it is an ancestor of P with read-only Git operations. This validates the cited history relationship, not the runtime behavior of every snapshot.

| Short | Full commit |
| --- | --- |
| a56dc26 | a56dc26cdf492c75b6a9a426e87827a9e696a545 |
| 665febb | 665febbdd685eefe63abf1e7bd3f9a9fab03b0d6 |
| 72dca42 | 72dca4242a63d8cc380c679f0fd05e08d2a7fbec |
| 93a45e1 | 93a45e1e7ccbf8e0a81d2c50eccabeb737baeb59 |
| 3df651c | 3df651c20c98898b30bde408030bd722ab7dc981 |
| ef34591 | ef345913c4303cacaa568659a66ed74d666639b5 |
| 30e920d | 30e920df128a78a9d17ee3360bed8bab4f08cc30 |
| ad17f35 | ad17f35ac728e19670de1df305bc3e55c3b5172c |
| 854bd1a | 854bd1a13ba9a62342581feea1ab4c88e4aa10bb |
| 89da310 | 89da310050a70b8e651f3a4ae3b82a113b5a4242 |
| 601a176 | 601a176cc6ead3384de9e15de90c34f576f62e58 |
| 7768b91 | 7768b91a3ea3591fc9d0b333cb177d08025277e7 |
| 84f68a7 | 84f68a7dbcc2b97db04a790e25d7390ed51ee6ff |
| 40d9251 | 40d92517c2411d6f2215a904ebb299281b4802cd |
| 104dc5f | 104dc5f07a0a8527d47f2e3c1fb4c33c325e1811 |
| 0d479b4 | 0d479b4954184f84afd3ca682a4e0d295d2fb138 |

## Acceptance boundary

Core accepts this ledger as bounded preservation research: 15 files are covered candidates for the reviewed behavior, one fixture is a duplicate, and five whole-file/behavior dispositions remain unresolved. Covered candidates still require preservation of original provenance and do not imply every byte or runtime outcome was verified. The restore-layout whole-file classification was deliberately narrowed after cross-review. All four assigned Pi reviewed their own summary rows against collected evidence; no remaining report correction was identified. A transient socket error during p4's report review recovered on the same model.

This ledger does not authorize Java or core deletion, replay old code, publish private material, certify source/target parity, or claim a final migration SHA. Exact original variants remain in Java's ownership until its verified backup and disposition record are complete. Unresolved UI choices belong in subsequent task planning rather than being silently enabled as migration fixes. The current session remains restricted to planning by its active workflow instruction despite recorded user approval.
