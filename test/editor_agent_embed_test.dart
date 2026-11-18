@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/editor/agent/agent_dock.dart';
import 'package:qfli_studio_core/editor/agent/editor_agent_host.dart';
import 'package:qfli_studio_core/editor/agent/editor_sidebar_tabs.dart';
import 'package:qfli_studio_core/editor/agent/session_list_view.dart';
import 'package:qfli_studio_core/editor/ai_panel.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/layout/breakpoints.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/shell/workbench_state.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';
import 'package:re_editor/re_editor.dart';

import 'support/fake_agent.dart';

/// agent 嵌在编辑器页里，应用只有「主页 → 编辑器页」两层路由。
///
/// 覆盖 CHECKLIST 的 A1-A4、B4、B6、E2、E3、F5、G8。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Project project;
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late MemoryAgentSessionStore sessions;
  late FakeAgentRuntime runtime;
  late _MemoryComposerDefaults composerDefaults;
  StudioProfile? previousProfile;

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'editor-agent-embed-test',
      appTitle: 'QFLIStudio+',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_editor_agent_');
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    File(
      p.join(directory.path, 'src', 'main.dart'),
    ).writeAsStringSync('void main() {\n  print(1);\n}\n');
    project = Project.create(name: 'Demo', path: directory.path);
    store = ProjectStore();
    settings = SettingsStore();
    auth = AuthStore();
    await auth.signIn(
      'token',
      const CommunityUser(
        id: 'u1',
        username: 'demo',
        nickname: 'Demo',
        bio: '',
        avatarColor: '#000000',
        points: 0,
        checkinStreak: 0,
        provider: 'local',
      ),
    );
    sessions = MemoryAgentSessionStore();
    composerDefaults = _MemoryComposerDefaults();
    runtime = FakeAgentRuntime(
      sessions: sessions,
      modelOptions: const [AgentModelOption(id: 'model-a', label: 'Model A')],
    );
    EditorAgentHost.resetRuntimeResolutions();
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 排队中的历史写入可能还握着句柄。
    }
  });

  /// 挂载真实的编辑器页。测试统一从这里进入，避免每个用例自己搭一遍宿主。
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    bool injectRuntime = true,
    bool agentEnabled = true,
    ValueNotifier<bool>? retainedVisibility,
    String? initialOpenPath,
    _RouteCounter? observer,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: observer == null
            ? const <NavigatorObserver>[]
            : <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) => MediaQuery(
            // 只叠加字缩放，其余沿用真实媒体查询（尺寸、内边距等）。
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: EditorPage(
              project: project,
              auth: auth,
              store: store,
              settings: settings,
              initialOpenPath: initialOpenPath,
              agentRuntime: injectRuntime ? runtime : null,
              composerDefaults: composerDefaults,
              agentEnabled: agentEnabled,
              retainedVisibility: retainedVisibility,
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('开关', () {
    testWidgets('关闭：无 agent 控件，「AI 助手」仍开旧面板', (tester) async {
      await mount(tester, agentEnabled: false);

      expect(find.byKey(const ValueKey('editor-agent-toggle')), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('editor-main-pane-switch')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-agent-pane')), findsNothing);

      await _openMoreMenu(tester, 'AI 助手');

      expect(find.byType(AiPanel), findsOneWidget);
    });

    testWidgets('开启：切换键在侧边栏卡片标题行内，「AI 助手」开 Agent 面板', (tester) async {
      await mount(tester);
      await _openSidebar(tester);

      final toggle = find.byKey(
        const ValueKey('editor-sidebar-section-switch'),
      );
      expect(toggle, findsOneWidget);
      final toggleRect = tester.getRect(toggle);
      final explorerRect = tester.getRect(find.byType(FileExplorer).first);

      expect(
        toggleRect.top,
        greaterThanOrEqualTo(explorerRect.top),
        reason: '切换键要在文件树卡片内部，不再是卡片之上的独立条',
      );
      expect(
        toggleRect.bottom,
        lessThan(explorerRect.top + 56),
        reason: '切换键要和卡片标题行同一行',
      );
      expect(toggleRect.left, lessThan(300), reason: '切换键在侧边栏，不在顶栏');

      await _openMoreMenu(tester, 'AI 助手');

      expect(find.byKey(const ValueKey('editor-agent-pane')), findsOneWidget);
      expect(find.byType(AiPanel), findsNothing, reason: '只剩一个 AI 入口');
    });
  });

  group('布局', () {
    testWidgets('宽屏有 Agent 入口与右侧切换键', (tester) async {
      await mount(tester);

      expect(find.byKey(const ValueKey('editor-agent-toggle')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
        findsOneWidget,
      );
      // 文件模式下，切换键指向会话。
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsOneWidget,
      );
      expect(find.byType(AgentDock), findsNothing);

      await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
      await pumpFrames(tester);

      expect(find.byType(AgentDock), findsOneWidget);
      expect(find.byType(WorkbenchAgentPane), findsOneWidget);
    });

    testWidgets('窄屏用顶栏切换编辑器与 Agent', (tester) async {
      await mount(tester, size: const Size(500, 900));

      expect(
        find.byKey(const ValueKey('editor-main-pane-switch')),
        findsNothing,
      );
      expect(find.byType(AgentDock), findsNothing);

      await tester.tap(find.byTooltip('打开 Agent 面板'));
      await pumpFrames(tester);

      expect(find.byType(WorkbenchAgentPane), findsOneWidget);

      await tester.tap(find.byTooltip('返回编辑器'));
      await pumpFrames(tester);
      expect(find.byType(WorkbenchAgentPane), findsNothing);
      expect(find.byTooltip('打开 Agent 面板'), findsOneWidget);
    });
  });

  group('导航', () {
    testWidgets('打开项目只推一个路由，返回一次回主页', (tester) async {
      final counter = _RouteCounter();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [counter],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openEditorPage(
                    context,
                    project: project,
                    auth: auth,
                    store: store,
                    settings: settings,
                  ),
                  child: const Text('打开项目'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(counter.pushes, 1, reason: '只有首屏路由');

      await tester.tap(find.text('打开项目'));
      await pumpFrames(tester);

      expect(counter.pushes, 2, reason: '打开项目只能再推一个路由');
      expect(find.byType(EditorPage), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await pumpFrames(tester);

      expect(find.text('打开项目'), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
    });

    testWidgets('工作区入口同样直达编辑器页', (tester) async {
      final counter = _RouteCounter();
      final workspace = SavedWorkspace(
        id: 'w1',
        name: '示例工作区',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        members: [WorkspaceMember.fromProject(project, primary: true)],
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [counter],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openEditorPage(
                    context,
                    project: project,
                    auth: auth,
                    store: store,
                    settings: settings,
                    workspace: workspace,
                    workspaceProjects: [project],
                    // 临时根目录：避开 AppPaths 的目录探测定时器。
                    workspaceStore: WorkspaceStore(
                      root: Directory(p.join(directory.path, 'ws')),
                    ),
                  ),
                  child: const Text('打开工作区'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开工作区'));
      await pumpFrames(tester);

      expect(counter.pushes, 2, reason: '首屏 + 一个编辑器路由');
      expect(find.byType(EditorPage), findsOneWidget);
      expect(
        find.textContaining('示例工作区'),
        findsWidgets,
        reason: '工作区直达编辑器页，不再经过项目页',
      );
    });

    testWidgets('发送消息和切换会话都不推路由', (tester) async {
      final counter = _RouteCounter();
      await mount(tester, observer: counter);
      await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
      await pumpFrames(tester);
      final baseline = counter.pushes;

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '把输出改成大写',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await pumpFrames(tester);

      expect(find.text('把输出改成大写'), findsWidgets);
      expect(counter.pushes, baseline, reason: '发送消息不得推路由');

      await tester.tap(find.byKey(const ValueKey('editor-agent-new-session')));
      await pumpFrames(tester);

      expect(counter.pushes, baseline, reason: '切换会话不得推路由');
      expect(sessions.sessionsOf(project.id), hasLength(2));
    });
  });

  group('保活', () {
    testWidgets('跨断点编辑器内容和对话流都不丢', (tester) async {
      await mount(
        tester,
        size: const Size(500, 900),
        initialOpenPath: p.join(directory.path, 'src', 'main.dart'),
      );
      await pumpUntil(
        tester,
        () => find.byType(CodeEditor).evaluate().isNotEmpty,
      );
      final editorBefore = tester.state<State>(find.byType(CodeEditor));

      // 打开 Agent 面板，写一段草稿。
      await tester.tap(find.byTooltip('打开 Agent 面板'));
      await pumpFrames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '保留这段草稿',
      );
      await tester.pump();
      final paneBefore = tester.state<State>(find.byType(WorkbenchAgentPane));

      // 拉宽到宽屏：编辑器列和对话流都移动位置，但不重建。
      tester.view.physicalSize = const Size(1280, 900);
      await pumpFrames(tester);

      expect(find.byType(CodeEditor), findsOneWidget);
      expect(
        identical(editorBefore, tester.state<State>(find.byType(CodeEditor))),
        isTrue,
        reason: '跨断点不得重建代码编辑器',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('composer-input')))
            .controller
            ?.text,
        '保留这段草稿',
      );
      expect(find.byType(AgentDock), findsOneWidget);

      // 回到窄屏：还是同一个对话流 State。
      tester.view.physicalSize = const Size(500, 900);
      await pumpFrames(tester);
      expect(
        identical(
          paneBefore,
          tester.state<State>(find.byType(WorkbenchAgentPane)),
        ),
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('composer-input')))
            .controller
            ?.text,
        '保留这段草稿',
      );
    });

    testWidgets('最小化再恢复，Agent 面板状态保留', (tester) async {
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await mount(tester, retainedVisibility: visible);

      await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
      await pumpFrames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '最小化前写的',
      );
      await tester.pump();
      final paneBefore = tester.state<State>(find.byType(WorkbenchAgentPane));

      visible.value = false;
      await pumpFrames(tester);
      visible.value = true;
      await pumpFrames(tester);

      expect(find.byType(AgentDock), findsOneWidget);
      expect(
        identical(
          paneBefore,
          tester.state<State>(find.byType(WorkbenchAgentPane)),
        ),
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('composer-input')))
            .controller
            ?.text,
        '最小化前写的',
      );
    });
  });

  group('会话列表与角标', () {
    testWidgets('列表状态标记正确', (tester) async {
      final waiting = await sessions.create(project.id, title: '等确认的');
      final failed = await sessions.create(project.id, title: '失败的');
      runtime.liveStatuses[waiting.id] = AgentLiveStatus.awaitingApproval;
      runtime.liveStatuses[failed.id] = AgentLiveStatus.failed;

      await mount(tester);
      await _openSidebar(tester);
      await tester.tap(_toggleTarget(tester));
      await pumpFrames(tester);

      expect(find.byType(SessionListView), findsOneWidget);
      expect(find.textContaining('待确认'), findsWidgets);
      expect(find.textContaining('失败'), findsWidgets);
      expect(
        find.byKey(ValueKey('session-status-${waiting.id}')),
        findsOneWidget,
      );
    });

    testWidgets('后台会话待确认时 agent 图标有角标', (tester) async {
      final waiting = await sessions.create(project.id, title: '等确认的');
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('editor-agent-badge')), findsNothing);

      runtime.liveStatuses[waiting.id] = AgentLiveStatus.awaitingApproval;
      runtime.notifyLive();
      await pumpFrames(tester);

      expect(find.byKey(const ValueKey('editor-agent-badge')), findsOneWidget);
    });

    testWidgets('空会话列表给出说明和主操作', (tester) async {
      await mount(tester);
      await _openSidebar(tester);
      await tester.tap(_toggleTarget(tester));
      await pumpFrames(tester);

      expect(find.text('还没有会话'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-empty-create')),
        findsOneWidget,
      );
    });
  });

  group('记忆', () {
    testWidgets('选模型后按项目记下', (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
      await pumpFrames(tester);
      await pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('composer-model')).evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const ValueKey('composer-model')));
      await pumpFrames(tester);
      await tester.tap(find.text('Model A').last);
      await pumpFrames(tester);

      expect(
        composerDefaults.valueFor(project.id)?.modelId,
        'model-a',
        reason: '模型选择要按项目落盘（design.md §4 第 9 条）',
      );
    });
  });

  group('门控', () {
    testWidgets('离线产品任何宽度都没有 agent 控件', (tester) async {
      StudioProfile.current = const StudioProfile(
        id: 'offline-product',
        appTitle: 'QFLIFlow',
        templates: [],
        productKey: StudioProductCatalog.pyFlowKey,
        isOffline: true,
      );
      await mount(tester, size: const Size(1280, 900));

      expect(find.byKey(const ValueKey('editor-agent-toggle')), findsNothing);
      expect(find.byType(AgentDock), findsNothing);
      expect(find.byType(SessionListView), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
        findsNothing,
      );

      // 窄屏的抽屉里也不许出现切换键：离线产品没有会话可言。
      await mount(tester, size: const Size(500, 900));
      await tester.tap(find.byTooltip('打开文件树'));
      await pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsNothing,
      );
    });

    testWidgets('agent 面板未展开时不解析运行时', (tester) async {
      EditorAgentHost.resetRuntimeResolutions();
      await mount(tester, injectRuntime: false);

      expect(EditorAgentHost.runtimeResolutions, 0);
      expect(find.byType(WorkbenchAgentPane), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
        findsOneWidget,
        reason: '切换键在，但还没有解析运行时',
      );
      // 还没解析运行时，会话列表还不存在，切换目标仍指向会话。
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsOneWidget,
      );
      expect(find.byType(SessionListView), findsNothing);
    });

    testWidgets('未登录时对话流显示登录引导，不发错误', (tester) async {
      final signedOut = AuthStore();
      // 换掉 setUp 里的登录态；旧实例还没有监听者，直接释放。
      auth.dispose();
      auth = signedOut;
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
      await pumpFrames(tester);

      expect(find.text('需要登录'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-guide-action')), findsOneWidget);
    });
  });

  group('基线契约', () {
    test('断点只从 breakpoints 取', () {
      expect(layoutOf(0), WorkbenchLayout.narrow);
      expect(layoutOf(719), WorkbenchLayout.narrow);
      expect(layoutOf(720), WorkbenchLayout.medium);
      expect(layoutOf(1099), WorkbenchLayout.medium);
      expect(layoutOf(1100), WorkbenchLayout.wide);
    });

    test('WorkbenchState 只在值变化时通知', () {
      final state = WorkbenchState(projectId: 'p1');
      addTearDown(state.dispose);
      var notified = 0;
      state.addListener(() => notified++);
      state.showMainPane(state.mainPane);
      state.setAgentPaneCollapsed(state.agentPaneCollapsed);
      expect(notified, 0);
      state.showMainPane(MainPane.editor);
      expect(notified, 1);
    });
  });
  group('侧边栏标题行的单一切换键', () {
    testWidgets('文件模式：切换键在最右，目标是会话', (tester) async {
      await mount(tester);
      await _openSidebar(tester);

      final card = tester.getRect(find.byType(FileExplorer).first);
      final root = find.byKey(const ValueKey('editor-sidebar-section-switch'));
      expect(root, findsOneWidget);
      final rootRect = tester.getRect(root);
      // 同一张卡片、同一个标题行。
      expect(rootRect.top, greaterThanOrEqualTo(card.top));
      expect(rootRect.bottom, lessThanOrEqualTo(card.top + 56));

      // 只画一个目标，不再两段并排。
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-files')),
        findsNothing,
        reason: '文件模式下切换键指向会话，不应再并排画两段',
      );

      // 最右：在所有标题动作的右边。
      final newFile = _headerAction('新建文件');
      expect(
        rootRect.left,
        greaterThanOrEqualTo(tester.getRect(newFile).right),
        reason: '切换键排在最右端',
      );

      // 上下文动作：文件动作在，会话动作不混进来。
      expect(find.byKey(const ValueKey('file-explorer-more')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-new')), findsNothing);
      expect(find.byKey(const ValueKey('session-list-menu')), findsNothing);
    });

    testWidgets('会话模式：同一卡片、同一位置，目标反过来变文件', (tester) async {
      await mount(tester);
      await _openSidebar(tester);

      final cardBefore = tester.getRect(find.byType(FileExplorer).first);
      final rootBefore = tester.getRect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
      );

      await tester.tap(_toggleTarget(tester));
      await pumpFrames(tester);

      // 外框还是同一个，不是第二张卡片。
      final cardAfter = tester.getRect(find.byType(FileExplorer));
      expect(cardAfter.left, cardBefore.left);
      expect(cardAfter.width, cardBefore.width);

      // 切换键位置不跳，只是目标反了。
      final rootAfter = tester.getRect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
      );
      expect(rootAfter.left, moreOrLessEquals(rootBefore.left, epsilon: 0.5));
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-files')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsNothing,
      );

      // 会话动作可达，文件动作不再显示。
      expect(find.byKey(const ValueKey('session-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-list-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('file-explorer-more')), findsNothing);
      expect(find.byTooltip('新建文件'), findsNothing);

      // 会话主体在卡片内部。
      expect(find.byType(SessionListView), findsOneWidget);
      expect(
        tester.getRect(find.byType(SessionListView)).top,
        greaterThanOrEqualTo(cardBefore.top),
      );
    });

    testWidgets('再点一次切回文件模式，文件动作恢复', (tester) async {
      await mount(tester);
      await _openSidebar(tester);

      await tester.tap(_toggleTarget(tester));
      await pumpFrames(tester);
      await tester.tap(_toggleTarget(tester));
      await pumpFrames(tester);

      expect(find.byTooltip('新建文件'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-new')), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsOneWidget,
      );
    });

    // 真实渲染尺寸：只声明最小约束时控件会被默认尺寸撑大，所以这里直接量出来。
    testWidgets('两种模式的标题动作与切换键都是 44×44、图标 20', (tester) async {
      await mount(tester);
      await _openSidebar(tester);

      final filesToggle = tester.getSize(_toggleTarget(tester));
      _expectHeaderTarget(tester, _headerAction('新建文件'), '文件模式 新建文件');
      _expectHeaderTarget(
        tester,
        find.byKey(const ValueKey('file-explorer-more')),
        '文件模式 溢出菜单',
      );
      _expectHeaderTarget(tester, _toggleTarget(tester), '文件模式 切换键');

      await tester.tap(_toggleTarget(tester));
      await pumpFrames(tester);

      final sessionsToggle = tester.getSize(_toggleTarget(tester));
      _expectHeaderTarget(
        tester,
        find.byKey(const ValueKey('session-new')),
        '会话模式 新会话',
      );
      _expectHeaderTarget(
        tester,
        find.byKey(const ValueKey('session-list-menu')),
        '会话模式 会话菜单',
      );
      _expectHeaderTarget(tester, _toggleTarget(tester), '会话模式 切换键');

      // 两种模式下切换键尺寸完全一致。
      expect(sessionsToggle, filesToggle);
    });

    // 窄侧边栏 + 字缩放 1.3：切换键不能缩水，也不能把动作挤没。
    for (final (label, size) in const [
      ('280 宽', Size(500, 900)),
      ('320 宽', Size(560, 900)),
    ]) {
      testWidgets('$label · 字缩放 1.3：切换键仍 44×44 且能双向切', (tester) async {
        await mount(tester, size: size, textScale: 1.3);
        await _openSidebar(tester);

        _expectHeaderTarget(tester, _toggleTarget(tester), '$label 切换键');
        expect(
          find.byKey(const ValueKey('editor-sidebar-section-sessions')),
          findsOneWidget,
        );

        await tester.tap(_toggleTarget(tester));
        await pumpFrames(tester);

        expect(
          find.byKey(const ValueKey('editor-sidebar-section-files')),
          findsOneWidget,
        );
        _expectHeaderTarget(tester, _toggleTarget(tester), '$label 会话模式切换键');
      });
    }
  });

  group('窄侧边栏标题行', () {
    testWidgets('280 宽：项目选择器可用，其余动作进溢出菜单', (tester) async {
      await mount(tester, size: const Size(500, 900));
      await _openSidebar(tester);

      final picker = find.byKey(const ValueKey('file-explorer-project-picker'));
      expect(picker, findsOneWidget);
      // 项目选择器必须有可用宽度，不能被挤成零宽。
      expect(tester.getSize(picker).width, greaterThanOrEqualTo(72));

      // 常用动作：新建文件就地可达；搜索最窄时也在溢出菜单里。
      expect(find.byTooltip('新建文件'), findsOneWidget);

      // 新建文件夹与刷新一定在溢出菜单里，而不是消失。
      expect(find.byTooltip('新建文件夹'), findsNothing);
      expect(find.byTooltip('刷新'), findsNothing);
      // 搜索按剩余宽度决定就地还是进菜单，两条路都算可达。
      final searchInline = find.byTooltip('搜索文件').evaluate().isNotEmpty;
      final more = find.byKey(const ValueKey('file-explorer-more'));
      expect(more, findsOneWidget);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('新建文件夹'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
      if (searchInline) {
        expect(find.text('搜索文件'), findsNothing, reason: '就地可达就不重复进菜单');
      } else {
        expect(find.text('搜索文件'), findsOneWidget, reason: '最窄时搜索仍可达');
      }
    });

    // 两种宽度 × 字缩放 1.3，都要保证项目选择器可用、所有操作可达。
    for (final (label, size) in const [
      ('280 宽', Size(500, 900)),
      ('320 宽', Size(560, 900)),
    ]) {
      testWidgets('$label · 字缩放 1.3：选择器可用且操作全可达', (tester) async {
        await mount(tester, size: size, textScale: 1.3);
        await _openSidebar(tester);

        final picker = find.byKey(
          const ValueKey('file-explorer-project-picker'),
        );
        expect(picker, findsOneWidget);
        expect(
          tester.getSize(picker).width,
          greaterThanOrEqualTo(72),
          reason: '字放大后项目选择器仍必须有可用宽度',
        );

        // 新建文件就地可达。
        expect(find.byTooltip('新建文件'), findsOneWidget);

        // 其余操作要么就地、要么在溢出菜单里，不能消失。
        final inlineNewFolder = find.byTooltip('新建文件夹');
        final inlineRefresh = find.byTooltip('刷新');
        final more = find.byKey(const ValueKey('file-explorer-more'));
        if (inlineNewFolder.evaluate().isEmpty) {
          expect(more, findsOneWidget);
          await tester.tap(more);
          await tester.pumpAndSettle();
          expect(find.text('新建文件夹'), findsOneWidget);
          expect(find.text('刷新'), findsOneWidget);
        } else {
          expect(inlineRefresh, findsOneWidget);
        }
      });
    }

    testWidgets('320 宽不选全套按钮：留给选择器足够宽度', (tester) async {
      // 侧边栏 320 时旧阈值（318）会选“四个按钮全放”，把选择器挤到 ~50。
      await mount(tester, size: const Size(560, 900));
      await _openSidebar(tester);

      final picker = find.byKey(const ValueKey('file-explorer-project-picker'));
      expect(
        tester.getSize(picker).width,
        greaterThanOrEqualTo(96),
        reason: '动作预算要扣掉真实的四个按钮宽度',
      );
    });
  });

  group('共享标题行', () {
    testWidgets('SidebarSectionSwitch 是单个图标按钮，点一下换到另一边', (tester) async {
      var current = SidebarSection.files;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SidebarSectionSwitch(
                section: current,
                onChanged: (value) => update(() => current = value),
              ),
            ),
          ),
        ),
      );

      final root = find.byKey(const ValueKey('editor-sidebar-section-switch'));
      expect(root, findsOneWidget);

      // 普通图标按钮，不是自绘的两段条。
      expect(tester.widget(_toggleTarget(tester)), isA<IconButton>());
      _expectHeaderTarget(tester, _toggleTarget(tester), '独立切换键');

      // 文件模式下只有指向会话的那一个 key。
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-files')),
        findsNothing,
      );

      await tester.tap(_toggleTarget(tester));
      await tester.pumpAndSettle();
      expect(current, SidebarSection.sessions);

      // 目标反过来。
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-files')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
        findsNothing,
      );
    });
  });
}

