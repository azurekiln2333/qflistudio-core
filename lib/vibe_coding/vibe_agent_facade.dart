/// Agent 会话的界面契约与运行时。
///
/// 这一层是 UI 与 `VibeCodingController` 之间的适配：控制器负责模型/工具循环，
/// 这里负责会话身份、消息视图、权限模式、写确认、持久化和登录门控。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../interop/interop_runner.dart';
import '../services/api_client.dart';
import '../session/agent_perf.dart';
import '../session/agent_session.dart';
import 'agent_request_scheduler.dart';
import 'project_write_leases.dart';
import 'vibe_coding_controller.dart';

/// 写操作权限。
enum AgentPermissionMode {
  /// 只读：拒绝一切写入。
  readOnly,

  /// 每次写入都要用户确认。
  askEveryWrite,

  /// 自动接受写入。
  autoAcceptEdits,
}

/// 会话运行状态。
enum AgentRunState { idle, running, awaitingApproval, cancelling, failed }

/// 会话在运行时里的活动状态，供侧边栏会话列表显示。
///
/// 与 [AgentRunState] 的区别：这个状态属于运行时，包括用户当前没有打开的后台会话。
enum AgentLiveStatus {
  /// 没有活动，或结果已被用户看过。
  idle,

  /// 在排队，等并发名额或限流窗口。
  queued,

  /// 正在运行。
  running,

  /// 等待用户确认写入。
  awaitingApproval,

  /// 在后台失败，用户还没看。
  failed,

  /// 在后台完成，用户还没看。
  finishedUnread,
}

/// 可选模型。[reasoningEfforts] 为空表示不提供推理强度选择。
class AgentModelOption {
  const AgentModelOption({
    required this.id,
    required this.label,
    this.reasoningEfforts = const [],
  });

  final String id;
  final String label;
  final List<String> reasoningEfforts;

  bool get supportsReasoning => reasoningEfforts.isNotEmpty;
}

/// 技能索引条目；正文只在模型调用 `use_skill` 时取。
class AgentSkillRef {
  const AgentSkillRef({required this.name, required this.description});

  final String name;
  final String description;
}

/// 界面上的一条消息。
class AgentMessageView {
  const AgentMessageView({
    required this.id,
    required this.role,
    required this.text,
    this.toolName,
    this.isError = false,
    this.changedPaths = const [],
    this.pending = false,
    this.aiGenerated = false,
  });

  /// 会话内稳定标识，用于列表 key。
  final String id;

  /// `user` | `assistant` | `tool`。
  final String role;

  final String text;

  /// 工具条目对应的工具名；普通文本为 null。
  final String? toolName;

  /// 工具是否失败（含被权限拒绝的冲突）。
  final bool isError;

  /// 该工具真正写入的相对路径。
  final List<String> changedPaths;

  /// 是否仍在进行。
  final bool pending;

  /// 该条文本是否由 AI 生成。
  final bool aiGenerated;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    if (toolName != null) 'toolName': toolName,
    'isError': isError,
    if (changedPaths.isNotEmpty) 'changedPaths': changedPaths,
    'pending': pending,
    'aiGenerated': aiGenerated,
  };

  static AgentMessageView? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final role = value['role'];
    final text = value['text'];
    if (id is! String || id.isEmpty) return null;
    if (role is! String || role.isEmpty) return null;
    final paths = value['changedPaths'];
    return AgentMessageView(
      id: id,
      role: role,
      text: text is String ? text : '',
      toolName: value['toolName'] is String
          ? value['toolName'] as String
          : null,
      isError: value['isError'] == true,
      changedPaths: paths is List
          ? [
              for (final path in paths)
                if (path is String) path,
            ]
          : const [],
      pending: false,
      aiGenerated: value['aiGenerated'] == true,
    );
  }
}

/// 一次等待用户确认的写入。
class AgentWriteApproval {
  const AgentWriteApproval({required this.path, required this.summary});

  final String path;

  /// 改动摘要，可直接显示。
  final String summary;
}

/// 未登录就调用 agent 功能时抛出；界面据此引导登录（R8）。
class AgentLoginRequired implements Exception {
  const AgentLoginRequired();

  @override
  String toString() => 'AgentLoginRequired';
}

/// 失败原因的分类。界面据此选文案，见 design.md §11.6。
enum AgentErrorKind {
  loginExpired,
  rateLimited,
  notConfigured,
  offline,
  timeout,
  unknown,
}

/// 一次失败的结构化信息。
class AgentErrorInfo {
  const AgentErrorInfo({
    required this.kind,
    this.statusCode,
    this.detail = '',
    this.host = '',
    this.phase = AgentErrorPhase.other,
  });

  final AgentErrorKind kind;

  /// HTTP 状态码；不是 HTTP 错误时为 null。
  final int? statusCode;

  /// 多行的技术说明，只放进「详情」折叠区。不含密钥、令牌和请求正文。
  final String detail;

