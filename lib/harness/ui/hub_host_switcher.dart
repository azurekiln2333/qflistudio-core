// 主机切换器：本机、Herdr、已绑定电脑（带在线点）、添加电脑。
//
// 只画 hub 里已按平台过滤过的主机；手机端因此不会出现本机和 Herdr。

import 'package:flutter/material.dart';

import '../harness_host.dart';
import '../hub/harness_hub.dart';

/// 顶部主机条。选中项高亮，不可用的主机仍可见但带说明。
class HubHostSwitcher extends StatelessWidget {
  const HubHostSwitcher({
    super.key,
    required this.hub,
    this.onAddComputer,
    this.onOpenRemote,
    this.remoteConnecting = false,
    this.remoteUnavailable = false,
    this.dense = false,
  });

  final HarnessHub hub;

  /// 打开设备与远程（配对）。为空时不显示添加入口。
  final VoidCallback? onAddComputer;

  /// 打开已绑定的电脑。
  ///
  /// 已绑定电脑要先异步打开存储才能变成主机，所以它在列表里先是这一枚占位
  /// 芯片，点了才去连；为空表示这个界面不管已绑定电脑。
  final VoidCallback? onOpenRemote;

  /// 正在打开已绑定电脑：占位芯片画成连接中。
  final bool remoteConnecting;

  /// 上次打开没成功（没配对、平台不支持）：占位芯片带说明。
  final bool remoteUnavailable;

  /// 窄屏会话视图里用更紧的高度。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        final hosts = hub.hosts;
        if (hosts.isEmpty && onAddComputer == null && onOpenRemote == null) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Container(
          key: const ValueKey('hub-host-switcher'),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: dense ? 4 : 6,
            ),
            child: Row(
              children: [
                for (final host in hosts) ...[
                  _HostChip(
                    key: ValueKey('hub-host-${host.id}'),
                    label: host.label,
                    icon: _iconFor(host.kind),
                    selected: host.id == hub.currentHostId,
                    state: hub.stateOf(host.id),
                    hint: hub.hintOf(host.id),
                    dense: dense,
                    onTap: () => hub.selectHost(host.id),
                  ),
                  const SizedBox(width: 6),
                ],
                if (onOpenRemote != null) ...[
                  _RemotePendingChip(
                    dense: dense,
                    connecting: remoteConnecting,
                    unavailable: remoteUnavailable,
                    onTap: onOpenRemote!,
                  ),
                  const SizedBox(width: 6),
                ],
                if (onAddComputer != null)
                  _AddComputerChip(dense: dense, onTap: onAddComputer!),
              ],
            ),
          ),
        );
      },
    );
  }

  static IconData _iconFor(HarnessHostKind kind) => switch (kind) {
    HarnessHostKind.local => Icons.computer_outlined,
    HarnessHostKind.remote => Icons.devices_other_outlined,
    HarnessHostKind.studio => Icons.smart_toy_outlined,
  };
}

/// 主机状态的在线点：在线实心，连接中半亮，离线空心，不支持画叉。
class HubHostOnlineDot extends StatelessWidget {
  const HubHostOnlineDot({super.key, required this.state, this.size = 8});

  final HarnessHostState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      HarnessHostState.online => const Color(0xFF2E7D32),
      HarnessHostState.connecting => scheme.tertiary,
      HarnessHostState.offline => scheme.outline,
      HarnessHostState.unsupported => scheme.error,
    };
    return Container(
      key: ValueKey('hub-host-dot-${state.name}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state == HarnessHostState.offline
            ? Colors.transparent
            : color.withValues(alpha: 0.85),
        border: Border.all(color: color, width: 1.2),
      ),
    );
  }
}

class _HostChip extends StatelessWidget {
  const _HostChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.state,
    required this.hint,
    required this.dense,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final HarnessHostState state;
  final String? hint;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: dense ? 14 : 16,
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style:
                  (dense
                          ? theme.textTheme.labelMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
            ),
            const SizedBox(width: 6),
            HubHostOnlineDot(state: state),
          ],
        ),
      ),
    );
    final text = hint?.trim();
    if (text == null || text.isEmpty) return content;
    // 不支持或未安装：把说明挂在悬浮提示上，不额外占一行。
    return Tooltip(message: text, child: content);
  }
}

/// 「已绑定电脑」占位芯片：点它才去打开远程存储并连接。
///
/// 连上之前没有主机可画，所以先用一枚芯片占位，画成连接中或不可用，
/// 而不是让面板里根本没有这个入口。
class _RemotePendingChip extends StatelessWidget {
  const _RemotePendingChip({
    required this.dense,
    required this.connecting,
    required this.unavailable,
    required this.onTap,
  });

  final bool dense;
  final bool connecting;
  final bool unavailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = connecting
        ? HarnessHostState.connecting
        : HarnessHostState.offline;
    final content = InkWell(
      key: const ValueKey('hub-host-pending-remote'),
      onTap: connecting ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: unavailable ? scheme.outline : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: dense ? 14 : 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              connecting ? '连接中…' : '已绑定电脑',
              style:
                  (dense
                          ? theme.textTheme.labelMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            HubHostOnlineDot(state: state),
          ],
        ),
      ),
    );
    if (!unavailable) return content;
    return Tooltip(message: '没有可用的已绑定电脑，先添加一台。', child: content);
  }
}

class _AddComputerChip extends StatelessWidget {
  const _AddComputerChip({required this.dense, required this.onTap});

  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      key: const ValueKey('hub-add-computer'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_link, size: dense ? 14 : 16, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              '添加电脑',
              style:
                  (dense
                          ? theme.textTheme.labelMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
