/// Agent 会话的元数据与持久化。
///
/// v2 布局（根目录 `agent_sessions/`）：
///
/// - `index.json`：全部会话的元数据数组，列表只读这个文件。
/// - `<会话id>.jsonl`：第 1 行是头，之后每行一条记录。消息视图与模型历史
///   快照分开记，写入是追加一行，不重写整个文件。
/// - `<会话id>.json`：v1 旧文件，迁移后改名为 `.json.bak` 保留。
///
/// 读取规则：列表只碰索引；打开会话只从文件尾部反向读，凑够一页即可。
/// 坏行跳过，崩溃最多丢最后一行。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'agent_perf.dart';

/// 会话列表展示所需的元数据。
class AgentSessionMeta {
  const AgentSessionMeta({
    required this.id,
    required this.projectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.preview = '',
  });

  final String id;
  final String projectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 已保存的消息条数，列表不用打开文件就能显示规模。
  final int messageCount;

  /// 最近一条消息的一行预览，空串表示还没有消息。
  final String preview;

  AgentSessionMeta copyWith({
    String? title,
    DateTime? updatedAt,
    int? messageCount,
    String? preview,
  }) => AgentSessionMeta(
    id: id,
    projectId: projectId,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messageCount: messageCount ?? this.messageCount,
    preview: preview ?? this.preview,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messageCount': messageCount,
    'preview': preview,
  };
}

/// 一次会话的完整内容。
///
/// [messages] 是界面展示用的消息，[history] 是模型对话历史。两者分开存：
/// 展示内容可以被界面裁剪，历史必须保持 `tool_calls` 与 `tool` 回复配对。
class AgentTranscript {
  const AgentTranscript({this.messages = const [], this.history = const []});

  static const AgentTranscript empty = AgentTranscript();

  final List<Map<String, Object?>> messages;
  final List<Map<String, Object?>> history;
}

/// 一页消息视图。
///
/// [hasEarlier] 为真表示文件里还有更早的消息，界面可以显示「载入更早」。
class AgentMessagePage {
  const AgentMessagePage({this.messages = const [], this.hasEarlier = false});

  static const AgentMessagePage empty = AgentMessagePage();

  final List<Map<String, Object?>> messages;
  final bool hasEarlier;
}

/// 会话存储。列表变化后通知监听者。
abstract class AgentSessionStore extends ChangeNotifier {
  /// 新会话的默认标题。
  static const String defaultTitle = '新会话';

  /// 读磁盘；可重复调用。
  Future<void> load();

  /// 某个项目的会话，`updatedAt` 倒序。
  List<AgentSessionMeta> sessionsOf(String projectId);

  AgentSessionMeta? metaOf(String sessionId);

  Future<AgentSessionMeta> create(String projectId, {String? title});

  Future<void> rename(String sessionId, String title);

  Future<void> delete(String sessionId);

  /// 读取会话全文；不存在时返回 [AgentTranscript.empty]。
  Future<AgentTranscript> read(String sessionId);

  /// 覆盖写入会话全文，并刷新 `updatedAt`。
  Future<void> write(String sessionId, AgentTranscript transcript);

  /// 只读最近 [limit] 条消息视图，不读模型历史，也不碰网络。
  ///
  /// 默认实现退回 [read]，文件实现走尾部反向读。
  Future<AgentMessagePage> readTail(String sessionId, {int limit = 60}) async {
    final transcript = await read(sessionId);
    final messages = transcript.messages;
    if (messages.length <= limit) {
      return AgentMessagePage(messages: messages);
    }
    return AgentMessagePage(
      messages: messages.sublist(messages.length - limit),
      hasEarlier: true,
    );
  }

  /// 读 [beforeId] 之前的一页消息视图。
  Future<AgentMessagePage> readBefore(
    String sessionId, {
    required String beforeId,
    int limit = 60,
  }) async {
    final transcript = await read(sessionId);
    final messages = transcript.messages;
    final index = messages.indexWhere((entry) => entry['id'] == beforeId);
    if (index <= 0) return AgentMessagePage.empty;
    final start = index - limit < 0 ? 0 : index - limit;
    return AgentMessagePage(
      messages: messages.sublist(start, index),
      hasEarlier: start > 0,
    );
  }

