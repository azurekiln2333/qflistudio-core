import 'package:flutter/material.dart';

import '../chat/composer_draft.dart';
import '../chat/composer_state.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_page.dart';
import '../layout/breakpoints.dart';
import '../models/project.dart';
import '../sidebar/workbench_sidebar.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../vibe_coding/vibe_agent_facade.dart';
import 'login_gate.dart';
import 'workbench_agent_pane.dart';
import 'workbench_state.dart';

/// 工作台外壳：侧边栏 + 编辑器 + 对话流。见 design.md §3。
///
/// 三种宽度共用一个 [WorkbenchState]。布局只读状态，不持有状态。
/// 拉伸窗口跨断点时，编辑器与对话流用 [GlobalKey] 保持同一个 Element，
/// 内容不丢失。
class WorkbenchShell extends StatefulWidget {
  const WorkbenchShell({
    super.key,
    required this.project,
    required this.auth,
    required this.store,
    required this.settings,
    this.state,
    this.runtime,
    this.initialSessionId,
    this.draft = ComposerDraft.empty,
    this.composerDefaults,
    this.sessions = const [],
    this.onSelectSession,
    this.onCreateSession,
    this.agentPaneBuilder,
    this.editorPaneBuilder,
    this.onClose,
  });

  final Project project;
  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;

  /// 外部注入状态，用于持久化与测试；为空时自行创建。
  final WorkbenchState? state;

  /// agent 运行时。为空时对话流只显示占位。
  final AgentRuntime? runtime;

  /// 进入时要打开的会话。
  final String? initialSessionId;

  /// 从项目页带过来的第一条消息。
  final ComposerDraft draft;

  /// 每个项目记住的输入卡片选择。
  final ComposerDefaultsStore? composerDefaults;

  final List<WorkbenchSessionItem> sessions;
  final ValueChanged<WorkbenchSessionItem>? onSelectSession;
  final VoidCallback? onCreateSession;

  /// 对话流。阶段 1 为空时显示占位。
  final WidgetBuilder? agentPaneBuilder;

  /// 编辑器。为空时嵌入 [EditorPage]。
  final WidgetBuilder? editorPaneBuilder;

  final VoidCallback? onClose;

  @override
  State<WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  late WorkbenchState _state;
  late bool _ownsState;
  late EditorController _explorerController;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _editorKey = GlobalKey(debugLabel: 'workbench-editor');
  final _agentKey = GlobalKey(debugLabel: 'workbench-agent');
  final _sidebarKey = GlobalKey(debugLabel: 'workbench-sidebar');

  @override
  void initState() {
    super.initState();
    _state = widget.state ?? WorkbenchState(projectId: widget.project.id);
    _ownsState = widget.state == null;
    _explorerController = EditorController(project: widget.project);
  }

