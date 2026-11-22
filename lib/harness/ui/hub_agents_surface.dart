// Agents 面板的 hub 部分：顶部主机条 + 会话视图，嵌在编辑器页原有面板里。
//
// 内置 Agent 的原生对话面板作为 [studioPane] 传入：当前主机是内置 Agent 或
// 没有可用主机时原样显示，外部主机的会话则在这里换成 [HubSessionView]。
// 不新开页面，也不另起一套应用外壳。

import 'package:flutter/material.dart';

import '../harness_host.dart';
import '../hub/harness_hub.dart';
import 'hub_host_switcher.dart';
import 'hub_session_list.dart';
import 'hub_session_view.dart';

/// Agents 面板上方的 hub 容器。
class HubAgentsSurface extends StatelessWidget {
  const HubAgentsSurface({
    super.key,
    required this.hub,
    required this.studioPane,
    required this.projectRoot,
    this.onAddComputer,
    this.compact = false,
  });

  final HarnessHub hub;

  /// 内置 Agent 的对话面板，保持原有行为。
  final Widget studioPane;

  /// 新会话的默认工作目录。
  final String projectRoot;

  /// 打开设备与远程（配对）。为空时不显示添加入口。
  final VoidCallback? onAddComputer;

  /// 手机端：会话视图带返回键和终端按键栏。
  final bool compact;

  @override
  Widget build(BuildContext context) {
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
                onAddComputer: onAddComputer,
                compact: compact,
                projectRoot: projectRoot,
              ),
            if (host == null && hub.hostBuildError != null)
              _HostBuildFailure(error: hub.hostBuildError!),
            Expanded(
              child: showsHubSession
                  ? HubSessionView(
                      key: ValueKey('hub-view-${active.hostId}-${active.id}'),
                      hub: hub,
                      session: active,
                      compact: compact,
                    )
                  : host == null || host.kind == HarnessHostKind.studio
                  ? studioPane
                  : _HostEmptyState(
                      hub: hub,
                      host: host,
                      projectRoot: projectRoot,
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

/// 主机条：选择器、连接状态说明、新建会话和刷新。
class _HostHeader extends StatelessWidget {
  const _HostHeader({
    required this.hub,
    required this.host,
    required this.onAddComputer,
    required this.compact,
    required this.projectRoot,
  });

  final HarnessHub hub;
  final HarnessHost host;
  final VoidCallback? onAddComputer;
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
    required this.compact,
    required this.projectRoot,
  });

  final HarnessHub hub;
  final HarnessHost host;
  final VoidCallback? onAddComputer;
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
    required this.compact,
  });

  final HarnessHub hub;
  final VoidCallback? onAddComputer;
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      HubHostSwitcher(hub: hub, onAddComputer: onAddComputer, dense: compact);
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
