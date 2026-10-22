import 'dart:async';
import 'dart:io';

import 'process_identity_stub.dart'
    if (dart.library.ffi) 'process_identity_ffi.dart'
    as process_identity;

/// Starts a process for [ProcessSupervisor].
///
/// Keeping process creation behind this callback lets tests provide a fake
/// [Process] without changing the production API.
typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
      bool runInShell,
      ProcessStartMode mode,
    });

/// Terminates a Windows process and all of its descendants.
///
/// The return value reports whether the tree command handled the process. A
/// false result causes [ManagedProcess] to fall back to [Process.kill].
typedef WindowsProcessTreeTerminator = Future<bool> Function(int pid);

/// Owns every process started through it and cancels all remaining processes
/// during shutdown.
class ProcessSupervisor {
  ProcessSupervisor({
    ProcessStarter? processStarter,
    WindowsProcessTreeTerminator? windowsProcessTreeTerminator,
    bool? isWindows,
  }) : _processStarter = processStarter ?? _startProcess,
       _windowsProcessTreeTerminator =
           windowsProcessTreeTerminator ?? _terminateWindowsProcessTree,
       _isWindows = isWindows ?? Platform.isWindows,
       _captureLinuxTree = processStarter == null && Platform.isLinux;

  final ProcessStarter _processStarter;
  final WindowsProcessTreeTerminator _windowsProcessTreeTerminator;
  final bool _isWindows;
  final bool _captureLinuxTree;
  final Set<ManagedProcess> _processes = <ManagedProcess>{};
  bool _disposed = false;

  /// Number of processes that have not completed cleanup.
  int get activeCount => _processes.length;

  /// A snapshot of the currently owned processes.
  Iterable<ManagedProcess> get activeProcesses =>
      List<ManagedProcess>.unmodifiable(_processes);

  /// Starts and registers a process before waiting for [Process.start] to
  /// complete. The returned object is the only process handle callers need.
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    if (_disposed) {
      throw StateError('ProcessSupervisor has been disposed');
    }

    late final ManagedProcess managedProcess;
    managedProcess = ManagedProcess._(
      windows: _isWindows,
      captureLinuxTree: _captureLinuxTree,
      windowsProcessTreeTerminator: _windowsProcessTreeTerminator,
      onCleanup: () => _processes.remove(managedProcess),
    );
    _processes.add(managedProcess);

    return _startRegistered(
      managedProcess,
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
  }

  Future<ManagedProcess> _startRegistered(
    ManagedProcess managedProcess,
    String executable,
    List<String> arguments, {
    required String? workingDirectory,
    required Map<String, String>? environment,
    required bool includeParentEnvironment,
    required bool runInShell,
    required ProcessStartMode mode,
  }) async {
    try {
      final process = await _processStarter(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: runInShell,
        mode: mode,
      );
      managedProcess.attach(process);
      return managedProcess;
    } catch (error, stackTrace) {
      managedProcess.failToStart(error, stackTrace);
      rethrow;
    }
  }

  /// Cancels every pending and running process, waiting for each exit code.
  Future<void> cancelAll() async {
    await Future.wait(_processes.map((process) => process.cancel()));
  }

  /// Idempotent app/page shutdown operation.
  Future<void> dispose() async {
    if (_disposed) {
      await cancelAll();
      return;
    }
    _disposed = true;
    await cancelAll();
  }

  /// Alias that reads naturally at app shutdown call sites.
  Future<void> shutdown() => dispose();
}

/// A process whose streams and lifetime are owned by a [ProcessSupervisor].
class ManagedProcess {
  ManagedProcess._({
    required bool windows,
    required bool captureLinuxTree,
    required WindowsProcessTreeTerminator windowsProcessTreeTerminator,
    required void Function() onCleanup,
  }) : _windows = windows,
       _captureLinuxTree = captureLinuxTree,
       _windowsProcessTreeTerminator = windowsProcessTreeTerminator,
       _onCleanup = onCleanup;

  final bool _windows;
  final bool _captureLinuxTree;
  final WindowsProcessTreeTerminator _windowsProcessTreeTerminator;
  final void Function() _onCleanup;
  final Completer<Process> _processReady = Completer<Process>();
  final Completer<int> _exitCode = Completer<int>();
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();

  Process? _process;
  _LinuxProcessTree? _linuxTree;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  Future<void>? _cancelFuture;
  Future<void>? _cleanupFuture;
  bool _cleanedUp = false;
  bool _cancelling = false;

  /// The operating-system process id after start has completed.
  int get pid => _requireProcess.pid;

