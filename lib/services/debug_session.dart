import 'dart:async';

import 'code_analysis.dart';

/// Product-owned offline debugging. Launch only after an explicit Debug action;
/// an unavailable provider must never fall back to ordinary program execution.
abstract interface class StudioDebugger {
  String get displayName;
  DebugCapabilities get capabilities;
  bool supportsLanguage(String language);

  /// Validates paths, capabilities and source snapshots before executing code.
  /// Any partially created worker must be cleaned up before a launch error.
  Future<DebugSession> launch(DebugLaunchRequest request);
}

enum DebugBreakpointUpdate { launchOnly, paused, live }

/// When actual program output can become observable through snapshots.
enum DebugOutputDelivery { live, pauseOrExit, exitOnly }

/// A capability describes implemented behavior, not a planned UI action.
final class DebugCapabilities {
  const DebugCapabilities({
    required this.breakpointUpdate,
    required this.outputDelivery,
    this.supportsPause = false,
    this.supportsStepInto = false,
    this.supportsStepOver = false,
    this.supportsStepOut = false,
    this.supportsDocumentSnapshots = false,
    this.supportsStopOnEntry = false,
    this.supportsStackFrames = false,
    this.supportsVariables = false,
  }) : assert(!supportsVariables || supportsStackFrames);

  final DebugBreakpointUpdate breakpointUpdate;
  final DebugOutputDelivery outputDelivery;
  final bool supportsPause;
  final bool supportsStepInto;
  final bool supportsStepOver;
  final bool supportsStepOut;

  /// Supports exact unsaved documents without overwriting project sources.
  final bool supportsDocumentSnapshots;
  final bool supportsStopOnEntry;
  final bool supportsStackFrames;
  final bool supportsVariables;
}

/// Paths are canonical absolute paths within one physical project root.
/// Providers resolve and check filesystem containment, including symlinks.
final class DebugLaunchRequest {
  DebugLaunchRequest({
    required this.projectPath,
    required this.entryFilePath,
    required this.language,
    required List<CodeDocumentSnapshot> documents,
    List<DebugBreakpoint> breakpoints = const [],
    this.stopOnEntry = false,
  }) : assert(projectPath.isNotEmpty),
       assert(entryFilePath.isNotEmpty),
       assert(language.isNotEmpty),
       documents = List.unmodifiable(documents),
       breakpoints = List.unmodifiable(breakpoints);

  final String projectPath;
  final String entryFilePath;
  final String language;

  /// Exact captured editor text. Unsupported nonempty snapshots must be rejected,
  /// never silently ignored. A caller may save first and pass an empty list.
  final List<CodeDocumentSnapshot> documents;
  final List<DebugBreakpoint> breakpoints;
  final bool stopOnEntry;
}

/// A canonical project-local file and a one-based physical source position.
/// A missing column means that the backend reports line precision only.
final class DebugSourceLocation {
  const DebugSourceLocation({
    required this.filePath,
    required this.line,
    this.column,
  }) : assert(filePath != ''),
       assert(line > 0),
       assert(column == null || column > 0);

  final String filePath;
  final int line;
  final int? column;
}

final class DebugBreakpoint {
  const DebugBreakpoint({required this.filePath, required this.line})
    : assert(filePath != ''),
      assert(line > 0);

  final String filePath;
  final int line;
}

enum DebugBreakpointStatus { pending, verified, rejected }

/// Accepting a requested line does not verify that it contains executable code.
/// Actual locations must come from the backend, never a guessed nearby line.
final class DebugBreakpointResult {
  const DebugBreakpointResult({
    required this.requested,
    required this.status,
    this.actualLocation,
    this.reason,
  }) : assert(
         status != DebugBreakpointStatus.verified || actualLocation != null,
       ),
       assert(
         status != DebugBreakpointStatus.rejected ||
             (reason != null && reason != ''),
       );

  final DebugBreakpoint requested;
  final DebugBreakpointStatus status;
  final DebugSourceLocation? actualLocation;
  final String? reason;
}

enum DebugPhase { starting, running, paused, stopping, terminated, failed }

enum DebugCommand { resume, pause, stepInto, stepOver, stepOut }

/// Binds commands and displayed frames to one observed pause in one session.
/// Invalidate the token after resume/step, even if another thread stays paused.
final class DebugPauseToken {
  const DebugPauseToken({required this.sessionId, required this.generation})
    : assert(sessionId != ''),
      assert(generation > 0);

  final String sessionId;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is DebugPauseToken &&
      sessionId == other.sessionId &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(sessionId, generation);
}

