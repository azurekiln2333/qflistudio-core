// 会话的「对话」标签：结构化对话记录、审批/提问回复和输入卡片。
//
// 消息气泡复用 Studio 的 ChatMessageTile，输入卡片复用 ComposerState 的
// 草稿状态；权限和模型选择器属于内置 Agent 的模型范围，hub 会话没有对应
// 契约字段，所以这里只保留发送与停止。
//
// 停止 = `stop()` = 结束会话，必须由外层确认后再调用：本组件只负责把点击
// 冒泡成 [HubChatView.onStop]，不直接碰 handle。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/chat_transcript.dart';
import '../../chat/composer_state.dart';
import '../../vibe_coding/vibe_agent_facade.dart' show AgentMessageView;
import '../harness_host.dart';

/// 对话记录上限：超过这个条数只保留最近部分，界面不会被长会话拖慢。
const int kHubTranscriptLimit = 400;

/// 契约的会话角色换成 ChatMessageTile 认的角色名。
String hubRoleName(TranscriptRole role) => switch (role) {
  TranscriptRole.user => 'user',
  TranscriptRole.assistant => 'assistant',
  TranscriptRole.tool => 'tool',
  // 系统提示按助手正文渲染：它同样是给用户看的正文，不是工具调用。
  TranscriptRole.system => 'assistant',
};

/// 一个 hub 会话的对话视图。
class HubChatView extends StatefulWidget {
  const HubChatView({
    super.key,
    required this.handle,
    this.onStop,
    this.emptyTitle = '还没有对话记录',
    this.emptyHint = '在下面的输入框里描述要它做什么。',
  });

  final HarnessSessionHandle handle;

  /// 用户点了输入卡片的停止按钮。为空时不显示该按钮。
  ///
  /// 结束会话需要用户确认（AC5），确认对话框与 `stop()` 都由外层完成。
  final VoidCallback? onStop;

  final String emptyTitle;
  final String emptyHint;

  @override
  State<HubChatView> createState() => _HubChatViewState();
}

class _HubChatViewState extends State<HubChatView> {
  final List<TranscriptEvent> _events = <TranscriptEvent>[];
  final Set<String> _answered = <String>{};
  final ScrollController _scroll = ScrollController();
  late final ComposerState _composer = ComposerState();
  StreamSubscription<TranscriptEvent>? _sub;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(HubChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同一个 State 换会话时必须重绑，否则界面留着上一个会话的事件，
    // 而 _send 已经发往新会话。
    if (!identical(oldWidget.handle, widget.handle)) {
      _events.clear();
      _answered.clear();
      _error = null;
      _bind();
    }
  }

  void _bind() {
    unawaited(_sub?.cancel());
    _sub = null;
    _events.clear();
    final stream = widget.handle.transcript;
    if (stream == null) return;
    _sub = stream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _events.add(event);
          if (_events.length > kHubTranscriptLimit) {
            _events.removeRange(0, _events.length - kHubTranscriptLimit);
          }
        });
        _scrollToEnd();
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = '对话记录中断：$error');
      },
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<bool> _send(String text, List<String> attachments) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return false;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.handle.sendPrompt(body);
      _composer.clearInput();
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _error = '这一条没有发出去：$error');
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(TranscriptEvent event, String choice) async {
    final requestId = event.requestId;
    if (requestId == null || _answered.contains(requestId)) return;
    setState(() => _answered.add(requestId));
    try {
      await widget.handle.reply(
        HarnessReply(requestId: requestId, choice: choice),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _answered.remove(requestId);
        _error = '回复没有送出去：$error';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('知道了'),
              ),
            ],
          ),
        Expanded(
          child: _events.isEmpty
              ? _empty(context)
              : ListView.builder(
                  key: const ValueKey('hub-chat-list'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChatMessageTile(
                          message: AgentMessageView(
                            id: event.id,
                            role: hubRoleName(event.role),
                            text: event.text,
                          ),
                        ),
                        if (event.requestId != null &&
                            !_answered.contains(event.requestId))
                          HubRequestCard(
                            event: event,
                            onReply: (choice) => _reply(event, choice),
                          ),
                      ],
                    );
                  },
                ),
        ),
        HubComposer(
          state: _composer,
          onSend: _send,
          sending: _sending,
          // 只是把点击转给外层：结束会话要先弹确认。
          onStop: widget.onStop,
          enabled: true,
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 30, color: scheme.outline),
            const SizedBox(height: 8),
            Text(widget.emptyTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              widget.emptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 审批或提问卡片：每个选项一个按钮，点了就把 requestId 和选择回给主机。
class HubRequestCard extends StatelessWidget {
  const HubRequestCard({super.key, required this.event, required this.onReply});

  final TranscriptEvent event;
  final ValueChanged<String> onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final options = event.options;
    return Container(
      key: ValueKey('hub-request-${event.requestId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: scheme.tertiary),
              const SizedBox(width: 6),
              Text(
                '需要你确认或回答',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(event.text, style: theme.textTheme.bodySmall),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final option in options)
                  FilledButton.tonal(
                    key: ValueKey(
                      'hub-request-option-${event.requestId}-$option',
                    ),
                    onPressed: () => onReply(option),
                    child: Text(option),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// hub 会话的输入卡片。
///
/// 外观与 Studio 的输入卡片一致（同一套圆角、描边和间距），但不含权限与
/// 模型选择器：那两项描述的是内置 Agent 的模型，外部 harness 没有这些字段。
class HubComposer extends StatefulWidget {
  const HubComposer({
    super.key,
    required this.state,
    required this.onSend,
    this.onStop,
    this.sending = false,
    this.enabled = true,
    this.hintText = '给这个会话发一条消息…',
  });

  final ComposerState state;
  final Future<bool> Function(String text, List<String> attachments) onSend;
  final VoidCallback? onStop;
  final bool sending;
  final bool enabled;
  final String hintText;

  @override
  State<HubComposer> createState() => _HubComposerState();
}

class _HubComposerState extends State<HubComposer> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _input.text = widget.state.text;
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(HubComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _input.text = widget.state.text;
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_input.text != widget.state.text) _input.text = widget.state.text;
    setState(() {});
  }

  void _onChanged(String value) {
    widget.state.text = value;
  }

  Future<void> _submit() async {
    if (widget.sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final ok = await widget.onSend(text, const <String>[]);
    if (ok && mounted) _focus.requestFocus();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSend = _input.text.trim().isNotEmpty && widget.enabled;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('hub-composer-input'),
                controller: _input,
                focusNode: _focus,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
                onChanged: _onChanged,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: widget.sending && widget.onStop != null
                        ? IconButton.filled(
                            key: const ValueKey('hub-composer-stop'),
                            tooltip: '结束会话',
                            onPressed: widget.onStop,
                            icon: const Icon(Icons.stop, size: 20),
                          )
                        : IconButton.filled(
                            key: const ValueKey('hub-composer-send'),
                            tooltip: '发送',
                            onPressed: canSend ? _submit : null,
                            icon: const Icon(Icons.arrow_upward, size: 20),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