  /// Forwarded stdout. The supervisor drains the underlying process stream.
  Stream<List<int>> get stdout => _stdoutController.stream;

  /// Forwarded stderr. The supervisor drains the underlying process stream.
  Stream<List<int>> get stderr => _stderrController.stream;

  /// Stdin for the managed process.
  IOSink get stdin => _requireProcess.stdin;

  /// Completes with the process exit code, including after cancellation.
  Future<int> get exitCode => _exitCode.future;

  /// Whether cancellation or natural completion has finished cleanup.
  bool get isDone => _cleanedUp;

  /// Completes when the process exits and all supervisor cleanup is done.
  Future<int> waitForExit() => exitCode;

  void attach(Process process) {
    if (_process != null) {
      throw StateError('ManagedProcess is already attached');
    }
    _process = process;
    if (!_windows && _captureLinuxTree) {
      _linuxTree = _LinuxProcessTree.capture(process.pid);
    }
    _processReady.complete(process);

    _stdoutSubscription = process.stdout.listen(
      _stdoutController.add,
      onError: _forwardStdoutError,
      onDone: () {
        unawaited(_stdoutController.close());
        _complete(_stdoutDone);
      },
    );
    _stderrSubscription = process.stderr.listen(
      _stderrController.add,
      onError: _forwardStderrError,
      onDone: () {
        unawaited(_stderrController.close());
        _complete(_stderrDone);
      },
    );
    unawaited(_observeExit(process));
  }

