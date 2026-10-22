# Adopted workspace integration review — 2026-10-22

C root explicitly adopted the previously unattributed `file_explorer.dart`,
`project_history.dart` and their tests after global attribution requests found no
active writer. Other language coordinators reserve all common UI to C. Java-owned
content commit 9a1c8b9 remains separate.

## Reviewed behavior

The initial work restored expansion and persisted multiple tree roots but its
EditorPage still saved only primary-project files. Added compatible ordered
`ProjectDocumentSession` records with registered owner root, relative file path,
cursor and active flag. Preserve main-root legacy fields and merge documents with
queued tree/membership updates. Snapshot caller collections before queueing.

Real restoration verifies the current owner, skips unregistered/cloud foreign
owners, escaped/absolute/missing files and duplicates, and checks physical link
containment. Reopened files receive their owner's current name/type. Source bytes
are never stored or rewritten by view restoration. Removed tree roots may retain
their registered open tabs. Closing before initial restoration completes preserves
the previous session; tree generations discard late async restore/list responses.

Reviewed owner-aware create/delete/search/history/import paths and protected root
deletion. Added a real secondary-root create/backed-up-delete test that verifies
backup project name/original path and untouched first-root source.

Independent read-only review found four concrete issues, all repaired before
publishing: folded visible line indices now convert both cursor endpoints to
physical source lines; creating inside a collapsed folder persists its expanded
parent after restoration; backed-up deletion skips editor/UI callbacks after
disposal; physical directory aliases now share one resolved history write lane.
Regressions reconstruct the actual EditorPage/tree and create a real directory
link for concurrent editor/tree/membership writes.

## Evidence

- `build/workspace-session-regressions.log`: 21 tests passed before adding file
  actions and malformed-row coverage. Actual EditorPage reconstruction verifies
  tab order, active file, cursor positions, C++ header owner type, old history and
  invalid/stale/duplicate records.
- `build/workspace-file-actions.log`: 10 explorer tests passed, including drawer
  reconstruction, multi-root membership/expansion/removal/search, secondary-root
  file actions and 280px/2x text layout.
- `build/workspace-reviewed-regressions.log`: **27 passed**, including all four
  independent-review regressions. The actual directory-link test ran successfully
  on this host; it was not skipped.
- `build/workspace-reviewed-analysis.log`: `dart analyze lib test tool` clean.
- `build/workspace-reviewed-integration.log`: **712 passed, 2 skipped**, all tests
  passed after the review fixes, including retained-editor/run/terminal regressions
  and Java expansion. Previous708-pass report is retained.

First fixture iteration awaited real disk writes inside fake widget time and hung;
the fixture now uses `runAsync` for initial writes and pumps/drains queued history
IO when unmounting. No product workaround was introduced for the test-clock issue.

Current OHOS device acceptance remains independent. This batch changes shared
view/session behavior and does not claim compiler, debugger or phone acceptance.
