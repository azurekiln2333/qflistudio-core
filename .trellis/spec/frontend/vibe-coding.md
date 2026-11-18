# Vibe Coding editor sessions

## 1. Scope and trigger

Use this contract when changing `lib/vibe_coding/`, the AI methods in
`lib/services/api_client.dart`, or the editor's Vibe Coding integration.
`VibeCodingController` owns the model/tool loop. `VibeProjectFiles` owns local
file access. `EditorGuardedProjectFiles`, `VibeSendCoordinator` and `EditorPage`
connect that loop to live buffers, project ownership and execution availability.
`VibeCodingPanel` and its widgets render the controller's actual state.

The main product offers Vibe Coding by default. A language product must set
`StudioProfile.vibeCoding: true`; its default is false. `offlineOnly: true`
always disables the entry. Keep the request boundary in
[Offline API request policy](../backend/offline-network-policy.md), and preserve
the owner rules in [Offline Workspace](offline-workspace.md).

Local tools create and edit real project files. Commands run through the
authenticated isolated terminal service. Assistant prose is never evidence that
a program ran. Live upstream, isolated Linux execution and packaged-device
acceptance require separate observed evidence.

## 2. Signatures

```dart
VibeCodingController({
  required ApiClient api,
  required String? Function() tokenProvider,
  required String projectRoot,
  required String projectName,
  required String language,
  bool Function()? onlineAllowed,
  void Function(String relativePath)? onFileChanged,
  void Function(String? relativePath)? onFileRemoved,
  void Function(String message)? onNotice,
  VibeProjectFiles? files,
  int maxRounds = kVibeMaxRounds,
})

void send(String text);
Future<void> cancel();
void dispose();

VibeProjectFiles({
  required String projectRoot,
  int maxReadBytes = 256 * 1024,
  int maxWriteBytes = 256 * 1024,
  int maxListEntries = 400,
  bool Function(String absolutePath)? shouldWrite,
})

Future<String> read(String path);
Future<VibeWriteResult> write(String path, String content,
    {bool createOnly = false});
Future<VibeWriteResult> edit(String path, String oldText, String newText,
    {bool replaceAll = false});
Future<List<Map<String, Object?>>> list({String? path, bool recursive = false});

Future<AiChatResult> ApiClient.aiChat({
  required String token,
  required List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>>? tools,
  Future<void>? abortTrigger,
});
Stream<TerminalEvent> ApiClient.terminalEvents(String token, String command,
    {List<Map<String, String>>? files, Future<void>? abortTrigger});
Future<void> ApiClient.resetTerminal(String token);
```

`VibeSendCoordinator.submit` requires `buffers`, `save`, `stillOwner`,
`hasActiveExecution`, `send` and `text`. It returns `Future<VibeSendResult>`.
`preparing` becomes true synchronously during accepted preparation. A successful
result has `sent == true`; an aborted result carries a user-readable `message`.

`EditorController.reloadFromDisk(OpenFile open)` returns `Future<String?>`.
Null means success or a stale/disposed target that needs no UI update.
`VibeCodingPanel.onSend` is `Future<bool> Function(String text)`; false retains
the input. `onInputFocusChanged` lets the editor keep the prompt mounted when
the software keyboard reduces panel height.

## 3. Contracts

### Model and tool protocol

`POST /api/ai/chat` uses bearer authentication and body `{messages, tools?}`.
The response is `{model, message, usage?}`. `message.role` is `assistant`, with
string/null `content` and optional OpenAI-compatible `tool_calls`. Preserve each
assistant tool-call message and append a `tool` message for every call ID.
Validate call structure before inserting it into history. Tool failures become
tool feedback so the model can inspect the real error, fix code and rerun.

The backend owns `QFLI_AI_BASE_URL`, `QFLI_AI_API_KEY` and `QFLI_AI_MODEL`
(default `deepseek-v4.1-flash`). Flutter sends neither an upstream key nor a model
override. Read `tokenProvider` at send, every model round and every command.
The AI request timeout is 90 seconds. The default loop limit is eight rounds.
Tool feedback retains a bounded 32 Ki UTF-16 character tail.

| Tool | Arguments and behavior |
| --- | --- |
| `list_files` | `{path?, recursive?}`; one level by default, at most 400 entries. |
| `read_file` | `{path}`; strict UTF-8, at most 256 KiB, tracks the decoded text. |
| `write_file` | `{path, content, createOnly?}`; creates parent directories, at most 256 KiB of UTF-8 output. |
| `edit_file` | `{path, oldText, newText, replaceAll?}`; exact replacement, requires a unique match unless `replaceAll` is true. |
| `run_command` | `{command}`; nonempty command, at most 2,000 characters, fresh isolated-terminal snapshot. |

There is no delete tool. `notifyFileRemoved` only forwards an editor-side notice.
`onFileChanged` fires after a successful local write/edit with a forward-slash
path relative to the captured project root.

### File identity, backups and commit protection