  void failToStart(Object error, StackTrace stackTrace) {
    if (!_processReady.isCompleted) {
      _processReady.completeError(error, stackTrace);
      unawaited(
        _processReady.future.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {},
        ),
      );
    }
    if (!_exitCode.isCompleted) {
      _exitCode.completeError(error, stackTrace);
      unawaited(
        _exitCode.future.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {},
        ),
      );
    }
    unawaited(_cleanup());
  }

  /// Idempotently stops the process and waits for its exit code.
  Future<void> cancel() {
    if (_cleanedUp) return Future<void>.value();
    return _cancelFuture ??= _cancelInternal();
  }

  /// Alias for lifecycle owners that use dispose terminology.
  Future<void> dispose() => cancel();

  Future<void> _cancelInternal() async {
    _cancelling = true;
    Process? process;
    try {
      process = await _processReady.future;
    } catch (_) {
      await _cleanup();
      return;
    }

    try {
      final closed = process.stdin.close();
      if (_windows) {
        await closed;
      } else {
        await closed.timeout(_terminationGrace);
      }
    } catch (_) {
      // A process can close stdin concurrently while it is being cancelled.
    }

    if (!_windows) {
      await _cancelPosix(process);
      return;
    }

    var treeTerminated = false;
    if (_windows) {
      try {
        treeTerminated = await _windowsProcessTreeTerminator(process.pid);
      } catch (_) {
        // Fall back to the direct process handle if taskkill is unavailable.
      }
    }
    if (!_windows || !treeTerminated) {
      process.kill();
    }

    try {
      final code = await process.exitCode;
      await _cleanup();
      if (!_exitCode.isCompleted) _exitCode.complete(code);
    } catch (error, stackTrace) {
      await _cleanup();
      if (!_exitCode.isCompleted) _exitCode.completeError(error, stackTrace);
    }
  }

  static const _terminationGrace = Duration(milliseconds: 500);
  static const _forcedExitTimeout = Duration(seconds: 2);

  Future<void> _cancelPosix(Process process) async {
    final tree = _linuxTree;
    if (tree != null) {
      // Stop known parents while discovering children, so they cannot fork a
      // new child between enumeration and acquisition of its identity handle.
      try {
        await tree.freezeAndCollect();
        tree.signalDescendants(ProcessSignal.sigterm);
      } finally {
        tree.resumeAll();
      }
      // Let a waiting shell reap terminated children and flush its final output
      // before terminating that shell. Retain handles to children that ignore
      // TERM, even if their parent exits and they are reparented.
      await _waitUntil(() => !tree.hasLiveDescendants, _terminationGrace);
      if (tree.hasLiveDescendants) {
        try {
          await tree.freezeAndCollect();
          tree.signalDescendants(ProcessSignal.sigkill);
        } finally {
          tree.resumeAll();
        }
        await _waitUntil(() => !tree.hasLiveDescendants, _forcedExitTimeout);
        // Give a waiting parent a chance to reap a stubborn child before TERM
        // reaches the parent; its normal wait/exit path also drains final text.
        await _waitForExitWithin(process, const Duration(milliseconds: 200));
      }
      try {
        await tree.freezeAndCollect();
        tree.signalDescendants(ProcessSignal.sigterm);
        tree.signalRoot(ProcessSignal.sigterm);
      } finally {
        tree.resumeAll();
      }
    } else {
      process.kill(ProcessSignal.sigterm);
    }

    final exited = await _waitForExitWithin(process, _terminationGrace);
    if (!exited || (tree?.hasLiveDescendants ?? false)) {
      if (tree != null) {
        try {
          await tree.freezeAndCollect();
          tree.signalDescendants(ProcessSignal.sigkill);
          tree.signalRoot(ProcessSignal.sigkill);
        } finally {
          tree.resumeAll();
        }
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }

    final code = await process.exitCode.timeout(_forcedExitTimeout);
    if (tree != null &&
        !await _waitUntil(() => !tree.hasLiveDescendants, _forcedExitTimeout)) {
      throw TimeoutException('Owned process descendants did not exit');
    }
    // Killing only the parent used to either leave inherited pipes open forever
    // or cancel the subscriptions before buffered final output was delivered.
    await _waitForStreams().timeout(_forcedExitTimeout);
    await _cleanup();
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  static Future<bool> _waitForExitWithin(
    Process process,
    Duration timeout,
  ) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _observeExit(Process process) async {
    try {
      final code = await process.exitCode;
      if (!_cancelling) await _waitForStreams();
      // Cancellation can begin while natural exit is waiting for inherited
      // pipes. Recheck after that await before releasing any identity handles.
      if (_cancelling) {
        try {
          await (_cancelFuture ?? Future<void>.value());
          return;
        } catch (_) {
          // A bounded cancellation failure is not proof of cleanup. Keep
          // observing the owned descendants and pipes until they really close.
          while (_linuxTree?.hasLiveDescendants ?? false) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await _waitForStreams();
        }
      }
      await _cleanup();
      if (!_exitCode.isCompleted) _exitCode.complete(code);
    } catch (error, stackTrace) {
      if (!_cancelling) await _waitForStreams();
      await _cleanup();
      if (!_exitCode.isCompleted) _exitCode.completeError(error, stackTrace);
    }
  }

  Future<void> _cleanup() {
    return _cleanupFuture ??= _cleanupInternal();
  }

  Future<void> _cleanupInternal() async {
    if (_cleanedUp) return;
    _cleanedUp = true;
    await Future.wait(<Future<void>>[
      _cancelSubscription(_stdoutSubscription),
      _cancelSubscription(_stderrSubscription),
    ]);
    _complete(_stdoutDone);
    _complete(_stderrDone);
    await Future.wait(<Future<void>>[
      _closeController(_stdoutController),
      _closeController(_stderrController),
    ]);
    _linuxTree?.close();
    _onCleanup();
  }

  Process get _requireProcess {
    final process = _process;
    if (process == null) {
      throw StateError('Process has not finished starting');
    }
    return process;
  }

  Future<void> _waitForStreams() =>
      Future.wait<void>(<Future<void>>[_stdoutDone.future, _stderrDone.future]);

  static void _complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void _forwardStdoutError(Object error, StackTrace stackTrace) {
    _stdoutController.addError(error, stackTrace);
  }

  void _forwardStderrError(Object error, StackTrace stackTrace) {
    _stderrController.addError(error, stackTrace);
  }

  static Future<void> _cancelSubscription(
    StreamSubscription<List<int>>? subscription,
  ) async {
    await subscription?.cancel();
  }

  static Future<void> _closeController(
    StreamController<List<int>> controller,
  ) => controller.close();
}

Future<bool> _waitUntil(bool Function() condition, Duration timeout) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed >= timeout) return false;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return true;
}

class _LinuxProcIdentity {
  _LinuxProcIdentity(this.parentPid, this.startTime, this.state);

  final int parentPid;
  final String startTime;
  final String state;

  static _LinuxProcIdentity? read(int pid) {
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      // comm may contain spaces and parentheses; fields after its final ')'
      // start at field 3 (state). starttime is field 22, not a wall clock.
      final end = stat.lastIndexOf(')');
      if (end < 0) return null;
      final fields = stat.substring(end + 1).trim().split(RegExp(r'\s+'));
      if (fields.length < 20) return null;
      final parentPid = int.tryParse(fields[1]);
      if (parentPid == null) return null;
      return _LinuxProcIdentity(parentPid, fields[19], fields[0]);
    } on FileSystemException {
      return null;
    }
  }
}

class _LinuxOwnedProcess {
  _LinuxOwnedProcess(this.pid, this.handle, this.startTime);

