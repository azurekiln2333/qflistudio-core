import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/attachment_picker.dart';
import '../chat/chat_transcript.dart';
import '../chat/composer_card.dart';
import '../chat/composer_draft.dart';
import '../chat/composer_state.dart';
import '../models/project.dart';
import '../store/auth_store.dart';
import '../store/settings_store.dart';
import '../vibe_coding/vibe_agent_facade.dart';
import '../workspace/workspace_store.dart';
import 'login_gate.dart';

/// 工作台的对话流面板：消息列表加输入卡片。
///
/// 一个面板对应一个会话，会话的执行者始终是这里持有的 [AgentFacade]。
/// 项目页只负责建会话，不重复执行。见 design.md §4 第 1、6、7 条。
class WorkbenchAgentPane extends StatefulWidget {
  const WorkbenchAgentPane({
    super.key,
    required this.project,
    required this.runtime,
    required this.auth,
    required this.settings,
    this.sessionId,
    this.draft = ComposerDraft.empty,
    this.composerDefaults,
    this.onSessionOpened,
    this.onOpenFile,
    this.fileExists,
    this.active = true,
  });

  final Project project;
  final AgentRuntime runtime;
  final AuthStore auth;
  final SettingsStore settings;

  /// 进入时要打开的会话；为空表示还没建会话。
  final String? sessionId;

  /// 从项目页带过来的第一条消息。
  final ComposerDraft draft;

  final ComposerDefaultsStore? composerDefaults;

  /// 首次发送时新建了会话，通知外层记住 id。
  final ValueChanged<String>? onSessionOpened;

  /// 点开工具写入的文件；为空时文件卡片不可点。
  final void Function(String path)? onOpenFile;

  /// 文件现在是否还在磁盘上；用于禁用已删除文件的卡片。
  final bool Function(String path)? fileExists;

  /// 面板当前是否在屏幕上可见。
  ///
  /// 中窄屏在「编辑器」分段、宽屏在收起态时为 false；只在可见时把当前
  /// 会话标为已读，避免后台会话的未读标记被保活子树误消，也避免用户正看着
  /// 当前失败或完成的会话时顶栏角标继续亮着。
  final bool active;

  @override
  State<WorkbenchAgentPane> createState() => _WorkbenchAgentPaneState();
}

class _WorkbenchAgentPaneState extends State<WorkbenchAgentPane> {
  /// 每个会话一份草稿：切换会话不丢输入，也不影响别的会话（brief 任务 3）。
  final Map<String, ComposerState> _composers = <String, ComposerState>{};

  /// 还没有会话时用的「新会话」草稿。
  ComposerState? _newComposer;

  String? _sessionId;
  AgentFacade? _facade;
  List<AgentModelOption> _models = const [];
  List<AgentSkillRef> _skills = const [];
  bool _modelsLoading = false;
  String? _modelsError;

  /// 会话打不开或这一条没发出去时的提示。与 facade 的失败原因分开。
  String? _openError;

  /// 切换会话的并发序列号：只有最后一次的结果能落到界面上。
  int _openToken = 0;

  /// 等待秒数计时器。只在有进展时存在。
  Timer? _waitTimer;
  int _waitedSeconds = 0;

  /// 已发出、门面还没收录的那条用户消息，用来在同一帧内给出反馈。
  AgentMessageView? _echo;
  String? _echoSessionId;
  int _echoBaseline = 0;

  bool _sending = false;
  bool _loadingEarlier = false;
  bool _draftSent = false;

  /// 正在重发的那条消息；用来避免连点重复发送。
  String? _resendingId;

  /// 每次发送的序号。换会话或又一次发送后，旧的那次不再动界面。
  int _sendToken = 0;

  bool get _loggedIn => widget.auth.isLoggedIn;

  ComposerState get _composer => _composerFor(_sessionId);

  ComposerState _composerFor(String? sessionId) {
    if (sessionId == null) {
      return _newComposer ??= _createComposer();
    }
    return _composers.putIfAbsent(sessionId, _createComposer);
  }

