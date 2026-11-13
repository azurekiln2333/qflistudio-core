import 'package:flutter/material.dart';

import '../../session/agent_session.dart';
import '../../shell/workbench_state.dart';
import '../../vibe_coding/vibe_agent_facade.dart';

/// 侧边栏「会话」分段：会话列表加状态标记。
///
/// 状态来自运行时的 [AgentRuntime.statusOf]，包括用户没有打开的后台会话。
/// 见 design.md §11.5。
class SessionListView extends StatelessWidget {
  const SessionListView({
    super.key,
    required this.runtime,
    required this.state,
    required this.projectId,
    this.onSelect,
    this.onCreate,
  });

  final AgentRuntime runtime;
  final WorkbenchState state;
  final String projectId;

  /// 点选会话。为空时只显示列表。
  final ValueChanged<String>? onSelect;

  /// 新建会话。
  final Future<void> Function()? onCreate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([runtime.sessions, runtime.liveChanges]),
      builder: (context, _) {
        final sessions = runtime.sessions.sessionsOf(projectId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(
              child: sessions.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) => _SessionRow(
                        meta: sessions[index],
                        status: runtime.statusOf(sessions[index].id),
                        selected: sessions[index].id == state.sessionId,
                        onSelect: onSelect,
                        onRename: (title) =>
                            runtime.sessions.rename(sessions[index].id, title),
                        onDelete: () => _delete(sessions[index]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text('会话', style: theme.textTheme.titleSmall),
          ),
          if (onCreate != null)
            IconButton(
              key: const ValueKey('session-new'),
              tooltip: '新会话',
              onPressed: () => onCreate!(),
              icon: const Icon(Icons.add_comment_outlined, size: 20),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('session-list-menu'),
            tooltip: '会话操作',
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'stop_all',
                height: 44,
                child: Text('全部停止'),
              ),
            ],
            onSelected: (action) {
              if (action == 'stop_all') runtime.cancelAll();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
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
            Text(
              '还没有会话',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '新建一个会话，在 Agent 面板里描述要改什么。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const ValueKey('session-empty-create'),
                onPressed: () => onCreate!(),
                child: const Text('新会话'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 删除会话。运行中的会话先停止，避免删掉正在写的文件。
  Future<void> _delete(AgentSessionMeta meta) async {
    final status = runtime.statusOf(meta.id);
    if (status == AgentLiveStatus.running ||
        status == AgentLiveStatus.queued ||
        status == AgentLiveStatus.awaitingApproval) {
      await runtime.liveFacade(meta.id)?.cancel();
    }
    await runtime.sessions.delete(meta.id);
    if (state.sessionId == meta.id) state.selectSession(null);
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.meta,
    required this.status,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
  });

  final AgentSessionMeta meta;
  final AgentLiveStatus status;
  final bool selected;
  final ValueChanged<String>? onSelect;
  final Future<void> Function(String title) onRename;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = _statusLabel(status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ListTile(
        key: ValueKey('session-${meta.id}'),
        dense: true,
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: SessionStatusMarker(
          key: ValueKey('session-status-${meta.id}'),
          status: status,
        ),
        title: Text(
          meta.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          label == null
              ? _relativeTime(meta.updatedAt)
              : '${_relativeTime(meta.updatedAt)} · $label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        onTap: onSelect == null ? null : () => onSelect!(meta.id),
        trailing: PopupMenuButton<String>(
          key: ValueKey('session-menu-${meta.id}'),
          tooltip: '会话操作',
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', height: 44, child: Text('重命名')),
            PopupMenuItem(value: 'delete', height: 44, child: Text('删除')),
          ],
          onSelected: (action) async {
            if (action == 'rename') {
              final title = await showDialog<String>(
                context: context,
                builder: (_) => _RenameDialog(initialTitle: meta.title),
              );
              if (title == null || title.trim().isEmpty) return;
              await onRename(title);
            }
            if (action == 'delete') {
              if (!context.mounted) return;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('删除会话'),
                  content: Text('「${meta.title}」的消息会一起删除，无法恢复。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      key: const ValueKey('session-delete-confirm'),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await onDelete();
            }
          },
        ),
      ),
    );
  }

  static String? _statusLabel(AgentLiveStatus status) => switch (status) {
    AgentLiveStatus.queued => '排队中',
    AgentLiveStatus.running => '运行中',
    AgentLiveStatus.awaitingApproval => '待确认',
    AgentLiveStatus.failed => '失败',
    AgentLiveStatus.finishedUnread => '已完成',
    AgentLiveStatus.idle => null,
  };

  /// 相对时间，够近的用「刚刚 / N 分钟前」，更早显示日期。
  static String _relativeTime(DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return '刚刚';
    if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
    if (delta.inDays < 1) return '${delta.inHours} 小时前';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }
}

/// 会话状态标记：运行中转圈，排队显示时钟，待确认橙点，失败红点，未读蓝点。
class SessionStatusMarker extends StatelessWidget {
  const SessionStatusMarker({super.key, required this.status});

  final AgentLiveStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 20,
      child: Center(child: _build(scheme)),
    );
  }

  Widget _build(ColorScheme scheme) => switch (status) {
    AgentLiveStatus.running => SizedBox.square(
      dimension: 14,
      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
    ),
    AgentLiveStatus.queued => Icon(
      Icons.schedule,
      size: 16,
      color: scheme.onSurfaceVariant,
    ),
    AgentLiveStatus.awaitingApproval => _dot(scheme.tertiary),
    AgentLiveStatus.failed => _dot(scheme.error),
    AgentLiveStatus.finishedUnread => _dot(scheme.primary),
    AgentLiveStatus.idle => Icon(
      Icons.chat_bubble_outline,
      size: 16,
      color: scheme.onSurfaceVariant,
    ),
  };

  Widget _dot(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 重命名会话。
///
/// 控制器由弹窗自己持有并释放：对话框在退场动画期间还在树上，
/// 在外面 await 完就 dispose 会撞上「已释放的控制器还在使用」。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名会话'),
      content: TextField(
        key: const ValueKey('session-rename-input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '会话名称'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('session-rename-confirm'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
