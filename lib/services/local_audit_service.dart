import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'local_store_backend.dart';

/// What kind of operation an audit entry records.
///
/// Deliberately a closed set: the audit page filters by these, and an unknown
/// string would silently become unfilterable.
enum LocalAuditKind {
  create('创建', 'create'),
  open('打开', 'open'),
  delete('删除', 'delete'),
  rename('重命名', 'rename'),
  save('保存', 'save'),
  run('运行', 'run'),
  import('导入', 'import'),
  export('导出', 'export'),
  restore('恢复', 'restore'),
  terminal('终端命令', 'terminal');

  const LocalAuditKind(this.label, this.key);

  final String label;

  /// Stable key used in the JSON file, so a renamed label does not break
  /// existing records.
  final String key;

  static LocalAuditKind? fromKey(String key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

/// One recorded operation.
class LocalAuditEntry {
  const LocalAuditEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.action,
    this.project,
    this.path,
    this.detail,
  });

  factory LocalAuditEntry.fromJson(Map<String, Object?> json) => LocalAuditEntry(
    id: json['id'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(
      (json['at'] as num?)?.toInt() ?? 0,
    ),
    kind: LocalAuditKind.fromKey(json['kind'] as String? ?? '') ??
        LocalAuditKind.save,
    action: json['action'] as String? ?? '',
    project: json['project'] as String?,
    path: json['path'] as String?,
    detail: json['detail'] as String?,
  );

  /// Monotonic-ish identity, used by the UI as a list key.
  final String id;
  final DateTime at;
  final LocalAuditKind kind;

  /// Short human description, e.g. `保存 Main.java`.
  final String action;

  /// Project name, when the operation belongs to one.
  final String? project;

  /// File or directory path, when there is one.
  final String? path;

  /// Free-form extra context (exit code, target path, …).
  final String? detail;

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'kind': kind.key,
    'action': action,
    if (project != null) 'project': project,
    if (path != null) 'path': path,
    if (detail != null) 'detail': detail,
  };

  /// Everything searchable, lower-cased once for the search filter.
  String get haystack =>
      '$action ${project ?? ''} ${path ?? ''} ${detail ?? ''}'.toLowerCase();
}

/// A filter over the log: kinds and an inclusive time window.
class LocalAuditFilter {
  const LocalAuditFilter({
    this.kinds = const {},
    this.search = '',
    this.since,
    this.until,
  });

  /// Empty means "every kind".
  final Set<LocalAuditKind> kinds;
  final String search;
  final DateTime? since;
  final DateTime? until;

  bool get isEmpty =>
      kinds.isEmpty && search.trim().isEmpty && since == null && until == null;

  bool matches(LocalAuditEntry entry) {
    if (kinds.isNotEmpty && !kinds.contains(entry.kind)) return false;
    if (since != null && entry.at.isBefore(since!)) return false;
    if (until != null && entry.at.isAfter(until!)) return false;
    final query = search.trim().toLowerCase();
    if (query.isNotEmpty && !entry.haystack.contains(query)) return false;
    return true;
  }
}

/// Local, append-only audit log of project and editor operations.
///
/// Pure local storage: it imports neither `ApiClient` nor `AuthStore`, so it
/// cannot upload anything even by accident. That is the point — an offline
/// product must never send this data anywhere, and a networked product keeps
/// its server audit log separately (see `pages/audit_page.dart`).
///
/// The log is capped: once [maxEntries] is reached the oldest entries are
/// evicted, so the file cannot grow without bound.
class LocalAuditService extends ChangeNotifier {
  LocalAuditService({
    LocalStoreBackend? backend,
    DateTime Function()? clock,
    this.maxEntries = 500,
    this.flushDelay = const Duration(milliseconds: 400),
  }) : _backend = backend ?? const LocalFileBackend('local_audit.json'),
       _clock = clock ?? DateTime.now;

  static final LocalAuditService instance = LocalAuditService();

  /// Hard cap on retained entries. The oldest are dropped first.
  final int maxEntries;

  /// How long a write is coalesced before it runs. `Duration.zero` makes every
  /// write immediate, which is what tests use so no timer outlives the test.
  final Duration flushDelay;

  final LocalStoreBackend _backend;
  final DateTime Function() _clock;

  final List<LocalAuditEntry> _entries = [];
  int _sequence = 0;
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _writeTimer;
  Future<void>? _writes;
  bool _dirty = false;

  /// Newest first, which is the order the page displays.
  List<LocalAuditEntry> get entries => List.unmodifiable(_entries.reversed);

  bool get isLoaded => _loaded;

  int get length => _entries.length;

