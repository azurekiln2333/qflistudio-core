// Harness Hub：把每台能跑 harness 的电脑抽象成一份主机列表，界面只读这里。
//
// 契约在 `lib/harness/harness_host.dart`，本文件不改它。主机由外部注入：
// 编辑器页按平台策略组出来，测试和预览用假主机，见 harness_hosts.dart。

import 'dart:async';
import 'dart:collection';

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
///
/// 会话订阅按需建立：hub 只订阅当前主机，其余主机等用户切过去或直接使用
/// （[openSession]、[launch]）时才拉起，见 [ensureListening]。订阅的代价不小
/// ——本机会起日志轮询定时器，Herdr 与已绑定电脑各起一个后台循环——同时开
/// 几个编辑器页就不该有几套轮询。
class HarnessHub extends ChangeNotifier {
  HarnessHub({
    required List<HarnessHost> hosts,
    required bool desktop,
    String? initialHostId,
    bool ownsHosts = true,
    this.hostBuildError,
  }) : _desktop = desktop,
       _ownsHosts = ownsHosts {
    for (final host in hosts) {
      if (!hostVisibleOnPlatform(host.kind, desktop: desktop)) continue;
      _attachHost(host);
    }
    _currentHostId = _pickInitialHost(initialHostId);
    // 只订阅打开面板就要显示的那台，其余等用户切过去。
    final current = _currentHostId;
    if (current != null) ensureListening(current);
    _openHubs.add(this);
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

  final List<HarnessHost> _hosts = <HarnessHost>[];

  /// 只读视图：列表会随 [addHost] 增长，所以视图要跟着底层列表走。
  late final List<HarnessHost> _hostsView = UnmodifiableListView<HarnessHost>(
    _hosts,
  );
  final Map<String, HarnessHostState> _states = <String, HarnessHostState>{};
  final Map<String, VoidCallback> _stateListeners = <String, VoidCallback>{};
  final Map<String, List<HarnessSessionInfo>> _sessions =
      <String, List<HarnessSessionInfo>>{};
  final Map<String, StreamSubscription<List<HarnessSessionInfo>>> _subs =
      <String, StreamSubscription<List<HarnessSessionInfo>>>{};
  final Map<String, List<HarnessProviderInfo>> _providers =
      <String, List<HarnessProviderInfo>>{};
  final Map<String, Object> _sessionErrors = <String, Object>{};

  /// 已订阅会话列表的主机 id；订阅是按需建立的，见 [ensureListening]。
  final Set<String> _listening = <String>{};

  String? _currentHostId;
  HarnessSessionInfo? _activeSession;
  HarnessSessionHandle? _activeHandle;
  bool _opening = false;
  bool _disposed = false;

  /// [dispose] 发起的清理；[shutdown] 等它。
  Future<void>? _shutdown;

  /// 还活着的 hub，退出钩子用一次 [shutdownOpenHubs] 统一收尾。
  static final Set<HarnessHub> _openHubs = <HarnessHub>{};

  /// 释放所有还活着的 hub，并等它们真的释放完。
  ///
  /// 应用退出前调一次。只调 `dispose()` 不够：它是同步的，里面那些
  /// `await`（终止子进程、关连接）可能还没跑完进程就退了。
  static Future<void> shutdownOpenHubs() async {
    for (final hub in List<HarnessHub>.of(_openHubs)) {
      await hub.shutdown();
    }
  }

  /// 平台是否按桌面版处理，测试可注入。
  bool get isDesktop => _desktop;

  /// 已按平台过滤的主机，顺序即界面顺序。
  List<HarnessHost> get hosts => _hostsView;

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
    ensureListening(id);
    notifyListeners();
  }

  /// 订阅某台主机的会话列表；重复调用无副作用。
  ///
  /// hub 在构造、切换主机、打开或启动会话时自己会调。界面若要一次显示多台
  /// 主机的会话（例如“全部会话”），也得先对每台调一次，否则读到的是空表。
  void ensureListening(String hostId) {
    if (_disposed || _listening.contains(hostId)) return;
    final host = hostById(hostId);
    if (host == null) return;
    _listening.add(hostId);
    _listen(host);
  }

  /// 是否已订阅该主机的会话列表。
  bool isListening(String hostId) => _listening.contains(hostId);

  /// 订阅全部主机。重复调用无副作用。
  ///
  /// 首页要一次显示多台主机的会话，先调它再读 [allSessions]。
  void listenAll() {
    if (_disposed) return;
    for (final host in _hosts) {
      ensureListening(host.id);
    }
  }

  /// 全部会话的合并流。
  ///
  /// 订阅时先发一帧，之后每次 hub 通知再发一帧。取消订阅只移除监听，
  /// 不停掉主机的订阅。
  Stream<List<HarnessSessionInfo>> watchSessions({bool listenAll = true}) {
    if (listenAll) this.listenAll();
    late final StreamController<List<HarnessSessionInfo>> controller;
    void emit() {
      if (controller.isClosed) return;
      controller.add(allSessions);
    }

    controller = StreamController<List<HarnessSessionInfo>>(
      onListen: () {
        addListener(emit);
        emit();
      },
      onCancel: () => removeListener(emit),
    );
    return controller.stream;
  }