  /// 读模型历史；第一次发送时才需要。
  Future<List<Map<String, Object?>>> readHistory(String sessionId) async =>
      (await read(sessionId)).history;

  /// 追加一条消息视图。
  Future<void> appendMessage(
    String sessionId,
    Map<String, Object?> message,
  ) async {
    final meta = metaOf(sessionId);
    if (meta == null) return;
    final transcript = await read(sessionId);
    await write(
      sessionId,
      AgentTranscript(
        messages: [...transcript.messages, message],
        history: transcript.history,
      ),
    );
  }

  /// 覆盖写入模型历史快照。
  Future<void> writeHistory(
    String sessionId,
    List<Map<String, Object?>> history,
  ) async {
    final meta = metaOf(sessionId);
    if (meta == null) return;
    final transcript = await read(sessionId);
    await write(
      sessionId,
      AgentTranscript(messages: transcript.messages, history: history),
    );
  }

  /// 等待已排队的写入落盘（退出页面前用）。
  Future<void> flush() async {}
}

/// 文件持久化实现：`index.json` 加 `<sessionId>.jsonl`。
class FileAgentSessionStore extends AgentSessionStore {
  FileAgentSessionStore({required Directory root, this.blockSize = 64 * 1024})
    : _root = root;

  /// 反向读时每次读多少字节。
  final int blockSize;

  static const int _indexVersion = 2;
  static const int _maxTitleChars = 60;
  static const int _maxPreviewChars = 80;
  static const String _indexFileName = 'index.json';
  static const Duration _indexDebounce = Duration(milliseconds: 500);

  final Directory _root;

  final Map<String, AgentSessionMeta> _metas = {};

  /// 目录尚未创建时 `load` 不报错，只当作空列表。
  bool _loaded = false;

  /// 同一毫秒内创建多个会话时的序号，避免 id 重复。
  int _sequence = 0;

  Timer? _indexTimer;
  Future<void> _chain = Future<void>.value();
  Future<void> _migration = Future<void>.value();

  Directory get root => _root;

  File get indexFile => File(p.join(_root.path, _indexFileName));

  /// 后台迁移的完成信号。
  ///
  /// 生产路径不等它：旧文件本来就不在列表里，早一点晚一点都看得见。
  /// 测试与首次启动后的自检可以 await 它。
  Future<void> get migrationDone => _migration;

  File _jsonlFor(String sessionId) =>
      File(p.join(_root.path, '$sessionId.jsonl'));

  File _legacyFor(String sessionId) =>
      File(p.join(_root.path, '$sessionId.json'));

  @override
  Future<void> load() async {
    final watch = Stopwatch()..start();
    _metas.clear();
    _loaded = true;
    try {
      final indexed = await _readIndex();
      if (indexed != null) {
        _metas.addAll(indexed);
        // 索引已就绪：旧文件迁移放到后台，不挡列表。
        _migration = _migrateLegacyFiles();
        unawaited(_migration);
      } else {
        await _rebuildIndex();
      }
    } on FileSystemException {
      // 目录不可读时当作空列表。
    } on FormatException {
      await _rebuildIndex();
    } finally {
      agentPerf('sessions.load', watch.elapsedMilliseconds);
      notifyListeners();
    }
  }

  @override
  List<AgentSessionMeta> sessionsOf(String projectId) {
    final list =
        _metas.values.where((meta) => meta.projectId == projectId).toList()
          ..sort((a, b) {
            final byUpdate = b.updatedAt.compareTo(a.updatedAt);
            if (byUpdate != 0) return byUpdate;
            final byCreate = b.createdAt.compareTo(a.createdAt);
            return byCreate != 0 ? byCreate : a.id.compareTo(b.id);
          });
    return List.unmodifiable(list);
  }

  @override
  AgentSessionMeta? metaOf(String sessionId) => _metas[sessionId];

  @override
  Future<AgentSessionMeta> create(String projectId, {String? title}) async {
    if (!_loaded) await load();
    final now = DateTime.now();
    final stamp = now.microsecondsSinceEpoch.toRadixString(36);
    final id = '$stamp-${(_sequence++).toRadixString(36)}';
    final meta = AgentSessionMeta(
      id: id,
      projectId: projectId,
      title: _cleanTitle(title) ?? AgentSessionStore.defaultTitle,
      createdAt: now,
      updatedAt: now,
    );
    _metas[id] = meta;
    await _ensureHeader(id);
    await _writeIndexNow();
    notifyListeners();
    return meta;
  }