/// 标题行里由 tooltip 定位的动作按钮。
Finder _headerAction(String tooltip) => find
    .ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton))
    .first;

/// 切换键的可点目标：根 key 可能就在 IconButton 上，也可能包在它外面。
Finder _toggleTarget(WidgetTester tester) {
  final root = find.byKey(const ValueKey('editor-sidebar-section-switch'));
  expect(root, findsOneWidget);
  final inner = find.descendant(of: root, matching: find.byType(IconButton));
  if (inner.evaluate().isNotEmpty) return inner.first;
  final outer = find.ancestor(of: root, matching: find.byType(IconButton));
  if (outer.evaluate().isNotEmpty) return outer.first;
  return root;
}

/// 量真实渲染尺寸：只写最小约束时，控件会被默认尺寸撑大，
/// 所以这里比对等值而不是下限。
void _expectHeaderTarget(WidgetTester tester, Finder target, String label) {
  final size = tester.getSize(target);
  expect(size.width, moreOrLessEquals(44, epsilon: 0.01), reason: '$label 宽度');
  expect(size.height, moreOrLessEquals(44, epsilon: 0.01), reason: '$label 高度');
  final icons = find.descendant(of: target, matching: find.byType(Icon));
  expect(icons, findsOneWidget, reason: '$label 应该只有一个图标');
  final iconSize = tester.getSize(icons);
  expect(
    iconSize.width,
    moreOrLessEquals(20, epsilon: 0.01),
    reason: '$label 图标宽度',
  );
  expect(
    iconSize.height,
    moreOrLessEquals(20, epsilon: 0.01),
    reason: '$label 图标高度',
  );
}

/// 记录路由推入次数。
class _RouteCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

/// 让真实的文件 I/O 和定时器跑完。
Future<void> pumpFrames(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

/// 打开侧边栏。宽屏默认收起，分段在侧边栏顶部，得先展开。
Future<void> _openSidebar(WidgetTester tester) async {
  final open = find.byTooltip('打开文件树');
  if (open.evaluate().isEmpty) return;
  await tester.tap(open);
  await pumpFrames(tester);
}

/// 打开「更多」菜单并点其中一项。
Future<void> _openMoreMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多'));
  final entry = find.widgetWithText(PopupMenuItem<String>, label);
  await pumpUntil(tester, () => entry.evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(entry);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int frames = 300,
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: '等待的条件没有达成');
}

/// 内存实现：测试里不碰文件系统，也不留目录探测定时器。
class _MemoryComposerDefaults implements ComposerDefaultsStore {
  final Map<String, ComposerDefaults> _byProject = {};

  ComposerDefaults? valueFor(String projectId) => _byProject[projectId];

  @override
  Future<ComposerDefaults?> read(String projectId) async =>
      _byProject[projectId];

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) async {
    _byProject[projectId] = defaults;
  }
}
