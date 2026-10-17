import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'command_parser.dart';
import 'portable_filesystem.dart';
import 'shell_backend.dart';

/// A terminal command that a host app can execute for the terminal.
///
/// Returns true when it handled [command] (streaming output/exit through the
/// backend); false when unrecognised so the sandbox can report honestly.
typedef TerminalCommandDelegate =
    Future<bool> Function(SandboxShellBackend backend, String command);

/// One terminal implementation for the whole app.
///
/// Commands run against **real** files under [sandboxRoot] using Dart file IO,
/// so the terminal works in mobile sandboxes that forbid exec'ing a shell.
/// Paths can never escape the root. Unknown commands are offered to
/// [delegate] for the host's supported language toolchain; when
/// no delegate handles them the backend reports an honest unsupported message
/// instead of a misleading exec error.
class SandboxShellBackend extends BaseShellBackend {
  SandboxShellBackend({
    required String sandboxRoot,
    String? startDirectory,
    this.delegate,
    this.label = 'Sandbox',
  }) {
    // A project can live outside the app data directory (imported from an
    // arbitrary path). In that case, confine the sandbox to the start directory
    // itself instead of rejecting it, so the terminal still works for that
    // project while remaining confined.
    final normalizedRoot = p.normalize(p.absolute(sandboxRoot));
    String start;
    if (startDirectory == null) {
      _sandboxRoot = normalizedRoot;
      start = normalizedRoot;
    } else {
      try {
        start = _resolveWithin(normalizedRoot, startDirectory);
        _sandboxRoot = normalizedRoot;
      } on SandboxEscapeException {
        final widened = p.normalize(p.absolute(startDirectory));
        _sandboxRoot = widened;
        start = widened;
      }
    }
    _cwd = start;
  }

  /// Absolute root every resolved path stays inside.
  String get sandboxRoot => _sandboxRoot;
  late final String _sandboxRoot;

  /// Optional command handler for the host's supported toolchain.
  TerminalCommandDelegate? delegate;

  /// Label shown in the prompt/UI.
  final String label;

  late String _cwd;

  @override
  String get shellLabel => label;

  @override
  EscapePolicy get escapePolicy => EscapePolicy.backslashLiteral;

  @override
  String get prompt => '${_displayCwd(_cwd)}>';

  @override
  String get cwd => _cwd;

  @override
  String get displayCwd => _displayCwd(_cwd);

  String _displayCwd(String path) {
    if (p.equals(path, sandboxRoot)) return '~';
    if (p.isWithin(sandboxRoot, path)) {
      return '~/${p.relative(path, from: sandboxRoot).replaceAll(r'\', '/')}';
    }
    return path;
  }

  @override
  String get helpText =>
      '''
$label 终端（应用内沙盒）

文件命令（对应用可访问的真实文件执行）:
  ls / dir [-a] [-l]  列出目录
  cd <目录>           切换目录（支持 ~、相对与 ../，不能越出沙盒）
  pwd                 打印当前目录
  cat <文件>          输出文件内容
  echo <文本>         输出文本
  mkdir [-p] <目录>   创建目录
  touch <文件>        创建空文件
  rm [-r] [-f] <路径> 删除
  cp <源> <目标>      复制文件
  mv <源> <目标>      移动/重命名
  clear / cls         清屏
  help                显示本帮助

语言工具链命令由宿主应用提供，支持范围取决于当前平台。
其它系统命令在当前平台不可用，会给出明确提示。''';

