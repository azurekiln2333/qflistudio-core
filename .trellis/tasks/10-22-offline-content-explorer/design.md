# Design

Keep filtering at the local content page/model adapter boundary. Add optional metadata to TutorialLesson and ExampleCode; retain existing constructors/defaults and saved-example storage compatibility. Filter immutable loaded rows in UI without refetching assets. Derive supported language choices from actual loaded content and profile; normalize C++ labels. Keep lazy list construction and avoid per-row repository work.

Use one shared language badge component styled consistently with project cards. Preserve content title sizing and narrow layouts. No extra navigation, network calls or changes to product runtime interfaces.

Initial content batch landed at ef34591. C root now also adopts the existing
file_explorer/project_history modifications and owns the workspace integration.
Keep diagnostic public APIs unchanged and exclude Java-owned content changes.

## Workspace session completion

Retain the legacy main-project `openFiles`/`files`/`activeFile` history shape for
compatibility. Add optional ordered document records carrying absolute owner root,
relative file path, cursor and active flag. Queue session writes with tree/root
membership writes and preserve fields outside each update's responsibility.

EditorPage restores only its own project or other registered local owners. Resolve
relative files inside the named root; reject absolute/traversing or linked
outside-root sources, skip missing entries and duplicates. Removed workspace roots
may keep open tabs, so membership removal must not delete projects or tab history.
Preserve owner name/type when reopening and keep the original tab order/active file.
Do not persist unsaved source contents as part of view-session metadata.

Changed files: editor/project_history.dart for additive history records and queued
merges; editor/editor_page.dart for session capture/restore; editor/file_explorer.dart
for adopted owner-aware tree/actions; history, explorer and real EditorPage tests.
