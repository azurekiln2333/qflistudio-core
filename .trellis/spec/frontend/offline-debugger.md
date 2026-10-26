# Offline debugger contract

## 1. Scope and trigger

`lib/services/debug_session.dart` is the public shared contract, re-exported by
`studio_profile.dart`. `StudioProfile.debugger` is optional. A product supplies
`StudioDebugger.displayName`, `capabilities`, `supportsLanguage(language)` and
`launch(DebugLaunchRequest)`. Only an explicit Debug action launches user code.
Missing providers or missing native libraries are unavailable; ordinary Run and
analysis are never debugger fallbacks. No expression evaluation API is provided.

This contract alone does not implement editor controls, adapters or device
acceptance. Each is a separate integration gate.

The shared editor integration uses `EditorDebugController` for one session lane,
`EditorDebugPanel` for capability-gated commands and read-only inspection, and a
painted `EditorDebugGutter` for physical-line breakpoints and execution position.
Only explicit Debug launches the provider; missing providers keep the action
unavailable. Product adapters and packaged-device acceptance remain separate.

## 2. Requests and source identity

A launch request carries `projectPath`, `entryFilePath`, `language`, immutable
`documents`, immutable `breakpoints` and `stopOnEntry`. Documents reuse
`CodeDocumentSnapshot(path, text, revision)` and retain exact UTF-16 text and line
endings. Providers validate all paths before execution, resolve filesystem aliases
and enforce containment within the one physical project root, including symlinks.
Reject missing, foreign, duplicate or unsupported inputs with a useful error.

`supportsDocumentSnapshots` means the provider can use every captured unsaved
document without overwriting project sources. Otherwise reject nonempty documents;
the editor may save first and pass an empty list. Never silently execute stale disk
text. Source preparation, imports and runtime exclusivity remain product-owned.

`DebugBreakpoint(filePath, line)` uses a canonical absolute project-local source
path and a one-based physical source line. `DebugSourceLocation` adds an optional
one-based column; null means the backend only knows the line. Convert native
relative or virtual paths inside the adapter. A frame without navigable project
source has a null location rather than a fabricated project path.

## 3. Capability gates and breakpoints

`DebugCapabilities` independently declares pause, step into/over/out, unsaved
document snapshots, stop on entry, stack frames and variables. A provider must
reject unsupported requests even if a caller bypasses the UI. Variable support
requires stack-frame support. Stop and real cleanup are mandatory.

| Capability | Meaning |
| --- | --- |
| `breakpointUpdate.launchOnly` | Launch accepts breakpoints; later replacement is unsupported. |
| `breakpointUpdate.paused` | Replacement is allowed only while paused. |
| `breakpointUpdate.live` | Replacement is allowed while running or paused. |
| `outputDelivery.live` | Actual output can be observed during execution. |
| `outputDelivery.pauseOrExit` | Actual output is observable when execution pauses or ends. |
| `outputDelivery.exitOnly` | Output is available only after execution returns. |

`setBreakpoints` atomically replaces the complete set, returns one
`DebugBreakpointResult` per request and publishes those results in the snapshot.
`pending` means accepted without executable-line verification. `verified` requires
an actual backend-confirmed `actualLocation`. `rejected` requires a useful reason.
Never mark a line verified merely because path/line validation succeeded, relocate
it by guessing or report a partial replacement as atomic success.

## 4. Full snapshots, threads and values

`DebugSession` exposes `id`, current `snapshot`, broadcast `updates` and `done`.
Publish immutable full `DebugSnapshot` replacements. Every observable change,
including output-only changes, increases the local revision. Native event sequence
numbers alone are insufficient: Go output can grow without a new native event.
Set `snapshot` before emitting the update. Consumers subscribe, then read the
getter so a pause reached during launch cannot be lost.

A snapshot contains session identity, revision, phase, pause token, threads,
frames, breakpoint results, full retained stdout/stderr/console text, truncation
flags, optional message and optional real exit code. Consumers replace output
buffers instead of appending retained text. Never invent exit code zero when a
backend supplies no exit code. The console is read-only backend diagnostics.

Providers must bound retained output, thread/frame counts, locals, nested children,
depth and string lengths. Document concrete limits in each adapter. Preserve
valid Unicode when truncating and set the appropriate `*Truncated` flag whenever
native or adapter bounds omit content. Missing inspection is not an empty scope:
use `localsUnavailableReason` or `DebugVariable.unavailableReason`.

