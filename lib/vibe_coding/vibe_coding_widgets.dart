import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vibe_coding_controller.dart';

/// 计划列表：每项一行，状态用图标与文案区分，窄屏自动换行。
class VibePlanList extends StatelessWidget {
  const VibePlanList({super.key, required this.plan, this.dense = false});

  final List<VibePlanItem> plan;

  /// 面板内的紧凑显示；对话里展开显示。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in plan)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 2 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (item.status) {
                    VibePlanStatus.pending => Icons.radio_button_unchecked,
                    VibePlanStatus.doing => Icons.autorenew,
                    VibePlanStatus.done => Icons.check_circle_outline,
                  },
                  size: 14,
                  color: switch (item.status) {
                    VibePlanStatus.pending => scheme.onSurfaceVariant,
                    VibePlanStatus.doing => scheme.primary,
                    VibePlanStatus.done => scheme.outline,
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: dense ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: item.status == VibePlanStatus.done
                          ? scheme.outline
                          : scheme.onSurface,
                      decoration: item.status == VibePlanStatus.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  item.statusLabel,
                  style: textTheme.labelSmall?.copyWith(
                    color: item.status == VibePlanStatus.doing
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 会话顶部的小标签：计划进度与已用技能。
class VibeAgentChips extends StatelessWidget {
  const VibeAgentChips({
    super.key,
    required this.plan,
    required this.usedSkills,
    this.onTogglePlan,
    this.planExpanded = false,
  });

  final List<VibePlanItem> plan;
  final List<String> usedSkills;
  final VoidCallback? onTogglePlan;
  final bool planExpanded;

  @override
  Widget build(BuildContext context) {
    if (plan.isEmpty && usedSkills.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final done = plan
        .where((item) => item.status == VibePlanStatus.done)
        .length;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (plan.isNotEmpty)
          ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              planExpanded ? Icons.expand_less : Icons.checklist,
              size: 14,
              color: scheme.primary,
            ),
            label: Text('计划 $done/${plan.length}'),
            onPressed: onTogglePlan,
          ),
        for (final skill in usedSkills)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
            label: Text(skill),
          ),
      ],
    );
  }
}

/// Status label and icon for one tool call.
({IconData icon, Color color, String label}) vibeToolStatusStyle(
  BuildContext context,
  VibeToolStatus status,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    VibeToolStatus.running => (
      icon: Icons.autorenew,
      color: scheme.primary,
      label: '执行中',
    ),
    VibeToolStatus.ok => (
      icon: Icons.check_circle_outline,
      color: scheme.primary,
      label: '完成',
    ),
    VibeToolStatus.error => (
      icon: Icons.error_outline,
      color: scheme.error,
      label: '失败',
    ),
    VibeToolStatus.conflict => (
      icon: Icons.report_gmailerrorred_outlined,
      color: scheme.error,
      label: '冲突，已拒绝覆盖',
    ),
  };
}

/// Chinese label for a tool name. Unknown names fall back to the raw name so a
/// newer tool stays visible instead of being hidden.
String vibeToolLabel(String toolName) => switch (toolName) {
  'list_files' => '列出文件',
  'read_file' => '读取文件',
  'write_file' => '写入文件',
  'edit_file' => '修改文件',
  'run_command' => '运行命令',
  'todo' => '更新计划',
  'use_skill' => '使用技能',
  'web_fetch' => '抓取网页',
  _ => toolName,
};

/// AI 生成内容的标识文案（整改任务书 §3-W3、§4 第 9 条）。
///
/// 只在模型回复下方显示；用户消息和工具结果不标。
const String kAiGeneratedLabel = '内容由AI生成';

/// 一句话标识：一个图标加文字，窄屏也不会折行到不可读。
class AiGeneratedBadge extends StatelessWidget {
  const AiGeneratedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 12,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            kAiGeneratedLabel,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One conversation entry: a user bubble, assistant prose, or a tool call.
class VibeMessageTile extends StatelessWidget {
  const VibeMessageTile({super.key, required this.message});

  final VibeMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (message.isUser) {
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
    final tool = message.tool;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 20),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tool != null) _VibeToolSection(call: tool),
            if (message.text.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: tool == null ? 0 : 8),
                child: SelectableText(
                  message.text,
                  style: Theme.of(context).textTheme.bodyMedium,
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
}

class _VibeToolSection extends StatelessWidget {
  const _VibeToolSection({required this.call});

  final VibeToolCall call;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = vibeToolStatusStyle(context, call.status);
    final output = call.commandOutput?.trimRight() ?? '';
    final result = call.result?.trimRight() ?? '';
    final hasDetail = output.isNotEmpty || result.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(style.icon, size: 16, color: style.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${vibeToolLabel(call.toolName)}'
                '${call.summary.trim().isEmpty ? '' : ' · ${call.summary}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              style.label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: style.color),
            ),
            if (hasDetail)
              IconButton(
                tooltip: '展开输出',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => _showDetail(context, call),
                icon: const Icon(Icons.open_in_full, size: 15),
              ),
          ],
        ),
        if (hasDetail)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              output.isNotEmpty ? output : result,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (call.plan != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: VibePlanList(plan: call.plan!),
          ),
      ],
    );
  }

  void _showDetail(BuildContext context, VibeToolCall call) {
    final output = call.commandOutput?.trimRight() ?? '';
    final result = call.result?.trimRight() ?? '';
    final body = StringBuffer();
    if (output.isNotEmpty) body.writeln(output);
    if (result.isNotEmpty) {
      if (body.isNotEmpty) body.writeln();
      body.write(result);
    }
    if (call.exitCode != null) {
      if (body.isNotEmpty) body.writeln();
      body.write('退出码 ${call.exitCode}');
    }
    final text = body.toString();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('${vibeToolLabel(call.toolName)} · ${call.summary}'),
        content: SizedBox(
          width: 560,
          child: SelectableText(
            text.isEmpty ? '（无输出）' : text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            icon: const Icon(Icons.content_copy_outlined, size: 16),
            label: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
