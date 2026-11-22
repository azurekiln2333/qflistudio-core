/// 会话日志读取的公共部分。
///
/// 三个 harness 的日志都是 jsonl，但字段名各不相同。公共层只负责四件事：
/// 找到最近的日志文件、按尾部窗口读行、把一行映射成 [TranscriptEvent]、
/// 提供稳定的会话 id。读取器只读文件，从不写入，也不打印日志内容。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../harness_host.dart';
import 'harness_provider.dart';

/// 单行字符上限。超过的行多半是内联附件，直接跳过。
const int kLogMaxLineChars = 256 * 1024;

/// 默认的尾部窗口大小。
const int kLogTailBytes = 512 * 1024;

/// 列表阶段读的头部大小，用于取工作目录与标题。
const int kLogHeadBytes = 16 * 1024;

/// 列表阶段读的尾部大小，用于判断最后一条事件。
const int kLogStatusBytes = 8 * 1024;

/// 日志里发现的一条历史会话。
class LogSessionRef {
  const LogSessionRef({
    required this.providerId,
    required this.id,
    required this.title,
    required this.filePath,
    required this.updatedAt,
    this.workingDirectory,
    this.lastRole,
    this.pendingRequestId,
  });

  final String providerId;

  /// 稳定 id：`log:<providerId>:<文件名>`。
  final String id;
  final String title;
  final String filePath;
  final DateTime updatedAt;
  final String? workingDirectory;

  /// 最后一条事件的角色；空日志为 null。
  final TranscriptRole? lastRole;

  /// 最后一条事件是待回复的请求时，它的 requestId。
  final String? pendingRequestId;

  /// 由尾部状态推断的会话状态。
  HarnessSessionStatus get status {
    if (pendingRequestId != null) return HarnessSessionStatus.blocked;
    return switch (lastRole) {
      TranscriptRole.assistant => HarnessSessionStatus.done,
      TranscriptRole.tool => HarnessSessionStatus.idle,
      TranscriptRole.user => HarnessSessionStatus.working,
      TranscriptRole.system => HarnessSessionStatus.idle,
      null => HarnessSessionStatus.unknown,
    };
  }

  /// 缩略标题：空标题回落到固定文案。
  String get displayTitle => title.trim().isEmpty ? '历史会话' : title.trim();
}

/// 会话日志读取器。
abstract class TranscriptLogReader {
  const TranscriptLogReader({
    required this.providerId,
    required this.format,
    required this.rootPath,
  });

  final String providerId;
  final HarnessLogFormat format;

  /// 日志根目录的绝对路径。
  final String rootPath;

  /// 最近的会话，按修改时间倒序。
  Future<List<LogSessionRef>> listSessions({int maxSessions = 40});

  /// 读取一个文件的尾部事件。
  Future<List<TranscriptEvent>> read(
    String filePath, {
    int maxEvents = 400,
    int maxBytes = kLogTailBytes,
  });

  /// 读取失败时的诊断信息，供设置页显示。不包含日志内容。
  List<String> get warnings => const <String>[];
}

/// 读取 jsonl 文件末尾的若干字节并切行。
///
/// 从中间开始读时第一行可能是半行，丢弃它。文件不存在或读取失败时返回
/// 空列表。
Future<List<String>> readJsonlTail(
  String path, {
  int maxBytes = kLogTailBytes,
  int maxLineChars = kLogMaxLineChars,
}) async {
  final lines = await readJsonlTailLines(
    path,
    maxBytes: maxBytes,
    maxLineChars: maxLineChars,
  );
  return <String>[for (final line in lines) line.text];
}

/// 一行 jsonl 及其在文件里的字节偏移。
///
/// 偏移用于生成稳定的事件 id：尾部窗口滑动后下标会变，字节偏移不会（日志
/// 只追加不重写），因此同一条消息重读后 id 仍然一样。
class JsonlLine {
  const JsonlLine({required this.text, required this.offset});

  final String text;

  /// 该行第一个字节在文件中的绝对偏移。
  final int offset;
}

/// 与 [readJsonlTail] 相同，但保留每行的字节偏移。
Future<List<JsonlLine>> readJsonlTailLines(
  String path, {
  int maxBytes = kLogTailBytes,
  int maxLineChars = kLogMaxLineChars,
}) async {
  RandomAccessFile? handle;
  try {
    handle = await File(path).open();
    final length = await handle.length();
    if (length == 0) return const <JsonlLine>[];
    final start = length > maxBytes ? length - maxBytes : 0;
    await handle.setPosition(start);
    final bytes = await handle.read(length - start);
    final result = <JsonlLine>[];
    var cursor = start;
    var index = 0;
    while (cursor < length) {
      final newline = bytes.indexOf(0x0a, index);
      final end = newline < 0 ? bytes.length : newline;
      final lineBytes = bytes.sublist(index, end);
      final lineStart = cursor;
      index = end + 1;
      cursor = lineStart + lineBytes.length + 1;
      // 第一行可能是被截断的半行，不能当作完整事件。
      if (start > 0 && lineStart == start) continue;
      final text = const Utf8Decoder(
        allowMalformed: true,
      ).convert(lineBytes).trim();
      if (text.isEmpty || text.length > maxLineChars) continue;
      result.add(JsonlLine(text: text, offset: lineStart));
    }
    return result;
  } on FileSystemException {
    return const <JsonlLine>[];
  } finally {
    await handle?.close();
  }
}

