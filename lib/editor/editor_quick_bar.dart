import 'package:flutter/material.dart';

/// The editor quick function bar.
///
/// It sits directly under the top bar and above the file tab bar. The old app
/// keeps a scrollable strip of fast operations in exactly that slot
/// (`editor_opeartions_bar`): the same actions that are otherwise buried in an
/// overflow menu. This bar is that strip, drawn with icons so it matches the
/// rest of the toolbar.
///
/// The bar is context aware: [agentMode] replaces the whole content, so an
/// editor-only action can never appear while the agent pane is the one the user
/// is working in.
class EditorQuickBar extends StatelessWidget {
  const EditorQuickBar({
    super.key,
    required this.agentMode,
    required this.editorActions,
    required this.agentActions,
  });

  /// Phone and tablet: the `Agent` segment is selected. Wide: the agent pane was
  /// the last pane the user touched.
  final bool agentMode;

  /// Editor actions; ignored while [agentMode] is true.
  final List<EditorQuickBarAction> editorActions;

  /// Agent actions; ignored while [agentMode] is false.
  final List<EditorQuickBarAction> agentActions;

  /// Height of the strip.
  ///
  /// The old app's fast-operation tabs are 25 dp tall
  /// (`qflistudio/src/main/res/layout/editor_activity.xml`,
  /// `android:id="@+id/editor_opeartions_bar"`, `android:layout_height="25dp"`).
  /// A 20 dp glyph inside 25 dp leaves no room for its ripple, so the strip
  /// keeps the same one-line look at 36 dp.
  static const double height = 36;

  /// Width of one slot.
  ///
  /// The old app's toolbar buttons are 55 dp wide, which a phone cannot spend
  /// per icon; the slot follows the 44 dp minimum touch target instead.
  static const double slotWidth = 44;

