import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/app_paths.dart';
import '../vibe_coding/vibe_agent_facade.dart';

/// 输入卡片的状态。
///
/// 一个实例对应一个项目的输入卡片。项目页和工作台共用同一个实现，见
/// design.md §4 第 1 条。附件只存路径，正文由 agent 用 `read_file` 取。
///
/// 附件路径按 harness 的约定存：项目内文件存相对路径（`/` 分隔），
/// 项目外文件存绝对路径。见 status/pi-B.md 的「附件传参格式」。
class ComposerState extends ChangeNotifier {
  ComposerState({
    AgentPermissionMode permission = AgentPermissionMode.askEveryWrite,
    ComposerDefaultsStore? defaults,
    String? projectId,
    String? projectRoot,
    String? modelId,
    String? reasoningEffort,
    Map<String, int> contextWindows = const {},
  }) : _permission = permission,
       _defaults = defaults,
       _projectId = projectId,
       _projectRoot = projectRoot,
       _modelId = modelId,
       // 没有模型就没有推理强度：避免把 A 模型的档位发给空选择。
       _reasoningEffort = modelId == null ? null : reasoningEffort,
       _contextWindows = Map.of(contextWindows);

  ComposerDefaultsStore? _defaults;
  String? _projectId;
  String? _projectRoot;

  String _text = '';
  final List<String> _attachments = <String>[];
  AgentPermissionMode _permission;
  String? _modelId;
  String? _reasoningEffort;
  final Map<String, int> _contextWindows;
  bool _loading = false;
  bool _disposed = false;
  Future<void> _saves = Future<void>.value();

  /// 输入框内容。
  String get text => _text;

  set text(String value) {
    if (_text == value) return;
    _text = value;
    notifyListeners();
  }

  /// 已附加的文件路径，按选择顺序。
  List<String> get attachments => List<String>.unmodifiable(_attachments);

  /// 写操作权限。
  AgentPermissionMode get permission => _permission;

  set permission(AgentPermissionMode value) {
    if (_permission == value) return;
    _permission = value;
    notifyListeners();
    _scheduleSave();
  }

  /// 选中的模型；null 表示用设置里的默认模型。
  String? get modelId => _modelId;

  /// 选中模型。换模型会清空推理强度，避免把 A 模型的档位发给 B 模型。
  set modelId(String? value) {
    if (_modelId == value) return;
    _modelId = value;
    _reasoningEffort = null;
    notifyListeners();
    _scheduleSave();
  }

  /// 推理强度；模型不支持时必须为 null。
  String? get reasoningEffort => _reasoningEffort;

  set reasoningEffort(String? value) {
    if (_reasoningEffort == value) return;
    _reasoningEffort = value;
    notifyListeners();
    _scheduleSave();
  }

  Map<String, int> get contextWindows => Map.unmodifiable(_contextWindows);

  int? contextWindowFor(String? modelId) => _contextWindows[modelId ?? ''];

  /// 按模型保存用户设置的容量，null 恢复接口值。
  void setContextWindowFor(String? modelId, int? value) {
    if (value != null && value <= 0) return;
    final key = modelId ?? '';
    if (_contextWindows[key] == value) return;
    if (value == null) {
      _contextWindows.remove(key);
    } else {
      _contextWindows[key] = value;
    }
    notifyListeners();
    _scheduleSave();
  }

  /// 默认值是否还在读盘。
  bool get loading => _loading;

  /// 有内容才能发送；只有附件没有文字也允许，用户常直接拖文件进来说「改这个」。
  bool get canSend => _text.trim().isNotEmpty || _attachments.isNotEmpty;

  /// 绑定另一个项目，并读回该项目记住的选择。
  Future<void> bindProject(
    String? projectId, {
    ComposerDefaultsStore? defaults,
    String? projectRoot,
  }) async {
    if (_projectId != projectId) _contextWindows.clear();
    _projectId = projectId;
    if (defaults != null) _defaults = defaults;
    if (projectRoot != null) _projectRoot = projectRoot;
    await loadDefaults();
  }

