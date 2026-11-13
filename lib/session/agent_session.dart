/// Agent 会话的元数据与持久化。
///
/// 一个会话对应一个 JSON 文件，存在应用数据目录下。写入先落临时文件再改名，
/// 中途崩溃不会留下半截 JSON。读到的坏文件直接跳过，不影响其它会话。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 会话列表展示所需的元数据。
class AgentSessionMeta {
  const AgentSessionMeta({
    required this.id,
    required this.projectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  AgentSessionMeta copyWith({String? title, DateTime? updatedAt}) =>
      AgentSessionMeta(
        id: id,
        projectId: projectId,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// 一次会话的持久化内容。
///
/// [messages] 是界面展示用的消息，[history] 是模型对话历史。两者分开存：
/// 展示内容可以被界面裁剪，历史必须保持 `tool_calls` 与 `tool` 回复配对。
class AgentTranscript {
  const AgentTranscript({this.messages = const [], this.history = const []});

  static const AgentTranscript empty = AgentTranscript();

  final List<Map<String, Object?>> messages;
  final List<Map<String, Object?>> history;
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

  /// 读取会话内容；不存在时返回 [AgentTranscript.empty]。
  Future<AgentTranscript> read(String sessionId);

  /// 覆盖写入会话内容，并刷新 `updatedAt`。
  Future<void> write(String sessionId, AgentTranscript transcript);
}

/// 文件持久化实现：`<root>/<sessionId>.json`。
class FileAgentSessionStore extends AgentSessionStore {
  FileAgentSessionStore({required Directory root}) : _root = root;

  final Directory _root;

  final Map<String, AgentSessionMeta> _metas = {};

  /// 目录尚未创建时 `load` 不报错，只当作空列表。
  bool _loaded = false;

  /// 同一毫秒内创建多个会话时的序号，避免 id 重复。
  int _sequence = 0;

  static const int _maxTitleChars = 60;

  Directory get _rootDir => _root;

  File _fileFor(String sessionId) =>
      File(p.join(_root.path, '$sessionId.json'));

  @override
  Future<void> load() async {
    _metas.clear();
    _loaded = true;
    if (!await _rootDir.exists()) {
      notifyListeners();
      return;
    }
    final entries = await _rootDir.list(followLinks: false).toList();
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (!name.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entry.readAsString());
        final meta = _metaFromJson(decoded);
        if (meta == null) continue;
        _metas[meta.id] = meta;
      } on FileSystemException {
        // 读不到的文件跳过。
      } on FormatException {
        // 坏 JSON 跳过，不阻塞其它会话。
      }
    }
    notifyListeners();
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
    await _persist(meta, AgentTranscript.empty);
    notifyListeners();
    return meta;
  }

  @override
  Future<void> rename(String sessionId, String title) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    final cleaned = _cleanTitle(title);
    if (cleaned == null) return;
    final next = meta.copyWith(title: cleaned, updatedAt: DateTime.now());
    _metas[sessionId] = next;
    await _persist(next, await read(sessionId));
    notifyListeners();
  }

  @override
  Future<void> delete(String sessionId) async {
    if (_metas.remove(sessionId) == null) return;
    final file = _fileFor(sessionId);
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 文件已不在，元数据一并消失即可。
    }
    notifyListeners();
  }

  @override
  Future<AgentTranscript> read(String sessionId) async {
    final file = _fileFor(sessionId);
    if (!await file.exists()) return AgentTranscript.empty;
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

  @override
  Future<void> write(String sessionId, AgentTranscript transcript) async {
    final meta = _metas[sessionId];
    if (meta == null) return;
    final next = meta.copyWith(updatedAt: DateTime.now());
    _metas[sessionId] = next;
    await _persist(next, transcript);
    notifyListeners();
  }

  /// 先写临时文件再改名；目标已存在时先删除（Windows 上 rename 不覆盖）。
  Future<void> _persist(
    AgentSessionMeta meta,
    AgentTranscript transcript,
  ) async {
    if (!await _rootDir.exists()) {
      await _rootDir.create(recursive: true);
    }
    final target = _fileFor(meta.id);
    final temp = File('${target.path}.tmp');
    final payload = jsonEncode({
      ...meta.toJson(),
      'messages': transcript.messages,
      'history': transcript.history,
    });
    await temp.writeAsString(payload, flush: true);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
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
    return AgentSessionMeta(
      id: id,
      projectId: projectId,
      title: title is String && title.trim().isNotEmpty
          ? title
          : AgentSessionStore.defaultTitle,
      createdAt: created ?? DateTime.now(),
      updatedAt: updated ?? created ?? DateTime.now(),
    );
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is Map) Map<String, Object?>.from(entry),
    ];
  }

  static String? _cleanTitle(String? title) {
    final flat = title?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (flat.isEmpty) return null;
    return flat.length <= _maxTitleChars
        ? flat
        : '${flat.substring(0, _maxTitleChars)}…';
  }
}
