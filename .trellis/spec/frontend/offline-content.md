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

## 4. Validation and error matrix

| Condition | Behavior |
| --- | --- |
| No optional metadata in old save | Use compatible defaults/bundled metadata. |
| No filter matches | Empty/reset controls remain available. |
| Absolute/traversing/aliased fixture path, metadata or source collision | Reject before writes. |
| Unsafe linked parent or malformed/reserved path name | Reject import. |
| Any existing source/fixture target | Include all targets in replacement prompt. |
| Later existing-project write fails | Restore earlier original bytes/delete newly created files. |

## 5. Good, base and bad cases

Good: a CSS subject remains CSS in chips and badges while its HTML document imports
and runs unchanged. Base: a legacy C example with no language falls back to type C.
Bad: changing runnable type to CSS merely to repair display labels.

## 6. Required tests

Run content filters, fixtures, import, lazy catalog, idle-frame and language content
render tests. Cover saved reload/default restoration, concept-only search, differing
subject/type, large text/narrow layouts, stdin fixture joins and failed-write rollback.
Materialized host files are not OHOS execution evidence.

## 7. Wrong versus correct

Wrong: use the edited detail model as the default source, drop fixture/concept fields
at an adapter, or key rollback originals with differently normalized Windows paths.
Correct: resolve bundled source, carry metadata end to end, normalize write/backup
keys identically, preflight all targets and serialize writes for each project root.