  /// 新建会话的输入卡片。
  ///
  /// 模型选择按项目记住（design.md §11.6），所以同一项目里的新会话沿用已打开
  /// 会话的选择；一个都没打开时用模型列表的第一项。不这两个来源做种子，新会话
  /// 会回到「默认模型」并丢掉推理强度（D1、D2）。
  ComposerState _createComposer() {
    final sibling = _composers.isEmpty ? _newComposer : _composers.values.last;
    final fallback = _models.isEmpty ? null : _models.first;
    final efforts = fallback?.reasoningEfforts ?? const <String>[];
    return ComposerState(
      permission: sibling?.permission ?? AgentPermissionMode.askEveryWrite,
      defaults: widget.composerDefaults,
      projectId: widget.project.id,
      projectRoot: widget.project.path,
      modelId: sibling?.modelId ?? fallback?.id,
      reasoningEffort:
          sibling?.reasoningEffort ?? (efforts.isEmpty ? null : efforts.first),
      contextWindows: sibling?.contextWindows ?? const {},
    );
  }

  /// 有进展：正在跑、正在收尾，或者这一条刚发出去还没回应。
  bool get _working {
    final state = _facade?.state;
    return _sending ||
        state == AgentRunState.running ||
        state == AgentRunState.cancelling ||
        state == AgentRunState.awaitingApproval;
  }

  /// 会话在排队等并发名额（design.md §11.4）。
  bool get _queued {
    final sessionId = _sessionId;
    if (sessionId == null) return false;
    return widget.runtime.statusOf(sessionId) == AgentLiveStatus.queued;
  }

