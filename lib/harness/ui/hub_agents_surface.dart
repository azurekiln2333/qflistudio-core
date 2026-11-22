// Agents 面板的 hub 部分：顶部主机条 + 会话视图，嵌在编辑器页原有面板里。
//
// 内置 Agent 的原生对话面板作为 [studioPane] 传入：当前主机是内置 Agent 或
// 没有可用主机时原样显示，外部主机的会话则在这里换成 [HubSessionView]。
// 不新开页面，也不另起一套应用外壳。

import 'dart:async';

import 'package:flutter/material.dart';

import '../harness_host.dart';
import '../hub/harness_hub.dart';
import 'hub_host_switcher.dart';
import 'hub_session_list.dart';
import 'hub_session_view.dart';

/// Agents 面板上方的 hub 容器。
class HubAgentsSurface extends StatefulWidget {
  const HubAgentsSurface({
    super.key,
    required this.hub,
    required this.studioPane,
    required this.projectRoot,
    this.onAddComputer,
    this.openRemoteHost,
    this.compact = false,
  });

  final HarnessHub hub;

  /// 内置 Agent 的对话面板，保持原有行为。
  final Widget studioPane;

  /// 新会话的默认工作目录。
  final String projectRoot;

  /// 打开设备与远程（配对）。为空时不显示添加入口。
  final VoidCallback? onAddComputer;

  /// 已绑定电脑的主机要先异步打开存储，所以由调用方注入。
  ///
  /// 只在用户第一次点「已绑定电脑」时调用一次，不在挂载时预连：面板在
  /// 编辑器页里是常挂的（收进 Offstage 也算挂载），挂着就开 WebSocket
  /// 等于每开一个项目就多一条连接。为空时不显示这个入口（测试与预览保持
  /// 纯内存）。装配好的主机交给 hub，随页面销毁一起释放。
  final Future<HarnessHost?> Function()? openRemoteHost;

  /// 手机端：会话视图带返回键和终端按键栏。
  final bool compact;

  @override
  State<HubAgentsSurface> createState() => _HubAgentsSurfaceState();
}

class _HubAgentsSurfaceState extends State<HubAgentsSurface> {
  /// 正在打开已绑定电脑。
  bool _remoteConnecting = false;

  /// 上次打开没成功（没配对、平台不支持、打不开存储）。
  bool _remoteUnavailable = false;

  /// 用户点了「已绑定电脑」才去开远程主机，开好之后选到那台上。
  Future<void> _openRemote() async {
    final opener = widget.openRemoteHost;
    if (opener == null || _remoteConnecting) return;
    setState(() => _remoteConnecting = true);
    HarnessHost? host;
    try {
      host = await opener();
    } on Object {
      // 打不开远程存储只影响已绑定电脑那一栏，不拦内置 Agent 和本机。
      host = null;
    }
    if (!mounted) {
      if (host != null) await host.dispose();
      return;
    }
    setState(() {
      _remoteConnecting = false;
      _remoteUnavailable = host == null;
    });
    if (host == null) return;
    widget.hub.addHost(host);
    // hub 会在平台不可见或 id 重复时直接释放掉，这时不能再切过去。
    if (widget.hub.hostById(host.id) == null) return;
    // 用户点名要这台电脑，就把视图落在那台上，而不是留在内置 Agent。
    widget.hub.selectHost(host.id);
  }

