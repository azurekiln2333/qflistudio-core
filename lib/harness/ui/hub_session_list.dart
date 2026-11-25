// 会话列表：按 harness 分组，显示状态标签和工作目录。
//
// 列表只读 hub，不自己订阅主机；选中一行交给 hub.openSession。

import 'package:flutter/material.dart';

import '../harness_host.dart';
import '../hub/harness_hub.dart';
import 'hub_status.dart';

/// 「新建会话」菜单：列出当前主机检测到的 harness。
///
/// 未安装的 provider 仍然列出但不可点，用户能看到缺什么，而不是菜单里
/// 凭空少一项。
class HubNewSessionButton extends StatefulWidget {
  const HubNewSessionButton({
    super.key,
    required this.hub,
    required this.cwd,
    this.onLaunched,
    this.onError,
    this.dense = false,
    this.buttonSize,
  });

  final HarnessHub hub;

  /// 新会话的工作目录；通常是当前打开的项目根。
  final String cwd;

  final void Function(HarnessSessionHandle handle)? onLaunched;
  final void Function(Object error)? onError;
  final bool dense;

  /// Explicit workbench trigger and menu-row size; null preserves phone sizing.
  final double? buttonSize;

  @override
  State<HubNewSessionButton> createState() => _HubNewSessionButtonState();
}

class _HubNewSessionButtonState extends State<HubNewSessionButton> {
  /// 菜单项的 future 只建一次：每帧新建会让 FutureBuilder 反复完成、反复重建。
  Future<List<HarnessProviderInfo>>? _providers;
  String? _hostId;

  @override
  void initState() {
    super.initState();
    _bind();
    widget.hub.addListener(_onHubChanged);
  }

