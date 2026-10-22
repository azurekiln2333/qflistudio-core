import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/tutorial.dart';
import 'app_paths.dart';
import 'example_input_fixtures.dart';

/// JSON-backed user examples layered over bundled defaults.
class ExampleCodeStore extends ChangeNotifier {
  ExampleCodeStore({File? storageFile}) : _storageOverride = storageFile;

  /// Bumped when the bundled Java tutorial/example content is wholly replaced.
  /// A persisted document written with an older version has all of its Java
  /// content records purged once, so obsolete local Java examples cannot
  /// survive the replacement. Other languages and post-migration Java entries
  /// are untouched.
  static const int contentVersion = 2;

  final File? _storageOverride;
  File? _storage;
  Future<void>? _loading;
  Future<void>? _writes;
  bool _disposed = false;
  final Map<String, ExampleCode> _defaults = {};
  final Map<String, ExampleCode> _custom = {};

  ExampleCode? bundledExample(String id) => _defaults[id];

  List<ExampleCode> get items => [
    ..._defaults.keys.map(
      (id) => _custom[id]?.withCatalogMetadata(_defaults[id]) ?? _defaults[id]!,
    ),
    ..._custom.entries
        .where((entry) => !_defaults.containsKey(entry.key))
        .map((entry) => entry.value),
  ];

  void seed(Iterable<ExampleCode> defaults) {
    for (final example in defaults) {
      _defaults[example.id] = example;
    }
  }

  Future<void> load({Iterable<ExampleCode> defaults = const []}) {
    if (_disposed) return Future<void>.value();
    seed(defaults);
    return _loading ??= _loadStorage();
  }

  Future<void> _loadStorage() async {
    final root = _storageOverride == null
        ? await AppPaths.storageDirectory()
        : null;
    if (_disposed) return;
    if (_storageOverride == null && root == null) {
      throw const FileSystemException('未找到可写的存储目录');
    }
    final file = _storage =
        _storageOverride ?? File(p.join(root!, 'examples.json'));
    if (!await file.exists() || _disposed) return;
    final loaded = <String, ExampleCode>{};
    var storedVersion = 0;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['examples'] is! List) return;
      storedVersion = (data['contentVersion'] as num?)?.toInt() ?? 0;
      for (final raw in data['examples'] as List) {
        if (raw is! Map) continue;
        final example = _fromJson(Map<String, dynamic>.from(raw));
        if (example != null) loaded[example.id] = example;
      }
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
    if (_disposed) return;
    final migrated = _migrateOnLoad(loaded, storedVersion);
    _custom.addAll(migrated.records);
    if (migrated.changed) {
      await _persistCurrent();
      if (_disposed) return;
    }
    notifyListeners();
  }

  /// One-time content migration. When the persisted [storedVersion] is older
  /// than [contentVersion], every Java content record is removed (the two Java
  /// pages were fully replaced) while other languages are preserved. Running
  /// again with an up-to-date version is a no-op.
  _MigrationOutcome _migrateOnLoad(
    Map<String, ExampleCode> loaded,
    int storedVersion,
  ) {
    if (storedVersion >= contentVersion) {
      return _MigrationOutcome(loaded, changed: false);
    }
    final kept = <String, ExampleCode>{
      for (final entry in loaded.entries)
        if (!_isJavaType(entry.value.type)) entry.key: entry.value,
    };
    return _MigrationOutcome(kept, changed: true);
  }

  static bool _isJavaType(String type) => type.trim().toLowerCase() == 'java';

  /// Writes the current [_custom] map with the up-to-date content version.
  Future<void> _persistCurrent() async {
    final file = _storage;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_document(_custom.values)),
      flush: true,
    );
  }

  Future<void> upsert(ExampleCode example) =>
      _updateCustom((items) => items[example.id] = example);

  Future<void> reset(String id) => _updateCustom((items) => items.remove(id));

  Map<String, dynamic> toJson() => _document(_custom.values);

  static Map<String, dynamic> _document(Iterable<ExampleCode> items) => {
    'schemaVersion': 1,
    'contentVersion': contentVersion,
    'examples': [for (final example in items) _toJson(example)],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  Future<void> importJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['examples'] is! List) {
      throw const FormatException('示例 JSON 缺少 examples 列表');
    }
    final imported = <String, ExampleCode>{};
    for (final raw in decoded['examples'] as List) {
      if (raw is! Map) continue;
      final example = _fromJson(Map<String, dynamic>.from(raw));
      if (example == null || example.type.isEmpty) continue;
      imported[example.id] = example;
    }
    await _updateCustom((items) {
      items
        ..clear()
        ..addAll(imported);
    });
  }

  Future<void> _updateCustom(
    void Function(Map<String, ExampleCode> items) update,
  ) async {
    await load();
    Future<void> write() async {
      if (_disposed) throw StateError('ExampleCodeStore has been disposed');
      final updated = Map<String, ExampleCode>.from(_custom);
      update(updated);
      final file = _storage!;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_document(updated.values)),
        flush: true,
      );
      if (_disposed) return;
      _custom
        ..clear()
        ..addAll(updated);
      notifyListeners();
    }

    // Commit each change only after its write succeeds, in request order.
    final previous = _writes;
    final current = previous == null
        ? write()
        : previous.catchError((Object _) {}).then((_) => write());
    _writes = current;
    await current;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static Map<String, dynamic> _toJson(ExampleCode example) => {
    'id': example.id,
    'type': example.type,
    'title': example.title,
    'summary': example.summary,
    'code': example.code,
    'output': example.output,
    if (example.concepts.isNotEmpty) 'concepts': example.concepts,
    if (example.language.isNotEmpty) 'language': example.language,
    if (example.level.isNotEmpty) 'level': example.level,
    if (example.inputFixtures.isNotEmpty)
      'inputFixtures': example.inputFixtures,
    if (example.sourceLessonId != null)
      'sourceLessonId': example.sourceLessonId,
  };

  static ExampleCode? _fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final type = json['type'] as String?;
    final title = json['title'] as String?;
    final code = json['code'] as String?;
    if (id == null || type == null || title == null || code == null) {
      return null;
    }
    return ExampleCode(
      id: id,
      type: type,
      title: title,
      summary: json['summary'] as String? ?? '',
      code: code,
      output: json['output'] as String? ?? '',
      concepts: (json['concepts'] as List?)?.whereType<String>().toList() ?? const [],
      sourceLessonId: json['sourceLessonId'] as String?,
      language: json['language'] as String? ?? '',
      level: json['level'] as String? ?? '',
      inputFixtures: ExampleInputFixtures.parse(
        json['inputFixtures'],
        input: json['input'],
      ),
    );
  }
}

/// Result of a load-time content migration.
class _MigrationOutcome {
  const _MigrationOutcome(this.records, {required this.changed});

  final Map<String, ExampleCode> records;
  final bool changed;
}
