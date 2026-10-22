import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

// Standalone verification avoids a platform-specific Flutter package config.
// ignore: avoid_relative_lib_imports
import '../lib/services/process_supervisor.dart';

/// Standalone real-process regression check. Needs no Flutter SDK/packages.
Future<void> main() async {
  if (!Platform.isLinux || !_canPinFixtures()) {
    stdout.writeln(
      'SKIP: real descendant checks require Linux procfs and pidfd support.',
    );
    return;
  }

  await _check('ignored TERM escalates', r'''
trap '' TERM
printf '%s\n' "$$" > "$1"
while :; do :; done
''');

  await _check(
    'background sleep is gone and shell output is drained',
    r'''
sleep 60 &
child=$!
printf '%s\n' "$child" > "$1"
wait "$child"
printf 'after-wait-out\n'
printf 'after-wait-err\n' >&2
''',
    hasChild: true,
    expectedOutput: 'after-wait-out',
    expectedError: 'after-wait-err',
  );

  await _check(
    'TERM-ignoring descendant is gone; unrelated sibling survives',
    r'''
sh -c 'trap "" TERM; printf "%s\n" "$$" > "$1"; exec sleep 60' child "$1" &
wait
''',
    hasChild: true,
  );

  await _check(
    'TERM trap final stdout and stderr are drained',
    r'''
trap 'printf "trap-out\n"; printf "trap-err\n" >&2; exit 0' TERM
printf '%s\n' "$$" > "$1"
while :; do :; done
''',
    expectedOutput: 'trap-out',
    expectedError: 'trap-err',
  );
}

Future<void> _check(
  String name,
  String script, {
  bool hasChild = false,
  String? expectedOutput,
  String? expectedError,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'qfli-process-check-',
  );
  final ready = File('${directory.path}/ready');
  final supervisor = ProcessSupervisor();
  final sibling = await Process.start('/bin/sleep', ['60']);
  ManagedProcess? managed;
  int? childPid;
  final cleanupHandles = <int>[];
  try {
    managed = await supervisor.start('/bin/sh', [
      '-c',
      script,
      'qfli-process-check',
      ready.path,
    ]);
    cleanupHandles.add(_pinFixture(managed.pid));
    final output = managed.stdout.transform(utf8.decoder).join();
    final errors = managed.stderr.transform(utf8.decoder).join();
    await _until(
      () => ready.existsSync() && ready.readAsStringSync().trim().isNotEmpty,
    );
    if (hasChild) {
      childPid = int.parse(ready.readAsStringSync().trim());
      cleanupHandles.add(_pinFixture(childPid));
    }
    final elapsed = Stopwatch()..start();
    await managed.cancel().timeout(const Duration(seconds: 8));
    await managed.exitCode;
    final outputText = await output;
    final errorText = await errors;
    _require(
      elapsed.elapsed < const Duration(seconds: 7),
      '$name: cancellation stalled',
    );
    _require(
      managed.isDone && supervisor.activeCount == 0,
      '$name: cleanup incomplete',
    );
    if (childPid != null) {
      // A zombie is exited but not gone. Require the actual procfs entry to
      // disappear as well, proving this is not merely a parent-exit assertion.
      await _until(() => !Directory('/proc/$childPid').existsSync());
    }
    _require(_running(sibling.pid), '$name: unrelated sibling was terminated');
    if (expectedOutput != null) {
      _require(
        outputText.contains(expectedOutput),
        '$name: final stdout lost: $outputText',
      );
    }
    if (expectedError != null) {
      _require(
        errorText.contains(expectedError),
        '$name: final stderr lost: $errorText',
      );
    }
    stdout.writeln('PASS: $name (${elapsed.elapsedMilliseconds} ms)');
  } finally {
    sibling.kill(ProcessSignal.sigkill);
    await sibling.exitCode;
    // These handles remain bound to the original fixtures after PID reuse.
    // Failure cleanup must meet the same scope requirement as production.
    for (final fd in cleanupHandles) {
      _signalPinned(fd, ProcessSignal.sigkill.signalNumber, nullptr, 0);
    }
    try {
      await supervisor.dispose().timeout(const Duration(seconds: 8));
    } finally {
      for (final fd in cleanupHandles) {
        _closePinned(fd);
      }
      await directory.delete(recursive: true);
    }
  }
}

final _openPinned = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Int32, Uint32), int Function(int, int)>(
      'pidfd_open',
    );
final _signalPinned = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Int32, Int32, Pointer<Void>, Uint32),
      int Function(int, int, Pointer<Void>, int)
    >('pidfd_send_signal');
final _closePinned = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

bool _canPinFixtures() {
  try {
    final fd = _openPinned(pid, 0);
    if (fd < 0) return false;
    final supported = _signalPinned(fd, 0, nullptr, 0) == 0;
    _closePinned(fd);
    return supported;
  } on ArgumentError {
    return false;
  }
}

int _pinFixture(int processPid) {
  final before = _procFields(processPid)?[19];
  final fd = _openPinned(processPid, 0);
  _require(fd >= 0, 'Cannot pin fixture process');
  if (before == null || _procFields(processPid)?[19] != before) {
    _closePinned(fd);
    throw StateError('Fixture process identity changed');
  }
  return fd;
}

List<String>? _procFields(int pid) {
  try {
    final stat = File('/proc/$pid/stat').readAsStringSync();
    return stat
        .substring(stat.lastIndexOf(')') + 1)
        .trim()
        .split(RegExp(r'\s+'));
  } on FileSystemException {
    return null;
  }
}

bool _running(int pid) {
  final fields = _procFields(pid);
  return fields != null && fields[0] != 'Z' && fields[0] != 'X';
}

Future<void> _until(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    _require(
      elapsed.elapsed < const Duration(seconds: 4),
      'Fixture condition timed out',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
