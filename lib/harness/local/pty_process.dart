/// PTY 会话的原始字节通道。
///
/// 子进程的输出按块转发，从不按行切分。上层 UI 交给 xterm 或
/// [StudioMux] 的滚动缓冲处理。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/process_supervisor.dart';

/// 一个已启动的 PTY 会话。
abstract class PtyProcess {
  /// 操作系统的进程 id。
  int get pid;

  /// 子进程的合并输出，包含转义序列。
  Stream<Uint8List> get output;

  /// 进程结束时的退出码，取消时也会完成。
  Future<int> get exitCode;

  /// 写入用户输入。
  void write(List<int> data);

  /// 调整终端尺寸；当前后端不支持时返回 false。
  bool resize(int columns, int rows);

  /// 结束进程并等待退出。
  Future<void> terminate();
}

/// 创建 PTY 会话的策略。
///
/// 抽象成策略有两个原因：桌面平台各有各的实现方式，测试也能用假的
/// launcher 驱动 StudioMux，不必启动真实子进程。
abstract class PtyLauncher {
  /// 策略名，写进诊断信息：`conpty`、`script`、`pipe`、`unsupported`。
  String get strategy;

  /// 子进程是否真的看到终端设备。
  bool get allocatesTerminal;

  /// 是否支持运行期改尺寸。
  bool get supportsResize;

  Future<PtyProcess> spawn({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  });

  /// 释放后端自己持有的资源（Supervisor 及其子进程）。幂等。
  Future<void> dispose();
}

/// 当前平台没有可用后端。
class UnsupportedPtyLauncher implements PtyLauncher {
  const UnsupportedPtyLauncher();

  @override
  String get strategy => 'unsupported';

  @override
  bool get allocatesTerminal => false;

  @override
  bool get supportsResize => false;

  @override
  Future<PtyProcess> spawn({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) {
    throw UnsupportedError('当前平台不支持本机终端会话');
  }

  @override
  Future<void> dispose() async {}
}

/// macOS 与 Linux 用系统 `script` 申请伪终端。
///
/// `script` 自己持有 pty 主设备，因此子进程看到的是真实终端：换行、回显
/// 和信号语义都正常。代价是运行期改尺寸无法送达主设备，[resize] 恒为
/// false；初始尺寸由命令开头的 `stty` 设定。
class ScriptPtyLauncher implements PtyLauncher {
  ScriptPtyLauncher({
    ProcessSupervisor? supervisor,
    bool? isMacOS,
    String? shellExecutable,
  }) : _supervisor = supervisor ?? ProcessSupervisor(),
       _ownsSupervisor = supervisor == null,
       isMacOS = isMacOS ?? Platform.isMacOS,
       shellExecutable = shellExecutable ?? '/bin/sh';

  final ProcessSupervisor _supervisor;
  final bool _ownsSupervisor;
  final bool isMacOS;
  final String shellExecutable;

  @override
  String get strategy => 'script';

  @override
  bool get allocatesTerminal => true;

  @override
  bool get supportsResize => false;