`DebugFrame` identifies its real thread and contains copied read-only `locals`.
`DebugVariable.children` are actual bounded snapshots, not live handles. Primitive
values and safe built-in container inspection may be exposed. Do not invoke user
code, repr/str hooks, arbitrary getters or equality/hash functions for inspection.
No expandable placeholder implies that unimplemented object retrieval exists.

## 5. Pause tokens, commands and cleanup

Phases are `starting`, `running`, `paused`, `stopping`, `terminated` and `failed`.
Only paused snapshots contain frames and a non-null `DebugPauseToken(sessionId,
generation)`. A generation is positive and identifies an observed pause. Frame IDs
are scoped to that token, and frame thread IDs must name threads in the snapshot.
Invalidate the token after resume/step, even if another thread remains paused.

`command(DebugCommand, pauseToken:, threadId:)` supports resume, pause and the three
step modes. Resume/step require the current token. Reject stale or foreign tokens,
unknown threads and invalid state without changing execution. Pause requires a
running session and its capability. Commands acknowledge dispatch rather than
waiting for the next pause; ongoing execution must not block pause or stop.
Adapters serialize transport work without queueing stop behind a long-running VM
resume call. Commands and frame navigation must not reuse an old pause after a
session/root switch.

`done`, `stop()` and `dispose()` complete only after actual worker exit and native
resource/runtime-lease cleanup. Stop and dispose are idempotent; dispose closes
updates after cleanup. A stop request, close response or elapsed timeout does not
prove termination. While termination is pending, retain the lease and show
`stopping`; never release the runtime for overlapping work. Terminal phases are
published after the worker exits. A failed program/backend publishes its useful
message; a failure while starting must clean up partial resources before throwing.

## 6. Existing backend mapping

| Backend | Truthful first adapter boundary |
| --- | --- |
| Lua | `LuaDebugger` snapshots; paused breakpoint updates; real pause/steps; bounded primitive locals; cumulative output at pause/exit. |
| Go | `GoDebugSession` polling; launch-only breakpoints; goroutine-specific commands; bounded locals, with shared-value inspection unavailable when other goroutines exist; rolling 64 KiB output tails. |
| Python | Native `qfli_py_debug_*` ABI; live breakpoint replacement; steps/stop, no asynchronous pause; stack and bounded built-in values; output currently returned only when execute finishes. |

Go native close currently requests stop and removes registration without awaiting
the worker: stop, poll actual termination, then close and dispose. Python retains
its runtime lease until `execute_into` returns and all references are released.
Lua awaits stop before freeing its VM. All three currently lack evaluation; no
provider may claim otherwise.

## 7. Validation and acceptance

Validate mutable/native payloads at the adapter boundary before constructing these
typed immutable records. Constructor assertions document scalar/state invariants;
they do not replace release-mode path, capability, bounds and generation checks.
Integration must cover real entry/breakpoint pauses, cross-file absolute paths,
stale tokens, each supported step, cancellation while running/paused, worker cleanup,
source snapshots or explicit save requirements, output-only revisions, rolling
buffer replacement, and unavailable/truncated values. Host tests cannot establish
OHOS packaged-runtime behavior. Record native ABI and current-device acceptance
separately, and never mark the umbrella complete from the contract alone.

## 8. Editor integration and lifecycle

Capture the active buffer's physical owning root, configured entry and exact
source revisions before asynchronous work. A workspace recovery buffer is not a
runnable owner: the host supplies `isFileAvailable` and the controller rechecks
it after pending saves and backup IO, immediately before writing. Navigation
guards belong inside `EditorController.openPath`, before selecting an existing
tab and after each read/stat await, so stale pause navigation never inserts or
activates a tab. Cancelled saves report cancellation and retain dirty text.

`paused` requires a current, unconsumed pause token, not merely a retained paused
snapshot. Hide stack/locals and execution marks after resume/step consumes that
token. Execution marks require the selected frame and exact captured source text
inside its canonical owner; dirty-at-launch snapshots are valid, later edits and
unknown sources are unavailable. Async frame navigation also fences source
identity and pause generation. Breakpoint replacement inputs are immutable and
their pending state belongs to the originating run, so an old pending request
cannot disable later sessions.

Editor Run, file tools and terminal dispatch share the debugger lane. Count all
terminal tabs and pending cleanup rather than only the selected tab. Closing a
panel cannot release a worker lease before actual exit. Keep Stop/interrupt
usable while another command is pending; cleanup errors retain ownership and
allow explicit retry. Closed-only debugger disposal retries are bounded to three
attempts with 50 ms delay; exhausted cleanup retains busy and the actual error.

