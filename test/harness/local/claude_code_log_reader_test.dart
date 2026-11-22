import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/claude_code_log_reader.dart';

String get _root =>
    '${Directory.current.path}/test/harness/local/fixtures/home/.claude/projects';

String get _session => '$_root/-home-dev-proj/session-abc.jsonl';

ClaudeCodeLogReader get _reader =>
    ClaudeCodeLogReader(providerId: 'claude', rootPath: _root);

void main() {
  group('ClaudeCodeLogReader', () {
    test('列出会话并取工作目录与摘要标题', () async {
      final sessions = await _reader.listSessions();

      expect(sessions, hasLength(1));
      final session = sessions.single;
      expect(session.providerId, 'claude');
      expect(session.id, startsWith('log:claude:'));
      expect(session.title, '修复登录页按钮无响应');
      expect(session.workingDirectory, '/home/dev/proj');
      expect(session.filePath, endsWith('session-abc.jsonl'));
    });

    test('最后一条是助手消息时状态为 done', () async {
      final sessions = await _reader.listSessions();

      expect(sessions.single.lastRole, TranscriptRole.assistant);
      expect(sessions.single.status, HarnessSessionStatus.done);
      expect(sessions.single.pendingRequestId, isNull);
    });

    test('解析文本、工具调用与工具结果', () async {
      final events = await _reader.read(_session);

      expect(events.map((TranscriptEvent e) => e.role), <TranscriptRole>[
        TranscriptRole.user,
        TranscriptRole.assistant,
        TranscriptRole.tool,
        TranscriptRole.tool,
        TranscriptRole.assistant,
      ]);
      expect(events.first.text, '登录按钮没反应，帮我看看');
      expect(events[1].text, '我先看下按钮的点击处理。');
      expect(events[2].text, contains('Read'));
      expect(events[2].text, contains('lib/login.dart'));
      expect(events[3].text, contains('LoginPage'));
      expect(events.last.text, '找到原因：onPressed 传的是 null。');
    });

    test('事件带时间戳与稳定 id', () async {
      final events = await _reader.read(_session);

      expect(events.first.at, DateTime.utc(2026, 11, 20, 10));
      expect(events.map((TranscriptEvent e) => e.id).toSet(), hasLength(5));
      // id 由文件内字节偏移生成，重读同一个文件必须完全一致。
      final again = await _reader.read(_session);
      expect(
        again.map((TranscriptEvent e) => e.id),
        events.map((TranscriptEvent e) => e.id),
      );
    });

    test('没有 requestId，因为 Claude 不把确认写进日志', () async {
      final events = await _reader.read(_session);

      expect(events.every((TranscriptEvent e) => e.requestId == null), isTrue);
    });

    test('maxEvents 只保留尾部事件', () async {
      final events = await _reader.read(_session, maxEvents: 2);

      expect(events, hasLength(2));
      expect(events.last.role, TranscriptRole.assistant);
    });

    test('目录不存在时返回空列表', () async {
      final reader = ClaudeCodeLogReader(
        providerId: 'claude',
        rootPath:
            '${Directory.current.path}/test/harness/local/fixtures/missing',
      );

      expect(await reader.listSessions(), isEmpty);
    });

    test('尾部窗口只有半行时丢掉它，不产生坏事件', () async {
      // 只读最后 20 字节，必然落在最后一行中间。
      final events = await _reader.read(_session, maxBytes: 20);

      expect(events, isEmpty);
    });

    test('完整落在窗口内的最后一行会被解析', () async {
      final events = await _reader.read(_session, maxBytes: 600);

      expect(events, isNotEmpty);
      expect(events.every((TranscriptEvent e) => e.text.isNotEmpty), isTrue);
      expect(events.last.role, TranscriptRole.assistant);
    });
  });
}
