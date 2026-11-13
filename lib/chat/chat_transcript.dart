import 'package:flutter/material.dart';

import '../vibe_coding/vibe_agent_facade.dart';
import '../vibe_coding/vibe_coding_widgets.dart';
import 'write_approval_card.dart';

/// 对话流：一个会话的消息列表。
///
/// 只渲染 facade 给出的消息，不推断工具结果。见 design.md §4 第 6、7、8 条。
class ChatTranscript extends StatefulWidget {
  const ChatTranscript({
    super.key,
    required this.messages,
    required this.state,
    this.lastError,
    this.pendingApproval,
    this.onApproval,
    this.onRetry,
    this.emptyTitle = '开始一个新的会话',
    this.emptyHint = '描述你想改什么。agent 会读写项目文件，并在在线终端里运行命令。',
    this.emptyAction,
    this.padding = const EdgeInsets.all(12),
  });

  final List<AgentMessageView> messages;
  final AgentRunState state;

  /// 最近一次失败的原因，直接来自 facade。
  final String? lastError;

  /// 等待确认的写入。
  final AgentWriteApproval? pendingApproval;

  final ValueChanged<bool>? onApproval;

  /// 重试上一条用户消息。
  final VoidCallback? onRetry;

  final String emptyTitle;
  final String emptyHint;
  final Widget? emptyAction;
  final EdgeInsets padding;

  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
}

class _ChatTranscriptState extends State<ChatTranscript> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  String _lastTail = '';

  @override
  void initState() {
    super.initState();
    _lastCount = widget.messages.length;
    if (widget.messages.isNotEmpty) {
      _lastTail = _tailOf(widget.messages.last);
    }
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant ChatTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    final messages = widget.messages;
    final tail = messages.isEmpty ? '' : _tailOf(messages.last);
    if (messages.length != _lastCount || tail != _lastTail) {
      _lastCount = messages.length;
      _lastTail = tail;
      _scheduleScrollToBottom();
    }
  }

  static String _tailOf(AgentMessageView message) =>
      '${message.id}|${message.text.length}|${message.pending}';

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _running =>
      widget.state == AgentRunState.running ||
      widget.state == AgentRunState.cancelling ||
      widget.state == AgentRunState.awaitingApproval;

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    if (messages.isEmpty && widget.pendingApproval == null) {
      return _buildEmpty(context);
    }
    final approval = widget.pendingApproval;
    final failed = widget.state == AgentRunState.failed;
    return ListView.builder(
      controller: _scroll,
      padding: widget.padding,
      itemCount:
          messages.length + (approval == null ? 0 : 1) + (failed ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return ChatMessageTile(message: messages[index]);
        }
        if (approval != null && index == messages.length) {
          return WriteApprovalCard(
            approval: approval,
            onResolve: (allow) => widget.onApproval?.call(allow),
          );
        }
        return _buildErrorBar(context);
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 30,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              widget.emptyTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              widget.emptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            if (widget.emptyAction != null) ...[
              const SizedBox(height: 16),
              widget.emptyAction!,
            ],
          ],
        ),
      ),
    );
  }

  /// 失败条：原因来自 facade，下一步由这里补一句可执行的动作。
  Widget _buildErrorBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = widget.lastError?.trim() ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error.isEmpty ? '这一轮没有完成。' : error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                key: const ValueKey('chat-retry'),
                onPressed: _running ? null : widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试上一条消息'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一条消息：用户气泡、助手正文或工具调用条目。
class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({super.key, required this.message});

  final AgentMessageView message;

  @override
  Widget build(BuildContext context) {
    final role = message.role;
    if (role == 'user') return _buildUser(context);
    if (role == 'tool') return _buildTool(context);
    return _buildAssistant(context);
  }

  Widget _buildUser(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          message.text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 20),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: message.isError
              ? Border.all(color: scheme.error, width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.trim().isNotEmpty)
              SelectableText(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: message.isError ? scheme.error : null,
                ),
              ),
            if (message.aiGenerated && message.text.trim().isNotEmpty)
              const AiGeneratedBadge(),
            if (message.pending)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '处理中…',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTool(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = message.toolName ?? '';
    final failed = message.isError;
    final icon = message.pending
        ? Icons.autorenew
        : (failed ? Icons.error_outline : Icons.check_circle_outline);
    final color = message.pending
        ? scheme.primary
        : (failed ? scheme.error : scheme.primary);
    final label = message.pending ? '执行中' : (failed ? '失败' : '完成');
    final detail = message.text.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vibeToolLabel(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
          if (message.changedPaths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                message.changedPaths.join('\n'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                detail,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: failed ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
