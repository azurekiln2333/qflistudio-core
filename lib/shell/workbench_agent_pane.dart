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

  @override
  State<WorkbenchAgentPane> createState() => _WorkbenchAgentPaneState();
}

class _WorkbenchAgentPaneState extends State<WorkbenchAgentPane> {
  late final ComposerState _composer;
  AgentFacade? _facade;
  List<AgentModelOption> _models = const [];
  List<AgentSkillRef> _skills = const [];
  String? _loadError;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _composer = ComposerState(
      defaults: widget.composerDefaults,
      projectId: widget.project.id,
    );
    widget.auth.addListener(_onAuthChanged);
    _bootstrap();
  }

  @override
  void didUpdateWidget(WorkbenchAgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) _openSession(widget.sessionId);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    _facade?.removeListener(_onFacadeChanged);
    _composer.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (!widget.auth.isLoggedIn) {
      _facade?.removeListener(_onFacadeChanged);
      _facade = null;
    }
    setState(() {});
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _composer.loadDefaults();
    if (!widget.auth.isLoggedIn || !mounted) return;
    try {
      final models = await widget.runtime.models();
      final skills = await widget.runtime.skills(widget.project.id);
      if (!mounted) return;
      setState(() {
        _models = models;
        _skills = skills;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is AgentLoginRequired ? null : '$error';
      });
    }
    await _openSession(widget.sessionId);
  }

  void _onFacadeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openSession(String? sessionId) async {
    if (sessionId == null || !widget.auth.isLoggedIn || _opening) return;
    if (_facade?.sessionId == sessionId) return;
    _opening = true;
    try {
      final facade = await widget.runtime.open(widget.project.id, sessionId);
      if (!mounted) {
        facade.dispose();
        return;
      }
      _facade?.removeListener(_onFacadeChanged);
      _facade?.dispose();
      facade.addListener(_onFacadeChanged);
      setState(() => _facade = facade);
      if (!widget.draft.isEmpty) {
        final draft = widget.draft;
        _composer.attachAll(draft.attachments);
        await _send(draft.text, draft.attachments);
      }
    } on AgentLoginRequired {
      if (mounted) setState(() => _loadError = null);
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error');
    } finally {
      _opening = false;
    }
  }

  Future<bool> _send(String text, List<String> attachments) async {
    if (!await ensureLoggedIn(context)) return false;
    if (!mounted) return false;
    var facade = _facade;
    if (facade == null) {
      try {
        final meta = await widget.runtime.sessions.create(widget.project.id);
        if (!mounted) return false;
        widget.onSessionOpened?.call(meta.id);
        final opened = await widget.runtime.open(widget.project.id, meta.id);
        if (!mounted) {
          opened.dispose();
          return false;
        }
        opened.addListener(_onFacadeChanged);
        setState(() => _facade = opened);
        facade = opened;
      } catch (error) {
        if (mounted) setState(() => _loadError = '$error');
        return false;
      }
    }
    try {
      await facade.send(
        text,
        attachedPaths: attachments,
        permission: _composer.permission,
        modelId: _composer.modelId,
        reasoningEffort: _composer.reasoningEffort,
      );
      _composer.clearInput();
      return true;
    } on AgentLoginRequired {
      return false;
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.isLoggedIn) {
      return const Center(child: LoginGuideCard(compact: true));
    }
    final facade = _facade;
    return Column(
      children: [
        if (_loadError != null)
          MaterialBanner(
            content: Text('agent 暂时不可用：$_loadError'),
            actions: [
              TextButton(onPressed: _bootstrap, child: const Text('重试')),
            ],
          ),
        Expanded(
          child: facade == null
              ? ChatTranscript(
                  messages: const [],
                  state: AgentRunState.idle,
                  emptyTitle: '还没有会话',
                  emptyHint: '在下方输入一句话开始。',
                )
              : ChatTranscript(
                  messages: facade.messages,
                  state: facade.state,
                  lastError: facade.lastError,
                  pendingApproval: facade.pendingApproval,
                  onApproval: facade.resolveApproval,
                  onRetry: facade.retryLast,
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ComposerCard(
              state: _composer,
              onSend: _send,
              onStop: facade?.cancel,
              running: facade?.state == AgentRunState.running,
              models: _models,
              skills: _skills,
              onPickAttachments: (source) => showAttachmentPicker(
                context,
                source: source,
                projectRoot: widget.project.path,
                workspaces: WorkspaceStore.instance,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
