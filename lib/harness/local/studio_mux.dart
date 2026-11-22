/// StudioMux：Studio 自己持有的本机终端会话。
///
/// 每个会话是一个 PTY 子进程。Mux 持有进程、滚动缓冲和状态；界面只看到
/// 契约里的 [HarnessTerminalChannel] 与状态监听。
///
/// 退出路径遵循 process-lifecycle：取消是幂等的，先 TERM 后 KILL，Windows
/// 走 `taskkill /T /F`。关闭视图不结束会话，[MuxSession.stop] 才结束。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/process_supervisor.dart';
import '../harness_host.dart';
import 'pty_process.dart';
import 'terminal_scrollback.dart';

/// Mux 事件类型。
enum MuxEventKind { started, status, exited }

/// 一条 Mux 事件。
@immutable
class MuxEvent {
  const MuxEvent({required this.kind, required this.session});

  final MuxEventKind kind;
  final MuxSession session;
}

/// 一个本机终端会话。
class MuxSession implements HarnessTerminalChannel {
  MuxSession._({
    required this.id,
    required this.providerId,
    required this.title,
    required this.workingDirectory,
    required this.startedAt,
    required this.columns,
    required this.rows,
    required int scrollbackBytes,
    required Duration idleAfter,
    required Duration stopTimeout,
    required PtyProcess process,
    required void Function(MuxEventKind kind) onEvent,
  }) : scrollback = TerminalScrollback(maxBytes: scrollbackBytes),
       _process = process,
       _idleAfter = idleAfter,
       _stopTimeout = stopTimeout,
       _onEvent = onEvent;

  final String id;
  final String providerId;
  final String title;
  final String workingDirectory;
  final DateTime startedAt;

  /// 最近一次申请的终端尺寸。
  int columns;
  int rows;

  /// 保留的滚动输出，用于重新挂载视图。
  final TerminalScrollback scrollback;

  final PtyProcess _process;
  final Duration _idleAfter;
  final Duration _stopTimeout;
  final void Function(MuxEventKind kind) _onEvent;
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  final ValueNotifier<HarnessSessionStatus> _status =
      ValueNotifier<HarnessSessionStatus>(HarnessSessionStatus.working);

  StreamSubscription<Uint8List>? _subscription;
  Timer? _idleTimer;
  Future<int>? _exitFuture;
  Future<void>? _stopFuture;
  int? _exitCode;
  bool _finished = false;

  /// 会话状态。界面只读。
  ValueListenable<HarnessSessionStatus> get status => _status;

  /// 原始输出。新订阅者不会收到历史；历史在 [scrollback] 里。
  @override
  Stream<Uint8List> get output => _output.stream;

  /// 退出码；仍在运行时为 null。
  int? get exitCode => _exitCode;

  bool get isRunning => !_finished;

  /// 进程 id；测试与诊断用。
  int get pid => _process.pid;

  void _start() {
    _subscription = _process.output.listen(
      _onOutput,
      onError: (Object error, StackTrace stackTrace) {
        _output.addError(error, stackTrace);
        _finish(null);
      },
      onDone: () => _finish(null),
    );
    _exitFuture = _process.exitCode.then(
      (int code) {
        _finish(code);
        return code;
      },
      onError: (Object error, StackTrace stackTrace) {
        _finish(null);
        return -1;
      },
    );
    _restartIdleTimer();
    _onEvent(MuxEventKind.started);
  }

  void _onOutput(Uint8List chunk) {
    if (_finished) return;
    scrollback.add(chunk);
    if (!_output.isClosed) _output.add(chunk);
    _status.value = HarnessSessionStatus.working;
    _restartIdleTimer();
  }

