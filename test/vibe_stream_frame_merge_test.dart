import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

/// 增量按帧合并：一帧最多写一次实时文本，期间不通知控制器监听者。
///
/// 这个文件只有 widget 测试：装了绑定之后，控制器的实时文本走帧回调，
/// 纯 `test()` 用例会因为没人推进帧而永远读不到新文本。
void main() {
  testWidgets('同一帧里的多个增量只写一次实时文本', (tester) async {
    StudioProfile.current = null;
    final api = _ScriptedApi();
    final controller = VibeCodingController(
      api: api,
      tokenProvider: () => 'local-token',
      // 目录不存在：本轮不碰磁盘，全部走微任务。
      projectRoot: 'memory://no-such-project',
      projectName: 'demo',
      language: 'python',
      context: _StubContext(),
    );
    var controlNotices = 0;
    controller.addListener(() => controlNotices++);

    controller.send('想一想');
    await tester.pump();
    expect(api.turns, hasLength(1));
    final turn = api.turns.first;

    turn.add(const AiReasoningDelta('一'));
    await tester.pump();
    final live = controller.liveText(1);
    expect(live, isNotNull);
    expect(live!.value, '一');

    var liveNotices = 0;
    live.addListener(() => liveNotices++);
    controlNotices = 0;

    turn.add(const AiReasoningDelta('二'));
    turn.add(const AiReasoningDelta('三'));
    await tester.pump();
    await tester.pump();

    // 两个增量合并成一次写入，期间控制器不通知。
    expect(live.value, '一二三');
    expect(liveNotices, 1);
    expect(controlNotices, 0);

    turn.add(
      AiTurnCompleted(
        AiChatResult(
          model: 'demo',
          content: '好了',
          reasoning: '一二三',
          rawMessage: {
            'role': 'assistant',
            'content': '好了',
            'reasoning_content': '一二三',
          },
        ),
      ),
    );
    await turn.close();
    for (
      var index = 0;
      index < 20 && controller.phase == VibePhase.running;
      index++
    ) {
      await tester.pump();
    }
    expect(controller.phase, VibePhase.succeeded);
    expect(controller.messages[1].text, '一二三');
    expect(controller.liveText(1), isNull);
    controller.dispose();
  });
}

class _StubContext implements VibeAgentContext {
  @override
  Future<List<VibeSkill>> skills() async => const [];

  @override
  Future<String> rules() async => '';
}

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
