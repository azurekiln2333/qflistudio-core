import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

import 'support/ai_relay_fixture.dart';

void main() {
  late Directory root;

  setUp(() {
    StudioProfile.current = null;
    root = Directory.systemTemp.createTempSync('vibe-hooks-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  VibeCodingController build(
    _FakeRelay relay, {
    Future<String?> Function(VibeWriteRequest request)? writeApproval,
    List<Map<String, dynamic>>? restoredHistory,
    String? modelId,
    String? reasoningEffort,
  }) => VibeCodingController(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => 'local-token',
    projectRoot: root.path,
    projectName: 'demo',
    language: 'python',
    maxRounds: 4,
    writeApproval: writeApproval,
    restoredHistory: restoredHistory,
    modelId: modelId,
    reasoningEffort: reasoningEffort,
  );

  Future<void> settle(VibeCodingController controller, VibePhase phase) async {
    for (var i = 0; i < 500 && controller.phase != phase; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(
      controller.phase,
      phase,
      reason:
          '${controller.lastError} | '
          '${controller.messages.map((m) => '${m.tool?.toolName}:${m.tool?.status}:${m.tool?.result}').join(', ')}',
    );
  }

  test('a rejected approval leaves no file and tells the model why', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'hi\n'),
        _textReply('没有权限，先不写。'),
      ]);
    final requests = <VibeWriteRequest>[];
    final controller = build(
      relay,
      writeApproval: (request) async {
        requests.add(request);
        return '只读模式已拒绝写入';
      },
    );

    controller.send('写个文件');
    await settle(controller, VibePhase.succeeded);

    expect(requests, hasLength(1));
    expect(requests.single.path, 'a.txt');
    expect(requests.single.isCreate, isTrue);
    expect(requests.single.summary, contains('a.txt'));
    expect(File(p.join(root.path, 'a.txt')).existsSync(), isFalse);

    final tool = controller.messages.firstWhere((m) => m.tool != null).tool!;
    expect(tool.status, VibeToolStatus.conflict);
    expect(tool.result, '只读模式已拒绝写入');
    expect(tool.changedPaths, isEmpty);

    final reply = (relay.chatBodies.last['messages'] as List)
        .cast<Map<String, dynamic>>()
        .lastWhere((entry) => entry['role'] == 'tool');
    expect(reply['content'], contains('error(permission)'));
  });

  test('an allowed approval writes and reports the changed path', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'src/app.py', 'print(1)\n'),
        _textReply('已写入。'),
      ]);
    final controller = build(relay, writeApproval: (_) async => null);

    controller.send('写个文件');
    await settle(controller, VibePhase.succeeded);

    expect(File(p.join(root.path, 'src', 'app.py')).existsSync(), isTrue);
    final tool = controller.messages.firstWhere((m) => m.tool != null).tool!;
    expect(tool.status, VibeToolStatus.ok);
    expect(tool.changedPaths, ['src/app.py']);
  });

  test('approval runs before the read-before-write policy check', () async {
    // 已有文件但没有先读；只读模式要在策略检查之前就明确拒绝。
    File(p.join(root.path, 'a.txt')).writeAsStringSync('old\n');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'new\n'),
        _textReply('好的。'),
      ]);
    final controller = build(relay, writeApproval: (_) async => '当前是只读模式');

    controller.send('覆盖 a.txt');
    await settle(controller, VibePhase.succeeded);

    final tool = controller.messages.firstWhere((m) => m.tool != null).tool!;
    expect(tool.result, '当前是只读模式');
    expect(File(p.join(root.path, 'a.txt')).readAsStringSync(), 'old\n');
  });

  test('cancelling while an approval is pending does not hang', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([_writeCall('c1', 'a.txt', 'hi\n')]);
    final asked = Completer<void>();
    final controller = build(
      relay,
      writeApproval: (_) {
        if (!asked.isCompleted) asked.complete();
        return Completer<String?>().future; // 用户一直不回复
      },
    );

    controller.send('写个文件');
    await asked.future;
    expect(controller.phase, VibePhase.running);

    await controller.cancel().timeout(const Duration(seconds: 5));

    expect(controller.phase, VibePhase.cancelled);
    expect(File(p.join(root.path, 'a.txt')).existsSync(), isFalse);
  });

  test('disposing while an approval is pending does not hang', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([_writeCall('c1', 'a.txt', 'hi\n')]);
    final asked = Completer<void>();
    final controller = build(
      relay,
      writeApproval: (_) {
        if (!asked.isCompleted) asked.complete();
        return Completer<String?>().future;
      },
    );

    controller.send('写个文件');
    await asked.future;
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(File(p.join(root.path, 'a.txt')).existsSync(), isFalse);
  });

  test('restored history keeps complete pairs and drops the rest', () async {
    final relay = _FakeRelay()..chatReplies.addAll([_textReply('继续。')]);
    final controller = build(
      relay,
      restoredHistory: [
        {'role': 'system', 'content': '旧系统提示'},
        {'role': 'user', 'content': '上一轮问题'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'old-1',
              'type': 'function',
              'function': {'name': 'list_files', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'old-1', 'content': '目录为空'},
        {'role': 'tool', 'tool_call_id': 'orphan', 'content': '孤立回复'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'old-2',
              'type': 'function',
              'function': {'name': 'read_file', 'arguments': '{"path":"a"}'},
            },
          ],
        },
      ],
    );

    controller.send('接着上一轮');
    await settle(controller, VibePhase.succeeded);

    final sent = (relay.chatBodies.first['messages'] as List)
        .cast<Map<String, dynamic>>();
    expect(sent.first['role'], 'system');
    expect(sent.first['content'], isNot(contains('旧系统提示')));
    expect(sent.map((entry) => entry['role']), [
      'system',
      'user',
      'assistant',
      'tool',
      'user',
    ]);
    expect(sent[3]['tool_call_id'], 'old-1');
    expect(sent.where((entry) => entry['tool_call_id'] == 'orphan'), isEmpty);
    // 尾部没有答完的 old-2 组整组丢掉，协议仍然合法。
    expect(
      sent.where(
        (entry) =>
            entry['role'] == 'assistant' &&
            '${entry['tool_calls']}'.contains('old-2'),
      ),
      isEmpty,
    );
  });

  test('the history getter exposes what a session would persist', () async {
    final relay = _FakeRelay()..chatReplies.addAll([_textReply('好了。')]);
    final controller = build(relay);

    controller.send('你好');
    await settle(controller, VibePhase.succeeded);

    final history = controller.history;
    expect(history.first['role'], 'system');
    expect(
      history.map((entry) => entry['role']),
      containsAll(['user', 'assistant']),
    );
    expect(
      () => (history as List).add({'role': 'user', 'content': 'x'}),
      throwsUnsupportedError,
    );
  });

  test('model and reasoning effort reach the relay only when set', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([_textReply('一'), _textReply('二')]);
    final controller = build(relay);

    controller.send('默认');
    await settle(controller, VibePhase.succeeded);
    expect(relay.chatBodies.first.containsKey('model'), isFalse);
    expect(relay.chatBodies.first.containsKey('reasoning_effort'), isFalse);

    controller.configureModel(modelId: 'demo-model', reasoningEffort: 'high');
    controller.send('指定模型');
    settle(controller, VibePhase.succeeded);
    for (var i = 0; i < 500 && controller.phase != VibePhase.succeeded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(relay.chatBodies.last['model'], 'demo-model');
    expect(relay.chatBodies.last['reasoning_effort'], 'high');
  });
}

Map<String, dynamic> _textReply(String text) => {
  'model': 'demo-model',
  'message': {'role': 'assistant', 'content': text},
  'aiGenerated': true,
};

Map<String, dynamic> _writeCall(String id, String path, String content) => {
  'model': 'demo-model',
  'message': {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': id,
        'type': 'function',
        'function': {
          'name': 'write_file',
          'arguments': jsonEncode({'path': path, 'content': content}),
        },
      },
    ],
  },
  'aiGenerated': true,
};

class _FakeRelay {
  _FakeRelay() {
    client = MockClient.streaming((request, bodyStream) async {
      final body = await utf8.decoder.bind(bodyStream).join();
      expect(request.url.path, '/api/ai/chat/stream');
      chatBodies.add(
        body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>,
      );
      final reply = chatReplies.removeAt(0);
      return relayTurnResponse(reply);
    });
  }

  late final http.Client client;
  final List<Map<String, dynamic>> chatReplies = [];
  final List<Map<String, dynamic>> chatBodies = [];
}
