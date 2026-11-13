import 'package:flutter/material.dart';

import '../editor/editor_controller.dart';
import '../editor/file_explorer.dart';
import '../models/project.dart';
import '../shell/workbench_state.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';

/// 侧边栏会话列表的一行。
///
/// 这是界面层的视图模型。真实数据来自 harness 的 `AgentSessionStore`，
/// 由上层转换成这个形状，避免侧边栏依赖另一个工作流的文件。
class WorkbenchSessionItem {
  const WorkbenchSessionItem({
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
}

/// 工作台侧边栏：「会话 / 文件」分段。见 design.md §3、§4 第 8 条。
class WorkbenchSidebar extends StatelessWidget {
  const WorkbenchSidebar({
    super.key,
    required this.project,
    required this.state,
    required this.store,
    required this.settings,
    required this.editorController,
    this.sessions = const [],
    this.sessionsLoading = false,
    this.onSelectSession,
    this.onCreateSession,
    this.onFileOpened,
  });

  final Project project;
  final WorkbenchState state;
  final ProjectStore store;
  final SettingsStore settings;
  final EditorController editorController;

  /// 当前项目的会话，已按更新时间倒序。
  final List<WorkbenchSessionItem> sessions;
  final bool sessionsLoading;

  /// 会话来宾。未接入时侧边栏只显示空状态。
  final ValueChanged<WorkbenchSessionItem>? onSelectSession;
  final VoidCallback? onCreateSession;

  /// 文件被点开后的回调。
  ///
  /// [FileExplorer] 只提供无参回调，具体打开了哪个文件由它的内部
  /// [EditorController] 持有。把文件���到中栏编辑器需要共享同一个 controller，
  /// 那属于 `editor/` 的改动，不在本工作流范围。
  final VoidCallback? onFileOpened;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SegmentedButton<SidebarSection>(
              key: const ValueKey('sidebar-section-switch'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: SidebarSection.sessions,
                  label: Text('会话'),
                  icon: Icon(Icons.forum_outlined, size: 18),
                ),
                ButtonSegment(
                  value: SidebarSection.files,
                  label: Text('文件'),
                  icon: Icon(Icons.folder_outlined, size: 18),
                ),
              ],
              selected: {state.sidebarSection},
              onSelectionChanged: (selection) =>
                  state.showSidebarSection(selection.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.sidebarSection == SidebarSection.sessions
                ? _buildSessions(context)
                : _buildFiles(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSessions(BuildContext context) {
    final theme = Theme.of(context);
    if (sessionsLoading) {
      return const Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (sessions.isEmpty) {
      return _SidebarEmpty(
        icon: Icons.forum_outlined,
        text: '还没有会话。新建一个会话开始对话。',
        actionLabel: onCreateSession == null ? null : '新建会话',
        onAction: onCreateSession,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final item = sessions[index];
        final selected = item.id == state.sessionId;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListTile(
            dense: true,
            selected: selected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: const Icon(Icons.chat_bubble_outline, size: 18),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: item.subtitle == null
                ? null
                : Text(
                    item.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
            onTap: onSelectSession == null
                ? null
                : () => onSelectSession!(item),
          ),
        );
      },
    );
  }

  Widget _buildFiles(BuildContext context) => FileExplorer(
    project: project,
    editor: editorController,
    store: store,
    settings: settings,
    outlined: false,
    onFileOpened: onFileOpened,
  );
}

class _SidebarEmpty extends StatelessWidget {
  const _SidebarEmpty({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
