import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/session/agent_session.dart';

void main() {
  late Directory root;
  late FileAgentSessionStore store;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('agent-session-');
    store = FileAgentSessionStore(root: root);
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

  FileAgentSessionStore fresh() => FileAgentSessionStore(root: root);

  File jsonlOf(String id) => File(p.join(root.path, '$id.jsonl'));

  Map<String, Object?> message(String id, [String text = '消息']) => {
    'id': id,
    'role': 'user',
    'text': text,
  };

  test('creates sessions with the default title and lists them', () async {
    final meta = await store.create('p1');

    expect(meta.projectId, 'p1');
    expect(meta.title, AgentSessionStore.defaultTitle);
    expect(store.sessionsOf('p1').map((m) => m.id), [meta.id]);
    expect(store.sessionsOf('p2'), isEmpty);
    expect(store.metaOf(meta.id)?.title, AgentSessionStore.defaultTitle);
    // 索引与 jsonl 头都已落地。
    expect(File(p.join(root.path, 'index.json')).existsSync(), isTrue);
    expect(jsonlOf(meta.id).existsSync(), isTrue);
  });

  test('lists a project by updatedAt descending', () async {
    final first = await store.create('p1');
    final second = await store.create('p1');
    final other = await store.create('p2');

    await store.rename(first.id, '较早改名的');

    expect(store.sessionsOf('p1').map((m) => m.id), [first.id, second.id]);
    expect(store.sessionsOf('p2').map((m) => m.id), [other.id]);
  });

  test('survives a reload from disk', () async {
    final meta = await store.create('p1', title: '会话一');
    await store.appendMessage(meta.id, message('m0', '你好'));
    await store.writeHistory(meta.id, [
      {'role': 'user', 'content': '你好'},
    ]);
    await store.flush();

    final reopened = fresh();
    await reopened.load();

    expect(reopened.sessionsOf('p1').single.title, '会话一');
    final transcript = await reopened.read(meta.id);
    expect(transcript.messages.single['text'], '你好');
    expect(transcript.history.single['content'], '你好');
    await reopened.flush();
  });

  test('index alone drives the list, the message file is untouched', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0'));
    await store.flush();
    // 列表只读索引：把 jsonl 挪走之后列表照旧。
    jsonlOf(meta.id).renameSync('${jsonlOf(meta.id).path}.away');

    final reopened = fresh();
    await reopened.load();

    expect(reopened.sessionsOf('p1').single.id, meta.id);
    expect(reopened.sessionsOf('p1').single.messageCount, 1);
  });

  test('appends one line per message instead of rewriting the file', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '一'));
    await store.appendMessage(meta.id, message('m1', '二'));
    await store.flush();
    final before = jsonlOf(meta.id).readAsStringSync();
    final lengthBefore = jsonlOf(meta.id).lengthSync();

    await store.appendMessage(meta.id, message('m2', '三'));
    await store.flush();

    final after = jsonlOf(meta.id).readAsStringSync();
    expect(after.startsWith(before), isTrue);
    expect(jsonlOf(meta.id).lengthSync(), greaterThan(lengthBefore));
    // 一行一条记录，没有第二次写头。
    expect(
      after.split('\n').where((row) => row.contains('"hdr"')).length,
      1,
    );
  });

  test('reads the tail and pages backwards', () async {
    final meta = await store.create('p1');
    for (var index = 0; index < 150; index++) {
      await store.appendMessage(
        meta.id,
        message('m$index', '第 $index 条 $index ${'x' * 200}'),
      );
    }
    await store.flush();

    final tail = await store.readTail(meta.id, limit: 60);
    expect(tail.messages.length, 60);
    expect(tail.hasEarlier, isTrue);
    expect(tail.messages.last['id'], 'm149');
    expect(tail.messages.first['id'], 'm90');

    final earlier = await store.readBefore(
      meta.id,
      beforeId: 'm90',
      limit: 60,
    );
    expect(earlier.messages.length, 60);
    expect(earlier.messages.last['id'], 'm89');
    expect(earlier.messages.first['id'], 'm30');
    expect(earlier.hasEarlier, isTrue);

    final oldest = await store.readBefore(
      meta.id,
      beforeId: 'm30',
      limit: 60,
    );
    expect(oldest.messages.length, 30);
    expect(oldest.messages.first['id'], 'm0');
    expect(oldest.hasEarlier, isFalse);
  });

  test('skips a corrupt line and keeps the rest', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '一'));
    await store.flush();
    jsonlOf(meta.id).writeAsStringSync(
      '${jsonlOf(meta.id).readAsStringSync()}{not json\n',
      mode: FileMode.append,
    );
    await store.appendMessage(meta.id, message('m1', '二'));
    await store.flush();

    final page = await store.readTail(meta.id);
    expect(page.messages.map((entry) => entry['id']), ['m0', 'm1']);
  });

  test('a truncated last line only loses that line', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '一'));
    await store.appendMessage(meta.id, message('m1', '二'));
    await store.flush();
    // 模拟写到一半崩溃：最后一行被截断，没有换行。
    final content = jsonlOf(meta.id).readAsStringSync();
    final cut = content.lastIndexOf('{"t":"m"');
    jsonlOf(meta.id).writeAsStringSync(content.substring(0, cut + 8));

    final page = await store.readTail(meta.id);
    expect(page.messages.map((entry) => entry['id']), ['m0']);

    // 崩溃后还能继续追加。
    await store.appendMessage(meta.id, message('m2', '三'));
    await store.flush();
    final reopened = fresh();
    await reopened.load();
    final after = await reopened.readTail(meta.id);
    expect(after.messages.map((entry) => entry['id']), ['m0', 'm2']);
    await reopened.flush();
  });

  test('later line with the same id wins', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '旧'));
    await store.appendMessage(meta.id, message('m0', '新'));
    await store.flush();

    final page = await store.readTail(meta.id);
    expect(page.messages.single['text'], '新');
  });

  test('migrates a legacy json file', () async {
    final legacy = AgentSessionMeta(
      id: 'legacy-1',
      projectId: 'p1',
      title: '旧会话',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );
    File(p.join(root.path, 'legacy-1.json')).writeAsStringSync(
      jsonEncode({
        ...legacy.toJson(),
        'messages': [message('m0', '旧消息')],
        'history': [
          {'role': 'user', 'content': '旧消息'},
        ],
      }),
    );

    final reopened = fresh();
    await reopened.load();
    await reopened.migrationDone;

    expect(reopened.sessionsOf('p1').single.messageCount, 1);
    expect(jsonlOf('legacy-1').existsSync(), isTrue);
    expect(File(p.join(root.path, 'legacy-1.json')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'legacy-1.json.bak')).existsSync(), isTrue);

    final tail = await reopened.readTail('legacy-1');
    expect(tail.messages.single['text'], '旧消息');
    final history = await reopened.readHistory('legacy-1');
    expect(history.single['content'], '旧消息');

    // 迁移只做一次：再启动一次不会重复转换。
    final again = fresh();
    await again.load();
    await again.migrationDone;
    expect(again.sessionsOf('p1').single.id, 'legacy-1');
    await reopened.flush();
    await again.flush();
  });

  test('reads history only when asked', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0'));
    await store.writeHistory(meta.id, [
      {'role': 'user', 'content': '问题'},
      {'role': 'assistant', 'content': '回答'},
    ]);
    await store.flush();

    final tail = await store.readTail(meta.id);
    expect(tail.messages.single['id'], 'm0');
    final history = await store.readHistory(meta.id);
    expect(history.map((entry) => entry['role']), ['user', 'assistant']);
  });

  test('ignores a corrupt legacy file', () async {
    File(p.join(root.path, 'broken.json')).writeAsStringSync('{not json');
    final reopened = fresh();
    await reopened.load();

    expect(reopened.sessionsOf('p1'), isEmpty);

    final meta = await reopened.create('p1');
    expect(reopened.sessionsOf('p1').map((m) => m.id), [meta.id]);
    await reopened.flush();
  });

  test('renames and deletes', () async {
    final meta = await store.create('p1');

    await store.rename(meta.id, '  带  空格的名字  ');
    expect(store.metaOf(meta.id)?.title, '带 空格的名字');

    await store.delete(meta.id);
    expect(store.metaOf(meta.id), isNull);
    expect(jsonlOf(meta.id).existsSync(), isFalse);
    await store.flush();

    final reopened = fresh();
    await reopened.load();
    expect(reopened.sessionsOf('p1'), isEmpty);
    await reopened.flush();
  });

  test('reads a missing session as empty', () async {
    final transcript = await store.read('nope');
    expect(transcript.messages, isEmpty);
    expect(transcript.history, isEmpty);
    expect((await store.readTail('nope')).messages, isEmpty);
    expect(await store.readHistory('nope'), isEmpty);
  });

  test('truncates an over-long title', () async {
    final meta = await store.create('p1', title: 'x' * 200);
    expect(meta.title.length, 61);
    expect(meta.title.endsWith('…'), isTrue);
  });

  test('write() still replaces the whole transcript', () async {
    final meta = await store.create('p1');
    await store.write(
      meta.id,
      AgentTranscript(
        messages: [message('m0', '甲'), message('m1', '乙')],
        history: [
          {'role': 'user', 'content': '甲'},
        ],
      ),
    );
    await store.flush();

    final transcript = await store.read(meta.id);
    expect(transcript.messages.map((entry) => entry['text']), ['甲', '乙']);
    expect(transcript.history.single['content'], '甲');
    expect(store.metaOf(meta.id)?.messageCount, 2);
    // 临时文件不留在目录里。
    final names = root
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .toList()
      ..sort();
    expect(names, ['${meta.id}.jsonl', 'index.json']);
  });
}
