import 'package:flutter/material.dart';

import 'trellis_panel.dart';
import 'trellis_project.dart';

/// Trellis 任务面板：当前任务、阶段、产物链接与活跃任务。
///
/// 只渲染 [TrellisTaskPanel]；打开产物交给 [onOpenPath]，面板本身不读文件。
/// 宿主可以把本组件放进 Agents 侧栏或编辑器侧栏。
class TrellisTaskPanelView extends StatelessWidget {
  const TrellisTaskPanelView({
    super.key,
    required this.panel,
    this.onOpenPath,
    this.compact = false,
    this.maxTasks = 12,
  });

  final TrellisTaskPanel panel;

  /// 打开相对项目根的路径，例如 `prd.md` 或 `.trellis/workflow.md`。
  final ValueChanged<String>? onOpenPath;

  /// 紧凑模式只显示当前任务与前三行活跃任务。
  final bool compact;

  /// 活跃任务最多显示多少行。
  final int maxTasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (panel.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '当前项目没有 Trellis 任务',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final current = panel.currentTask;
    final rows = panel.activeTasks.take(compact ? 3 : maxTasks).toList();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text('Trellis', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (panel.developer.isNotEmpty)
              Text(
                panel.developer,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (current != null)
          _CurrentTask(panel: panel, task: current, onOpenPath: onOpenPath),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('活跃任务', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          for (final row in rows)
            _TaskRow(
              row: row,
              selected: current?.dirName == row.task.dirName,
              onOpenPath: onOpenPath,
            ),
        ],
        if (!compact && panel.specIndexes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('规范索引', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          for (final index in panel.specIndexes)
            _PathLink(
              label: index.layer,
              path: index.relativePath,
              onOpenPath: onOpenPath,
            ),
        ],
      ],
    );
  }
}

class _CurrentTask extends StatelessWidget {
  const _CurrentTask({
    required this.panel,
    required this.task,
    this.onOpenPath,
  });

  final TrellisTaskPanel panel;
  final TrellisTask task;
  final ValueChanged<String>? onOpenPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(label: task.phase.label),
              _Chip(label: task.status),
              if (task.phase.step.isNotEmpty)
                _Chip(label: '下一步 ${task.phase.step}'),
            ],
          ),
          const SizedBox(height: 6),
          for (final doc in task.docs)
            _PathLink(
              label: doc.relativePath,
              path: doc.relativePath,
              enabled: doc.exists,
              onOpenPath: onOpenPath,
              trailing: doc.exists ? doc.name : '未写入',
            ),
          const SizedBox(height: 4),
          _PathLink(
            label: panel.workflowPath,
            path: panel.workflowPath,
            onOpenPath: onOpenPath,
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.row, required this.selected, this.onOpenPath});

  final TrellisPanelTask row;
  final bool selected;
  final ValueChanged<String>? onOpenPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = row.task;
    return InkWell(
      onTap: onOpenPath == null ? null : () => onOpenPath!(task.relativePath),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4.0 + row.indent * 12, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.circle_outlined,
              size: 12,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              task.status,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathLink extends StatelessWidget {
  const _PathLink({
    required this.label,
    required this.path,
    this.onOpenPath,
    this.enabled = true,
    this.trailing,
  });

  final String label;
  final String path;
  final ValueChanged<String>? onOpenPath;
  final bool enabled;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = enabled && onOpenPath != null;
    return InkWell(
      onTap: active ? () => onOpenPath!(path) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 13,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
