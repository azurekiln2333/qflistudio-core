import 'package:flutter/material.dart';

import '../../session/agent_session.dart';
import '../../shell/workbench_state.dart';
import '../../store/project_store.dart';
import '../../sync/placeholder_project.dart';
import '../../vibe_coding/vibe_agent_facade.dart';

/// 会话被删后清掉它的占位项目。
///
/// 会话在配对电脑或内置 Agent 上时，手机上往往只有一个占位项目（需求 12）。
/// 没拉过文件的占位项目随会话一起消失：留着它，项目列表里就是一堆点开
/// 却打不开的条目。拉过文件的项目是用户自己的副本，不在这里处理。
///
/// [store] 为空（例如骨架页）时什么也不做：删目录而留下记录，或者反过来，
/// 都会让项目列表与磁盘对不上。
Future<void> discardSessionPlaceholders(
  ProjectStore? store,
  String sessionId,
) async {
  if (store == null) return;
  final listed = store.projects
      .where(
        (project) =>
            project.deviceSessionId == sessionId &&
            project.placeholder &&
            !project.filesPulled,
      )
      .toList();
  if (listed.isEmpty) return;
  const placeholders = PlaceholderProjects();
  for (final project in listed) {
    await placeholders.discardIfUnused(project);
    await placeholders.removeProject(store, project);
  }
}

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
    this.embedded = false,
    this.extra,
    this.store,
  });

  final AgentRuntime runtime;
  final WorkbenchState state;
  final String projectId;

  /// 项目列表。删会话时用它找到那个会话的占位项目。
  ///
  /// 为空时只删会话本身，不动项目列表。
  final ProjectStore? store;

  /// 点选会话。为空时只显示列表。
  final ValueChanged<String>? onSelect;

  /// 新建会话。
  final Future<void> Function()? onCreate;

  /// 标题栏最左侧的控件，例如「文件 | 会话」分段。
  ///
  /// 会话分段选中时预览仍是同一个标题行，用户能从那里切回文件树。
  /// 为 true 时本视图只给卡片主体，不再带自己的标题行和外框。
  ///
  /// 嵌入 [FileExplorerSections] 时由文件树卡片的共享标题行提供标题、
  /// 新建和「全部停止」，两种主体共用一套外框。
  final bool embedded;

  /// 追加在会话行之后的额外内容（其它主机的会话）。
  ///
  /// 用同一个滚动区，侧边栏里内置会话和外部会话看起来是一份列表。
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([runtime.sessions, runtime.liveChanges]),
      builder: (context, _) {
        final sessions = runtime.sessions.sessionsOf(projectId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!embedded) ...[_buildHeader(context), const Divider(height: 1)],
            Expanded(
              child: sessions.isEmpty && extra == null
                  ? _buildEmpty(context)
                  : ListView.builder(
                      // 与文件树同一套纵向节奏：上下各 8，行间不加分隔。
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      // 内置会话为空时仍要画空态说明：外部会话不能替内置
                      // 列表说话。以前只看 `extra` 是否为空，结果有主机的那一
                      // 栏会得到一张空白卡片，新建入口也跟着消失。
                      itemCount:
                          (sessions.isEmpty ? 1 : 0) +
                          sessions.length +
                          (extra == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        var slot = index;
                        if (sessions.isEmpty) {
                          if (slot == 0) return _buildEmpty(context);
                          slot -= 1;
                        }
                        if (slot >= sessions.length) return extra!;
                        final meta = sessions[slot];
                        return _SessionRow(
                          meta: meta,
                          status: runtime.statusOf(meta.id),
                          selected: meta.id == state.sessionId,
                          onSelect: onSelect,
                          onRename: (title) =>
                              runtime.sessions.rename(meta.id, title),
                          onDelete: () => _delete(meta),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 独立使用（未嵌入文件树卡片）时的标题行。
  ///
  /// 几何与文件树卡片标题行一致：左右各 12 的入场内边距、48 的最小高度、
  /// `labelLarge` 字号。嵌入时标题行由文件树卡片提供，见
  /// [FileExplorerSections]。
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '会话',
                style: theme.textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onCreate != null)
              IconButton(
                key: const ValueKey('session-new'),
                tooltip: '新会话',
                onPressed: () => onCreate!(),
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
              ),
            PopupMenuButton<String>(
              key: const ValueKey('session-list-menu'),
              tooltip: '会话操作',
              padding: EdgeInsets.zero,
              iconSize: 20,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
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
  ///
  /// 会话在配对电脑或内置 Agent 上时，手机上往往只有一个占位项目（需求 12）。
  /// 没拉过文件的占位项目随会话一起消失：留着它，项目列表里就是一堆点开
  /// 却打不开的条目。
  Future<void> _delete(AgentSessionMeta meta) async {
    final status = runtime.statusOf(meta.id);
    if (status == AgentLiveStatus.running ||
        status == AgentLiveStatus.queued ||
        status == AgentLiveStatus.awaitingApproval) {
      await runtime.liveFacade(meta.id)?.cancel();
    }
    await runtime.sessions.delete(meta.id);
    await discardSessionPlaceholders(store, meta.id);
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
    final time = _relativeTime(meta.updatedAt);
    // 右侧次要信息：有状态时显示状态，否则显示相对时间。两种都只占一行。
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      // 与文件树行同一套横向内边距。
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        // 长按和右端菜单同源：两种手势打开同一个菜单。
        onLongPressStart: (details) =>
            _showMenu(context, details.globalPosition),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            key: ValueKey('session-${meta.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: onSelect == null ? null : () => onSelect!(meta.id),
            child: ConstrainedBox(
              // 与文件树行同高：一行标题 34，字缩放时可以再长。
              constraints: const BoxConstraints(minHeight: 34),
              child: Padding(
                // 竖向不留内边距：行高由 34 的下限决定，与文件树行同高。
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Row(
                  children: [
                    SessionStatusMarker(
                      key: ValueKey('session-status-${meta.id}'),
                      status: status,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        meta.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 次要信息可收缩，标题优先。
                    Flexible(
                      child: Text(
                        label ?? time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: label == null
                            ? muted
                            : muted?.copyWith(
                                color: switch (status) {
                                  AgentLiveStatus.awaitingApproval =>
                                    scheme.tertiary,
                                  AgentLiveStatus.failed => scheme.error,
                                  AgentLiveStatus.finishedUnread =>
                                    scheme.primary,
                                  _ => scheme.onSurfaceVariant,
                                },
                              ),
                      ),
                    ),
                    _buildMenu(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 右端菜单：与行同一高度感。
  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey('session-menu-${meta.id}'),
      tooltip: '会话操作',
      iconSize: 16,
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      // M3 的 IconButton 默认把触摸区撑到 48，这里收缩到 32，行高回到 34。
      style: IconButton.styleFrom(
        fixedSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.center,
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'rename', height: 44, child: Text('重命名')),
        PopupMenuItem(value: 'delete', height: 44, child: Text('删除')),
      ],
      onSelected: (action) => _onMenuAction(context, action),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action) async {
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
  }

  /// 长按菜单：同一个菜单在鼠标位置弹出，省一次瞄准。
  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'rename', height: 44, child: Text('重命名')),
        PopupMenuItem(value: 'delete', height: 44, child: Text('删除')),
      ],
    );
    if (action == null || !context.mounted) return;
    await _onMenuAction(context, action);
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
  const SessionStatusMarker({super.key, required this.status, this.size = 20});

  final AgentLiveStatus status;

  /// 占位边长。侧边栏的紧凑行用 16，其余地方保持 20。
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Center(child: _build(scheme)),
    );
  }

  Widget _build(ColorScheme scheme) => switch (status) {
    AgentLiveStatus.running => SizedBox.square(
      dimension: size * 0.7,
      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
    ),
    AgentLiveStatus.queued => Icon(
      Icons.schedule,
      size: size * 0.8,
      color: scheme.onSurfaceVariant,
    ),
    AgentLiveStatus.awaitingApproval => _dot(scheme.tertiary),
    AgentLiveStatus.failed => _dot(scheme.error),
    AgentLiveStatus.finishedUnread => _dot(scheme.primary),
    AgentLiveStatus.idle => Icon(
      Icons.chat_bubble_outline,
      size: size * 0.8,
      color: scheme.onSurfaceVariant,
    ),
  };

  Widget _dot(Color color) => Container(
    width: size * 0.5,
    height: size * 0.5,
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
