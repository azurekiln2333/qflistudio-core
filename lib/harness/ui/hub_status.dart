// Agents 面板里会话状态的统一说法与配色。
//
// 契约的 HarnessSessionStatus 只有一个来源，列表、会话视图和测试都从这里取
// 文案，避免三处各写一套。

import 'package:flutter/material.dart';

import '../harness_host.dart';

/// 状态的中文说法。
String harnessStatusLabel(HarnessSessionStatus status) => switch (status) {
  HarnessSessionStatus.working => '运行中',
  HarnessSessionStatus.idle => '空闲',
  HarnessSessionStatus.done => '已完成',
  HarnessSessionStatus.blocked => '待确认',
  HarnessSessionStatus.exited => '已结束',
  HarnessSessionStatus.unknown => '未知',
};

/// 状态色。与 Studio 会话列表的语义一致：运行中强调色、待确认第三色、
/// 失败/结束用错误色、其余用弱化文字色。
Color harnessStatusColor(ColorScheme scheme, HarnessSessionStatus status) =>
    switch (status) {
      HarnessSessionStatus.working => scheme.primary,
      HarnessSessionStatus.blocked => scheme.tertiary,
      HarnessSessionStatus.exited => scheme.error,
      HarnessSessionStatus.done => scheme.primary,
      HarnessSessionStatus.idle => scheme.onSurfaceVariant,
      HarnessSessionStatus.unknown => scheme.onSurfaceVariant,
    };

/// 状态圆点配色。
///
/// 固定语义色，不取主题色（裁定 R3）：浅色与深色主题下都能区分。返回 null
/// 表示 [HarnessSessionStatus.unknown]，界面改画空心圈。
Color? harnessStatusDotColor(HarnessSessionStatus status) => switch (status) {
  HarnessSessionStatus.blocked => const Color(0xFFF59E0B),
  HarnessSessionStatus.working => const Color(0xFF22C55E),
  HarnessSessionStatus.idle => const Color(0xFF9CA3AF),
  HarnessSessionStatus.done => const Color(0xFF3B82F6),
  HarnessSessionStatus.exited => const Color(0xFFEF4444),
  HarnessSessionStatus.unknown => null,
};

/// 圆点的描边色。未知状态用主题前景色画空心圈。
Color harnessStatusDotBorderColor(
  ColorScheme scheme,
  HarnessSessionStatus status,
) => harnessStatusDotColor(status) ?? scheme.onSurface;

/// 一行状态标签：运行中转圈，其余用文字胶囊。
class HarnessStatusChip extends StatelessWidget {
  const HarnessStatusChip({
    super.key,
    required this.status,
    this.dense = false,
  });

  final HarnessSessionStatus status;

  /// 列表行里的紧凑版本：只占一行高度。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = harnessStatusColor(scheme, status);
    final label = harnessStatusLabel(status);
    final spinner = status == HarnessSessionStatus.working;
    return Container(
      key: ValueKey('harness-status-${status.name}'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner) ...[
            SizedBox.square(
              dimension: dense ? 8 : 10,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            ),
            SizedBox(width: dense ? 4 : 6),
          ],
          Text(
            label,
            style:
                (dense
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// 相对时间：刚打开会话时给「刚刚」，更早给日期。
String harnessRelativeTime(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
  if (delta.inDays < 1) return '${delta.inHours} 小时前';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}
