// Desktop/CLI platform layer for Herdr: executable discovery and process runs.
//
// Two rules shape this file:
//
//   * Discovery describes reality. The host must be able to say "Herdr is not
//     installed" instead of offering a menu that fails on click, so nothing is
//     guessed: a candidate is returned only when the probe succeeds.
//   * Every argument is one argv element. Herdr is started with `runInShell:
//     false`, so text containing spaces or quotes reaches it literally and can
//     never become shell syntax.
//
// Process ownership follows `process-lifecycle.md`: runs go through
// [ProcessSupervisor] (Windows tree kill, drain both streams, await exit), and
// [HerdrCliRunner.dispose] releases whatever is still alive.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../services/process_supervisor.dart';
import 'herdr_cli.dart';

/// Refuse to hold more than this per stream; a runaway command must not
/// exhaust memory. Real Herdr JSON for a few dozen agents is far below it.
const int _maxCapturedBytes = 2 * 1024 * 1024;

/// Where the user may point Studio at a Herdr build that is not on PATH.
const String herdrPathEnvironmentVariable = 'QFLI_HERDR_PATH';

/// Locates the Herdr executable.
///
/// Order: explicit user setting → `QFLI_HERDR_PATH` → `PATH` → the platform's
/// usual install directories. Returns null when Herdr is not installed; the
/// host then reports `unsupported` with an install hint.
Future<String?> locateHerdrExecutable({
  String? explicitPath,
  Map<String, String>? environment,
  HerdrPathProbe? isExecutable,
  HerdrDirectoryLister? listDirectory,
  bool? isWindows,
  bool? isMacOS,
}) async {
  final env = environment ?? Platform.environment;
  final windows = isWindows ?? Platform.isWindows;
  final macos = isMacOS ?? Platform.isMacOS;
  final probe = isExecutable ?? _defaultIsExecutable;
  final binary = windows ? 'herdr.exe' : 'herdr';

  final explicit = explicitPath?.trim() ?? '';
  if (explicit.isNotEmpty) {
    return probe(explicit) ? explicit : null;
  }

  final fromEnv = env[herdrPathEnvironmentVariable]?.trim() ?? '';
  if (fromEnv.isNotEmpty && probe(fromEnv)) return fromEnv;

  final fromPath = _findOnPath(
    binary,
    env: env,
    probe: probe,
    windows: windows,
  );
  if (fromPath != null) return fromPath;

  final lister = listDirectory ?? _defaultListDirectory;
  for (final candidate in _commonHerdrLocations(
    env: env,
    windows: windows,
    macos: macos,
    listDirectory: lister,
  )) {
    if (probe(candidate)) return candidate;
  }
  return null;
}

/// Whether [name] (an agent CLI, not Herdr itself) can be launched.
///
/// Used to mark a provider unavailable instead of offering a menu entry whose
/// launch would fail. Covers PATH plus the package-manager bins agents are
/// usually installed into.
bool executableOnPath(
  String name, {
  Map<String, String>? environment,
  HerdrPathProbe? isExecutable,
  HerdrDirectoryLister? listDirectory,
  bool? isWindows,
  bool? isMacOS,
}) {
  if (name.trim().isEmpty) return false;
  final env = environment ?? Platform.environment;
  final windows = isWindows ?? Platform.isWindows;
  final macos = isMacOS ?? Platform.isMacOS;
  final probe = isExecutable ?? _defaultIsExecutable;
  if (_findOnPath(name, env: env, probe: probe, windows: windows) != null) {
    return true;
  }
  final lister = listDirectory ?? _defaultListDirectory;
  for (final directory in _agentBinDirectories(
    env: env,
    windows: windows,
    macos: macos,
    listDirectory: lister,
  )) {
    for (final candidate in _executableNames(name, windows)) {
      if (probe(_join(directory, candidate))) return true;
    }
  }
  return false;
}

List<String> _commonHerdrLocations({
  required Map<String, String> env,
  required bool windows,
  required bool macos,
  required HerdrDirectoryLister listDirectory,
}) {
  final home = _home(env, windows);
  if (windows) {
    final locations = <String>[];
    // `herdr update` installs beside the running binary, e.g.
    // `%ProgramFiles%\herdr-windows-x86_64\herdr.exe`, and a version bump adds
    // a new suffixed directory instead of overwriting the old one.
    for (final base in <String?>[
      env['ProgramFiles'],
      env['ProgramFiles(x86)'],
      env['LOCALAPPDATA'] == null
          ? null
          : _join(env['LOCALAPPDATA']!, 'Programs'),
    ]) {
      if (base == null || base.isEmpty) continue;
      for (final entry in listDirectory(base)) {
        final leaf = entry.split(RegExp(r'[/\\]')).last;
        if (leaf.toLowerCase().startsWith('herdr-')) {
          locations.add(_join(entry, 'herdr.exe'));
        }
      }
    }
    for (final directory in <String?>[
      env['LOCALAPPDATA'] == null
          ? null
          : _join(env['LOCALAPPDATA']!, 'Programs'),
      env['USERPROFILE'] == null
          ? null
          : _join(env['USERPROFILE']!, 'scoop', 'shims'),
      home == null ? null : _join(home, '.cargo', 'bin'),
    ]) {
      if (directory != null && directory.isNotEmpty) {
        locations.add(_join(directory, 'herdr.exe'));
      }
    }
    return locations;
  }
  return <String>[
    if (macos) '/opt/homebrew/bin/herdr',
    '/usr/local/bin/herdr',
    '/usr/bin/herdr',
    if (!macos) '/bin/herdr',
    if (home != null) _join(home, '.local/bin/herdr'),
    if (home != null) _join(home, '.cargo/bin/herdr'),
  ];
}