  /// Waits for the pending throttled write to land.
  ///
  /// Cancels the throttle timer and performs the write immediately, then waits
  /// for any write already in flight. Tests await this instead of sleeping for
  /// the throttle window.
  Future<void> get settled async {
    if (_dirty || _writeTimer != null) await _writeNow();
    while (_writes != null) {
      final pending = _writes!;
      await pending;
      if (identical(pending, _writes)) break;
    }
  }

  /// Records one operation.
  ///
  /// Safe to call before [load]: the entry is queued in memory and included in
  /// the next write. A failing write is reported once and dropped rather than
  /// thrown, because auditing must never break the operation it observes.
  Future<void> record({
    required LocalAuditKind kind,
    required String action,
    String? project,
    String? path,
    String? detail,
  }) async {
    final entry = LocalAuditEntry(
      id: '${_clock().microsecondsSinceEpoch}-${_sequence++}',
      at: _clock(),
      kind: kind,
      action: action,
      project: project,
      path: path,
      detail: detail,
    );
    _entries.add(entry);
    _evictIfNeeded();
    _dirty = true;
    notifyListeners();
    _scheduleWrite();
  }

  /// Whether a write is worth scheduling.
  ///
  /// Recording is only persisted once the store has been loaded, because until
  /// then there is no resolved storage location and arming a timer would leave
  /// one pending in environments that never load (widget tests, for example).
  /// The in-memory entry is not lost: [load] picks up whatever is already
  /// queued, and the next write after it includes everything.
  bool get _shouldPersist => _loaded;

  void _evictIfNeeded() {
    if (_entries.length <= maxEntries) return;
    // Oldest-first eviction: drop from the front, which is the oldest.
    _entries.removeRange(0, _entries.length - maxEntries);
  }

  /// Entries matching [filter], newest first.
  List<LocalAuditEntry> filtered(LocalAuditFilter filter) {
    if (filter.isEmpty) return entries;
    return [
      for (final entry in _entries.reversed)
        if (filter.matches(entry)) entry,
    ];
  }

  /// The distinct project names seen, for a filter dropdown.
  List<String> get projects {
    final names = <String>{};
    for (final entry in _entries) {
      final name = entry.project;
      if (name != null && name.isNotEmpty) names.add(name);
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  Future<void> clear() async {
    _entries.clear();
    _dirty = true;
    notifyListeners();
    await _writeNow();
  }

  /// Serialises the current log as indented JSON for the export action.
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'exportedAt': _clock().toIso8601String(),
    'entries': [for (final entry in _entries.reversed) entry.toJson()],
  });

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final payload = await _backend.read();
      if (payload != null) {
        final decoded = jsonDecode(payload);
        if (decoded is Map && decoded['entries'] is List) {
          _entries
            ..clear()
            ..addAll(
              (decoded['entries'] as List).whereType<Map>().map(
                (raw) => LocalAuditEntry.fromJson(
                  raw.cast<String, Object?>(),
                ),
              ),
            );
        }
      }
    } on Object catch (error) {
      // A corrupt or unreadable file must not stop the app; start empty.
      debugPrint('LocalAuditService load failed: $error');
      _entries.clear();
    } finally {
      _loaded = true;
      notifyListeners();
      // Anything recorded before the store was loaded is still in memory and
      // now has somewhere to go.
      if (_dirty) _scheduleWrite();
    }
  }

  /// Throttles writes so a burst of operations costs one file write.
  ///
  /// A zero [flushDelay] skips the timer entirely and writes on the next
  /// microtask, which keeps tests free of pending timers.
  void _scheduleWrite() {
    if (!_shouldPersist) return;
    _writeTimer?.cancel();
    if (flushDelay <= Duration.zero) {
      _writeTimer = null;
      unawaited(_writeNow());
      return;
    }
    _writeTimer = Timer(flushDelay, () {
      unawaited(_writeNow());
    });
  }

  Future<void> _writeNow() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (!_dirty) return;
    _dirty = false;
    final previous = _writes;
    final write = () async {
      if (previous != null) await previous;
      try {
        await _backend.write(
          jsonEncode({
            'version': 1,
            'entries': [for (final entry in _entries) entry.toJson()],
          }),
        );
      } on Object catch (error) {
        debugPrint('LocalAuditService write failed: $error');
      }
    }();
    _writes = write;
    await write;
    if (identical(_writes, write)) _writes = null;
  }

  @override
  void dispose() {
    // Cancel every timer so nothing survives the widget/page that owns this
    // service; a live timer is what stops a test process from exiting.
    _writeTimer?.cancel();
    _writeTimer = null;
    super.dispose();
  }
}
