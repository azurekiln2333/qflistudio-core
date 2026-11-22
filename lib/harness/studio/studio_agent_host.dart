/// Studio 内置 Agent 的主机实现：把现有 Vibe 会话映射到 Harness Hub 契约。
///
/// 只包装 [AgentRuntime] 与会话存储，不改控制器的行为。会话列表按项目过滤，
/// 标题、状态与更新时间都来自会话元数据与运行时的活动状态。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../session/agent_session.dart';
import '../../vibe_coding/vibe_agent_facade.dart';
import '../harness_host.dart';

/// 主机与 provider 的固定标识。
const String kStudioHostId = 'studio';
const String kStudioProviderId = 'studio';

/// 内置 Agent 出现在 Hub 列表里的名称。
const String kStudioHostLabel = '内置 Agent';

/// 一次视图最多保留多少条转录事件。
const int kStudioTranscriptBacklog = 200;

/// 内置 Agent 主机。
///
/// 只有 [watchSessions]、[open] 与 [launch] 会读会话存储；[dispose] 只释放
/// 本主机的监听与流，不会停止任何会话。一个主机只属于一个项目，一个 Hub
/// 一个实例——[dispose] 之后不可复用。
class StudioAgentHost implements HarnessHost {
  StudioAgentHost({
    required AgentRuntime runtime,
    required this.projectId,
    required this.projectRoot,
    this.label = kStudioHostLabel,
    bool Function()? signedIn,
  }) : _runtime = runtime,
       _signedIn = signedIn ?? _assumeSignedIn {
    _sessions.addListener(_onChanged);
    _runtime.liveChanges.addListener(_onChanged);
  }

  static bool _assumeSignedIn() => true;

  final AgentRuntime _runtime;

  /// 登录态探针；未接线时假定已登录（启动前 hub 不拦用户）。
  final bool Function() _signedIn;

  /// 会话所属项目。
  final String projectId;

  /// 项目根目录，作为会话的工作目录。
  final String projectRoot;

  @override
  final String label;

  final ValueNotifier<HarnessHostState> _state = ValueNotifier(
    HarnessHostState.online,
  );

  /// 已打开的视图，用于随主机一起释放监听。
  final Set<StudioSessionHandle> _handles = {};

  final Set<MultiStreamController<List<HarnessSessionInfo>>> _watchers = {};

  bool _disposed = false;

  AgentSessionStore get _sessions => _runtime.sessions;

  @override
  String get id => kStudioHostId;

  @override
  HarnessHostKind get kind => HarnessHostKind.studio;

  @override
  ValueListenable<HarnessHostState> get state => _state;

  @override
  Stream<List<HarnessSessionInfo>> watchSessions() {
    return Stream<List<HarnessSessionInfo>>.multi((controller) {
      if (_disposed) {
        controller.close();
        return;
      }
      _watchers.add(controller);
      controller.onCancel = () {
        _watchers.remove(controller);
      };
      controller.add(snapshot());
    });
  }

  /// 当前会话列表；界面刷新时也可直接调用。
  List<HarnessSessionInfo> snapshot() {
    if (_disposed) return const [];
    return [
      for (final meta in _sessions.sessionsOf(projectId))
        HarnessSessionInfo(
          id: meta.id,
          hostId: id,
          providerId: kStudioProviderId,
          title: meta.title,
          status: _statusOf(meta.id),
          capabilities: _capabilities,
          cwd: projectRoot,
          updatedAt: meta.updatedAt,
          sourceRef: meta.id,
        ),
    ];
  }

  /// 内置会话没有原始终端，只有对话、输入、确认与停止。
  static const Set<HarnessCapability> _capabilities = {
    HarnessCapability.transcript,
    HarnessCapability.prompt,
    HarnessCapability.approve,
    HarnessCapability.stop,
  };

  @override
  Future<List<HarnessProviderInfo>> providers() async => [
    HarnessProviderInfo(
      id: kStudioProviderId,
      label: kStudioHostLabel,
      // 未登录时启动必然抛 [AgentLoginRequired]，不要报“可用”。
      available: _signedIn(),
    ),
  ];

  @override
  Future<HarnessSessionHandle> open(String sessionId) async {
    if (_disposed) throw StateError('StudioAgentHost has been disposed');
    final meta = _sessions.metaOf(sessionId);
    // 会话必须属于本项目：否则 `AgentRuntime.open` 会拿本项目的根目录去装
    // 别的项目的会话，读写边界跟着错。
    if (meta == null || meta.projectId != projectId) {
      throw ArgumentError.value(sessionId, 'sessionId', '会话不属于本项目');
    }
    final facade = await _runtime.open(projectId, sessionId);
    final handle = StudioSessionHandle(
      host: this,
      runtime: _runtime,
      projectRoot: projectRoot,
      facade: facade,
      info: () => _infoFor(sessionId),
    );
    _handles.add(handle);
    return handle;
  }

