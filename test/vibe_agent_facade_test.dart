import 'dart:async';
import 'dart:convert';
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
    root = Directory.systemTemp.createTempSync('agent-facade-');
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
      // Windows 上偶发占用，测试目录可以留在临时区。
    }
  });

  VibeAgentRuntime runtime(
    _FakeRelay relay, {
    String? token = 'local-token',
    String Function()? configuredModel,
  }) => VibeAgentRuntime(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => token,
    sessions: store,
    projectRootOf: (_) => project.path,
    languageOf: (_) => 'python',
    configuredModel: configuredModel,
  );

  Future<void> waitFor(
    Future<bool> Function() condition, {
    String reason = 'condition not met',
  }) async {
    for (var i = 0; i < 600; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail(reason);
  }

  /// 等待后台持久化追上，避免测试结束与写入竞争。
  Future<void> settle(AgentFacade facade) async {
    await waitFor(() => Future.value(facade.state == AgentRunState.idle));
    await facade.flush();
  }

  test('opening a session without a token requires login', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay();

    await expectLater(
      runtime(relay, token: null).open('p1', meta.id),
      throwsA(isA<AgentLoginRequired>()),
    );
    await expectLater(
      runtime(relay, token: '').models(),
      throwsA(isA<AgentLoginRequired>()),
    );
  });

  test('sending without a token throws instead of faking a run', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay();
    // 登录态在打开会话之后过期：send 仍然要抛，不发请求。
    final facade = VibeAgentFacade(
      api: ApiClient(transport: relay.client),
      tokenProvider: () => null,
      store: store,
      meta: meta,
      projectRoot: project.path,
      projectName: 'proj',
      language: 'python',
    );
    addTearDown(facade.dispose);

    await expectLater(
      facade.send('x', permission: AgentPermissionMode.autoAcceptEdits),
      throwsA(isA<AgentLoginRequired>()),
    );
    expect(facade.messages, isEmpty);
    expect(relay.chatBodies, isEmpty);
  });

  test('read only mode refuses writes without asking', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'hi\n'),
        _textReply('写不了，当前只读。'),
      ]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('写个文件', permission: AgentPermissionMode.readOnly);
    await settle(facade);

    expect(facade.pendingApproval, isNull);
    expect(File(p.join(project.path, 'a.txt')).existsSync(), isFalse);
    final tool = facade.messages.firstWhere((m) => m.role == 'tool');
    expect(tool.isError, isTrue);
    expect(tool.toolName, 'write_file');
    expect(tool.text, contains('只读模式'));
  });

  test('ask every write surfaces the approval and honours allow', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'hi\n'),
        _textReply('写好了。'),
      ]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('写个文件', permission: AgentPermissionMode.askEveryWrite);
    await waitFor(
      () => Future.value(facade.state == AgentRunState.awaitingApproval),
      reason: 'approval was never requested',
    );

    expect(facade.pendingApproval?.path, 'a.txt');
    expect(facade.pendingApproval?.summary, contains('新建 a.txt'));

    facade.resolveApproval(true);
    await settle(facade);

    expect(facade.pendingApproval, isNull);
    expect(File(p.join(project.path, 'a.txt')).existsSync(), isTrue);
    expect(
      facade.messages.any((m) => m.changedPaths.contains('a.txt')),
      isTrue,
    );
  });

  test('ask every write honours deny', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'hi\n'),
        _textReply('好的，不写。'),
      ]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('写个文件', permission: AgentPermissionMode.askEveryWrite);
    await waitFor(
      () => Future.value(facade.state == AgentRunState.awaitingApproval),
    );
    facade.resolveApproval(false);
    await settle(facade);

    expect(File(p.join(project.path, 'a.txt')).existsSync(), isFalse);
    final tool = facade.messages.firstWhere((m) => m.role == 'tool');
    expect(tool.isError, isTrue);
    expect(tool.text, contains('拒绝'));
  });

  test('auto accept edits writes without asking', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'hi\n'),
        _textReply('写好了。'),
      ]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('写个文件', permission: AgentPermissionMode.autoAcceptEdits);
    await settle(facade);

    expect(facade.pendingApproval, isNull);
    expect(File(p.join(project.path, 'a.txt')).existsSync(), isTrue);
  });

  test('attachments travel as paths, not as file bodies', () async {
    final meta = await store.create('p1');
    final target = File(p.join(project.path, 'notes.txt'))
      ..writeAsStringSync('秘密正文\n');
    final relay = _FakeRelay()..chatReplies.addAll([_textReply('收到。')]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send(
      '看看这个文件',
      attachedPaths: ['notes.txt'],
      permission: AgentPermissionMode.autoAcceptEdits,
    );
    await settle(facade);

    final userMessage = facade.messages.firstWhere((m) => m.role == 'user');
    expect(userMessage.text, contains('notes.txt'));
    expect(userMessage.text, isNot(contains('秘密正文')));
    expect(target.existsSync(), isTrue);

    final sent = (relay.chatBodies.first['messages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((entry) => entry['role'] == 'user');
    expect(sent['content'], contains('- notes.txt'));
    expect(sent['content'], isNot(contains('秘密正文')));
  });

  test('persists messages and restores the model history', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()..chatReplies.addAll([_textReply('第一轮回复。')]);
    final first = await runtime(relay).open('p1', meta.id);

    await first.send('第一轮问题', permission: AgentPermissionMode.autoAcceptEdits);
    await settle(first);
    await waitFor(
      () async => (await store.read(meta.id)).messages.isNotEmpty,
      reason: 'transcript was never written',
    );

    final saved = await store.read(meta.id);
    expect(saved.messages.first['role'], 'user');
    expect(saved.messages.first['text'], '第一轮问题');
    expect(saved.history.map((entry) => entry['role']), contains('user'));

    // 新会话实例恢复展示消息，并把历史带回模型。
    final relay2 = _FakeRelay()..chatReplies.addAll([_textReply('第二轮回复。')]);
    final reopened = await runtime(relay2).open('p1', meta.id);
    expect(reopened.messages.first.text, '第一轮问题');

    await reopened.send(
      '第二轮问题',
      permission: AgentPermissionMode.autoAcceptEdits,
    );
    await settle(reopened);

    final sent = (relay2.chatBodies.first['messages'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      sent.map((entry) => entry['content']),
      containsAll(['第一轮问题', '第一轮回复。', '第二轮问题']),
    );
  });

  test('names the session after the first message', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()..chatReplies.addAll([_textReply('好。')]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send(
      '帮我把首页改成深色主题\n再加一个按钮',
      permission: AgentPermissionMode.autoAcceptEdits,
    );
    await waitFor(
      () async =>
          store.metaOf(meta.id)?.title != AgentSessionStore.defaultTitle,
      reason: 'title was not derived',
    );

    expect(store.metaOf(meta.id)?.title, '帮我把首页改成深色主题');
  });

  test('models reads reasoning efforts and falls back on failure', () async {
    final relay = _FakeRelay()
      ..models = {
        'object': 'list',
        'data': [
          {'id': 'fast-model', 'object': 'model'},
          {
            'id': 'think-model',
            'object': 'model',
            'reasoning_efforts': ['low', 'high'],
          },
        ],
      };
    final models = await runtime(relay).models();

    expect(models.map((m) => m.id), ['fast-model', 'think-model']);
    expect(models.first.supportsReasoning, isFalse);
    expect(models.last.reasoningEfforts, ['low', 'high']);

    final broken = _FakeRelay()..modelsFail = true;
    final fallback = await runtime(
      broken,
      configuredModel: () => 'configured-model',
    ).models();
    expect(fallback.single.id, 'configured-model');
    expect(fallback.single.reasoningEfforts, isEmpty);

    expect(await runtime(_FakeRelay()..modelsFail = true).models(), isEmpty);
  });

  test('skills lists project skills for the sidebar', () async {
    Directory(
      p.join(project.path, '.qfli', 'skills', 'demo'),
    ).createSync(recursive: true);
    File(
      p.join(project.path, '.qfli', 'skills', 'demo', 'SKILL.md'),
    ).writeAsStringSync('---\nname: demo\ndescription: 演示技能\n---\n正文\n');

    final skills = await runtime(_FakeRelay()).skills('p1');

    expect(skills.map((skill) => skill.name), contains('demo'));
    expect(
      skills.firstWhere((skill) => skill.name == 'demo').description,
      '演示技能',
    );
  });

  test('retryLast resends the previous prompt', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()
      ..chatReplies.addAll([_textReply('一'), _textReply('二')]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('同一个问题', permission: AgentPermissionMode.autoAcceptEdits);
    await settle(facade);
    await facade.retryLast();
    await settle(facade);
    await waitFor(() => Future.value(relay.chatBodies.length >= 2));

    final last = (relay.chatBodies.last['messages'] as List)
        .cast<Map<String, dynamic>>()
        .where((entry) => entry['role'] == 'user')
        .map((entry) => entry['content'])
        .toList();
    expect(last, ['同一个问题', '同一个问题']);
  });

  test('permission changes notify listeners', () async {
    final meta = await store.create('p1');
    final facade = await runtime(_FakeRelay()).open('p1', meta.id);
    var notified = 0;
    facade.addListener(() => notified++);

    facade.permission = AgentPermissionMode.readOnly;
    facade.permission = AgentPermissionMode.readOnly;

    expect(facade.permission, AgentPermissionMode.readOnly);
    expect(notified, 1);
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
      if (request.url.path == '/api/ai/models') {
        if (modelsFail) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'error': '服务不可用'}))),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(jsonEncode(models ?? {'object': 'list', 'data': []})),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      chatBodies.add(
        body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>,
      );
      final reply = chatReplies.removeAt(0);
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(reply))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  late final http.Client client;
  final List<Map<String, dynamic>> chatReplies = [];
  final List<Map<String, dynamic>> chatBodies = [];
  Map<String, dynamic>? models;
  bool modelsFail = false;
}
