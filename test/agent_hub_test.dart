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
    root = Directory.systemTemp.createTempSync('agent-hub-');
    project = Directory(p.join(root.path, 'proj'))..createSync(recursive: true);
    store = FileAgentSessionStore(
      root: Directory(p.join(root.path, 'sessions')),
    );
    await store.load();
  });

  tearDown(() async {
    await store.flush();
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 上偶发占用，临时目录可以留在临时区。
    }
  });

  VibeAgentRuntime runtime(
    _Relay relay, {
    int maxIdleFacades = 8,
    AgentRequestScheduler? scheduler,
  }) => VibeAgentRuntime(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => 'local-token',
    sessions: store,
    projectRootOf: (_) => project.path,
    languageOf: (_) => 'python',
    scheduler: scheduler ?? AgentRequestScheduler(retryDelays: const []),
    maxIdleFacades: maxIdleFacades,
  );

  Future<void> waitFor(
    Future<bool> Function() condition, {
    String reason = 'condition not met',
  }) async {
    for (var i = 0; i < 2000; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail(reason);
  }

  test('E1 two sessions run at the same time', () async {
    final first = await store.create('p1');
    final second = await store.create('p1');
    final relay = _Relay()
      ..add(_textReply('一'), gate: Completer<void>())
      ..add(_textReply('二'), gate: Completer<void>());
    final hub = runtime(relay);

    final a = await hub.open('p1', first.id);
    final b = await hub.open('p1', second.id);

    final sendA = a.send('甲', permission: AgentPermissionMode.autoAcceptEdits);
    final sendB = b.send('乙', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(
      () => Future.value(
        a.state == AgentRunState.running && b.state == AgentRunState.running,
      ),
      reason: '两个会话没有同时运行',
    );
    expect(hub.statusOf(first.id), AgentLiveStatus.running);
    expect(hub.statusOf(second.id), AgentLiveStatus.running);

    // 切换显示不影响原来那个会话：它还在跑。
    expect(hub.liveFacade(first.id), same(a));
    expect(a.state, AgentRunState.running);

    relay.releaseAll();
    await sendA;
    await sendB;
    await waitFor(
      () => Future.value(
        a.state == AgentRunState.idle && b.state == AgentRunState.idle,
      ),
    );
    // 两个会话各自拿到一条回复；谁先谁后取决于磁盘读的完成顺序。
    expect({a.messages.last.text, b.messages.last.text}, {'一', '二'});
  });

  test('open returns the same instance for the same session', () async {
    final meta = await store.create('p1');
    final hub = runtime(_Relay());

    final first = await hub.open('p1', meta.id);
    final again = await hub.open('p1', meta.id);

    expect(again, same(first));
    expect(hub.liveFacade(meta.id), same(first));
  });

  test('maps run state to the sidebar status', () async {
    final meta = await store.create('p1');
    final relay = _Relay()..add(_textReply('好。'), gate: Completer<void>());
    final hub = runtime(relay);
    final facade = await hub.open('p1', meta.id);

    expect(hub.statusOf(meta.id), AgentLiveStatus.idle);

    final send = facade.send('跑一下', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.running));
    expect(hub.statusOf(meta.id), AgentLiveStatus.running);

    relay.releaseAll();
    await send;
    await waitFor(() => Future.value(facade.state == AgentRunState.idle));
    // 后台完成、用户还没看。
    expect(hub.statusOf(meta.id), AgentLiveStatus.finishedUnread);

    hub.markSeen(meta.id);
    expect(hub.statusOf(meta.id), AgentLiveStatus.idle);
  });

  test('a failed background session stays failed until seen', () async {
    final meta = await store.create('p1');
    final relay = _Relay()..failWith(500, '上游炸了');
    final hub = runtime(relay);
    final facade = await hub.open('p1', meta.id);

    await facade.send('跑一下', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.failed));

    expect(hub.statusOf(meta.id), AgentLiveStatus.failed);
    hub.markSeen(meta.id);
    expect(hub.statusOf(meta.id), AgentLiveStatus.idle);
  });

  test('awaiting approval is visible from the hub', () async {
    final meta = await store.create('p1');
    final relay = _Relay()
      ..add(_writeCall('c1', 'a.txt', 'hi\n'))
      ..add(_textReply('好了。'));
    final hub = runtime(relay);
    final facade = await hub.open('p1', meta.id);

    await facade.send('写个文件', permission: AgentPermissionMode.askEveryWrite);
    await waitFor(
      () => Future.value(facade.state == AgentRunState.awaitingApproval),
    );

    expect(hub.statusOf(meta.id), AgentLiveStatus.awaitingApproval);
    facade.resolveApproval(true);
    await waitFor(() => Future.value(facade.state == AgentRunState.idle));
  });

  test('E4 the second session gets a conflict and the file is not overwritten',
      () async {
    final first = await store.create('p1');
    final second = await store.create('p1');
    final relay = _Relay()
      // 会话一：写 a.txt，等用户确认（此时持有租约）。
      ..add(_writeCall('c1', 'a.txt', '甲的正文\n'))
      // 会话二：写同一个文件，自动接受，应该拿到冲突。
      ..add(_writeCall('c2', 'a.txt', '乙的正文\n'))
      // 请求按发出顺序取回复：先接会话二收尾，再接会话一收尾。
      ..add(_textReply('写不了。'))
      ..add(_textReply('写好了。'));
    final hub = runtime(relay);

    final a = await hub.open('p1', first.id);
    final b = await hub.open('p1', second.id);

    await a.send('写 a.txt', permission: AgentPermissionMode.askEveryWrite);
    await waitFor(
      () => Future.value(a.state == AgentRunState.awaitingApproval),
    );

    await b.send('也写 a.txt', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(
      () => Future.value(b.messages.any((m) => m.role == 'tool')),
      reason: '会话二没有产生工具结果',
    );
    await waitFor(() => Future.value(b.state == AgentRunState.idle));

    final conflict = b.messages.firstWhere((m) => m.role == 'tool');
    expect(conflict.isError, isTrue);
    expect(conflict.text, contains('文件正被会话'));
    expect(conflict.text, contains('稍后再试'));
    expect(File(p.join(project.path, 'a.txt')).existsSync(), isFalse);

    a.resolveApproval(true);
    await waitFor(() => Future.value(a.state == AgentRunState.idle));
    expect(
      File(p.join(project.path, 'a.txt')).readAsStringSync(),
      contains('甲的正文'),
    );
  });

  test('E5 deleting a running session stops it before destroying it', () async {
    final meta = await store.create('p1');
    final relay = _Relay()..add(_textReply('好。'), gate: Completer<void>());
    final hub = runtime(relay);
    final facade = await hub.open('p1', meta.id);

    final send = facade.send('跑一下', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.running));

    await store.delete(meta.id);
    // 回复还被 gate 挡着：状态离开 running 只可能是 cancel 做过了。
    await waitFor(
      () => Future.value(facade.state != AgentRunState.running),
      reason: '删除运行中的会话时没有先 cancel，实例被直接销毁',
    );
    relay.releaseAll();
    await send;

    await waitFor(
      () => Future.value(hub.liveFacade(meta.id) == null),
      reason: '删除后实例没有被销毁',
    );
    expect(facade.state, isNot(AgentRunState.running));
    expect(store.metaOf(meta.id), isNull);
  });

  test('keeps at most maxIdleFacades idle instances', () async {
    final hub = runtime(_Relay(), maxIdleFacades: 3);
    final ids = <String>[];
    for (var index = 0; index < 6; index++) {
      final meta = await store.create('p1');
      ids.add(meta.id);
      await hub.open('p1', meta.id);
    }

    final live = ids.where((id) => hub.liveFacade(id) != null).toList();
    expect(live.length, lessThanOrEqualTo(3));
    // 最近打开的还在。
    expect(hub.liveFacade(ids.last), isNotNull);
  });

  test('never evicts a running instance', () async {
    final running = await store.create('p1');
    final relay = _Relay()..add(_textReply('好。'), gate: Completer<void>());
    final hub = runtime(relay, maxIdleFacades: 1);
    final facade = await hub.open('p1', running.id);
    final send = facade.send('跑一下', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.running));

    for (var index = 0; index < 4; index++) {
      final meta = await store.create('p1');
      await hub.open('p1', meta.id);
    }

    expect(hub.liveFacade(running.id), same(facade));
    relay.releaseAll();
    await send;
  });

  test('cancelAll stops every running session', () async {
    final first = await store.create('p1');
    final second = await store.create('p1');
    final relay = _Relay()
      ..add(_textReply('一'), gate: Completer<void>())
      ..add(_textReply('二'), gate: Completer<void>());
    final hub = runtime(relay);
    final a = await hub.open('p1', first.id);
    final b = await hub.open('p1', second.id);

    final sendA = a.send('甲', permission: AgentPermissionMode.autoAcceptEdits);
    final sendB = b.send('乙', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(
      () => Future.value(
        a.state == AgentRunState.running && b.state == AgentRunState.running,
      ),
    );

    final stopping = hub.cancelAll();
    relay.releaseAll();
    await stopping;
    await sendA;
    await sendB;

    expect(a.state, isNot(AgentRunState.running));
    expect(b.state, isNot(AgentRunState.running));
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

class _Reply {
  _Reply(this.body, {this.gate});

  final Map<String, dynamic> body;
  final Completer<void>? gate;
}

class _Relay {
  _Relay() {
    client = MockClient.streaming((request, bodyStream) async {
      final body = await utf8.decoder.bind(bodyStream).join();
      if (request.url.path == '/api/ai/models') {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'object': 'list', 'data': []}))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      chatBodies.add(
        body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>,
      );
      if (failure != null) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'error': failure!.$2}))),
          failure!.$1,
          headers: {'content-type': 'application/json'},
        );
      }
      final reply = replies.removeAt(0);
      final gate = reply.gate;
      if (gate != null) await gate.future;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(reply.body))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  late final http.Client client;
  final List<_Reply> replies = [];
  final List<Completer<void>> gates = [];
  final List<Map<String, dynamic>> chatBodies = [];
  (int, String)? failure;

  void add(Map<String, dynamic> body, {Completer<void>? gate}) {
    replies.add(_Reply(body, gate: gate));
    if (gate != null) gates.add(gate);
  }

  void failWith(int status, String message) => failure = (status, message);

  /// 放行所有被挡住的回复（包括已经在途的）。
  void releaseAll() {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}