  /// Glyph size of one slot.
  static const double iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actions = agentMode ? agentActions : editorActions;
    return Material(
      key: const ValueKey('editor-quick-bar'),
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SizedBox(
          height: height,
          child: ScrollConfiguration(
            // A toolbar scrolls sideways without a page-like glow.
            behavior: const _BarScrollBehavior(),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // A drag anywhere on the strip scrolls it, so a phone with more
              // actions than pixels stays usable.
              child: Row(
                key: ValueKey(
                  agentMode
                      ? 'editor-quick-bar-agent'
                      : 'editor-quick-bar-editor',
                ),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions) _QuickBarSlot(action: action),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One slot of the quick bar.
class _QuickBarSlot extends StatelessWidget {
  const _QuickBarSlot({required this.action});

  final EditorQuickBarAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: EditorQuickBar.slotWidth,
      height: EditorQuickBar.height,
      child: IconButton(
        key: ValueKey('quick-${action.id}'),
        tooltip: action.tooltip,
        onPressed: action.onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: EditorQuickBar.iconSize,
        style: action.active
            ? IconButton.styleFrom(
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
              )
            : null,
        icon: action.badge > 0
            ? EditorQuickBadge(
                badgeCount: action.badge,
                icon: action.icon,
                iconSize: EditorQuickBar.iconSize,
              )
            : Icon(action.icon),
      ),
    );
  }
}

/// One slot of the quick bar.
class EditorQuickBarAction {
  const EditorQuickBarAction({
    required this.id,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.badge = 0,
  });

  /// Stable id. The widget key is `quick-<id>`.
  final String id;

  final IconData icon;

  /// Shown on hover, on long press and to screen readers.
  final String tooltip;

  /// Null renders the slot disabled.
  final VoidCallback? onPressed;

  /// The action's toggle is on (the minimap is visible, the panel is open).
  final bool active;

  /// Small count over the icon, e.g. background agent sessions.
  final int badge;
}

/// A badge over an icon, sized for the bar glyph.
class EditorQuickBadge extends StatelessWidget {
  const EditorQuickBadge({
    super.key,
    required this.badgeCount,
    required this.icon,
    this.iconSize,
  });

  final int badgeCount;
  final IconData icon;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: iconSize),
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text(
              badgeCount > 9 ? '9+' : '$badgeCount',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onError,
                fontSize: 9,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mutable view of the editor, read once per frame by the strip.
///
/// The page owns the state; this object only carries the flags the catalogue
/// gates on plus the callbacks it runs. Keeping the two apart means the strip
/// never reaches into the page, and the page never spells out the catalogue.
class EditorQuickBarSource {
  const EditorQuickBarSource({
    required this.offlineOnly,
    required this.hasDocument,
    required this.readOnly,
    required this.brokenProject,
    required this.undoInMenu,
    required this.minimapVisible,
    required this.terminalVisible,
    required this.contentPanelOpen,
    required this.aiPanelOpen,
    required this.isCloudProject,
    required this.contentToolAvailable,
    required this.canCloseEditor,
    this.onUndo,
    this.onSave,
    this.onFind,
    this.onGoto,
    this.onFormat,
    this.onContentTool,
    this.onToggleMinimap,
    this.onTerminal,
    this.onOutput,
    this.onDebug,
    this.onDebugConsole,
    this.onPorts,
    this.onGit,
    this.onCloudPull,
    this.onOnlineTerminal,
    this.onSettings,
    this.onAi,
    this.onCloseEditor,
  });

  /// The product has no network features at all.
  final bool offlineOnly;

  /// A file is open in the editor.
  final bool hasDocument;

  /// The open file is a read-only history snapshot.
  final bool readOnly;

  /// The open file's project folder is gone; saving needs «save as».
  final bool brokenProject;

  /// The top bar has no undo button, so the strip keeps one.
  final bool undoInMenu;

  final bool minimapVisible;
  final bool terminalVisible;

  /// One of the bottom activity panels (output / debug / console / ports).
  final bool contentPanelOpen;

  /// The AI panel or the agent pane is the visible one.
  final bool aiPanelOpen;

  final bool isCloudProject;

  /// The open file is JSON or Markdown, so the content tool applies.
  final bool contentToolAvailable;

  /// The page was opened from a host that can close it.
  final bool canCloseEditor;

  final VoidCallback? onUndo;
  final VoidCallback? onSave;
  final VoidCallback? onFind;
  final VoidCallback? onGoto;
  final VoidCallback? onFormat;
  final VoidCallback? onContentTool;
  final VoidCallback? onToggleMinimap;
  final VoidCallback? onTerminal;
  final VoidCallback? onOutput;
  final VoidCallback? onDebug;
  final VoidCallback? onDebugConsole;
  final VoidCallback? onPorts;
  final VoidCallback? onGit;
  final VoidCallback? onCloudPull;
  final VoidCallback? onOnlineTerminal;
  final VoidCallback? onSettings;
  final VoidCallback? onAi;
  final VoidCallback? onCloseEditor;

  /// The editor strip, in the order a phone scrolls through it.
  List<EditorQuickBarAction> build() {
    final editing = hasDocument && !brokenProject;
    return [
      EditorQuickBarAction(
        id: 'save',
        icon: Icons.save_outlined,
        tooltip: '保存 (Ctrl+S)',
        onPressed: editing && !readOnly ? onSave : null,
      ),
      if (undoInMenu)
        EditorQuickBarAction(
          id: 'undo',
          icon: Icons.undo,
          tooltip: '撤销 (Ctrl+Z)',
          onPressed: editing ? onUndo : null,
        ),
      EditorQuickBarAction(
        id: 'find',
        icon: Icons.search,
        tooltip: '查找替换 (Ctrl+F)',
        onPressed: hasDocument ? onFind : null,
      ),
      EditorQuickBarAction(
        id: 'goto',
        icon: Icons.pin,
        tooltip: '跳转到行 (Ctrl+G)',
        onPressed: hasDocument ? onGoto : null,
      ),
      EditorQuickBarAction(
        id: 'format',
        icon: Icons.format_align_left,
        tooltip: '格式化 (Ctrl+I)',
        onPressed: editing && !readOnly ? onFormat : null,
      ),
      if (contentToolAvailable)
        EditorQuickBarAction(
          id: 'content_tool',
          icon: Icons.preview_outlined,
          tooltip: '内容工具',
          onPressed: onContentTool,
        ),
      EditorQuickBarAction(
        id: 'minimap',
        icon: minimapVisible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        tooltip: minimapVisible ? '隐藏代码鸟瞰' : '显示代码鸟瞰',
        active: minimapVisible,
        onPressed: onToggleMinimap,
      ),
      EditorQuickBarAction(
        id: 'terminal',
        icon: terminalVisible ? Icons.terminal : Icons.terminal_outlined,
        tooltip: terminalVisible ? '关闭终端' : '打开终端',
        active: terminalVisible,
        onPressed: onTerminal,
      ),
      EditorQuickBarAction(
        id: 'output',
        icon: Icons.output,
        tooltip: 'Output · 输出',
        active: contentPanelOpen,
        onPressed: onOutput,
      ),
      EditorQuickBarAction(
        id: 'debug',
        icon: Icons.bug_report_outlined,
        tooltip: '调试',
        onPressed: onDebug,
      ),
      EditorQuickBarAction(
        id: 'debug_console',
        icon: Icons.data_object,
        tooltip: 'Debug Console',
        onPressed: onDebugConsole,
      ),
      EditorQuickBarAction(
        id: 'ports',
        icon: Icons.router_outlined,
        tooltip: 'Ports · 本地端口',
        onPressed: onPorts,
      ),
      if (!offlineOnly)
        EditorQuickBarAction(
          id: 'git',
          icon: Icons.account_tree_outlined,
          tooltip: 'Git',
          onPressed: onGit,
        ),
      if (!offlineOnly && isCloudProject)
        EditorQuickBarAction(
          id: 'cloud_pull',
          icon: Icons.cloud_download_outlined,
          tooltip: '从云端拉取',
          onPressed: onCloudPull,
        ),
      if (!offlineOnly)
        EditorQuickBarAction(
          id: 'online_terminal',
          icon: Icons.cloud_outlined,
          tooltip: '在线终端（服务器执行）',
          onPressed: onOnlineTerminal,
        ),
      if (!offlineOnly)
        EditorQuickBarAction(
          id: 'ai',
          icon: aiPanelOpen ? Icons.auto_awesome : Icons.auto_awesome_outlined,
          tooltip: aiPanelOpen ? '关闭 AI 助手' : 'AI 助手',
          active: aiPanelOpen,
          onPressed: onAi,
        ),
      EditorQuickBarAction(
        id: 'settings',
        icon: Icons.settings_outlined,
        tooltip: '设置',
        onPressed: onSettings,
      ),
      if (canCloseEditor)
        EditorQuickBarAction(
          id: 'close_editor',
          icon: Icons.close,
          tooltip: '关闭编辑器',
          onPressed: onCloseEditor,
        ),
    ];
  }
}

/// The agent strip: session work only, never an editor-only action.
class EditorQuickBarAgentSource {
  const EditorQuickBarAgentSource({
    required this.hasRuntime,
    required this.running,
    required this.failedToLoad,
    this.badgeCount = 0,
    this.onNewSession,
    this.onSessions,
    this.onStopAll,
    this.onRetry,
  });

  /// The runtime resolved, so session work is possible.
  final bool hasRuntime;

  /// At least one session of this project is queued or running.
  final bool running;

  /// The runtime failed to resolve; [onRetry] tries again.
  final bool failedToLoad;

  /// Background sessions waiting for the user.
  final int badgeCount;

  final VoidCallback? onNewSession;
  final VoidCallback? onSessions;
  final VoidCallback? onStopAll;
  final VoidCallback? onRetry;

  List<EditorQuickBarAction> build() {
    return [
      EditorQuickBarAction(
        id: 'agent-new-session',
        icon: Icons.add_comment_outlined,
        tooltip: '新会话',
        onPressed: hasRuntime ? onNewSession : null,
      ),
      EditorQuickBarAction(
        id: 'agent-sessions',
        icon: Icons.forum_outlined,
        tooltip: '会话列表',
        badge: badgeCount,
        onPressed: onSessions,
      ),
      EditorQuickBarAction(
        id: 'agent-stop',
        icon: Icons.stop_circle_outlined,
        tooltip: '停止全部会话',
        onPressed: running ? onStopAll : null,
      ),
      if (failedToLoad)
        EditorQuickBarAction(
          id: 'agent-retry',
          icon: Icons.refresh,
          tooltip: '重新连接 Agent',
          onPressed: onRetry,
        ),
    ];
  }
}

/// Toolbar scroll behaviour: no glow, no page-like bouncing.
class _BarScrollBehavior extends ScrollBehavior {
  const _BarScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
