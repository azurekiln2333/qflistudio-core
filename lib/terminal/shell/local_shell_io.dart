import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/process_supervisor.dart';
import 'command_parser.dart';
import 'portable_filesystem.dart';
import 'sandbox_shell_backend.dart';
import 'shell_backend.dart';

/// Creates a shell backed by real OS processes.
///
/// Each command is spawned as its own process with the session's working
/// directory, so `cd` is tracked in Dart instead of relying on a persistent
/// interactive shell. Output is streamed as it is produced.
ShellBackend createLocalShell({String? workingDirectory}) =>
    LocalShellBackend(workingDirectory: workingDirectory);

/// Creates the unified in-app sandbox terminal backend used across the app.
///
/// Commands run against real files under [sandboxRoot] via Dart file IO, so the
/// terminal works where exec is forbidden. Desktop additionally forwards
/// non-built-in commands to the real shell so ordinary tools keep working;
/// [delegate] (the Java app) can claim `java`/`javac` on any platform.
ShellBackend createSandboxShell({
  required String sandboxRoot,
  String? startDirectory,
  String label = 'Sandbox',
  TerminalCommandDelegate? delegate,
}) {
  final desktopShell = localShellAvailable()
      ? LocalShellBackend(workingDirectory: startDirectory ?? sandboxRoot)
      : null;
  final sandbox = SandboxShellBackend(
    sandboxRoot: sandboxRoot,
    startDirectory: startDirectory,
    label: label,
    delegate: (backend, command) async {
      if (delegate != null && await delegate(backend, command)) return true;
      // Desktop fallback: let the real shell run a tool that is not a sandbox
      // built-in (e.g. git/grep), keeping desktop parity. Mobile has none. The
      // shell's output must be mirrored into the sandbox; simply calling
      // `execute` would drop everything and the command would look silent.
      final shell = desktopShell;
      if (shell != null) {
        await backend.delegateToProcessShell(shell, command);
        return true;
      }
      return false;
    },
  );
  return sandbox;
}

/// Whether the local shell can be expected to work on this platform.
///
/// Desktop platforms ship a shell the app is allowed to exec. The mobile
/// sandboxes do not: iOS has no `/bin/sh` at all, and Android and HarmonyOS
/// commonly have one that the app process is forbidden to exec, which surfaces
/// as `ProcessException: Permission denied` on the user's very first command.
///
/// Deliberately synchronous — it is consulted while a session is being created,
/// and awaiting a process spawn there would make startup depend on spawning a
/// process. The guess is not trusted blindly: [_resolveShell] still probes for
/// real before the first command runs, so a wrong answer degrades into a clear
/// message rather than a raw exception.
///
/// Reads `defaultTargetPlatform` rather than `Platform.is*` so it agrees with
/// the rest of the widget tree about which platform this is. `dart:io`'s
/// `Platform` reports the *host* OS, which is the wrong answer the moment the
/// app is cross-compiled — and it cannot be overridden in a test, so the branch
/// would be untestable.
bool localShellAvailable() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return true;
    // HarmonyOS: the shell at /bin/sh or /system/bin/sh usually exists but the
    // app is not permitted to exec it, so this is a no as well.
    case TargetPlatform.ohos:
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

String? _resolvedShell;
Future<String?>? _resolveInFlight;

/// First shell binary that actually runs, or null when none of them do.
Future<String?> _resolveShell() {
  if (_resolvedShell != null) return Future<String?>.value(_resolvedShell);
  return _resolveInFlight ??= _probeShells();
}

Future<String?> _probeShells() async {
  for (final candidate in _shellCandidates()) {
    try {
      final process = await Process.start(
        candidate,
        _probeArgs(candidate),
        runInShell: false,
      );
      if (await process.exitCode == 0) {
        _resolvedShell = candidate;
        return candidate;
      }
    } catch (_) {
      // Not executable here; try the next candidate.
    }
  }
  return null;
}

/// Shell binaries to try, best first.
///
/// `$SHELL` wins when the platform sets it. The rest are the usual locations;
/// Android and HarmonyOS keep their shell under `/system/bin` or `/vendor/bin`
/// rather than `/bin`, and a bare `sh` on `PATH` is a last resort.
List<String> _shellCandidates() {
  if (Platform.isWindows) return const <String>['powershell.exe'];
  final env = Platform.environment['SHELL'];
  return <String>[
    if (env != null && env.isNotEmpty) env,
    '/bin/sh',
    '/system/bin/sh',
    '/vendor/bin/sh',
    'sh',
  ];
}