  @override
  Future<void> rename(String sessionId, String title) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    final cleaned = _cleanTitle(title);
    if (cleaned == null) return;
    _metas[sessionId] = meta.copyWith(
      title: cleaned,
      updatedAt: DateTime.now(),
    );
    await _writeIndexNow();
    notifyListeners();
  }

  @override
  Future<void> delete(String sessionId) async {
    if (_metas.remove(sessionId) == null) return;
    final candidates = [
      _jsonlFor(sessionId),
      _legacyFor(sessionId),
      File('${_legacyFor(sessionId).path}.bak'),
    ];
    for (final file in candidates) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 文件已不在，元数据一并消失即可。
      }
    }
    await _writeIndexNow();
    notifyListeners();
  }

  @override
  Future<AgentTranscript> read(String sessionId) async {
    final jsonl = _jsonlFor(sessionId);
    if (await jsonl.exists()) return _readJsonl(jsonl);
    final legacy = _legacyFor(sessionId);
    if (await legacy.exists()) return _readLegacy(legacy);
    return AgentTranscript.empty;
  }

  @override
  Future<void> write(String sessionId, AgentTranscript transcript) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    final next = meta.copyWith(
      updatedAt: DateTime.now(),
      messageCount: transcript.messages.length,
      preview: _previewOf(transcript.messages),
    );
    _metas[sessionId] = next;
    final buffer = StringBuffer()
      ..writeln(jsonEncode(_headerRecord(next)));
    for (final message in transcript.messages) {
      buffer.writeln(jsonEncode({'t': 'm', 'v': message}));
    }
    buffer.writeln(jsonEncode({'t': 'hs', 'v': transcript.history}));
    await _rewrite(sessionId, buffer.toString());
    await _writeIndexNow();
    notifyListeners();
  }

  @override
  Future<AgentMessagePage> readTail(String sessionId, {int limit = 60}) =>
      _readPage(sessionId, limit: limit);

  @override
  Future<AgentMessagePage> readBefore(
    String sessionId, {
    required String beforeId,
    int limit = 60,
  }) => _readPage(sessionId, beforeId: beforeId, limit: limit);

  @override
  Future<List<Map<String, Object?>>> readHistory(String sessionId) async {
    final file = _jsonlFor(sessionId);
    if (!await file.exists()) {
      return (await read(sessionId)).history;
    }
    List<Map<String, Object?>>? found;
    await _LineTail(file, blockSize: blockSize).readReverseLines((line) {
      final record = _decodeLine(line);
      if (record == null || record.kind != _RecordKind.history) return true;
      found = _mapList(record.value);
      return false;
    });
    return found ?? const [];
  }

  @override
  Future<void> appendMessage(
    String sessionId,
    Map<String, Object?> message,
  ) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    final watch = Stopwatch()..start();
    await _appendRecord(sessionId, {'t': 'm', 'v': message});
    final text = message['text'];
    _metas[sessionId] = meta.copyWith(
      updatedAt: DateTime.now(),
      messageCount: meta.messageCount + 1,
      preview: text is String && text.trim().isNotEmpty
          ? _short(text)
          : meta.preview,
    );
    _scheduleIndexWrite();
    agentPerf('persist.append', watch.elapsedMilliseconds);
  }

  @override
  Future<void> writeHistory(
    String sessionId,
    List<Map<String, Object?>> history,
  ) async {
    if (_metas[sessionId] == null) return;
    await _appendRecord(sessionId, {'t': 'hs', 'v': history});
  }

  @override
  Future<void> flush() async {
    _indexTimer?.cancel();
    _indexTimer = null;
    await _writeIndexNow();
    await _chain;
  }

  @override
  void dispose() {
    _indexTimer?.cancel();
    _indexTimer = null;
    super.dispose();
  }

  // ---- 读 ----

  Future<AgentTranscript> _readJsonl(File file) async {
    final messages = <String, Map<String, Object?>>{};
    final order = <String>[];
    var history = const <Map<String, Object?>>[];
    final rows = const LineSplitter().convert(await file.readAsString());
    for (final row in rows) {
      final record = _decodeLine(row);
      if (record == null) continue;
      switch (record.kind) {
        case _RecordKind.message:
          final message = _map(record.value);
          final id = message?['id'];
          if (message == null || id is! String) continue;
          if (!messages.containsKey(id)) order.add(id);
          messages[id] = message;
        case _RecordKind.history:
          history = _mapList(record.value);
        case _RecordKind.header:
          break;
      }
    }
    return AgentTranscript(
      messages: [for (final id in order) messages[id]!],
      history: history,
    );
  }

  Future<AgentMessagePage> _readPage(
    String sessionId, {
    String? beforeId,
    required int limit,
  }) async {
    final file = _jsonlFor(sessionId);
    if (!await file.exists()) return AgentMessagePage.empty;
    final collected = <Map<String, Object?>>[];
    final seen = <String>{};
    var reached = beforeId == null;
    var more = false;
    await _LineTail(file, blockSize: blockSize).readReverseLines((line) {
      final record = _decodeLine(line);
      if (record == null || record.kind != _RecordKind.message) return true;
      final message = _map(record.value);
      final id = message?['id'];
      if (message == null || id is! String) return true;
      // 同一 id 后写的覆盖旧值；反向读时先遇到的就是最新那条。
      if (!seen.add(id)) return true;
      if (!reached) {
        if (id == beforeId) reached = true;
        return true;
      }
      collected.add(message);
      if (collected.length > limit) {
        more = true;
        return false;
      }
      return true;
    });
    if (!reached) return AgentMessagePage.empty;
    final page = collected.take(limit).toList().reversed.toList();
    return AgentMessagePage(messages: page, hasEarlier: more);
  }

  Future<AgentTranscript> _readLegacy(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return AgentTranscript.empty;
      return AgentTranscript(
        messages: _mapList(decoded['messages']),
        history: _mapList(decoded['history']),
      );
    } on FileSystemException {
      return AgentTranscript.empty;
    } on FormatException {
      return AgentTranscript.empty;
    }
  }

  // ---- 写 ----

  /// 追加一行；文件不存在时先写头。写入在串行链上执行。
  ///
  /// 崩溃可能留下半行：最后一行没以换行结尾时先补一个换行，否则新记录会
  /// 粘到坏行上，一起被当成坏行跳过。
  Future<void> _appendRecord(
    String sessionId,
    Map<String, Object?> record,
  ) {
    return _serialize(() async {
      if (!await _root.exists()) await _root.create(recursive: true);
      final file = _jsonlFor(sessionId);
      final length = await file.exists() ? await file.length() : 0;
      final needsHeader = length == 0;
      var needsNewline = false;
      if (length > 0) {
        final reader = await file.open();
        try {
          await reader.setPosition(length - 1);
          final tail = await reader.read(1);
          needsNewline = tail.isEmpty || tail.first != 0x0A;
        } finally {
          await reader.close();
        }
      }
      final sink = await file.open(mode: FileMode.append);
      try {
        if (needsHeader) {
          final meta = _metas[sessionId];
          if (meta != null) {
            await sink.writeFrom(
              utf8.encode('${jsonEncode(_headerRecord(meta))}\n'),
            );
          }
        } else if (needsNewline) {
          await sink.writeFrom(utf8.encode('\n'));
        }
        await sink.writeFrom(utf8.encode('${jsonEncode(record)}\n'));
      } finally {
        await sink.close();
      }
    });
  }

  /// 只在文件为空时写头。
  Future<void> _ensureHeader(String sessionId) {
    return _serialize(() async {
      if (!await _root.exists()) await _root.create(recursive: true);
      final file = _jsonlFor(sessionId);
      final meta = _metas[sessionId];
      if (meta == null) return;
      if (await file.exists() && await file.length() > 0) return;
      await file.writeAsString(
        '${jsonEncode(_headerRecord(meta))}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  /// 整文件重写：只在 `write()` 与迁移时使用。
  Future<void> _rewrite(String sessionId, String payload) {
    return _serialize(() async {
      if (!await _root.exists()) await _root.create(recursive: true);
      final target = _jsonlFor(sessionId);
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    });
  }

  /// 索引是派生数据：写不进去只影响下次启动的列表速度，不该把调用方炸掉。
  Future<void> _writeIndexNow() {
    _indexTimer?.cancel();
    _indexTimer = null;
    return _serialize(() async {
      try {
        if (!await _root.exists()) await _root.create(recursive: true);
        final payload = jsonEncode({
          'version': _indexVersion,
          'sessions': [for (final meta in _metas.values) meta.toJson()],
        });
        final target = indexFile;
        final temp = File('${target.path}.tmp');
        await temp.writeAsString(payload, flush: true);
        if (await target.exists()) await target.delete();
        await temp.rename(target.path);
      } on FileSystemException {
        // 盘忙或目录已被删除：下次元数据变化时再写。
      }
    });
  }

  void _scheduleIndexWrite() {
    _indexTimer?.cancel();
    _indexTimer = Timer(_indexDebounce, () {
      _indexTimer = null;
      unawaited(_writeIndexNow());
    });
  }

  /// 所有写操作串行执行，避免同一文件并发。
  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _chain.then((_) => action());
    _chain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  // ---- 索引与迁移 ----

  Future<Map<String, AgentSessionMeta>?> _readIndex() async {
    final file = indexFile;
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    final list = decoded['sessions'];
    if (list is! List) return null;
    final metas = <String, AgentSessionMeta>{};
    for (final entry in list) {
      final meta = _metaFromJson(entry);
      if (meta != null) metas[meta.id] = meta;
    }
    return metas;
  }

  /// 没有索引时逐个读旧文件建索引；读完顺手转成 jsonl。
  Future<void> _rebuildIndex() async {
    _metas.clear();
    if (!await _root.exists()) {
      await _writeIndexNow();
      return;
    }
    final entries = await _root.list(followLinks: false).toList();
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (!name.endsWith('.json') || name == _indexFileName) continue;
      final meta = await _metaFromLegacy(entry);
      if (meta == null) continue;
      _metas[meta.id] = meta;
      await _convertLegacy(entry, meta);
    }
    await _writeIndexNow();
  }

  /// 索引已就绪后，把还没转换的旧文件补转一遍（不阻塞列表）。
  Future<void> _migrateLegacyFiles() async {
    try {
      if (!await _root.exists()) return;
      final entries = await _root.list(followLinks: false).toList();
      var changed = false;
      for (final entry in entries) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (!name.endsWith('.json') || name == _indexFileName) continue;
        if (name.endsWith('.bak')) continue;
        final meta = await _metaFromLegacy(entry);
        if (meta == null) continue;
        _metas.putIfAbsent(meta.id, () => meta);
        await _convertLegacy(entry, meta);
        changed = true;
      }
      if (changed) {
        // 迁移结果必须落进索引，否则下次启动又看不到这些会话。
        await _writeIndexNow();
        notifyListeners();
      }
    } on FileSystemException {
      // 后台迁移失败就下次再试。
    }
  }

  Future<AgentSessionMeta?> _metaFromLegacy(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      final meta = _metaFromJson(decoded);
      if (meta == null) {
        await _markUnusable(file);
        return null;
      }
      return meta;
    } on FileSystemException {
      return null;
    } on FormatException {
      await _markUnusable(file);
      return null;
    }
  }

  /// 坏文件改名 `.json.bak`，下次启动不再重复解析。
  Future<void> _markUnusable(File file) async {
    try {
      final backup = File('${file.path}.bak');
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    } on FileSystemException {
      // 改名失败也不该挡住其它会话。
    }
  }

  /// 旧 `.json` → `.jsonl`，然后改名为 `.json.bak`。
  Future<void> _convertLegacy(File file, AgentSessionMeta meta) async {
    final transcript = await _readLegacy(file);
    final buffer = StringBuffer()
      ..writeln(jsonEncode(_headerRecord(meta)));
    for (final message in transcript.messages) {
      buffer.writeln(jsonEncode({'t': 'm', 'v': message}));
    }
    buffer.writeln(jsonEncode({'t': 'hs', 'v': transcript.history}));
    final target = _jsonlFor(meta.id);
    if (await target.exists()) {
      await _markUnusable(file);
      return;
    }
    await _rewrite(meta.id, buffer.toString());
    _metas[meta.id] = meta.copyWith(
      messageCount: transcript.messages.length,
      preview: _previewOf(transcript.messages),
    );
    await _markUnusable(file);
  }

  Map<String, Object?> _headerRecord(AgentSessionMeta meta) => {
    't': 'hdr',
    'v': _indexVersion,
    'id': meta.id,
    'projectId': meta.projectId,
    'createdAt': meta.createdAt.toIso8601String(),
  };

  static _Record? _decodeLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      return switch (decoded['t']) {
        'm' => _Record(_RecordKind.message, decoded['v']),
        'hs' => _Record(_RecordKind.history, decoded['v']),
        'hdr' => _Record(_RecordKind.header, decoded['v']),
        _ => null,
      };
    } on FormatException {
      // 崩溃或写坏的行：跳过，后面还有好行。
      return null;
    }
  }

  static AgentSessionMeta? _metaFromJson(Object? decoded) {
    if (decoded is! Map) return null;
    final id = decoded['id'];
    final projectId = decoded['projectId'];
    final title = decoded['title'];
    final created = DateTime.tryParse('${decoded['createdAt'] ?? ''}');
    final updated = DateTime.tryParse('${decoded['updatedAt'] ?? ''}');
    if (id is! String || id.isEmpty) return null;
    if (projectId is! String || projectId.isEmpty) return null;
    final count = decoded['messageCount'];
    final preview = decoded['preview'];
    return AgentSessionMeta(
      id: id,
      projectId: projectId,
      title: title is String && title.trim().isNotEmpty
          ? title
          : AgentSessionStore.defaultTitle,
      createdAt: created ?? DateTime.now(),
      updatedAt: updated ?? created ?? DateTime.now(),
      messageCount: count is num ? count.toInt() : 0,
      preview: preview is String ? preview : '',
    );
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return Map<String, Object?>.from(value);
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is Map) Map<String, Object?>.from(entry),
    ];
  }

  static String _previewOf(List<Map<String, Object?>> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final text = messages[index]['text'];
      if (text is String && text.trim().isNotEmpty) return _short(text);
    }
    return '';
  }

  static String _short(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= _maxPreviewChars
        ? flat
        : '${flat.substring(0, _maxPreviewChars)}…';
  }

  static String? _cleanTitle(String? title) {
    final flat = title?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (flat.isEmpty) return null;
    return flat.length <= _maxTitleChars
        ? flat
        : '${flat.substring(0, _maxTitleChars)}…';
  }
}