  /// 读回本项目记住的权限模式、模型和推理强度。
  Future<void> loadDefaults() async {
    final store = _defaults;
    final projectId = _projectId;
    if (store == null || projectId == null) return;
    _loading = true;
    _notify();
    try {
      final saved = await store.read(projectId);
      if (_disposed || _projectId != projectId) return;
      if (saved != null) {
        _permission = saved.permission;
        _modelId = saved.modelId;
        _reasoningEffort = saved.reasoningEffort;
        _contextWindows
          ..clear()
          ..addAll(saved.contextWindows);
      }
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// 把路径规范成传给 agent 的形态。
  ///
  /// 项目内的绝对路径折成相对路径（`/` 分隔），项目外保持绝对路径。
  /// 未知项目根时只统一分隔符。
  String payloadPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    final slashed = _slashed(trimmed);
    final root = _projectRoot?.trim();
    if (root == null || root.isEmpty) return slashed;
    if (!p.isAbsolute(trimmed)) return slashed;
    final base = _trimTrailingSlash(_slashed(root));
    final candidate = slashed;
    final lowerBase = base.toLowerCase();
    final lowerCandidate = candidate.toLowerCase();
    if (lowerCandidate == lowerBase) return '';
    if (!lowerCandidate.startsWith('$lowerBase/')) return slashed;
    return candidate.substring(base.length + 1);
  }

  /// 附加一个文件路径；重复附加不加入第二次。
  void attach(String path) {
    final payload = payloadPath(path);
    if (payload.isEmpty || _attachments.contains(payload)) return;
    _attachments.add(payload);
    notifyListeners();
  }

  /// 一次附加多个路径，保留顺序并去重。
  void attachAll(Iterable<String> paths) {
    var changed = false;
    for (final path in paths) {
      final payload = payloadPath(path);
      if (payload.isEmpty || _attachments.contains(payload)) continue;
      _attachments.add(payload);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 移除一个附件。
  void detach(String path) {
    if (!_attachments.remove(path)) return;
    notifyListeners();
  }

  /// 发送成功后清空输入，保留权限模式与模型选择。
  void clearInput() {
    if (_text.isEmpty && _attachments.isEmpty) return;
    _text = '';
    _attachments.clear();
    notifyListeners();
  }

  /// 当前选择，用于持久化。
  ComposerDefaults get defaults => ComposerDefaults(
    permission: _permission,
    modelId: _modelId,
    reasoningEffort: _reasoningEffort,
    contextWindows: Map.unmodifiable(_contextWindows),
  );

  /// 等已排队的写入完成。离开页面前调用，避免丢掉最后一次选择。
  Future<void> flush() => _saves;

  void _scheduleSave() {
    final store = _defaults;
    final projectId = _projectId;
    if (store == null || projectId == null || _loading) return;
    // Capture the model choices before another project or model is selected.
    final snapshot = defaults;
    _saves = _saves.then((_) => store.write(projectId, snapshot));
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  static String _slashed(String value) => value.replaceAll('\\', '/');

  static String _trimTrailingSlash(String value) =>
      value.length > 1 && value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 每个项目记住的输入卡片选择。
@immutable
class ComposerDefaults {
  const ComposerDefaults({
    this.permission = AgentPermissionMode.askEveryWrite,
    this.modelId,
    this.reasoningEffort,
    this.contextWindows = const {},
  });

  final AgentPermissionMode permission;
  final String? modelId;
  final String? reasoningEffort;
  final Map<String, int> contextWindows;

  Map<String, Object?> toJson() => {
    'permission': permission.name,
    if (modelId != null) 'modelId': modelId,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    if (contextWindows.isNotEmpty) 'contextWindows': contextWindows,
  };

  /// 坏字段逐项回落，不让一个坏值丢掉整个文件。
  static ComposerDefaults fromJson(Object? value) {
    if (value is! Map) return const ComposerDefaults();
    final rawPermission = value['permission'];
    final permission = AgentPermissionMode.values.firstWhere(
      (mode) => mode.name == rawPermission,
      orElse: () => AgentPermissionMode.askEveryWrite,
    );
    final modelId = value['modelId'];
    final effort = value['reasoningEffort'];
    final windows = value['contextWindows'];
    return ComposerDefaults(
      permission: permission,
      modelId: modelId is String && modelId.trim().isNotEmpty ? modelId : null,
      reasoningEffort: effort is String && effort.trim().isNotEmpty
          ? effort
          : null,
      contextWindows: Map.unmodifiable({
        if (windows is Map)
          for (final entry in windows.entries)
            if (entry.key is String && entry.value is int && entry.value > 0)
              entry.key as String: entry.value as int,
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ComposerDefaults &&
      other.permission == permission &&
      other.modelId == modelId &&
      other.reasoningEffort == reasoningEffort &&
      mapEquals(other.contextWindows, contextWindows);

  @override
  int get hashCode {
    final keys = contextWindows.keys.toList()..sort();
    return Object.hash(
      permission,
      modelId,
      reasoningEffort,
      Object.hashAll([
        for (final key in keys) Object.hash(key, contextWindows[key]),
      ]),
    );
  }
}

/// 输入卡片选择的持久化边界。
abstract class ComposerDefaultsStore {
  Future<ComposerDefaults?> read(String projectId);

  Future<void> write(String projectId, ComposerDefaults defaults);
}

/// 一个 JSON 文件记住所有项目的选择：`<应用数据>/composer_defaults.json`。
///
/// 写入先落临时文件再改名，中途中断不会留下半截 JSON。读失败一律当作没有
/// 记住过，不让坏文件挡住输入卡片。
class FileComposerDefaultsStore implements ComposerDefaultsStore {
  FileComposerDefaultsStore({Directory? root}) : _rootOverride = root;

  static const String fileName = 'composer_defaults.json';

  final Directory? _rootOverride;
  Map<String, Object?>? _cache;
  Future<void> _writes = Future<void>.value();

  File? _fileFor(String rootPath) => File(p.join(rootPath, fileName));

  Future<File?> _file() async {
    if (_rootOverride case final override?) {
      return _fileFor(override.path);
    }
    final base = await AppPaths.storageDirectory();
    if (base == null) return null;
    return _fileFor(base);
  }

  Future<Map<String, Object?>> _readAll() async {
    final cached = _cache;
    if (cached != null) return cached;
    final empty = <String, Object?>{};
    final file = await _file();
    if (file == null) return _cache = empty;
    try {
      if (!await file.exists()) return _cache = empty;
      final decoded = jsonDecode(await file.readAsString());
      return _cache = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : empty;
    } on FileSystemException {
      return _cache = empty;
    } on FormatException {
      return _cache = empty;
    }
  }

  @override
  Future<ComposerDefaults?> read(String projectId) async {
    final all = await _readAll();
    final entry = all[projectId];
    if (entry == null) return null;
    return ComposerDefaults.fromJson(entry);
  }

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) {
    // 串行写入：并发合并会让后一次写入拿到旧快照，丢掉前一次的选择。
    _writes = _writes.then((_) => _writeNow(projectId, defaults));
    return _writes;
  }

  Future<void> _writeNow(String projectId, ComposerDefaults defaults) async {
    final all = Map<String, Object?>.from(await _readAll());
    if (all[projectId] == defaults.toJson()) return;
    all[projectId] = defaults.toJson();
    _cache = all;
    final file = await _file();
    if (file == null) return;
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(jsonEncode(all), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } on FileSystemException {
      // 记住选择不是关键路径，写失败不能挡住发送。
    }
  }
}