  /// 出错的服务器主机名，例如 `qfli.suanxiwanjie.cn`。未知时为空。
  final String host;

  /// 失败发生在哪一步。
  final AgentErrorPhase phase;
}

/// 失败发生在哪一步。界面据此写出「哪里坏了」。
enum AgentErrorPhase {
  /// 域名解析。
  dns,

  /// TCP 连接。
  connect,

  /// TLS 握手。
  tls,

  /// 等待响应超时。
  timeout,

  /// 服务器返回了 HTTP 错误。
  http,

  /// 响应内容无法解析。
  response,

  /// 其他或未知。
  other,
}

/// 一个实例对应一个会话。消息在会话结束时自动持久化。
abstract class AgentFacade extends ChangeNotifier {
  String get sessionId;
  List<AgentMessageView> get messages;
  AgentRunState get state;
  String? get lastError;

  /// 最近一次失败的分类。没有失败时为 null。由 pi-B 在返工阶段实现。
  AgentErrorInfo? get lastErrorInfo => null;

  /// 一句话说明正在做什么，例如「正在读取 lib/main.dart」。空闲时为 null。
  /// 由 pi-B 在返工阶段实现。
  String? get activity => null;

  /// 是否还有更早的消息没有载入。由 pi-B 在返工阶段实现。
  bool get hasEarlier => false;

  /// 载入更早的一页消息。由 pi-B 在返工阶段实现。
  Future<void> loadEarlier() async {}

  AgentWriteApproval? get pendingApproval;

  /// 当前权限模式。[send] 会更新它，界面也可直接设置。
  AgentPermissionMode get permission;
  set permission(AgentPermissionMode value);

  void resolveApproval(bool allow);

  /// 发送一条消息。未登录时抛 [AgentLoginRequired]。
  Future<void> send(
    String text, {
    List<String> attachedPaths = const [],
    required AgentPermissionMode permission,
    String? modelId,
    String? reasoningEffort,
  });

  Future<void> cancel();

  /// 重发上一条用户消息。
  Future<void> retryLast();

  /// 等待已排队的持久化完成（退出页面前用）。
  Future<void> flush();
}

/// 应用级单例：模型、技能、打开会话。
abstract class AgentRuntime {
  AgentSessionStore get sessions;

  /// 可用模型；未登录时抛 [AgentLoginRequired]。
  Future<List<AgentModelOption>> models();

  Future<List<AgentSkillRef>> skills(String projectId);

  /// 打开（或恢复）一个会话；未登录时抛 [AgentLoginRequired]。
  ///
  /// 同一个 [sessionId] 多次调用返回同一个实例。调用方不得 dispose 它。
  /// 实例由运行时持有。会话被删除、运行时释放、或空闲实例超过上限时才销毁。
  /// 切换会话只是换一个实例来显示，不会停止原来那个会话。
  Future<AgentFacade> open(String projectId, String sessionId);

  /// 任一会话的活动状态变化时通知，包括后台会话。
  Listenable get liveChanges;

  /// 某个会话当前的活动状态。
  AgentLiveStatus statusOf(String sessionId);

  /// 已经存在的会话实例，没有则返回 null。界面只借用，不得 dispose。
  AgentFacade? liveFacade(String sessionId);

  /// 用户查看了这个会话。清除 `finishedUnread` 与 `failed`。
  void markSeen(String sessionId);

  /// 停止全部运行中和排队中的会话。
  Future<void> cancelAll();

  /// 检查到 API 服务器的连接，逐步报告：域名解析、TCP 连接、TLS 握手。
  ///
  /// 只连接 API 服务器，不连接任何其他主机。返回多行文本，可直接显示。
  /// 由 pi-B 在第四轮实现；基线是占位，返回空文本。
  Future<String> diagnoseConnection();
}

/// 基于 [VibeCodingController] 的会话实现。
class VibeAgentFacade extends AgentFacade {
  VibeAgentFacade({
    required ApiClient api,
    required String? Function() tokenProvider,
    required AgentSessionStore store,
    required AgentSessionMeta meta,
    required String projectRoot,
    required String projectName,
    required String language,
    AiEndpoint Function()? endpointProvider,
    bool Function()? onlineAllowed,
    VibeProjectFiles? files,
    InteropRunner? interopRunner,
    List<Map<String, Object?>> restoredMessages = const [],
    bool hasEarlier = false,
    AgentRequestScheduler? scheduler,
    ProjectWriteLeases? leases,
  }) : _store = store,
       _meta = meta,
       _tokenProvider = tokenProvider,
       _leases = leases,
       _hasEarlier = hasEarlier,
       _controller = VibeCodingController(
         api: api,
         tokenProvider: tokenProvider,
         projectRoot: projectRoot,
         projectName: projectName,
         language: language,
         endpointProvider: endpointProvider,
         onlineAllowed: onlineAllowed,
         files: files,
         interopRunner: interopRunner,
         writeApproval: null,
       ) {
    _controller.writeApprovalHook = _handleApproval;
    _controller.requestScheduler = scheduler;
    _controller.schedulerKey = meta.id;
    // 路径租约接到既有的 shouldWrite 钩子上：被别的会话占着时拒绝覆盖。
    if (_leases case final leases?) {
      _controller.files.addWriteGuard(
        (absolute) => !leases.isHeldByOther(meta.id, absolute),
      );
    }
    final restored = <AgentMessageView>[];
    for (final entry in restoredMessages) {
      final view = AgentMessageView.fromJson(entry);
      if (view != null) restored.add(view);
    }
    _restored = List.unmodifiable(restored);
    // 尾部页本来就在盘上，不需要再写一次。
    _persistedCount = restored.length;
    _nextMessageId = restored.length;
    _controller.addListener(_sync);
    _lastPhase = _controller.phase;
  }

