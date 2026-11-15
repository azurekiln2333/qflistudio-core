# Embedded Agent interactions

## 1. Scope / Trigger

Apply this contract when changing editor Agent navigation, session loading,
transcript paging, composer controls or user-message actions.

## 2. Signatures

- `FileExplorer.sections` supplies the Sessions body and contextual actions.
  `SidebarSectionSwitch` lives in the existing card header.
- `VibeAgentRuntime.open(projectId, sessionId)` shares an in-flight open per
  session and returns one cached facade.
- `AgentMessageView.sourceText` is nullable raw user input. `attachedPaths`
  defaults to an empty list and contains actual attachment paths.
  A null source means legacy metadata is absent. An empty source means the
  user sent attachments without text; preserve it through JSON and actions.
- `ChatTranscript` receives `sessionKey`, `busy`, `onEdit` and `onResend`.
  `AgentUserMessage.of` projects typed message metadata for these actions.

## 3. Contracts

Files and Sessions share one sidebar card and header on desktop and in the
drawer. Switching replaces the body and header actions. Keep tree expansion,
search and browsing state, lazy Agent activation and offline gating. Reserve
usable project-selector width. Move file actions to a labeled overflow menu
when the header is narrow.

Opening a session reads only the message tail. Do not scan the whole file for
compaction on that path. Reverse line reading accumulates byte chunks and joins
once per line. Canonical history/header records can bypass JSON decoding during
message paging. Noncanonical JSON falls back to the real decoder. History reads
stop at the newest valid snapshot, including an empty snapshot. A malformed
latest record must not hide an older valid one. Decode large snapshots outside
the UI isolate. Remove facade listeners on destruction and reject opens for
sessions deleted during the read.

Session switches clear stale facade content before awaiting the selected
session. Keep drafts scoped to sessions. Reading earlier messages preserves the
visible reading position. New output follows the bottom only when the reader
was already there. A session change starts at that session's latest message.

Copy uses displayed text. Only settled user messages offer edit/resend. Edit
restores raw text and attachments into the composer for an explicit new send.
Confirm before replacing a nonempty draft, then replace both text and
attachments. Recheck session identity and busy state after asynchronous dialogs.
Direct resend uses the existing send pipeline and preserves an independent
draft on success and failure. Never reconstruct attachments from display text.
Old persisted records without metadata retain their displayed text and no
inferred attachments. Retry retains typed attachments.
Keep source text and attachment metadata per controller message across sends.
Projecting a later run must not erase earlier user inputs. Attachment-only sends
use the same send pipeline, retain an empty source and remain retryable.

Composer controls retain at least 44 logical pixels of touch area. The painted
send circle can be smaller. Reserve real gaps between attachment, permission,
model and send controls even when flex space collapses. Preserve disabled and
keyboard behavior and theme colors.

## 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Concurrent opens of one session | One facade, read and listener chain. |
| Delete during open | Fail the open; do not cache a resurrected facade. |
| Truncated large history record | Continue to an older valid snapshot. |
| Noncanonical whitespace/key order | Decode without losing messages/history. |
| Switch while loading | No flash of the previous conversation. |
| Busy or pending message | No edit/resend action. Copy remains available. |
| Edit with existing draft | Confirm; cancellation preserves text and attachments. |
| Direct resend fails | Preserve the independent draft and expose retry. |
| A second message is sent | Earlier messages retain their source and attachments. |
| Attachment-only message reopens | Keep empty source text and the real paths. |
| Width 320 / text scale 1.3 | No overflow or touching selector groups. |

## 5. Good / Base / Bad Cases

Good: a message with an attached file reopens with raw text and its real path,
then resends without consuming another draft. Base: legacy text-only messages
still copy and edit. Bad: parsing an attachment list out of rendered text or
rebuilding one facade for every concurrent tap.

## 6. Tests Required

Run store/runtime/facade/metadata suites, composer and composer-state suites,
transcript and pane suites, editor embedding/sidebar/topbar suites, and file
explorer/workspace regressions. Check variable-height prepend geometry,
per-session drafts, pending/busy menus and attachment replacement. Inspect
320/360/424 layouts, both themes and scale 1.3. Desktop synthetic benchmarks do
not establish device speed; label their scope and separately inspect OHOS.

## 7. Wrong vs Correct

Wrong: collect multiple large history candidates before checking the newest,
or use a fixed candidate cap that skips valid older history. Correct: decode
candidate records during reverse scanning and stop at the first valid snapshot.

Wrong: put a second Files/Sessions strip above the file card. Correct: render
the switch and context actions in the original card header.