List<String> _probeArgs(String binary) => binary == 'powershell.exe'
    ? const <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'exit 0',
      ]
    : const <String>['-c', 'exit 0'];

class LocalShellBackend extends BaseShellBackend {
  LocalShellBackend({String? workingDirectory}) {
    cwd = workingDirectory ?? homeDirectory ?? Directory.current.path;
  }

  static const String _powerShellPreamble =
      '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
      r'$OutputEncoding=[System.Text.Encoding]::UTF8;';

  final ProcessSupervisor _processSupervisor = ProcessSupervisor();
  ManagedProcess? _process;

  /// Completes with the started process, or null when startup failed/was
  /// cancelled. [interrupt] awaits this so it can cancel a process that is
  /// still being spawned.
  Completer<ManagedProcess?>? _startPending;

  /// Directory that `~` stands for.
  ///
  /// Falls back to the process directory when the platform exports neither
  /// `HOME` nor `USERPROFILE`: Android and HarmonyOS app processes usually get
  /// neither, and a prompt reading `/storage/Users/cu $` is both long and
  /// uninformative. The directory the shell starts in is the honest answer for
  /// "where am I at home" on those platforms.
  @override
  String? get homeDirectory => _home;
  late final String? _home = _resolveHome();

  static String? _resolveHome() {
    final env = Platform.environment;
    final home = Platform.isWindows
        ? (env['USERPROFILE'] ?? env['HOMEDRIVE'])
        : env['HOME'];
    if (home != null && home.isNotEmpty) return home;
    return Directory.current.path;
  }

  @override
  String get shellLabel {
    if (Platform.isWindows) return 'PowerShell';
    final resolved = _resolvedShell;
    if (resolved != null) return resolved.split(RegExp(r'[/\\]')).last;
    final shell = Platform.environment['SHELL'];
    if (shell == null || shell.isEmpty) return 'sh';
    return shell.split(RegExp(r'[/\\]')).last;
  }

  @override
  String get prompt => Platform.isWindows ? '$cwd>' : '$cwd \$';

  @override
  bool get canInterrupt => true;

  @override
  String get helpText =>
      '''
QFLI 终端 · $shellLabel

内置命令（由应用处理）:
  cd <目录>    切换当前目录，支持 ~ 与相对路径
  pwd          打印当前目录
  clear / cls  清空当前终端
  help         显示这份帮助

其他命令会交给系统 $shellLabel 执行。''';

  @override
  EscapePolicy get escapePolicy => Platform.isWindows
      ? EscapePolicy.backslashLiteral
      : EscapePolicy.backslashEscapes;

  List<String> _buildCommand(String shell, String command) {
    if (Platform.isWindows) {
      return <String>[
        shell,
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '$_powerShellPreamble$command',
      ];
    }
    return <String>[shell, '-c', command];
  }