  /// Resolves [target] under the sandbox root, rejecting escapes.
  ///
  /// Throws [SandboxEscapeException] when the result leaves the root.
  String resolveSandboxPath(String target, {bool expandTilde = true}) {
    var path = target;
    if (expandTilde && (path == '~' || path.startsWith('~/') || path.startsWith(r'~\'))) {
      path = path.length == 1 ? sandboxRoot : '$sandboxRoot${path.substring(1)}';
    }
    final absolute = p.isAbsolute(path)
        ? p.normalize(path)
        : p.normalize(p.join(_cwd, path));
    return _resolveWithin(sandboxRoot, absolute);
  }

  static String _resolveWithin(String root, String candidate) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final resolved = p.normalize(p.absolute(candidate));
    if (!p.equals(resolved, normalizedRoot) &&
        !p.isWithin(normalizedRoot, resolved)) {
      throw SandboxEscapeException(candidate);
    }
    return resolved;
  }

  // -------------------------------------------------------------- execution

  @override
  Future<bool> changeDirectory(String target, {bool expandTilde = true}) async {
    final String resolved;
    try {
      resolved = resolveSandboxPath(target, expandTilde: expandTilde);
    } on SandboxEscapeException {
      emitLine('cd: 不能越出沙盒目录: $target', OutputKind.stderr);
      return true;
    }
    final type = FileSystemEntity.typeSync(resolved);
    if (type == FileSystemEntityType.notFound) {
      emitLine('cd: 目录不存在: $target', OutputKind.stderr);
      return true;
    }
    if (type != FileSystemEntityType.directory) {
      emitLine('cd: 不是目录: $target', OutputKind.stderr);
      return true;
    }
    _cwd = resolved;
    return true;
  }

  @override
  bool handlePortableBuiltin(CommandToken name, List<CommandToken> args) {
    // cp/mv are sandbox-specific (not in PortableFilesystem); handle them here.
    if (name.text == 'cp' || name.text == 'mv') {
      _copyOrMove(name.text, args);
      return true;
    }
    if (!PortableFilesystem.handles(name.text)) return false;
    final filesystem = PortableFilesystem(
      cwd: _cwd,
      homeDirectory: sandboxRoot,
      sink: this,
      resolveOverride: (target) {
        try {
          return resolveSandboxPath(target);
        } on SandboxEscapeException {
          emitLine('不能越出沙盒目录: $target', OutputKind.stderr);
          throw const CommandFailure();
        }
      },
    );
    try {
      filesystem.run(name, args);
    } on CommandFailure {
      // Already reported through the sink; keep cwd/state intact.
    }
    return true;
  }

  void _copyOrMove(String command, List<CommandToken> args) {
    final operands = <CommandToken>[];
    for (final arg in args) {
      if (arg.text.startsWith('-') && arg.text.length > 1) {
        emitLine('$command: 暂不支持选项: ${arg.text}', OutputKind.stderr);
        return;
      }
      operands.add(arg);
    }
    if (operands.length != 2) {
      emitLine('$command: 需要源和目标两个路径', OutputKind.stderr);
      return;
    }
    final String from;
    final String to;
    try {
      from = resolveSandboxPath(operands[0].text);
      to = resolveSandboxPath(operands[1].text);
    } on SandboxEscapeException {
      emitLine('$command: 不能越出沙盒目录', OutputKind.stderr);
      return;
    }
    try {
      if (command == 'cp') {
        File(from).copySync(to);
      } else {
        File(from).renameSync(to);
      }
    } on FileSystemException catch (error) {
      final reason = error.osError?.message ?? error.message;
      emitLine('$command: $reason', OutputKind.stderr);
    }
  }

  @override
  Future<void> runExternal(String command) async {
    final handler = delegate;
    if (handler != null && await handler(this, command)) return;
    // Honest unsupported message. A line that reached this point may be a
    // compound shell construct (pipeline/redirection/chaining/glob) which the
    // in-app sandbox deliberately cannot evaluate; name the actual unavailable
    // feature instead of blaming the command name, and fall back to the
    // generic wording only for a plain unknown command.
    final construct = _compoundConstruct(command);
    if (construct != null) {
      emitLine(construct, OutputKind.stderr);
      return;
    }
    final name = CommandParser.tokenize(command).tokens.firstOrNull?.text ?? command;
    emitLine(
      '$name: 当前平台的内置终端不支持该命令（沙盒仅提供文件命令'
      '${delegate == null ? '' : '与宿主应用支持的工具链命令'}）。',
      OutputKind.stderr,
    );
  }

  /// Names the shell construct that forced [command] onto the external path, or
  /// null when the line is a plain unknown command.
  ///
  /// Only consulted for a [CommandSyntax.compound] line (`handleBuiltin`
  /// already routed it here), so the first unquoted operator found is the
  /// feature the user actually asked for. Quoted operators are literal operands
  /// and must not be reported as syntax.
  static String? _compoundConstruct(String command) {
    final line = command.trim();
    var quote = 0; // 0 = none, 1 = single, 2 = double
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote == 1) {
        if (char == "'") quote = 0;
        continue;
      }
      if (quote == 2) {
        if (char == '"') {
          quote = 0;
        } else if (char == r'$' || char == '`') {
          return '当前平台的内置终端不支持命令替换'
              '（`...` / \$(...)）：需要真实 shell 才能执行。';
        }
        continue;
      }
      if (char == "'") {
        quote = 1;
        continue;
      }
      if (char == '"') {
        quote = 2;
        continue;
      }
      if (char == '\r' || char == '\n') {
        return '当前平台的内置终端不支持多行/依次执行命令'
            '（换行、;、&&、||）：需要真实 shell 才能执行。';
      }
      switch (char) {
        case '|':
          if (i + 1 < line.length && line[i + 1] == '|') {
            return '当前平台的内置终端不支持命令串联'
                '（;、&&、||）：需要真实 shell 才能执行多个命令。';
          }
          return '当前平台的内置终端不支持管道'
              '（|）：需要真实 shell 才能把输出连接到下一个命令。';
        case '&':
          return '当前平台的内置终端不支持命令串联或后台执行'
              '（&、&&）：需要真实 shell 才能执行。';
        case ';':
          return '当前平台的内置终端不支持命令串联'
              '（;、&&、||）：需要真实 shell 才能执行多个命令。';
        case '>':
        case '<':
          return '当前平台的内置终端不支持输入/输出重定向'
              '（>、>>、<）：需要真实 shell 才能读写文件流。';
        case '`':
          return '当前平台的内置终端不支持命令替换'
              '（`...` / \$(...)）：需要真实 shell 才能执行。';
        case r'$':
          if (i + 1 < line.length && line[i + 1] == '(') {
            return '当前平台的内置终端不支持命令替换'
                '（`...` / \$(...)）：需要真实 shell 才能执行。';
          }
          continue;
        case '*':
        case '?':
        case '[':
          return '当前平台的内置终端不支持通配符展开'
              '（*、?、[...]）：需要真实 shell 才能匹配多个文件。';
      }
    }
    return null;
  }

  /// Streams a host-provided program (e.g. `javac`/`java` from the language
  /// App's delegate) into the terminal, then records its exit status.
  ///
  /// Called by a [TerminalCommandDelegate]; the exit code is exposed through
  /// [lastExitCode] so the session can show a nonzero status.
  Future<void> runStreams({
    required String title,
    required Stream<String> stdout,
    required Stream<String> stderr,
    required Future<int> exitCode,
    Future<void> Function()? cancel,
  }) async {
    _activeCancel = cancel;
    try {
      final outDone = stdout.listen(
        (line) => emitLine(line, OutputKind.stdout),
        onError: (Object error) => emitLine('$error', OutputKind.stderr),
      ).asFuture<void>();
      final errDone = stderr.listen(
        (line) => emitLine(line, OutputKind.stderr),
        onError: (Object error) => emitLine('$error', OutputKind.stderr),
      ).asFuture<void>();
      // A toolchain can prepare asynchronously before handing over its streams.
      // Preserve an interrupt received while no active cancel callback existed.
      if (cancelRequested && cancel != null) await cancel();
      await Future.wait<void>([outDone, errDone]);
      final code = await exitCode;
      if (!cancelRequested) lastExitCode = code;
    } finally {
      _activeCancel = null;
    }
  }

  Future<void> Function()? _activeCancel;

  /// Runs [command] on a real-process [shell] and mirrors its output and exit
  /// status into this sandbox.
  ///
  /// Used by the desktop fallback in [createSandboxShell]: [shell] emits on its
  /// own stream, which nobody else listens to, so without this forwarding every
  /// desktop-only tool (`git`, `grep`, a pipeline) would run silently and its
  /// status would be lost. The chunks are re-emitted through this backend so
  /// the session renders them and [lastExitCode] stays truthful.
  Future<void> delegateToProcessShell(
    ShellBackend shell,
    String command,
  ) async {
    final subscription = shell.output.listen(
      (chunk) => emit(chunk.text, chunk.kind),
      onError: (Object error) => emitLine('$error', OutputKind.stderr),
    );
    // Interrupt must reach the real process, not just this wrapper.
    _activeProcessShell = shell;
    try {
      await shell.execute(command);
      if (!cancelRequested) lastExitCode = shell.lastExitCode;
    } finally {
      _activeProcessShell = null;
      await subscription.cancel();
    }
  }

  ShellBackend? _activeProcessShell;

  @override
  Future<void> onInterrupt() async {
    final processShell = _activeProcessShell;
    if (processShell != null) {
      // The real shell owns the `^C` banner (its own interrupt emits it), so do
      // not print a second one here.
      await processShell.interrupt();
      return;
    }
    final cancel = _activeCancel;
    if (cancel != null) {
      emitLine('^C', OutputKind.system);
      await cancel();
    }
  }
}

/// Thrown when a path would leave the sandbox root.
class SandboxEscapeException implements Exception {
  const SandboxEscapeException(this.path);

  final String path;

  @override
  String toString() => 'SandboxEscapeException: $path escapes the sandbox root';
}
