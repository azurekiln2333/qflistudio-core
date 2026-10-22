import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/process_supervisor.dart';

void main() {
  test('forwards output and removes a naturally completed process', () async {
    final process = _FakeProcess(
      pid: 41,
      stdoutBytes: <int>[1, 2],
      stderrBytes: <int>[3],
      exitCode: 7,
    );
    final supervisor = ProcessSupervisor(
      processStarter:
          (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
            bool includeParentEnvironment = true,
            bool runInShell = false,
            ProcessStartMode mode = ProcessStartMode.normal,
          }) async {
            return process as Process;
          },
    );

    final managed = await supervisor.start('fixture', <String>['arg']);
    final stdout = managed.stdout.expand((chunk) => chunk).toList();
    final stderr = managed.stderr.expand((chunk) => chunk).toList();
    process.complete();

    expect(await managed.exitCode, 7);
    expect(await stdout, <int>[1, 2]);
    expect(await stderr, <int>[3]);
    expect(supervisor.activeCount, 0);
    expect(managed.isDone, isTrue);
  });

  test(
    'registers before starter completion and cancellation is idempotent',
    () async {
      final starterCompleter = Completer<Process>();
      final process = _FakeProcess(pid: 99, exitCode: -15);
      final supervisor = ProcessSupervisor(
        processStarter:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) => starterCompleter.future,
      );

      final startFuture = supervisor.start('fixture', const <String>[]);
      await Future<void>.delayed(Duration.zero);
      expect(supervisor.activeCount, 1);

      final managed =
          await Future.wait<ManagedProcess>(<Future<ManagedProcess>>[
            startFuture,
            Future<ManagedProcess>.microtask(() async {
              starterCompleter.complete(process);
              return startFuture;
            }),
          ]).then((values) => values.first);
      final firstCancel = managed.cancel();
      final secondCancel = managed.cancel();
      process.completeWhenKilled = true;

      await Future.wait(<Future<void>>[firstCancel, secondCancel]);
      expect(process.killCount, 1);
      expect(process.stdinClosed, isTrue);
      expect(await managed.exitCode, -15);
      expect(supervisor.activeCount, 0);
    },
  );

  test('uses Windows tree termination and falls back to direct kill', () async {
    final process = _FakeProcess(pid: 123, exitCode: -1);
    var terminatedPid = 0;
    final supervisor = ProcessSupervisor(
      isWindows: true,
      windowsProcessTreeTerminator: (pid) async {
        terminatedPid = pid;
        process.complete();
        return true;
      },
      processStarter:
          (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
            bool includeParentEnvironment = true,
            bool runInShell = false,
            ProcessStartMode mode = ProcessStartMode.normal,
          }) async {
            return process as Process;
          },
    );

    final managed = await supervisor.start('fixture', const <String>[]);
    await managed.cancel();

    expect(terminatedPid, 123);
    expect(process.killCount, 0);
    expect(supervisor.activeCount, 0);
  });

  test(
    'POSIX cancellation escalates an ignored TERM and drains output',
    () async {
      final process = _FakeProcess(
        pid: 471,
        stdoutBytes: <int>[1, 2, 3],
        stderrBytes: <int>[4, 5],
        exitCode: -9,
      )..ignoreTerm = true;
      final supervisor = ProcessSupervisor(
        isWindows: false,
        processStarter:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async => process,
      );
      final managed = await supervisor.start('fixture', const []);
      final output = managed.stdout.expand((bytes) => bytes).toList();
      final errors = managed.stderr.expand((bytes) => bytes).toList();

      await managed.cancel().timeout(const Duration(seconds: 3));

      expect(process.killSignals, [
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
      expect(await managed.exitCode, -9);
      expect(await output, [1, 2, 3]);
      expect(await errors, [4, 5]);
      expect(supervisor.activeCount, 0);
    },
  );

  test(
    'Windows unavailable tree command keeps its direct kill fallback',
    () async {
      final process = _FakeProcess(pid: 472, exitCode: -1);
      final supervisor = ProcessSupervisor(
        isWindows: true,
        windowsProcessTreeTerminator: (_) async => false,
        processStarter:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async => process,
      );
      final managed = await supervisor.start('fixture', const []);

      await managed.cancel();

      expect(process.killSignals, [ProcessSignal.sigterm]);
      expect(supervisor.activeCount, 0);
    },
  );

  test(
    'natural exit cannot clean up while cancellation is still pending',
    () async {
      final process = _FakeProcess(pid: 473, exitCode: 0);
      final supervisor = ProcessSupervisor(
        isWindows: false,
        processStarter:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async => process,
      );
      final managed = await supervisor.start('fixture', const []);
      process.completeExitOnly();
      await Future<void>.delayed(Duration.zero);
      process.pauseStdin();
      final cancellation = managed.cancel();
      process.closeOutputStreams();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(managed.isDone, isFalse);
        expect(supervisor.activeCount, 1);
      } finally {
        process.resumeStdin();
        await cancellation;
      }
      expect(managed.isDone, isTrue);
      expect(supervisor.activeCount, 0);
    },
  );
}

class _FakeProcess implements Process {
  _FakeProcess({
    required this.pid,
    required int exitCode,
    List<int> stdoutBytes = const <int>[],
    List<int> stderrBytes = const <int>[],
  }) : _exitCode = Completer<int>(),
       _stdoutController = StreamController<List<int>>(),
       _stderrController = StreamController<List<int>>(),
       stdinController = StreamController<List<int>>() {
    _stdinSubscription = stdinController.stream.listen((_) {});
    _plannedExitCode = exitCode;
    stdout = _stdoutController.stream;
    stderr = _stderrController.stream;
    stdin = IOSink(stdinController.sink);
    if (stdoutBytes.isNotEmpty) _stdoutController.add(stdoutBytes);
    if (stderrBytes.isNotEmpty) _stderrController.add(stderrBytes);
  }

  final Completer<int> _exitCode;
  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final StreamController<List<int>> stdinController;
  late final StreamSubscription<List<int>> _stdinSubscription;
  late final int _plannedExitCode;

  @override
  final int pid;

  @override
  late final Future<int> exitCode = _exitCode.future;

  @override
  late final IOSink stdin;

  @override
  late final Stream<List<int>> stdout;

  @override
  late final Stream<List<int>> stderr;

  int killCount = 0;
  final killSignals = <ProcessSignal>[];
  bool completeWhenKilled = false;
  bool ignoreTerm = false;

  bool get stdinClosed => stdinController.isClosed;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount++;
    killSignals.add(signal);
    if (ignoreTerm && signal == ProcessSignal.sigterm) return true;
    if (completeWhenKilled || !_exitCode.isCompleted) {
      complete();
    }
    return true;
  }

  void complete() {
    completeExitOnly();
    closeOutputStreams();
  }

  void pauseStdin() => _stdinSubscription.pause();

  void resumeStdin() => _stdinSubscription.resume();

  void completeExitOnly() {
    if (!_exitCode.isCompleted) _exitCode.complete(_plannedExitCode);
  }

  void closeOutputStreams() {
    if (!_stdoutController.isClosed) _stdoutController.close();
    if (!_stderrController.isClosed) _stderrController.close();
  }
}