  /// 安静一段时间后视为空闲。持续输出期间状态保持 working。
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleAfter, () {
      if (_finished) return;
      if (_status.value == HarnessSessionStatus.working) {
        _status.value = HarnessSessionStatus.idle;
        _onEvent(MuxEventKind.status);
      }
    });
  }

  void _finish(int? code) {
    // 输出关闭与退出码可能先后到达；先到的一侧不能丢掉真实的退出码。
    if (code != null) _exitCode = code;
    if (_finished) return;
    _finished = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _status.value = HarnessSessionStatus.exited;
    _onEvent(MuxEventKind.exited);
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _subscription = null;
    if (!_output.isClosed) unawaited(_output.close());
  }

  /// 写入用户输入。
  @override
  void write(Uint8List data) {
    if (_finished) return;
    _process.write(data);
  }

  /// 写入一段文本并回车，等价于在终端里输入一行。
  ///
  /// 必须按 UTF-8 编码：`String.codeUnits` 是 UTF-16 码元，直接塞进
  /// [Uint8List] 只保留低 8 位，中文会被截成乱码（'复' 的低字节恰好是 0x0D，
  /// 也就是回车）。
  void sendLine(String text) {
    write(Uint8List.fromList(<int>[...utf8.encode(text), 13]));
  }

  /// 调整终端尺寸。
  @override
  bool resize(int columns, int rows) {
    if (_finished) return false;
    final applied = _process.resize(columns, rows);
    if (applied) {
      this.columns = columns;
      this.rows = rows;
    }
    return applied;
  }

  /// 等待进程退出。
  Future<int> get exited => _exitFuture ?? Future<int>.value(_exitCode ?? -1);

  /// 结束会话。重复调用返回同一个 future。
  ///
  /// 调用方必须先取得用户确认；Mux 自身不再询问。
  Future<void> stop() {
    if (_stopFuture != null) return _stopFuture!;
    _stopFuture = _stopInternal();
    return _stopFuture!;
  }

  Future<void> _stopInternal() async {
    if (!_finished) {
      try {
        await _process.terminate();
      } on Object {
        // 进程可能已经退出；下面的状态更新仍然有效。
      }
      try {
        _exitCode = await _process.exitCode.timeout(_stopTimeout);
      } on Object {
        // 退出码未知时保留 null。
      }
    }
    await _subscription?.cancel();
    _subscription = null;
    _finish(_exitCode);
  }

  /// 释放本视图持有的资源。进程由 [StudioMux] 管理。
  Future<void> dispose() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (!_output.isClosed) await _output.close();
    _status.dispose();
  }
}

/// 本机会话管理器。
class StudioMux {
  StudioMux({
    PtyLauncher? launcher,
    ProcessSupervisor? supervisor,
    int scrollbackBytes = kDefaultScrollbackBytes,
    Duration idleAfter = const Duration(milliseconds: 900),
    Duration stopTimeout = defaultStopTimeout,
    String Function()? idFactory,
    this.maxExitedSessions = 8,
  }) : _scrollbackBytes = scrollbackBytes,
       _idleAfter = idleAfter,
       _stopTimeout = stopTimeout,
       _idFactory =
           idFactory ??
           (() =>
               'mux-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'),
       _ownsSupervisor = launcher == null,
       _ownsLauncher = launcher == null {
    _supervisor = supervisor ?? ProcessSupervisor();
    _launcher = launcher ?? createPtyLauncher(supervisor: _supervisor);
  }

  /// 保留多少个已退出的会话（含各自的滚动缓冲）。
  ///
  /// 每个会话持有一份滚动缓冲，不设上限就是单调增长的泄漏；已退出会话只
  /// 用于“刚结束还能回看”，超过这个数量按退出顺序淘汰。
  final int maxExitedSessions;

  /// 等待进程退出的上限。
  ///
  /// 释放时逐个会话串行等待，所以这个值同时也是“释放 N 个会话最多多久”的
  /// 一份量。进程不响应 TERM 时它决定 teardown 的上限，测试可以注入更短的
  /// 值来断言这一点。
  static const Duration defaultStopTimeout = Duration(seconds: 5);