final class DebugThread {
  const DebugThread({
    required this.id,
    required this.name,
    required this.isPaused,
  }) : assert(id != '');

  final String id;
  final String name;
  final bool isPaused;
}

/// Copied, read-only data from a real stopped frame. Children are bounded
/// snapshots, not live handles. Inspection must not invoke user code or repr.
final class DebugVariable {
  DebugVariable({
    required this.name,
    required this.type,
    required this.value,
    List<DebugVariable> children = const [],
    this.unavailableReason,
    this.truncated = false,
  }) : children = List.unmodifiable(children);

  final String name;
  final String type;
  final String value;
  final List<DebugVariable> children;
  final String? unavailableReason;
  final bool truncated;
}

/// Frame identifiers are valid only with the containing snapshot's pause token.
/// A missing location denotes an actual frame without navigable project source.
final class DebugFrame {
  DebugFrame({
    required this.id,
    required this.threadId,
    required this.name,
    this.location,
    List<DebugVariable> locals = const [],
    this.localsUnavailableReason,
    this.localsTruncated = false,
  }) : assert(id.isNotEmpty),
       assert(threadId.isNotEmpty),
       locals = List.unmodifiable(locals);

  final String id;
  final String threadId;
  final String name;
  final DebugSourceLocation? location;
  final List<DebugVariable> locals;
  final String? localsUnavailableReason;
  final bool localsTruncated;
}

/// Complete immutable replacement state, never an output delta. Each revision
/// increases for every observable change, including output-only updates.
/// Providers bound every collection and string and expose any lost content.
final class DebugSnapshot {
  DebugSnapshot({
    required this.sessionId,
    required this.revision,
    required this.phase,
    this.pauseToken,
    List<DebugThread> threads = const [],
    List<DebugFrame> frames = const [],
    List<DebugBreakpointResult> breakpoints = const [],
    this.threadsTruncated = false,
    this.framesTruncated = false,
    this.stdout = '',
    this.stderr = '',
    this.console = '',
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.consoleTruncated = false,
    this.message,
    this.exitCode,
  }) : assert(sessionId.isNotEmpty),
       assert(revision >= 0),
       assert((phase == DebugPhase.paused) == (pauseToken != null)),
       assert(pauseToken == null || pauseToken.sessionId == sessionId),
       assert(phase == DebugPhase.paused || frames.isEmpty),
       assert(
         phase != DebugPhase.failed || (message != null && message.isNotEmpty),
       ),
       threads = List.unmodifiable(threads),
       frames = List.unmodifiable(frames),
       breakpoints = List.unmodifiable(breakpoints);

  final String sessionId;
  final int revision;
  final DebugPhase phase;
  final DebugPauseToken? pauseToken;
  final List<DebugThread> threads;
  final List<DebugFrame> frames;
  final List<DebugBreakpointResult> breakpoints;
  final bool threadsTruncated;
  final bool framesTruncated;

  /// Complete retained text, possibly a rolling tail. Consumers replace their
  /// displayed buffers rather than appending this text to an old snapshot.
  final String stdout;
  final String stderr;

  /// Read-only backend diagnostics; this contract has no evaluation command.
  final String console;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final bool consoleTruncated;
  final String? message;

  /// Null when the backend does not expose a real program exit code.
  final int? exitCode;

  /// Terminal phases are published only once the actual worker has exited.
  bool get isTerminal =>
      phase == DebugPhase.terminated || phase == DebugPhase.failed;
}

abstract interface class DebugSession {
  String get id;
  DebugSnapshot get snapshot;

  /// Broadcast full snapshots. Update [snapshot] before publishing; callers
  /// subscribe and then read it to include a pause reached during launch.
  Stream<DebugSnapshot> get updates;

  /// Completes after actual worker exit and native resource/runtime-lease
  /// cleanup. A stop request, timeout or transport close is not completion.
  Future<void> get done;

  /// Atomically replaces the complete breakpoint set according to capabilities.
  /// Return one truthful result per request, also reflected in the snapshot.
  Future<List<DebugBreakpointResult>> setBreakpoints(
    List<DebugBreakpoint> breakpoints,
  );

  /// Resume/step require the current observed pause token. Pause requires a
  /// running session and supportsPause. Reject stale tokens, unsupported actions
  /// and unknown threads without changing execution. Completion acknowledges
  /// dispatch, not the next pause, so pause/stop remain usable while running.
  Future<void> command(
    DebugCommand command, {
    DebugPauseToken? pauseToken,
    String? threadId,
  });

  /// Idempotently requests stop, then waits for [done].
  Future<void> stop();

  /// Idempotently stops, awaits cleanup, then closes [updates].
  Future<void> dispose();
}
