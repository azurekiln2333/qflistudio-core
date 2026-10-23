# Offline content metadata and import fixtures

## 1. Scope and trigger

Tutorial/example metadata crosses repository, adapter, editable saved state and
UI/import boundaries. Keep optional fields compatible with old catalogs and saves.

## 2. Signatures

`TutorialLesson` and `ExampleCode` retain `language`, `level`, `concepts` and
`inputFixtures` through parsing, adapters, copy/inheritance and serialization.
`ExampleCodeStore.bundledExample(id)` returns the bundled source for restoration.
`CodeImportService.projectFiles` materializes source and validated input fixtures.
`ToolsGridSliver(tools: List<ToolDefinition>)` exposes shared card geometry for
inline product scroll views; the caller supplies `SliverPadding`.

## 3. Contracts

The teaching `language` drives chips/badges; executable `type` is the legacy
fallback only when language is empty. A CSS or JavaScript lesson may intentionally
import as runnable HTML. Search intersects subject language, difficulty and all
query words across title/summary/concepts without reloading the repository.

Old overrides inherit missing bundled metadata. Restore-default uses bundled code
even when a detail page is reopened with the saved example as its initial model.

`inputFixtures` maps relative filenames to text; `stdin` becomes root `input.txt`.
Old aggregate lessons resolve missing fixtures by paired `sourceLessonId` once at
load time. Scratch, new-project and existing-project imports preserve the fixtures.

Go import defaults inspect the currently displayed source. Real top-level
`Test`/`Benchmark`/`Fuzz` declarations with the corresponding `testing` pointer
parameter (including `TestMain(*testing.M)`) suggest `snippet_test.go`; ordinary
programs retain `main.go`. Ignore comments, literals and receiver methods, honor
normal/grouped/aliased/dot imports, and preserve explicitly chosen names and code.

## 4. Validation and error matrix

| Condition | Behavior |
| --- | --- |
| No optional metadata in old save | Use compatible defaults/bundled metadata. |
| No filter matches | Empty/reset controls remain available. |
| Absolute/traversing/aliased fixture path, metadata or source collision | Reject before writes. |
| Unsafe linked parent or malformed/reserved path name | Reject import. |
| Any existing source/fixture target | Include all targets in replacement prompt. |
| Later existing-project write fails | Restore/delete earlier outputs only while their current bytes still match this import. |
| Another save changes an imported output before rollback | Preserve the changed bytes and report a rollback conflict with the affected paths. |
| A save or deletion completes after preflight but before replacement | Snapshot the actual target after backup and immediately before replacement; rollback restores that snapshot, not the preflight state. |

Preflight validates the entire target set without retaining stale rollback bytes.
For replacement, finish staging and backup first, recheck the physical parent and
target type, read the current bytes synchronously, then rename synchronously with
no asynchronous yield between snapshot and replacement. A target absent at this
boundary has no original bytes to restore. Preserve exclusive creation and require
explicit replacement for any file discovered after preflight.

For a new file, finish asynchronous preparation before the final physical-parent
and target-type checks, exclusive synchronous creation, and synchronous flushed
write. Do not yield between reservation and writing; a same-isolate editor save
must not see an empty reservation and then be overwritten when the import resumes.
On write failure, cleanup stays synchronous and rechecks confinement, regular-file type and
bytes. Delete only an empty reservation or the exact complete imported bytes.
Preserve divergent or unknown partial content and report a cleanup conflict;
failure is not proof that the current target still belongs to this import.

For replacements, the snapshot boundary preserves saves that complete in the same
Dart isolate before replacement. For both new and replaced outputs, conditional
recovery compares current bytes with the import's own bytes and recovers without
an asynchronous yield, preserving changed content saved before rollback. These
boundaries are not an operating-system compare-and-swap or locking protocol for
other processes. An external writer can still race filesystem operations, and
identical bytes do not identify which writer last saved them.

## 5. Good, base and bad cases

Good: a CSS subject remains CSS in chips and badges while its HTML document imports
and runs unchanged. Base: a legacy C example with no language falls back to type C.
Bad: changing runnable type to CSS merely to repair display labels.

## 6. Required tests

Run content filters, fixtures, import, lazy catalog, idle-frame and language content
render tests. Cover saved reload/default restoration, concept-only search, differing
subject/type, large text/narrow layouts, stdin fixture joins and failed-write rollback,
including real saves after preflight, after backup and after the import write,
deletion at either side of replacement, late no-overwrite conflicts and linked
parent rejection for both new and existing files. Queue a real save at new-file
reservation to prove it observes complete imported content and survives a later
rollback; inject write failure to cover safe empty cleanup and changed-target
preservation.
Materialized host files are not OHOS execution evidence.

## 7. Wrong versus correct

Wrong: use the edited detail model as the default source, drop fixture/concept fields
at an adapter, or key rollback originals with differently normalized Windows paths.
Correct: resolve bundled source, carry metadata end to end, normalize write/backup
keys identically, preflight all targets and serialize writes for each project root.
