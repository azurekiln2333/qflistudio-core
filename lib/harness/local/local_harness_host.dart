/// 本机 harness 主机。
///
/// 桌面版把 Studio 自己启动的 PTY 会话和历史日志会话合成一个列表。手机、
/// Web 与鸿蒙没有本机 PTY，状态为 [HarnessHostState.unsupported]，界面只
/// 显示已绑定电脑与内置 Agent。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../harness_host.dart';
import 'live_log_follower.dart';
import 'log_reader_factory.dart';
import 'provider_registry.dart';
import 'pty_process.dart';
import 'studio_mux.dart';
import 'transcript_log_reader.dart';

/// 一条日志会话的缓存项。
class _LogEntry {
  _LogEntry({required this.reader, required this.ref, required this.status});

  final TranscriptLogReader reader;
  final LogSessionRef ref;
  final HarnessSessionStatus status;

  HarnessSessionInfo get info => HarnessSessionInfo(
    id: ref.id,
    hostId: LocalHarnessHost.hostId,
    providerId: ref.providerId,
    title: ref.displayTitle,
    cwd: ref.workingDirectory,
    status: status,
    capabilities: const <HarnessCapability>{HarnessCapability.transcript},
    updatedAt: ref.updatedAt,
    sourceRef: ref.filePath,
  );
}

/// 本机终端会话句柄。
class _LiveSessionHandle implements HarnessSessionHandle {
  _LiveSessionHandle(
    this._session, {
    LiveLogFollower? follower,
    bool? hasTranscript,
    Future<void> Function(_LiveSessionHandle handle)? onRelease,
  }) : _follower = follower,
       _hasTranscript = hasTranscript ?? follower != null,
       _onRelease = onRelease;

  final MuxSession _session;

  /// 有可用日志时提供结构化对话，否则只有终端。
  LiveLogFollower? _follower;

  /// 这个会话是否有结构化对话（与当前是否挂着跟随器无关）。
  final bool _hasTranscript;
  final Future<void> Function(_LiveSessionHandle handle)? _onRelease;
  bool _detached = false;

  /// 重新接上一个跟随器（重新打开会话时由宿主建立）。
  void attachFollower(LiveLogFollower follower) {
    if (_detached) return;
    _follower = follower;
  }

  @override
  HarnessSessionInfo get info => HarnessSessionInfo(
    id: _session.id,
    hostId: LocalHarnessHost.hostId,
    providerId: _session.providerId,
    title: _session.title,
    cwd: _session.workingDirectory.isEmpty ? null : _session.workingDirectory,
    status: _session.status.value,
    capabilities: !_hasTranscript
        ? const <HarnessCapability>{
            HarnessCapability.terminal,
            HarnessCapability.prompt,
            HarnessCapability.stop,
          }
        : const <HarnessCapability>{
            HarnessCapability.terminal,
            HarnessCapability.transcript,
            HarnessCapability.prompt,
            HarnessCapability.stop,
          },
    updatedAt: _session.startedAt,
    sourceRef: _session.id,
  );

  @override
  ValueListenable<HarnessSessionStatus> get status => _session.status;

  @override
  Stream<TranscriptEvent>? get transcript => _follower?.events;

  @override
  HarnessTerminalChannel? get terminal => _session;

  @override
  Future<void> sendPrompt(String text) async {
    if (_detached) return;
    _session.sendLine(text);
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    if (_detached) return;
    // 终端 harness 的审批在 TUI 内完成，回复等于输入一行。
    _session.sendLine(reply.text ?? reply.choice);
  }

  /// 只释放视图。会话由 [StudioMux] 持有，进程继续运行。
  @override
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    await _onRelease?.call(this);
  }

  @override
  Future<void> stop() async {
    // detach 只释放视图；stop 无论如何都必须结束会话，所以不能因为已经
    // detach 过就变成空操作。
    if (!_detached) {
      _detached = true;
      await _onRelease?.call(this);
    }
    await _session.stop();
  }
}

/// 历史日志会话句柄。只读，不能发送提示词。
class _LogSessionHandle implements HarnessSessionHandle {
  _LogSessionHandle(
    this._entry, {
    Future<void> Function(_LogSessionHandle handle)? onRelease,
  }) : _onRelease = onRelease,
       _status = ValueNotifier<HarnessSessionStatus>(_entry.status);

  final _LogEntry _entry;
  final Future<void> Function(_LogSessionHandle handle)? _onRelease;
  final ValueNotifier<HarnessSessionStatus> _status;
  StreamController<TranscriptEvent>? _controller;
  bool _released = false;

  /// 刷新时更新列表推断出的状态。
  void updateStatus(HarnessSessionStatus status) {
    if (_released) return;
    _status.value = status;
  }