  @override
  Future<PtyProcess> spawn({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async {
    final command = buildCommand(
      executable: executable,
      arguments: arguments,
      columns: columns,
      rows: rows,
    );
    // util-linux 的 script 用 `-c` 传命令、`-e` 传子进程退出码；BSD 的
    // script（macOS）把命令当普通参数。
    final argv = isMacOS
        ? <String>['-q', '/dev/null', shellExecutable, '-c', command]
        : <String>['-q', '-e', '-f', '-c', command, '/dev/null'];
    final process = await _supervisor.start(
      'script',
      argv,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return SupervisedPtyProcess(ManagedPtyChild(process));
  }

  /// 组装在 pty 里执行的 shell 命令。
  ///
  /// `stty` 先设定初始行列，失败也不影响启动；随后 `exec` 让子进程替换
  /// shell，信号与退出码因此直达。
  static String buildCommand({
    required String executable,
    required List<String> arguments,
    required int columns,
    required int rows,
  }) {
    final buffer = StringBuffer()
      ..write('stty cols ')
      ..write(columns)
      ..write(' rows ')
      ..write(rows)
      ..write(' 2>/dev/null; exec ')
      ..write(quoteArgument(executable));
    for (final argument in arguments) {
      buffer
        ..write(' ')
        ..write(quoteArgument(argument));
    }
    return buffer.toString();
  }

  /// POSIX shell 单引号转义。
  static String quoteArgument(String value) {
    if (value.isEmpty) return "''";
    if (_safeArgument.hasMatch(value)) return value;
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static final RegExp _safeArgument = RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$');

  /// 只释放自己创建的 Supervisor；外部注入的由调用方负责。
  @override
  Future<void> dispose() async {
    if (_ownsSupervisor) await _supervisor.dispose();
  }
}

/// 用普通管道承载子进程。子进程看不到终端设备。
///
/// 该后端是回退路径：Windows 没有原生 ConPTY 绑定，交互式 TUI 会退化成
/// 管道模式。批处理命令（`.cmd`、`.bat`）通过 `cmd.exe /c` 启动。
class PipePtyLauncher implements PtyLauncher {
  PipePtyLauncher({ProcessSupervisor? supervisor, bool? isWindows})
    : _supervisor = supervisor ?? ProcessSupervisor(),
      _ownsSupervisor = supervisor == null,
      isWindows = isWindows ?? Platform.isWindows;

  final ProcessSupervisor _supervisor;
  final bool _ownsSupervisor;
  final bool isWindows;

  @override
  String get strategy => 'pipe';

  @override
  bool get allocatesTerminal => false;

  @override
  bool get supportsResize => false;

  @override
  Future<PtyProcess> spawn({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async {
    final (String command, List<String> args) = buildInvocation(
      executable: executable,
      arguments: arguments,
      isWindows: isWindows,
    );
    final process = await _supervisor.start(
      command,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return SupervisedPtyProcess(ManagedPtyChild(process));
  }

  /// 解析实际启动的命令行。
  ///
  /// Windows 的 `.cmd`、`.bat` 不是可执行文件，必须交给 `cmd.exe /c`，
  /// 否则 `Process.start` 直接失败。
  @visibleForTesting
  static (String, List<String>) buildInvocation({
    required String executable,
    required List<String> arguments,
    required bool isWindows,
  }) {
    if (isWindows && _isBatchFile(executable)) {
      return ('cmd.exe', <String>['/c', executable, ...arguments]);
    }
    return (executable, arguments);
  }

  static bool _isBatchFile(String executable) {
    final lower = executable.toLowerCase();
    return lower.endsWith('.cmd') || lower.endsWith('.bat');
  }

  @override
  Future<void> dispose() async {
    if (_ownsSupervisor) await _supervisor.dispose();
  }
}

/// [SupervisedPtyProcess] 需要的最小子进程能力。
///
/// 抽象出来是为了能用两个普通 stream 验证“stdout 与 stderr 都转发”，
/// 不必真的启动一个进程。
abstract class PtyChildProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  /// 子进程的标准输入。已退出时写会抛，调用方自行忽略。
  StreamSink<List<int>> get stdin;

  Future<void> cancel();
}

/// 把 [ManagedProcess] 接成 [PtyChildProcess]。
class ManagedPtyChild implements PtyChildProcess {
  ManagedPtyChild(this._process);

  final ManagedProcess _process;

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  StreamSink<List<int>> get stdin => _process.stdin;

  @override
  Future<void> cancel() => _process.cancel();
}

/// 由子进程托管的 PTY 进程。
///
/// 取消路径沿用 process-lifecycle：Windows 先 `taskkill /T /F`，POSIX 先
/// TERM 再 KILL，并等待退出码。
class SupervisedPtyProcess implements PtyProcess {
  SupervisedPtyProcess(PtyChildProcess process) : _process = process {
    _stdoutSubscription = _process.stdout.listen(
      (List<int> chunk) => _append(chunk),
      onError: _streamError,
      onDone: _streamFinished,
    );
    // 真实 pty 下 stdout 与 stderr 是同一设备，但 Windows 的 pipe 后端把它们
    // 分成两个管道。不订阅 stderr 就等于丢掉 CLI 的报错与进度，因此两个都转发。
    _stderrSubscription = _process.stderr.listen(
      (List<int> chunk) => _append(chunk),
      onError: _streamError,
      onDone: _streamFinished,
    );
  }

  final PtyChildProcess _process;
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  int _openStreams = 2;
  bool _terminated = false;

  void _append(List<int> chunk) {
    if (_terminated || _output.isClosed || chunk.isEmpty) return;
    _output.add(Uint8List.fromList(chunk));
  }

  void _streamError(Object error, StackTrace stackTrace) {
    if (_terminated || _output.isClosed) return;
    _output.addError(error, stackTrace);
  }

  /// 两个管道都结束才关闭输出，避免 stderr 尾巴被截掉。
  void _streamFinished() {
    _openStreams--;
    if (_openStreams <= 0 && !_output.isClosed) unawaited(_output.close());
  }

  @override
  int get pid => _process.pid;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(List<int> data) {
    if (_terminated || data.isEmpty) return;
    try {
      _process.stdin.add(data);
    } on StateError {
      // 子进程已关闭输入，用户的按键不再有接收方。
    } on IOException {
      // 同上：写入一个已退出的进程不是错误。
    }
  }

  @override
  bool resize(int columns, int rows) => false;

  @override
  Future<void> terminate() async {
    if (_terminated) return;
    _terminated = true;
    await _process.cancel();
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;
    if (!_output.isClosed) await _output.close();
  }
}

/// 按平台创建默认后端。
///
/// 桌面平台可用；移动端、Web 与鸿蒙由 [UnsupportedPtyLauncher] 拒绝启动。
/// 三个平台标志可注入，测试因此不必运行在桌面系统上。
PtyLauncher createPtyLauncher({
  ProcessSupervisor? supervisor,
  bool? isWindows,
  bool? isMacOS,
  bool? isLinux,
}) {
  final windows = isWindows ?? Platform.isWindows;
  final macos = isMacOS ?? Platform.isMacOS;
  final linux = isLinux ?? Platform.isLinux;
  final shared = supervisor ?? ProcessSupervisor();
  if (windows) return PipePtyLauncher(supervisor: shared, isWindows: true);
  if (macos || linux) {
    return ScriptPtyLauncher(supervisor: shared, isMacOS: macos);
  }
  return const UnsupportedPtyLauncher();
}

/// 把字节解码成可显示的文本，坏字节替换而不抛异常。
String decodeTerminalBytes(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);
