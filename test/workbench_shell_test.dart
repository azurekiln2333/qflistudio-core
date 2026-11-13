import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/chat/composer_card.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/layout/breakpoints.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/project/project_page.dart';
import 'package:qfli_studio_core/shell/login_gate.dart';
import 'package:qfli_studio_core/shell/project_entry.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/shell/workbench_shell.dart';
import 'package:qfli_studio_core/shell/workbench_state.dart';
import 'package:qfli_studio_core/sidebar/workbench_sidebar.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

Project _project() => Project(
  id: 'p1',
  name: 'Demo',
  path: 'demo',
  createdAt: DateTime(2026, 1, 1),
  lastOpenedAt: DateTime(2026, 1, 1),
);

/// 计数用的编辑器替身，用来证明跨断点后状态没丢。
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('count:$value', key: const ValueKey('counter-value')),
      ElevatedButton(
        key: const ValueKey('counter-increment'),
        onPressed: () => setState(() => value++),
        child: const Text('inc'),
      ),
    ],
  );
}

Widget _harness({
  required Size size,
  required AuthStore auth,
  WidgetBuilder? agentPaneBuilder,
  WorkbenchState? state,
  AgentRuntime? runtime,
  List<WorkbenchSessionItem> sessions = const [],
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: WorkbenchShell(
        project: _project(),
        auth: auth,
        store: ProjectStore(),
        settings: SettingsStore(),
        state: state,
        runtime: runtime,
        sessions: sessions,
        agentPaneBuilder: agentPaneBuilder,
        editorPaneBuilder: (_) => const _Counter(),
      ),
    ),
  );
}

/// 已登录的 store；不触盘（未 load 前没有存储文件）。
Future<AuthStore> _loggedInAuth() async {
  final auth = AuthStore();
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
  return auth;
}