  final AgentSessionStore _store;
  final String? Function() _tokenProvider;
  final ProjectWriteLeases? _leases;
  final VibeCodingController _controller;

  AgentSessionMeta _meta;

  /// 打开会话时读到的尾部消息；[loadEarlier] 往前面加。
  List<AgentMessageView> _restored = const [];

  /// 本次运行产生的消息；由控制器投影而来。
  List<AgentMessageView> _runViews = const [];

  AgentPermissionMode _permission = AgentPermissionMode.askEveryWrite;
  AgentWriteApproval? _pendingApproval;
  Completer<bool>? _pendingCompleter;
  String? _lastUserText;
  VibePhase _lastPhase = VibePhase.idle;

  /// 已经写给存储的消息条数（含尾部页）。
  int _persistedCount = 0;

  /// 消息 id 序号；重新打开会话时从已有条数继续，避免和旧 id 撞车。
  int _nextMessageId = 0;

  /// 控制器消息下标 → 会话内稳定 id。
  final Map<int, String> _idByIndex = {};

  /// 同步段先给界面的用户消息；控制器接管后清空。
  AgentMessageView? _optimistic;

  bool _starting = false;

  /// 用户在「已显示反馈、还没真正开始」的窗口里点了停止。
  bool _cancelBeforeStart = false;
  bool _hasEarlier;
  bool _loadingEarlier = false;
  bool _historyLoaded = false;
  bool _disposed = false;

  /// 本轮占着的写路径；本轮结束、取消、销毁时释放。
  final Set<String> _heldPaths = {};

  /// 持久化串行队列：上一次写完再写下一次，避免同文件并发。
  Future<void> _persistChain = Future<void>.value();
  String? _persistError;

  @override
  String get sessionId => _meta.id;

  @override
  List<AgentMessageView> get messages => List.unmodifiable([
    ..._restored,
    ..._runViews,
    ?_optimistic,
  ]);

  @override
  AgentRunState get state {
    if (_pendingApproval != null) return AgentRunState.awaitingApproval;
    if (_starting) return AgentRunState.running;
    return switch (_controller.phase) {
      VibePhase.running => AgentRunState.running,
      VibePhase.cancelling => AgentRunState.cancelling,
      VibePhase.failed => AgentRunState.failed,
      _ => AgentRunState.idle,
    };
  }

  @override
  String? get lastError => _controller.lastError;

  @override
  AgentErrorInfo? get lastErrorInfo {
    final api = _controller.lastApiError;
    final message = _controller.lastError;
    if (api == null) {
      if (message == null) return null;
      return AgentErrorInfo(
        kind: _kindOfMessage(message),
        detail: message,
      );
    }
    return AgentErrorInfo(
      kind: _kindOf(api),
      statusCode: api.statusCode,
      detail: api.message,
    );
  }

  @override
  String? get activity => _controller.activity;

  @override
  bool get hasEarlier => _hasEarlier;

  @override
  Future<void> loadEarlier() async {
    if (!_hasEarlier || _loadingEarlier) return;
    final first = _restored.isNotEmpty ? _restored.first.id : null;
    if (first == null) {
      _hasEarlier = false;
      notifyListeners();
      return;
    }
    _loadingEarlier = true;
    try {
      final page = await _store.readBefore(
        _meta.id,
        beforeId: first,
        limit: 60,
      );
      final earlier = <AgentMessageView>[];
      for (final entry in page.messages) {
        final view = AgentMessageView.fromJson(entry);
        if (view != null) earlier.add(view);
      }
      if (earlier.isNotEmpty) {
        _restored = [...earlier, ..._restored];
        // 这些消息早就在盘上了。
        _persistedCount += earlier.length;
      }
      _hasEarlier = page.hasEarlier;
    } on Object {
      // 读不到就保持现状，用户可以再点一次。
    } finally {
      _loadingEarlier = false;
      notifyListeners();
    }
  }

