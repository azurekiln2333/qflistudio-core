import 'dart:convert';
import 'dart:io';

/// One cached device project copy, as recorded in the index.
class SyncCacheEntry {
  SyncCacheEntry({
    required this.key,
    required this.directory,
    required this.bytes,
    required this.usedAt,
  });

  factory SyncCacheEntry.fromJson(
    String key,
    Map<String, dynamic> json,
  ) => SyncCacheEntry(
    key: key,
    directory: json['directory'] is String ? json['directory'] as String : '',
    bytes: json['bytes'] is num ? (json['bytes'] as num).toInt() : 0,
    usedAt: json['usedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((json['usedAt'] as num).toInt())
        : DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// `hostId/projectKey`.
  final String key;
  final String directory;
  final int bytes;
  final DateTime usedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'directory': directory,
    'bytes': bytes,
    'usedAt': usedAt.millisecondsSinceEpoch,
  };
}

/// Bookkeeping for the device project copies on this phone.
///
/// The index is a small JSON file next to the copies. It records how many bytes
/// each project occupies and when it was last used, which is all the eviction
/// rule needs. A missing or unreadable index is not an error: the next
/// [load] starts from an empty map and the next sync treats every file as new.
class SyncCache {
  SyncCache({required String indexFile, int budgetBytes = 512 * 1024 * 1024})
    : _indexFile = indexFile,
      _budgetBytes = budgetBytes;

  final String _indexFile;
  final int _budgetBytes;

  final Map<String, SyncCacheEntry> _entries = <String, SyncCacheEntry>{};

  /// Total bytes the cached copies may occupy.
  int get budgetBytes => _budgetBytes;

  /// Keys currently known to the index.
  List<String> get keys => _entries.keys.toList()..sort();

  SyncCacheEntry? entryFor(String key) => _entries[key];

  /// Read the index from disk. Never throws: a corrupt file is ignored.
  Future<void> load() async {
    _entries.clear();
    final file = File(_indexFile);
    if (!await file.exists()) return;
    final text = await file.readAsString().catchError((Object _) => '');
    if (text.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final projects = decoded['projects'];
      if (projects is! Map) return;
      for (final entry in projects.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) continue;
        _entries[key] = SyncCacheEntry.fromJson(
          key,
          Map<String, dynamic>.from(value),
        );
      }
    } on FormatException {
      return;
    }
  }

  /// Write the index back to disk, creating the parent directory first.
  Future<void> save() async {
    final file = File(_indexFile);
    await file.parent.create(recursive: true);
    final payload = <String, dynamic>{
      'version': 1,
      'projects': <String, dynamic>{
        for (final entry in _entries.entries) entry.key: entry.value.toJson(),
      },
    };
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(payload), flush: true);
    await temp.rename(file.path);
  }

  /// Bytes used by every cached copy.
  int get usedBytes =>
      _entries.values.fold<int>(0, (sum, entry) => sum + entry.bytes);

  /// Record that [key] now occupies [bytes] and was just used.
  Future<void> touch(
    String key, {
    required String directory,
    required int bytes,
    DateTime? at,
  }) async {
    _entries[key] = SyncCacheEntry(
      key: key,
      directory: directory,
      bytes: bytes,
      usedAt: at ?? DateTime.now(),
    );
  }

  /// Remove [key] from the index without touching the files.
  Future<void> forget(String key) async {
    _entries.remove(key);
  }

  /// Keys to delete so that [needBytes] more bytes fit.
  ///
  /// Least recently used first. [keep] (the project the user has open) is never
  /// returned. The budget is not enforced when even an empty cache would not
  /// fit the request: the caller writes the new copy and the next sync evicts.
  List<String> evictCandidates({
    required int needBytes,
    Set<String> keep = const <String>{},
  }) {
    if (needBytes <= 0) return const <String>[];
    final candidates =
        _entries.values.where((entry) => !keep.contains(entry.key)).toList()
          ..sort((a, b) => a.usedAt.compareTo(b.usedAt));
    final chosen = <String>[];
    var freed = 0;
    for (final entry in candidates) {
      if (usedBytes - freed + needBytes <= _budgetBytes) break;
      chosen.add(entry.key);
      freed += entry.bytes;
    }
    return chosen;
  }
}