void main() {
  group('breakpoints', () {
    test('三种宽度按契约分界', () {
      expect(layoutOf(0), WorkbenchLayout.narrow);
      expect(layoutOf(719), WorkbenchLayout.narrow);
      expect(layoutOf(720), WorkbenchLayout.medium);
      expect(layoutOf(1099), WorkbenchLayout.medium);
      expect(layoutOf(1100), WorkbenchLayout.wide);
      expect(layoutOf(4000), WorkbenchLayout.wide);
    });
  });

  group('WorkbenchState', () {
    test('切换各字段都会通知监听者', () {
      final state = WorkbenchState(projectId: 'p1');
      var notified = 0;
      state.addListener(() => notified++);

      state.selectSession('s1');
      state.showSidebarSection(SidebarSection.files);
      state.showMainPane(MainPane.editor);
      state.setAgentPaneCollapsed(true);

      expect(state.sessionId, 's1');
      expect(state.sidebarSection, SidebarSection.files);
      expect(state.mainPane, MainPane.editor);
      expect(state.agentPaneCollapsed, isTrue);
      expect(notified, 4);
    });

    test('写入相同值不通知', () {
      final state = WorkbenchState(projectId: 'p1');
      var notified = 0;
      state.addListener(() => notified++);
      state.showMainPane(state.mainPane);
      state.setAgentPaneCollapsed(state.agentPaneCollapsed);
      expect(notified, 0);
    });
  });

  group('登录门控', () {
    testWidgets('没有 LoginGateScope 时 ensureLoggedIn 返回 false', (tester) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = false;
              return ElevatedButton(
                onPressed: () async {
                  result = await ensureLoggedIn(context);
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('未登录时 agent 区域显示登录引导卡片', (tester) async {
      final auth = AuthStore();
      await tester.pumpWidget(
        _harness(size: const Size(1400, 900), auth: auth),
      );
      expect(find.byType(LoginGuideCard), findsOneWidget);
      expect(find.byKey(const ValueKey('login-guide-action')), findsOneWidget);
    });

    testWidgets('未登录时窄屏 agent 分段也显示引导卡片', (tester) async {
      final auth = AuthStore();
      await tester.pumpWidget(
        _harness(size: const Size(500, 900), auth: auth),
      );
      expect(find.byType(LoginGuideCard), findsOneWidget);
    });
  });

  group('工作台布局', () {
    testWidgets('宽屏三段：侧边栏、编辑器、对话流同时存在', (tester) async {
      await tester.pumpWidget(
        _harness(size: const Size(1400, 900), auth: AuthStore()),
      );
      expect(find.byType(WorkbenchSidebar), findsOneWidget);
      expect(find.byKey(const ValueKey('counter-value')), findsOneWidget);
      expect(find.byType(LoginGuideCard), findsOneWidget);
    });

    testWidgets('跨断点拉伸后编辑器状态不丢失', (tester) async {
      await tester.pumpWidget(
        _harness(size: const Size(1400, 900), auth: AuthStore()),
      );
      await tester.tap(find.byKey(const ValueKey('counter-increment')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('counter-increment')));
      await tester.pump();
      expect(find.text('count:2'), findsOneWidget);

      // 宽屏 → 中屏：对话流与编辑器改为单区，编辑器被 Offstage 隐藏。
      await tester.pumpWidget(
        _harness(size: const Size(900, 900), auth: AuthStore()),
      );
      await tester.pump();
      await tester.tap(find.text('编辑器'));
      await tester.pump();
      expect(find.text('count:2'), findsOneWidget);

      // 中屏 → 窄屏：侧边栏变抽屉，编辑器仍然保留。
      await tester.pumpWidget(
        _harness(size: const Size(500, 900), auth: AuthStore()),
      );
      await tester.pump();
      await tester.tap(find.text('编辑器'));
      await tester.pump();
      expect(find.text('count:2'), findsOneWidget);

      // 再拉回宽屏：仍然是同一份状态。
      await tester.pumpWidget(
        _harness(size: const Size(1400, 900), auth: AuthStore()),
      );
      await tester.pump();
      expect(find.text('count:2'), findsOneWidget);
    });

    testWidgets('窄屏用抽屉放侧边栏，中屏常驻', (tester) async {
      await tester.pumpWidget(
        _harness(size: const Size(500, 900), auth: AuthStore()),
      );
      expect(find.byType(WorkbenchSidebar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('workbench-open-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchSidebar), findsOneWidget);

      await tester.pumpWidget(
        _harness(size: const Size(900, 900), auth: AuthStore()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchSidebar), findsOneWidget);
    });

    testWidgets('宽屏可收起与展开对话流，收起后对话流仍存活', (tester) async {
      final state = WorkbenchState(projectId: 'p1');
      await tester.pumpWidget(
        _harness(
          size: const Size(1400, 900),
          auth: AuthStore(),
          state: state,
        ),
      );
      expect(find.byType(LoginGuideCard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workbench-toggle-agent-pane')));
      await tester.pump();
      expect(state.agentPaneCollapsed, isTrue);
      await tester.tap(find.byKey(const ValueKey('workbench-toggle-agent-pane')));
      await tester.pump();
      expect(state.agentPaneCollapsed, isFalse);
      expect(find.byType(LoginGuideCard), findsOneWidget);
    });

    testWidgets('侧边栏默认显示会话空状态', (tester) async {
      await tester.pumpWidget(
        _harness(size: const Size(1400, 900), auth: AuthStore()),
      );
      expect(find.text('还没有会话。新建一个会话开始对话。'), findsOneWidget);
    });

    testWidgets('侧边栏列出传入的会话', (tester) async {
      await tester.pumpWidget(
        _harness(
          size: const Size(1400, 900),
          auth: AuthStore(),
          sessions: const [
            WorkbenchSessionItem(id: 's1', title: '第一个会话'),
            WorkbenchSessionItem(id: 's2', title: '第二个会话'),
          ],
        ),
      );
      expect(find.text('第一个会话'), findsOneWidget);
      expect(find.text('第二个会话'), findsOneWidget);
      expect(find.text('还没有会话。新建一个会话开始对话。'), findsNothing);
    });
  });

  group('阶段 2 接线', () {
    testWidgets('已登录且有运行时时，对话流与输入卡片都就位', (tester) async {
      final auth = await _loggedInAuth();
      final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore());
      await tester.pumpWidget(
        _harness(size: const Size(1400, 900), auth: auth, runtime: runtime),
      );
      await tester.pump();
      expect(find.byType(WorkbenchAgentPane), findsOneWidget);
      expect(find.byType(ChatTranscript), findsOneWidget);
      expect(find.byType(ComposerCard), findsOneWidget);
      expect(find.byType(LoginGuideCard), findsNothing);
    });

    testWidgets('有运行时而未登录时仍显示登录引导，不崩溃', (tester) async {
      final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore());
      await tester.pumpWidget(
        _harness(
          size: const Size(1400, 900),
          auth: AuthStore(),
          runtime: runtime,
        ),
      );
      await tester.pump();
      expect(find.byType(LoginGuideCard), findsOneWidget);
      expect(find.byType(ComposerCard), findsNothing);
      expect(runtime.openedSessions, isEmpty);
    });

    testWidgets('给初始会话时打开它并加载消息', (tester) async {
      final auth = await _loggedInAuth();
      final sessions = MemoryAgentSessionStore();
      final meta = await sessions.create('p1', title: '第一个');
      final runtime = FakeAgentRuntime(sessions: sessions);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1400, 900)),
            child: WorkbenchShell(
              project: _project(),
              auth: auth,
              store: ProjectStore(),
              settings: SettingsStore(),
              runtime: runtime,
              initialSessionId: meta.id,
              editorPaneBuilder: (_) => const _Counter(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(runtime.openedSessions, contains(meta.id));
    });

    testWidgets('编辑器里的 AI 入口切到对话流，不再展开内嵌 AI 面板', (tester) async {
      final auth = await _loggedInAuth();
      final state = WorkbenchState(projectId: 'p1', mainPane: MainPane.editor);
      await tester.pumpWidget(
        _harness(
          size: const Size(900, 900),
          auth: auth,
          state: state,
          runtime: FakeAgentRuntime(sessions: MemoryAgentSessionStore()),
        ),
      );
      await tester.pump();
      expect(state.mainPane, MainPane.editor);
      // 工作台内部的切换由 EditorPage 的 AI 入口触发；这里直接验证同一个
      // 状态实例被布局读取，切到 agent 后对话流可见。
      state.showMainPane(MainPane.agent);
      await tester.pump();
      expect(find.byType(WorkbenchAgentPane), findsOneWidget);
    });
  });

  group('项目入口', () {
    testWidgets('装配运行时后渲染项目页', (tester) async {
      final auth = await _loggedInAuth();
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectEntryPage(
            project: _project(),
            auth: auth,
            store: ProjectStore(),
            settings: SettingsStore(),
            runtime: FakeAgentRuntime(sessions: MemoryAgentSessionStore()),
            persistComposerDefaults: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ProjectPage), findsOneWidget);
      expect(find.byKey(const ValueKey('project-new-session')), findsOneWidget);
      // onOpenEditor 非空时项目页提供编辑器入口。
      expect(find.byTooltip('编辑器'), findsOneWidget);
      // 可交互的输入框与工具提示会留下光标/长按定时器，收尾前卸载再走完。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('没有会话时项目页显示登录引导而不是崩溃', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectEntryPage(
            project: _project(),
            auth: AuthStore(),
            store: ProjectStore(),
            settings: SettingsStore(),
            runtime: FakeAgentRuntime(sessions: MemoryAgentSessionStore()),
            persistComposerDefaults: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ProjectPage), findsOneWidget);
      expect(find.byType(LoginGuideCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