Gutters listen to render-paragraph changes only through `CustomPainter.repaint`.
The editor publishes geometry during layout; a widget listener must not schedule
a new build there. Both paint and tap mapping ignore stale paragraph indexes
after source shrink and map folded chunks to physical source lines.

## 9. Output, console and ports

`EditorOutputBuffer` retains a bounded 128 Ki UTF-16 tail without splitting a
surrogate pair. Ordinary Run forwards the same actual stream subscriptions used
by Terminal; do not attach duplicate single-subscription listeners. Exit codes,
real file-tool results and provider-analysis results may be logged. The main
product with no analyzer hides that unavailable checker message in Output;
standalone products retain useful provider-unavailable reasons.

Debug stdout/stderr/console are full retained replacements, including when a
backend trims a rolling tail. Never append each full snapshot to earlier output.
Debug Console is read-only and may also retain actual preview console messages.
Closing Terminal does not cancel the page-owned preview console subscription.

Ports lists only a real preview session started by this editor. Stop delegates
to that session, keeps a failed listener visible for retry, and cannot remove a
new replacement session when an old stop finishes. A tab or timeout does not
prove cleanup. No process/port scanning, shell, REPL or expression evaluator is
implied by these panels.


## 10. Workspace removal and asynchronous command ordering

`isProjectAvailable(String projectPath)` checks current workspace membership for
an original owner even after clean tabs close. Check it before inserting an
unopened stack source and after asynchronous reads; a path-only dirty recovery
set cannot identify closed clean sources. Main saved-workspace membership is
strict, while standalone multi-root history keeps its existing registered-tab
behavior. Removed dirty sources remain recoverable through Save As.

Every page write path, including manual save, autosave, tab-close Save and
document-tool callbacks, passes a live membership predicate to `saveFile`.
Checking only before entering the write queue is insufficient: a root may be
removed while the save waits for earlier IO or backup. Keep canceled buffers
dirty and open. After awaiting a tab-close dialog or save, locate the captured
file by identity before closing it; an old numeric tab index may now name a
different file.

Pending breakpoint replacement blocks resume and step dispatch until the
replacement finishes, without consuming the pause token. Stop remains available.
Each frame selection or new navigation invalidates older pending navigation,
even within the same pause generation, so a slow earlier read cannot reactivate
its tab after a newer stack selection.

Closing a busy terminal hides its panel while retaining the real execution lane.
Every explicit reopen, including menu, Run feedback and online-terminal routing,
cancels deferred panel removal. The eventual worker-idle callback must not destroy
a terminal the user has reopened. Widget tests pump asynchronous cleanup until
actual busy becomes false instead of directly awaiting fake-time stream cleanup.


## 11. Attached output failures

Register real exit observation before waiting for either output stream. Capture transport and observer errors without skipping lifecycle finalization. Cancel a failed transport subscription, request shared retryable cancellation, and wait for actual worker exit plus healthy-stream drainage before releasing running resources. Keep failed or in-flight cleanup in aggregate ownership. An exceptional exit future proves no exit and must remain blocked. Attachment identity prevents an older completion from clearing a replacement run. Void process adapters must observe the returned attachment future.

Widget fixtures capture controller.done immediately after controller creation, before cancellation. A close after cancellation can return a root-zone singleton future that FakeAsync pumping cannot flush. Create completion observers before pumping, retain exact failure assertions and test cleanup retries, late exit, replacement ownership and both process adapters.

## 12. Cancellation with blocked process input

Closing stdin can wait for buffered bytes that a child never reads. Observe the
close future immediately, but dispatch Windows tree termination before awaiting
that future. Await stdin settlement before releasing cancellation ownership.
Natural root exit must not bypass an in-flight cancellation. Repeated requests
share the same cancellation future.

POSIX retains its bounded input-close grace before its existing tree signals.
The Windows Boolean tree-command result and direct-kill fallback are legacy
behavior. They do not prove exact descendant identities or terminal state.
Product adapters must not report completed subtree cleanup solely from a root
kill, an exit status of 130, closed streams or a cancellation timeout. Preserve
pending or failed ownership when cleanup is unproved.

A blocked-input fake must verify that termination starts while stdin is still
pending. Keep ownership assertions for natural root exit and fallback paths.
Actual descendant cleanup needs a separately identified live-process regression.
Do not attribute residual host processes to a test without parent or launch
identity evidence.