Reject absolute paths, drive prefixes, NUL, empty/dot/parent segments, and a
protected first segment `.qfli` or `.git` without case sensitivity. Reject linked
components beneath the root and physical escapes. A root alias itself is valid.
Listing and snapshots skip hidden entries, links, and dependency/build folders.
Reject NUL-containing and malformed UTF-8 files instead of decoding loosely and
writing damaged bytes back.

An existing file must have been read in the same `VibeProjectFiles` session.
Compare disk text with that session's known text before overwrite. Serialize
writes across instances using the resolved real root plus the relative path;
normalize Windows key case. Resolve the key before enqueueing, and repeat path
and link validation after dequeue. Root aliases must share the same write lane.

Before overwrite, copy the current file into
`.qfli/vibe-backups/<timestamp>-<flattened-path>` and write a JSON sidecar with
`path` and `time`. Validate the backup directory's links and physical location
before and after creation. A failed backup aborts the overwrite. Re-read disk
text after the awaited backup and reject a changed version.

Run `shouldWrite(absolutePath)` inside the write lane after backup and version
checks, immediately before writing. False produces a `conflict` without changing
the source. `EditorGuardedProjectFiles` supplies this hook and an eager dirty
check. `edit` delegates its result through `write` and the same commit hook.
`createOnly` uses exclusive creation, checks the hook before creating a file, and
must yield one success and one `exists` error for concurrent creators.

### Fresh execution and truthful state

For every `run_command`, collect a new `VibeProjectSnapshot`: at most 64 files
and 256 KiB total decoded bytes. Send `{path, content}` rows where `content` is
base64. The terminal request is `POST /api/terminal/exec/stream` with
`{command, files}` and an `application/x-ndjson` response. Never run this command
on the business host. Snapshot execution does not synchronize generated remote
files back into the local project.

Consume real `progress`, `stdout`, `stderr` and `result` events. Retain a 24 Ki
UTF-16 character tail per output stream. A real nonzero exit code is an error.
A closed stream without a result is an error. Show actual output and send it
back to the model; preserve failure evidence through the fix/rerun loop.

`VibePhase` is `idle`, `running`, `cancelling`, `succeeded`, `failed` or
`cancelled`. `VibeToolStatus` is `running`, `ok`, `error` or `conflict`. Expose an
unmodifiable chronological `messages` list. A tool remains pending until its
operation returns. Mark it `ok` only after success. Session `succeeded` means the
model completed its turn; it does not replace each tool's actual result.

### Owner, busy, product and offline boundaries

Capture the active file's owning project root, falling back to the page's primary
project. Freeze that controller/root while preparing or running a prompt. Save
only that owner's non-orphaned dirty buffers. Pass a live ownership predicate to
`saveFile`. Recheck ownership after each save and before handoff. Abort on save
failure, remaining dirty text or lost ownership.

`_vibeBusy` includes preparation, `running` and `cancelling`. Run, file tools,
debugger work and aggregate terminal work own the competing execution lane.
Check that lane before preparation and again after saves, immediately before
`send`. Run, Debug and terminal dispatch must also respect Vibe's busy state.
Hiding the panel does not release the controller or its running work.

Bind file-change callbacks to the controller's captured root. Refresh the
explorer and reload only an already-open clean buffer. `reloadFromDisk` waits
for `pendingSave`, captures the buffer revision, and rechecks dirty state and
revision after IO. An edit followed by a save can be clean again; its changed
revision must still prevent stale reload. Preserve cursor selection when text
does not change.

The editor gates entry and `onlineAllowed` with the product rule in section 1.
The panel shows a login gate when signed out. The controller also rejects a
missing token or a false `onlineAllowed` without backend calls. `ApiClient`
enforces `offlineOnly` again at `_send` and at terminal-stream subscription,
before preparing requests. Use `ApiException` with `OFFLINE_ONLY` and no HTTP
status for that policy denial. UI visibility alone is insufficient enforcement.

### Cancellation and lifecycle

`canSend` is false through `running` and `cancelling`. `cancel` sets
`cancelling`, completes the abort trigger used by both AI and terminal
`http.AbortableRequest`s, cancels the stream subscription and settles the pending
command. Discard late model replies. Finalize pending tool cards and add a
cancelled `tool` reply for every unanswered call ID before accepting another turn.

After the loop stops, await terminal reset (`DELETE /api/terminal/session`) if a
terminal command was started. Keep `cancelling` until that reset attempt settles,
then publish `cancelled`. This prevents a delayed reset from cancelling the next
task. Reset is best effort and catches `ApiException`; `cancelled` alone is not
proof of remote resource reclamation. `dispose` aborts current work and suppresses
later notifications. A send after disposal performs no request.

## 4. Validation and error matrix