enum _RecordKind { header, message, history }

class _Record {
  const _Record(this.kind, this.value);

  final _RecordKind kind;
  final Object? value;
}

/// 反向逐行读：从文件尾往前，凑够调用方要的行数就停。
///
/// 只读需要的块，20 MB 的会话读最后 60 条也只是读几十 KB。
class _LineTail {
  _LineTail(this.file, {this.blockSize = 64 * 1024});

  final File file;
  final int blockSize;

  /// 逐行回调，返回 false 停止。
  Future<void> readReverseLines(bool Function(String line) onLine) async {
    if (!await file.exists()) return;
    final RandomAccessFile handle = await file.open();
    try {
      var position = await handle.length();
      var carry = <int>[];
      while (position > 0) {
        final start = position - blockSize < 0 ? 0 : position - blockSize;
        await handle.setPosition(start);
        final chunk = await handle.read(position - start);
        position = start;
        final parts = <List<int>>[];
        var current = <int>[];
        for (final byte in chunk) {
          if (byte == 0x0A) {
            parts.add(current);
            current = <int>[];
          } else {
            current.add(byte);
          }
        }
        parts.add(current);
        final tail = parts.removeLast();
        final joined = <int>[...tail, ...carry];
        if (position > 0 && parts.isNotEmpty) {
          carry = parts.removeAt(0);
        } else {
          carry = <int>[];
        }
        if (!_emit(joined, onLine)) return;
        for (var index = parts.length - 1; index >= 0; index--) {
          if (!_emit(parts[index], onLine)) return;
        }
      }
      if (carry.isNotEmpty) _emit(carry, onLine);
    } finally {
      await handle.close();
    }
  }

  static bool _emit(List<int> bytes, bool Function(String line) onLine) {
    if (bytes.isEmpty) return true;
    final line = utf8.decode(bytes, allowMalformed: true).trim();
    if (line.isEmpty) return true;
    return onLine(line);
  }
}