  final int _scrollbackBytes;
  final Duration _idleAfter;
  final Duration _stopTimeout;
  final String Function() _idFactory;
  final bool _ownsSupervisor;
  final bool _ownsLauncher;
  final Map<String, MuxSession> _sessions = <String, MuxSession>{};
  final StreamController<MuxEvent> _events =
      StreamController<MuxEvent>.broadcast();
  late final ProcessSupervisor _supervisor;
  late final PtyLauncher _launcher;
  bool _disposed = false;

  /// PTY 后端名：`script`、`pipe` 或 `unsupported`。
  String get strategy => _launcher.strategy;

  /// 当前平台能否启动本机会话。
  bool get isSupported => _launcher.strategy != 'unsupported';

  /// 子进程是否看到真实终端。
  bool get allocatesTerminal => _launcher.allocatesTerminal;

  /// 后端是否支持运行期改尺寸。
  bool get supportsResize => _launcher.supportsResize;

  /// 会话事件流，用于界面刷新。广播流不缓存。
  Stream<MuxEvent> get events => _events.stream;

  /// 当前会话，按启动顺序。
  List<MuxSession> get sessions =>
      List<MuxSession>.unmodifiable(_sessions.values.toList(growable: false));

  MuxSession? sessionFor(String id) => _sessions[id];

  /// 启动一个会话。
  Future<MuxSession> start({
    required String providerId,
    required String executable,
    List<String> arguments = const <String>[],
    String? workingDirectory,
    Map<String, String>? environment,
    String? title,
    int columns = 80,
    int rows = 24,
  }) async {
    if (_disposed) throw StateError('StudioMux 已释放');
    if (!isSupported) {
      throw UnsupportedError('当前平台不支持本机终端会话');
    }
    final process = await _launcher.spawn(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      columns: columns,
      rows: rows,
    );
    late final MuxSession session;
    session = MuxSession._(
      id: _idFactory(),
      providerId: providerId,
      title: title ?? providerId,
      workingDirectory: workingDirectory ?? '',
      startedAt: DateTime.now(),
      columns: columns,
      rows: rows,
      scrollbackBytes: _scrollbackBytes,
      idleAfter: _idleAfter,
      stopTimeout: _stopTimeout,
      process: process,
      onEvent: (MuxEventKind kind) => _emitEvent(session, kind),
    );
    _sessions[session.id] = session;
    session._start();
    return session;
  }

  void _emitEvent(MuxSession session, MuxEventKind kind) {
    if (kind == MuxEventKind.exited) _pruneExited(except: session);
    if (_events.isClosed) return;
    _events.add(MuxEvent(kind: kind, session: session));
  }

  /// 只保留最近 [maxExitedSessions] 个已退出会话。
  ///
  /// 淘汰时释放滚动缓冲（每个会话默认 512 KiB），但不 dispose 会话对象：
  /// 界面可能还拿着它的句柄在渲染。进程已经结束，定时器与订阅也都已释放，
  /// 丢引用后剩下的内存由 GC 回收。
  /// [except] 是刚发出事件的那个会话，不能在自己回调里被回收。
  void _pruneExited({MuxSession? except}) {
    final exited = <MuxSession>[
      for (final session in _sessions.values)
        if (!session.isRunning && !identical(session, except)) session,
    ];
    if (exited.length <= maxExitedSessions) return;
    final removeCount = exited.length - maxExitedSessions;
    for (final session in exited.take(removeCount)) {
      _sessions.remove(session.id);
      session.scrollback.clear();
    }
  }

  /// 结束一个会话并等待进程退出。
  Future<void> stop(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    await session.stop();
  }

  /// 释放全部会话与后端。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final session in _sessions.values.toList(growable: false)) {
      await session.stop();
      await session.dispose();
    }
    _sessions.clear();
    await _events.close();
    if (_ownsLauncher) {
      // 自建 launcher 也拥有那个共享的 Supervisor。
      await _launcher.dispose();
    } else if (_ownsSupervisor) {
      await _supervisor.dispose();
    }
  }
}