  @override
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request) async {
    if (_disposed) throw StateError('StudioAgentHost has been disposed');
    if (request.providerId != kStudioProviderId) {
      throw ArgumentError.value(
        request.providerId,
        'providerId',
        '内置主机只启动内置 Agent',
      );
    }
    if (request.args.isNotEmpty) {
      throw UnsupportedError('内置 Agent 不接受启动参数');
    }
    final cwd = request.cwd.trim();
    if (cwd.isNotEmpty && !_sameDirectory(cwd, projectRoot)) {
      throw UnsupportedError('内置 Agent 只在项目根目录启动：$projectRoot');
    }
    final meta = await _sessions.create(projectId, title: request.title);
    try {
      return await open(meta.id);
    } on Object {
      // 打开失败（例如未登录）时不留空会话记录。
      await _sessions.delete(meta.id);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessions.removeListener(_onChanged);
    _runtime.liveChanges.removeListener(_onChanged);
    for (final handle in _handles.toList()) {
      await handle.detach();
    }
    _handles.clear();
    for (final controller in _watchers.toList()) {
      controller.close();
    }
    _watchers.clear();
    _state.dispose();
  }

  HarnessSessionInfo _infoFor(String sessionId) {
    final meta = _sessions.metaOf(sessionId);
    return HarnessSessionInfo(
      id: sessionId,
      hostId: id,
      providerId: kStudioProviderId,
      title: meta?.title ?? AgentSessionStore.defaultTitle,
      status: _statusOf(sessionId),
      capabilities: _capabilities,
      cwd: projectRoot,
      updatedAt: meta?.updatedAt,
      sourceRef: sessionId,
    );
  }

  /// 运行时活动状态到契约状态。
  HarnessSessionStatus _statusOf(String sessionId) =>
      mapStudioLiveStatus(_runtime.statusOf(sessionId));

  void _onChanged() {
    if (_disposed) return;
    final list = snapshot();
    for (final controller in _watchers.toList()) {
      controller.add(list);
    }
  }

  void _release(StudioSessionHandle handle) => _handles.remove(handle);

  static bool _sameDirectory(String left, String right) {
    String normalize(String value) {
      var path = value.replaceAll('\\', '/');
      while (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      return path.toLowerCase();
    }

    return normalize(left) == normalize(right);
  }
}

/// 运行时活动状态到契约状态。
///
/// 列表与句柄共用这一份：两处各写一遍时，加一个状态很容易只改一处。
/// 失败既不是完成也不是在跑，按未知上报，不粉饰。
HarnessSessionStatus mapStudioLiveStatus(AgentLiveStatus status) =>
    switch (status) {
      AgentLiveStatus.running ||
      AgentLiveStatus.queued => HarnessSessionStatus.working,
      AgentLiveStatus.awaitingApproval => HarnessSessionStatus.blocked,
      AgentLiveStatus.finishedUnread => HarnessSessionStatus.done,
      AgentLiveStatus.failed => HarnessSessionStatus.unknown,
      AgentLiveStatus.idle => HarnessSessionStatus.idle,
    };

/// 一个内置 Agent 会话的视图。
///
/// [detach] 只释放本视图，会话继续运行；[stop] 结束本轮运行。
class StudioSessionHandle implements HarnessSessionHandle {
  StudioSessionHandle({
    required StudioAgentHost host,
    required AgentRuntime runtime,
    required this.projectRoot,
    required AgentFacade facade,
    required HarnessSessionInfo Function() info,
  }) : _host = host,
       _runtime = runtime,
       _facade = facade,
       _infoOf = info,
       _status = ValueNotifier(
         mapStudioLiveStatus(runtime.statusOf(facade.sessionId)),
       ) {
    _facade.addListener(_onFacadeChanged);
    // 排队进出与“完成/失败未读”只在运行时侧变化，门面不会通知。
    _runtime.liveChanges.addListener(_onLiveChanged);
    for (final message in _facade.messages) {
      _remember(_eventOf(message));
    }
    _approvalKey = _pendingApprovalKey();
    // 打开时已经失败的会话也要在转录里留下原因。
    _publishFailure();
  }

  final StudioAgentHost _host;
  final AgentRuntime _runtime;
  final AgentFacade _facade;
  final HarnessSessionInfo Function() _infoOf;
  final String projectRoot;

  final ValueNotifier<HarnessSessionStatus> _status;
  final List<TranscriptEvent> _events = [];

  /// 已发布消息的当前文本，用于在同一条消息被改写时重新发布。
  final Map<String, String> _lastText = {};
  final Set<MultiStreamController<TranscriptEvent>> _listeners = {};

  /// 已经发布过的确认请求键，避免同一次确认重复出现。
  String? _approvalKey;

  /// 已经作为转录事件发布过的错误文本，避免同一错误重复刷屏。
  String? _lastError;

  bool _detached = false;

  /// 当前转录快照；新监听者先收到历史，再收后续消息。
  List<TranscriptEvent> get _backlog => List.unmodifiable(_events);

  @override
  HarnessSessionInfo get info => _infoOf();

  @override
  ValueListenable<HarnessSessionStatus> get status => _status;

  @override
  Stream<TranscriptEvent>? get transcript {
    if (_detached) return null;
    return Stream<TranscriptEvent>.multi((controller) {
      for (final event in _backlog) {
        controller.add(event);
      }
      _listeners.add(controller);
      controller.onCancel = () {
        _listeners.remove(controller);
      };
    });
  }

  @override
  HarnessTerminalChannel? get terminal => null;

  @override
  Future<void> sendPrompt(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty) return;
    // 门面在 running/cancelling/awaitingApproval 时直接 return，不排队也不
    // 报错；这里必须显式失败，否则用户输入被静默丢掉。
    if (_facade.state != AgentRunState.idle &&
        _facade.state != AgentRunState.failed) {
      throw StateError('会话正在运行，请先停止或等待本轮结束');
    }
    await _facade.send(prompt, permission: _facade.permission);
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    final key = _approvalKey;
    // 只处理当前这一次确认；旧卡片重放时 requestId 对不上，直接忽略。
    if (key == null || reply.requestId != key) return;
    if (_facade.pendingApproval == null) return;
    final choice = reply.choice.trim().toLowerCase();
    final bool allow;
    switch (choice) {
      case 'allow' || 'yes' || 'approve' || 'always':
        allow = true;
      case 'deny' || 'no' || 'reject':
        allow = false;
      default:
        // 未知选项不当作拒绝：错写法不应该直接放行或直接拒绝一次写盘。
        throw ArgumentError.value(reply.choice, 'choice', '未知的确认选项');
    }
    _facade.resolveApproval(allow);
    _approvalKey = null;
  }

  @override
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    _facade.removeListener(_onFacadeChanged);
    _runtime.liveChanges.removeListener(_onLiveChanged);
    for (final controller in _listeners.toList()) {
      controller.close();
    }
    _listeners.clear();
    _host._release(this);
  }

  /// 停止本轮运行。
  ///
  /// 契约的措辞是“结束会话”，但内置 Agent 的会话是持久对话：这里只取消
  /// 当前轮次，会话记录与历史保留。界面文案必须写“停止本轮”，不能写
  /// “结束会话”。删除会话是另一件事。
  @override
  Future<void> stop() async {
    await _facade.cancel();
  }

  /// 只有运行时侧状态变化，例如排队进出与完成/失败未读。
  void _onLiveChanged() {
    if (_detached) return;
    _status.value = mapStudioLiveStatus(_runtime.statusOf(_facade.sessionId));
    _publishFailure();
  }

  /// 快照的是当前转录，包括打开前已有的消息；之后的消息实时追加。
  void _onFacadeChanged() {
    if (_detached) return;
    _status.value = mapStudioLiveStatus(_runtime.statusOf(_facade.sessionId));
    // 先比较文本再构事件：流式输出时每条增量都会走到这里，逐条 new 一遍
    // TranscriptEvent 是不必要的分配。消息是追加式的，未变的最多几百个 map
    // 查询，比重构整份转录便宜。
    for (final message in _facade.messages) {
      if (_lastText[message.id] == message.text) continue;
      _publish(_eventOf(message));
    }
    final key = _pendingApprovalKey();
    if (key != null && key != _approvalKey) {
      _approvalKey = key;
      final approval = _facade.pendingApproval!;
      _publish(
        TranscriptEvent(
          id: 'approval:$key',
          role: TranscriptRole.system,
          text: '需要确认写入 ${approval.path}\n${approval.summary}',
          requestId: key,
          options: const ['allow', 'deny'],
        ),
      );
    } else if (key == null) {
      _approvalKey = null;
    }
    _publishFailure();
  }

  /// 失败时补一条系统事件；同一错误只发一次。
  void _publishFailure() {
    if (_runtime.statusOf(_facade.sessionId) != AgentLiveStatus.failed) return;
    final error = _facade.lastError?.trim();
    if (error == null || error.isEmpty || error == _lastError) return;
    _lastError = error;
    _publish(
      TranscriptEvent(
        id: 'error:${_lastError.hashCode}',
        role: TranscriptRole.system,
        text: error,
      ),
    );
  }

  String? _pendingApprovalKey() {
    final approval = _facade.pendingApproval;
    if (approval == null) return null;
    return '${approval.path}|${approval.summary}';
  }

  /// 记下打开前已经存在的消息，供之后接入的监听者补发。
  void _remember(TranscriptEvent event) {
    _lastText[event.id] = event.text;
    _events.add(event);
  }

  void _publish(TranscriptEvent event) {
    _lastText[event.id] = event.text;
    _events.removeWhere((entry) => entry.id == event.id);
    _events.add(event);
    if (_events.length > kStudioTranscriptBacklog) {
      final dropped = _events.take(_events.length - kStudioTranscriptBacklog);
      for (final event in dropped) {
        _lastText.remove(event.id);
      }
      _events.removeRange(0, _events.length - kStudioTranscriptBacklog);
    }
    for (final controller in _listeners.toList()) {
      controller.add(event);
    }
  }

  static TranscriptEvent _eventOf(AgentMessageView message) => TranscriptEvent(
    id: message.id,
    role: switch (message.role) {
      'user' => TranscriptRole.user,
      'tool' => TranscriptRole.tool,
      'reasoning' => TranscriptRole.system,
      _ => TranscriptRole.assistant,
    },
    text: message.text,
  );
}
