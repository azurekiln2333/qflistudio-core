import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/local_store_backend.dart';

/// 默认的持久化后端。
///
/// 测试进程里用内存后端：一次运行写下工具页状态不会污染下一次运行，
/// 也不会在 widget 测试里留下未完成的真实 I/O 定时器。
/// 应用进程里写 `AppPaths.storageDirectory()/tools_state.json`。
LocalStoreBackend defaultToolStateBackend() {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return LocalMemoryBackend();
  }
  return const LocalFileBackend(toolStateFileName);
}

/// 工具页状态的默认文件名。
const String toolStateFileName = 'tools_state.json';

/// 工具页的两种显示密度。
///
/// 与 netrix 的 `ToolCardDensity` 同名同序：[standard] 是宽松显示（卡片网格），
/// [compact] 是紧密显示（每行一个工具）。持久化的字符串就是 [name]，
/// 与 netrix 的 `standard` / `compact` 完全一致，重启和跨版本都能读回。
enum ToolCardDensity { standard, compact }

/// 工具页的本地状态：显示密度、列数、收藏和使用记录。
///
/// 沿用内核已经有的本地存储约定（[LocalStoreBackend]），默认写
/// `AppPaths.storageDirectory()/tools_state.json`。
/// 保留 netrix 的显示密度、收藏和使用记录字段。
class ToolStateStore extends ChangeNotifier {
  ToolStateStore({
    LocalStoreBackend? backend,
    Duration flushDelay = Duration.zero,
  }) : _backend = backend ?? defaultToolStateBackend(),
       _flushDelay = flushDelay;

  /// 工具页共用的实例。应用进程内只加载和写入一次。
  static final ToolStateStore instance = ToolStateStore();

  static const String defaultDensity = 'standard';
  static const int defaultCardColumns = 1;
  static const int maxRecent = 12;

  /// 设置文件里的显示密度字段。
  static const String densityKey = 'cardDensity';

  /// 宽松模式的列数字段，只接受 1 或 2。
  static const String cardColumnsKey = 'cardColumns';

  /// 设置文件里的收藏字段，值为工具标识列表。
  static const String favoritesKey = 'favorites';

  /// 设置文件里的使用记录字段，最新的在前。
  static const String recentKey = 'recent';

  final LocalStoreBackend _backend;
  final Duration _flushDelay;

  ToolCardDensity _density = ToolCardDensity.standard;
  int _cardColumns = defaultCardColumns;
  Set<String> _favorites = const <String>{};
  List<String> _recent = const <String>[];
  bool _loaded = false;
  Future<void> _writes = Future<void>.value();

  ToolCardDensity get density => _density;

  int get cardColumns => _cardColumns;

  Set<String> get favorites => Set<String>.unmodifiable(_favorites);

  List<String> get recent => List<String>.unmodifiable(_recent);

  bool get loaded => _loaded;

  /// 读取持久化状态。文件缺失、损坏或不可读时保持默认值。
  Future<void> load() async {
    try {
      final raw = await _backend.read();
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _density = _decodeDensity(decoded[densityKey]);
          _cardColumns = _decodeCardColumns(decoded[cardColumnsKey]);
          _favorites = _decodeIds(decoded[favoritesKey]);
          _recent = _decodeRecent(decoded[recentKey]);
        }
      }
    } on Object {
      // 配置损坏时用默认值，与 netrix 的处理一致。
    }
    _loaded = true;
    notifyListeners();
  }

  /// 设置显示密度并持久化。非法值被忽略。
  Future<void> setDensity(ToolCardDensity value) {
    if (_density == value) return _writes;
    _density = value;
    notifyListeners();
    return _persist();
  }

  /// 保存宽松模式的列数。
  Future<void> setCardColumns(int value) {
    if ((value != 1 && value != 2) || _cardColumns == value) return _writes;
    _cardColumns = value;
    notifyListeners();
    return _persist();
  }

  /// 记录一个工具被打开，最新的排在最前，最多保留 [maxRecent] 条。
  Future<void> recordRecent(String toolId) {
    final id = toolId.trim();
    if (id.isEmpty) return _writes;
    final next = <String>[id, ..._recent.where((item) => item != id)];
    if (next.length > maxRecent) next.removeRange(maxRecent, next.length);
    _recent = List<String>.unmodifiable(next);
    notifyListeners();
    return _persist();
  }

  Future<void> clearRecent() {
    _recent = const <String>[];
    notifyListeners();
    return _persist();
  }

  /// 切换收藏并持久化。返回切换后的状态。
  Future<bool> toggleFavorite(String toolId) {
    final id = toolId.trim();
    if (id.isEmpty) return Future<bool>.value(false);
    final next = <String>{..._favorites};
    final added = !next.remove(id);
    if (added) next.add(id);
    _favorites = Set<String>.unmodifiable(next);
    notifyListeners();
    _persist();
    return Future<bool>.value(added);
  }

  /// 等待所有排队中的写入落盘。测试在断言持久化结果前调用。
  Future<void> settled() async {
    while (true) {
      final pending = _writes;
      await pending;
      if (identical(pending, _writes)) return;
    }
  }

  Future<void> _persist() {
    final payload = jsonEncode(<String, Object>{
      'version': 1,
      densityKey: _density.name,
      cardColumnsKey: _cardColumns,
      favoritesKey: _favorites.toList()..sort(),
      recentKey: _recent,
    });
    Future<void> write() async {
      try {
        await _backend.write(payload);
      } on Object {
        // 写入失败只影响下次启动，内存里的选择仍然可用。
      }
    }

    Future<void> scheduled() {
      if (_flushDelay == Duration.zero) return write();
      return Future<void>.delayed(_flushDelay).then((_) => write());
    }

    final previous = _writes;
    return _writes = previous.then((_) => scheduled());
  }

  static ToolCardDensity _decodeDensity(Object? raw) {
    return raw is String && ToolCardDensity.values.any((v) => v.name == raw)
        ? ToolCardDensity.values.firstWhere((v) => v.name == raw)
        : ToolCardDensity.standard;
  }

  static int _decodeCardColumns(Object? raw) =>
      raw is int && (raw == 1 || raw == 2) ? raw : defaultCardColumns;

  static Set<String> _decodeIds(Object? raw) {
    if (raw is! List) return const <String>{};
    return Set<String>.unmodifiable(<String>{
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    });
  }

  static List<String> _decodeRecent(Object? raw) {
    if (raw is! List) return const <String>[];
    final ids = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final id = item.trim();
      if (id.isEmpty || ids.contains(id)) continue;
      ids.add(id);
      if (ids.length == maxRecent) break;
    }
    return List<String>.unmodifiable(ids);
  }
}
