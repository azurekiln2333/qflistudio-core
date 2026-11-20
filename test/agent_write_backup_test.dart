import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/file_backup.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/vibe_coding/agent_request_scheduler.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/ai_relay_fixture.dart';

/// Agent 的覆盖写入必须和用户手动保存走同一条备份路径，
/// 这样「文件历史」里能看到 agent 覆盖前的版本，也能回滚。
void main() {
  late Directory root;
  late Directory project;
  late Directory appData;
  late FileAgentSessionStore store;
  StudioProfile? previousProfile;

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
    root = Directory.systemTemp.createTempSync('agent_backup_');
    project = Directory(p.join(root.path, 'proj'))..createSync(recursive: true);
    appData = Directory(p.join(root.path, 'appdata'))..createSync(recursive: true);
    FileBackup.baseOverride = appData.path;
    store = FileAgentSessionStore(
      root: Directory(p.join(root.path, 'sessions')),
    );
    await store.load();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    FileBackup.baseOverride = null;
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 上偶发占用，临时目录可以留下。
    }
  });

  Future<void> waitFor(Future<bool> Function() condition) async {
    for (var i = 0; i < 600; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition not met');
  }

  VibeAgentRuntime runtime(_FakeRelay relay) => VibeAgentRuntime(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => 'local-token',
    sessions: store,
    projectRootOf: (_) => project.path,
    languageOf: (_) => 'python',
    scheduler: AgentRequestScheduler(retryDelays: const []),
  );

  test('agent 覆盖已有文件时写进与手动保存同一份版本历史', () async {
    final target = File(p.join(project.path, 'src', 'main.py'));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync('print("user")\n', flush: true);

    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _readCall('c0', 'src/main.py'),
        _writeCall('c1', 'src/main.py', 'print("agent")\n'),
        _textReply('已改写 src/main.py。'),
      ]);
    final meta = await store.create('p1');
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('改写入口文件', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.idle));
    await facade.flush();

    expect(target.readAsStringSync(), contains('print("agent")'));

    // 与用户手动保存同一条路径：FileBackup 的历史里能看到覆盖前的版本。
    final versions = await FileBackup.listVersions(
      target,
      projectName: p.basename(project.path),
    );
    expect(versions, isNotEmpty, reason: 'agent 的覆盖必须留下版本历史');
    expect(
      versions.first.file.readAsStringSync(),
      'print("user")\n',
      reason: '备份的是覆盖前的磁盘内容',
    );
  });

  test('agent 新建文件不产生历史版本，也不报错', () async {
    final target = File(p.join(project.path, 'notes.md'));
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _writeCall('c1', 'notes.md', '# 笔记\n'),
        _textReply('已创建 notes.md。'),
      ]);
    final meta = await store.create('p1');
    final facade = await runtime(relay).open('p1', meta.id);

    await facade.send('新建笔记', permission: AgentPermissionMode.autoAcceptEdits);
    await waitFor(() => Future.value(facade.state == AgentRunState.idle));
    await facade.flush();

    expect(target.existsSync(), isTrue);
    expect(
      await FileBackup.listVersions(
        target,
        projectName: p.basename(project.path),
      ),
      isEmpty,
      reason: '新建没有覆盖任何内容，不需要历史版本',
    );
  });
}

Map<String, dynamic> _toolCall(
  String id,
  String name,
  Map<String, Object?> arguments,
) => {
  'model': 'deepseek-v4.1-flash',
  'message': {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      },
    ],
  },
  'usage': {'total_tokens': 10},
};

Map<String, dynamic> _readCall(String id, String path) =>
    _toolCall(id, 'read_file', {'path': path});

Map<String, dynamic> _writeCall(String id, String path, String content) =>
    _toolCall(id, 'write_file', {'path': path, 'content': content});

Map<String, dynamic> _textReply(String content) => {
  'model': 'deepseek-v4.1-flash',
  'message': {'role': 'assistant', 'content': content},
  'usage': {'total_tokens': 10},
};

class _FakeRelay {
  _FakeRelay() {
    client = MockClient.streaming((request, bodyStream) async {
      final body = await utf8.decoder.bind(bodyStream).join();
      if (request.url.path == '/api/ai/chat/stream') {
        chatBodies.add(jsonDecode(body) as Map<String, dynamic>);
        final reply = chatReplies.removeAt(0);
        return relayTurnResponse(reply);
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  late final http.Client client;
  final chatReplies = <Map<String, dynamic>>[];
  final chatBodies = <Map<String, dynamic>>[];
}