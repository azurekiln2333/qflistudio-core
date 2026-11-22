/// 每个用例都限时：轮询与读盘卡住时要尽快报错。
@Timeout(Duration(seconds: 20))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/live_log_follower.dart';
import 'package:qfli_studio_core/harness/local/pi_log_reader.dart';

String get _fixtureSession =>
    '${Directory.current.path}/test/harness/local/fixtures/home/.pi/agent/sessions/-home-dev-pi/2026-11-20_abc.jsonl';

/// 把夹具复制到临时目录，测试因此可以追加内容。
Directory copyFixture() {
  final root = Directory.systemTemp.createTempSync('harness_follower_');
  final target = Directory('${root.path}/-home-dev-pi')
    ..createSync(recursive: true);
  File(_fixtureSession).copySync('${target.path}/2026-11-20_abc.jsonl');
  return root;
}

void main() {
  group('LiveLogFollower', () {
    test('按工作目录找到日志并推送已有事件', () async {
      final root = copyFixture();
      addTearDown(() => root.deleteSync(recursive: true));
      final follower = LiveLogFollower(
        reader: PiLogReader(providerId: 'pi', rootPath: root.path),
        workingDirectory: '/home/dev/pi',
        since: DateTime.now(),
      );
      addTearDown(follower.stop);
      final events = <TranscriptEvent>[];
      final subscription = follower.events.listen(events.add);
      addTearDown(subscription.cancel);

      await follower.poll();
      await Future<void>.delayed(Duration.zero);

      expect(follower.logPath, endsWith('2026-11-20_abc.jsonl'));
      expect(events.map((TranscriptEvent e) => e.role), <TranscriptRole>[
        TranscriptRole.user,
        TranscriptRole.assistant,
        TranscriptRole.tool,
        TranscriptRole.system,
      ]);
      expect(follower.delivered, 4);
    });

    test('再次轮询只推送新增事件', () async {
      final root = copyFixture();
      addTearDown(() => root.deleteSync(recursive: true));
      final follower = LiveLogFollower(
        reader: PiLogReader(providerId: 'pi', rootPath: root.path),
        workingDirectory: '/home/dev/pi',
        since: DateTime.now(),
      );
      addTearDown(follower.stop);
      final events = <TranscriptEvent>[];
      final subscription = follower.events.listen(events.add);
      addTearDown(subscription.cancel);
      await follower.poll();
      await Future<void>.delayed(Duration.zero);

      final file = File(follower.logPath!);
      file.writeAsStringSync(
        '{"type":"message","timestamp":"2026-11-20T10:00:09.000Z",'
        '"message":{"role":"assistant","content":[{"type":"text",'
        '"text":"已经加好了。"}]}}\n',
        mode: FileMode.append,
      );
      await follower.poll();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(5));
      expect(events.last.text, '已经加好了。');
    });

    test('窗口封顶后仍能推送新事件', () async {
      final root = copyFixture();
      addTearDown(() => root.deleteSync(recursive: true));
      final follower = LiveLogFollower(
        reader: PiLogReader(providerId: 'pi', rootPath: root.path),
        workingDirectory: '/home/dev/pi',
        since: DateTime.now(),
        // 夹具里共 4 条事件；上限 3 意味着返回窗口恒为最后 3 条。
        maxEvents: 3,
      );
      addTearDown(follower.stop);
      final events = <TranscriptEvent>[];
      final subscription = follower.events.listen(events.add);
      addTearDown(subscription.cancel);

      await follower.poll();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(3));

      File(follower.logPath!).writeAsStringSync(
        '{"type":"message","timestamp":"2026-11-20T10:00:10.000Z",'
        '"message":{"role":"assistant","content":[{"type":"text",'
        '"text":"窗口封顶后的新事件。"}]}}\n',
        mode: FileMode.append,
      );
      await follower.poll();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(4), reason: '条数游标在窗口封顶后会永久停更');
      expect(events.last.text, '窗口封顶后的新事件。');
    });

    test('没有匹配工作目录的日志时不推送', () async {
      final root = copyFixture();
      addTearDown(() => root.deleteSync(recursive: true));
      final follower = LiveLogFollower(
        reader: PiLogReader(providerId: 'pi', rootPath: root.path),
        workingDirectory: '/home/dev/other',
        since: DateTime.now(),
      );
      addTearDown(follower.stop);

      await follower.poll();

      expect(follower.logPath, isNull);
      expect(follower.delivered, 0);
    });

    test('早于会话启动的日志不被采用', () async {
      final root = copyFixture();
      addTearDown(() => root.deleteSync(recursive: true));
      final follower = LiveLogFollower(
        reader: PiLogReader(providerId: 'pi', rootPath: root.path),
        workingDirectory: '/home/dev/pi',
        since: DateTime.now().add(const Duration(minutes: 5)),
        matchWindow: Duration.zero,
      );
      addTearDown(follower.stop);

      await follower.poll();

      expect(follower.logPath, isNull);
    });

    test('stop 关闭事件流', () async {
      final root = copyFixture();
      addTearDown(() => root.deleteSync(recursive: true));
      final follower = LiveLogFollower(
        reader: PiLogReader(providerId: 'pi', rootPath: root.path),
        workingDirectory: '/home/dev/pi',
        since: DateTime.now(),
      );

      await follower.stop();

      expect(await follower.events.isEmpty, isTrue);
    });
  });
}
