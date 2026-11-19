import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  late Directory root;
  late Directory project;
  late FileAgentSessionStore store;

  setUp(() async {
    StudioProfile.current = null;
    root = Directory.systemTemp.createTempSync('agent-live-text-');
    project = Directory(p.join(root.path, 'proj'))..createSync(recursive: true);
    store = FileAgentSessionStore(
      root: Directory(p.join(root.path, 'sessions')),
    );
    await store.load();
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 上偶发占用，临时目录可以留着。
    }
  });

  Future<void> waitFor(
    bool Function() condition, {
    String reason = '条件未满足',
  }) async {
    for (var index = 0; index < 600; index++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail(reason);
  }

  test('思考消息映射成 reasoning 视图，实时文本只在流式中可读', () async {
    final api = _ScriptedApi();
    final meta = await store.create('p1');
    final facade = VibeAgentFacade(
      api: api,
      tokenProvider: () => 'local-token',
      store: store,
      meta: meta,
      projectRoot: project.path,
      projectName: 'demo',
      language: 'python',
    );
    var notifications = 0;
    facade.addListener(() => notifications++);

    await facade.send('想一想', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => api.turns.isNotEmpty, reason: '没有发起请求');
    final turn = api.turns.first;

    turn.add(const AiReasoningDelta('第一段'));
    await waitFor(
      () => facade.messages.any((view) => view.role == 'reasoning'),
    );

    final view = facade.messages.firstWhere((view) => view.role == 'reasoning');
    expect(view.pending, isTrue);
    final live = facade.liveTextOf(view.id);
    expect(live, isNotNull);

    // 增量期间门面不通知：界面只重绘这一条消息。
    notifications = 0;
    turn.add(const AiReasoningDelta('第二段'));
    await waitFor(() => live!.value == '第一段第二段', reason: '实时文本没有增长');
    expect(notifications, 0);

    turn.add(const AiContentDelta('答案'));
    await waitFor(
      () => facade.messages.any((view) => view.role == 'assistant'),
    );
    expect(facade.liveTextOf(view.id), isNull);

    final closed = facade.messages.firstWhere(
      (view) => view.role == 'reasoning',
    );
    expect(closed.pending, isFalse);
    expect(closed.durationMs, isNotNull);

    turn.add(
      AiTurnCompleted(
        AiChatResult(
          model: 'demo',
          content: '答案',
          reasoning: '第一段第二段',
          rawMessage: {
            'role': 'assistant',
            'content': '答案',
            'reasoning_content': '第一段第二段',
          },
        ),
      ),
    );
    await turn.close();
    await waitFor(() => facade.state == AgentRunState.idle);
    await facade.flush();

    final assistant = facade.messages.firstWhere(
      (view) => view.role == 'assistant',
    );
    expect(assistant.text, '答案');
    expect(notifications, greaterThan(0));
    facade.dispose();
  });

  test('恢复会话后思考消息不 pending 并带用时', () async {
    final api = _ScriptedApi();
    final meta = await store.create('p1');
    final facade = VibeAgentFacade(
      api: api,
      tokenProvider: () => 'local-token',
      store: store,
      meta: meta,
      projectRoot: project.path,
      projectName: 'demo',
      language: 'python',
      restoredMessages: [
        {
          'id': 'm0',
          'role': 'reasoning',
          'text': '想过很久',
          'pending': false,
          'aiGenerated': true,
          'durationMs': 18000,
        },
        {
          'id': 'm1',
          'role': 'assistant',
          'text': '答案',
          'pending': false,
          'aiGenerated': true,
        },
      ],
    );

    final reasoning = facade.messages.first;
    expect(reasoning.role, 'reasoning');
    expect(reasoning.pending, isFalse);
    expect(reasoning.durationMs, 18000);
    expect(reasoning.aiGenerated, isTrue);
    expect(facade.liveTextOf(reasoning.id), isNull);
    facade.dispose();
  });
}

/// 可脚本化的 ApiClient：每次请求给测试一个事件流控制器。
class _ScriptedApi extends ApiClient {
  _ScriptedApi() : super(transport: _emptyTransport);

  static final http.Client _emptyTransport = MockClient(
    (request) async => http.Response('{}', 200),
  );

  final List<StreamController<AiTurnEvent>> turns = [];

  @override
  Stream<AiTurnEvent> aiChatStream({
    required String token,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    AiEndpoint? endpoint,
    String? model,
    String? reasoningEffort,
  }) {
    final controller = StreamController<AiTurnEvent>();
    turns.add(controller);
    return controller.stream;
  }
}
