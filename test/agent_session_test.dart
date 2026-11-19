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
    expect(after.split('\n').where((row) => row.contains('"hdr"')).length, 1);
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

    final earlier = await store.readBefore(meta.id, beforeId: 'm90', limit: 60);
    expect(earlier.messages.length, 60);
    expect(earlier.messages.last['id'], 'm89');
    expect(earlier.messages.first['id'], 'm30');
    expect(earlier.hasEarlier, isTrue);

    final oldest = await store.readBefore(meta.id, beforeId: 'm30', limit: 60);
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

  test('compacts a file whose bad lines dominate', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '好行'));
    await store.flush();
    jsonlOf(meta.id).writeAsStringSync(
      '${jsonlOf(meta.id).readAsStringSync()}'
      '{坏行1\n{坏行2\n{坏行3\n',
    );

    await store.compactIfNeeded(meta.id);

    final raw = jsonlOf(meta.id).readAsStringSync();
    expect(raw, isNot(contains('坏行')));
    final page = await store.readTail(meta.id);
    expect(page.messages.single['text'], '好行');
  });

  test('decodes a large history snapshot and caps it', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0'));
    final filler = 'x' * 600;
    await store.writeHistory(meta.id, [
      for (var index = 0; index < 600; index++)
        {'role': 'assistant', 'content': '$index $filler'},
    ]);
    await store.flush();
    // 这条快照超过 200 KB，解析走独立 isolate。
    expect(jsonlOf(meta.id).lengthSync(), greaterThan(200 * 1024));

    final history = await store.readHistory(meta.id);
    expect(history.length, 200);
    expect(history.last['content'], startsWith('599 '));
  });

  test('opening the tail page leaves the full-file repair alone', () async {
    // 回归：打开会话的路径曾经顺带扫全文件（读全文 + 逐行 JSON 解码），
    // 大会话第一次打开会把界面 isolate 占住几百毫秒。
    // 现在扫描只挂在 read() 上，readTail 不再触发它。
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '好行'));
    for (var index = 1; index <= 80; index++) {
      await store.appendMessage(meta.id, message('m$index', '第 $index 条'));
    }
    await store.flush();
    jsonlOf(meta.id).writeAsStringSync(
      '${jsonlOf(meta.id).readAsStringSync()}'
      '{坏行1\n{坏行2\n{坏行3\n',
    );
    final before = jsonlOf(meta.id).readAsStringSync();

    final page = await store.readTail(meta.id);
    await store.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(page.messages.length, 60);
    expect(page.hasEarlier, isTrue);
    expect(
      jsonlOf(meta.id).readAsStringSync(),
      before,
      reason: 'readTail 不该触发全文件重写',
    );
  });

  test('a corrupt-heavy file is still repaired from read()', () async {
    // 不在打开路径上扫描，不等于放弃修复：read() 仍会修复坏行过半的文件。
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '好行'));
    await store.flush();
    jsonlOf(meta.id).writeAsStringSync(
      '${jsonlOf(meta.id).readAsStringSync()}'
      '{坏行1\n{坏行2\n{坏行3\n',
    );

    final transcript = await store.read(meta.id);
    expect(transcript.messages.single['text'], '好行');
    await store.flush();
    // 后台修复是异步的：等它落盘后坏行应消失。
    for (var i = 0; i < 100; i++) {
      if (!jsonlOf(meta.id).readAsStringSync().contains('坏行')) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(jsonlOf(meta.id).readAsStringSync(), isNot(contains('坏行')));
  });

  test(
    'a large corrupt-heavy file is scanned off the calling isolate',
    () async {
      // 超过 isolate 阈值的文件交给独立 isolate，不占界面 isolate 的一帧。
      final meta = await store.create('p1');
      await store.appendMessage(meta.id, message('m0', '好行'));
      await store.flush();
      final padding = 'x' * (210 * 1024);
      final junk = List.filled(4, 'junk line that is not json').join('\n');
      jsonlOf(meta.id).writeAsStringSync(
        '${jsonlOf(meta.id).readAsStringSync()}'
        '${jsonEncode({'t': 'm', 'v': message('m1', padding)})}\n'
        '$junk\n',
      );
      expect(jsonlOf(meta.id).lengthSync(), greaterThan(200 * 1024));

      await store.compactIfNeeded(meta.id);

      final raw = jsonlOf(meta.id).readAsStringSync();
      expect(raw, isNot(contains('junk line')));
      expect(raw, contains(padding.substring(0, 20)));
      // 重写后每条记录占一行，行内不能出现裸换行。
      for (final line in raw.split('\n')) {
        if (line.trim().isEmpty) continue;
        expect(line, startsWith('{"t":'));
      }
    },
  );

  test('a multi-MB history snapshot is skipped when paging', () async {
    // 回归：_readPage 曾经对每一行都做 JSON 解码，包括几 MB 的 hs 快照；
    // 反向分页每翻一页都要越过它。现在按字节看前缀直接跳过。
    final meta = await store.create('p1');
    for (var index = 0; index < 80; index++) {
      await store.appendMessage(meta.id, message('m$index', '第 $index 条'));
    }
    await store.writeHistory(meta.id, [
      for (var index = 0; index < 400; index++)
        {'role': 'assistant', 'content': 'h$index ${'y' * 10000}'},
    ]);
    await store.flush();
    expect(jsonlOf(meta.id).lengthSync(), greaterThan(3 * 1024 * 1024));

    final page = await store.readTail(meta.id);
    expect(page.messages.length, 60);
    expect(page.hasEarlier, isTrue);
    expect(page.messages.map((entry) => entry['text']).last, '第 79 条');

    // 翻上一页要越过整条快照，结果仍要正确。
    final oldest = page.messages.first['id'] as String;
    final previous = await store.readBefore(meta.id, beforeId: oldest);
    expect(previous.messages.length, 20);
    expect(previous.messages.first['text'], '第 0 条');
    expect(previous.hasEarlier, isFalse);
  });

  test(
    'a single huge newline-free line pages without quadratic copies',
    () async {
      // 回归：_LineTail 以前每读一块就 [...tail, ...carry]，
      // 一条 4 MB 行要多拷几 MB × 块数。现在按块收集、末尾拼一次。
      final meta = await store.create('p1');
      await store.appendMessage(meta.id, message('m0', '你好'));
      await store.writeHistory(meta.id, [
        for (var index = 0; index < 800; index++)
          {'role': 'assistant', 'content': 'h$index ${'z' * 6000}'},
      ]);
      await store.flush();
      expect(jsonlOf(meta.id).lengthSync(), greaterThan(4 * 1024 * 1024));

      final page = await store.readTail(meta.id);
      expect(page.messages.single['id'], 'm0');
      expect(page.messages.single['text'], '你好');
      expect(page.hasEarlier, isFalse);
    },
  );

  test(
    'tolerates non-canonical record formatting without losing history',
    () async {
      // 回归：按字节比对前缀曾不容忍前导空白，手工写的 hs 行会被静默跳过，
      // readHistory 返回空表。老解码器会 trim 后整行解码，这些写法都能读。
      final variants = <String, String>{
        'canonical': '{"t":"hs","v":[{"role":"assistant","content":"好"}]}',
        'leading space': ' {"t":"hs","v":[{"role":"assistant","content":"好"}]}',
        'leading tab': '\t{"t":"hs","v":[{"role":"assistant","content":"好"}]}',
        'space between keys':
            '{ "t" : "hs" , "v" : [{"role":"assistant","content":"好"}] }',
        'reordered keys': '{"v":[{"role":"assistant","content":"好"}],"t":"hs"}',
        'reordered with space':
            '{ "v" : [ { "role" : "assistant", "content" : "好" } ] , "t" : "hs" }',
      };

      for (final entry in variants.entries) {
        final dir = Directory.systemTemp.createTempSync('variant-');
        try {
          final local = FileAgentSessionStore(root: dir);
          await local.load();
          final meta = await local.create('p1');
          await local.appendMessage(meta.id, message('m0'));
          await local.flush();
          final file = File(p.join(dir.path, '${meta.id}.jsonl'));
          file.writeAsStringSync('${file.readAsStringSync()}${entry.value}\n');

          final history = await local.readHistory(meta.id);
          expect(history.single['content'], '好', reason: entry.key);
          // 分页也不能把这条 hs 当成消息。
          final page = await local.readTail(meta.id);
          expect(page.messages.single['id'], 'm0', reason: entry.key);
          await local.flush();
        } finally {
          try {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Windows may retain a file handle briefly after the store closes.
          }
        }
      }
    },
  );

  test(
    'an empty history snapshot does not hide a message from paging',
    () async {
      final meta = await store.create('p1');
      await store.appendMessage(meta.id, message('m0', '甲'));
      await store.flush();
      final file = jsonlOf(meta.id);
      file.writeAsStringSync(
        '${file.readAsStringSync()}'
        '{"t":"hs","v":[]}\n',
      );

      final page = await store.readTail(meta.id);
      expect(page.messages.single['text'], '甲');
    },
  );

  test('garbage before the record tag is ignored, not fatal', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '甲'));
    await store.flush();
    final file = jsonlOf(meta.id);
    file.writeAsStringSync(
      '${file.readAsStringSync()}'
      '[[[garbage not json\n'
      '{"t":"hs","v":[{"role":"x"}]}\n',
    );

    // 结构不对的行按老规矩当坏行，不影响最后一条好行。
    final history = await store.readHistory(meta.id);
    expect(history.single['role'], 'x');
    expect((await store.readTail(meta.id)).messages.single['id'], 'm0');
  });

  test(
    'a truncated latest history snapshot keeps the older valid one',
    () async {
      // 回归：早先版本只取最新一条 hs 的字节，解码失败就返回空表，
      // 把还完整的老快照一起挡住了。基线行为是一直往前找到能读的。
      final meta = await store.create('p1');
      await store.appendMessage(meta.id, message('m0', '甲'));
      await store.writeHistory(meta.id, [
        {'role': 'assistant', 'content': 'OLD'},
      ]);
      await store.flush();
      final file = jsonlOf(meta.id);
      // 模拟崩溃：最新一条 hs 写到一半就断了。
      file.writeAsStringSync(
        '${file.readAsStringSync()}'
        '{"t":"hs","v":[{"role":"assistant","content":"NEW-cut',
      );

      final history = await store.readHistory(meta.id);
      expect(history.single['content'], 'OLD');
    },
  );

  test(
    'a truncated latest history snapshot over the isolate threshold',
    () async {
      // 同上，但截断的快照超过 200 KB，会走独立 isolate。
      // 那里抛的 FormatException 被包了一层，必须当坏快照而不是往上抛。
      final meta = await store.create('p1');
      await store.appendMessage(meta.id, message('m0', '甲'));
      await store.writeHistory(meta.id, [
        {'role': 'assistant', 'content': 'OLD'},
      ]);
      await store.flush();
      final file = jsonlOf(meta.id);
      final big = 'z' * (300 * 1024);
      file.writeAsStringSync(
        '${file.readAsStringSync()}'
        '{"t":"hs","v":[{"role":"assistant","content":"$big',
      );

      final history = await store.readHistory(meta.id);
      expect(history.single['content'], 'OLD');
    },
  );

  test('several consecutive broken snapshots still fall back', () async {
    final meta = await store.create('p1');
    await store.writeHistory(meta.id, [
      {'role': 'assistant', 'content': 'OLD'},
    ]);
    await store.flush();
    final file = jsonlOf(meta.id);
    file.writeAsStringSync(
      '${file.readAsStringSync()}'
      '{"t":"hs","v":[{"broken":1\n'
      '{"t":"hs","v":[{"broken":2\n'
      '{"t":"hs","v":[{"broken":3',
    );

    final history = await store.readHistory(meta.id);
    expect(history.single['content'], 'OLD');
  });

  test('a header line is not mistaken for an empty history', () async {
    // 回归：把非 hs 当成“空历史”就会提前停下，把老快照漏掉。
    final meta = await store.create('p1');
    await store.writeHistory(meta.id, [
      {'role': 'assistant', 'content': 'OLD'},
    ]);
    await store.flush();
    final file = jsonlOf(meta.id);
    file.writeAsStringSync(
      '${file.readAsStringSync()}'
      '{"t":"hdr","v":{"id":"x","projectId":"p1"}}\n',
    );

    final history = await store.readHistory(meta.id);
    expect(history.single['content'], 'OLD');
  });

  test('escaped key names are decoded like the old reader', () async {
    final meta = await store.create('p1');
    await store.flush();
    jsonlOf(meta.id).writeAsStringSync(
      '${jsonlOf(meta.id).readAsStringSync()}'
      '{"\\u0074":"hs","v":[{"role":"assistant","content":"ESC"}]}\n',
    );

    final history = await store.readHistory(meta.id);
    expect(history.single['content'], 'ESC');
  });

  test('a non-canonical message line is still paged', () async {
    // 分页的快捷路径只跳过 canonical 的 hs/hdr；认不出来就照旧解码，
    // 不能把格式不规范的消息当成快照丢掉。
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0', '甲'));
    await store.flush();
    final file = jsonlOf(meta.id);
    file.writeAsStringSync(
      '${file.readAsStringSync()}'
      '{ "t" : "m" , "v" : { "id" : "m1" , "role" : "user" , "text" : "乙" } }\n',
    );

    final page = await store.readTail(meta.id);
    expect(page.messages.map((entry) => entry['id']), ['m0', 'm1']);
  });

  test(
    'more than eight non-canonical message lines do not hide history',
    () async {
      // 回归：曾先把候选行攒够 8 条再解码，超过 8 条不规范的行就把
      // 后面的有效快照甩掉了。现在边读边解，碰到第一条有效 hs 才停。
      final meta = await store.create('p1');
      await store.writeHistory(meta.id, [
        {'role': 'assistant', 'content': 'VALID'},
      ]);
      await store.flush();
      final file = jsonlOf(meta.id);
      final junk = List.generate(
        12,
        (index) =>
            '{ "t" : "m" , "v" : { "id" : "x$index" , "role" : "user" } }',
      ).join('\n');
      file.writeAsStringSync('${file.readAsStringSync()}\n$junk\n');

      final history = await store.readHistory(meta.id);
      expect(history.single['content'], 'VALID');
    },
  );

  test(
    'more than eight non-canonical header lines do not hide history',
    () async {
      final meta = await store.create('p1');
      await store.writeHistory(meta.id, [
        {'role': 'assistant', 'content': 'VALID'},
      ]);
      await store.flush();
      final file = jsonlOf(meta.id);
      final junk = List.generate(
        12,
        (index) => '{ "t" : "hdr" , "v" : { "n" : $index } }',
      ).join('\n');
      file.writeAsStringSync('${file.readAsStringSync()}\n$junk\n');

      final history = await store.readHistory(meta.id);
      expect(history.single['content'], 'VALID');
    },
  );

  test('the newest valid empty snapshot stops the search', () async {
    // 最新一条有效快照是空的：就该返回空。回退到老的非空快照是错的。
    final meta = await store.create('p1');
    await store.writeHistory(meta.id, [
      {'role': 'assistant', 'content': 'OLD'},
    ]);
    await store.writeHistory(meta.id, const []);
    await store.flush();

    final history = await store.readHistory(meta.id);
    expect(history, isEmpty);
  });

  test('only the newest snapshot is returned, not an older one', () async {
    // 回归：先攒候选再解码会读好几份大快照；而且必须拿到最新的那份。
    // 只断言内容，不断言耗时：耗时随机器变，内容不会。
    final meta = await store.create('p1');
    for (var round = 0; round < 4; round++) {
      await store.writeHistory(meta.id, [
        for (var index = 0; index < 100; index++)
          {'role': 'assistant', 'content': 'snap$round-$index ${'q' * 10000}'},
      ]);
      await store.flush();
    }
    final file = jsonlOf(meta.id);
    expect(file.lengthSync(), greaterThan(3 * 1024 * 1024));

    final history = await store.readHistory(meta.id);

    expect(history.length, 100);
    // 最新一轮是 round 3：首条与末条都必须是它，不能混入旧快照。
    expect(history.first['content'], startsWith('snap3-0 '));
    expect(history.last['content'], startsWith('snap3-99 '));
    expect(
      history.where((entry) => '${entry['content']}'.startsWith('snap2-')),
      isEmpty,
      reason: '混进了上一轮的快照',
    );
  });

  test('a session with no history snapshot reads as empty', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, message('m0'));
    await store.flush();
    final file = jsonlOf(meta.id);
    file.writeAsStringSync(
      const LineSplitter()
          .convert(file.readAsStringSync())
          .where((line) => !line.contains('"hs"'))
          .join('\n'),
    );

    expect(await store.readHistory(meta.id), isEmpty);
    expect((await store.readTail(meta.id)).messages.length, 1);
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
    final names =
        root
            .listSync()
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toList()
          ..sort();
    expect(names, ['${meta.id}.jsonl', 'index.json']);
  });
}
