# Project transfer and main-page headers

## 1. Scope / Trigger

Read when changing Home project import/export, its search field, or the main
tools/tutorial/examples/profile page headers. These features belong to core;
language applications consume the same implementation.

## 2. Signatures

- `ProjectZipService.exportToFile(Project project, String destination)` writes a
  ZIP file; `exportProject(Project project)` returns bytes for document providers.
- `ProjectStore.importProjectArchive(Uint8List bytes)` returns `ProjectResult`
  after extraction, metadata preparation and registry persistence.
- `PickerService.pickDocument(extensions: ['qsz'])`, `saveDocument`, `readUri`
  and `writeUri` preserve provider URIs as opaque strings.
- Android registers `com.azurekiln.qfli.core.QfliPickerPlugin` through core's
  `pubspec.yaml`; consuming applications run `flutter pub get` to discover it.
  OHOS uses its existing host `qflistudio/platform` bridge.

## 3. Contracts

- `.qsz` is a normal ZIP containing one project's relative directory contents,
  including binary, hidden files and empty directories. Keep `.git` and `build`.
  Preserve `.qfli/project.json`; generate portable display metadata in the archive
  only if it is absent. Do not mutate the source project while exporting.
- `.qfliz` remains the separate whole-application backup format with root
  `app_info.json`. Do not route project import into application restore.
- Compression, ZIP validation/extraction and imported metadata scanning run in
  isolates. Local export streams to a staged file; URI export transfers bytes.
  Directory availability checks for card actions are asynchronous.
- Import creates an independent private `import_*` directory and a new local
  project identity. Preserve display name, language, type and relative entry
  file; remove old machine paths and cloud identity. Only publish success after
  registry persistence; clean up this import's directory on failure.
- Validate raw ZIP members before extraction: reject traversal/absolute paths,
  duplicate and case-conflicting paths, file/directory conflicts, unsupported
  links/special files, encryption and corrupt data. Check extracted size and CRC.
  Export rejects links explicitly instead of following or silently omitting them.
- Card export is available for existing local directories. Home's top-right menu
  imports `.qsz`, then selects All and clears filters so the result is visible.
  Serialize operations per Home state; cancellation is silent and post-await UI
  work checks `mounted`.
- If adding `.qsz` changes a selected local output path, reject an already
  existing final destination: the picker did not confirm overwriting that file.
- Android SAF uses an attached Activity, returns null on cancellation, retains
  its pending picker through configuration changes, and reads/writes binary URI
  content on an executor. Custom archive extensions use `application/octet-stream`
  on save and an unrestricted MIME picker on open; archive UI validates suffixes.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| Repeated import of the same archive | Separate directories and local IDs; existing data preserved. |
| Invalid ZIP/path/CRC/entry configuration | Error and cleanup; registry unchanged. |
| Registry write failure | Remove only this import's new directory. |
| Cancelled picker or disposed page | No new archive work or disposed-context UI. |
| Auto-appended output name already exists | Error; existing bytes preserved. |

## 5. Main-page Presentation

Main headers use `textTheme.titleLarge` with `colorScheme.primary`, matching
Home's product title in either theme. Profile has its own localized title.
Only the tutorial branch of the online tutorial/discussion page changes style.
Home search uses start alignment, centered vertical alignment and explicit
padding; its toolbar grows with the scaled text line instead of clipping it.

## 6. Required Verification

Run `project_zip_test.dart`, `home_search_archive_test.dart` and the existing
Home scope/navigation, tools, content and Settings navigation tests. Verify
binary/hidden/empty-directory round trips, no overwrite, failed persistence,
invalid members, URI/path flows, cancellation and narrow large-text search.
Compile the Android plugin through a consuming app's
`:qfli_studio_core:compileDebugJavaWithJavac` task. Widget mocks and compilation
do not establish real provider UI behavior; executable/link behavior also needs
Unix validation because Windows skips the real-link fixture.

## 7. Wrong vs Correct

Wrong: rename the old JSON export to `.qsz`, decompress on the UI isolate, or
restore files into an existing project's directory.

Correct: export real ZIP members, validate/extract in an isolate, register a new
local project, and keep whole-application restore independent.