  @override
  HarnessSessionInfo get info => _entry.info;

  @override
  ValueListenable<HarnessSessionStatus> get status => _status;

  @override
  Stream<TranscriptEvent>? get transcript {
    _controller ??= _createController();
    return _controller!.stream;
  }

  StreamController<TranscriptEvent> _createController() {
    late final StreamController<TranscriptEvent> controller;
    controller = StreamController<TranscriptEvent>(
      onListen: () => unawaited(_pump(controller)),
      // 取消订阅就释放，避免把整窗事件缓冲在没有接收方的 controller 里；
      // 也保证同一个句柄不会因为二次订阅而抛“已经监听过”。
      onCancel: () => unawaited(controller.close()),
    );
    return controller;
  }

  Future<void> _pump(StreamController<TranscriptEvent> controller) async {
    final events = await _entry.reader.read(_entry.ref.filePath);
    for (final event in events) {
      if (controller.isClosed) return;
      controller.add(event);
    }
    if (!controller.isClosed) await controller.close();
  }

  @override
  HarnessTerminalChannel? get terminal => null;

  @override
  Future<void> sendPrompt(String text) async {
    throw UnsupportedError('历史会话只读，不能发送提示词');
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    throw UnsupportedError('历史会话只读，不能回复');
  }

  @override
  Future<void> detach() async {
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    if (_released) return;
    _released = true;
    await _onRelease?.call(this);
  }

  @override
  Future<void> stop() async {
    throw UnsupportedError('历史会话已经结束');
  }
}

/// 本机主机实现。
class LocalHarnessHost implements HarnessHost {
  LocalHarnessHost({
    ProviderRegistry? registry,
    StudioMux? mux,
    PtyLauncher? launcher,
    bool? supported,
    this.logRefreshInterval = const Duration(seconds: 20),
    this.maxLogSessions = 24,
    this.maxSessionEntries = 80,
  }) : _registry = registry ?? ProviderRegistry(),
       _mux = mux,
       _launcher = launcher ?? createPtyLauncher(),
       _ownsLauncher = launcher == null,
       _supported = supported ?? _platformSupportsLocalSessions() {
    if (!_supported) _state.value = HarnessHostState.unsupported;
  }

  /// 主机 id；界面用它区分本机与其他主机。
  static const String hostId = 'local';

  /// 历史会话刷新间隔。不做高频轮询。
  final Duration logRefreshInterval;

  /// 每个 provider 最多列出的历史会话数。
  final int maxLogSessions;

  /// 列表最多显示的会话数。
  final int maxSessionEntries;

  final ProviderRegistry _registry;
  final PtyLauncher _launcher;
  final bool _ownsLauncher;
  final bool _supported;
  final ValueNotifier<HarnessHostState> _state =
      ValueNotifier<HarnessHostState>(HarnessHostState.offline);
  final StreamController<List<HarnessSessionInfo>> _sessions =
      StreamController<List<HarnessSessionInfo>>.broadcast();
  final Map<String, _LogEntry> _logEntries = <String, _LogEntry>{};
  final Map<String, LiveLogFollower> _followers = <String, LiveLogFollower>{};
  final Map<String, _LiveSessionHandle> _liveHandles =
      <String, _LiveSessionHandle>{};
  final Map<String, _LogSessionHandle> _logHandles =
      <String, _LogSessionHandle>{};

  List<HarnessSessionInfo> _latest = const <HarnessSessionInfo>[];

  StudioMux? _mux;
  StreamSubscription<MuxEvent>? _muxEvents;
  Timer? _refreshTimer;
  Future<void>? _starting;
  bool _watching = false;
  bool _disposed = false;

  @override
  String get id => hostId;

  @override
  String get label => '本机';

  @override
  HarnessHostKind get kind => HarnessHostKind.local;

  @override
  ValueListenable<HarnessHostState> get state => _state;

  /// 当前平台能否启动本机会话。
  bool get isSupported => _supported;

  /// PTY 后端名，供设置页诊断。
  String get ptyStrategy => _launcher.strategy;

  /// 子进程是否看到真实终端。
  bool get allocatesTerminal => _launcher.allocatesTerminal;

  /// 提供方加载诊断。
  List<String> get warnings => _registry.warnings;

  /// 日志读取诊断。
  List<String> get logWarnings => _logWarnings;
  final List<String> _logWarnings = <String>[];

