/// Agent 会话的界面契约与运行时。
///
/// 这一层是 UI 与 `VibeCodingController` 之间的适配：控制器负责模型/工具循环，
/// 这里负责会话身份、消息视图、权限模式、写确认、持久化和登录门控。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../interop/interop_runner.dart';
import '../services/api_client.dart';
import '../session/agent_session.dart';
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
  const AgentErrorInfo({required this.kind, this.statusCode, this.detail = ''});

  final AgentErrorKind kind;

  /// HTTP 状态码；不是 HTTP 错误时为 null。
  final int? statusCode;

  /// 服务端原文或异常摘要，只放进「详情」折叠区。不含密钥。
  final String detail;
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
    List<Map<String, Object?>> restoredHistory = const [],
  }) : _store = store,
       _meta = meta,
       _tokenProvider = tokenProvider,
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
    if (restoredHistory.isNotEmpty) {
      _controller.restoreHistory(restoredHistory);
    }
    final restored = <AgentMessageView>[];
    for (final entry in restoredMessages) {
      final view = AgentMessageView.fromJson(entry);
      if (view != null) restored.add(view);
    }
    _views = restored;
    _controller.addListener(_sync);
    _lastPhase = _controller.phase;
  }

  final AgentSessionStore _store;
  final String? Function() _tokenProvider;
  final VibeCodingController _controller;

  AgentSessionMeta _meta;
  List<AgentMessageView> _views = const [];
  AgentPermissionMode _permission = AgentPermissionMode.askEveryWrite;
  AgentWriteApproval? _pendingApproval;
  Completer<bool>? _pendingCompleter;
  String? _lastUserText;
  VibePhase _lastPhase = VibePhase.idle;

  /// 持久化串行队列：上一次写完再写下一次，避免同文件并发。
  Future<void> _persistChain = Future<void>.value();
  String? _persistError;

  @override
  String get sessionId => _meta.id;

  @override
  List<AgentMessageView> get messages => List.unmodifiable(_views);

  @override
  AgentRunState get state {
    if (_pendingApproval != null) return AgentRunState.awaitingApproval;
    return switch (_controller.phase) {
      VibePhase.running => AgentRunState.running,
      VibePhase.cancelling => AgentRunState.cancelling,
      VibePhase.failed => AgentRunState.failed,
      _ => AgentRunState.idle,
    };
  }

  @override
  String? get lastError => _controller.lastError;

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
    _permission = permission;
    _lastUserText = body;
    _controller.configureModel(
      modelId: modelId,
      reasoningEffort: reasoningEffort,
    );
    await _maybeRetitle(body);
    _controller.send(_compose(body, _resolveAttachments(attachedPaths)));
    _sync();
    unawaited(_persist());
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
    await _controller.cancel();
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
    final completer = _pendingCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(false);
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  /// 写盘前的权限判定；返回 null 放行，返回字符串作为拒绝原因。
  Future<String?> _handleApproval(VibeWriteRequest request) async {
    switch (_permission) {
      case AgentPermissionMode.readOnly:
        return '当前是只读模式，不允许写入。切换到“每次询问”或“自动接受”后再试';
      case AgentPermissionMode.autoAcceptEdits:
        return null;
      case AgentPermissionMode.askEveryWrite:
        break;
    }
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
    notifyListeners();
    return allowed ? null : '用户拒绝了这次写入';
  }

  /// 把控制器状态搬到视图层，并在本轮结束时落盘。
  void _sync() {
    final next = <AgentMessageView>[];
    final source = _controller.messages;
    for (var index = 0; index < source.length; index++) {
      final message = source[index];
      final tool = message.tool;
      next.add(
        AgentMessageView(
          id: 'm$index',
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
    _views = next;
    final phase = _controller.phase;
    final settled = phase != VibePhase.running && phase != VibePhase.cancelling;
    final wasRunning =
        _lastPhase == VibePhase.running || _lastPhase == VibePhase.cancelling;
    _lastPhase = phase;
    notifyListeners();
    if (settled && wasRunning) unawaited(_persist());
  }

  Future<void> _persist() {
    final next = _persistChain.then((_) => _writeTranscript());
    // 链上必须吞掉异常，否则一次失败会让后续写入全部跳过。
    _persistChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _writeTranscript() async {
    try {
      await _store.write(
        _meta.id,
        AgentTranscript(
          messages: [for (final view in _views) view.toJson()],
          history: _controller.history,
        ),
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

/// 应用级实现：模型目录、技能索引、打开会话。
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
  }) : _api = api,
       _tokenProvider = tokenProvider,
       _sessions = sessions,
       _projectRootOf = projectRootOf,
       _languageOf = languageOf,
       _endpointProvider = endpointProvider,
       _onlineAllowed = onlineAllowed,
       _filesFactory = filesFactory,
       _interopRunnerOf = interopRunnerOf,
       _configuredModel = configuredModel;

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

  @override
  AgentSessionStore get sessions => _sessions;

  // 并行会话的注册表由 pi-B 在返工阶段实现。下面是能编译的占位。
  final ValueNotifier<int> _liveTick = ValueNotifier<int>(0);

  @override
  Listenable get liveChanges => _liveTick;

  @override
  AgentLiveStatus statusOf(String sessionId) => AgentLiveStatus.idle;

  @override
  AgentFacade? liveFacade(String sessionId) => null;

  @override
  void markSeen(String sessionId) {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<AgentModelOption>> models() async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) throw const AgentLoginRequired();
    try {
      final list = await _api.aiModels(
        token: token,
        endpoint: _endpointProvider?.call(),
      );
      if (list.isNotEmpty) {
        return [
          for (final model in list)
            AgentModelOption(
              id: model.id,
              label: model.id,
              reasoningEfforts: model.reasoningEfforts,
            ),
        ];
      }
    } on ApiException {
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
    final meta = _sessions.metaOf(sessionId);
    if (meta == null) {
      throw ArgumentError.value(sessionId, 'sessionId', '会话不存在');
    }
    final root = _projectRootOf(projectId);
    final transcript = await _sessions.read(sessionId);
    return VibeAgentFacade(
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
      restoredMessages: transcript.messages,
      restoredHistory: transcript.history,
    );
  }
}
