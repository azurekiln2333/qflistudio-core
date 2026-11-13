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
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

void main() {
  late Directory root;
  late Directory project;
  late Directory other;

  setUp(() {
    StudioProfile.current = null;
    root = Directory.systemTemp.createTempSync('vibe-attach-');
    project = Directory(p.join(root.path, 'proj'))..createSync(recursive: true);
    other = Directory(p.join(root.path, 'workspace', 'other'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 上偶发占用。
    }
  });

  String writeOutside(String name, String content) {
    final file = File(p.join(other.path, name))..writeAsStringSync(content);
    return file.path;
  }

  VibeProjectFiles files() => VibeProjectFiles(projectRoot: project.path);

  group('read only attachments', () {
    test('an outside file still needs the whitelist', () async {
      final outside = writeOutside('notes.txt', '外部正文\n');

      await expectLater(
        files().read(outside),
        throwsA(
          isA<VibeToolException>().having(
            (error) => error.code,
            'code',
            'escape',
          ),
        ),
      );
    });

    test('a whitelisted file is readable and keeps no write rights', () async {
      final outside = writeOutside('notes.txt', '外部正文\n');
      final guard = files()..allowReadOnlyFiles([outside]);

      expect(await guard.read(outside), '外部正文\n');
      expect(guard.readOnlyFiles, {p.normalize(outside)});

      await expectLater(
        guard.write(outside, '改写'),
        throwsA(isA<VibeToolException>()),
      );
      expect(File(outside).readAsStringSync(), '外部正文\n');

      await expectLater(
        guard.edit(outside, '外部正文', '改写'),
        throwsA(isA<VibeToolException>()),
      );
      expect(File(outside).readAsStringSync(), '外部正文\n');
    });

    test('the whitelist does not extend listing or search', () async {
      writeOutside('notes.txt', '外部正文\n');
      final guard = files()..allowReadOnlyFiles([other.path]);

      await expectLater(
        guard.list(path: other.path),
        throwsA(isA<VibeToolException>()),
      );
      await expectLater(
        guard.searchText('外部正文', path: other.path),
        throwsA(isA<VibeToolException>()),
      );
    });

    test('a directory on the whitelist cannot be read', () async {
      final guard = files()..allowReadOnlyFiles([other.path]);

      await expectLater(
        guard.read(other.path),
        throwsA(
          isA<VibeToolException>().having(
            (error) => error.code,
            'code',
            'escape',
          ),
        ),
      );
    });

    test('paths are normalised before they enter the whitelist', () async {
      final outside = writeOutside('notes.txt', '外部正文\n');
      final messy = p.join(other.path, '..', 'other', 'notes.txt');
      final guard = files()
        ..allowReadOnlyFiles([messy, 'relative/ignored.txt']);

      expect(guard.readOnlyFiles, hasLength(1));
      expect(await guard.read(outside), '外部正文\n');
      // 正斜杠写法也应命中同一条目。
      expect(await guard.read(outside.replaceAll('\\', '/')), '外部正文\n');
    });

    test('project files never enter the whitelist', () async {
      final inside = File(p.join(project.path, 'main.py'))
        ..writeAsStringSync('print(1)\n');
      final guard = files()..allowReadOnlyFiles([inside.path, 'main.py']);

      expect(guard.readOnlyFiles, isEmpty);
      expect(await guard.read('main.py'), 'print(1)\n');
    });

    test('a symlink is rejected even when its target is allowlisted', () async {
      final target = writeOutside('real.txt', '外部正文\n');
      final link = Link(p.join(other.path, 'link.txt'));
      try {
        link.createSync(target);
      } on FileSystemException {
        // 某些 Windows 环境不允许建符号链接，跳过这一条。
        return;
      }

      final guard = files()..allowReadOnlyFiles([link.path, target]);

      // 通过链接读被拒绝。
      await expectLater(
        guard.read(link.path),
        throwsA(
          isA<VibeToolException>().having(
            (error) => error.code,
            'code',
            'escape',
          ),
        ),
      );
      // 直接读真实路径仍然可以。
      expect(await guard.read(target), '外部正文\n');
    });

    test('the whitelist is capped', () async {
      final guard = files();
      final paths = [
        for (var index = 0; index <= VibeProjectFiles.maxReadOnlyFiles; index++)
          p.join(other.path, 'f$index.txt'),
      ];

      guard.allowReadOnlyFiles(paths);

      expect(guard.readOnlyFiles, hasLength(VibeProjectFiles.maxReadOnlyFiles));
    });
  });

  group('controller read_file', () {
    late Directory sessionsDir;

    setUp(() {
      sessionsDir = Directory(p.join(root.path, 'sessions'));
    });

    VibeCodingController build(_FakeRelay relay) => VibeCodingController(
      api: ApiClient(transport: relay.client),
      tokenProvider: () => 'local-token',
      projectRoot: project.path,
      projectName: 'proj',
      language: 'python',
      maxRounds: 4,
    );

    Future<void> settle(VibeCodingController controller) async {
      for (var i = 0; i < 500 && controller.phase != VibePhase.succeeded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(
        controller.phase,
        VibePhase.succeeded,
        reason: controller.lastError,
      );
    }

    test('reads an allowlisted outside file through the tool', () async {
      final outside = writeOutside('notes.txt', '外部正文\n');
      final relay = _FakeRelay()
        ..chatReplies.addAll([_readCall('c1', outside), _textReply('读到了。')]);
      final controller = build(relay)..allowReadOnlyFiles([outside]);

      controller.send('看看附件');
      await settle(controller);

      final tool = controller.messages
          .firstWhere((message) => message.tool != null)
          .tool!;
      expect(tool.status, VibeToolStatus.ok);
      expect(tool.result, contains('notes.txt'));
      final reply = (relay.chatBodies.last['messages'] as List)
          .cast<Map<String, dynamic>>()
          .lastWhere((entry) => entry['role'] == 'tool');
      expect(reply['content'], '外部正文\n');
    });

    test('still refuses an outside file that is not allowlisted', () async {
      final outside = writeOutside('notes.txt', '外部正文\n');
      final relay = _FakeRelay()
        ..chatReplies.addAll([_readCall('c1', outside), _textReply('读不到。')]);
      final controller = build(relay);

      controller.send('看看附件');
      await settle(controller);

      final tool = controller.messages
          .firstWhere((message) => message.tool != null)
          .tool!;
      expect(tool.status, VibeToolStatus.error);
      expect(tool.result, contains('相对路径'));
    });

    test('keeps the old behaviour for project relative paths', () async {
      File(p.join(project.path, 'main.py')).writeAsStringSync('print(1)\n');
      final relay = _FakeRelay()
        ..chatReplies.addAll([_readCall('c1', 'main.py'), _textReply('好。')]);
      final controller = build(relay);

      controller.send('读 main.py');
      await settle(controller);

      final tool = controller.messages
          .firstWhere((message) => message.tool != null)
          .tool!;
      expect(tool.status, VibeToolStatus.ok);
      expect(tool.result, contains('main.py'));
    });

    test('facade registers workspace attachments before sending', () async {
      final store = FileAgentSessionStore(root: sessionsDir);
      await store.load();
      final meta = await store.create('p1');
      final outside = writeOutside('notes.txt', '外部正文\n');
      File(p.join(project.path, 'local.txt')).writeAsStringSync('项目内\n');

      final relay = _FakeRelay()
        ..chatReplies.addAll([
          _readCall('c1', outside),
          _readCall('c2', 'local.txt'),
          _textReply('两个都读了。'),
        ]);
      final facade = await VibeAgentRuntime(
        api: ApiClient(transport: relay.client),
        tokenProvider: () => 'local-token',
        sessions: store,
        projectRootOf: (_) => project.path,
        languageOf: (_) => 'python',
      ).open('p1', meta.id);

      await facade.send(
        '看这两个文件',
        attachedPaths: [outside, 'local.txt'],
        permission: AgentPermissionMode.autoAcceptEdits,
      );
      for (var i = 0; i < 600 && facade.state != AgentRunState.idle; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await facade.flush();

      final user = facade.messages.firstWhere(
        (message) => message.role == 'user',
      );
      expect(user.text, contains(outside.replaceAll('\\', '/')));
      expect(user.text, contains('- local.txt'));
      expect(user.text, isNot(contains('外部正文')));

      final tools = facade.messages
          .where((message) => message.role == 'tool')
          .toList();
      expect(tools, hasLength(2));
      expect(tools.first.isError, isFalse);
      expect(tools.last.isError, isFalse);
    });

    test('an outside attachment is not persisted as a read grant', () async {
      final store = FileAgentSessionStore(root: sessionsDir);
      await store.load();
      final meta = await store.create('p1');
      final outside = writeOutside('notes.txt', '外部正文\n');
      final relay = _FakeRelay()
        ..chatReplies.addAll([_readCall('c1', outside), _textReply('好。')]);
      final runtime = VibeAgentRuntime(
        api: ApiClient(transport: relay.client),
        tokenProvider: () => 'local-token',
        sessions: store,
        projectRootOf: (_) => project.path,
      );
      final facade = await runtime.open('p1', meta.id);

      await facade.send(
        '看附件',
        attachedPaths: [outside],
        permission: AgentPermissionMode.autoAcceptEdits,
      );
      for (var i = 0; i < 600 && facade.state != AgentRunState.idle; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await facade.flush();

      final saved = await store.read(meta.id);
      expect(
        saved.messages.first['text'],
        contains(outside.replaceAll('\\', '/')),
      );
      // 会话文件里只有消息与历史，没有任何白名单字段。
      final raw = File(
        p.join(sessionsDir.path, '${meta.id}.jsonl'),
      ).readAsStringSync();
      expect(raw, isNot(contains('readOnly')));
      expect(raw, isNot(contains('allowList')));
    });
  });
}

Map<String, dynamic> _textReply(String text) => {
  'model': 'demo-model',
  'message': {'role': 'assistant', 'content': text},
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
      final body = await utf8.decoder.bind(bodyStream).join();
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
}