| Condition | Observable result |
| --- | --- |
| Absolute/traversing/protected/linked path | Tool error; no source write. |
| Existing source was never read | `not_read`; ask the model to read first. |
| Disk changes after read or during backup | `conflict`; preserve the changed source. |
| Dirty buffer at entry or commit hook | `conflict`; retain the buffer and disk source. |
| Invalid UTF-8 or NUL bytes | `binary`; no loose decoding or overwrite. |
| Missing or multiple exact edit matches | `no_match` or `ambiguous`; no edit. |
| Failed or escaped backup | `backup`; no overwrite. |
| Concurrent exclusive creation | One success; the other returns `exists`. |
| Read/write/list/snapshot limit exceeded | `too_large`; no claimed execution. |
| Signed out or product gate denies send | Failed phase with useful error; zero backend calls. |
| Request starts in an offline-only profile | `ApiException(OFFLINE_ONLY)`, null status; zero transport sends. |
| Save fails, owner changes or execution starts during preparation | Abort prompt, retain input, release preparation in `finally`. |
| Malformed tool arguments | Tool error fed back to the model. |
| Nonzero terminal exit or missing terminal result | Tool error with actual output; never fabricate exit zero. |
| Eight rounds exhausted | Failed phase stating the round limit. |
| Cancel while tools are pending | Finalize pending cards and protocol replies; block send through reset. |
| Reload sees changed dirty state or revision | Preserve current buffer text and report the refusal. |

## 5. Good, base and bad cases

Good: a secondary-root Python project fails in the real terminal, the model reads
the actual traceback, edits a previously read source, creates a result file and
reruns a fresh snapshot successfully. The UI keeps both real exit codes and the
source backup.

Base: the main product opens the panel, saves the selected owner's dirty files,
sends one authenticated prompt and refreshes a clean edited tab.

Bad: a tab switch redirects an awaited save or refresh, two root aliases bypass
the write lane, a dirty buffer is overwritten after an eager-only check, or a
late reset kills a newly accepted prompt. Offline products must never expose an
online fallback.

## 6. Tests required

| Test file | Required assertion points |
| --- | --- |
| `test/vibe_coding_tools_test.dart` | Path and link rejection, metadata case, strict UTF-8/binary rejection, read-before-write, backups, disk conflicts, two-instance write serialization, atomic create, commit hook, alias-root listing/lane, backup-directory escape and snapshot bounds. |
| `test/vibe_coding_controller_test.dart` | Preserved tool protocol, failure/error/fix/rerun feedback, guard conflicts, token/offline checks, round limit, malformed arguments, cancellation, pending-card completion, delayed reset blocking resend, valid history after resume, disposed send and output tails. |
| `test/vibe_editor_bridge_test.dart` | Dirty refusal, clean/new writes, external disk conflict and an eager-clean/commit-dirty transition. |
| `test/vibe_send_coordinator_test.dart` | Busy-before-send, duplicate preparation, execution starting during save, save failure, ownership loss, remaining dirty text and owner-scoped successful save/handoff. |
| `test/editor_reload_from_disk_test.dart` | Clean reload, dirty-buffer retention and unchanged-text cursor preservation; retain revision protection across asynchronous reloads. |
| `test/vibe_coding_panel_test.dart` | Real output and exit display, conflict labels, login gate, retained input after refused send, collapse, focus reporting and narrow/short viewport layout. |
| `test/api_client_offline_test.dart` | Zero transport sends and zero sentinel requests for offline entrypoints; retain the online positive controls. |

Run the focused suites and affected analyzer checks in the shared validation
slot. Recheck main-product availability, explicit language-product opt-in,
offline-only exclusion and editor Run/Debug/terminal regressions when changing
those host integrations. A filesystem-link test may return early when the host
cannot create links; record whether that branch actually ran.

Live acceptance was observed on 2026-10-28: the opt-in
`test/vibe_live_integration_test.dart` passed in 51 seconds against the loopback
relay fixture selected by `QFLI_VIBE_LIVE_ORIGIN`. The recorded
`deepseek-v4.1-flash` run first exited 1 with `AssertionError`, read and edited
`math_ops.py`, retained a real source backup, and created `result.txt` containing
exactly the three bytes `42\n`. Its final command exited 0 and printed
`QFLI_VIBE_VERIFIED_42`. The evidence is in `build/vibe-live/evidence.json`.

The fixture gives explicit JSON newline-content instructions. Keep its exact
local content assertion and Python byte assertion. Its completion observer must
first see a running phase before accepting a terminal phase; `send` can notify
listeners while appending the user message before it sets `running`.

This observed run covers live upstream calls, real project writes and command
execution. Production deployment, Linux isolation guarantees and packaged-device
acceptance still require separate observed evidence. Keep these results distinct
from the fake-transport suites.

## 7. Wrong vs correct

Wrong: check dirty state once, then enter awaited backup/write work without a
commit guard.

```dart
if (!hasUnsavedEdits(absolutePath)) {
  await files.write(relativePath, replacement);
}
```

Correct: install the editor guard on the shared file object. Its eager check and
base-class commit hook both participate in every write/edit.

```dart
final files = EditorGuardedProjectFiles(
  projectRoot: ownerRoot,
  hasUnsavedEdits: hasUnsavedEdits,
);
```

Wrong: publish `cancelled` while a background terminal reset is still pending.
Correct: retain `cancelling`, finish the model/tool loop and await reset before
re-enabling send. Preserve a matching tool response for every cancelled call ID.