  @override
  Future<void> runExternal(String command) async {
    final startPending = Completer<ManagedProcess?>();
    _startPending = startPending;
    try {
      final shell = await _resolveShell();
      if (cancelRequested) {
        startPending.complete(null);
        return;
      }
      if (shell == null) {
        startPending.complete(null);
        emitLine('当前平台不允许应用执行系统命令，便携命令（ls/cd/cat 等）仍可使用。', OutputKind.stderr);
        return;
      }

      // Never fall back to an unrelated process directory: if the session cwd
      // is gone, report it instead of silently running elsewhere.
      final directory = Directory(cwd);
      if (!directory.existsSync()) {
        startPending.complete(null);
        emitLine('无法执行：当前目录不存在：$cwd', OutputKind.stderr);
        return;
      }
      final workingDirectory = cwd;

      final argv = _buildCommand(shell, command);
      final ManagedProcess process;
      try {
        process = await _processSupervisor.start(
          argv.first,
          argv.sublist(1),
          workingDirectory: workingDirectory,
          runInShell: false,
        );
      } on ProcessException catch (error) {
        startPending.complete(null);
        // Report which binary and why, instead of letting a bare
        // "ProcessException: Permission denied" reach the user.
        emitLine('无法启动 $shell：${error.message}', OutputKind.stderr);
        emitLine('该平台可能不允许应用执行系统命令，可以改用「沙盒终端」。', OutputKind.system);
        return;
      }

      // An interrupt may have arrived while the process was being spawned; when
      // so, cancel it immediately instead of running it to completion.
      if (cancelRequested) {
        startPending.complete(null);
        await process.cancel();
        return;
      }
      _process = process;
      startPending.complete(process);

      const decoder = Utf8Decoder(allowMalformed: true);
      await Future.wait<void>(<Future<void>>[
        process.stdout
            .transform(decoder)
            .forEach((chunk) => emit(chunk, OutputKind.stdout)),
        process.stderr
            .transform(decoder)
            .forEach((chunk) => emit(chunk, OutputKind.stderr)),
      ]);

      final exitCode = await process.exitCode;
      _process = null;
      if (cancelRequested) {
        // A cancelled command's status is not a program result.
        lastExitCode = null;
        return;
      }
      // Expose the real numeric status; the pane renders the concise English
      // line, so the backend must not emit its own localized banner.
      lastExitCode = exitCode;
    } finally {
      if (!startPending.isCompleted) startPending.complete(null);
      if (identical(_startPending, startPending)) _startPending = null;
    }
  }

  @override
  Future<bool> changeDirectory(String target, {bool expandTilde = true}) async {
    final resolved = resolvePath(target, expandTilde: expandTilde);
    final directory = Directory(resolved);

    if (!directory.existsSync()) {
      emitLine('cd: 目录不存在: $target', OutputKind.stderr);
      return true;
    }
    if (FileSystemEntity.typeSync(resolved) != FileSystemEntityType.directory) {
      emitLine('cd: 不是目录: $target', OutputKind.stderr);
      return true;
    }
    cwd = directory.absolute.path;
    return true;
  }

  @override
  bool handlePortableBuiltin(CommandToken name, List<CommandToken> args) {
    if (!PortableFilesystem.handles(name.text)) return false;
    final filesystem = PortableFilesystem(
      cwd: cwd,
      homeDirectory: homeDirectory,
      sink: this,
    );
    try {
      filesystem.run(name, args);
    } on CommandFailure {
      // PortableFilesystem already emitted the user-facing error; swallow only
      // this deliberate marker so unrelated errors still surface.
    }
    return true;
  }

  /// Resolves [target] the way a shell would: a leading `~` expands to the
  /// home directory when [expandTilde] is true, rooted paths are used as-is
  /// and anything else is relative to the session's current directory. Never
  /// falls back to the host process directory.
  String resolvePath(String target, {bool expandTilde = true}) {
    var path = target;

    if (expandTilde &&
        (path == '~' || path.startsWith('~/') || path.startsWith(r'~\'))) {
      final home = homeDirectory;
      if (home != null && home.isNotEmpty) {
        path = path.length == 1 ? home : '$home${path.substring(1)}';
      }
    }

    if (_isRooted(path)) return Directory(path).absolute.path;

    return Directory(
      '$cwd${Platform.pathSeparator}'
      '${path.replaceAll('/', Platform.pathSeparator)}',
    ).absolute.path;
  }

  bool _isRooted(String path) {
    if (path.startsWith('/') || path.startsWith(r'\\')) return true;
    return RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path);
  }

  @override
  Future<void> onInterrupt() async {
    // requestCancel() already set the flag at the base level; just cancel the
    // process (or await startup so a process that appears late is cancelled).
    emitLine('^C', OutputKind.system);

    final pending = _startPending;
    if (pending != null && !pending.isCompleted) {
      // Startup is still in flight; wait for the handle (or failure) so we can
      // cancel a process that appears after this interrupt arrived.
      final process = await pending.future;
      if (process != null) {
        await process.cancel();
        if (identical(_process, process)) _process = null;
      }
      return;
    }

    final process = _process;
    if (process == null) return;
    await process.cancel();
    _process = null;
  }

  @override
  Future<void> shutdown() async {
    await _processSupervisor.dispose();
    _process = null;
    await super.shutdown();
  }
}
