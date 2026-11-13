@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/agent/agent_dock.dart';
import 'package:qfli_studio_core/editor/agent/editor_agent_host.dart';
import 'package:qfli_studio_core/editor/agent/session_list_view.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
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
    ValueNotifier<bool>? retainedVisibility,
    String? initialOpenPath,
    _RouteCounter? observer,
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
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          initialOpenPath: initialOpenPath,
          agentRuntime: injectRuntime ? runtime : null,
          retainedVisibility: retainedVisibility,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('布局', () {
    testWidgets('宽屏有 Agent 入口与「文件 | 会话」分段', (tester) async {
      await mount(tester);

      expect(find.byKey(const ValueKey('editor-agent-toggle')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
        findsOneWidget,
      );
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

    testWidgets('窄屏用分段条切换编辑器与 Agent', (tester) async {
      await mount(tester, size: const Size(500, 900));

      expect(
        find.byKey(const ValueKey('editor-main-pane-switch')),
        findsOneWidget,
      );
      expect(find.byType(AgentDock), findsNothing);

      await tester.tap(find.text('Agent'));
      await pumpFrames(tester);

      expect(find.byType(WorkbenchAgentPane), findsOneWidget);
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

      // 切到 Agent 分段，写一段草稿。
      await tester.tap(find.text('Agent'));
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
      await tester.tap(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
      );
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
      await tester.tap(
        find.byKey(const ValueKey('editor-sidebar-section-sessions')),
      );
      await pumpFrames(tester);

      expect(find.text('还没有会话'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-empty-create')), findsOneWidget);
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

      // 窄屏的抽屉里也不许出现分段：离线产品没有会话可言。
      await mount(tester, size: const Size(500, 900));
      await tester.tap(find.byTooltip('打开文件树'));
      await pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('editor-sidebar-section-switch')),
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
        reason: '分段在，但还没有解析运行时',
      );
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
