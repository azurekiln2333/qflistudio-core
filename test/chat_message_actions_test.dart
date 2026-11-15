import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/shell/login_gate.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 消息动作：复制、编辑后重发、直接重发，以及编辑时草稿的处理。
void main() {
  AgentMessageView message({
    required String id,
    required String role,
    String text = '',
    String? sourceText,
    List<String> attachedPaths = const [],
    bool pending = false,
  }) => AgentMessageView(
    id: id,
    role: role,
    text: text,
    sourceText: sourceText,
    attachedPaths: attachedPaths,
    pending: pending,
  );

  /// 对话流自己的滚动位置。
  ScrollPosition positionOf(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!
      .position;

  Widget host(Widget child, {double textScale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  );

  /// 用假的平台通道接管剪贴板。
  List<String> mockClipboard() {
    final written = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            written.add(args['text'] as String? ?? '');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return written;
  }

  group('AgentUserMessage 用类型化元数据，不从展示文本反推', () {
    test('attachment-only actions preserve an explicitly empty source', () {
      final view = message(
        id: 'm0',
        role: 'user',
        text: 'Attached files: notes.txt',
        sourceText: '',
        attachedPaths: ['notes.txt'],
      );
      final parsed = AgentUserMessage.of(view);
      expect(parsed.text, '');
      expect(parsed.attachedPaths, ['notes.txt']);
    });

    test('优先用 sourceText，附件来自 attachedPaths', () {
      final view = message(
        id: 'm0',
        role: 'user',
        text: '看一下 @src/Main.java',
        sourceText: '看一下',
        attachedPaths: ['src/Main.java'],
      );
      final parsed = AgentUserMessage.of(view);
      expect(parsed.text, '看一下');
      expect(parsed.attachedPaths, ['src/Main.java']);
    });

    test('旧消息没有元数据时正文保持原样，附件为空', () {
      const composed = '看一下\n\n附带的文件：\n- src/Main.java';
      final view = message(id: 'm0', role: 'user', text: composed);
      final parsed = AgentUserMessage.of(view);
      // 不切分、不猜路径：整段原文就是正文。
      expect(parsed.text, composed);
      expect(parsed.attachedPaths, isEmpty);
    });
  });

  group('消息动作菜单', () {
    testWidgets('用户消息能复制原文', (tester) async {
      final written = mockClipboard();
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [message(id: 'm0', role: 'user', text: '把输出改成大写')],
            state: AgentRunState.idle,
            onEdit: (_, _) {},
            onResend: (_, _) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-m0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(written, ['把输出改成大写']);
    });

    testWidgets('助手消息也能复制', (tester) async {
      final written = mockClipboard();
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [message(id: 'm1', role: 'assistant', text: '已经改好了。')],
            state: AgentRunState.idle,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(written, ['已经改好了。']);
    });

    testWidgets('助手消息不提供编辑与重发', (tester) async {
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [message(id: 'm1', role: 'assistant', text: '已经改好了。')],
            state: AgentRunState.idle,
            onEdit: (_, _) {},
            onResend: (_, _) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-m1')));
      await tester.pumpAndSettle();

      expect(find.text('复制'), findsOneWidget);
      expect(find.text('编辑后重发'), findsNothing);
      expect(find.text('重发'), findsNothing);
    });

    testWidgets('还在发送中的回声消息不给编辑与重发', (tester) async {
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [
              message(id: 'e0', role: 'user', text: '刚发出去的', pending: true),
            ],
            state: AgentRunState.running,
            onEdit: (_, _) {},
            onResend: (_, _) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-e0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('编辑后重发'), findsNothing);
      expect(find.text('重发'), findsNothing);
    });

    testWidgets('编辑菜单是「编辑后重发」，带原文和真实附件路径', (tester) async {
      AgentUserMessage? edited;
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [
              message(
                id: 'm0',
                role: 'user',
                text: '改一下 @src/Main.java',
                sourceText: '改一下',
                attachedPaths: ['src/Main.java'],
              ),
            ],
            state: AgentRunState.idle,
            onEdit: (value, _) => edited = value,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-m0')));
      await tester.pumpAndSettle();
      expect(find.text('编辑后重发'), findsOneWidget);
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();

      expect(edited!.text, '改一下');
      expect(edited!.attachedPaths, ['src/Main.java']);
    });

    testWidgets('重发把原文和附件交给调用方', (tester) async {
      AgentUserMessage? resent;
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [
              message(
                id: 'm0',
                role: 'user',
                text: '改一下 @src/Main.java',
                sourceText: '改一下',
                attachedPaths: ['src/Main.java'],
              ),
            ],
            state: AgentRunState.idle,
            onResend: (value, _) => resent = value,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-m0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重发'));
      await tester.pumpAndSettle();

      expect(resent!.text, '改一下');
      expect(resent!.attachedPaths, ['src/Main.java']);
    });

    testWidgets('运行中编辑和重发都不可点，并说明原因', (tester) async {
      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [message(id: 'm0', role: 'user', text: '跑一下')],
            state: AgentRunState.running,
            busy: true,
            onEdit: (_, _) {},
            onResend: (_, _) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-actions-m0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final edit = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('编辑后重发'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      final resend = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('重发'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(edit.enabled, isFalse);
      expect(resend.enabled, isFalse);
      expect(find.text('等这一轮结束后可用'), findsOneWidget);
    });

    testWidgets('动作可用性变化时条目会重建，不用旧回调', (tester) async {
      var edits = 0;
      Widget build({required bool busy}) => host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'user', text: '跑一下')],
          state: busy ? AgentRunState.running : AgentRunState.idle,
          busy: busy,
          onEdit: (_, _) => edits++,
        ),
      );

      await tester.pumpWidget(build(busy: true));
      await tester.pumpWidget(build(busy: false));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat-actions-m0')));
      await tester.pumpAndSettle();
      final edit = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('编辑后重发'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(edit.enabled, isTrue);
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();
      expect(edits, 1);
    });

    testWidgets('原文与附件更新后，编辑用的是新元数据', (tester) async {
      final edits = <AgentUserMessage>[];
      Widget build({required String source, required List<String> paths}) =>
          host(
            ChatTranscript(
              messages: [
                message(
                  id: 'm0',
                  role: 'user',
                  text: '展示文本',
                  sourceText: source,
                  attachedPaths: paths,
                ),
              ],
              state: AgentRunState.idle,
              onEdit: (value, _) => edits.add(value),
            ),
          );

      await tester.pumpWidget(build(source: '第一版', paths: const ['a.dart']));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(source: '第二版', paths: const ['b.dart']));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat-actions-m0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();

      expect(edits.single.text, '第二版');
      expect(edits.single.attachedPaths, ['b.dart']);
    });
  });

  group('会话切换与滚动', () {
    testWidgets('换会话后回到最新一条，不沿用旧会话的滚动位置', (tester) async {
      List<AgentMessageView> many(String prefix) => [
        for (var index = 0; index < 30; index++)
          message(id: '$prefix-$index', role: 'assistant', text: '内容 $index'),
      ];
      Widget build(String key) => host(
        ChatTranscript(
          messages: many(key),
          state: AgentRunState.idle,
          sessionKey: key,
        ),
      );

      await tester.pumpWidget(build('a'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build('b'));
      await tester.pumpAndSettle();

      final position = positionOf(tester);
      expect(
        position.maxScrollExtent - position.pixels,
        lessThan(40),
        reason: '新会话应停在最新一条',
      );
    });

    testWidgets('用户往回翻看历史时，新消息不抢走滚动位置', (tester) async {
      final messages = [
        for (var index = 0; index < 40; index++)
          message(id: 'm$index', role: 'assistant', text: '内容 $index'),
      ];
      await tester.pumpWidget(
        host(ChatTranscript(messages: messages, state: AgentRunState.idle)),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      final before = positionOf(tester).pixels;

      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [
              ...messages,
              message(id: 'm40', role: 'assistant', text: '新消息'),
            ],
            state: AgentRunState.idle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(positionOf(tester).pixels, closeTo(before, 1));
    });

    testWidgets('贴着底部时新消息仍然自动跟到底部', (tester) async {
      final messages = [
        for (var index = 0; index < 40; index++)
          message(id: 'm$index', role: 'assistant', text: '内容 $index'),
      ];
      await tester.pumpWidget(
        host(ChatTranscript(messages: messages, state: AgentRunState.idle)),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        host(
          ChatTranscript(
            messages: [
              ...messages,
              message(id: 'm40', role: 'assistant', text: '新消息'),
            ],
            state: AgentRunState.idle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final position = positionOf(tester);
      expect(
        position.maxScrollExtent - position.pixels,
        lessThan(40),
        reason: '贴着底部时应跟随新消息',
      );
    });
  });

  group('面板：编辑与重发', () {
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

    Project project() => Project(
      id: 'p1',
      name: 'Demo',
      path: 'demo',
      createdAt: DateTime(2026, 1, 1),
      lastOpenedAt: DateTime(2026, 1, 1),
    );

    Widget paneHost({
      required AuthStore auth,
      required FakeAgentRuntime runtime,
      String? sessionId,
    }) => MaterialApp(
      home: LoginGateScope(
        auth: auth,
        child: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(420, 800)),
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

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    String inputText(WidgetTester tester) {
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('composer-input')),
      );
      return field.controller?.text ?? '';
    }

    testWidgets('编辑空卡片：把原文和附件放进输入卡片，不自动发送', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(
            id: 'u0',
            role: 'user',
            text: '改一下 @src/Main.java',
            sourceText: '改一下',
            attachedPaths: ['src/Main.java'],
          ),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();

      expect(inputText(tester), '改一下');
      expect(facade.sentTexts, isEmpty);
      expect(find.text('改一下 @src/Main.java'), findsOneWidget);
    });

    testWidgets('编辑时卡片有内容：先确认，取消则草稿原样保留', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(id: 'u0', role: 'user', text: '旧的这句话', sourceText: '旧的这句话'),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '我还没发的内容',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-replace-draft')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('composer-replace-cancel')));
      await tester.pumpAndSettle();

      expect(inputText(tester), '我还没发的内容');
    });

    testWidgets('编辑时卡片有内容：确认后替换为历史原文，旧附件不残留', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(
            id: 'u0',
            role: 'user',
            text: '旧的这句话',
            sourceText: '旧的这句话',
            attachedPaths: ['keep.dart'],
          ),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      // 卡片里先放一份带附件的草稿。
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '我还没发的内容',
      );
      await tester.pump();
      final composer = tester.state<State<WorkbenchAgentPane>>(
        find.byType(WorkbenchAgentPane),
      );
      expect(composer, isNotNull);

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-replace-confirm')));
      await tester.pumpAndSettle();

      expect(inputText(tester), '旧的这句话');
      expect(facade.sentTexts, isEmpty);
    });

    testWidgets('直接重发走发送管线，保留卡片里未发出的草稿', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(
            id: 'u0',
            role: 'user',
            text: '重新跑一遍',
            sourceText: '重新跑一遍',
            attachedPaths: ['src/Main.java'],
          ),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '草稿别丢',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重发'));
      await tester.pumpAndSettle();

      expect(facade.sentTexts, ['重新跑一遍']);
      expect(facade.sentAttachments.single, ['src/Main.java']);
      expect(inputText(tester), '草稿别丢');
    });

    testWidgets('这一轮还在跑时，编辑与重发都不给动作', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..sendGate = Completer<void>()
        ..seed([
          message(id: 'u0', role: 'user', text: '旧的这句话', sourceText: '旧的这句话'),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      // 发一条把这一轮占住。
      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '先占住这一轮',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final edit = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('编辑后重发'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(edit.enabled, isFalse);

      facade.sendGate!.complete();
      facade.sendGate = null;
      await tester.pumpAndSettle();
    });

    testWidgets('发送成功后卡片清空，编辑进来的原文不被塞回去', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(id: 'u0', role: 'user', text: '改一下', sourceText: '改一下'),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      // 编辑把原文放进卡片，然后用户自己点发送。
      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();
      expect(inputText(tester), '改一下');

      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pumpAndSettle();

      expect(facade.sentTexts, ['改一下']);
      // 发完就清空，不把刚发出去的内容留在卡片里。
      expect(inputText(tester), '');
    });

    testWidgets('编辑时带历史附件，发送后附件按历史的那一份带出去', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(
            id: 'u0',
            role: 'user',
            text: '改一下 @src/Main.java',
            sourceText: '改一下',
            attachedPaths: ['src/Main.java'],
          ),
        ]);
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑后重发'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pumpAndSettle();

      expect(facade.sentTexts, ['改一下']);
      expect(facade.sentAttachments.single, ['src/Main.java']);
    });

    testWidgets('重发失败时草稿与附件都原样留着', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(
            id: 'u0',
            role: 'user',
            text: '重新跑一遍',
            sourceText: '重新跑一遍',
            attachedPaths: ['src/Main.java'],
          ),
        ]);
      // 让这一发送失败：登录态在发送时失效。
      facade.throwLoginRequired = true;
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '草稿别丢',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重发'));
      await tester.pumpAndSettle();

      // 重发没有借用草稿，失败也不许把重发的正文塞回卡片。
      expect(inputText(tester), '草稿别丢');
    });

    testWidgets('重发途中换会话：发送留在原会话，新会话的界面和草稿都不动', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final first = await store.create('p1');
      final second = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);

      final facadeA = FakeAgentFacade(sessionId: first.id)
        ..sendGate = Completer<void>()
        ..seed([
          message(id: 'u0', role: 'user', text: '重新跑一遍', sourceText: '重新跑一遍'),
        ]);
      final facadeB = FakeAgentFacade(sessionId: second.id)
        ..seed([
          message(id: 'b0', role: 'user', text: 'B 会话的话'),
          message(id: 'b1', role: 'assistant', text: 'B 会话的回复'),
        ]);
      runtime.facades[first.id] = facadeA;
      runtime.facades[second.id] = facadeB;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: first.id),
      );
      await settle(tester);

      // 在 A 里点重发，卡在发送闸门上。
      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重发'));
      await tester.pump();
      await tester.pump();
      expect(facadeA.sentTexts, ['重新跑一遍']);

      // 还没发完就换到 B。
      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: second.id),
      );
      await settle(tester);
      expect(find.text('B 会话的回复'), findsOneWidget);

      // 让 A 的那次发送落地。
      facadeA.sendGate!.complete();
      facadeA.sendGate = null;
      await tester.pumpAndSettle();

      // 发送确实发生在 A，而且只发生一次。
      expect(facadeA.sentTexts, ['重新跑一遍']);
      expect(facadeB.sentTexts, isEmpty);
      // B 的界面没被 A 的回声或发送态污染。
      expect(find.text('B 会话的回复'), findsOneWidget);
      expect(find.text('重新跑一遍'), findsNothing);
    });

    testWidgets('打开途中换会话：新会话的界面不被旧门面顶掉', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final target = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);

      final facadeB = FakeAgentFacade(sessionId: target.id)
        ..seed([message(id: 'b0', role: 'assistant', text: 'B 会话的回复')]);
      runtime.facades[target.id] = facadeB;

      // 空会话里发一条：会先建会话，再 open；open 卡住制造竞态。
      var created = '';
      runtime.sessions.addListener(() {});
      final blocker = Completer<void>();
      runtime.openBlockers['session-0'] = blocker;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: null),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '开一个新会话',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      await tester.pump();

      // create 已完成，open 还卡着；这时切到 B。
      created = runtime.sessions.sessionsOf('p1').first.id;
      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: target.id),
      );
      await settle(tester);
      expect(find.text('B 会话的回复'), findsOneWidget);

      // 放行旧会话的 open：它必须留在后台，不能把 B 的界面换掉。
      blocker.complete();
      await tester.pumpAndSettle();

      expect(find.text('B 会话的回复'), findsOneWidget);
      expect(created, isNotEmpty);
    });

    testWidgets('重发同一条消息不会连点两次都发出去', (tester) async {
      final auth = await loggedIn();
      final store = MemoryAgentSessionStore();
      final meta = await store.create('p1');
      final runtime = FakeAgentRuntime(sessions: store);
      final facade = FakeAgentFacade(sessionId: meta.id)
        ..seed([
          message(id: 'u0', role: 'user', text: '重新跑一遍', sourceText: '重新跑一遍'),
        ]);
      facade.sendGate = Completer<void>();
      runtime.facades[meta.id] = facade;

      await tester.pumpWidget(
        paneHost(auth: auth, runtime: runtime, sessionId: meta.id),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('composer-input')),
        '草稿别丢',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-actions-u0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重发'));
      await tester.pump();
      await tester.pump();

      expect(facade.sentTexts, ['重新跑一遍']);

      facade.sendGate!.complete();
      facade.sendGate = null;
      await tester.pumpAndSettle();
      expect(facade.sentTexts, ['重新跑一遍']);
      expect(inputText(tester), '草稿别丢');
    });
  });
}
