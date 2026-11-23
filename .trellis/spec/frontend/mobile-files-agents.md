# Mobile Files and the Agents Home Tab

## 1. Scope / Trigger

Read this contract when changing external folders, incoming shared files,
Home session navigation, or project downloads from paired computers.
The implementation spans `lib/share`, `lib/sync`, `lib/harness`, the editor,
and the app repository's native receivers.

## 2. Signatures

- `HarnessSessionTarget({required String hostId, required String sessionId})`
  is the single session address. `openEditorPage(harnessSession: ...)` passes
  it to `EditorPage(initialHarnessSession: ...)`.
- `ExternalFolderService.pick()` returns `Future<ExternalFolder?>`.
  `restore()` returns `Future<List<ExternalFolder>>` and registers resolved
  roots. `adopt(ExternalFolder)` registers a root in the current process.
- `ProjectFileAccess.readBytes`, `writeBytes`, and `delete` own the dispatch
  between app files and external folders. `FileService.listSorted` dispatches
  directory listings through the same registered root ownership.
- `ShareInbox.start()` installs the `qflistudio/share_inbox` handler and calls
  `takePending`. Subsequent `incoming` messages use `ShareInboxBatch`.
- `DeviceFilePort.manifest(String root)` returns `Future<FsManifest>`.
  `read(String path, {required int offset, int? length})` returns `FsChunk`.

## 3. Contracts

### External folders

Native bookmarks stay native. Dart receives `id`, `name`, and the currently
resolved absolute `path`. A stored path may change after restoring a bookmark.
Successful project registration must also register the root with
`ExternalFolderService`, including when the project registry was empty.

The `qflistudio/platform` methods are `pickFolder`, `resolveFolders`,
`releaseFolder`, `folderList`, `coordinatedRead`, and `coordinatedWrite`.
Listings include `name`, `path`, `isDirectory`, `size`, and `downloaded`.
Native reads download iCloud placeholders before reading. Native writes use
file coordination. Do not create `.qfli` metadata inside an external folder.
Removing a project registration must preserve its external files.

### Sharing and sessions

A batch contains `id`, `files`, `coldStart`, and `source`. Each file contains
`path`, `name`, `bytes`, and optional `mimeType`. The path refers to an already
copied inbox file. Validate batch IDs before constructing deletion paths.
The intake sheet offers project import or a session attachment. Attaching
prefills the composer with `autoSend: false`. Cancellation or partial import
keeps the batch available.

Home lists session metadata and opens the existing editor Agent panel.
Studio sessions come from `agent_sessions/index.json`, not transcript scans.
Host `studio` selects the built-in session without calling `hub.openSession`.
Other hosts use the supplied host and session IDs. Session waits must release
timers and listeners when the editor closes.

Status colors are semantic: blocked orange, working green, idle gray, done
blue, exited red, and unknown an outline. Provide text semantics too.
Remote device name uses `hostName`, falling back to `host`. Recognize `os`
values `windows`, `macos`, and `linux`; missing or `other` falls back to
`platform` values `win32`, `darwin`, and `linux`. Preserve `osVersion`.
Initialize device metadata from the port's current frame in the constructor,
then update it on notifications. An absent frame remains unknown.

### Device downloads

Download only after a user action. Non-Git sync uses manifests and changed
files over the authenticated paired-computer channel. The relay stores no
project files. `kSyncChunkBytes` is 512 KiB. Stream received data to staging
while hashing. Verify size and hash before replacing a destination.
Apply deletions only after every planned download succeeds. Abort on a
truncated manifest or an ignore-table version mismatch.

Git uses a full clone through qfli_git. Prompt when reported `.git` size is
greater than `kGitConfirmBytes` (200 MiB); this is an estimate, not exact
transfer size. This task does not add shallow clone support.

A session without a local project gets a placeholder. Opening that session
does not download project files. Retain pulled files when cleaning unused
placeholders. `RemoteSessionCache` keeps at most 2 MiB and 400 events.

## 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Folder picker cancelled | Return null without reopening the picker. |
| External directory access fails | Preserve existing nodes and show a failure. |
| External delete requested | Reject it without deleting external contents. |
| Native file bytes absent | Report failure; do not fabricate empty content. |
| Shared batch only partly imported | Retain the batch for retry. |
| Device has no info frame | Show unknown fields. |
| Editor closes during a session wait | Cancel timer and listener. |
| Sync hash/size mismatch or connection failure | Preserve destination and defer deletions. |
| Manifest truncated or ignore table differs | Abort before interpreting missing entries as deletions. |

## 5. Good / Base / Bad Cases

- Good: an empty registry adds its first external folder and immediately lists
  it through the native channel, including undownloaded placeholders.
- Base: an app-local project continues using `dart:io`.
- Bad: treating an access failure as an empty folder or deleting external
  files when removing the project registration.

## 6. Tests Required

Run tests in cloud CI only. Local format and static analysis are permitted.

- `external_project_root_test.dart`, `external_explorer_menu_test.dart`, and
  `external_agent_files_test.dart`: registration, native dispatch, visible
  entries, coordinated reads/writes, and external file preservation.
- `editor_harness_session_target_test.dart` and
  `editor_harness_session_wait_test.dart`: selected host/session and disposal.
- `harness_remote_device_test.dart`: synchronous initial metadata, updates,
  missing fields, and OS fallback.
- `test/share/`: cold start, cancellation, partial imports, and composer intent.
- `test/sync/`: changed files, failed downloads, deferred deletion, cache
  bounds, placeholder cleanup, and explicit download confirmation.

Cloud tests do not validate an iOS bookmark across reinstalls or an actual
WeChat share. Record those physical-device checks separately.

## 7. Wrong vs Correct

Wrong: persist only `externalFolderId`, then rely on a previous startup
restore to have populated the in-memory root map.

Correct: registration establishes both project identity and root ownership.
Verify this with an initially empty registry and unchanged file-tree assertions.

Wrong: compare a failed CI run from an earlier SHA with today's working tree
and call the new implementation verified.

Correct: require the exact repository, workflow, commit SHA, and run result.
