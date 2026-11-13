import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/session/agent_session.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('agent-session-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<FileAgentSessionStore> open() async {
    final store = FileAgentSessionStore(root: root);
    await store.load();
    return store;
  }

  test('creates sessions with the default title and lists them', () async {
    final store = await open();
    final meta = await store.create('p1');

    expect(meta.projectId, 'p1');
    expect(meta.title, AgentSessionStore.defaultTitle);
    expect(store.sessionsOf('p1').map((m) => m.id), [meta.id]);
    expect(store.sessionsOf('p2'), isEmpty);
    expect(store.metaOf(meta.id)?.title, AgentSessionStore.defaultTitle);
  });

  test('lists a project by updatedAt descending', () async {
    final store = await open();
    final first = await store.create('p1');
    final second = await store.create('p1');
    final other = await store.create('p2');

    await store.rename(first.id, '较早改名的');

    expect(store.sessionsOf('p1').map((m) => m.id), [first.id, second.id]);
    expect(store.sessionsOf('p2').map((m) => m.id), [other.id]);
  });

  test('survives a reload from disk', () async {
    final store = await open();
    final meta = await store.create('p1', title: '会话一');
    await store.write(
      meta.id,
      const AgentTranscript(
        messages: [
          {'id': 'm0', 'role': 'user', 'text': '你好'},
        ],
        history: [
          {'role': 'user', 'content': '你好'},
        ],
      ),
    );

    final reopened = await open();

    expect(reopened.sessionsOf('p1').single.title, '会话一');
    final transcript = await reopened.read(meta.id);
    expect(transcript.messages.single['text'], '你好');
    expect(transcript.history.single['content'], '你好');
  });

  test('writes through a temp file and leaves no leftovers', () async {
    final store = await open();
    final meta = await store.create('p1');
    await store.write(
      meta.id,
      const AgentTranscript(
        messages: [
          {'id': 'm0', 'role': 'user', 'text': 'x'},
        ],
      ),
    );

    final names = root
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .toList();
    expect(names, ['${meta.id}.json']);
  });

  test('ignores a corrupt session file', () async {
    File(p.join(root.path, 'broken.json')).writeAsStringSync('{not json');
    final store = await open();

    expect(store.sessionsOf('p1'), isEmpty);

    final meta = await store.create('p1');
    expect(store.sessionsOf('p1').map((m) => m.id), [meta.id]);
  });

  test('renames and deletes', () async {
    final store = await open();
    final meta = await store.create('p1');

    await store.rename(meta.id, '  带  空格的名字  ');
    expect(store.metaOf(meta.id)?.title, '带 空格的名字');

    await store.delete(meta.id);
    expect(store.metaOf(meta.id), isNull);
    expect(File(p.join(root.path, '${meta.id}.json')).existsSync(), isFalse);

    final reopened = await open();
    expect(reopened.sessionsOf('p1'), isEmpty);
  });

  test('reads a missing session as empty', () async {
    final store = await open();
    final transcript = await store.read('nope');
    expect(transcript.messages, isEmpty);
    expect(transcript.history, isEmpty);
  });

  test('truncates an over-long title', () async {
    final store = await open();
    final meta = await store.create('p1', title: 'x' * 200);
    expect(meta.title.length, 61);
    expect(meta.title.endsWith('…'), isTrue);
  });

  test('ignores non-object entries when reading a transcript', () async {
    final store = await open();
    final meta = await store.create('p1');
    File(p.join(root.path, '${meta.id}.json')).writeAsStringSync(
      jsonEncode({
        ...meta.toJson(),
        'messages': [
          {'id': 'm0', 'role': 'user', 'text': 'ok'},
          42,
          'skip',
        ],
        'history': null,
      }),
    );

    final transcript = await store.read(meta.id);
    expect(transcript.messages.single['id'], 'm0');
    expect(transcript.history, isEmpty);
  });
}