  /// HTTP 异常 → 界面文案分类。
  static AgentErrorKind _kindOf(ApiException error) {
    final code = error.details['code'];
    if (code is String) {
      switch (code) {
        case 'AI_NOT_CONFIGURED':
          return AgentErrorKind.notConfigured;
        case 'RATE_LIMITED':
          return AgentErrorKind.rateLimited;
        case 'UNAUTHORIZED':
          return AgentErrorKind.loginExpired;
        case 'TIMEOUT':
          return AgentErrorKind.timeout;
        case 'OFFLINE':
        case 'NETWORK':
          return AgentErrorKind.offline;
      }
    }
    switch (error.statusCode) {
      case 401:
        return AgentErrorKind.loginExpired;
      case 429:
        return AgentErrorKind.rateLimited;
      case 503:
        if (error.message.contains('AI 服务未配置')) {
          return AgentErrorKind.notConfigured;
        }
    }
    return _kindOfMessage(error.message);
  }

  /// 只有文案时的退路：按关键词归类。
  static AgentErrorKind _kindOfMessage(String message) {
    if (message.contains('AI 服务未配置') || message.contains('未配置')) {
      return AgentErrorKind.notConfigured;
    }
    if (message.contains('登录') &&
        (message.contains('过期') || message.contains('请先'))) {
      return AgentErrorKind.loginExpired;
    }
    if (message.contains('频繁') || message.contains('429')) {
      return AgentErrorKind.rateLimited;
    }
    if (message.contains('超时')) return AgentErrorKind.timeout;
    if (message.contains('网络') ||
        message.contains('无法连接') ||
        message.contains('连接')) {
      return AgentErrorKind.offline;
    }
    return AgentErrorKind.unknown;
  }

  /// 最近一次会话保存失败的原因；保存正常时为 null。
  String? get persistError => _persistError;

  /// 等待已排队的写入完成（界面退出前可用）。
  @override
  Future<void> flush() => _persistChain;

  @override
  AgentWriteApproval? get pendingApproval => _pendingApproval;

  /// 当前权限模式；界面切换时同步。
  @override
  AgentPermissionMode get permission => _permission;

  @override
  set permission(AgentPermissionMode value) {
    if (_permission == value) return;
    _permission = value;
    notifyListeners();
  }

  @override
  void resolveApproval(bool allow) {
    final completer = _pendingCompleter;
    _pendingApproval = null;
    _pendingCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete(allow);
    notifyListeners();
  }

