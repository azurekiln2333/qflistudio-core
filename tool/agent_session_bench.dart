/// 会话存储基准：旧实现（每会话一个 JSON，整文件读写）对比新实现
/// （`index.json` 加 `<id>.jsonl`，只读尾部、只追加）。
///
/// 跑法：`flutter test tool/agent_session_bench.dart`
///
/// 数据规模按 design.md §11.7：200 个会话，其中 1 个 3000 条消息、约 20 MB。
/// 只测存储层，不含界面与网络。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/session/agent_session.dart';

const int _sessionCount = 200;
const int _bigMessages = 3000;
const int _smallMessages = 20;
const int _pageSize = 60;

/// 追加计时的样本数：取中位数，避开磁盘抖动。
const int _appendSamples = 9;

int _medianMicros(List<int> samples) {
  final sorted = [...samples]..sort();
  return sorted[sorted.length ~/ 2];
}

/// 一条消息约 6.7 KB，3000 条约 20 MB。
String _body(int index) =>
    '第 $index 条：${'这是一段用于撑大文件的正文。' * 200}';

void main() {
  test('session storage benchmark', () async {
    final root = Directory.systemTemp.createTempSync('agent-bench-');
    addTearDown(() {
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
      } on FileSystemException {
        // 临时目录可以留在临时区。
      }
    });

    final bigId = 'big-session';
    final ids = <String>[bigId];
    for (var index = 1; index < _sessionCount; index++) {
      ids.add('session-$index');
    }

    // ---- 造数据：新实现 ----
    final newRoot = Directory(p.join(root.path, 'new'));
    final store = FileAgentSessionStore(root: newRoot);
    await store.load();
    for (final id in ids) {
      final meta = await store.create('p1', title: '会话 $id');
      expect(meta.id, isNotEmpty);
    }
    // create 生成的 id 与上面的名字不同，按顺序取回来。
    final created = store.sessionsOf('p1').map((meta) => meta.id).toList();
    final big = created.first;
    for (final id in created) {
      final total = id == big ? _bigMessages : _smallMessages;
      for (var index = 0; index < total; index++) {
        await store.appendMessage(id, {
          'id': 'm$index',
          'role': index.isEven ? 'user' : 'assistant',
          'text': _body(index),
        });
      }
    }
    await store.writeHistory(big, [
      {'role': 'user', 'content': '历史'},
    ]);
    await store.flush();
    final bigBytes = File(p.join(newRoot.path, '$big.jsonl')).lengthSync();
    // ignore: avoid_print
    print('数据：$_sessionCount 个会话，大会话 $bigBytes 字节');

    // ---- 新实现：列表、打开、追加 ----
    final newStore = FileAgentSessionStore(root: newRoot);
    final loadWatch = Stopwatch()..start();
    await newStore.load();
    loadWatch.stop();
    final newLoad = loadWatch.elapsedMicroseconds;

    final openWatch = Stopwatch()..start();
    final page = await newStore.readTail(big, limit: _pageSize);
    openWatch.stop();
    final newOpen = openWatch.elapsedMicroseconds;
    expect(page.messages.length, _pageSize);
    expect(page.hasEarlier, isTrue);

    final newAppendSamples = <int>[];
    for (var index = 0; index < _appendSamples; index++) {
      final appendWatch = Stopwatch()..start();
      await newStore.appendMessage(big, {
        'id': 'm-last-$index',
        'role': 'user',
        'text': '追加一条',
      });
      appendWatch.stop();
      newAppendSamples.add(appendWatch.elapsedMicroseconds);
    }
    final newAppend = _medianMicros(newAppendSamples);
    await newStore.flush();

    // ---- 旧实现：每会话一个 JSON，整文件读写 ----
    final oldRoot = Directory(p.join(root.path, 'old'));
    await oldRoot.create(recursive: true);
    for (final id in created) {
      final total = id == big ? _bigMessages : _smallMessages;
      final messages = [
        for (var index = 0; index < total; index++)
          {
            'id': 'm$index',
            'role': index.isEven ? 'user' : 'assistant',
            'text': _body(index),
          },
      ];
      File(p.join(oldRoot.path, '$id.json')).writeAsStringSync(
        jsonEncode({
          'id': id,
          'projectId': 'p1',
          'title': '会话 $id',
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'messages': messages,
          'history': [
            {'role': 'user', 'content': '历史'},
          ],
        }),
      );
    }

    final oldLoadWatch = Stopwatch()..start();
    var oldCount = 0;
    for (final entry in oldRoot.listSync()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final decoded = jsonDecode(entry.readAsStringSync());
      if (decoded is Map && decoded['id'] is String) oldCount++;
    }
    oldLoadWatch.stop();
    final oldLoad = oldLoadWatch.elapsedMicroseconds;
    expect(oldCount, _sessionCount);

    final oldOpenWatch = Stopwatch()..start();
    final oldDecoded = jsonDecode(
      File(p.join(oldRoot.path, '$big.json')).readAsStringSync(),
    );
    oldOpenWatch.stop();
    final oldOpen = oldOpenWatch.elapsedMicroseconds;
    expect((oldDecoded as Map)['messages'], isA<List>());

    final oldAppendSamples = <int>[];
    for (var index = 0; index < _appendSamples; index++) {
      final transcript = Map<String, Object?>.from(oldDecoded);
      final messages = List<Map<String, Object?>>.from(
        (transcript['messages'] as List).cast<Map<String, Object?>>(),
      )..add({'id': 'm-last-$index', 'role': 'user', 'text': '追加一条'});
      transcript['messages'] = messages;
      // 旧实现为了加一条消息要把 20 MB 整体重写一次。
      final oldAppendWatch = Stopwatch()..start();
      File(p.join(oldRoot.path, '$big.json')).writeAsStringSync(
        jsonEncode(transcript),
      );
      oldAppendWatch.stop();
      oldAppendSamples.add(oldAppendWatch.elapsedMicroseconds);
    }
    final oldAppend = _medianMicros(oldAppendSamples);

    // ---- 报告 ----
    String ms(int micros) => (micros / 1000).toStringAsFixed(1);

    void row(String name, int oldMicros, int newMicros, int budgetMs) {
      final verdict = newMicros <= budgetMs * 1000 ? '通过' : '超出';
      // ignore: avoid_print
      print(
        '${name.padRight(22)} 旧 ${ms(oldMicros).padLeft(6)} ms   '
        '新 ${ms(newMicros).padLeft(6)} ms   预算 $budgetMs ms   $verdict',
      );
    }

    // ignore: avoid_print
    print('---- 结果 ----');
    row('sessions.load', oldLoad, newLoad, 50);
    row('session.open(3000)', oldOpen, newOpen, 150);
    row('persist.append', oldAppend, newAppend, 5);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