  @override
  void didUpdateWidget(HubNewSessionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hub, widget.hub)) {
      oldWidget.hub.removeListener(_onHubChanged);
      widget.hub.addListener(_onHubChanged);
      _bind();
    }
  }

  @override
  void dispose() {
    widget.hub.removeListener(_onHubChanged);
    super.dispose();
  }

  void _onHubChanged() {
    if (widget.hub.currentHostId != _hostId) _bind();
  }

  void _bind() {
    _hostId = widget.hub.currentHostId;
    _providers = widget.hub.launchMenu();
  }

  Future<void> _launch(BuildContext context, String providerId) async {
    try {
      final handle = await widget.hub.launch(
        HarnessLaunchRequest(providerId: providerId, cwd: widget.cwd),
      );
      widget.onLaunched?.call(handle);
    } on Object catch (error) {
      widget.onError?.call(error);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('启动失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HarnessProviderInfo>>(
      future: _providers,
      builder: (context, snapshot) {
        final providers = snapshot.data ?? const <HarnessProviderInfo>[];
        final menu = PopupMenuButton<String>(
          key: const ValueKey('hub-new-session'),
          tooltip: '新建会话',
          iconSize: 20,
          padding: EdgeInsets.zero,
          // PopupMenuButton.constraints sizes the menu, not its icon trigger.
          constraints: widget.buttonSize == null
              ? BoxConstraints.tightFor(
                  width: widget.dense ? 32 : 44,
                  height: widget.dense ? 32 : 44,
                )
              : null,
          style: widget.buttonSize == null
              ? null
              : IconButton.styleFrom(
                  fixedSize: Size.square(widget.buttonSize!),
                  minimumSize: Size.square(widget.buttonSize!),
                  maximumSize: Size.square(widget.buttonSize!),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
          icon: const Icon(Icons.add_comment_outlined),
          itemBuilder: (context) => [
            if (providers.isEmpty)
              PopupMenuItem<String>(
                value: '__none__',
                enabled: false,
                height: widget.buttonSize ?? 44,
                child: Text('没有检测到可启动的 harness'),
              ),
            for (final provider in providers)
              PopupMenuItem<String>(
                value: provider.id,
                enabled: provider.available,
                height: widget.buttonSize ?? 44,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!provider.available)
                      Text(
                        '未安装',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          onSelected: (value) {
            if (value == '__none__') return;
            _launch(context, value);
          },
        );
        return menu;
      },
    );
  }
}

/// 一行会话：状态标签、标题、provider、工作目录和更新时间。
class HubSessionRow extends StatelessWidget {
  const HubSessionRow({
    super.key,
    required this.session,
    required this.providerLabel,
    required this.selected,
    this.onTap,
    this.showHostLabel = false,
    this.hostLabel,
  });

  final HarnessSessionInfo session;
  final String providerLabel;
  final bool selected;
  final VoidCallback? onTap;

  /// 合并列表里要标注会话在哪台电脑上。
  final bool showHostLabel;
  final String? hostLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cwd = session.cwd?.trim();
    final updated = session.updatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          key: ValueKey('hub-session-${session.hostId}-${session.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.title.trim().isEmpty
                              ? '(未命名会话)'
                              : session.title,
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
                      HarnessStatusChip(status: session.status, dense: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (showHostLabel &&
                          (hostLabel?.isNotEmpty ?? false)) ...[
                        Icon(
                          Icons.computer_outlined,
                          size: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          hostLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          cwd == null || cwd.isEmpty ? providerLabel : cwd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (updated != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          harnessRelativeTime(updated),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组列表主体，不带滚动：既给侧边栏内嵌，也给独立列表用。
class HubSessionGroups extends StatelessWidget {
  const HubSessionGroups({
    super.key,
    required this.hub,
    this.hostId,
    this.onSelect,
    this.showHostLabel = false,
  });

  final HarnessHub hub;

  /// 为空时用当前主机。
  final String? hostId;

  final void Function(HarnessSessionInfo session)? onSelect;
  final bool showHostLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        final target = hostId ?? hub.currentHostId;
        if (target == null) return const SizedBox.shrink();
        final groups = hub.groupsOf(target);
        if (groups.isEmpty) return const SizedBox.shrink();
        final host = hub.hostById(target);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups) ...[
              Padding(
                key: ValueKey('hub-provider-group-${group.providerId}'),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Text(
                      group.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${group.sessions.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              for (final session in group.sessions)
                HubSessionRow(
                  session: session,
                  providerLabel: group.label,
                  selected:
                      hub.activeSession?.id == session.id &&
                      hub.activeSession?.hostId == session.hostId,
                  showHostLabel: showHostLabel,
                  hostLabel: host?.label,
                  onTap: onSelect == null ? null : () => onSelect!(session),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// 侧边栏里的“外部会话”分段：标题行带新建菜单，正文按 provider 分组。
///
/// 内置 Agent 的会话仍在上面原有的会话列表里，这里只列其它主机，
/// 同一个卡片内两类会话都在，用户看到的就是一份列表。
class HubSessionListSection extends StatelessWidget {
  const HubSessionListSection({
    super.key,
    required this.hub,
    required this.cwd,
    this.onSelect,
    this.onLaunched,
  });

  final HarnessHub hub;

  /// 新建会话的工作目录。
  final String cwd;

  final Future<void> Function(HarnessSessionInfo session)? onSelect;
  final ValueChanged<HarnessSessionHandle>? onLaunched;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        final host = hub.currentHost;
        if (host == null) return const SizedBox.shrink();
        // 内置 Agent 的会话由上面的原生列表画过了，这里只补其它主机。
        if (host.kind == HarnessHostKind.studio) {
          return const SizedBox.shrink();
        }
        final groups = hub.groupsOf(host.id);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final error = hub.sessionErrorOf(host.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '外部会话 · ${host.label}',
                        key: const ValueKey('hub-session-section-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    HubNewSessionButton(
                      hub: hub,
                      cwd: cwd,
                      dense: true,
                      onLaunched: onLaunched,
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '会话列表暂时取不到，稍后刷新。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Text(
                  _emptyHint(hub.stateOf(host.id)),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              HubSessionGroups(
                hub: hub,
                hostId: host.id,
                onSelect: onSelect == null
                    ? null
                    : (session) => onSelect!(session),
              ),
          ],
        );
      },
    );
  }

  static String _emptyHint(HarnessHostState state) => switch (state) {
    HarnessHostState.unsupported => '这台电脑暂不可用，检查是否已安装对应程序。',
    HarnessHostState.connecting => '正在连接…',
    HarnessHostState.offline => '电脑未连接，恢复后会话会重新出现。',
    HarnessHostState.online => '还没有会话，用右上角的新建按钮启动一个 harness。',
  };
}
