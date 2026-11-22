/// Codex 会话日志读取。
///
/// 目录：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`。每行是
/// `{"timestamp": ..., "type": ..., "payload": ...}`。消息在
/// `response_item` 的 `message` 里，命令执行与审批在 `event_msg` 里。
///
/// 审批请求带 `call_id`，读取器把它映射成 [TranscriptEvent.requestId]，
/// 界面因此可以显示审批按钮。批准或拒绝由用户在终端里完成，这里只读。
library;

import 'dart:io';

import '../harness_host.dart';
import 'harness_provider.dart';
import 'transcript_log_reader.dart';

class CodexLogReader extends TranscriptLogReader {
  CodexLogReader({required super.providerId, required super.rootPath})
    : super(format: HarnessLogFormat.codex);

  @override
  Future<List<LogSessionRef>> listSessions({int maxSessions = 40}) async {
    final files = recentJsonlFiles(
      Directory(rootPath),
      maxSessions: maxSessions,
      maxDepth: 4,
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
      final message = _userMessage(decoded);
      if (message == null) continue;
      title = summarizeText(message, maxChars: 120);
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
      final event = _parseLine(line.text, base, line.offset);
      if (event != null) events.add(event);
    }
    if (events.length <= maxEvents) return events;
    return events.sublist(events.length - maxEvents);
  }

  TranscriptEvent? _parseLine(String line, String base, int offset) {
    final decoded = decodeJsonLine(line);
    if (decoded is! Map) return null;
    final at = parseLogTimestamp(decoded['timestamp']);
    final type = decoded['type'];
    final payload = decoded['payload'];
    if (type == 'response_item' && payload is Map) {
      return _responseItem(payload, base, offset, at);
    }
    if (type == 'event_msg' && payload is Map) {
      return _eventMessage(payload, base, offset, at);
    }
    if (type == 'session_meta' && payload is Map) {
      final cwd = payload['cwd'];
      if (cwd is String && cwd.trim().isNotEmpty) {
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.system,
          text: '会话目录：${cwd.trim()}',
          at: at,
        );
      }
    }
    return null;
  }

  TranscriptEvent? _responseItem(
    Map<dynamic, dynamic> payload,
    String base,
    int offset,
    DateTime? at,
  ) {
    switch (payload['type']) {
      case 'message':
        final role = payload['role'];
        final text = summarizeText(textFromContent(payload['content']));
        if (text.isEmpty) return null;
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: role == 'assistant'
              ? TranscriptRole.assistant
              : role == 'system'
              ? TranscriptRole.system
              : TranscriptRole.user,
          text: text,
          at: at,
        );
      case 'function_call':
      case 'custom_tool_call':
        final name = payload['name'] is String
            ? payload['name'] as String
            : 'tool';
        final arguments = summarizeText(
          textFromContent(payload['arguments']),
          maxChars: 240,
        );
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.tool,
          text: arguments.isEmpty ? name : '$name · $arguments',
          at: at,
        );
      case 'function_call_output':
      case 'custom_tool_call_output':
        final text = summarizeText(textFromContent(payload['output']));
        if (text.isEmpty) return null;
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.tool,
          text: text,
          at: at,
        );
      default:
        return null;
    }
  }

  TranscriptEvent? _eventMessage(
    Map<dynamic, dynamic> payload,
    String base,
    int offset,
    DateTime? at,
  ) {
    switch (payload['type']) {
      case 'user_message':
        final text = summarizeText(textFromContent(payload['message']));
        if (text.isEmpty) return null;
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.user,
          text: text,
          at: at,
        );
      case 'agent_message':
        final text = summarizeText(textFromContent(payload['message']));
        if (text.isEmpty) return null;
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.assistant,
          text: text,
          at: at,
        );
      case 'exec_command_begin':
        final command = payload['command'];
        final text = summarizeText(
          command is List ? command.join(' ') : textFromContent(command),
          maxChars: 240,
        );
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.tool,
          text: text.isEmpty ? 'exec_command' : text,
          at: at,
        );
      case 'exec_approval_request':
      case 'apply_patch_approval_request':
      case 'request_permissions':
        final requestId = _requestId(payload, offset);
        final command = payload['command'];
        final detail = summarizeText(
          command is List ? command.join(' ') : textFromContent(command),
          maxChars: 240,
        );
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.system,
          text: detail.isEmpty ? '需要确认' : '需要确认：$detail',
          at: at,
          requestId: requestId,
          options: const <String>['approve', 'deny'],
        );
      case 'error':
        final text = summarizeText(textFromContent(payload['message']));
        if (text.isEmpty) return null;
        return TranscriptEvent(
          id: logEventId(base, offset),
          role: TranscriptRole.system,
          text: text,
          at: at,
        );
      default:
        return null;
    }
  }

  /// 审批请求的 id。Codex 用 `call_id`，旧版本用 `id`。
  String? _requestId(Map<dynamic, dynamic> payload, int offset) {
    for (final key in const <String>['call_id', 'id', 'request_id']) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'codex-request-$offset';
  }

  static String? _userMessage(Map<dynamic, dynamic> decoded) {
    final payload = decoded['payload'];
    if (payload is! Map) return null;
    if (payload['type'] == 'user_message') {
      final text = summarizeText(textFromContent(payload['message']));
      return text.isEmpty ? null : text;
    }
    if (payload['type'] != 'message' || payload['role'] != 'user') return null;
    final text = summarizeText(textFromContent(payload['content']));
    return text.isEmpty ? null : text;
  }

  static TranscriptRole? _lastRole(List<String> tail) {
    for (final line in tail.reversed) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      final payload = decoded['payload'];
      if (payload is! Map) continue;
      switch (payload['type']) {
        case 'user_message':
          return TranscriptRole.user;
        case 'agent_message':
          return TranscriptRole.assistant;
        case 'exec_command_begin':
        case 'exec_command_end':
          return TranscriptRole.tool;
        case 'exec_approval_request':
        case 'apply_patch_approval_request':
        case 'request_permissions':
          return TranscriptRole.system;
        case 'message':
          return payload['role'] == 'assistant'
              ? TranscriptRole.assistant
              : TranscriptRole.user;
        default:
          break;
      }
    }
    return null;
  }

  static String? _pendingRequestId(List<String> tail) {
    for (final line in tail.reversed) {
      final decoded = decodeJsonLine(line);
      if (decoded is! Map) continue;
      final payload = decoded['payload'];
      if (payload is! Map) continue;
      final type = payload['type'];
      if (type == 'exec_approval_request' ||
          type == 'apply_patch_approval_request' ||
          type == 'request_permissions') {
        final value = payload['call_id'] ?? payload['id'];
        return value is String && value.trim().isNotEmpty ? value.trim() : null;
      }
      // 其他事件说明流程已经继续，不再有待确认项。
      return null;
    }
    return null;
  }
}
