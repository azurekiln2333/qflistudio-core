import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

/// 记录调用参数的会话门面，供输入卡片与对话流的 widget 测试使用。
class FakeAgentFacade extends AgentFacade {
  FakeAgentFacade({this.sessionId = 'fake-session'});

  @override
  final String sessionId;

  final List<AgentMessageView> _messages = <AgentMessageView>[];
  final List<String> sentTexts = <String>[];
  final List<List<String>> sentAttachments = <List<String>>[];
  final List<AgentPermissionMode> sentPermissions = <AgentPermissionMode>[];
  final List<String?> sentModels = <String?>[];
  final List<String?> sentEfforts = <String?>[];
  final List<bool> approvals = <bool>[];
  int cancelCount = 0;
  int retryCount = 0;

  /// 发送时抛 [AgentLoginRequired]，用于验证登录门控。
  bool throwLoginRequired = false;

  @override
  List<AgentMessageView> get messages => List.unmodifiable(_messages);

  AgentRunState _state = AgentRunState.idle;

  AgentPermissionMode _permission = AgentPermissionMode.askEveryWrite;

  @override
  AgentPermissionMode get permission => _permission;

  @override
  set permission(AgentPermissionMode value) {
    if (_permission == value) return;
    _permission = value;
    notifyListeners();
  }

  @override
  Future<void> flush() async {}

  @override
  AgentRunState get state => _state;

  set state(AgentRunState value) {
    _state = value;
    notifyListeners();
  }

  String? _lastError;

  @override
  String? get lastError => _lastError;

  set lastError(String? value) {
    _lastError = value;
    notifyListeners();
  }

  AgentWriteApproval? _pendingApproval;

  @override
  AgentWriteApproval? get pendingApproval => _pendingApproval;

  set pendingApproval(AgentWriteApproval? value) {
    _pendingApproval = value;
    notifyListeners();
  }

  /// 预置消息，用于渲染断言。
  void seed(List<AgentMessageView> messages) {
    _messages
      ..clear()
      ..addAll(messages);
    notifyListeners();
  }

  /// 追加一条消息，模拟真实门面在循环中的行为。
  void append(AgentMessageView message) {
    _messages.add(message);
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
    if (throwLoginRequired) throw const AgentLoginRequired();
    _permission = permission;
    sentTexts.add(text);
    sentAttachments.add(attachedPaths);
    sentPermissions.add(permission);
    sentModels.add(modelId);
    sentEfforts.add(reasoningEffort);
    append(
      AgentMessageView(id: 'm${_messages.length}', role: 'user', text: text),
    );
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    _state = AgentRunState.idle;
    notifyListeners();
  }

  @override
  Future<void> retryLast() async {
    retryCount++;
  }

  @override
  void resolveApproval(bool allow) {
    approvals.add(allow);
    _pendingApproval = null;
    notifyListeners();
  }
}

/// 只读的运行时替身：模型、技能和会话都由测试给定。
class FakeAgentRuntime implements AgentRuntime {
  FakeAgentRuntime({
    required this.sessions,
    this.modelOptions = const [],
    this.skillRefs = const [],
    this.loginRequired = false,
  });

  @override
  final AgentSessionStore sessions;

  final List<AgentModelOption> modelOptions;
  final List<AgentSkillRef> skillRefs;

  /// 未登录时 `models`/`skills`/`open` 都抛 [AgentLoginRequired]。
  final bool loginRequired;

  /// `open` 返回的门面；为 null 时按会话 id 新建。
  FakeAgentFacade? facade;

  final List<String> openedSessions = <String>[];

  /// 测试给定的会话活动状态。改完后调 [notifyLive]。
  final Map<String, AgentLiveStatus> liveStatuses = <String, AgentLiveStatus>{};

  /// 被 `markSeen` 清除过的会话。
  final List<String> seenSessions = <String>[];

  int cancelAllCount = 0;

  final ValueNotifier<int> _liveTick = ValueNotifier<int>(0);

  void notifyLive() => _liveTick.value++;

  @override
  Listenable get liveChanges => _liveTick;

  @override
  AgentLiveStatus statusOf(String sessionId) =>
      liveStatuses[sessionId] ?? AgentLiveStatus.idle;

  @override
  AgentFacade? liveFacade(String sessionId) => null;

  @override
  void markSeen(String sessionId) => seenSessions.add(sessionId);

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  @override
  Future<List<AgentModelOption>> models() async {
    if (loginRequired) throw const AgentLoginRequired();
    return modelOptions;
  }

  @override
  Future<List<AgentSkillRef>> skills(String projectId) async {
    if (loginRequired) throw const AgentLoginRequired();
    return skillRefs;
  }

  @override
  Future<AgentFacade> open(String projectId, String sessionId) async {
    if (loginRequired) throw const AgentLoginRequired();
    openedSessions.add(sessionId);
    return facade ?? FakeAgentFacade(sessionId: sessionId);
  }

  /// 用给定目录建一个真实的文件会话存储。
  static FileAgentSessionStore fileStore(Directory root) =>
      FileAgentSessionStore(root: root);
}

/// 内存会话存储。
///
/// widget 测试跑在 fake async 里，真实文件 I/O 的 Future 永远不会完成，
/// 所以页面测试用这一份；文件持久化由 `agent_session_test.dart` 自己覆盖。
class MemoryAgentSessionStore extends AgentSessionStore {
  final Map<String, AgentSessionMeta> _metas = {};
  final Map<String, AgentTranscript> _transcripts = {};
  int _sequence = 0;

  @override
  Future<void> load() async {
    notifyListeners();
  }

  @override
  List<AgentSessionMeta> sessionsOf(String projectId) {
    final list =
        _metas.values.where((meta) => meta.projectId == projectId).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(list);
  }

  @override
  AgentSessionMeta? metaOf(String sessionId) => _metas[sessionId];

  @override
  Future<AgentSessionMeta> create(String projectId, {String? title}) async {
    final now = DateTime.now();
    final meta = AgentSessionMeta(
      id: 'session-${_sequence++}',
      projectId: projectId,
      title: title ?? AgentSessionStore.defaultTitle,
      createdAt: now,
      updatedAt: now,
    );
    _metas[meta.id] = meta;
    notifyListeners();
    return meta;
  }

  @override
  Future<void> rename(String sessionId, String title) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    _metas[sessionId] = meta.copyWith(title: title, updatedAt: DateTime.now());
    notifyListeners();
  }

  @override
  Future<void> delete(String sessionId) async {
    if (_metas.remove(sessionId) == null) return;
    _transcripts.remove(sessionId);
    notifyListeners();
  }

  @override
  Future<AgentTranscript> read(String sessionId) async =>
      _transcripts[sessionId] ?? AgentTranscript.empty;

  @override
  Future<void> write(String sessionId, AgentTranscript transcript) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    _transcripts[sessionId] = transcript;
    _metas[sessionId] = meta.copyWith(updatedAt: DateTime.now());
    notifyListeners();
  }
}