  /// 按主机 id 与会话 id 打开会话。
  ///
  /// 会话还没出现在列表里时先等一帧，超时抛 [HarnessHubException]。
  Future<HarnessSessionHandle> openSessionById(
    String hostId,
    String sessionId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final host = hostById(hostId);
    if (host == null) {
      throw HarnessHubException('找不到主机 $hostId，请刷新后重试');
    }
    HarnessSessionInfo? found;
    for (final session in sessionsOf(hostId)) {
      if (session.id == sessionId) {
        found = session;
        break;
      }
    }
    found ??= await _awaitSession(hostId, sessionId, timeout: timeout);
    if (found == null) {
      throw HarnessHubException('会话 $sessionId 没有出现在主机 $hostId 的列表里');
    }
    return openSession(found, hostId: hostId);
  }

  /// 等目标会话出现在列表里。超时返回 null。
  Future<HarnessSessionInfo?> _awaitSession(
    String hostId,
    String sessionId, {
    required Duration timeout,
  }) async {
    if (_disposed) return null;
    ensureListening(hostId);
    final completer = Completer<HarnessSessionInfo?>();
    void settle(HarnessSessionInfo? info) {
      if (!completer.isCompleted) completer.complete(info);
    }

    void onChanged() {
      for (final session in sessionsOf(hostId)) {
        if (session.id == sessionId) {
          settle(session);
          return;
        }
      }
    }

    addListener(onChanged);
    final timer = Timer(timeout, () => settle(null));
    try {
      onChanged();
      return await completer.future;
    } finally {
      timer.cancel();
      removeListener(onChanged);
    }
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

  /// 已订阅主机的会话合并，带主机 id，界面据此区分来源。
  ///
  /// 只包含订阅过的主机（当前主机与被访问过的主机）；要让某台主机进入
  /// 列表，先对它调一次 [ensureListening]。
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
    ensureListening(targetHostId);
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
    ensureListening(host.id);
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

  /// 重新订阅已订阅主机的会话列表，并丢弃 provider 缓存。
  ///
  /// 主机离线时订阅可能只是空表，用户点「刷新」就再要一次。刷新只动已经
  /// 订阅过的主机：点一次刷新不该把没在看的主机全唤醒。
  Future<void> refresh() async {
    if (_disposed) return;
    final current = _currentHostId;
    if (current != null) ensureListening(current);
    _providers.clear();
    for (final host in _hosts) {
      if (!_listening.contains(host.id)) continue;
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

  /// 运行时追加一台主机。
  ///
  /// 已绑定电脑要先异步打开存储才能装配，而 hub 的构造是同步的，所以远程主机
  /// 走这条路径。平台策略与构造时一致；重复 id 或该平台不可见的主机会被直接
  /// 释放，不留给界面一个点了会失败的空壳。
  void addHost(HarnessHost host) {
    if (_disposed) {
      unawaited(host.dispose());
      return;
    }
    if (!hostVisibleOnPlatform(host.kind, desktop: _desktop) ||
        hostById(host.id) != null) {
      unawaited(host.dispose());
      return;
    }
    _attachHost(host);
    _currentHostId ??= _pickInitialHost(null);
    final current = _currentHostId;
    if (current != null) ensureListening(current);
    notifyListeners();
  }

  /// 把一台主机接上监听；构造与 [addHost] 共用。
  void _attachHost(HarnessHost host) {
    _hosts.add(host);
    _states[host.id] = host.state.value;
    void onState() => _onHostState(host);
    _stateListeners[host.id] = onState;
    host.state.addListener(onState);
    // 会话订阅不在这里建立：状态点要立刻显示，会话列表等切过去再拉。
  }

  String? _pickInitialHost(String? initialHostId) {
    if (initialHostId != null && hostById(initialHostId) != null) {
      return initialHostId;
    }
    if (_hosts.isEmpty) return null;
    // 内置 Agent 是面板默认内容：它的会话历史、审批和输入框就是这一栏本来的
    // 样子，其他主机都是加进来的。没有内置 Agent 时才退到本机/已绑定电脑。
    for (final host in _hosts) {
      if (host.kind == HarnessHostKind.studio) return host.id;
    }
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
    if (_disposed) return;
    _disposed = true;
    _openHubs.remove(this);
    for (final entry in _subs.entries) {
      unawaited(entry.value.cancel());
    }
    _subs.clear();
    _listening.clear();
    final closing = <Future<void>>[];
    for (final host in _hosts) {
      final listener = _stateListeners.remove(host.id);
      if (listener != null) host.state.removeListener(listener);
      if (_ownsHosts) closing.add(host.dispose());
    }
    final handle = _activeHandle;
    _activeHandle = null;
    _activeSession = null;
    if (handle != null) closing.add(handle.detach());
    _shutdown = _drain(closing);
    super.dispose();
  }

  /// 释放并**等清理跑完**。
  ///
  /// [dispose] 是同步的（ChangeNotifier 的要求），它发起的释放还在路上：
  /// 一张会话视图要先把 `herdr agent attach` 的客户端 kill 掉，终止信号得
  /// 过几个 await 才发得出去。进程这时退出就会留下孤儿 attach，下次打开
  /// 还会说窗格被占用。所以退出钩子（见 `QfliApp`）等这一个。
  Future<void> shutdown() {
    final pending = _shutdown;
    if (pending != null) return pending;
    dispose();
    return _shutdown ?? Future<void>.value();
  }

  /// 一项一项等收尾；单项失败不挡其它项。
  static Future<void> _drain(List<Future<void>> futures) async {
    for (final future in futures) {
      try {
        await future;
      } on Object {
        // 一台主机释放失败不该挡住其它主机与子进程的收尾。
      }
    }
  }
}
