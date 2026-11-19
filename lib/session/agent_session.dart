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
import 'dart:isolate';

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

  /// 单条记录超过这个字节数就放到独立 isolate 解析。
  static const int _isolateThreshold = 200 * 1024;

  /// 同一个文件里允许保留的历史快照行数。
  /// 超过这个数就重写（prd R14）。
  static const int _maxHistoryRows = 20;

  /// 会话文件大小上限。
  /// 超过这个大小就重写。
  static const int _maxSessionBytes = 8 * 1024 * 1024;

  /// 读历史时最多取多少条；控制器自己还会再裁一次。
  static const int _maxHistoryEntries = 200;

  final Directory _root;

  final Map<String, AgentSessionMeta> _metas = {};

  /// 目录尚未创建时 `load` 不报错，只当作空列表。
  bool _loaded = false;

  /// 同一毫秒内创建多个会话时的序号，避免 id 重复。
  int _sequence = 0;

  Timer? _indexTimer;
  Future<void> _chain = Future<void>.value();
  Future<void> _migration = Future<void>.value();

  /// 已经检查过垃圾行比例的会话，避免反复全量扫。
  final Set<String> _compactChecked = {};

  /// 每个会话现有的历史快照行数。追加 `hs` 时累加。
  final Map<String, int> _historyRows = {};

  /// 正在重写的会话，避免同时排两次重写。
  final Set<String> _compacting = {};

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
    if (await jsonl.exists()) {
      final transcript = await _readJsonl(jsonl);
      _scheduleCompaction(sessionId);
      return transcript;
    }
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
    await _rewrite(sessionId, _payloadOf(next, transcript));
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
    // 边读边解：遇到第一条能用的 hs 就停，不先把候选行攒起来。
    // 写坏的、或者根本不是 hs 的行继续往前找，一直找到文件头。
    await _LineTail(file, blockSize: blockSize).readReverseLines(
      (_) => true,
      onLineBytes: (raw) async {
        if (!_mayBeHistoryBytes(raw)) return true;
        final history = await _decodeHistoryRecord(raw);
        if (history == null) return true;
        found = history;
        return false;
      },
    );
    final history = found;
    if (history == null) return const [];
    if (history.length <= _maxHistoryEntries) return history;
    return history.sublist(history.length - _maxHistoryEntries);
  }

  /// 解开一条历史快照。
  ///
  /// 返回 null 表示这行不是可用的 `hs`：不是历史记录、或者 JSON 已经写坏。
  /// 两种情况都该继续往前找，所以不区分。
  Future<List<Map<String, Object?>>?> _decodeHistoryRecord(
    List<int> bytes,
  ) async {
    if (bytes.length > _isolateThreshold) {
      // compute 内部抛的 FormatException 会包一层：这里兜住，当作坏快照。
      try {
        return await compute(_decodeHistoryInIsolate, bytes);
      } catch (_) {
        return null;
      }
    }
    try {
      return _decodeHistoryBytes(bytes);
    } on FormatException {
      return null;
    }
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
    final rows = (_historyRows[sessionId] ?? 0) + 1;
    _historyRows[sessionId] = rows;
    if (rows <= _maxHistoryRows && await _sizeWithinLimit(sessionId)) return;
    await _compactNow(sessionId);
  }

  /// 文件还在大小上限以内时返回真。
  Future<bool> _sizeWithinLimit(String sessionId) async {
    try {
      final file = _jsonlFor(sessionId);
      if (!await file.exists()) return true;
      return await file.length() <= _maxSessionBytes;
    } on FileSystemException {
      return true;
    }
  }

  @override
  Future<void> flush() async {
    _indexTimer?.cancel();
    _indexTimer = null;
    await _writeIndexNow();
    await _chain;
  }

  /// 坏行比例过半、快照行数过多或文件过大时重写。
  ///
  /// 这里会读全文件，所以它不挂在打开会话的路径上，也不会在界面 isolate
  /// 上做：大于阈值的文件交给独立 isolate 扫。
  Future<void> compactIfNeeded(String sessionId) async {
    if (!_compactChecked.add(sessionId)) return;
    try {
      final file = _jsonlFor(sessionId);
      if (!await file.exists()) return;
      final scan = await _scanRows(file);
      if (scan == null) return;
      final (total, bad, historyRows) = scan;
      _historyRows[sessionId] = historyRows;
      final broken = bad > 0 && bad * 2 > total;
      if (!broken &&
          historyRows <= _maxHistoryRows &&
          await _sizeWithinLimit(sessionId)) {
        return;
      }
      await _compactNow(sessionId);
    } on FileSystemException {
      // 压缩失败就下次再说。
    } on FormatException {
      // 同上。
    }
  }

  /// 重写文件：只保留文件头、全部 `m` 行和最后一份 `hs`。
  ///
  /// 读写都在串行链上做，中途不会插进追加写入。大文件交给独立 isolate
  /// 拼好文本，只把结果拷回来。
  ///
  /// 快照计数不重置：越过上限后每次追加都留下唯一一份快照。
  Future<void> _compactNow(String sessionId) async {
    if (!_compacting.add(sessionId)) return;
    try {
      final meta = _metas[sessionId];
      if (meta == null) return;
      final file = _jsonlFor(sessionId);
      await _serialize(() async {
        if (!await file.exists()) return;
        final header = jsonEncode(_headerRecord(meta));
        final length = await file.length();
        final payload = length > _isolateThreshold
            ? await Isolate.run(() => _compactInIsolate(file.path, header))
            : _compactPayloadSync(await file.readAsString(), header);
        await _writePayload(file, payload);
      });
    } on FileSystemException {
      // 下次再试。
    } finally {
      _compacting.remove(sessionId);
    }
  }

  /// 后台排队做一次坏行扫描；真正的扫描由 [compactIfNeeded] 去重。
  void _scheduleCompaction(String sessionId) {
    if (_compactChecked.contains(sessionId)) return;
    unawaited(compactIfNeeded(sessionId));
  }

  /// 扫一遍全文件，返回（总行数, 坏行数, 快照行数）。空文件返回 null。
  ///
  /// 大文件放到独立 isolate，避免占住界面 isolate 的一帧。
  Future<(int, int, int)?> _scanRows(File file) async {
    final length = await file.length();
    if (length == 0) return null;
    if (length <= _isolateThreshold) {
      return _scanRowsSync(await file.readAsString());
    }
    return Isolate.run(() => _scanRowsInIsolate(file.path));
  }

  /// 把会话正文编码成完整的 jsonl 文本（建文件用）。
  String _payloadOf(AgentSessionMeta meta, AgentTranscript transcript) {
    final buffer = StringBuffer()..writeln(jsonEncode(_headerRecord(meta)));
    for (final message in transcript.messages) {
      buffer.writeln(jsonEncode({'t': 'm', 'v': message}));
    }
    buffer.writeln(jsonEncode({'t': 'hs', 'v': transcript.history}));
    return buffer.toString();
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
    await _LineTail(file, blockSize: blockSize).readReverseLines(
      (_) => true,
      onLineBytes: (bytes) {
        // 历史快照单行就能到几 MB。分页只要消息，先在字节上看类型前缀：
        // 认出是 hs / hdr 就直接跳过，不做 UTF-8 解码也不做 JSON 解码。
        if (isOtherRecordBytes(bytes)) return true;
        final record = _decodeLine(utf8.decode(bytes, allowMalformed: true));
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
      },
    );
    if (!reached) return AgentMessagePage.empty;
    final page = collected.take(limit).toList().reversed.toList();
    // 打开会话的路径不扫全文件：坏行修复留给 read()。
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
  Future<void> _appendRecord(String sessionId, Map<String, Object?> record) {
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

  /// 整文件重写：只在 `write()`、迁移与压缩时使用。
  Future<void> _rewrite(String sessionId, String payload) {
    return _serialize(() => _writePayload(_jsonlFor(sessionId), payload));
  }

  /// 写一份完整的文件内容。
  /// 调用方负责串行化。
  Future<void> _writePayload(File target, String payload) async {
    if (!await _root.exists()) await _root.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
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
    final buffer = StringBuffer()..writeln(jsonEncode(_headerRecord(meta)));
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

  /// 分页里能不能直接跳过这一行。
  ///
  /// 只认 canonical 写法：应用自己写的行永远从列 0 开始、格式固定，
  /// 所以绝大多数行一次比较就完事。认不出来就返回 false，
  /// 让调用方照旧解码判定，宁可多解一行也不能把消息当成快照丢掉。
  static bool isOtherRecordBytes(List<int> bytes) {
    return _startsWithBytes(bytes, _historyPrefixBytes) ||
        _startsWithBytes(bytes, _headerPrefixBytes);
  }

  /// 值不值得当成历史快照去试。
  ///
  /// 快捷路径先认 canonical 写法；认不出来只排除明显的消息行和空行，
  /// 剩下的交给真解码去判。
  static bool _mayBeHistoryBytes(List<int> bytes) {
    if (_startsWithBytes(bytes, _historyPrefixBytes)) return true;
    if (_startsWithBytes(bytes, _messagePrefixBytes)) return false;
    if (bytes.isEmpty) return false;
    var index = 0;
    while (index < bytes.length && _isJsonSpace(bytes[index])) {
      index++;
    }
    // 不是 JSON 对象开头的行不可能是快照。
    return index < bytes.length && bytes[index] == _braceOpen;
  }

  static bool _startsWithBytes(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  static bool _isJsonSpace(int byte) =>
      byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;

  static const int _braceOpen = 0x7B;

  /// 小快照就地解码；不是 `hs` 或结构不对时返回 null。
  static List<Map<String, Object?>>? _decodeHistoryBytes(List<int> bytes) =>
      _historyFrom(jsonDecode(utf8.decode(bytes, allowMalformed: true)));

  /// 与写端 `jsonEncode({"t": "hs"})` / `{"t": "hdr"}` / `{"t": "m"}` 一致。
  static final List<int> _historyPrefixBytes = utf8.encode('{"t":"hs",');
  static final List<int> _headerPrefixBytes = utf8.encode('{"t":"hdr",');
  static final List<int> _messagePrefixBytes = utf8.encode('{"t":"m",');

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

/// 扫一遍 jsonl 文本，返回（总行数, 坏行数, 快照行数）。
///
/// 单独拿出来是因为隔离 isolate 只能调顶层函数。
(int, int, int) _scanRowsSync(String text) {
  var bad = 0;
  var total = 0;
  var history = 0;
  for (final row in const LineSplitter().convert(text)) {
    if (row.trim().isEmpty) continue;
    total++;
    final kind = _rowKind(row);
    if (kind == null) {
      bad++;
      continue;
    }
    if (kind == 'hs') history++;
  }
  return (total, bad, history);
}

/// 在独立 isolate 里扫文件：不把整份文本回传到界面 isolate。
(int, int, int) _scanRowsInIsolate(String path) =>
    _scanRowsSync(File(path).readAsStringSync());

/// 这一行记录的 `t` 值。读不出来时返回 null。
///
/// 与 `_decodeLine` 同口径。
String? _rowKind(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final kind = decoded['t'];
    if (kind != 'm' && kind != 'hs' && kind != 'hdr') return null;
    return kind as String;
  } on FormatException {
    return null;
  }
}

/// 重写用的完整文本：文件头、全部 `m` 行、最后一份 `hs`。
///
/// 坏行与未知类型直接丢掉，所以压缩也顺带修好了坏行。
String _compactPayloadSync(String text, String headerLine) {
  final messages = <String>[];
  String? history;
  for (final row in const LineSplitter().convert(text)) {
    final trimmed = row.trim();
    if (trimmed.isEmpty) continue;
    final kind = _rowKind(trimmed);
    if (kind == 'm') {
      messages.add(trimmed);
    } else if (kind == 'hs') {
      history = trimmed;
    }
    // 文件头重新写一份，其余未知行丢弃。
  }
  final buffer = StringBuffer()..writeln(headerLine);
  for (final row in messages) {
    buffer.writeln(row);
  }
  if (history != null) buffer.writeln(history);
  return buffer.toString();
}

/// 在独立 isolate 里拼好重写文本。
String _compactInIsolate(String path, String headerLine) =>
    _compactPayloadSync(File(path).readAsStringSync(), headerLine);

/// 把 `{"t":"hs","v":[...]}` 解析成历史列表。
///
/// 不是 `hs` 记录、或 `v` 不是列表时返回 null：调用方据此继续往前找，
/// 不能把一条 `hdr` 当成“空历史”而提前停下。
List<Map<String, Object?>>? _historyFrom(Object? decoded) {
  if (decoded is! Map || decoded['t'] != 'hs') return null;
  final value = decoded['v'];
  if (value is! List) return null;
  return [
    for (final entry in value)
      if (entry is Map) Map<String, Object?>.from(entry),
  ];
}

/// 在独立 isolate 里解历史快照。
List<Map<String, Object?>>? _decodeHistoryInIsolate(List<int> bytes) =>
    _historyFrom(jsonDecode(utf8.decode(bytes, allowMalformed: true)));

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
  ///
  /// [onLineBytes] 非空时直接交原始字节，由调用方决定要不要解码：
  /// 分页只要消息，遇到几 MB 的历史快照行就不该为它做一次 UTF-8 解码。
  ///
  /// 回调可以返回 Future：分页这种同步场景不会多付一次 await，
  /// 读历史则能边读边解码，碰到第一条可用快照就停。
  Future<void> readReverseLines(
    FutureOr<bool> Function(String line) onLine, {
    FutureOr<bool> Function(List<int> bytes)? onLineBytes,
  }) async {
    // 同步回调直接返回布尔，不进事件循环。只有真的是 Future 才 await。
    FutureOr<bool> emit(List<int> bytes) =>
        onLineBytes != null ? onLineBytes(bytes) : _emit(bytes, onLine);
    if (!await file.exists()) return;
    final RandomAccessFile handle = await file.open();
    try {
      var position = await handle.length();
      // 跨块的半行按块收集，最后拼一次。以前每读一块就拼一次更大的列表，
      // 一条 4 MB 的历史快照要多拷近 4 MB × 块数，占了打开的绝大部分时间。
      final carryParts = <List<int>>[];
      var carryLength = 0;
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
        if (tail.isNotEmpty) {
          carryParts.add(tail);
          carryLength += tail.length;
        }
        if (parts.isEmpty) {
          // 这一块里没有换行：整行还没读完，继续往左拼。
          continue;
        }
        final joined = _joinReversed(carryParts, carryLength);
        carryParts.clear();
        carryLength = 0;
        if (position > 0) {
          final head = parts.removeAt(0);
          if (head.isNotEmpty) {
            carryParts.add(head);
            carryLength += head.length;
          }
        }
        final joinedResult = emit(joined);
        if (!(joinedResult is bool ? joinedResult : await joinedResult)) return;
        for (var index = parts.length - 1; index >= 0; index--) {
          final result = emit(parts[index]);
          if (!(result is bool ? result : await result)) return;
        }
      }
      if (carryLength > 0) {
        final result = emit(_joinReversed(carryParts, carryLength));
        if (result is Future<bool>) await result;
      }
    } finally {
      await handle.close();
    }
  }

  /// 把反向收集的块拼成一条完整的行。只拷一次。
  static List<int> _joinReversed(List<List<int>> parts, int length) {
    if (parts.isEmpty) return const [];
    if (parts.length == 1) return parts.single;
    final joined = Uint8List(length);
    var offset = length;
    // parts 是按从右往左的顺序收的。
    for (final part in parts) {
      offset -= part.length;
      joined.setRange(offset, offset + part.length, part);
    }
    return joined;
  }

  static FutureOr<bool> _emit(
    List<int> bytes,
    FutureOr<bool> Function(String line) onLine,
  ) {
    if (bytes.isEmpty) return true;
    final line = utf8.decode(bytes, allowMalformed: true).trim();
    if (line.isEmpty) return true;
    return onLine(line);
  }
}
