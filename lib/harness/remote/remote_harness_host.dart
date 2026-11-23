// RemoteHarnessHost: one paired computer as a HarnessHub host.
//
// This is an adapter, not a second protocol implementation. Every action lands on
// the module that already owns it (`RemoteController`, `HerdrController`,
// `CodexThreadView`), so the wire format, request ids, reconnect and replay
// behaviour, and the "approvals only from an explicit reply" rule are exactly the
// ones the Remote Computer page uses.
//
// Sessions from all three remote surfaces are merged into one list because the
// Agents surface shows "what runs on that computer", not "which sub-module".

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../remote_control/models/herdr.dart' as herdr;
import '../../remote_control/models/protocol.dart' as protocol;
import '../../remote_control/state/remote_controller.dart' show ConnectionPhase;
import '../../services/app_paths.dart';
import '../../sync/placeholder_project.dart';
import '../../sync/remote_session_cache.dart';
import '../harness_host.dart';
import 'remote_mapping.dart';
import 'remote_ports.dart';
import 'remote_session.dart';

class RemoteHarnessHost implements HarnessHost, HarnessDeviceHost {
  RemoteHarnessHost({
    required RemoteSessionPort remote,
    RemoteHerdrPort? herdr,
    RemoteCodexPort? codex,
    this.refreshInterval = const Duration(seconds: 20),
    String? hostId,
    bool cacheTranscripts = true,
  }) : _remote = remote,
       _herdr = herdr,
       _codex = codex,
       _cacheTranscripts = cacheTranscripts,
       // Resolved once: `id` is a map key in the hub and is stamped into every
       // `HarnessSessionInfo`, so it must not drift when pairing arrives later.
       // Pass [hostId] when the pairing is not loaded yet.
       _id = _resolveHostId(hostId ?? remote.hostId),
       _state = ValueNotifier<HarnessHostState>(_stateFor(remote.phase)) {
    _remote.changes.addListener(_onRemoteChanged);
    _herdr?.changes.addListener(_onHerdrChanged);
    _state.value = _stateFor(_remote.phase);
    _wasOnline = remote.isOnline;
    _refreshDevice();
    if (_wasOnline) unawaited(_loadRemote());
  }

  static String _resolveHostId(String value) {
    final key = value.trim();
    if (key.isEmpty) return 'remote';
    return key.startsWith('remote:') ? key : 'remote:$key';
  }

  final String _id;

  /// How often the thread catalog is refreshed while the list is open. Sessions
  /// themselves arrive as pushes, so this is only for the Codex catalog.
  final Duration refreshInterval;

  final RemoteSessionPort _remote;
  final RemoteHerdrPort? _herdr;
  final RemoteCodexPort? _codex;
  final ValueNotifier<HarnessHostState> _state;
  final StreamController<List<HarnessSessionInfo>> _sessions =
      StreamController<List<HarnessSessionInfo>>.broadcast();
  final Map<String, RemoteSessionHandle> _sessionHandles =
      <String, RemoteSessionHandle>{};
  final Map<String, RemoteHerdrHandle> _herdrHandles =
      <String, RemoteHerdrHandle>{};
  final Map<String, RemoteCodexThreadHandle> _codexHandles =
      <String, RemoteCodexThreadHandle>{};
  final List<protocol.CodexThread> _codexThreads = <protocol.CodexThread>[];

  late final bool _cacheTranscripts;

  List<HarnessSessionInfo> _latest = const <HarnessSessionInfo>[];
  bool _wasOnline = false;
  bool _disposed = false;
  bool _loadingCodex = false;
  String? _lastError;
  Timer? _codexTimer;

  /// 最近一帧设备信息。
  ///
  /// [device] 是同步读的：构造完就要能回答。构造函数里先取一次，之后每次
  /// 主机变化再取。只有真正连接到电脑、主机报出信息时它才变。
  final ValueNotifier<HarnessDeviceInfo> _device =
      ValueNotifier<HarnessDeviceInfo>(const HarnessDeviceInfo());

  @override
  String get id => _id;

  /// Bounded transcript cache for one session, inside its placeholder project.
  ///
  /// The directory matches [PlaceholderProjects.streamDirectory] so the cache is
  /// one file inside `deviceSessions/<hostKey>/<sessionId>/.session`, and a
  /// session that ran on the computer reads back what it showed before the
  /// connection dropped. Created on demand and returned without one when the app
  /// data directory is not writable: a missing cache only costs history after a
  /// reconnect, and a session must still open without it.
  Future<RemoteSessionCache?> _streamCacheFor(String sessionId) async {
    if (!_cacheTranscripts) return null;
    final raw = sessionId.startsWith('session:')
        ? sessionId.substring('session:'.length)
        : sessionId;
    final root = await AppPaths.deviceSessionsRoot(create: true);
    if (root == null) return null;
    final dir =
        '$root/${PlaceholderProjects.hostKey(_id)}/${_safeSessionSegment(raw)}/.session';
    try {
      await Directory(dir).create(recursive: true);
    } on FileSystemException {
      return null;
    }
    return RemoteSessionCache(directory: dir);
  }