  bool get _showProgress => _working || _queued;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    widget.auth.addListener(_onAuthChanged);
    widget.runtime.liveChanges.addListener(_onLiveChanged);
    // 首帧之后才开始跑：会话显示和发送都不等任何网络调用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_bootstrap());
    });
  }

  @override
  void didUpdateWidget(WorkbenchAgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      // 同步换草稿和门面引用，随本次重建生效，不必再标脏。
      _adoptSession(widget.sessionId);
      unawaited(_openSession(widget.sessionId));
    } else if (!oldWidget.active && widget.active) {
      _markCurrentSessionSeen();
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    widget.runtime.liveChanges.removeListener(_onLiveChanged);
    // 门面由运行时持有，这里只摘监听，绝不 dispose（design.md §11.4）。
    _facade?.removeListener(_onFacadeChanged);
    _waitTimer?.cancel();
    for (final composer in _composers.values) {
      composer.dispose();
    }
    _newComposer?.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (!_loggedIn) {
      _facade?.removeListener(_onFacadeChanged);
      setState(() {
        _facade = null;
        _models = const [];
        _skills = const [];
        _modelsLoading = false;
        _modelsError = null;
        _openError = null;
        _echo = null;
        _sending = false;
      });
      _syncWaitTimer();
      return;
    }
    setState(() {});
    unawaited(_bootstrap());
  }

  /// 先本地打开会话，模型和技能各走各的，都不阻塞会话显示和发送。
  Future<void> _bootstrap() async {
    unawaited(_composer.loadDefaults());
    unawaited(_loadModels());
    unawaited(_loadSkills());
    await _openSession(_sessionId);
    if (!mounted) return;
    final draft = widget.draft;
    if (!draft.isEmpty && !_draftSent) {
      _draftSent = true;
      _composer.attachAll(draft.attachments);
      await _send(draft.text, draft.attachments);
    }
  }

  Future<void> _loadModels() async {
    if (!_loggedIn) return;
    setState(() {
      _modelsLoading = true;
      _modelsError = null;
    });
    try {
      final models = await widget.runtime.models();
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelsLoading = false;
        _modelsError = models.isEmpty ? '没有取到可选的模型，暂时使用默认模型。' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _modelsLoading = false;
        _modelsError = error is AgentLoginRequired
            ? '登录后才能读取模型列表。'
            : '模型列表暂时取不到，稍后重试。';
      });
    }
  }

  Future<void> _loadSkills() async {
    if (!_loggedIn) return;
    try {
      final skills = await widget.runtime.skills(widget.project.id);
      if (!mounted) return;
      setState(() => _skills = skills);
    } catch (_) {
      // 技能列表取不到不影响发送；输入卡片只是少了 `/` 补全。
    }
  }

  void _onLiveChanged() {
    if (!mounted) return;
    _syncWaitTimer();
    setState(() {});
  }

  void _onFacadeChanged() {
    if (!mounted) return;
    if (_echo != null && _echoSuperseded()) _echo = null;
    _markCurrentSessionSeen();
    _syncWaitTimer();
    setState(() {});
  }

  /// 当前会话正在用户面前且已经停下时，同步标为已读。
  void _markCurrentSessionSeen() {
    if (!widget.active) return;
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final facade = _facade;
    if (facade != null &&
        facade.sessionId == sessionId &&
        (facade.state == AgentRunState.running ||
            facade.state == AgentRunState.cancelling ||
            facade.state == AgentRunState.awaitingApproval)) {
      return;
    }
    widget.runtime.markSeen(sessionId);
  }

  /// 门面已经收录了这条用户消息，就不再显示回声。
  bool _echoSuperseded() {
    final facade = _facade;
    if (facade == null) return false;
    final messages = facade.messages;
    if (messages.length <= _echoBaseline) return false;
    for (var index = _echoBaseline; index < messages.length; index++) {
      if (messages[index].role == 'user') return true;
    }
    return false;
  }

  /// 计时器只在有进展时存在，空闲立刻取消。
  void _syncWaitTimer() {
    if (_showProgress) {
      _waitTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _waitedSeconds++);
      });
      return;
    }
    _waitTimer?.cancel();
    _waitTimer = null;
    _waitedSeconds = 0;
  }

  /// 换到另一个会话。只动本地状态，不改别人的门面，也不停别人的会话。
  void _adoptSession(String? sessionId) {
    // 新会话刚建好时，外层会用 onSessionOpened 把 id 回传，这里必须当成同一个
    // 会话：否则刚发出的那条回声和停止键会被清掉，界面闪一下。
    final sameAsEcho = sessionId != null && sessionId == _echoSessionId;
    _sessionId = sessionId;
    if (!sameAsEcho) {
      _echo = null;
      _echoSessionId = null;
      _sending = false;
      _waitedSeconds = 0;
    }
    _openError = null;
    if (sessionId == null) {
      _facade?.removeListener(_onFacadeChanged);
      _facade = null;
    } else {
      // 只有面板可见时才清角标；面板处于后台保活时不得误消。
      if (widget.active) widget.runtime.markSeen(sessionId);
      final live = widget.runtime.liveFacade(sessionId);
      if (live != null) {
        _attachFacade(live);
      } else if (_facade == null || _facade!.sessionId != sessionId) {
        // 新会话还没有活着的门面：先摘掉旧的那个，否则在 _openSession
        // 完成前会继续把上一个会话的历史显示在新会话下面。
        _facade?.removeListener(_onFacadeChanged);
        _facade = null;
      }
    }
    _syncWaitTimer();
  }

  Future<void> _openSession(String? sessionId) async {
    _adoptSession(sessionId);
    await _openRemote(sessionId);
  }

  Future<void> _openRemote(String? sessionId) async {
    final token = ++_openToken;
    if (sessionId == null || !_loggedIn) return;
    if (_facade?.sessionId == sessionId) return;
    try {
      final facade = await widget.runtime.open(widget.project.id, sessionId);
      // 竞态：快速 A 到 B 时，只显示最后选的那个。
      if (!mounted || token != _openToken) return;
      setState(() {
        _attachFacade(facade);
        _openError = null;
      });
    } on AgentLoginRequired {
      if (!mounted || token != _openToken) return;
      setState(() {
        _facade = null;
        _openError = null;
      });
    } catch (_) {
      if (!mounted || token != _openToken) return;
      setState(() {
        _facade = null;
        _openError = '打不开这个会话，请重试。';
      });
    }
  }

  void _attachFacade(AgentFacade facade) {
    if (!identical(_facade, facade)) {
      _facade?.removeListener(_onFacadeChanged);
      facade.addListener(_onFacadeChanged);
      _facade = facade;
    }
    _echoBaseline = facade.messages.length;
    _markCurrentSessionSeen();
    _syncWaitTimer();
  }

  /// 发送。同一帧内先清空输入、追加用户消息、把发送键换成停止键。
  ///
  /// [preserveDraft] 为真时不碰输入卡片：重发历史消息不能借用、也不能
  /// 清掉用户未发出的草稿。
  Future<bool> _send(
    String text,
    List<String> attachments, {
    bool preserveDraft = false,
  }) async {
    if (_working) return false;
    final composer = _composer;
    final body = text.trim();
    if (body.isEmpty && attachments.isEmpty) return false;
    // 这次发送属于哪个会话。每个 await 之后都要确认还归自己管：
    // 用户中途换会话时，发送继续在原会话后台跑，但绝不动现在的界面和草稿。
    var owner = _sessionId;
    final token = ++_sendToken;
    bool ownsUi() => mounted && token == _sendToken && _sessionId == owner;
    if (!_loggedIn) {
      final ok = await ensureLoggedIn(context);
      if (!ok || !ownsUi() || _working || !identical(composer, _composer)) {
        return false;
      }
    }
    final echoText = body.isEmpty ? '（附带了 ${attachments.length} 个项目文件）' : body;
    if (!preserveDraft) composer.clearInput();
    final baseline = _facade?.messages.length ?? 0;
    setState(() {
      _sending = true;
      _openError = null;
      _echo = AgentMessageView(
        id: 'pending-echo',
        role: 'user',
        text: echoText,
        pending: true,
      );
      _echoSessionId = _sessionId;
      _echoBaseline = baseline;
    });
    _syncWaitTimer();

    AgentFacade? facade = _facade;
    var sessionId = _sessionId;
    try {
      if (sessionId == null) {
        // 空会话：在原处建会话，不跳转（brief 任务 4）。
        final meta = await widget.runtime.sessions.create(widget.project.id);
        if (!mounted) return false;
        sessionId = meta.id;
        _composers[sessionId] = composer;
        if (identical(_newComposer, composer)) _newComposer = null;
        // 建会话期间用户换走了：这条消息在原会话后台发出去，不把界面拉回来。
        if (ownsUi()) {
          owner = sessionId;
          setState(() {
            _sessionId = sessionId;
            _echoSessionId = sessionId;
            _echoBaseline = 0;
          });
          widget.onSessionOpened?.call(sessionId);
        }
      }
      if (facade == null || facade.sessionId != sessionId) {
        final opened = await widget.runtime.open(widget.project.id, sessionId);
        if (!mounted) return false;
        facade = opened;
        // 打开期间换了会话：门面只留给后台发送，不接到现在的界面上。
        if (ownsUi()) {
          _openToken++;
          setState(() {
            _attachFacade(opened);
            _echoSessionId = sessionId;
            _echoBaseline = opened.messages.length;
          });
        }
      }
      await facade.send(
        body,
        attachedPaths: attachments,
        permission: composer.permission,
        modelId: composer.modelId,
        reasoningEffort: composer.reasoningEffort,
      );
      if (!mounted) return true;
      // 只有还归自己管才收掉发送态；否则会清掉新会话的界面状态。
      if (ownsUi()) {
        setState(() => _sending = false);
        _syncWaitTimer();
      }
      return true;
    } on AgentLoginRequired {
      // 草稿按会话保存，还给原会话是对的；界面提示只给还在看它的人。
      _rollback(composer, body, attachments, preserveDraft, ownsUi());
      if (ownsUi()) setState(() {});
      return false;
    } catch (_) {
      _rollback(composer, body, attachments, preserveDraft, ownsUi());
      if (ownsUi()) setState(() => _openError = '这一条没有发出去，请重试。');
      return false;
    }
  }

  /// 把一条历史用户消息放进输入卡片，等用户自己确认发送。
  ///
  /// 原消息留在对话流里，历史不变。卡片里已有内容时不默默覆盖：
  /// 先问一句「替换草稿」，用户同意才写进去。
  Future<void> _editUserMessage(
    AgentUserMessage message, [
    String? menuSession,
  ]) async {
    // 同上：旧会话的菜单不能把内容写进现在的卡片。
    if (menuSession != null && menuSession != _sessionId) return;
    if (_working || _resendingId != null) return;
    final composer = _composer;
    if (composer.canSend) {
      final replace = await _confirmReplaceDraft();
      // 等待确认期间状态可能变了：会话换掉、这一轮开始跑、面板卸载。
      if (!mounted || !replace) return;
      if (!identical(composer, _composer)) return;
      if (_working || _resendingId != null) return;
    }
    // 先清空再写入：否则旧的附件会和这条历史消息的附件叠在一起。
    composer.clearInput();
    composer.text = message.text;
    composer.attachAll(message.attachedPaths);
    if (mounted) setState(() {});
  }

  /// 覆盖非空草稿前问一次。只在这里问，不发消息也不改历史。
  Future<bool> _confirmReplaceDraft() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('composer-replace-draft'),
        title: const Text('替换当前草稿？'),
        content: const Text('输入卡片里已有内容。编辑后重发会覆盖这些内容。'),
        actions: [
          TextButton(
            key: const ValueKey('composer-replace-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留草稿'),
          ),
          TextButton(
            key: const ValueKey('composer-replace-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('替换并编辑'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 把一条历史用户消息原样再发一次。
  ///
  /// 走现有发送管线，不碰输入卡片里未发出的草稿。成功或失败都不动草稿。
  Future<void> _resendUserMessage(
    AgentUserMessage message,
    String id, [
    String? menuSession,
  ]) async {
    // 菜单弹着的时候换了会话：这条历史不属于现在的会话，直接不响应。
    if (menuSession != null && menuSession != _sessionId) return;
    if (_working || _resendingId != null) return;
    final body = message.text.trim();
    if (body.isEmpty && message.attachedPaths.isEmpty) return;
    setState(() => _resendingId = id);
    try {
      // preserveDraft: 直接重发不借用也不清空卡片里未发出的草稿。
      await _send(body, message.attachedPaths, preserveDraft: true);
    } finally {
      if (mounted) setState(() => _resendingId = null);
    }
  }

  /// 发送失败时把草稿还给用户，回声消息撤回。
  ///
  /// 草稿按会话保存，所以总是还给发起这次发送的那个会话；
  /// 界面状态只在这次发送仍然拥有界面时才收，免得清掉别人的发送态。
  void _rollback(
    ComposerState composer,
    String text,
    List<String> attachments, [
    bool preserveDraft = false,
    bool touchUi = true,
  ]) {
    if (!mounted) return;
    // 重发失败时草稿原样留着，不把重发的正文塞回卡片。
    if (!preserveDraft) {
      composer.text = text;
      composer.attachAll(attachments);
    }
    if (!touchUi || !mounted) return;
    setState(() {
      _sending = false;
      _echo = null;
    });
    _syncWaitTimer();
  }

  Future<void> _stop() async {
    if (mounted) setState(() => _sending = false);
    _syncWaitTimer();
    await _facade?.cancel();
  }

  Future<void> _loadEarlier() async {
    final facade = _facade;
    if (facade == null || _loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    try {
      await facade.loadEarlier();
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  /// 门面消息加上尚未被收录的回声消息。
  List<AgentMessageView> _visibleMessages() {
    final base = _facade?.messages ?? const <AgentMessageView>[];
    final echo = _echo;
    if (echo == null || _echoSessionId != _sessionId) return base;
    return [...base, echo];
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) {
      return const Center(child: LoginGuideCard(compact: true));
    }
    final facade = _facade;
    // 这一帧的会话。菜单回调拿着它，换会话后旧菜单就失效。
    final menuSession = _sessionId;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Column(
      children: [
        if (_openError != null)
          MaterialBanner(
            content: Text(_openError!),
            actions: [
              TextButton(
                key: const ValueKey('agent-open-retry'),
                onPressed: () => _openSession(_sessionId),
                child: const Text('重试'),
              ),
            ],
          ),
        Expanded(
          child: ChatTranscript(
            messages: _visibleMessages(),
            state: facade?.state ?? AgentRunState.idle,
            lastError: facade?.lastError,
            errorInfo: facade?.lastErrorInfo,
            activity: facade?.activity,
            queued: _queued,
            waitingSeconds: _waitedSeconds >= 3 ? _waitedSeconds : null,
            hasEarlier: facade?.hasEarlier ?? false,
            loadingEarlier: _loadingEarlier,
            onLoadEarlier: _loadEarlier,
            pendingApproval: facade?.pendingApproval,
            onApproval: facade?.resolveApproval,
            onRetry: facade?.retryLast,
            // 只在用户点「诊断连接」时才发起，不自动跑。
            onDiagnose: widget.runtime.diagnoseConnection,
            onResend: (message, id) =>
                _resendUserMessage(message, id, menuSession),
            onEdit: (message, id) => _editUserMessage(message, menuSession),
            onOpenFile: widget.onOpenFile,
            fileExists: widget.fileExists,
            busy: _working || _resendingId != null,
            sessionKey: _sessionId,
            // 气泡用它只重绘增长的那一条消息（thinking-stream design §6.1）。
            liveTextOf: facade?.liveTextOf,
            emptyTitle: '开始一个新的会话',
            emptyHint: '在下面的输入卡片里说一句要改什么，发送后就在这里跑。',
          ),
        ),
        // 软键盘弹出时输入卡片跟着上移，不被遮挡（design.md §4 第 4 条）。
        Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ComposerCard(
                state: _composer,
                onSend: _send,
                onStop: _stop,
                running: _working,
                models: _models,
                skills: _skills,
                contextUsage:
                    facade?.contextUsage ?? const AgentContextUsage.empty(),
                modelsLoading: _modelsLoading,
                modelsError: _modelsError,
                onRetryModels: _loadModels,
                onPickAttachments: (source) => showAttachmentPicker(
                  context,
                  source: source,
                  projectRoot: widget.project.path,
                  workspaces: WorkspaceStore.instance,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