  @override
  void didUpdateWidget(WorkbenchShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.project, widget.project) ||
        oldWidget.project.path != widget.project.path) {
      _explorerController.dispose();
      _explorerController = EditorController(project: widget.project);
    }
    if (!identical(oldWidget.state, widget.state) && widget.state != null) {
      if (_ownsState) _state.dispose();
      _state = widget.state!;
      _ownsState = false;
    }
  }

  @override
  void dispose() {
    _explorerController.dispose();
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final layout = layoutOf(MediaQuery.sizeOf(context).width);
        final scaffold = Scaffold(
          key: _scaffoldKey,
          drawer: layout == WorkbenchLayout.narrow
              ? Drawer(child: _sidebar())
              : null,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(context, layout),
                const Divider(height: 1),
                Expanded(child: _body(context, layout)),
              ],
            ),
          ),
        );
        return LoginGateScope(auth: widget.auth, child: scaffold);
      },
    );
  }

  Widget _topBar(BuildContext context, WorkbenchLayout layout) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          if (layout == WorkbenchLayout.narrow)
            IconButton(
              key: const ValueKey('workbench-open-sidebar'),
              icon: const Icon(Icons.menu),
              tooltip: '侧边栏',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (layout != WorkbenchLayout.wide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SegmentedButton<MainPane>(
                key: const ValueKey('workbench-main-pane-switch'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: MainPane.editor,
                    label: Text('编辑器'),
                    icon: Icon(Icons.code, size: 18),
                  ),
                  ButtonSegment(
                    value: MainPane.agent,
                    label: Text('Agent'),
                    icon: Icon(Icons.smart_toy_outlined, size: 18),
                  ),
                ],
                selected: {_state.mainPane},
                onSelectionChanged: (selection) =>
                    _state.showMainPane(selection.first),
              ),
            )
          else
            IconButton(
              key: const ValueKey('workbench-toggle-agent-pane'),
              icon: Icon(
                _state.agentPaneCollapsed
                    ? Icons.chevron_left
                    : Icons.chevron_right,
              ),
              tooltip: _state.agentPaneCollapsed ? '展开对话流' : '收起对话流',
              onPressed: _state.toggleAgentPane,
            ),
          if (widget.onClose != null)
            IconButton(
              key: const ValueKey('workbench-close'),
              icon: const Icon(Icons.close),
              tooltip: '关闭',
              onPressed: widget.onClose,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WorkbenchLayout layout) {
    switch (layout) {
      case WorkbenchLayout.narrow:
      case WorkbenchLayout.medium:
        final panes = Stack(
          fit: StackFit.expand,
          children: [
            _hidden(
              hidden: _state.mainPane != MainPane.editor,
              child: KeyedSubtree(key: _editorKey, child: _editor()),
            ),
            _hidden(
              hidden: _state.mainPane != MainPane.agent,
              child: KeyedSubtree(key: _agentKey, child: _agent()),
            ),
          ],
        );
        if (layout == WorkbenchLayout.narrow) return panes;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(key: _sidebarKey, width: Breakpoints.sidebarWidth, child: _sidebar()),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: panes),
          ],
        );
      case WorkbenchLayout.wide:
        final collapsed = _state.agentPaneCollapsed;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(key: _sidebarKey, width: Breakpoints.sidebarWidth, child: _sidebar()),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: KeyedSubtree(key: _editorKey, child: _editor())),
            if (!collapsed) const VerticalDivider(width: 1, thickness: 1),
            SizedBox(
              width: collapsed ? 0 : Breakpoints.agentPaneWidth,
              child: KeyedSubtree(
                key: _agentKey,
                child: _hidden(hidden: collapsed, child: _agent()),
              ),
            ),
          ],
        );
    }
  }

  /// 隐藏但保持存活。[GlobalKey] 包在 [KeyedSubtree] 里，三种宽度使用同一个
  /// 包装类型，跨断点改变时 Element 原地更新，状态不丢。
  Widget _hidden({required bool hidden, required Widget child}) => Offstage(
    offstage: hidden,
    child: TickerMode(
      enabled: !hidden,
      child: ExcludeFocus(
        excluding: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: IgnorePointer(ignoring: hidden, child: child),
        ),
      ),
    ),
  );

  Widget _sidebar() => WorkbenchSidebar(
    project: widget.project,
    state: _state,
    store: widget.store,
    settings: widget.settings,
    editorController: _explorerController,
    sessions: widget.sessions,
    onSelectSession: widget.onSelectSession,
    onCreateSession: widget.onCreateSession,
    onFileOpened: () {
      if (MediaQuery.sizeOf(context).width < Breakpoints.sidebarPersistent) {
        _scaffoldKey.currentState?.closeDrawer();
      }
    },
  );

  Widget _editor() {
    final injected = widget.editorPaneBuilder;
    if (injected != null) return injected(context);
    return EditorPage(
      project: widget.project,
      auth: widget.auth,
      store: widget.store,
      settings: widget.settings,
      onClose: widget.onClose,
      onOpenAgent: _showAgentPane,
    );
  }

  /// 编辑器里的 AI 入口改为打开这里的对话流，应用内只保留一个 AI 入口。
  void _showAgentPane() {
    if (MediaQuery.sizeOf(context).width >= Breakpoints.threePane) {
      _state.setAgentPaneCollapsed(false);
    } else {
      _state.showMainPane(MainPane.agent);
    }
  }

  Widget _agent() {
    final injected = widget.agentPaneBuilder;
    if (injected != null) return injected(context);
    final runtime = widget.runtime;
    if (runtime == null) {
      return _AgentPanePlaceholder(loggedIn: widget.auth.isLoggedIn);
    }
    return WorkbenchAgentPane(
      key: const ValueKey('workbench-agent-pane'),
      project: widget.project,
      runtime: runtime,
      auth: widget.auth,
      settings: widget.settings,
      sessionId: widget.initialSessionId ?? _state.sessionId,
      draft: widget.draft,
      composerDefaults: widget.composerDefaults,
      onSessionOpened: _state.selectSession,
    );
  }
}

/// 阶段 1 的对话流占位。阶段 2 由 pi-C 的对话流替换。
class _AgentPanePlaceholder extends StatelessWidget {
  const _AgentPanePlaceholder({required this.loggedIn});

  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) return const Center(child: LoginGuideCard(compact: true));
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '对话流尚未接入',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '输入卡片和对话流由另一个工作流提供。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
