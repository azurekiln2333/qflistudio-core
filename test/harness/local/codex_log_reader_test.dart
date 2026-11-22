import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/codex_log_reader.dart';

String get _root =>
    '${Directory.current.path}/test/harness/local/fixtures/home/.codex/sessions';

CodexLogReader get _reader =>
    CodexLogReader(providerId: 'codex', rootPath: _root);

String _sessionPath(String name) =>
    '$_root/2026/11/20/rollout-2026-11-20T10-00-00-$name.jsonl';

void main() {
  group('CodexLogReader', () {
    test('列出会话并按修改时间倒序', () async {
      final sessions = await _reader.listSessions();

      expect(sessions, hasLength(2));
      expect(
        sessions.every((session) => session.providerId == 'codex'),
        isTrue,
      );
    });

    test('从 session_meta 取工作目录，从首条用户消息取标题', () async {
      final sessions = await _reader.listSessions();
      final session = sessions.firstWhere(
        (session) => session.filePath.endsWith('10-00-00-abc.jsonl'),
      );

      expect(session.workingDirectory, '/home/dev/app');
      expect(session.title, '跑一下测试');
      expect(session.lastRole, TranscriptRole.assistant);
      expect(session.status, HarnessSessionStatus.done);
    });

    test('末尾是审批请求时会话状态为 blocked', () async {
      final sessions = await _reader.listSessions();
      final session = sessions.firstWhere(
        (session) => session.filePath.endsWith('09-00-00-def.jsonl'),
      );

      expect(session.status, HarnessSessionStatus.blocked);
      expect(session.pendingRequestId, 'call_9');
    });

    test('解析消息、命令与审批请求', () async {
      final events = await _reader.read(_sessionPath('abc'));

      expect(events.map((TranscriptEvent e) => e.role), <TranscriptRole>[
        TranscriptRole.system,
        TranscriptRole.user,
        TranscriptRole.tool,
        TranscriptRole.system,
        TranscriptRole.assistant,
      ]);
      expect(events.first.text, contains('/home/dev/app'));
      expect(events[1].text, '跑一下测试');
      expect(events[2].text, 'npm test');
      expect(events[3].requestId, 'call_2');
      expect(events[3].options, <String>['approve', 'deny']);
      expect(events[3].text, contains('rm -rf build'));
      expect(events.last.text, '测试通过。');
    });

    test('事件 id 稳定且不重复', () async {
      final events = await _reader.read(_sessionPath('abc'));

      expect(events.map((TranscriptEvent e) => e.id).toSet(), hasLength(5));
      final again = await _reader.read(_sessionPath('abc'));
      expect(
        again.map((TranscriptEvent e) => e.id),
        events.map((TranscriptEvent e) => e.id),
        reason: 'id 用字节偏移，重读不能变',
      );
    });

    test('maxEvents 只保留尾部事件', () async {
      final events = await _reader.read(_sessionPath('abc'), maxEvents: 1);

      expect(events.single.role, TranscriptRole.assistant);
      expect(events.single.text, '测试通过。');
    });

    test('目录不存在时返回空列表', () async {
      final reader = CodexLogReader(
        providerId: 'codex',
        rootPath:
            '${Directory.current.path}/test/harness/local/fixtures/missing',
      );

      expect(await reader.listSessions(), isEmpty);
    });
  });
}
