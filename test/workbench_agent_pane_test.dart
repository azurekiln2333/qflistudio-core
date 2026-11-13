import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/chat/composer_card.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/shell/login_gate.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// Agent 面板的反馈、错误和输入卡片（CHECKLIST 的 C、D、H 与 E2 显示部分）。
void main() {
  Project project() => Project(
    id: 'p1',
    name: 'Demo',
    path: 'demo',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  Future<AuthStore> loggedIn() async {
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

  Widget host({
    required AuthStore auth,
    required FakeAgentRuntime runtime,
    String? sessionId,
    Size size = const Size(420, 800),
    double bottomInset = 0,
  }) => MaterialApp(
    home: LoginGateScope(
      auth: auth,
      child: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            viewInsets: EdgeInsets.only(bottom: bottomInset),
          ),
          child: WorkbenchAgentPane(
            project: project(),
            runtime: runtime,
            auth: auth,
            settings: SettingsStore(),
            sessionId: sessionId,
          ),
        ),
      ),
    ),
  );

  /// 首帧渲染，之后 bootstrap 才开始；两次 pump 让会话与模型的状态落地。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// 卸下窗口：取消等待计时器，避免测试结束时残留定时器。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  String inputText(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('composer-input')),
    );
    return field.controller?.text ?? '';
  }

  FakeAgentRuntime runtimeFor(
    MemoryAgentSessionStore store, {
    List<AgentModelOption> models = const [],
    bool loginRequired = false,
  }) => FakeAgentRuntime(
    sessions: store,
    modelOptions: models,
    loginRequired: loginRequired,
  );

  group('C 反馈', () {
    testWidgets('C1 发送后同一帧：输入清空、出现用户消息、发送键变停止键', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..sendGate = Completer<void>();
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '把输出改成大写',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));

      // 只 pump 一帧。
      await tester.pump();

      expect(inputText(tester), isEmpty);
      expect(
        find.descendant(
          of: find.byType(ChatTranscript),
          matching: find.text('把输出改成大写'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('composer-stop')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-send')), findsNothing);

      facade.sendGate!.complete();
      await unmount(tester);
    });

    testWidgets('C2 对话流顶部有进度条', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-progress')), findsNothing);

      facade.state = AgentRunState.running;
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-progress')), findsOneWidget);
      final transcript = tester.widget<ChatTranscript>(
        find.byType(ChatTranscript),
      );
      expect(transcript.state, AgentRunState.running);

      await unmount(tester);
    });

    testWidgets('C3 状态行跟随 activity 与排队状态', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      facade
        ..state = AgentRunState.running
        ..activity = '正在读取 lib/main.dart';
      await tester.pump();
      expect(find.text('正在读取 lib/main.dart'), findsOneWidget);

      // activity 为空时写「思考中…」。
      facade.activity = null;
      await tester.pump();
      expect(find.text('思考中…'), findsOneWidget);

      // 排队时写「排队中」。
      facade.state = AgentRunState.idle;
      runtime.liveStatuses[meta.id] = AgentLiveStatus.queued;
      runtime.notifyLive();
      await tester.pump();
      expect(find.text('排队中'), findsOneWidget);

      runtime.liveStatuses[meta.id] = AgentLiveStatus.idle;
      runtime.notifyLive();
      await unmount(tester);
    });

    testWidgets('C4 超过 3 秒追加已等待秒数', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      facade.state = AgentRunState.running;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 不足 3 秒不显示。
      expect(find.byKey(const ValueKey('chat-waiting')), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('已等待 3 秒'), findsOneWidget);

      // 结束运行后计时器消失，文案随之清空。
      facade.state = AgentRunState.idle;
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-waiting')), findsNothing);

      await unmount(tester);
    });

    testWidgets('C5 工具条目运行中转圈，完成后对勾或叉', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      facade
        ..state = AgentRunState.running
        ..seed([
          const AgentMessageView(
            id: 't1',
            role: 'tool',
            text: '',
            toolName: 'read_file',
            pending: true,
          ),
          const AgentMessageView(
            id: 't2',
            role: 'tool',
            text: '12 行',
            toolName: 'read_file',
          ),
          const AgentMessageView(
            id: 't3',
            role: 'tool',
            text: '路径超出项目目录',
            toolName: 'write_file',
            isError: true,
          ),
        ]);
      await tester.pump();

      expect(find.byKey(const ValueKey('tool-spinner-t1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-done-t2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-done-t3')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('C6 取消后恢复可输入状态', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      facade.state = AgentRunState.running;
      await tester.pump();
      expect(find.byKey(const ValueKey('composer-stop')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-stop')));
      await tester.pump();

      expect(facade.cancelCount, 1);
      expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-stop')), findsNothing);

      // 输入卡片仍然可用，发送按钮在输入后可用。
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '再来一次',
      );
      await tester.pump();
      final send = tester.widget<IconButton>(
        find.byKey(const ValueKey('composer-send')),
      );
      expect(send.onPressed, isNotNull);

      await unmount(tester);
    });
  });

  group('D 输入卡片', () {
    testWidgets('D1 工具行有加号、权限、模型、推理强度、发送', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(
        store,
        models: const [
          AgentModelOption(
            id: 'model-a',
            label: 'Model A',
            reasoningEfforts: ['low', 'high'],
          ),
        ],
      );
      runtime.facades[meta.id] = FakeAgentFacade(sessionId: meta.id);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('composer-plus')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-permission')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-reasoning')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
      // 选中的模型支持推理强度，标签是当前档位。
      expect(find.text('low'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('D2 模型列表为空时仍然可见，文案是「默认模型」', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      runtime.facades[meta.id] = FakeAgentFacade(sessionId: meta.id);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
      expect(find.text('默认模型'), findsOneWidget);

      // 点开说明原因并提供重试。
      await tester.tap(find.byKey(const ValueKey('composer-model')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-model-retry')), findsOneWidget);
      expect(find.textContaining('默认模型'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('composer-model-retry')));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('D3 模型加载中显示加载态，且不影响会话与发送', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store)..modelsGate = Completer<void>();
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      // models() 永不返回：会话照常显示，选择器显示「模型…」。
      expect(find.byType(ComposerCard), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
      expect(find.text('模型…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('composer-model')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // 仍然能发送。
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '模型列表还没回来也能发',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      expect(facade.sentTexts, ['模型列表还没回来也能发']);

      await unmount(tester);
    });

    testWidgets('D4 草稿和附件按会话保留', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final first = await store.create('p1', title: '会话一');
      final second = await store.create('p1', title: '会话二');
      final runtime = runtimeFor(store);
      runtime.facades[first.id] = FakeAgentFacade(sessionId: first.id);
      runtime.facades[second.id] = FakeAgentFacade(sessionId: second.id);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: first.id),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '会话一的草稿',
      );
      await tester.pump();
      expect(inputText(tester), '会话一的草稿');

      // 切到第二个会话：草稿是空的。
      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: second.id),
      );
      await settle(tester);
      expect(inputText(tester), isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '会话二的草稿',
      );
      await tester.pump();

      // 切回第一个会话：草稿还在，且不是第二个会话的内容。
      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: first.id),
      );
      await settle(tester);
      expect(inputText(tester), '会话一的草稿');

      await unmount(tester);
    });

    testWidgets('D6 软键盘弹出时输入卡片上移，不被遮挡', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      runtime.facades[meta.id] = FakeAgentFacade(sessionId: meta.id);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);
      final before = tester.getRect(find.byType(ComposerCard));

      await tester.pumpWidget(
        host(
          auth: auth,
          runtime: runtime,
          sessionId: meta.id,
          bottomInset: 300,
        ),
      );
      await settle(tester);
      final after = tester.getRect(find.byType(ComposerCard));

      expect(before.bottom - after.bottom, closeTo(300, 1));

      await unmount(tester);
    });

    testWidgets('空会话：面板里有输入卡片，发送后在原处建会话', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final runtime = runtimeFor(store);

      await tester.pumpWidget(host(auth: auth, runtime: runtime));
      await settle(tester);

      expect(find.byType(ComposerCard), findsOneWidget);
      expect(find.text('开始一个新的会话'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '新建一个会话试试',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      await tester.pump();

      // 会话在原处创建，界面没有跳转：输入卡片和对话流都还在。
      expect(store.sessionsOf('p1'), hasLength(1));
      expect(find.byType(ComposerCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatTranscript),
          matching: find.text('新建一个会话试试'),
        ),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('模型不支持推理强度时隐藏推理强度', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(
        store,
        models: const [AgentModelOption(id: 'plain', label: 'Plain')],
      );
      runtime.facades[meta.id] = FakeAgentFacade(sessionId: meta.id);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-reasoning')), findsNothing);

      await unmount(tester);
    });

    testWidgets('窄卡片下工具行不溢出，只显示图标', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(
        store,
        models: const [
          AgentModelOption(
            id: 'model-a',
            label: '很长的模型名字，长到会把工具行撑开',
            reasoningEfforts: ['high'],
          ),
        ],
      );
      runtime.facades[meta.id] = FakeAgentFacade(sessionId: meta.id);

      await tester.pumpWidget(
        host(
          auth: auth,
          runtime: runtime,
          sessionId: meta.id,
          size: const Size(320, 700),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      // 图标按钮仍然齐全，可点区域不小于 44。
      for (final key in const [
        'composer-permission',
        'composer-model',
        'composer-reasoning',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
        expect(size.width, greaterThanOrEqualTo(44), reason: key);
      }

      await unmount(tester);
    });
  });

  group('E 会话', () {
    testWidgets('切换会话不 dispose 旧 facade，也不停止它', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final first = await store.create('p1', title: '会话一');
      final second = await store.create('p1', title: '会话二');
      final runtime = runtimeFor(store);
      final facadeA = FakeAgentFacade(sessionId: first.id);
      final facadeB = FakeAgentFacade(sessionId: second.id);
      runtime.facades[first.id] = facadeA;
      runtime.facades[second.id] = facadeB;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: first.id),
      );
      await settle(tester);
      facadeA.state = AgentRunState.running;
      await tester.pump();

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: second.id),
      );
      await settle(tester);

      expect(facadeA.disposeCount, 0);
      expect(facadeB.disposeCount, 0);
      expect(facadeA.state, AgentRunState.running);
      // 用户看过这个会话。
      expect(runtime.seenSessions, contains(second.id));

      facadeA.state = AgentRunState.idle;
      await unmount(tester);
    });

    testWidgets('E2 排队状态在面板上显示为「排队中」', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      runtime.facades[meta.id] = FakeAgentFacade(sessionId: meta.id);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      runtime.liveStatuses[meta.id] = AgentLiveStatus.queued;
      runtime.notifyLive();
      await tester.pump();

      expect(find.text('排队中'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-progress')), findsOneWidget);

      runtime.liveStatuses[meta.id] = AgentLiveStatus.idle;
      runtime.notifyLive();
      await unmount(tester);
    });

    testWidgets('快速 A 到 B：只显示 B', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final first = await store.create('p1', title: '会话一');
      final second = await store.create('p1', title: '会话二');
      final runtime = runtimeFor(store);
      final blocker = Completer<void>();
      runtime.openBlockers[first.id] = blocker;
      final facadeA = FakeAgentFacade(sessionId: first.id)
        ..seed(const [
          AgentMessageView(id: 'a1', role: 'assistant', text: '会话一的消息'),
        ]);
      final facadeB = FakeAgentFacade(sessionId: second.id)
        ..seed(const [
          AgentMessageView(id: 'b1', role: 'assistant', text: '会话二的消息'),
        ]);
      runtime.facades[first.id] = facadeA;
      runtime.facades[second.id] = facadeB;

      // 先打开 A，被拦住；还没回来就切到 B。
      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: first.id),
      );
      await settle(tester);

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: second.id),
      );
      await settle(tester);
      expect(find.text('会话二的消息'), findsOneWidget);

      // A 这时才回来，不能把界面切回去。
      blocker.complete();
      await settle(tester);
      expect(find.text('会话一的消息'), findsNothing);
      expect(find.text('会话二的消息'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('H 错误', () {
    Future<FakeAgentFacade> failedPane(
      WidgetTester tester, {
      required AgentErrorKind kind,
      int? statusCode,
      String detail = '',
      String? lastError,
    }) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      facade.seed(const [
        AgentMessageView(id: 'm0', role: 'user', text: '跑一下'),
      ]);
      facade.lastError = lastError;
      facade
        ..lastErrorInfo = AgentErrorInfo(
          kind: kind,
          statusCode: statusCode,
          detail: detail,
        )
        ..state = AgentRunState.failed;
      await tester.pump();
      return facade;
    }

    testWidgets('H1 未登录时显示登录引导，不显示错误', (tester) async {
      final store = MemoryAgentSessionStore();
      final runtime = runtimeFor(store, loginRequired: true);

      await tester.pumpWidget(
        host(auth: AuthStore(), runtime: runtime),
      );
      await settle(tester);

      expect(find.byType(LoginGuideCard), findsOneWidget);
      expect(find.byKey(const ValueKey('login-guide-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-error')), findsNothing);
      expect(find.byType(ComposerCard), findsNothing);
      expect(runtime.openedSessions, isEmpty);
    });

    testWidgets('H2 503 未配置的文案正确', (tester) async {
      await failedPane(
        tester,
        kind: AgentErrorKind.notConfigured,
        statusCode: 503,
      );
      expect(find.text('AI 服务暂未开通（服务端未配置），请联系管理员'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('H3 429 的文案正确', (tester) async {
      await failedPane(
        tester,
        kind: AgentErrorKind.rateLimited,
        statusCode: 429,
      );
      expect(find.text('请求太频繁，已自动重试仍失败，请稍后再试'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('H4 断网的文案正确', (tester) async {
      await failedPane(tester, kind: AgentErrorKind.offline);
      expect(find.text('网络不可用，检查网络后重试'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('H5 每个错误都有「重试」，详情可展开', (tester) async {
      for (final entry in const {
        AgentErrorKind.loginExpired: '登录已过期，请重新登录',
        AgentErrorKind.rateLimited: '请求太频繁，已自动重试仍失败，请稍后再试',
        AgentErrorKind.notConfigured: 'AI 服务暂未开通（服务端未配置），请联系管理员',
        AgentErrorKind.offline: '网络不可用，检查网络后重试',
        AgentErrorKind.timeout: '上游响应超时，重试一次',
      }.entries) {
        final facade = await failedPane(
          tester,
          kind: entry.key,
          statusCode: 503,
          detail: '上游返回的原文',
        );
        expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
        expect(find.byKey(const ValueKey('chat-retry')), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);

        // 详情折叠区显示状态码和原文。
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();
        expect(find.text('状态码：503'), findsOneWidget);
        expect(find.text('上游返回的原文'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('chat-retry')));
        await tester.pump();
        expect(facade.retryCount, 1);

        await unmount(tester);
      }
    });

    testWidgets('未知分类回退到 facade 的原文', (tester) async {
      await failedPane(
        tester,
        kind: AgentErrorKind.unknown,
        lastError: '这一轮被中断了',
      );
      expect(find.text('这一轮被中断了'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-retry')), findsOneWidget);
      await unmount(tester);
    });
  });

  group('对话流性能与分页', () {
    testWidgets('只有 hasEarlier 为真时才显示「载入更早的消息」', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed(const [
          AgentMessageView(id: 'm0', role: 'user', text: '最后一条'),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('chat-load-earlier')), findsNothing);

      facade.seedEarlier(const [
        AgentMessageView(id: 'e0', role: 'assistant', text: '更早的一条'),
      ]);
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-load-earlier')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-load-earlier')));
      await tester.pump();
      expect(facade.loadEarlierCount, 1);
      expect(find.text('更早的一条'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-load-earlier')), findsNothing);

      await unmount(tester);
    });

    testWidgets('对话流用 ListView.builder，长对话只建可见条目', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = runtimeFor(store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          for (var index = 0; index < 200; index++)
            AgentMessageView(
              id: 'm$index',
              role: index.isEven ? 'user' : 'assistant',
              text: '第 $index 条消息',
            ),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        host(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      expect(find.byType(ListView), findsOneWidget);
      final built = tester.widgetList(find.byType(ChatMessageTile)).length;
      expect(built, lessThan(200));
      // 末尾一条在可视区内。
      expect(find.text('第 199 条消息'), findsOneWidget);

      await unmount(tester);
    });
  });
}