/// 读取 jsonl 文件开头的若干字节并切行，用于取元数据。
Future<List<String>> readJsonlHead(
  String path, {
  int maxBytes = kLogHeadBytes,
  int maxLineChars = kLogMaxLineChars,
}) async {
  final text = await _readWindow(path, maxBytes: maxBytes, fromEnd: false);
  return _splitLines(text, maxLineChars: maxLineChars);
}

Future<String> _readWindow(
  String path, {
  required int maxBytes,
  required bool fromEnd,
}) async {
  RandomAccessFile? handle;
  try {
    handle = await File(path).open();
    final length = await handle.length();
    if (length == 0) return '';
    final start = fromEnd && length > maxBytes ? length - maxBytes : 0;
    final count = fromEnd
        ? length - start
        : (length > maxBytes ? maxBytes : length);
    await handle.setPosition(start);
    final bytes = await handle.read(count);
    var text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    if (fromEnd && start > 0) {
      // 第一行是被截断的半行。
      final newline = text.indexOf('\n');
      text = newline < 0 ? '' : text.substring(newline + 1);
    } else if (!fromEnd && length > maxBytes) {
      // 最后一行可能被截断，不能当作完整事件。
      final newline = text.lastIndexOf('\n');
      text = newline < 0 ? '' : text.substring(0, newline);
    }
    return text;
  } on FileSystemException {
    return '';
  } finally {
    await handle?.close();
  }
}

List<String> _splitLines(String text, {required int maxLineChars}) {
  if (text.isEmpty) return const <String>[];
  final lines = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.length > maxLineChars) continue;
    lines.add(line);
  }
  return lines;
}

/// 递归列出 [root] 下的 jsonl 文件，按修改时间倒序。
List<File> recentJsonlFiles(
  Directory root, {
  int maxSessions = 40,
  int maxDepth = 3,
}) {
  if (!root.existsSync()) return const <File>[];
  final files = <File>[];
  void walk(Directory directory, int depth) {
    if (depth > maxDepth) return;
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      if (entry is Directory) {
        walk(entry, depth + 1);
      } else if (entry is File && entry.path.endsWith('.jsonl')) {
        files.add(entry);
      }
    }
  }

  walk(root, 0);
  files.sort((File a, File b) => _modified(b).compareTo(_modified(a)));
  return files.length > maxSessions ? files.sublist(0, maxSessions) : files;
}

DateTime _modified(File file) {
  try {
    return file.statSync().modified;
  } on FileSystemException {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// 解析一行 jsonl；空行、坏行与非对象行返回 null。
Object? decodeJsonLine(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// 把消息内容压成纯文本。
///
/// 支持字符串、`{type: text, text: ...}` 数组与 `tool_result` 数组。
String textFromContent(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      final text = textFromContent(item);
      if (text.trim().isNotEmpty) parts.add(text);
    }
    return parts.join('\n');
  }
  if (content is Map) {
    final text = content['text'];
    if (text is String) return text;
    final raw = content['content'];
    if (raw != null) return textFromContent(raw);
    final result = content['result'];
    if (result is String) return result;
  }
  return '';
}

/// 取一段文本的摘要：折叠空白并截断。
String summarizeText(String value, {int maxChars = 400}) {
  final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxChars) return collapsed;
  return '${collapsed.substring(0, maxChars)}…';
}

/// 解析 ISO 时间戳。
DateTime? parseLogTimestamp(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// 用工作目录的最后一段做标题。
String? titleFromCwd(String? cwd) {
  if (cwd == null || cwd.trim().isEmpty) return null;
  return p.basename(cwd.trim().replaceAll(r'\', '/'));
}

/// 稳定的会话 id。
///
/// 用相对日志根目录的路径，避免不同项目目录下的同名文件互相覆盖。
String logSessionId(String providerId, String filePath, {String? rootPath}) {
  var relative = filePath;
  if (rootPath != null && rootPath.isNotEmpty) {
    final normalizedRoot = p.normalize(rootPath);
    final normalizedFile = p.normalize(filePath);
    if (p.isWithin(normalizedRoot, normalizedFile)) {
      relative = p.relative(normalizedFile, from: normalizedRoot);
    }
  }
  return 'log:$providerId:${relative.replaceAll(r'\', '/')}';
}

/// 为一行日志生成事件 id。
///
/// [offset] 是 [JsonlLine.offset]（文件内字节偏移），不是窗口内下标，
/// 因此尾部窗口滑动后同一条消息的 id 不变。
String logEventId(String sessionBase, int offset, [int part = 0]) =>
    part == 0 ? '$sessionBase#$offset' : '$sessionBase#$offset/$part';

/// 由头部行推断工作目录；没有则返回 null。
String? cwdFromLines(List<String> lines, {String key = 'cwd'}) {
  for (final line in lines) {
    final decoded = decodeJsonLine(line);
    if (decoded is! Map) continue;
    for (final container in <Object?>[
      decoded,
      decoded['payload'],
      decoded['message'],
      decoded['session'],
    ]) {
      final value = container is Map ? container[key] : null;
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }
  return null;
}

/// 由头部行推断会话 id；没有则返回 null。
String? idFromLines(List<String> lines, {String key = 'id'}) {
  for (final line in lines) {
    final decoded = decodeJsonLine(line);
    if (decoded is! Map) continue;
    for (final container in <Object?>[
      decoded,
      decoded['payload'],
      decoded['message'],
      decoded['session'],
    ]) {
      final value = container is Map ? container[key] : null;
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }
  return null;
}

/// 文件名去掉扩展名。
String basenameWithoutExtension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}
