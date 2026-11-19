import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/session/agent_session.dart';

void main() {
  late Directory root;
  late FileAgentSessionStore store;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('agent-session-compact-');
    store = FileAgentSessionStore(root: root);
    await store.load();
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 上偶发占用，临时目录可以留着。
    }
  });

  File fileOf(String sessionId) => File(p.join(root.path, '$sessionId.jsonl'));

  List<Map<String, dynamic>> rows(File file) => [
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];

  test('追加 25 份历史快照后只剩最后一份，消息行都在', () async {
    final meta = await store.create('p1');
    for (var index = 0; index < 5; index++) {
      await store.appendMessage(meta.id, {
        'id': 'm$index',
        'role': 'user',
        'text': '第 $index 条消息',
      });
    }

    for (var round = 0; round < 25; round++) {
      await store.writeHistory(meta.id, [
        {'role': 'user', 'content': '第 $round 轮问题'},
        {'role': 'assistant', 'content': '第 $round 轮回复'},
      ]);
    }
    await store.flush();

    final decoded = rows(fileOf(meta.id));
    final snapshots = decoded.where((row) => row['t'] == 'hs').toList();
    expect(snapshots, hasLength(1));
    final history = snapshots.single['v'] as List;
    expect((history.first as Map)['content'], '第 24 轮问题');
    // 全部消息行都在（prd AC12 的后半句）。
    final messages = decoded.where((row) => row['t'] == 'm').toList();
    expect(messages, hasLength(5));
    expect(
      [for (final row in messages) (row['v'] as Map)['id']],
      ['m0', 'm1', 'm2', 'm3', 'm4'],
    );
    expect(decoded.where((row) => row['t'] == 'hdr'), hasLength(1));

    // 重写后会话照常可读。
    final page = await store.readTail(meta.id);
    expect(page.messages, hasLength(5));
    final restored = await store.readHistory(meta.id);
    expect(restored.first['content'], '第 24 轮问题');
  });

  test('没到上限时不重写，文件继续追加', () async {
    final meta = await store.create('p1');
    await store.appendMessage(meta.id, {
      'id': 'm0',
      'role': 'user',
      'text': '你好',
    });
    for (var round = 0; round < 5; round++) {
      await store.writeHistory(meta.id, [
        {'role': 'user', 'content': '第 $round 轮'},
      ]);
    }
    await store.flush();

    final decoded = rows(fileOf(meta.id));
    expect(decoded.where((row) => row['t'] == 'hs'), hasLength(5));
    expect(decoded.where((row) => row['t'] == 'm'), hasLength(1));
  });

  test('打开会话时统计快照行数并压缩', () async {
    final meta = await store.create('p1');
    for (var round = 0; round < 22; round++) {
      // 直接写原始行，模拟旧版本留下的多份快照。
      final record = {
        't': 'hs',
        'v': [
          {'role': 'user', 'content': '第 $round 轮'},
        ],
      };
      fileOf(meta.id).writeAsStringSync(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
    expect(
      rows(fileOf(meta.id)).where((row) => row['t'] == 'hs'),
      hasLength(22),
    );

    final store2 = FileAgentSessionStore(root: root);
    await store2.load();
    await store2.compactIfNeeded(meta.id);

    final snapshots = rows(fileOf(meta.id)).where((row) => row['t'] == 'hs');
    expect(snapshots, hasLength(1));
    expect(((snapshots.single['v'] as List).first as Map)['content'], '第 21 轮');
  });
}