  final int pid;
  final process_identity.ProcessIdentityHandle handle;
  final String startTime;
  bool frozen = false;

  static _LinuxOwnedProcess? capture(int pid, {int? parentPid}) {
    final before = _LinuxProcIdentity.read(pid);
    if (before == null ||
        (parentPid != null && before.parentPid != parentPid)) {
      return null;
    }
    final handle = process_identity.ProcessIdentityHandle.tryOpen(pid);
    if (handle == null) return null;
    final after = _LinuxProcIdentity.read(pid);
    if (after == null ||
        after.startTime != before.startTime ||
        (parentPid != null && after.parentPid != parentPid)) {
      handle.close();
      return null;
    }
    return _LinuxOwnedProcess(pid, handle, before.startTime);
  }

  _LinuxProcIdentity? get identity {
    // The pinned task must still exist: a recycled numeric PID can never make
    // an exited pidfd look like a new live parent during later discovery.
    if (!handle.sendSignal(0)) return null;
    final current = _LinuxProcIdentity.read(pid);
    return current?.startTime == startTime ? current : null;
  }

  bool get isAlive {
    final current = identity;
    return current != null && current.state != 'Z' && current.state != 'X';
  }

  bool send(ProcessSignal signal) => handle.sendSignal(signal.signalNumber);

  Future<void> freeze() async {
    if (!isAlive) return;
    if (!send(ProcessSignal.sigstop)) {
      if (isAlive) throw StateError('Cannot stop owned process for inspection');
      return;
    }
    frozen = true;
    if (!await _waitUntil(() {
      final current = identity;
      return !isAlive || current?.state == 'T' || current?.state == 't';
    }, const Duration(milliseconds: 200))) {
      throw TimeoutException('Owned process did not stop for tree inspection');
    }
  }
}

class _LinuxProcessTree {
  _LinuxProcessTree(this.root) : owned = {root.pid: root};

  final _LinuxOwnedProcess root;
  final Map<int, _LinuxOwnedProcess> owned;

  static _LinuxProcessTree? capture(int rootPid) {
    final root = _LinuxOwnedProcess.capture(rootPid, parentPid: pid);
    return root == null ? null : _LinuxProcessTree(root);
  }

  bool get hasLiveDescendants =>
      owned.values.any((process) => process != root && process.isAlive);

  Future<void> freezeAndCollect() async {
    final queue = owned.values.toList();
    for (var index = 0; index < queue.length; index++) {
      final parent = queue[index];
      await parent.freeze();
      if (!parent.isAlive) continue;
      // SIGSTOP suspends the process's entire thread group. Read every task's
      // children list: a fork need not originate from the main thread.
      final tasks = Directory('/proc/${parent.pid}/task');
      try {
        for (final task in tasks.listSync(followLinks: false)) {
          final children = File('${task.path}/children').readAsStringSync();
          for (final value in children.trim().split(RegExp(r'\s+'))) {
            final pid = int.tryParse(value);
            if (pid == null || pid <= 0 || owned.containsKey(pid)) continue;
            if (owned.length >= 512) {
              throw StateError('Owned process tree exceeds 512 processes');
            }
            final child = _LinuxOwnedProcess.capture(
              pid,
              parentPid: parent.pid,
            );
            if (child != null) {
              owned[pid] = child;
              queue.add(child);
            } else {
              final current = _LinuxProcIdentity.read(pid);
              if (current?.parentPid == parent.pid &&
                  current?.state != 'Z' &&
                  current?.state != 'X') {
                throw StateError('Cannot acquire owned descendant identity');
              }
            }
          }
        }
      } on FileSystemException {
        if (parent.isAlive) rethrow;
      }
    }
  }

  void signalDescendants(ProcessSignal signal) {
    for (final process in owned.values.toList().reversed) {
      if (process != root) process.send(signal);
    }
  }

  void signalRoot(ProcessSignal signal) => root.send(signal);

  void resumeAll() {
    for (final process in owned.values.toList().reversed) {
      if (process.frozen) {
        process.send(ProcessSignal.sigcont);
        process.frozen = false;
      }
    }
  }

  void close() {
    for (final process in owned.values) {
      process.handle.close();
    }
    owned.clear();
  }
}

Future<Process> _startProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool runInShell = false,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell,
    mode: mode,
  );
}

Future<bool> _terminateWindowsProcessTree(int pid) async {
  try {
    final result = await Process.run('taskkill', <String>[
      '/PID',
      '$pid',
      '/T',
      '/F',
    ], runInShell: false);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
