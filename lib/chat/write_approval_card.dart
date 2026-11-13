import 'package:flutter/material.dart';

import '../vibe_coding/vibe_agent_facade.dart';

/// 写文件的确认卡片。
///
/// 出现在对话流内，显示路径和改动摘要，见 design.md §4 第 6 条。两个按钮
/// 都是主操作，不做默认高亮以外的引导，避免误触。
class WriteApprovalCard extends StatelessWidget {
  const WriteApprovalCard({
    super.key,
    required this.approval,
    required this.onResolve,
  });

  final AgentWriteApproval approval;

  /// true 允许，false 拒绝。
  final ValueChanged<bool> onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 18,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '需要确认写入',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              approval.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onSecondaryContainer,
              ),
            ),
            if (approval.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                approval.summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      key: const ValueKey('approval-deny'),
                      onPressed: () => onResolve(false),
                      child: const Text('拒绝'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      key: const ValueKey('approval-allow'),
                      onPressed: () => onResolve(true),
                      child: const Text('允许'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
