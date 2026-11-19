import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/agent_request_scheduler.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

void main() {
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
  });

  VibeCodingController build(
    _ScriptedApi api, {
    List<Map<String, dynamic>>? restoredHistory,
    AgentRequestScheduler? scheduler,
    String schedulerKey = 'session-a',
    String projectRoot = 'memory://no-such-project',
  }) {
    final controller = VibeCodingController(
      api: api,
      tokenProvider: () => 'local-token',
      projectRoot: projectRoot,
      projectName: 'demo',
      language: 'python',
      maxRounds: 4,
      context: _StubContext(),
      restoredHistory: restoredHistory,
    );
    controller.requestScheduler = scheduler;
    controller.schedulerKey = schedulerKey;
    return controller;
  }

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

  Future<void> settle(VibeCodingController controller) async {
    await waitFor(
      () =>
          controller.phase != VibePhase.running &&
          controller.phase != VibePhase.cancelling,
      reason: '回合没有结束：${controller.phase} ${controller.lastError}',
    );
  }

  test('思考增量新建一条思考消息，正文开始时收尾', () async {
    final api = _ScriptedApi();
    final controller = build(api);

    controller.send('想一想再回答');
    await waitFor(() => api.turns.isNotEmpty, reason: '没有发起请求');

    final turn = api.turns.first;
    turn.add(const AiReasoningDelta('先看'));
    await waitFor(() => controller.messages.length == 2);
    final streaming = controller.messages.last;
    expect(streaming.kind, VibeMessageKind.reasoning);
    expect(streaming.pending, isTrue);
    expect(streaming.aiGenerated, isTrue);
    expect(streaming.durationMs, isNull);

    turn.add(const AiReasoningDelta('目录'));
    await waitFor(
      () => controller.liveText(1)?.value == '先看目录',
      reason: '实时文本没有增长',
    );

    turn.add(const AiContentDelta('答案'));
    await waitFor(() => controller.messages.length == 3);
    final reasoning = controller.messages[1];
    expect(reasoning.pending, isFalse);
    expect(reasoning.durationMs, isNotNull);
    expect(reasoning.text, '先看目录');
    expect(controller.messages[2].pending, isTrue);

    turn.add(completed('先看目录', '答案'));
    await turn.close();
    await settle(controller);

    expect(controller.phase, VibePhase.succeeded);
    expect(controller.messages[1].text, '先看目录');
    expect(controller.messages[1].pending, isFalse);
    expect(controller.messages[2].text, '答案');
    expect(controller.messages[2].pending, isFalse);
    // 回合结束后不再有实时文本。
    expect(controller.liveText(1), isNull);
    expect(controller.liveText(2), isNull);
  });

  test('工具调用开始时思考气泡收尾', () async {
    final api = _ScriptedApi();
    final controller = build(api);

    controller.send('读文件');
    await waitFor(() => api.turns.isNotEmpty);
    final turn = api.turns.first;
    turn.add(const AiReasoningDelta('要读文件'));
    await waitFor(() => controller.messages.length == 2);

    turn.add(const AiToolCallStarted(index: 0, name: 'read_file'));
    await waitFor(() => !controller.messages[1].pending);
    expect(controller.messages[1].kind, VibeMessageKind.reasoning);
    expect(controller.messages[1].durationMs, isNotNull);

    turn.add(completed('要读文件', '好了'));
    await turn.close();
    await settle(controller);
    expect(controller.phase, VibePhase.succeeded);
  });

  test('完成时用权威结果校准思考与正文', () async {
    final api = _ScriptedApi();
    final controller = build(api);

    controller.send('想一想');
    await waitFor(() => api.turns.isNotEmpty);
    final turn = api.turns.first;
    turn.add(const AiReasoningDelta('半句'));
    turn.add(const AiContentDelta('草稿'));
    await waitFor(() => controller.messages.length == 3);

    turn.add(completed('完整的思考', '成稿'));
    await turn.close();
    await settle(controller);

    expect(controller.messages[1].text, '完整的思考');
    expect(controller.messages[2].text, '成稿');
  });

  test('取消保留已显示的思考和正文，不写历史', () async {
    final api = _ScriptedApi();
    final controller = build(api);

    controller.send('想一想');
    await waitFor(() => api.turns.isNotEmpty);
    final turn = api.turns.first;
    turn.add(const AiReasoningDelta('正在思考'));
    await waitFor(() => controller.messages.length == 2);
    final before = controller.history.length;

    final cancelled = controller.cancel();
    await turn.close();
    await cancelled;

    expect(controller.phase, VibePhase.cancelled);
    expect(controller.messages[1].text, '正在思考');
    expect(controller.messages[1].pending, isFalse);
    // 取消的回合不写入模型历史。
    expect(controller.history.length, before);
    expect(
      controller.history.where((entry) => entry['role'] == 'assistant'),
      isEmpty,
    );
  });

  test('流中途失败保留已显示内容', () async {
    final api = _ScriptedApi();
    final controller = build(api);

    controller.send('想一想');
    await waitFor(() => api.turns.isNotEmpty);
    final turn = api.turns.first;
    turn.add(const AiReasoningDelta('先说一句'));
    await waitFor(() => controller.messages.length == 2);

    turn.addError(ApiException('上游断开', statusCode: 502));
    await turn.close();
    await settle(controller);

    expect(controller.phase, VibePhase.failed);
    expect(controller.lastError, '上游断开');
    expect(controller.messages[1].text, '先说一句');
    expect(controller.messages[1].pending, isFalse);
  });

  test('历史带上 reasoning_content 和 reasoning_blocks', () async {
    final api = _ScriptedApi();
    final controller = build(api);

    controller.send('想一想');
    await waitFor(() => api.turns.isNotEmpty);
    final turn = api.turns.first;
    turn.add(
      AiTurnCompleted(
        AiChatResult(
          model: 'demo',
          content: '答案',
          reasoning: '想过',
          rawMessage: {
            'role': 'assistant',
            'content': '答案',
            'reasoning_content': '想过',
            'reasoning_blocks': [
              {
                'type': 'thinking',
                'thinking': '想过',
                'signature': 'sig-1',
                'unexpected': '丢掉',
              },
              {'type': 'redacted_thinking', 'data': 'blob'},
            ],
          },
        ),
      ),
    );
    await turn.close();
    await settle(controller);

    final assistant = controller.history.last;
    expect(assistant['role'], 'assistant');
    expect(assistant['reasoning_content'], '想过');
    final blocks = assistant['reasoning_blocks'] as List;
    expect(blocks, hasLength(2));
    expect((blocks.first as Map)['signature'], 'sig-1');
    expect((blocks.first as Map).containsKey('unexpected'), isFalse);
    expect((blocks.last as Map)['data'], 'blob');
  });

  test('恢复历史时清洗保留思考字段', () async {
    final api = _ScriptedApi();
    final controller = build(
      api,
      restoredHistory: [
        {'role': 'user', 'content': '第一轮'},
        {
          'role': 'assistant',
          'content': '第一轮回复',
          'reasoning_content': '想到过',
          'reasoning_blocks': [
            {'type': 'thinking', 'thinking': '想到过', 'secret': '丢掉'},
            {'type': '', 'thinking': '没有类型'},
            'not-a-map',
          ],
        },
        {
          'role': 'assistant',
          'content': '第二轮回复',
          'tool_calls': [
            {
              'id': 'call-1',
              'type': 'function',
              'function': {'name': 'read_file', 'arguments': '{}'},
            },
          ],
          // 类型不对的字段整条丢掉。
          'reasoning_content': 42,
          'reasoning_blocks': 'not-a-list',
        },
        {'role': 'tool', 'tool_call_id': 'call-1', 'content': '读好了'},
      ],
    );

    // `_sanitizeHistory` 从尾部丢掉没答完的一组，所以取倒数两条。
    final first = controller.history[controller.history.length - 2];
    final second = controller.history.last;
    expect(first['reasoning_content'], '想到过');
    final blocks = first['reasoning_blocks'] as List;
    expect(blocks, hasLength(1));
    expect((blocks.single as Map).keys.toSet(), {'type', 'thinking'});
    expect(second.containsKey('reasoning_content'), isFalse);
    expect(second.containsKey('reasoning_blocks'), isFalse);
  });

  test('历史序列化超过 448 KiB 时从最旧的轮次开始丢', () async {
    final api = _ScriptedApi();
    final filler = 'x' * 20 * 1024;
    final restored = <Map<String, dynamic>>[];
    for (var index = 0; index < 30; index++) {
      restored
        ..add({'role': 'user', 'content': '问题 $index'})
        ..add({
          'role': 'assistant',
          'content': '回复 $index',
          'reasoning_content': filler,
        });
    }
    final controller = build(api, restoredHistory: restored);
    expect(controller.history.length, greaterThan(20));

    controller.send('继续');
    await waitFor(() => api.turns.isNotEmpty);

    final bytes = utf8.encode(jsonEncode(controller.history)).length;
    expect(bytes, lessThanOrEqualTo(448 * 1024));
    // 系统提示永远保留，裁剪起点不是 tool 条目。
    expect(controller.history.first['role'], 'system');
    expect(controller.history[1]['role'], isNot('tool'));
    // 最新的轮次还在。
    expect(controller.history.last['content'], '继续');

    final turn = api.turns.first;
    await turn.close();
    await settle(controller);
    expect(controller.phase, VibePhase.failed);
  });

  test('调度名额覆盖整个流的消费过程', () async {
    final api = _ScriptedApi();
    final scheduler = AgentRequestScheduler(maxConcurrent: 1);
    final first = build(api, scheduler: scheduler, schedulerKey: 'a');

    first.send('第一个会话');
    await waitFor(() => api.turns.isNotEmpty);
    expect(scheduler.activeCount, 1);

    final second = build(api, scheduler: scheduler, schedulerKey: 'b');
    second.send('第二个会话');
    await waitFor(() => scheduler.isWaiting('b'), reason: '第二个会话没有排队');

    // 流还没结束，名额必须一直占着。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(scheduler.activeCount, 1);
    expect(api.turns, hasLength(1));

    final turn = api.turns.first;
    turn.add(completed('想', '好'));
    await turn.close();
    await settle(first);

    await waitFor(() => api.turns.length == 2, reason: '排队没有继续');
    expect(scheduler.activeCount, 1);

    final next = api.turns[1];
    next.add(completed('', '好'));
    await next.close();
    await settle(second);
    expect(scheduler.activeCount, 0);
  });

  test('429 在发出增量前照旧重试', () async {
    final api = _ScriptedApi();
    final scheduler = AgentRequestScheduler(retryDelays: const [Duration.zero]);
    final controller = build(api, scheduler: scheduler);

    controller.send('重试一次');
    await waitFor(() => api.turns.isNotEmpty);
    final first = api.turns.first;
    first.addError(ApiException('太频繁', statusCode: 429));
    await first.close();

    await waitFor(() => api.turns.length == 2, reason: '没有重试');
    final retry = api.turns[1];
    retry.add(completed('', '好了'));
    await retry.close();
    await settle(controller);
    expect(controller.phase, VibePhase.succeeded);
  });

  test('已经发出增量的回合不重试', () async {
    final api = _ScriptedApi();
    final scheduler = AgentRequestScheduler(retryDelays: const [Duration.zero]);
    final controller = build(api, scheduler: scheduler);

    controller.send('重试一次');
    await waitFor(() => api.turns.isNotEmpty);
    final turn = api.turns.first;
    turn.add(const AiReasoningDelta('想了一半'));
    await waitFor(() => controller.messages.length == 2);
    turn.addError(ApiException('太频繁', statusCode: 429));
    await turn.close();
    await settle(controller);

    expect(api.turns, hasLength(1));
    expect(controller.phase, VibePhase.failed);
    // 已经显示的内容不能重来一遍。
    expect(controller.messages[1].text, '想了一半');
  });
}

/// 只发空结果的上下文，测试不碰磁盘。
class _StubContext implements VibeAgentContext {
  @override
  Future<List<VibeSkill>> skills() async => const [];

  @override
  Future<String> rules() async => '';
}

/// 一回合结束：思考文本 + 正文。
AiTurnCompleted completed(String reasoning, String content) => AiTurnCompleted(
  AiChatResult(
    model: 'demo',
    content: content,
    reasoning: reasoning,
    rawMessage: {
      'role': 'assistant',
      'content': content,
      if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
    },
  ),
);

/// 可脚本化的 ApiClient：每次请求给测试一个事件流控制器。
class _ScriptedApi extends ApiClient {
  _ScriptedApi() : super(transport: _emptyTransport);

  static final http.Client _emptyTransport = MockClient(
    (request) async => http.Response('{}', 200),
  );

  final List<StreamController<AiTurnEvent>> turns = [];
  final List<List<Map<String, dynamic>>> requests = [];

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
    requests.add(messages);
    final controller = StreamController<AiTurnEvent>();
    turns.add(controller);
    return controller.stream;
  }
}