  @override
  Stream<List<HarnessSessionInfo>> watchSessions() {
    unawaited(_beginWatching());
    // 每个订阅者先拿一帧当前快照：广播流不重放，晚挂载的页面否则要等到
    // 下一次刷新（最长 logRefreshInterval）才有内容。
    return Stream.multi((MultiStreamController<List<HarnessSessionInfo>> c) {
      c.add(_latest);
      final subscription = _sessions.stream.listen(
        c.add,
        onError: c.addError,
        onDone: c.close,
      );
      c.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<HarnessProviderInfo>> providers() async {
    await _ensureStarted();
    return _registry.infosFor(allocatesTerminal: _launcher.allocatesTerminal);
  }

  @override
  Future<HarnessSessionHandle> open(String sessionId) async {
    await _ensureStarted();
    final live = _mux?.sessionFor(sessionId);
    if (live != null) {
      final cached = _liveHandles[sessionId];
      if (cached != null) return cached;
      var follower = _followers[sessionId];
      if (follower == null) {
        // 上次 detach 关掉了跟随器；重新建一个，since 用会话启动时刻，
        // 因此仍能找回同一个日志文件并补齐已有事件。
        follower = _startFollower(
          live.providerId,
          live.workingDirectory,
          since: live.startedAt,
        );
        if (follower != null) _followers[sessionId] = follower;
      }
      late final _LiveSessionHandle handle;
      handle = _LiveSessionHandle(
        live,
        follower: follower,
        onRelease: (released) async {
          if (!identical(_liveHandles[sessionId], released)) return;
          _liveHandles.remove(sessionId);
          await _followers.remove(sessionId)?.stop();
        },
      );
      _liveHandles[sessionId] = handle;
      return handle;
    }
    await refreshLogSessions();
    final entry = _logEntries[sessionId];
    if (entry == null) {
      throw StateError('会话不存在：$sessionId');
    }
    final cached = _logHandles[sessionId];
    if (cached != null) return cached;
    late final _LogSessionHandle handle;
    handle = _LogSessionHandle(
      entry,
      onRelease: (released) async {
        if (identical(_logHandles[sessionId], released)) {
          _logHandles.remove(sessionId);
        }
      },
    );
    _logHandles[sessionId] = handle;
    return handle;
  }

  @override
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request) async {
    if (!_supported) {
      throw UnsupportedError('当前平台没有本机终端会话');
    }
    await _ensureStarted();
    final provider = _registry.byId(request.providerId);
    if (provider == null) {
      throw ArgumentError.value(
        request.providerId,
        'providerId',
        '未知的 harness',
      );
    }
    if (!provider.available) {
      throw StateError('未安装 ${provider.spec.label}');
    }
    if (provider.spec.requiresTerminal && !_launcher.allocatesTerminal) {
      // 管道后端下全屏 TUI 无法工作；宁可拒绝，也不给一个假终端。
      throw StateError(
        '${provider.spec.label} 需要真实终端，当前后端（${_launcher.strategy}）只有管道',
      );
    }
    final cwd = request.cwd.trim();
    if (cwd.isEmpty || !Directory(cwd).existsSync()) {
      throw ArgumentError.value(request.cwd, 'cwd', '工作目录不存在');
    }
    final spec = provider.launchSpec;
    final mux = _mux;
    if (mux == null) throw StateError('本机会话管理器未就绪');
    final session = await mux.start(
      providerId: spec.id,
      executable: spec.executable,
      arguments: <String>[...spec.args, ...request.args],
      workingDirectory: cwd,
      environment: spec.environment.isEmpty ? null : spec.environment,
      title: request.title ?? spec.label,
    );
    final follower = _startFollower(spec.id, cwd, since: session.startedAt);
    if (follower != null) _followers[session.id] = follower;
    await _emitSessions();
    late final _LiveSessionHandle handle;
    handle = _LiveSessionHandle(
      session,
      follower: follower,
      onRelease: (released) async {
        if (!identical(_liveHandles[session.id], released)) return;
        _liveHandles.remove(session.id);
        await _followers.remove(session.id)?.stop();
      },
    );
    _liveHandles[session.id] = handle;
    return handle;
  }

  /// 为直播会话建立日志跟随；没有日志配置时返回 null。
  LiveLogFollower? _startFollower(
    String providerId,
    String cwd, {
    DateTime? since,
  }) {
    final format = _registry.byId(providerId)?.spec.logFormat;
    if (format == null) return null;
    final reader = createLogReader(
      providerId: providerId,
      format: format,
      rootPath: _registry.logDirectory(providerId),
    );
    if (reader == null) return null;
    final follower = LiveLogFollower(
      reader: reader,
      workingDirectory: cwd,
      since: since ?? DateTime.now(),
    );
    follower.start();
    return follower;
  }

  /// 重新读取日志目录。界面下拉刷新时调用。
  Future<void> refreshLogSessions() async {
    if (!_supported || _disposed) return;
    await _ensureStarted();
    _logWarnings.clear();
    final entries = <String, _LogEntry>{};
    for (final provider in _registry.resolved) {
      final spec = provider.spec;
      if (!spec.hasTranscript) continue;
      final reader = createLogReader(
        providerId: spec.id,
        format: spec.logFormat!,
        rootPath: _registry.logDirectory(spec.id),
      );
      if (reader == null) continue;
      try {
        final refs = await reader.listSessions(maxSessions: maxLogSessions);
        for (final ref in refs) {
          entries[ref.id] = _LogEntry(
            reader: reader,
            ref: ref,
            status: ref.status,
          );
        }
      } on FileSystemException catch (error) {
        _logWarnings.add('${spec.id}: ${error.message}');
      } on FormatException {
        _logWarnings.add('${spec.id}: 日志格式无法识别');
      }
    }
    _logEntries
      ..clear()
      ..addAll(entries);
    // 已打开的日志句柄跟着刷新状态，列表与详情不会各说各话。
    for (final entry in _logHandles.entries.toList()) {
      final fresh = _logEntries[entry.key];
      entry.value.updateStatus(fresh?.status ?? HarnessSessionStatus.exited);
    }
    await _emitSessions();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _muxEvents?.cancel();
    _muxEvents = null;
    for (final follower in _followers.values) {
      await follower.stop();
    }
    _followers.clear();
    for (final handle in _liveHandles.values.toList()) {
      await handle.detach();
    }
    _liveHandles.clear();
    for (final handle in _logHandles.values.toList()) {
      await handle.detach();
    }
    _logHandles.clear();
    await _mux?.dispose();
    _mux = null;
    if (_ownsLauncher) await _launcher.dispose();
    _logEntries.clear();
    if (!_sessions.isClosed) await _sessions.close();
    _state.dispose();
  }

  Future<void> _beginWatching() async {
    if (_watching) {
      // 已有扫描在跑：只等启动完成，不重复扫日志目录。
      await _ensureStarted();
      if (_disposed) return;
      await _emitSessions();
      return;
    }
    _watching = true;
    await _ensureStarted();
    if (_disposed) return;
    _refreshTimer ??= Timer.periodic(
      logRefreshInterval,
      (Timer _) => unawaited(refreshLogSessions()),
    );
    await refreshLogSessions();
  }

  Future<void> _ensureStarted() {
    final starting = _starting;
    if (starting != null) return starting;
    return _starting = _start();
  }

  Future<void> _start() async {
    if (_disposed) return;
    if (!_supported) {
      _state.value = HarnessHostState.unsupported;
      // 订阅者仍会拿到一次空列表，界面因此不必区分“没有会话”与“未收到”。
      await _emitSessions();
      return;
    }
    _state.value = HarnessHostState.connecting;
    try {
      await _registry.load();
    } on Object {
      // 配置损坏不影响内置项；注册表保留诊断信息。
    }
    if (_disposed) return;
    final mux = _mux ??= StudioMux(launcher: _launcher);
    _muxEvents ??= mux.events.listen((MuxEvent event) {
      if (event.kind == MuxEventKind.exited) {
        // 会话结束后再读日志没有意义，释放轮询。
        final sessionId = event.session.id;
        unawaited(_followers.remove(sessionId)?.stop());
        _liveHandles.remove(sessionId);
      }
      unawaited(_emitSessions());
    });
    if (_disposed) return;
    _state.value = HarnessHostState.online;
    await _emitSessions();
  }

  Future<void> _emitSessions() async {
    if (_disposed || _sessions.isClosed) return;
    final infos = <HarnessSessionInfo>[];
    final mux = _mux;
    if (mux != null) {
      for (final session in mux.sessions) {
        infos.add(_sessionInfo(session));
      }
    }
    for (final entry in _logEntries.values) {
      infos.add(entry.info);
    }
    infos.sort((HarnessSessionInfo a, HarnessSessionInfo b) {
      final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    _latest = List<HarnessSessionInfo>.unmodifiable(
      infos.length > maxSessionEntries
          ? infos.sublist(0, maxSessionEntries)
          : infos,
    );
    _sessions.add(_latest);
  }

  /// 列表行不需要跟随器；能力集取决于 provider 是否配置了可读日志，而不是
  /// 此刻是否恰好有一个活着的跟随器（detach 后重开会重建）。
  HarnessSessionInfo _sessionInfo(MuxSession session) => _LiveSessionHandle(
    session,
    hasTranscript: _hasTranscriptProvider(session.providerId),
  ).info;

  /// 该 provider 是否配置了可读日志。
  bool _hasTranscriptProvider(String providerId) =>
      _registry.byId(providerId)?.spec.logFormat != null &&
      _registry.logDirectory(providerId) != null;

  static bool _platformSupportsLocalSessions() {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }
}
