import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';

import 'support/ai_relay_fixture.dart';

void main() {
  late Directory root;

  setUp(() {
    StudioProfile.current = null;
    root = Directory.systemTemp.createTempSync('vibe-search-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void writeFile(String relative, String content) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  VibeProjectFiles files() => VibeProjectFiles(projectRoot: root.path);

  test('finds matches with relative path and 1-based line numbers', () async {
    writeFile('lib/main.py', 'import os\nprint("TODO")\n');
    writeFile('lib/util.py', '# nothing here\n');

    final matches = await files().searchText('todo');

    expect(matches, hasLength(1));
    expect(matches.single.path, 'lib/main.py');
    expect(matches.single.line, 2);
    expect(matches.single.text, 'print("TODO")');
  });

  test('is case-insensitive by default and honours caseSensitive', () async {
    writeFile('a.txt', 'Needle\nneedle\n');

    expect(await files().searchText('NEEDLE'), hasLength(2));
    expect(await files().searchText('NEEDLE', caseSensitive: true), isEmpty);
    expect(
      await files().searchText('needle', caseSensitive: true),
      hasLength(1),
    );
  });

  test('treats the pattern as literal text unless regex is set', () async {
    writeFile('a.txt', 'a.c\nabc\n');

    expect(await files().searchText('a.c'), hasLength(1));
    expect(await files().searchText('a.c', regex: true), hasLength(2));
  });

  test('rejects an invalid regular expression', () async {
    writeFile('a.txt', 'x\n');
    expect(
      () => files().searchText('([', regex: true),
      throwsA(isA<VibeToolException>()),
    );
  });

  test('rejects an empty or over-long pattern', () async {
    expect(() => files().searchText('   '), throwsA(isA<VibeToolException>()));
    expect(
      () => files().searchText('x' * 201),
      throwsA(isA<VibeToolException>()),
    );
  });

  test('caps results and reports the cap as a limit', () async {
    writeFile('a.txt', List.filled(10, 'hit').join('\n'));

    expect(await files().searchText('hit', maxResults: 3), hasLength(3));
    expect(await files().searchText('hit', maxResults: 10000), hasLength(10));
  });

  test('scopes to a subdirectory or a single file', () async {
    writeFile('src/a.txt', 'hit\n');
    writeFile('test/b.txt', 'hit\n');

    final scoped = await files().searchText('hit', path: 'src');
    expect(scoped.map((m) => m.path), ['src/a.txt']);

    final single = await files().searchText('hit', path: 'test/b.txt');
    expect(single.map((m) => m.path), ['test/b.txt']);
  });

  test('skips hidden, excluded and linked directories', () async {
    writeFile('.hidden/a.txt', 'hit\n');
    writeFile('node_modules/b.txt', 'hit\n');
    writeFile('build/c.txt', 'hit\n');
    writeFile('keep/d.txt', 'hit\n');

    final matches = await files().searchText('hit');

    expect(matches.map((m) => m.path), ['keep/d.txt']);
  });

  test('skips binary files instead of failing the search', () async {
    final binary = File(p.join(root.path, 'blob.bin'))
      ..writeAsBytesSync([104, 105, 116, 0, 1, 2]);
    writeFile('a.txt', 'hit\n');

    final matches = await files().searchText('hit');

    expect(binary.existsSync(), isTrue);
    expect(matches.map((m) => m.path), ['a.txt']);
  });

  test('rejects a path that escapes the project', () async {
    expect(
      () => files().searchText('hit', path: '../'),
      throwsA(isA<VibeToolException>()),
    );
  });

  test('the tool spec exposes pattern, path and result limits', () {
    final spec = vibeToolSpecs().firstWhere(
      (entry) => (entry['function'] as Map)['name'] == 'search_text',
    );
    final parameters =
        (spec['function'] as Map)['parameters'] as Map<String, dynamic>;
    expect(parameters['required'], ['pattern']);
    expect(
      (parameters['properties'] as Map).keys,
      containsAll(['pattern', 'path', 'maxResults', 'regex', 'caseSensitive']),
    );
  });

  test('the controller answers search_text with real matches', () async {
    writeFile('lib/main.py', 'value = 1\nprint(value)\n');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolReply('call-search', 'search_text', {'pattern': 'value'}),
        _textReply('找到 2 处'),
      ]);
    final controller = VibeCodingController(
      api: ApiClient(transport: relay.client),
      tokenProvider: () => 'local-token',
      projectRoot: root.path,
      projectName: 'demo',
      language: 'python',
      maxRounds: 4,
    );

    controller.send('找一下 value 在哪里');
    for (var i = 0; i < 500 && controller.phase != VibePhase.succeeded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(controller.phase, VibePhase.succeeded, reason: controller.lastError);
    final toolMessage = controller.messages.firstWhere(
      (message) => message.tool?.toolName == 'search_text',
    );
    expect(toolMessage.tool?.result, '2 处匹配');
    final toolReply = (relay.chatBodies.last['messages'] as List)
        .cast<Map<String, dynamic>>()
        .lastWhere((entry) => entry['role'] == 'tool');
    expect(toolReply['content'], contains('lib/main.py:1: value = 1'));
    expect(toolReply['content'], contains('lib/main.py:2: print(value)'));
  });
}

Map<String, dynamic> _textReply(String text) => {
  'model': 'demo-model',
  'message': {'role': 'assistant', 'content': text},
  'aiGenerated': true,
};

Map<String, dynamic> _toolReply(
  String id,
  String name,
  Map<String, Object?> arguments,
) => {
  'model': 'demo-model',
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
