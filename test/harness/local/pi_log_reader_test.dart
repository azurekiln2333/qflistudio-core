/// 每个用例都限时：读盘卡住时要尽快报错。
@Timeout(Duration(seconds: 20))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/pi_log_reader.dart';

String get _root =>
    '${Directory.current.path}/test/harness/local/fixtures/home/.pi/agent/sessions';

String get _session => '$_root/-home-dev-pi/2026-11-20_abc.jsonl';

PiLogReader get _reader => PiLogReader(providerId: 'pi', rootPath: _root);

void main() {
  group('PiLogReader', () {
    test('列出会话并取工作目录与标题', () async {
      final sessions = await _reader.listSessions();

      expect(sessions, hasLength(1));
      final session = sessions.single;
      expect(session.providerId, 'pi');
      expect(session.workingDirectory, '/home/dev/pi');
      expect(session.title, '帮我加一个单元测试');
    });

    test('末尾是权限请求时会话状态为 blocked', () async {
      final sessions = await _reader.listSessions();

      expect(sessions.single.status, HarnessSessionStatus.blocked);
      expect(sessions.single.pendingRequestId, 'req-7');
    });

    test('解析文本与工具调用', () async {
      final events = await _reader.read(_session);

      expect(events.map((TranscriptEvent e) => e.role), <TranscriptRole>[
        TranscriptRole.user,
        TranscriptRole.assistant,
        TranscriptRole.tool,
        TranscriptRole.system,
      ]);
      expect(events.first.text, '帮我加一个单元测试');
      expect(events[1].text, '好的，先看现有测试。');
      expect(events[2].text, 'read');
      expect(events[3].requestId, 'req-7');
      expect(events[3].options, <String>['allow', 'deny']);
    });

    test('权限请求保留原始提问文本', () async {
      final events = await _reader.read(_session);

      expect(events.last.text, contains('允许写入'));
      expect(events.last.at, DateTime.utc(2026, 11, 20, 10, 0, 3));
    });

    test('没有 requestId 的普通对话不会伪造审批', () async {
      final events = await _reader.read(_session);

      expect(events.take(3).every((e) => e.requestId == null), isTrue);
    });

    test('目录不存在时返回空列表', () async {
      final reader = PiLogReader(
        providerId: 'pi',
        rootPath:
            '${Directory.current.path}/test/harness/local/fixtures/missing',
      );

      expect(await reader.listSessions(), isEmpty);
    });
  });
}