  @override
  Future<void> send(
    String text, {
    List<String> attachedPaths = const [],
    required AgentPermissionMode permission,
    String? modelId,
    String? reasoningEffort,
  }) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) throw const AgentLoginRequired();
    final body = text.trim();
    if (body.isEmpty) return;
    final feedbackWatch = Stopwatch()..start();
    _permission = permission;
    _lastUserText = body;
    _cancelBeforeStart = false;
    _controller.configureModel(
      modelId: modelId,
      reasoningEffort: reasoningEffort,
    );
    final composed = _compose(body, _resolveAttachments(attachedPaths));
    // 同步段：这一帧就要看到用户消息和运行状态。这里不做任何磁盘 I/O。
    _optimistic = AgentMessageView(
      id: 'pending-user',
      role: 'user',
      text: composed,
    );
    _starting = true;
    notifyListeners();
    // 「发送到出现用户消息」的耗时，不含网络与磁盘。
    agentPerf('send.feedback', feedbackWatch.elapsedMilliseconds);
    try {
      // 历史推迟到第一次发送时才读：打开会话不需要它。
      await _ensureHistoryLoaded();
    } finally {
      _optimistic = null;
      _starting = false;
    }
    if (_disposed || _cancelBeforeStart) {
      _cancelBeforeStart = false;
      return;
    }
    _controller.send(composed);
    _sync();
    // 标题只是列表的装饰，不能拖住发送。
    unawaited(_maybeRetitle(body));
    unawaited(_persist());
  }

  /// 恢复模型历史；只做一次。
  ///
  /// 读不到历史不影响发送：最多少一点上下文。
  Future<void> _ensureHistoryLoaded() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      final history = await _store.readHistory(_meta.id);
      if (history.isNotEmpty && !_disposed) {
        _controller.restoreHistory(history);
      }
    } on Object {
      // 历史缺失不阻塞发送。
    }
  }

  /// 把附件分成项目内和项目外两组。
  ///
  /// 项目内用相对路径（受原有沙箱约束），项目外用规范化绝对路径并登记为本
  /// 会话的只读白名单，模型才能用 `read_file` 取到正文。写、编辑、列目录、
  /// 搜索不会因此延伸到项目外。
  List<String> _resolveAttachments(List<String> attachedPaths) {
    final root = _controller.projectRoot;
    final resolved = <String>{};
    final outside = <String>[];
    for (final raw in attachedPaths) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final absolute = p.normalize(
        p.isAbsolute(trimmed) ? trimmed : p.join(root, trimmed),
      );
      if (p.equals(absolute, root) || p.isWithin(root, absolute)) {
        resolved.add(p.relative(absolute, from: root).replaceAll('\\', '/'));
      } else {
        resolved.add(absolute.replaceAll('\\', '/'));
        outside.add(absolute);
      }
    }
    if (outside.isNotEmpty) _controller.allowReadOnlyFiles(outside);
    return resolved.toList();
  }

  @override
  Future<void> cancel() async {
    final completer = _pendingCompleter;
    _pendingApproval = null;
    _pendingCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete(false);
    if (_starting) {
      // 还没进入控制器：记下来，send 恢复后不再启动本轮。
      _cancelBeforeStart = true;
      _starting = false;
      _optimistic = null;
    }
    await _controller.cancel();
    _releaseLeases();
    _sync();
  }

  @override
  Future<void> retryLast() async {
    final text = _lastUserText;
    if (text == null || state == AgentRunState.running) return;
    await send(text, permission: _permission);
  }

  @override
  void dispose() {
    _disposed = true;
    final completer = _pendingCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(false);
    _releaseLeases();
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  /// 本轮占着的写路径全部释放。
  void _releaseLeases() {
    final leases = _leases;
    if (leases == null) return;
    leases.releaseAll(_meta.id);
    _heldPaths.clear();
  }

  /// 写盘前的权限判定；返回 null 放行，返回字符串作为拒绝原因。
  ///
  /// 放行前先取路径租约：同一个文件被另一个运行中的会话占着时，后到的得到
  /// 冲突，文件不会被覆盖。
  Future<String?> _handleApproval(VibeWriteRequest request) async {
    switch (_permission) {
      case AgentPermissionMode.readOnly:
        return '当前是只读模式，不允许写入。切换到“每次询问”或“自动接受”后再试';
      case AgentPermissionMode.autoAcceptEdits:
      case AgentPermissionMode.askEveryWrite:
        break;
    }
    final leases = _leases;
    if (leases != null) {
      final lease = leases.acquire(
        sessionId: _meta.id,
        sessionLabel: _meta.title,
        path: request.path,
      );
      if (!lease.granted) return lease.conflict;
      _heldPaths.add(request.path);
    }
    if (_permission == AgentPermissionMode.autoAcceptEdits) return null;
    final completer = Completer<bool>();
    _pendingApproval = AgentWriteApproval(
      path: request.path,
      summary: request.summary,
    );
    _pendingCompleter = completer;
    notifyListeners();
    final allowed = await completer.future;
    _pendingApproval = null;
    _pendingCompleter = null;
    if (!allowed) {
      leases?.release(_meta.id, request.path);
      _heldPaths.remove(request.path);
    }
    notifyListeners();
    return allowed ? null : '用户拒绝了这次写入';
  }

  /// 把控制器状态搬到视图层，并在本轮结束时落盘。
  void _sync() {
    final source = _controller.messages;
    _idByIndex.removeWhere((index, _) => index >= source.length);
    final next = <AgentMessageView>[];
    for (var index = 0; index < source.length; index++) {
      final message = source[index];
      final tool = message.tool;
      final id = _idByIndex.putIfAbsent(index, () => 'm${_nextMessageId++}');
      next.add(
        AgentMessageView(
          id: id,
          role: tool != null ? 'tool' : (message.isUser ? 'user' : 'assistant'),
          text: tool != null ? (tool.result ?? '') : message.text,
          toolName: tool?.toolName,
          isError:
              tool != null &&
              (tool.status == VibeToolStatus.error ||
                  tool.status == VibeToolStatus.conflict),
          changedPaths: tool?.changedPaths ?? const [],
          pending: message.pending,
          aiGenerated: message.aiGenerated,
        ),
      );
    }
    if (source.isNotEmpty) {
      // 控制器已接管用户消息，乐观条目下台。
      _optimistic = null;
      _starting = false;
    }
    _runViews = next;
    final phase = _controller.phase;
    final settled = phase != VibePhase.running && phase != VibePhase.cancelling;
    final wasRunning =
        _lastPhase == VibePhase.running || _lastPhase == VibePhase.cancelling;
    _lastPhase = phase;
    notifyListeners();
    if (settled && (wasRunning || _heldPaths.isNotEmpty)) {
      // 本轮结束：释放路径租约，再收尾落盘。
      _releaseLeases();
      unawaited(_persist());
    }
  }

  Future<void> _persist() {
    final next = _persistChain.then((_) => _writeTranscript());
    // 链上必须吞掉异常，否则一次失败会让后续写入全部跳过。
    _persistChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// 只追加还没写过的消息，再写一份历史快照。
  Future<void> _writeTranscript() async {
    try {
      final views = [..._restored, ..._runViews];
      for (var index = _persistedCount; index < views.length; index++) {
        await _store.appendMessage(_meta.id, _persistable(views[index]));
      }
      _persistedCount = views.length;
      await _store.writeHistory(
        _meta.id,
        _persistableHistory(_controller.history),
      );
      final meta = _store.metaOf(_meta.id);
      if (meta != null) _meta = meta;
      _persistError = null;
    } on Object catch (error) {
      // 保存失败不能把一次已经完成的对话炸掉，但要留下可查的原因。
      _persistError = '会话保存失败：$error';
      notifyListeners();
    }
  }

  /// 工具输出落盘前截断到 8 KB；完整输出只在内存里，不写文件。
  ///
  /// 视图里的工具条目只是摘要，真正的完整输出在模型历史的 `tool` 条目里，
  /// 所以两处都截。
  static const int _maxPersistedToolChars = 8 * 1024;

  static List<Map<String, Object?>> _persistableHistory(
    List<Map<String, dynamic>> history,
  ) => [
    for (final entry in history)
      if (entry['role'] == 'tool' &&
          entry['content'] is String &&
          (entry['content'] as String).length > _maxPersistedToolChars)
        {
          ...entry,
          'content':
              '…（已截断，只保留最后 8 KB）\n'
              '${(entry['content'] as String).substring((entry['content'] as String).length - _maxPersistedToolChars)}',
        }
      else
        Map<String, Object?>.from(entry),
  ];

  static Map<String, Object?> _persistable(AgentMessageView view) {
    if (view.role != 'tool' || view.text.length <= _maxPersistedToolChars) {
      return view.toJson();
    }
    final tail = view.text.substring(
      view.text.length - _maxPersistedToolChars,
    );
    return AgentMessageView(
      id: view.id,
      role: view.role,
      text: '…（已截断，只保留最后 8 KB）\n$tail',
      toolName: view.toolName,
      isError: view.isError,
      changedPaths: view.changedPaths,
      aiGenerated: view.aiGenerated,
    ).toJson();
  }

  /// 第一条消息决定会话标题，用户改名后不再覆盖。
  Future<void> _maybeRetitle(String text) async {
    if (_meta.title != AgentSessionStore.defaultTitle) return;
    final firstLine = text.split('\n').first.trim();
    if (firstLine.isEmpty) return;
    final title = firstLine.length <= 24
        ? firstLine
        : '${firstLine.substring(0, 24)}…';
    await _store.rename(_meta.id, title);
    final meta = _store.metaOf(_meta.id);
    if (meta != null) _meta = meta;
  }

  /// 附件只写路径，不把正文塞进消息；模型需要内容时自己 read_file。
  ///
  /// 项目外的附件是只读的，文案里讲明白，免得模型去改它们。
  static String _compose(String text, List<String> attachments) {
    if (attachments.isEmpty) return text;
    final list = attachments.map((path) => '- $path').join('\n');
    return '$text\n\n附带的文件（需要内容时用 read_file 打开，只用相对项目根的路径才能写）：\n$list';
  }
}

/// 应用级实现：模型目录、技能索引、会话注册表。
///
/// 一个会话一个实例，按 `sessionId` 复用。切换会话只是换一个实例显示，
/// 不会停掉原来那个。空闲且已读的实例超过 [maxIdleFacades] 时销毁最久未用的；
/// 运行中的永不销毁。
class VibeAgentRuntime implements AgentRuntime {
  VibeAgentRuntime({
    required ApiClient api,
    required String? Function() tokenProvider,
    required AgentSessionStore sessions,
    required String Function(String projectId) projectRootOf,
    String Function(String projectId)? languageOf,
    AiEndpoint Function()? endpointProvider,
    bool Function()? onlineAllowed,
    VibeProjectFiles Function(String projectRoot)? filesFactory,
    InteropRunner? Function(String projectId)? interopRunnerOf,
    String Function()? configuredModel,
    AgentRequestScheduler? scheduler,
    Directory? cacheDir,
    this.maxIdleFacades = 8,
    this.pageSize = 60,
  }) : _api = api,
       _tokenProvider = tokenProvider,
       _sessions = sessions,
       _projectRootOf = projectRootOf,
       _languageOf = languageOf,
       _endpointProvider = endpointProvider,
       _onlineAllowed = onlineAllowed,
       _filesFactory = filesFactory,
       _interopRunnerOf = interopRunnerOf,
       _configuredModel = configuredModel,
       _scheduler = scheduler ?? AgentRequestScheduler(),
       _cacheDir = cacheDir {
    _sessions.addListener(_onSessionsChanged);
  }

  /// 空闲且已读的实例上限。
  final int maxIdleFacades;

  /// 打开会话时读多少条尾部消息。
  final int pageSize;

  static const Duration _modelsTtl = Duration(minutes: 10);

  final ApiClient _api;
  final String? Function() _tokenProvider;
  final AgentSessionStore _sessions;
  final String Function(String projectId) _projectRootOf;
  final String Function(String projectId)? _languageOf;
  final AiEndpoint Function()? _endpointProvider;
  final bool Function()? _onlineAllowed;
  final VibeProjectFiles Function(String projectRoot)? _filesFactory;
  final InteropRunner? Function(String projectId)? _interopRunnerOf;
  final String Function()? _configuredModel;
  final AgentRequestScheduler _scheduler;
  final Directory? _cacheDir;

  final Map<String, VibeAgentFacade> _facades = {};
  final Map<String, DateTime> _lastUsed = {};
  final Map<String, AgentLiveStatus> _lastStatus = {};
  final Set<String> _active = {};
  final Set<String> _unread = {};
  final Set<String> _failedUnread = {};
  final Map<String, ProjectWriteLeases> _leasesByRoot = {};

  List<AgentModelOption>? _memoryModels;
  DateTime? _memoryModelsAt;

  final ValueNotifier<int> _liveTick = ValueNotifier<int>(0);

  @override
  AgentSessionStore get sessions => _sessions;

  @override
  Listenable get liveChanges => _liveTick;

  @override
  AgentLiveStatus statusOf(String sessionId) {
    final facade = _facades[sessionId];
    if (facade == null) return AgentLiveStatus.idle;
    if (_scheduler.isWaiting(sessionId)) return AgentLiveStatus.queued;
    return switch (facade.state) {
      AgentRunState.running || AgentRunState.cancelling =>
        AgentLiveStatus.running,
      AgentRunState.awaitingApproval => AgentLiveStatus.awaitingApproval,
      AgentRunState.failed => _failedUnread.contains(sessionId)
          ? AgentLiveStatus.failed
          : AgentLiveStatus.idle,
      AgentRunState.idle => _unread.contains(sessionId)
          ? AgentLiveStatus.finishedUnread
          : AgentLiveStatus.idle,
    };
  }

  @override
  AgentFacade? liveFacade(String sessionId) => _facades[sessionId];

  @override
  void markSeen(String sessionId) {
    final changed =
        _unread.remove(sessionId) | _failedUnread.remove(sessionId);
    if (changed) _liveTick.value++;
  }

  @override
  Future<void> cancelAll() async {
    for (final facade in _facades.values.toList()) {
      if (facade.state == AgentRunState.running ||
          facade.state == AgentRunState.awaitingApproval ||
          facade.state == AgentRunState.cancelling) {
        await facade.cancel();
      }
    }
    _scheduler.cancelWaiting();
  }

  // 连接诊断由 pi-B 在第四轮实现。下面是能编译的占位。
  @override
  Future<String> diagnoseConnection() async => '';

  @override
  Future<List<AgentModelOption>> models() async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) throw const AgentLoginRequired();
    final cached = await _readModelsCache();
    if (cached != null) return cached;
    try {
      final list = await _api.aiModels(
        token: token,
        endpoint: _endpointProvider?.call(),
      );
      if (list.isNotEmpty) {
        final options = [
          for (final model in list)
            AgentModelOption(
              id: model.id,
              label: model.id,
              reasoningEfforts: model.reasoningEfforts,
            ),
        ];
        await _writeModelsCache(options);
        return options;
      }
    } on Object {
      // 目录接口不可用时退回设置里的单个模型，不让选择器变成硬错误。
    }
    final fallback = _configuredModel?.call().trim() ?? '';
    if (fallback.isEmpty) return const [];
    return [AgentModelOption(id: fallback, label: fallback)];
  }

  @override
  Future<List<AgentSkillRef>> skills(String projectId) async {
    final library = VibeSkillLibrary(
      projectRoot: _projectRootOf(projectId),
      language: _languageOf?.call(projectId) ?? '',
    );
    final skills = await library.load();
    return [
      for (final skill in skills)
        AgentSkillRef(name: skill.name, description: skill.description),
    ];
  }

  @override
  Future<AgentFacade> open(String projectId, String sessionId) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) throw const AgentLoginRequired();
    final live = _facades[sessionId];
    if (live != null) {
      _lastUsed[sessionId] = DateTime.now();
      return live;
    }
    final watch = Stopwatch()..start();
    final meta = _sessions.metaOf(sessionId);
    if (meta == null) {
      throw ArgumentError.value(sessionId, 'sessionId', '会话不存在');
    }
    final root = _projectRootOf(projectId);
    // 只读尾部一页：打开会话不等网络，也不解析全文。
    final page = await _sessions.readTail(sessionId, limit: pageSize);
    final facade = VibeAgentFacade(
      api: _api,
      tokenProvider: _tokenProvider,
      store: _sessions,
      meta: meta,
      projectRoot: root,
      projectName: p.basename(root),
      language: _languageOf?.call(projectId) ?? '',
      endpointProvider: _endpointProvider,
      onlineAllowed: _onlineAllowed,
      files: _filesFactory?.call(root),
      interopRunner: _interopRunnerOf?.call(projectId),
      restoredMessages: page.messages,
      hasEarlier: page.hasEarlier,
      scheduler: _scheduler,
      leases: _leasesFor(root),
    );
    _facades[sessionId] = facade;
    _lastUsed[sessionId] = DateTime.now();
    facade.addListener(() => _onFacadeChanged(sessionId));
    _lastStatus[sessionId] = statusOf(sessionId);
    agentPerf('session.open', watch.elapsedMilliseconds);
    _evictIfNeeded();
    return facade;
  }

  /// 某个项目的路径租约表；同项目根的会话共用一份。
  ProjectWriteLeases _leasesFor(String root) {
    final key = root.isEmpty ? '' : p.normalize(p.absolute(root));
    return _leasesByRoot.putIfAbsent(
      key,
      () => ProjectWriteLeases(projectRoot: key),
    );
  }

  void _onFacadeChanged(String sessionId) {
    final facade = _facades[sessionId];
    if (facade == null) return;
    final state = facade.state;
    final isActive =
        state == AgentRunState.running ||
        state == AgentRunState.awaitingApproval ||
        state == AgentRunState.cancelling;
    if (isActive) {
      _active.add(sessionId);
      _unread.remove(sessionId);
      _failedUnread.remove(sessionId);
    } else if (_active.remove(sessionId)) {
      // 后台刚结束：失败进「失败未读」，其余进「完成未读」。
      if (state == AgentRunState.failed) {
        _failedUnread.add(sessionId);
      } else if (state == AgentRunState.idle) {
        _unread.add(sessionId);
      }
    }
    final next = statusOf(sessionId);
    if (_lastStatus[sessionId] == next) return;
    _lastStatus[sessionId] = next;
    _liveTick.value++;
  }

  /// 销毁空闲且已读的旧实例，直到不超过上限。
  void _evictIfNeeded() {
    while (_facades.length > maxIdleFacades) {
      String? victim;
      DateTime? oldest;
      for (final entry in _facades.entries) {
        final id = entry.key;
        if (_active.contains(id)) continue;
        if (statusOf(id) != AgentLiveStatus.idle) continue;
        final used = _lastUsed[id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (oldest == null || used.isBefore(oldest)) {
          oldest = used;
          victim = id;
        }
      }
      if (victim == null) return;
      _destroy(victim);
    }
  }

  void _destroy(String sessionId) {
    final facade = _facades.remove(sessionId);
    _lastUsed.remove(sessionId);
    _lastStatus.remove(sessionId);
    _active.remove(sessionId);
    _unread.remove(sessionId);
    _failedUnread.remove(sessionId);
    facade?.dispose();
  }

  /// 会话被删除：先停掉再销毁实例。
  void _onSessionsChanged() {
    for (final id in _facades.keys.toList()) {
      if (_sessions.metaOf(id) != null) continue;
      final facade = _facades[id];
      if (facade == null) continue;
      if (facade.state != AgentRunState.idle) {
        unawaited(
          facade.cancel().whenComplete(() {
            _destroy(id);
            _liveTick.value++;
          }),
        );
      } else {
        _destroy(id);
        _liveTick.value++;
      }
    }
  }

  File? get _modelsCacheFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File(p.join(dir.path, 'models_cache.json'));
  }

  /// 缓存顺次：内存，盘，都不新鲜返回 null。
  Future<List<AgentModelOption>?> _readModelsCache() async {
    final now = DateTime.now();
    final at = _memoryModelsAt;
    final memory = _memoryModels;
    if (memory != null && at != null && now.difference(at) < _modelsTtl) {
      return memory;
    }
    final file = _modelsCacheFile;
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final fetched = DateTime.tryParse('${decoded['fetchedAt'] ?? ''}');
      if (fetched == null || now.difference(fetched) >= _modelsTtl) return null;
      final list = decoded['models'];
      if (list is! List) return null;
      final models = <AgentModelOption>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final id = entry['id'];
        if (id is! String || id.isEmpty) continue;
        final efforts = entry['reasoning_efforts'];
        models.add(
          AgentModelOption(
            id: id,
            label: entry['label'] is String ? entry['label'] as String : id,
            reasoningEfforts: efforts is List
                ? [
                    for (final effort in efforts)
                      if (effort is String) effort,
                  ]
                : const [],
          ),
        );
      }
      if (models.isEmpty) return null;
      _memoryModels = models;
      _memoryModelsAt = fetched;
      return models;
    } on Object {
      // 缓存坏了就当没有。
      return null;
    }
  }

  Future<void> _writeModelsCache(List<AgentModelOption> models) async {
    final now = DateTime.now();
    _memoryModels = models;
    _memoryModelsAt = now;
    final file = _modelsCacheFile;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'fetchedAt': now.toIso8601String(),
          'models': [
            for (final model in models)
              {
                'id': model.id,
                'label': model.label,
                'reasoning_efforts': model.reasoningEfforts,
              },
          ],
        }),
        flush: true,
      );
    } on Object {
      // 写缓存失败不影响本次结果。
    }
  }
}