List<String> _agentBinDirectories({
  required Map<String, String> env,
  required bool windows,
  required bool macos,
  required HerdrDirectoryLister listDirectory,
}) {
  final home = _home(env, windows);
  return <String>[
    if (windows && env['APPDATA'] != null) _join(env['APPDATA']!, 'npm'),
    if (windows && env['LOCALAPPDATA'] != null)
      _join(env['LOCALAPPDATA']!, 'Programs'),
    if (home != null) _join(home, '.local', 'bin'),
    if (home != null) _join(home, '.bun', 'bin'),
    if (home != null) _join(home, '.cargo', 'bin'),
    if (home != null) _join(home, '.volta', 'bin'),
    if (macos) '/opt/homebrew/bin',
  ];
}

String? _findOnPath(
  String name, {
  required Map<String, String> env,
  required HerdrPathProbe probe,
  required bool windows,
}) {
  final path = env['PATH'] ?? env['Path'] ?? '';
  if (path.isEmpty) return null;
  final separator = windows ? ';' : ':';
  for (final rawDirectory in path.split(separator)) {
    var directory = rawDirectory.trim();
    if (directory.isEmpty) continue;
    if (directory.length > 1 &&
        directory.startsWith('"') &&
        directory.endsWith('"')) {
      directory = directory.substring(1, directory.length - 1);
    }
    for (final candidate in _executableNames(name, windows)) {
      final full = _join(directory, candidate);
      if (probe(full)) return full;
    }
  }
  return null;
}

List<String> _executableNames(String name, bool windows) {
  if (!windows) return <String>[name];
  if (name.contains('.')) return <String>[name];
  // npm/pip shims are `.cmd`, standalone installers `.exe`.
  return <String>['$name.exe', '$name.cmd', '$name.bat', '$name.com'];
}

String? _home(Map<String, String> env, bool windows) {
  final value = windows
      ? (env['USERPROFILE'] ?? env['HOMEDRIVE'])
      : env['HOME'];
  return value == null || value.isEmpty ? null : value;
}

String _join(String base, String leaf, [String? more]) {
  final separator = Platform.pathSeparator;
  final prefix = base.endsWith('/') || base.endsWith(r'\')
      ? base
      : '$base$separator';
  return more == null ? '$prefix$leaf' : '$prefix$leaf$separator$more';
}

bool _defaultIsExecutable(String path) {
  try {
    final type = FileSystemEntity.typeSync(path);
    if (type != FileSystemEntityType.file) return false;
    if (Platform.isWindows) return true;
    final mode = FileStat.statSync(path).mode;
    return mode & 0x49 != 0; // owner/group/other execute
  } on FileSystemException {
    return false;
  }
}

List<String> _defaultListDirectory(String path) {
  try {
    return <String>[
      for (final entry in Directory(path).listSync(followLinks: false))
        if (entry is Directory) entry.path,
    ];
  } on FileSystemException {
    return const <String>[];
  }
}

/// Runs `herdr` under [ProcessSupervisor].
///
/// One instance per host, so a host disposal cannot disturb another host's
/// child processes.
class HerdrCliRunner {
  HerdrCliRunner({ProcessSupervisor? supervisor})
    : _supervisor = supervisor ?? ProcessSupervisor();

  final ProcessSupervisor _supervisor;
  bool _disposed = false;

  Future<HerdrProcessResult> call(
    List<String> argv, {
    String? workingDirectory,
    required Duration timeout,
  }) async {
    if (argv.isEmpty) {
      throw ArgumentError.value(argv, 'argv', 'must not be empty');
    }
    if (_disposed) {
      return const HerdrProcessResult(exitCode: -1, spawnError: 'disposed');
    }
    final stdout = _BoundedBytes(_maxCapturedBytes);
    final stderr = _BoundedBytes(_maxCapturedBytes);
    try {
      final process = await _supervisor.start(
        argv.first,
        argv.sublist(1),
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      final stdoutDone = process.stdout.listen(stdout.add).asFuture<void>();
      final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();
      var timedOut = false;
      int code;
      try {
        code = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        timedOut = true;
        await process.cancel();
        code = await process.exitCode;
      }
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      return HerdrProcessResult(
        exitCode: code,
        stdout: stdout.decode(),
        stderr: stderr.decode(),
        timedOut: timedOut,
      );
    } on ProcessException catch (error) {
      return HerdrProcessResult(
        exitCode: -1,
        stderr: error.message,
        spawnError: _looksMissing(error) ? 'ENOENT' : error.message,
      );
    } on StateError {
      // Supervisor disposed while the call was in flight.
      return const HerdrProcessResult(exitCode: -1, spawnError: 'disposed');
    }
  }

  /// Releases children still running. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _supervisor.dispose();
  }

  static bool _looksMissing(ProcessException error) {
    if (error.errorCode == 2) return true;
    final message = error.message.toLowerCase();
    return message.contains('no such file') ||
        message.contains('cannot find the file') ||
        message.contains('not found');
  }
}

/// Byte buffer with a hard cap, so a chatty child cannot exhaust memory.
class _BoundedBytes {
  _BoundedBytes(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  bool _overflowed = false;

  void add(List<int> chunk) {
    if (_overflowed) return;
    final remaining = limit - _builder.length;
    if (chunk.length <= remaining) {
      _builder.add(chunk);
      return;
    }
    if (remaining > 0) _builder.add(chunk.sublist(0, remaining));
    _overflowed = true;
  }

  String decode() => utf8.decode(_builder.takeBytes(), allowMalformed: true);
}
