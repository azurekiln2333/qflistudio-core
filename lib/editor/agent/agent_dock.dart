import 'package:flutter/material.dart';

import '../../shell/workbench_agent_pane.dart';
import '../../chat/composer_state.dart';
import '../../models/project.dart';
import '../../shell/workbench_state.dart';
import '../../store/auth_store.dart';
import '../../store/settings_store.dart';
import '../../vibe_coding/vibe_agent_facade.dart';

import 'editor_agent_host.dart';

/// 顶栏的 agent 入口：图标加后台会话角标。
///
/// 一个应用只有一个 AI 入口，这里打开的是本页内的 Agent 面板。
class AgentEntryButton extends StatelessWidget {
  const AgentEntryButton({
    super.key,
    required this.host,
    required this.active,
    required this.onPressed,
  });

  final EditorAgentHost host;

  /// 面板是否已经展开（宽屏）或分段是否停在 Agent。
  final bool active;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: host,
      builder: (context, _) {
        final runtime = host.runtime;
        if (runtime == null) return _button(0);
        return AnimatedBuilder(
          animation: Listenable.merge([
            runtime.liveChanges,
            runtime.sessions,
          ]),
          builder: (context, _) => _button(_badgeCount(runtime)),
        );
      },
    );
  }

  Widget _button(int badge) => IconButton(
    key: const ValueKey('editor-agent-toggle'),
    tooltip: active ? '收起 Agent 面板' : '打开 Agent 面板',
    onPressed: onPressed,
    icon: AgentBadgeIcon(
      badgeCount: badge,
      icon: active ? Icons.smart_toy : Icons.smart_toy_outlined,
    ),
  );

  /// 后台待确认或失败的会话数。
  int _badgeCount(AgentRuntime runtime) {
    var count = 0;
    for (final meta in runtime.sessions.sessionsOf(host.project.id)) {
      final status = runtime.statusOf(meta.id);
      if (status == AgentLiveStatus.awaitingApproval ||
          status == AgentLiveStatus.failed) {
        count++;
      }
    }
    return count;
  }
}

/// 宽屏右栏：会话标题、新建、收起，下面是对话流。
///
/// 见 design.md §11.1 的宽屏示意图与 §11.2 第 2 点。对话流本体由外部传入，
/// 这样它在宽屏右栏和中窄屏分段里是同一个 widget 类型，[GlobalKey] 才能
/// 把状态连同草稿一起搬到另一套布局。
class AgentDock extends StatelessWidget {
  const AgentDock({
    super.key,
    required this.runtime,
    required this.state,
    required this.onCollapse,
    required this.onCreateSession,
    required this.child,
  });

  final AgentRuntime runtime;
  final WorkbenchState state;

  final VoidCallback onCollapse;

  /// 新建会话并把 Agent 面板切到它上面。
  final Future<void> Function() onCreateSession;

  /// 对话流本体。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: AnimatedBuilder(
              animation: Listenable.merge([runtime.sessions, runtime.liveChanges]),
              builder: (context, _) {
                final sessionId = state.sessionId;
                final title = sessionId == null
                    ? 'Agent 面板'
                    : (runtime.sessions.metaOf(sessionId)?.title ?? '新会话');
                return Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('editor-agent-new-session'),
                      tooltip: '新会话',
                      onPressed: () => onCreateSession(),
                      icon: const Icon(Icons.add_comment_outlined, size: 20),
                    ),
                    IconButton(
                      key: const ValueKey('editor-agent-collapse'),
                      tooltip: '收起 Agent 面板',
                      onPressed: onCollapse,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const SizedBox(width: 4),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 收起后的竖条：只剩一个展开按钮和角标。
class AgentDockRail extends StatelessWidget {
  const AgentDockRail({
    super.key,
    required this.onExpand,
    this.badgeCount = 0,
  });

  final VoidCallback onExpand;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 矮窗口下只留按钮：竖排文字需要固定的高度，不能把整块撑到溢出。
          final showLabel = constraints.maxHeight >= 200;
          return Column(
            children: [
              const SizedBox(height: 8),
              IconButton(
                key: const ValueKey('editor-agent-expand'),
                tooltip: '展开 Agent 面板',
                onPressed: onExpand,
                icon: AgentBadgeIcon(
                  badgeCount: badgeCount,
                  icon: Icons.smart_toy_outlined,
                ),
              ),
              if (showLabel) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      'Agent 面板',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 对话流本体：运行时还没解析好时给出等待与重试。
class EditorAgentPane extends StatelessWidget {
  const EditorAgentPane({
    super.key,
    required this.project,
    required this.runtime,
    required this.auth,
    required this.settings,
    this.sessionId,
    this.onSessionOpened,
    this.error,
    this.onRetry,
    this.composerDefaults,
  });

  final Project project;
  final AgentRuntime? runtime;
  final AuthStore auth;
  final SettingsStore settings;
  final String? sessionId;
  final ValueChanged<String>? onSessionOpened;

  /// 解析运行时的错误。
  final Object? error;
  final VoidCallback? onRetry;

  /// 按项目记住的模型 / 推理强度 / 权限模式。
  final ComposerDefaultsStore? composerDefaults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final runtime = this.runtime;
    if (runtime == null) {
      if (error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: scheme.error),
                const SizedBox(height: 8),
                Text(
                  'Agent 暂时不可用，请检查网络后重试。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (onRetry != null)
                  FilledButton.tonal(
                    key: const ValueKey('editor-agent-retry'),
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
              ],
            ),
          ),
        );
      }
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return WorkbenchAgentPane(
      key: const ValueKey('editor-agent-pane'),
      project: project,
      runtime: runtime,
      auth: auth,
      settings: settings,
      sessionId: sessionId,
      onSessionOpened: onSessionOpened,
      composerDefaults: composerDefaults,
    );
  }
}

/// 角标：后台会话待确认或失败的数量。
class AgentBadgeIcon extends StatelessWidget {
  const AgentBadgeIcon({
    super.key,
    required this.badgeCount,
    required this.icon,
  });

  final int badgeCount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (badgeCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              key: const ValueKey('editor-agent-badge'),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeCount > 9 ? '9+' : '$badgeCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onError,
                  fontSize: 10,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
