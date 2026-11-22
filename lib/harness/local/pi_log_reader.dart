/// Pi 会话日志读取。
///
/// 目录：`~/.pi/agent/sessions/<编码路径>/*.jsonl`。Pi 的日志行比 Claude
/// 与 Codex 更宽松，因此这里按兼容顺序识别：`message.message`、
/// `message.content`、`{role, content}` 和裸 `{type, text}`。
///
/// 权限请求与提问带 `requestId`，读取器把它映射到
/// [TranscriptEvent.requestId]；没有该字段的行只当普通对话。
library;

import 'dart:io';

import '../harness_host.dart';
import 'harness_provider.dart';
import 'transcript_log_reader.dart';

class PiLogReader extends TranscriptLogReader {
  PiLogReader({required super.providerId, required super.rootPath})
    : super(format: HarnessLogFormat.pi);

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
    final cwd = cwdFromLines(head) ?? cwdFromLines(tail);
    String? title;
    var lastRole = _lastRole(tail);
    final pending = _pendingRequestId(tail);
    for (final line in head.reversed) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      final role = _roleOf(decoded);
      if (role != TranscriptRole.user) continue;
      title = summarizeText(_textOf(decoded), maxChars: 120);
      if (title.isEmpty) title = null;
      break;
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
      title: title ?? titleFromCwd(cwd) ?? basenameWithoutExtension(file.path),
      filePath: file.path,
      updatedAt: updatedAt,
      workingDirectory: cwd,
      lastRole: lastRole,
      pendingRequestId: pending,
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

  List<TranscriptEvent> _parseLine(String line, String base, int offset) {
    final decoded = decodeJsonLine(line);
    if (decoded is! Map) return const <TranscriptEvent>[];
    final at = parseLogTimestamp(
      decoded['timestamp'] ?? decoded['createdAt'] ?? decoded['created_at'],
    );
    final type = decoded['type'];

    // 权限请求与提问：带 requestId 才能回复。
    if (type == 'permission_request' ||
        type == 'approval_request' ||
        type == 'question' ||
        type == 'request') {
      final requestId = _requestId(decoded, offset);
      final prompt = summarizeText(
        _textOf(decoded).isEmpty ? '需要确认' : _textOf(decoded),
        maxChars: 400,
      );
      return <TranscriptEvent>[
        TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.system,
          text: prompt,
          at: at,
          requestId: requestId,
          options: _optionsOf(decoded),
        ),
      ];
    }

    final role = _roleOf(decoded);
    if (role == null) return const <TranscriptEvent>[];
    final message = decoded['message'];
    final content = message is Map
        ? (message['content'] ?? message['text'])
        : (decoded['content'] ?? decoded['text']);
    final events = <TranscriptEvent>[];
    var part = 0;
    void add(String value, {TranscriptRole? as}) {
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
      add(content);
      return events;
    }
    if (content is! List) return events;
    for (final block in content) {
      if (block is String) {
        add(block);
        continue;
      }
      if (block is! Map) continue;
      final blockType = block['type'];
      if (blockType == 'text' || blockType == 'thinking') {
        add(textFromContent(block));
      } else if (blockType == 'tool_use' || blockType == 'tool_call') {
        final name = block['name'] is String ? block['name'] as String : 'tool';
        add(name, as: TranscriptRole.tool);
      } else if (blockType == 'tool_result') {
        add(textFromContent(block['content']), as: TranscriptRole.tool);
      }
    }
    return events;
  }

  /// 事件角色；非消息行返回 null。
  TranscriptRole? _roleOf(Map<dynamic, dynamic> decoded) {
    final message = decoded['message'];
    final rawRole = message is Map
        ? (message['role'] ?? decoded['role'])
        : (decoded['role'] ?? decoded['type']);
    return switch (rawRole) {
      'user' => TranscriptRole.user,
      'assistant' => TranscriptRole.assistant,
      'tool' || 'tool_result' || 'tool_use' => TranscriptRole.tool,
      'system' || 'info' => TranscriptRole.system,
      _ => null,
    };
  }

  String _textOf(Map<dynamic, dynamic> decoded) {
    final message = decoded['message'];
    final Object? content = message is Map
        ? (message['content'] ?? message['text'] ?? message['summary'])
        : (decoded['content'] ??
              decoded['text'] ??
              decoded['prompt'] ??
              decoded['title']);
    return textFromContent(content);
  }

  String? _requestId(Map<dynamic, dynamic> decoded, int offset) {
    for (final key in const <String>[
      'requestId',
      'request_id',
      'id',
      'callId',
      'call_id',
    ]) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'pi-request-$offset';
  }

  List<String> _optionsOf(Map<dynamic, dynamic> decoded) {
    final raw = decoded['options'] ?? decoded['choices'];
    if (raw is! List) return const <String>['allow', 'deny'];
    final options = <String>[
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
    return options.isEmpty ? const <String>['allow', 'deny'] : options;
  }

  static TranscriptRole? _lastRole(List<String> tail) {
    for (final line in tail.reversed) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      final type = decoded['type'];
      if (type == 'permission_request' ||
          type == 'approval_request' ||
          type == 'question' ||
          type == 'request') {
        return TranscriptRole.system;
      }
      final message = decoded['message'];
      final rawRole = message is Map
          ? (message['role'] ?? decoded['role'])
          : (decoded['role'] ?? type);
      final role = switch (rawRole) {
        'user' => TranscriptRole.user,
        'assistant' => TranscriptRole.assistant,
        'tool' || 'tool_result' || 'tool_use' => TranscriptRole.tool,
        'system' || 'info' => TranscriptRole.system,
        _ => null,
      };
      if (role != null) return role;
    }
    return null;
  }

  static String? _pendingRequestId(List<String> tail) {
    for (final line in tail.reversed) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      final type = decoded['type'];
      if (type != 'permission_request' &&
          type != 'approval_request' &&
          type != 'question' &&
          type != 'request') {
        // 其他事件说明流程已经继续。
        return null;
      }
      for (final key in const <String>[
        'requestId',
        'request_id',
        'id',
        'callId',
        'call_id',
      ]) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }
    return null;
  }
}
