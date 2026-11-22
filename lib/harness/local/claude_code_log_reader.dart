/// Claude Code 会话日志读取。
///
/// 目录：`~/.claude/projects/<编码路径>/*.jsonl`，一行一个 JSON 对象。
/// 用户与助手的消息在 `message.content` 里，工具调用是 `tool_use` 块，工具
/// 结果是 user 角色里的 `tool_result` 块。
///
/// Claude Code 把权限确认留在 TUI 内，不写日志，因此这里没有 requestId。
/// 界面只显示对话记录，不伪造审批入口。
library;

import 'dart:io';

import '../harness_host.dart';
import 'harness_provider.dart';
import 'transcript_log_reader.dart';

class ClaudeCodeLogReader extends TranscriptLogReader {
  ClaudeCodeLogReader({required super.providerId, required super.rootPath})
    : super(format: HarnessLogFormat.claude);

  @override
  Future<List<LogSessionRef>> listSessions({int maxSessions = 40}) async {
    final files = recentJsonlFiles(
      Directory(rootPath),
      maxSessions: maxSessions,
      maxDepth: 2,
    );
    final result = <LogSessionRef>[];
    for (final file in files) {
      final ref = await _describe(file);
      if (ref != null) result.add(ref);
    }
    return result;
  }

  Future<LogSessionRef?> _describe(File file) async {
    final head = await readJsonlHead(file.path);
    final tail = await readJsonlTail(file.path, maxBytes: kLogStatusBytes);
    String? cwd;
    String? summary;
    for (final line in head) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      final candidate = decoded['cwd'];
      if (candidate is String && candidate.trim().isNotEmpty) {
        cwd = candidate.trim();
      }
      if (decoded['type'] == 'summary') {
        final value = decoded['summary'];
        if (value is String && value.trim().isNotEmpty) {
          summary = summarizeText(value, maxChars: 120);
        }
      }
    }
    TranscriptRole? role;
    for (final line in tail.reversed) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      role = _roleFor(decoded);
      if (role != null) break;
    }
    final DateTime updatedAt;
    try {
      updatedAt = file.statSync().modified;
    } on FileSystemException {
      return null;
    }
    return LogSessionRef(
      providerId: providerId,
      id: logSessionId(providerId, file.path, rootPath: rootPath),
      title:
          summary ?? titleFromCwd(cwd) ?? basenameWithoutExtension(file.path),
      filePath: file.path,
      updatedAt: updatedAt,
      workingDirectory: cwd,
      lastRole: role,
    );
  }

  @override
  Future<List<TranscriptEvent>> read(
    String filePath, {
    int maxEvents = 400,
    int maxBytes = kLogTailBytes,
  }) async {
    final lines = await readJsonlTailLines(filePath, maxBytes: maxBytes);
    final base = logSessionId(providerId, filePath, rootPath: rootPath);
    final events = <TranscriptEvent>[];
    for (final line in lines) {
      events.addAll(_parseLine(line.text, base, line.offset));
    }
    if (events.length <= maxEvents) return events;
    return events.sublist(events.length - maxEvents);
  }

  /// 解析一行；一段内容可能展开成多个事件（文本与多个工具调用）。
  List<TranscriptEvent> _parseLine(String line, String base, int offset) {
    final decoded = decodeJsonLine(line);
    if (decoded is! Map) return const <TranscriptEvent>[];
    final type = decoded['type'];
    if (type != 'user' && type != 'assistant' && type != 'system') {
      return const <TranscriptEvent>[];
    }
    final at = parseLogTimestamp(decoded['timestamp']);
    if (type == 'system') {
      final text = summarizeText(textFromContent(decoded['content']));
      if (text.isEmpty) return const <TranscriptEvent>[];
      return <TranscriptEvent>[
        TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.system,
          text: text,
          at: at,
        ),
      ];
    }
    final message = decoded['message'];
    final content = message is Map ? message['content'] : decoded['content'];
    final role = type == 'user'
        ? TranscriptRole.user
        : TranscriptRole.assistant;
    final events = <TranscriptEvent>[];
    var part = 0;
    void addText(String value, {TranscriptRole? as}) {
      final text = summarizeText(value);
      if (text.isEmpty) return;
      events.add(
        TranscriptEvent(
          id: logEventId(base, offset, part++),
          role: as ?? role,
          text: text,
          at: at,
        ),
      );
    }

    if (content is String) {
      addText(content);
      return events;
    }
    if (content is! List) return events;
    for (final block in content) {
      if (block is String) {
        addText(block);
        continue;
      }
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          addText(textFromContent(block));
        case 'tool_use':
          final name = block['name'] is String
              ? block['name'] as String
              : 'tool';
          final detail = _describeInput(block['input']);
          addText(
            detail.isEmpty ? name : '$name · $detail',
            as: TranscriptRole.tool,
          );
        case 'tool_result':
          addText(textFromContent(block['content']), as: TranscriptRole.tool);
        default:
          break;
      }
    }
    return events;
  }

  /// 工具入参的紧凑描述：只保留前几个字段。
  String _describeInput(Object? input) {
    if (input is! Map) return '';
    final parts = <String>[];
    for (final entry in input.entries) {
      final value = entry.value;
      final text = value is String ? value : '$value';
      parts.add('${entry.key}=${summarizeText(text, maxChars: 120)}');
      if (parts.length >= 3) break;
    }
    return summarizeText(parts.join(' '), maxChars: 240);
  }

  /// 这一行代表的事件角色；辅助行返回 null。
  TranscriptRole? _roleFor(Map<dynamic, dynamic> decoded) {
    return switch (decoded['type']) {
      'user' => TranscriptRole.user,
      'assistant' => TranscriptRole.assistant,
      'system' => TranscriptRole.system,
      _ => null,
    };
  }
}
