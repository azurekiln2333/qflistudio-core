// Harness Hub：把每台能跑 harness 的电脑抽象成一份主机列表，界面只读这里。
//
// 契约在 `lib/harness/harness_host.dart`，本文件不改它。主机由外部注入：
// 编辑器页按平台策略组出来，测试和预览用假主机，见 harness_hosts.dart。

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../harness_host.dart';

/// 主机可选能力：装不上或平台不支持时给界面的一句说明。
///
/// 契约里没有安装提示字段，所以用这个可选接口传，避免改动共享契约。
/// 返回值是 `Object?`：各家主机可以给自己定义的结构化对象（例如
/// `{title, message, url}`），文字由 [harnessHintText] 统一取。
abstract class HarnessHostHint {
  /// 例如「未检测到 Herdr，请先安装」，或一个带 `message` 字段的对象。
  Object? get installHint;
}

/// 把 [HarnessHostHint.installHint] 变成一行可显示的文本。
///
/// 认三种形态，都是按结构取文字，不做字符串搜索：
/// * `String`：直接用（空串视为没有说明）；
/// * `Map`：依次取 `message`、`detail`、`title`；
/// * 其它对象：取 `message` 字段，取不到就退到 `toString`。
///
/// 默认的 `Instance of ...` 不算说明，返回 null 让界面走通用文案。
String? harnessHintText(Object? hint) {
  if (hint == null) return null;
  if (hint is String) {
    final text = hint.trim();
    return text.isEmpty ? null : text;
  }
  if (hint is Map) {
    for (final key in const ['message', 'detail', 'title']) {
      final value = hint[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
  try {
    final message = (hint as dynamic).message;
    if (message is String && message.trim().isNotEmpty) return message.trim();
  } on Object {
    // 没有 message 字段：继续往下退。
  }
  final text = hint.toString().trim();
  if (text.isEmpty || text.startsWith('Instance of ')) return null;
  return text;
}

/// 一个主机里同一 provider 的会话。
@immutable
class HubProviderGroup {
  const HubProviderGroup({
    required this.providerId,
    required this.label,
    required this.sessions,
  });

  final String providerId;

  /// 界面上显示的 provider 名称；没有 provider 信息时退回 id。
  final String label;
  final List<HarnessSessionInfo> sessions;
}

/// 玩家可读的 provider 名称：先查 [labels]，再退回 id。
String hubProviderLabel(String providerId, Map<String, String> labels) {
  final label = labels[providerId];
  if (label != null && label.trim().isNotEmpty) return label;
  return providerId;
}

/// 按 provider 分组，组内按更新时间倒序，组间按名称排序。
///
/// 纯函数，方便列表和测试共用同一套顺序。
List<HubProviderGroup> groupSessionsByProvider(
  List<HarnessSessionInfo> sessions, {
  Map<String, String> labels = const <String, String>{},
}) {
  final grouped = <String, List<HarnessSessionInfo>>{};
  for (final session in sessions) {
    grouped
        .putIfAbsent(session.providerId, () => <HarnessSessionInfo>[])
        .add(session);
  }
  final groups = <HubProviderGroup>[
    for (final entry in grouped.entries)
      HubProviderGroup(
        providerId: entry.key,
        label: hubProviderLabel(entry.key, labels),
        sessions: [...entry.value]
          ..sort((a, b) {
            final at = a.updatedAt;
            final bt = b.updatedAt;
            if (at == null && bt == null) return a.title.compareTo(b.title);
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          }),
      ),
  ];
  groups.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return groups;
}

/// hub 层拒绝请求时抛出的错误：主机不存在、会话已被别处移除等。
class HarnessHubException implements Exception {
  const HarnessHubException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 主机池、当前主机与合并后的会话列表。
///
/// 界面只依赖这里和契约类型：
///
/// * [hosts] 已按平台策略过滤，手机端只有已绑定电脑和内置 Agent；
/// * [currentSessions] 是当前主机的会话，[groupsOf] 已按 provider 分好组；
/// * [activeSession] 是正在看的会话，[activeHandle] 是它打开的视图，
///   关闭视图时调用 [closeActiveSession] 释放，不结束会话。
class HarnessHub extends ChangeNotifier {
  HarnessHub({
    required List<HarnessHost> hosts,
    required bool desktop,
    String? initialHostId,
    bool ownsHosts = true,
    this.hostBuildError,
  }) : _desktop = desktop,
       _ownsHosts = ownsHosts,
       _hosts = List<HarnessHost>.unmodifiable(
         hosts.where(
           (host) => hostVisibleOnPlatform(host.kind, desktop: desktop),
         ),
       ) {
    for (final host in _hosts) {
      _states[host.id] = host.state.value;
      void onState() => _onHostState(host);
      _stateListeners[host.id] = onState;
      host.state.addListener(onState);
      _listen(host);
    }
    _currentHostId = _pickInitialHost(initialHostId);
  }

  /// 平台策略：桌面版能用本机和 Herdr，手机端只能用已绑定电脑和内置 Agent。
  ///
  /// 手机上没有 PTY，也没有本机 Herdr，所以这两类主机不上列表，
  /// 而不是上一个点了会失败的空壳。
  static bool hostVisibleOnPlatform(
    HarnessHostKind kind, {
    required bool desktop,
  }) {
    if (desktop) return true;
    return kind == HarnessHostKind.remote || kind == HarnessHostKind.studio;
  }

  final bool _desktop;

  /// 销毁时是否连带 `dispose()` 主机。
  ///
  /// 主机是应用级共享单例时由调用方传 false：关掉一个编辑页不能把全局主机
  /// 释放掉。默认 true，对应「工厂每次给新实例」的约定。
  final bool _ownsHosts;

  /// 装配主机时的异常；没有异常或没有注册工厂时为 null。
  final Object? hostBuildError;

  final List<HarnessHost> _hosts;
  final Map<String, HarnessHostState> _states = <String, HarnessHostState>{};
  final Map<String, VoidCallback> _stateListeners = <String, VoidCallback>{};
  final Map<String, List<HarnessSessionInfo>> _sessions =
      <String, List<HarnessSessionInfo>>{};
  final Map<String, StreamSubscription<List<HarnessSessionInfo>>> _subs =
      <String, StreamSubscription<List<HarnessSessionInfo>>>{};
  final Map<String, List<HarnessProviderInfo>> _providers =
      <String, List<HarnessProviderInfo>>{};
  final Map<String, Object> _sessionErrors = <String, Object>{};

  String? _currentHostId;
  HarnessSessionInfo? _activeSession;
  HarnessSessionHandle? _activeHandle;
  bool _opening = false;
  bool _disposed = false;

  /// 平台是否按桌面版处理，测试可注入。
  bool get isDesktop => _desktop;

  /// 已按平台过滤的主机，顺序即界面顺序。
  List<HarnessHost> get hosts => _hosts;

  HarnessHost? hostById(String id) {
    for (final host in _hosts) {
      if (host.id == id) return host;
    }
    return null;
  }

  /// 当前主机；没有任何可用主机时为 null。
  HarnessHost? get currentHost =>
      _currentHostId == null ? null : hostById(_currentHostId!);

  String? get currentHostId => _currentHostId;

  /// 切换主机。切换会先释放当前会话视图（只释放视图，不结束会话）。
  void selectHost(String id) {
    if (_disposed || id == _currentHostId) return;
    if (hostById(id) == null) return;
    unawaited(closeActiveSession());
    _currentHostId = id;
    notifyListeners();
  }

  /// 主机状态；没有该主机时按 unsupported 处理，界面不会因为缺一项就崩。
  HarnessHostState stateOf(String hostId) =>
      _states[hostId] ?? HarnessHostState.unsupported;

  /// 主机状态的监听句柄，供选择器画在线点。
  ValueListenable<HarnessHostState> stateListenableOf(String hostId) {
    final host = hostById(hostId);
    return host?.state ?? _missingState;
  }

  /// 没有该主机时共用的只读占位，避免每帧新建一个 notifier。
  static final ValueNotifier<HarnessHostState> _missingState =
      ValueNotifier<HarnessHostState>(HarnessHostState.unsupported);

  /// 主机自带的安装/修复说明；没有时为 null。
  String? hintOf(String hostId) {
    final host = hostById(hostId);
    // 两个类型互不相关，Dart 不会做类型提升；用模式匹配绑定出非空副本。
    if (host case final HarnessHostHint hinted) {
      return harnessHintText(hinted.installHint);
    }
    return null;
  }

  /// 该主机最近一次会话列表读取失败的原因。
  Object? sessionErrorOf(String hostId) => _sessionErrors[hostId];

  /// 某台主机的会话，顺序沿用主机给的顺序。
  List<HarnessSessionInfo> sessionsOf(String hostId) =>
      List<HarnessSessionInfo>.unmodifiable(
        _sessions[hostId] ?? const <HarnessSessionInfo>[],
      );

  /// 当前主机的会话。
  List<HarnessSessionInfo> get currentSessions {
    final host = currentHost;
    return host == null ? const <HarnessSessionInfo>[] : sessionsOf(host.id);
  }

  /// 所有主机的会话合并，带主机 id，界面据此区分来源。
  List<HarnessSessionInfo> get allSessions => <HarnessSessionInfo>[
    for (final host in _hosts) ...sessionsOf(host.id),
  ];

  /// 某台主机按 provider 分好的组。
  List<HubProviderGroup> groupsOf(String hostId) => groupSessionsByProvider(
    sessionsOf(hostId),
    labels: providerLabelsOf(hostId),
  );

  /// 当前主机的分组。
  List<HubProviderGroup> get currentGroups {
    final host = currentHost;
    return host == null ? const <HubProviderGroup>[] : groupsOf(host.id);
  }

  /// 已知的 provider 名称，未读取过时为空。
  Map<String, String> providerLabelsOf(String hostId) {
    final list = _providers[hostId];
    if (list == null) return const <String, String>{};
    return <String, String>{
      for (final provider in list) provider.id: provider.label,
    };
  }

  /// 读取某台主机能启动的 harness，并缓存名称。
  ///
  /// 读不到时返回空列表，不抛给界面：启动菜单为空只需要提示一句。
  Future<List<HarnessProviderInfo>> providersOf(
    String hostId, {
    bool refresh = false,
  }) async {
    final cached = _providers[hostId];
    if (cached != null && !refresh) return cached;
    final host = hostById(hostId);
    if (host == null) return const <HarnessProviderInfo>[];
    try {
      final providers = await host.providers();
      if (_disposed) return providers;
      _providers[hostId] = List<HarnessProviderInfo>.unmodifiable(providers);
      notifyListeners();
      return _providers[hostId]!;
    } on Object {
      if (_disposed) return const <HarnessProviderInfo>[];
      _providers[hostId] = const <HarnessProviderInfo>[];
      notifyListeners();
      return _providers[hostId]!;
    }
  }

  /// 当前主机的“新建会话”菜单项。
  Future<List<HarnessProviderInfo>> launchMenu() async {
    final host = currentHost;
    if (host == null) return const <HarnessProviderInfo>[];
    return providersOf(host.id);
  }

  /// 正在看的会话；没有打开会话时为 null。
  HarnessSessionInfo? get activeSession => _activeSession;

  /// 正在看的会话视图；为 null 表示还没打开。
  HarnessSessionHandle? get activeHandle => _activeHandle;

  /// 会话列表是否已至少收到一次。
  bool get hasLoadedSessions => _sessions.isNotEmpty;

  /// 选中并打开一个会话。
  ///
  /// 同一个会话重复调用返回同一个视图；换会话会先释放旧的视图。
  Future<HarnessSessionHandle> openSession(
    HarnessSessionInfo info, {
    String? hostId,
  }) async {
    final targetHostId = hostId ?? info.hostId;
    final host = hostById(targetHostId);
    if (host == null) {
      throw HarnessHubException('找不到主机 ${info.hostId}，请刷新后重试');
    }
    final existing = _activeHandle;
    if (_activeSession?.id == info.id &&
        _activeSession?.hostId == info.hostId &&
        existing != null) {
      return existing;
    }
    if (_opening) {
      throw const HarnessHubException('上一个会话还没打开，请稍后再试');
    }
    _opening = true;
    try {
      await closeActiveSession();
      final handle = await host.open(info.id);
      if (_disposed) {
        await handle.detach();
        return handle;
      }
      _activeSession = handle.info;
      _activeHandle = handle;
      if (_currentHostId != targetHostId) _currentHostId = targetHostId;
      notifyListeners();
      return handle;
    } finally {
      _opening = false;
    }
  }

  /// 在当前主机上启动一个 harness，并把它设为正在看的会话。
  Future<HarnessSessionHandle> launch(
    HarnessLaunchRequest request, {
    String? hostId,
  }) async {
    final host = hostById(hostId ?? _currentHostId ?? '');
    if (host == null) {
      throw const HarnessHubException('当前没有可用的主机');
    }
    if (_opening) {
      throw const HarnessHubException('上一个会话还没打开，请稍后再试');
    }
    _opening = true;
    try {
      await closeActiveSession();
      final handle = await host.launch(request);
      if (_disposed) {
        await handle.detach();
        return handle;
      }
      _activeSession = handle.info;
      _activeHandle = handle;
      // 与 openSession 一致：新会话属于哪台主机，当前主机就跟到哪。
      if (_currentHostId != host.id) _currentHostId = host.id;
      notifyListeners();
      return handle;
    } finally {
      _opening = false;
    }
  }

  /// 只释放当前会话视图。会话照常在主机上跑，再次打开就重新接上。
  Future<void> closeActiveSession() async {
    final handle = _activeHandle;
    _activeHandle = null;
    _activeSession = null;
    if (!_disposed) notifyListeners();
    if (handle != null) {
      try {
        await handle.detach();
      } on Object {
        // 释放视图失败不该挡住界面退出；会话本身仍在主机上。
      }
    }
  }

  /// 重新订阅所有主机的会话列表，并丢弃 provider 缓存。
  ///
  /// 主机离线时订阅可能只是空表，用户点「刷新」就再要一次。
  Future<void> refresh() async {
    if (_disposed) return;
    _providers.clear();
    for (final host in _hosts) {
      await _subs.remove(host.id)?.cancel();
      _listen(host);
      unawaited(
        host.providers().then<void>((providers) {
          if (_disposed) return;
          _providers[host.id] = List<HarnessProviderInfo>.unmodifiable(
            providers,
          );
          notifyListeners();
        }, onError: (Object _) {}),
      );
    }
    notifyListeners();
  }

  void _listen(HarnessHost host) {
    _sessionErrors.remove(host.id);
    _subs[host.id] = host.watchSessions().listen(
      (sessions) {
        if (_disposed) return;
        _sessions[host.id] = List<HarnessSessionInfo>.unmodifiable(sessions);
        _sessionErrors.remove(host.id);
        // 正在看的会话被主机移除（自己退出或被删掉）：只摘掉视图，
        // 不再对它发任何请求。
        final active = _activeSession;
        if (active != null &&
            active.hostId == host.id &&
            !sessions.any((session) => session.id == active.id)) {
          unawaited(closeActiveSession());
        }
        notifyListeners();
      },
      onError: (Object error) {
        if (_disposed) return;
        _sessionErrors[host.id] = error;
        notifyListeners();
      },
    );
  }

  void _onHostState(HarnessHost host) {
    if (_disposed) return;
    final state = host.state.value;
    if (_states[host.id] == state) return;
    _states[host.id] = state;
    notifyListeners();
  }

  String? _pickInitialHost(String? initialHostId) {
    if (initialHostId != null && hostById(initialHostId) != null) {
      return initialHostId;
    }
    if (_hosts.isEmpty) return null;
    // 桌面版默认停在「本机」，手机端默认停在第一台已绑定电脑。
    for (final host in _hosts) {
      if (host.kind == HarnessHostKind.local && _desktop) return host.id;
    }
    for (final host in _hosts) {
      if (host.kind == HarnessHostKind.remote) return host.id;
    }
    return _hosts.first.id;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _subs.entries) {
      unawaited(entry.value.cancel());
    }
    _subs.clear();
    for (final host in _hosts) {
      final listener = _stateListeners.remove(host.id);
      if (listener != null) host.state.removeListener(listener);
      if (_ownsHosts) unawaited(host.dispose());
    }
    final handle = _activeHandle;
    _activeHandle = null;
    _activeSession = null;
    if (handle != null) unawaited(handle.detach());
    super.dispose();
  }
}
