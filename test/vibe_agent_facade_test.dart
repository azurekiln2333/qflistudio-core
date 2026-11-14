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
import 'package:qfli_studio_core/vibe_coding/agent_request_scheduler.dart';
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
    Directory? cacheDir,
  }) => VibeAgentRuntime(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => token,
    sessions: store,
    projectRootOf: (_) => project.path,
    languageOf: (_) => 'python',
    configuredModel: configuredModel,
    // 测试里不真的等 1/2/4 秒。
    scheduler: AgentRequestScheduler(retryDelays: const []),
    cacheDir: cacheDir,
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

  /// 等本轮结束，失败也算结束。
  Future<void> settleAny(AgentFacade facade) async {
    await waitFor(
      () => Future.value(
        facade.state != AgentRunState.running &&
            facade.state != AgentRunState.cancelling,
      ),
    );
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

  test('send shows the user message and running state in the same frame', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()..chatReplies.addAll([_textReply('好。')]);
    final facade = await runtime(relay).open('p1', meta.id);

    final pending = facade.send(
      '马上要看到我',
      permission: AgentPermissionMode.autoAcceptEdits,
    );
    // 同步段：这里还没 await 任何东西，界面已经能拿到用户消息和运行状态。
    expect(facade.messages.last.role, 'user');
    expect(facade.messages.last.text, '马上要看到我');
    expect(facade.state, AgentRunState.running);

    await pending;
    await settle(facade);
    expect(facade.messages.first.text, '马上要看到我');
  });

  test('opening a session never touches the network', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, {
      'id': 'm0',
      'role': 'user',
      'text': '历史消息',
    });
    await store.flush();
    final relay = _FakeRelay()..failOnRequest = true;

    final facade = await runtime(relay).open('p1', meta.id);

    expect(facade.messages.single.text, '历史消息');
    expect(relay.requestCount, 0);
  });

  test('opens the tail and pages earlier messages on demand', () async {
    final meta = await store.create('p1');
    for (var index = 0; index < 100; index++) {
      await store.appendMessage(meta.id, {
        'id': 'm$index',
        'role': 'user',
        'text': '第 $index 条',
      });
    }
    await store.flush();

    final facade = await runtime(_FakeRelay()).open('p1', meta.id);
    expect(facade.messages.length, 60);
    expect(facade.messages.last.text, '第 99 条');
    expect(facade.hasEarlier, isTrue);

    await facade.loadEarlier();
    expect(facade.messages.length, 100);
    expect(facade.messages.first.text, '第 0 条');
    expect(facade.hasEarlier, isFalse);
  });

  test('classifies API failures for the error card', () async {
    final meta = await store.create('p1');

    Future<AgentFacade> failing(int status, String message) async {
      final relay = _FakeRelay()
        ..chatStatus = status
        ..chatError = message;
      final facade = await runtime(relay).open('p1', meta.id);
      await facade.send('x', permission: AgentPermissionMode.autoAcceptEdits);
      await settleAny(facade);
      return facade;
    }

    final notConfigured = await failing(503, 'AI 服务未配置');
    expect(notConfigured.lastErrorInfo?.kind, AgentErrorKind.notConfigured);
    expect(notConfigured.lastErrorInfo?.statusCode, 503);

    final limited = await failing(429, '请求太频繁');
    expect(limited.lastErrorInfo?.kind, AgentErrorKind.rateLimited);

    final expired = await failing(401, '登录已过期');
    expect(expired.lastErrorInfo?.kind, AgentErrorKind.loginExpired);
  });

  test('activity names the tool that is running', () async {
    final meta = await store.create('p1');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'a.txt', 'hi\n'),
        _textReply('好了。'),
      ]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('写个文件', permission: AgentPermissionMode.askEveryWrite);
    await waitFor(
      () => Future.value(facade.state == AgentRunState.awaitingApproval),
    );
    expect(facade.activity, '正在写入 a.txt');

    facade.resolveApproval(true);
    await settle(facade);
    expect(facade.activity, isNull);
  });

  test('truncates tool output on disk but keeps it in memory', () async {
    final meta = await store.create('p1');
    File(p.join(project.path, 'big.txt')).writeAsStringSync('y' * 20000);
    final relay = _FakeRelay()
      ..chatReplies.addAll([_readCall('c1', 'big.txt'), _textReply('看过了。')]);
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send(
      '看看 big.txt',
      permission: AgentPermissionMode.autoAcceptEdits,
    );
    await settle(facade);

    // 内存里的工具条目是摘要，完整输出在模型历史里。
    final tool = facade.messages.firstWhere((m) => m.role == 'tool');
    expect(tool.toolName, 'read_file');

    final saved = await store.read(meta.id);
    final toolEntry = saved.history.firstWhere((e) => e['role'] == 'tool');
    final savedText = toolEntry['content']! as String;
    expect(savedText.length, lessThan(9000));
    expect(savedText, contains('已截断'));
    // 截断保留尾部：文件末尾的内容还在。
    expect(savedText.trimRight().endsWith('y'), isTrue);
  });

  test('models are cached in memory and on disk', () async {
    final relay = _FakeRelay()
      ..models = {
        'object': 'list',
        'data': [
          {'id': 'fast-model', 'object': 'model'},
        ],
      };
    final cacheDir = Directory(p.join(root.path, 'cache'));

    final first = runtime(relay, cacheDir: cacheDir);
    expect((await first.models()).map((m) => m.id), ['fast-model']);
    expect(relay.modelRequests, 1);

    // 内存缓存：第二次不再请求。
    expect((await first.models()).map((m) => m.id), ['fast-model']);
    expect(relay.modelRequests, 1);

    // 新运行时读盘缓存，仍然不请求。
    final second = runtime(relay, cacheDir: cacheDir);
    expect((await second.models()).map((m) => m.id), ['fast-model']);
    expect(relay.modelRequests, 1);
  });

  test('send and retryLast ignore duplicate triggers while active', () async {
    final meta = await store.create('p1');
    final gate = Completer<void>();
    final relay = _FakeRelay()..chatGate = gate;
    relay.chatReplies.add(_textReply('回复一'));
    final facade = await runtime(relay).open('p1', meta.id);

    final first = facade.send('只发一次', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.running));

    await facade.send('并发重复', permission: AgentPermissionMode.autoAcceptEdits);
    await facade.retryLast();

    gate.complete();
    await first;
    await settle(facade);

    expect(relay.chatBodies, hasLength(1));
    expect(
      facade.messages.where((m) => m.role == 'user').map((m) => m.text).toList(),
      ['只发一次'],
    );
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

Map<String, dynamic> _readCall(String id, String path) => {
  'model': 'demo-model',
  'message': {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': id,
        'type': 'function',
        'function': {
          'name': 'read_file',
          'arguments': jsonEncode({'path': path}),
        },
      },
    ],
  },
  'aiGenerated': true,
};

class _FakeRelay {
  _FakeRelay() {
    client = MockClient.streaming((request, bodyStream) async {
      requestCount++;
      if (failOnRequest) {
        throw StateError('测试里不应该发请求：${request.url.path}');
      }
      final body = await utf8.decoder.bind(bodyStream).join();
      if (request.url.path == '/api/ai/models') {
        modelRequests++;
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
      if (chatStatus != null) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(jsonEncode({'error': chatError ?? '失败'})),
          ),
          chatStatus!,
          headers: {'content-type': 'application/json'},
        );
      }
      final reply = chatReplies.removeAt(0);
      final gate = chatGate;
      if (gate != null) await gate.future;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(reply))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  late final http.Client client;
  Completer<void>? chatGate;
  final List<Map<String, dynamic>> chatReplies = [];
  final List<Map<String, dynamic>> chatBodies = [];
  Map<String, dynamic>? models;
  bool modelsFail = false;

  /// 任何请求都直接失败，用来证明某条路径不碰网络。
  bool failOnRequest = false;

  /// 非空时 `/api/ai/chat` 直接返回这个状态码。
  int? chatStatus;
  String? chatError;

  int requestCount = 0;
  int modelRequests = 0;
}
