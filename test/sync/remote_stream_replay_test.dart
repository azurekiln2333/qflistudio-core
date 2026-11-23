@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/remote/remote_ports.dart';
import 'package:qfli_studio_core/harness/remote/remote_terminal.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart'
    as protocol;
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart'
    show ConnectionPhase;
import 'package:qfli_studio_core/remote_control/state/session_view.dart';
import 'package:qfli_studio_core/sync/remote_session_cache.dart';

/// A session view the test fills by hand.
class _Port extends ChangeNotifier implements RemoteSessionPort {
  _Port(this.session, this._view);

  final protocol.SessionInfo session;
  final SessionView _view;

  @override
  Listenable get changes => this;
  @override
  bool get isOnline => true;
  @override
  ConnectionPhase get phase => ConnectionPhase.online;
  @override
  String get hostLabel => '办公室电脑';
  @override
  String get hostId => 'agent-42';
  @override
  List<protocol.SessionInfo> get sessions => <protocol.SessionInfo>[session];
  @override
  SessionView view(protocol.SessionInfo info) => _view;
  @override
  Future<void> refreshSessions() async {}
  @override
  Future<void> subscribe(String id, {required Object owner}) async {}
  @override
  void unsubscribe(String id, {required Object owner}) {}
  @override
  Future<void> send(String id, String text) async {}
  @override
  Future<void> respondPermission(
    String id,
    String requestId,
    String decision, {
    String? message,
    Map<String, String>? answers,
  }) async {}
  @override
  Future<void> terminalInput(String id, String data) async {}
  @override
  Future<void> terminalResize(String id, int cols, int rows) async {}
  @override
  Future<void> closeSession(String id) async {}
  @override
  Future<protocol.SessionInfo> createSession({
    required String cwd,
    String? prompt,
  }) async => session;
  @override
  Future<protocol.SessionInfo> createTerminal({required String cwd}) async =>
      session;
}

protocol.SessionInfo _session() => protocol.SessionInfo(
  id: 's1',
  title: '修复登录',
  cwd: r'D:\work',
  status: protocol.SessionStatus.running,
  mode: 'default',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  kind: 'claude',
  pending: 0,
);

/// 会话流缓存：断线重连后仍能看到此前的内容。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('qfli-stream-replay-');
  });

  tearDown(() async {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 文件句柄可能还没释放。
    }
  });

  Future<void> seed(RemoteSessionCache cache, List<String> texts) async {
    for (final text in texts) {
      await cache.append(<String, dynamic>{
        'id': 'e-$text',
        'role': 'user',
        'text': text,
      });
    }
  }

  RemoteTranscriptFeed feedFor(_Port port, RemoteSessionCache cache) =>
      RemoteTranscriptFeed(
        view: port._view,
        port: port,
        sessionId: 's1',
        owner: Object(),
        cache: cache,
      );

  Future<List<TranscriptEvent>> collect(
    RemoteTranscriptFeed feed, {
    Duration wait = const Duration(milliseconds: 900),
  }) async {
    final events = <TranscriptEvent>[];
    final subscription = feed.stream.listen(events.add);
    await Future<void>.delayed(wait);
    await subscription.cancel();
    return events;
  }

  test('重连后把缓存里的会话流补回来', () async {
    final cache = RemoteSessionCache(directory: dir.path);
    await seed(cache, ['第一句', '第二句']);
    final session = _session();

    final feed = feedFor(_Port(session, SessionView(session)), cache);
    final events = await collect(feed);

    expect(events.map((event) => event.text), ['第一句', '第二句']);
    expect(events.every((event) => event.role == TranscriptRole.user), isTrue);
    await feed.close();
  });

  test('实时流先到时不用缓存，避免重复一遍历史', () async {
    final cache = RemoteSessionCache(directory: dir.path);
    await seed(cache, ['旧内容']);
    final session = _session();
    final port = _Port(session, SessionView(session));

    final feed = feedFor(port, cache);
    final events = <TranscriptEvent>[];
    final subscription = feed.stream.listen(events.add);
    port._view.applyEvent(
      protocol.UserEvent(1, DateTime.fromMillisecondsSinceEpoch(10), '新一句'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await subscription.cancel();

    expect(events.map((event) => event.text), ['新一句']);
    await feed.close();
  });

  test('缓存为空时什么也不补', () async {
    final cache = RemoteSessionCache(directory: dir.path);
    final session = _session();

    final feed = feedFor(_Port(session, SessionView(session)), cache);

    expect(await collect(feed), isEmpty);
    await feed.close();
  });

  test('坏行跳过，好的照旧补回来', () async {
    final cache = RemoteSessionCache(directory: dir.path);
    await File(p.join(dir.path, 'stream.jsonl')).writeAsString(
      'not json\n'
      '${jsonEncode(<String, dynamic>{'id': 'e1', 'role': 'assistant', 'text': '在'})}\n'
      '${jsonEncode(<String, dynamic>{'id': 'e2', 'role': 'nonsense', 'text': 'x'})}\n',
    );
    final session = _session();

    final feed = feedFor(_Port(session, SessionView(session)), cache);
    final events = await collect(feed);

    expect(events.map((event) => event.text), ['在']);
    expect(events.single.role, TranscriptRole.assistant);
    await feed.close();
  });
}
