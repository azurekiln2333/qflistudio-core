import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/trellis/trellis_context.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

import 'support/ai_relay_fixture.dart';
import 'support/trellis_fixture.dart';

/// 记录调用次数、可注入失败的可替换上下文。
class _CountingContext extends VibeProjectAgentContext {
  _CountingContext({
    required super.projectRoot,
    super.trellisLoader,
    this.failSkills = false,
    this.failRules = false,
  });

  final bool failSkills;
  final bool failRules;

  int skillCalls = 0;
  int ruleCalls = 0;
  int trellisCalls = 0;

  @override
  Future<List<VibeSkill>> skills() async {
    skillCalls++;
    if (failSkills) throw const FileSystemException('技能目录不可读');
    return const <VibeSkill>[];
  }

  @override
  Future<String> rules() async {
    ruleCalls++;
    if (failRules) throw const FileSystemException('规则文件不可读');
    return '项目规则：不要改生成文件。';
  }

  @override
  Future<String> trellisContext() async {
    trellisCalls++;
    return super.trellisContext();
  }
}

void main() {
  late Directory project;

  setUp(() {
    StudioProfile.current = null;
    project = makeTrellisProject();
  });

  VibeCodingController build(
    _FakeRelay relay, {
    VibeProjectAgentContext? context,
    int maxRounds = 2,
  }) => VibeCodingController(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => 'local-token',
    projectRoot: project.path,
    projectName: 'demo',
    language: 'python',
    maxRounds: maxRounds,
    context:
        context ??
        VibeProjectAgentContext(
          projectRoot: project.path,
          trellisLoader: const TrellisContextLoader(),
        ),
  );

  Future<void> settle(VibeCodingController controller, VibePhase phase) async {
    for (var i = 0; i < 500 && controller.phase != phase; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(
      controller.phase,
      phase,
      reason: controller.lastError ?? controller.phase.name,
    );
  }

  test(
    'injects the Trellis context once per session',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final relay = _FakeRelay()
        ..chatReplies.addAll([_textReply('第一轮'), _textReply('第二轮')]);
      final context = _CountingContext(
        projectRoot: project.path,
        trellisLoader: const TrellisContextLoader(),
      );
      final controller = build(relay, context: context);

      controller.send('先做第一步');
      await settle(controller, VibePhase.succeeded);
      controller.send('再做第二步');
      await settle(controller, VibePhase.succeeded);

      final system =
          ((relay.chatBodies.first['messages'] as List).first as Map)['content']
              as String;
      expect(system, contains('### Trellis 项目上下文'));
      expect(system, contains('项目规则：不要改生成文件。'));
      // Trellis 一个会话只读一次；技能与规则每次 send 重新读（磁盘上的改动要能生效）。
      expect(context.trellisCalls, 1);
      expect(context.skillCalls, 2);
      expect(context.ruleCalls, 2);
    },
  );

  test(
    'replaces the current user message for a Trellis slash command',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final relay = _FakeRelay()
        ..chatReplies.addAll([_textReply('先回答'), _textReply('继续做了')]);
      final controller = build(relay);

      controller.send('普通提问');
      await settle(controller, VibePhase.succeeded);
      controller.send('/trellis:continue 接着做');
      await settle(controller, VibePhase.succeeded);

      final second = (relay.chatBodies.last['messages'] as List)
          .cast<Map<String, dynamic>>();
      final userMessages = second
          .where((entry) => entry['role'] == 'user')
          .map((entry) => entry['content'] as String)
          .toList();

      // 上一条用户消息原样保留，只有本轮输入被换成了展开后的指令。
      expect(userMessages.first, '普通提问');
      expect(userMessages.last, isNot('/trellis:continue 接着做'));
      expect(userMessages.last, contains('接着做'));
      // 气泡仍显示用户输入的那一行。
      expect(
        controller.messages.lastWhere((message) => message.isUser).text,
        '/trellis:continue 接着做',
      );
    },
  );

  test(
    'a failing skill or rule read does not stall the session',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final relay = _FakeRelay()..chatReplies.add(_textReply('照常回答'));
      final controller = build(
        relay,
        context: _CountingContext(
          projectRoot: project.path,
          failSkills: true,
          failRules: true,
        ),
      );

      controller.send('读不到技能也要能聊');
      await settle(controller, VibePhase.succeeded);

      expect(controller.lastError, isNull);
      final messages = (relay.chatBodies.single['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages.first['content'] as String, isNot(contains('项目规则')));
    },
  );

  test(
    'a project without a workflow gets no Trellis context',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final root = Directory.systemTemp.createTempSync('no-trellis-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      File(p.join(root.path, 'README.md')).writeAsStringSync('# demo\n');
      final relay = _FakeRelay()..chatReplies.add(_textReply('好的'));
      final controller = VibeCodingController(
        api: ApiClient(transport: relay.client),
        tokenProvider: () => 'local-token',
        projectRoot: root.path,
        projectName: 'demo',
        language: 'python',
        maxRounds: 1,
      );

      controller.send('你好');
      await settle(controller, VibePhase.succeeded);

      final system =
          ((relay.chatBodies.single['messages'] as List).first
                  as Map)['content']
              as String;
      expect(system, isNot(contains('Trellis')));
    },
  );
}

Map<String, dynamic> _textReply(String text) => {
  'model': 'demo-model',
  'message': {'role': 'assistant', 'content': text},
};

/// 只回答固定文本的假中继，记录每次请求体。
class _FakeRelay {
  _FakeRelay() {
    client = MockClient.streaming((
      http.BaseRequest request,
      Stream<List<int>> body,
    ) async {
      final raw = await utf8.decoder.bind(body).join();
      chatBodies.add(
        raw.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>,
      );
      return relayTurnResponse(chatReplies.removeAt(0));
    });
  }

  late final http.Client client;
  final List<Map<String, dynamic>> chatReplies = [];
  final List<Map<String, dynamic>> chatBodies = [];
}