  /// 没配对时点击先带用户去配对，配好了再点一次。
  VoidCallback? get _remoteEntry {
    if (widget.openRemoteHost == null) return null;
    // 已经有已绑定电脑在列表里：占位芯片让位给真正的主机芯片，
    // 否则同一台电脑会出现两个入口。
    if (widget.hub.hosts.any((host) => host.kind == HarnessHostKind.remote)) {
      return null;
    }
    if (_remoteUnavailable && widget.onAddComputer != null) {
      return widget.onAddComputer!;
    }
    return () => unawaited(_openRemote());
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        final host = hub.currentHost;
        final active = hub.activeSession;
        final showsHubSession =
            active != null &&
            host != null &&
            host.kind != HarnessHostKind.studio;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (host != null)
              _HostHeader(
                hub: hub,
                host: host,
                onAddComputer: widget.onAddComputer,
                onOpenRemote: _remoteEntry,
                remoteConnecting: _remoteConnecting,
                remoteUnavailable: _remoteUnavailable,
                compact: widget.compact,
                projectRoot: widget.projectRoot,
              ),
            if (host == null)
              // 一台可见主机都没有（手机端未配对）：主机条无处可挂，
              // 这里自己占一行，不然用户找不到“已绑定电脑”和“添加电脑”。
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: HubHostSwitcher(
                  hub: hub,
                  onAddComputer: widget.onAddComputer,
                  onOpenRemote: _remoteEntry,
                  remoteConnecting: _remoteConnecting,
                  remoteUnavailable: _remoteUnavailable,
                  dense: widget.compact,
                ),
              ),
            if (_remoteConnecting) const _RemoteConnectingBanner(),
            if (host == null && hub.hostBuildError != null)
              _HostBuildFailure(error: hub.hostBuildError!),
            Expanded(
              child: showsHubSession
                  ? HubSessionView(
                      key: ValueKey('hub-view-${active.hostId}-${active.id}'),
                      hub: hub,
                      session: active,
                      compact: widget.compact,
                    )
                  : host == null || host.kind == HarnessHostKind.studio
                  ? widget.studioPane
                  : _HostEmptyState(
                      hub: hub,
                      host: host,
                      projectRoot: widget.projectRoot,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 主机装配失败时的说明条。
///
/// 装配异常不能让面板只剩下内置 Agent 而没有任何线索；这里给出原因，
/// 用户能直接把它转给支持人员。
class _HostBuildFailure extends StatelessWidget {
  const _HostBuildFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('hub-host-build-error'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: scheme.errorContainer,
      child: Text(
        '外部主机没有装配成功：$error',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// 正在打开已绑定电脑时的一行说明。
///
/// 芯片只画得下“连接中…”，这一行说清楚在等什么，连接可能要几秒。
class _RemoteConnectingBanner extends StatelessWidget {
  const _RemoteConnectingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('hub-remote-connecting'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      color: scheme.surfaceContainerHighest,
      child: Text(
        '正在连接已绑定的电脑…',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 主机条：选择器、连接状态说明、新建会话和刷新。
class _HostHeader extends StatelessWidget {
  const _HostHeader({
    required this.hub,
    required this.host,
    required this.onAddComputer,
    required this.onOpenRemote,
    required this.remoteConnecting,
    required this.remoteUnavailable,
    required this.compact,
    required this.projectRoot,
  });

  final HarnessHub hub;
  final HarnessHost host;
  final VoidCallback? onAddComputer;
  final VoidCallback? onOpenRemote;
  final bool remoteConnecting;
  final bool remoteUnavailable;
  final bool compact;
  final String projectRoot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = hub.stateOf(host.id);
    final hint = hub.hintOf(host.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitcherRow(
          hub: hub,
          host: host,
          onAddComputer: onAddComputer,
          onOpenRemote: onOpenRemote,
          remoteConnecting: remoteConnecting,
          remoteUnavailable: remoteUnavailable,
          compact: compact,
          projectRoot: projectRoot,
        ),
        if (hint != null && hint.isNotEmpty)
          Container(
            key: const ValueKey('hub-host-hint'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: scheme.tertiaryContainer.withValues(alpha: 0.35),
            child: Text(
              hint,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          )
        else if (state == HarnessHostState.offline ||
            state == HarnessHostState.connecting)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: scheme.surfaceContainerHighest,
            child: Text(
              state == HarnessHostState.connecting
                  ? '正在连接…'
                  : '电脑未连接，恢复后会话会自动同步。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _SwitcherRow extends StatelessWidget {
  const _SwitcherRow({
    required this.hub,
    required this.host,
    required this.onAddComputer,
    required this.onOpenRemote,
    required this.remoteConnecting,
    required this.remoteUnavailable,
    required this.compact,
    required this.projectRoot,
  });

  final HarnessHub hub;
  final HarnessHost host;
  final VoidCallback? onAddComputer;
  final VoidCallback? onOpenRemote;
  final bool remoteConnecting;
  final bool remoteUnavailable;
  final bool compact;
  final String projectRoot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _HostChips(
            hub: hub,
            onAddComputer: onAddComputer,
            onOpenRemote: onOpenRemote,
            remoteConnecting: remoteConnecting,
            remoteUnavailable: remoteUnavailable,
            compact: compact,
          ),
        ),
        IconButton(
          key: const ValueKey('hub-sessions-refresh'),
          tooltip: '刷新会话',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          onPressed: hub.refresh,
          icon: const Icon(Icons.refresh),
        ),
        SizedBox(width: 2),
        Container(width: 1, height: 20, color: scheme.outlineVariant),
        SizedBox(width: 2),
        HubNewSessionButton(hub: hub, cwd: projectRoot, dense: true),
      ],
    );
  }
}

/// 主机选择条：直接复用 [HubHostSwitcher]，这里只是一个不滚动的窄容器。
class _HostChips extends StatelessWidget {
  const _HostChips({
    required this.hub,
    required this.onAddComputer,
    required this.onOpenRemote,
    required this.remoteConnecting,
    required this.remoteUnavailable,
    required this.compact,
  });

  final HarnessHub hub;
  final VoidCallback? onAddComputer;
  final VoidCallback? onOpenRemote;
  final bool remoteConnecting;
  final bool remoteUnavailable;
  final bool compact;

  @override
  Widget build(BuildContext context) => HubHostSwitcher(
    hub: hub,
    onAddComputer: onAddComputer,
    onOpenRemote: onOpenRemote,
    remoteConnecting: remoteConnecting,
    remoteUnavailable: remoteUnavailable,
    dense: compact,
  );
}

/// 当前主机没有会话时的说明与启动入口。
class _HostEmptyState extends StatelessWidget {
  const _HostEmptyState({
    required this.hub,
    required this.host,
    required this.projectRoot,
  });

  final HarnessHub hub;
  final HarnessHost host;
  final String projectRoot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = hub.stateOf(host.id);
    final unsupported = state == HarnessHostState.unsupported;
    final hasSessions = hub.sessionsOf(host.id).isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unsupported ? Icons.link_off : Icons.dns_outlined,
              size: 32,
              color: unsupported ? scheme.error : scheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              unsupported
                  ? '${host.label} 暂不可用'
                  : hasSessions
                  ? '选择一个会话'
                  : '${host.label} 还没有会话',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              unsupported
                  ? (hub.hintOf(host.id) ?? '检查这台电脑上是否已安装对应程序。')
                  : hasSessions
                  ? '从左侧会话列表选一个，或新建会话。'
                  : '从右上角的新建会话启动一个 harness，或先刷新。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!unsupported) ...[
              const SizedBox(height: 12),
              HubNewSessionButton(hub: hub, cwd: projectRoot),
            ],
          ],
        ),
      ),
    );
  }
}