  static String _safeSessionSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'session' : cleaned;
  }

  @override
  String get label {
    final name = _remote.hostLabel;
    return name.isEmpty ? '远程电脑' : name;
  }

  @override
  HarnessHostKind get kind => HarnessHostKind.remote;

  @override
  ValueListenable<HarnessHostState> get state => _state;

  // -------------------------------------------------------------------------
  // HarnessDeviceHost (R4)
  // -------------------------------------------------------------------------

  /// Device information forwarded from the agent's `info` frame.
  ///
  /// Field mapping follows ruling R4: `name` prefers `hostName` and falls back
  /// to `host`; `os` prefers the reported short name and falls back to
  /// `platform`; `osVersion` is passed through verbatim. Nothing is invented:
  /// a field the agent did not send stays unknown.
  @override
  ValueListenable<HarnessDeviceInfo> get device => _device;

  /// Recompute [device] from the latest info frame.
  void _refreshDevice() {
    final info = _remote is RemoteDevicePort
        ? (_remote as RemoteDevicePort).agentInfo
        : null;
    _device.value = _deviceInfoFrom(info);
  }

  static HarnessDeviceInfo _deviceInfoFrom(protocol.AgentInfo? info) {
    if (info == null) return const HarnessDeviceInfo();
    final name = (info.hostName ?? info.host).trim();
    final version = (info.osVersion ?? '').trim();
    return HarnessDeviceInfo(
      hostName: name.isEmpty ? null : name,
      os: _deviceOsFrom(info),
      osVersion: version.isEmpty ? null : info.osVersion,
    );
  }

  /// Map the reported `os`, then fall back to the Node `platform` value.
  static HarnessDeviceOs _deviceOsFrom(protocol.AgentInfo info) {
    switch ((info.os ?? '').trim().toLowerCase()) {
      case 'windows':
        return HarnessDeviceOs.windows;
      case 'macos':
        return HarnessDeviceOs.macos;
      case 'linux':
        return HarnessDeviceOs.linux;
      case 'android':
        return HarnessDeviceOs.android;
      case 'ios':
        return HarnessDeviceOs.ios;
      case 'ohos':
        return HarnessDeviceOs.ohos;
    }
    // `other` or missing: the platform value is the only remaining signal.
    switch (info.platform.trim().toLowerCase()) {
      case 'win32':
        return HarnessDeviceOs.windows;
      case 'darwin':
        return HarnessDeviceOs.macos;
      case 'linux':
        return HarnessDeviceOs.linux;
    }
    return HarnessDeviceOs.unknown;
  }

  /// Last failure, already user-facing.
  String? get lastError => _lastError;

  /// Phase of the underlying pairing, for a host switcher's status dot.
  ConnectionPhase get phase => _remote.phase;

  /// Snapshot for a UI that mounts after the first push.
  List<HarnessSessionInfo> get currentSessions => _latest;

  // -------------------------------------------------------------------------
  // HarnessHost
  // -------------------------------------------------------------------------

  @override
  Stream<List<HarnessSessionInfo>> watchSessions() {
    return Stream.multi((controller) {
      _watchCount += 1;
      _startCodexTimer();
      final subscription = _sessions.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      // 先挂上取消回调，再发第一帧：有人在第一帧就取消（`.first` 或
      // 建好就拆的界面）时，计数也要减回去。计数不归零，20 s 的定时器
      // 就会一直跑，测试进程也跟着不退出。
      controller.onCancel = () {
        subscription.cancel();
        if (_watchCount > 0) _watchCount -= 1;
        // No listener, no polling: the catalog is only for the visible list.
        if (_watchCount <= 0) _stopCodexTimer();
      };
      controller.add(_latest);
    });
  }

  int _watchCount = 0;

  void _startCodexTimer() {
    if (_codexTimer != null || _disposed) return;
    _codexTimer = Timer.periodic(refreshInterval, (_) {
      if (_remote.isOnline) unawaited(_loadCodex());
    });
  }

  void _stopCodexTimer() {
    _codexTimer?.cancel();
    _codexTimer = null;
  }

  @override
  Future<List<HarnessProviderInfo>> providers() async {
    // Both entries are launchable on the desktop through the existing agent
    // protocol. Herdr panes are listed as sessions but cannot be started from
    // here (the wire protocol has no Herdr start verb), so they are not offered.
    return const <HarnessProviderInfo>[
      HarnessProviderInfo(
        id: 'claude',
        label: 'Claude Code',
        available: true,
        executable: 'claude',
        builtIn: true,
      ),
      HarnessProviderInfo(
        id: 'shell',
        label: '终端',
        available: true,
        builtIn: true,
      ),
    ];
  }

  @override
  Future<HarnessSessionHandle> open(String sessionId) async {
    final existing =
        _sessionHandles[sessionId] ??
        _herdrHandles[sessionId] ??
        _codexHandles[sessionId];
    if (existing != null) {
      // A stopped or released handle can linger until its owner lets go; reuse
      // it only while it is still live.
      if (!_isEnded(existing)) return existing;
      _sessionHandles.remove(sessionId);
      _herdrHandles.remove(sessionId);
      _codexHandles.remove(sessionId);
    }

    if (sessionId.startsWith('session:')) {
      final rawId = sessionId.substring('session:'.length);
      final session = _sessionById(rawId);
      if (session == null) {
        throw StateError('找不到该会话，可能已在电脑上关闭');
      }
      final handle = RemoteSessionHandle(
        port: _remote,
        session: session,
        hostId: id,
        streamCache: await _streamCacheFor(sessionId),
        onDetached: (detached) async {
          if (identical(_sessionHandles[sessionId], detached)) {
            _sessionHandles.remove(sessionId);
          }
          detached.dispose();
        },
      );
      _sessionHandles[sessionId] = handle;
      return handle;
    }

    if (sessionId.startsWith('herdr:')) {
      final paneId = sessionId.substring('herdr:'.length);
      final port = _herdr;
      if (port == null) {
        throw StateError('当前电脑没有 Herdr 面板');
      }
      final agent = _agentByPane(paneId);
      if (agent == null) {
        throw StateError('找不到该 Herdr 面板，可能已关闭');
      }
      final handle = RemoteHerdrHandle(
        herdrPort: port,
        agent: agent,
        hostId: id,
        onDetached: (detached) async {
          if (identical(_herdrHandles[sessionId], detached)) {
            _herdrHandles.remove(sessionId);
          }
          detached.dispose();
        },
      );
      _herdrHandles[sessionId] = handle;
      return handle;
    }

    if (sessionId.startsWith('codex:')) {
      final threadId = sessionId.substring('codex:'.length);
      final port = _codex;
      if (port == null) {
        throw StateError('当前电脑没有 Codex 会话');
      }
      final thread = _threadById(threadId);
      if (thread == null) {
        throw StateError('找不到该 Codex 会话');
      }
      final handle = RemoteCodexThreadHandle(
        codex: port,
        view: port.openThread(thread),
        hostId: id,
        onDetached: (detached) async {
          if (identical(_codexHandles[sessionId], detached)) {
            _codexHandles.remove(sessionId);
          }
          await detached.dispose();
        },
      );
      _codexHandles[sessionId] = handle;
      return handle;
    }

    throw StateError('无法识别的会话：$sessionId');
  }

  /// Whether a cached handle is finished, without widening the shared contract.
  static bool _isEnded(HarnessSessionHandle handle) => switch (handle) {
    RemoteSessionHandle() => handle.isEnded,
    RemoteHerdrHandle() => handle.isEnded,
    RemoteCodexThreadHandle() => handle.isEnded,
    _ => false,
  };

  @override
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request) async {
    if (!_remote.isOnline) {
      throw StateError('电脑未连接，无法新建会话');
    }
    if (request.args.isNotEmpty) {
      // The wire verbs take no extra arguments: dropping them would make a
      // "start with these flags" request look successful but run differently.
      throw UnsupportedError('远程电脑暂不支持启动参数，请在桌面端启动该会话。');
    }
    final protocol.SessionInfo created;
    switch (request.providerId) {
      case 'shell':
        created = await _remote.createTerminal(cwd: request.cwd);
      case 'claude':
        created = await _remote.createSession(cwd: request.cwd);
      default:
        throw StateError('远程电脑暂不支持启动 ${request.providerId} 会话');
    }
    await _remote.refreshSessions();
    return open('session:${created.id}');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopCodexTimer();
    _device.dispose();
    _remote.changes.removeListener(_onRemoteChanged);
    _herdr?.changes.removeListener(_onHerdrChanged);
    final sessionHandles = _sessionHandles.values.toList();
    _sessionHandles.clear();
    for (final handle in sessionHandles) {
      handle.dispose();
    }
    final herdrHandles = _herdrHandles.values.toList();
    _herdrHandles.clear();
    for (final handle in herdrHandles) {
      handle.dispose();
    }
    final codexHandles = _codexHandles.values.toList();
    _codexHandles.clear();
    for (final handle in codexHandles) {
      await handle.dispose();
    }
    await _sessions.close();
    _state.dispose();
  }

  // -------------------------------------------------------------------------
  // State and refresh
  // -------------------------------------------------------------------------

  void _onRemoteChanged() {
    if (_disposed) return;
    _state.value = _stateFor(_remote.phase);
    final online = _remote.isOnline;
    if (online && !_wasOnline) {
      // A fresh connection: the desktop may have restarted, so re-read
      // everything rather than trusting the pre-disconnect caches.
      _wasOnline = true;
      unawaited(_loadRemote());
    } else if (!online) {
      _wasOnline = false;
    }
    _refreshDevice();
    _emit();
  }

  void _onHerdrChanged() {
    if (_disposed) return;
    _syncHerdrHandles();
    _emit();
  }

  Future<void> _loadRemote() async {
    try {
      await _remote.refreshSessions();
      final herdrPort = _herdr;
      if (herdrPort != null && herdrPort.canControl) {
        await herdrPort.refresh();
      }
      await _loadCodex();
      _lastError = null;
    } catch (error) {
      _lastError = '$error';
    }
    _emit();
  }

  /// Codex catalog refresh. Failures are recorded but never block the list: a
  /// computer without Codex is a normal computer.
  Future<void> _loadCodex() async {
    final port = _codex;
    if (port == null || _disposed || _loadingCodex) return;
    if (!_remote.isOnline || !port.available) return;
    _loadingCodex = true;
    try {
      final threads = await port.recentThreads();
      _codexThreads
        ..clear()
        ..addAll(threads.take(50));
      _emit();
    } catch (error) {
      _lastError = '$error';
    } finally {
      _loadingCodex = false;
    }
  }

  void _emit() {
    final infos = <HarnessSessionInfo>[
      for (final session in _remote.sessions)
        remoteSessionInfo(hostId: id, session: session),
      if (_herdr?.canControl == true)
        for (final agent in _herdr!.agents)
          remoteHerdrSessionInfo(hostId: id, agent: agent),
      for (final thread in _codexThreads)
        remoteCodexSessionInfo(hostId: id, thread: thread),
    ];
    infos.sort(_compareSessions);
    _latest = List<HarnessSessionInfo>.unmodifiable(infos);
    _syncHerdrHandles();
    if (!_sessions.isClosed) _sessions.add(_latest);
  }

  void _syncHerdrHandles() {
    if (_herdr == null) return;
    for (final entry in _herdrHandles.entries.toList()) {
      final paneId = entry.key.substring('herdr:'.length);
      final agent = _agentByPane(paneId);
      if (agent == null) {
        // The pane is gone; the row keeps its last title and shows as exited.
        entry.value.markExited();
      } else {
        entry.value.update(agent);
      }
    }
  }

  /// Attention first: blocked/done need a human, working does not.
  static int _compareSessions(HarnessSessionInfo a, HarnessSessionInfo b) {
    int rank(HarnessSessionStatus status) {
      switch (status) {
        case HarnessSessionStatus.blocked:
          return 0;
        case HarnessSessionStatus.done:
          return 1;
        case HarnessSessionStatus.working:
          return 2;
        case HarnessSessionStatus.idle:
          return 3;
        case HarnessSessionStatus.unknown:
          return 4;
        case HarnessSessionStatus.exited:
          return 5;
      }
    }

    final byRank = rank(a.status).compareTo(rank(b.status));
    if (byRank != 0) return byRank;
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  protocol.SessionInfo? _sessionById(String id) {
    for (final session in _remote.sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  herdr.HerdrAgent? _agentByPane(String paneId) {
    final port = _herdr;
    if (port == null) return null;
    for (final agent in port.agents) {
      if (agent.paneId == paneId) return agent;
    }
    return null;
  }

  protocol.CodexThread? _threadById(String id) {
    for (final thread in _codexThreads) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  static HarnessHostState _stateFor(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.online:
        return HarnessHostState.online;
      case ConnectionPhase.connecting:
        return HarnessHostState.connecting;
      case ConnectionPhase.unpaired:
      case ConnectionPhase.agentOffline:
      case ConnectionPhase.authFailed:
      case ConnectionPhase.disconnected:
        return HarnessHostState.offline;
    }
  }
}
