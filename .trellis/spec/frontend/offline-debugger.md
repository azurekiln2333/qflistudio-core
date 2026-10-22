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
