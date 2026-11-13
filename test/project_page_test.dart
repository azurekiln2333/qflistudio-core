import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/composer_draft.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/project/project_page.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 只覆盖登录判定，不碰真实存储。
class FakeAuthStore extends AuthStore {
  FakeAuthStore({required this.loggedIn});

  final bool loggedIn;

  @override
  bool get isLoggedIn => loggedIn;
}

void main() {
  late MemoryAgentSessionStore sessions;
  late FakeAgentRuntime runtime;
  late Project project;

  setUp(() {
    sessions = MemoryAgentSessionStore();
    runtime = FakeAgentRuntime(
      sessions: sessions,
      modelOptions: const [AgentModelOption(id: 'model-a', label: 'Model A')],
      skillRefs: const [AgentSkillRef(name: 'style', description: '写法')],
    );
    project = Project.create(name: 'BackgroundSmoke', path: '/tmp/smoke');
  });

  Widget host(Widget child) => MaterialApp(home: child);

  ProjectPage page({
    bool loggedIn = true,
    Future<bool> Function(String sessionId, ComposerDraft draft)? onOpenSession,
  }) => ProjectPage(
    project: project,
    runtime: runtime,
    auth: FakeAuthStore(loggedIn: loggedIn),
    onOpenSession: onOpenSession,
  );

  testWidgets('a signed out user sees the login guide, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(host(page(loggedIn: false)));
    await tester.pumpAndSettle();

    expect(find.text('需要登录'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-input')), findsNothing);
  });

  testWidgets('an empty project explains how to start a session', (
    tester,
  ) async {
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();

    expect(find.text('这个项目还没有会话'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-input')), findsOneWidget);
  });

  testWidgets('existing sessions are listed with their title', (tester) async {
    await sessions.create(project.id, title: '改输出');
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();

    expect(find.text('改输出'), findsOneWidget);
    expect(find.text('这个项目还没有会话'), findsNothing);
  });

  testWidgets('tapping a session opens it in the workbench', (tester) async {
    final meta = await sessions.create(project.id, title: '改输出');
    final opened = <String>[];
    await tester.pumpWidget(
      host(
        page(
          onOpenSession: (sessionId, draft) async {
            opened.add(sessionId);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('session-${meta.id}')));
    await tester.pumpAndSettle();

    expect(opened, [meta.id]);
  });

  testWidgets('sending the first message creates a session and hands it over', (
    tester,
  ) async {
    final handed = <(String, ComposerDraft)>[];
    await tester.pumpWidget(
      host(
        page(
          onOpenSession: (sessionId, draft) async {
            handed.add((sessionId, draft));
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      '把输出改成大写',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();

    expect(handed, hasLength(1));
    final (sessionId, draft) = handed.single;
    expect(draft.text, '把输出改成大写');
    expect(sessions.metaOf(sessionId), isNotNull);
    expect(sessions.sessionsOf(project.id), hasLength(1));
  });

  testWidgets('a refused handover keeps the text in the card', (tester) async {
    await tester.pumpWidget(
      host(page(onOpenSession: (sessionId, draft) async => false)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      '保留这一条',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();

    expect(find.text('保留这一条'), findsOneWidget);
  });

  testWidgets('the new session action creates one', (tester) async {
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('project-new-session')));
    await tester.pumpAndSettle();

    expect(sessions.sessionsOf(project.id), hasLength(1));
    expect(find.text(AgentSessionStore.defaultTitle), findsOneWidget);
  });

  testWidgets('a session can be renamed from its menu', (tester) async {
    final meta = await sessions.create(project.id, title: '新会话');
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('session-menu-${meta.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('session-rename-input')),
      '改成大写',
    );
    await tester.tap(find.byKey(const ValueKey('session-rename-confirm')));
    await tester.pumpAndSettle();

    expect(sessions.metaOf(meta.id)?.title, '改成大写');
    expect(find.text('改成大写'), findsOneWidget);
  });

  testWidgets('a session can be deleted after confirming', (tester) async {
    final meta = await sessions.create(project.id, title: '待删除');
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('session-menu-${meta.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('无法恢复'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-delete-confirm')));
    await tester.pumpAndSettle();

    expect(sessions.metaOf(meta.id), isNull);
    expect(find.text('这个项目还没有会话'), findsOneWidget);
  });

  testWidgets('a login requirement from the harness degrades to the guide', (
    tester,
  ) async {
    runtime = FakeAgentRuntime(sessions: sessions, loginRequired: true);
    await tester.pumpWidget(host(page()));
    await tester.pumpAndSettle();

    expect(find.text('需要登录'), findsOneWidget);
  });
}
