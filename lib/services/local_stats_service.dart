import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'local_store_backend.dart';

/// Aggregated counters for one day, keyed `yyyy-MM-dd`.
///
/// Every field is a plain counter so the daily map stays small and JSON-safe.
class LocalDayStats {
  LocalDayStats({
    this.filesEdited = 0,
    this.projectsEdited = 0,
    this.filesCreated = 0,
    this.filesDeleted = 0,
    this.filesRenamed = 0,
    this.saves = 0,
    this.projectOpens = 0,
    this.runsSucceeded = 0,
    this.runsFailed = 0,
    this.terminalCommands = 0,
    this.linesAdded = 0,
    this.linesRemoved = 0,
    this.editingMillis = 0,
    this.usageMillis = 0,
  });

  factory LocalDayStats.fromJson(Map<String, Object?> json) => LocalDayStats(
    filesEdited: _int(json['filesEdited']),
    projectsEdited: _int(json['projectsEdited']),
    filesCreated: _int(json['filesCreated']),
    filesDeleted: _int(json['filesDeleted']),
    filesRenamed: _int(json['filesRenamed']),
    saves: _int(json['saves']),
    projectOpens: _int(json['projectOpens']),
    runsSucceeded: _int(json['runsSucceeded']),
    runsFailed: _int(json['runsFailed']),
    terminalCommands: _int(json['terminalCommands']),
    linesAdded: _int(json['linesAdded']),
    linesRemoved: _int(json['linesRemoved']),
    editingMillis: _int(json['editingMillis']),
    usageMillis: _int(json['usageMillis']),
  );

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;

  int filesEdited;
  int projectsEdited;
  int filesCreated;
  int filesDeleted;
  int filesRenamed;
  int saves;
  int projectOpens;
  int runsSucceeded;
  int runsFailed;
  int terminalCommands;
  int linesAdded;
  int linesRemoved;
  int editingMillis;
  int usageMillis;

  Map<String, Object?> toJson() => {
    if (filesEdited != 0) 'filesEdited': filesEdited,
    if (projectsEdited != 0) 'projectsEdited': projectsEdited,
    if (filesCreated != 0) 'filesCreated': filesCreated,
    if (filesDeleted != 0) 'filesDeleted': filesDeleted,
    if (filesRenamed != 0) 'filesRenamed': filesRenamed,
    if (saves != 0) 'saves': saves,
    if (projectOpens != 0) 'projectOpens': projectOpens,
    if (runsSucceeded != 0) 'runsSucceeded': runsSucceeded,
    if (runsFailed != 0) 'runsFailed': runsFailed,
    if (terminalCommands != 0) 'terminalCommands': terminalCommands,
    if (linesAdded != 0) 'linesAdded': linesAdded,
    if (linesRemoved != 0) 'linesRemoved': linesRemoved,
    if (editingMillis != 0) 'editingMillis': editingMillis,
    if (usageMillis != 0) 'usageMillis': usageMillis,
  };

  /// Total operations recorded that day, used for the heatmap intensity and to
  /// decide whether a day counts towards a streak.
  int get activityCount =>
      filesEdited +
      filesCreated +
      filesDeleted +
      filesRenamed +
      saves +
      projectOpens +
      runsSucceeded +
      runsFailed +
      terminalCommands;

  bool get isEmpty => activityCount == 0 && editingMillis == 0 && usageMillis == 0;

  /// Adds every counter of [other] into this one.
  void addFrom(LocalDayStats other) {
    filesEdited += other.filesEdited;
    projectsEdited += other.projectsEdited;
    filesCreated += other.filesCreated;
    filesDeleted += other.filesDeleted;
    filesRenamed += other.filesRenamed;
    saves += other.saves;
    projectOpens += other.projectOpens;
    runsSucceeded += other.runsSucceeded;
    runsFailed += other.runsFailed;
    terminalCommands += other.terminalCommands;
    linesAdded += other.linesAdded;
    linesRemoved += other.linesRemoved;
    editingMillis += other.editingMillis;
    usageMillis += other.usageMillis;
  }
}

/// Totals for one project.
class LocalProjectStats {
  LocalProjectStats({this.edits = 0, this.opens = 0, this.runs = 0});

  factory LocalProjectStats.fromJson(Map<String, Object?> json) =>
      LocalProjectStats(
        edits: (json['edits'] as num?)?.toInt() ?? 0,
        opens: (json['opens'] as num?)?.toInt() ?? 0,
        runs: (json['runs'] as num?)?.toInt() ?? 0,
      );

  int edits;
  int opens;
  int runs;

  int get score => edits + opens + runs;

  Map<String, Object?> toJson() => {
    if (edits != 0) 'edits': edits,
    if (opens != 0) 'opens': opens,
    if (runs != 0) 'runs': runs,
  };
}

/// A slice of the language/extension distribution.
class LocalLanguageCount {
  const LocalLanguageCount(this.extension, this.count);

  final String extension;
  final int count;
}

/// One point on a trend line.
class LocalTrendPoint {
  const LocalTrendPoint(this.day, this.value);

  final DateTime day;
  final int value;
}

/// Read-only view the stats page renders from. Building one is pure and cheap,
/// which is why the page can recompute it on every rebuild.
class LocalStatsSummary {
  const LocalStatsSummary({
    required this.totals,
    required this.days,
    required this.projects,
    required this.languages,
    required this.currentStreak,
    required this.longestStreak,
    required this.last7,
    required this.last30,
    required this.usageMillis,
  });

  /// All-time totals, computed by summing [days].
  final LocalDayStats totals;

  /// Per-day counters, ascending by date.
  final Map<DateTime, LocalDayStats> days;

  /// Per-project counters, highest score first.
  final Map<String, LocalProjectStats> projects;

  /// Extension -> edit count, highest first.
  final List<LocalLanguageCount> languages;

  final int currentStreak;
  final int longestStreak;
  final List<LocalTrendPoint> last7;
  final List<LocalTrendPoint> last30;
  final int usageMillis;

  /// Top projects by score, at most [limit].
  List<MapEntry<String, LocalProjectStats>> topProjects([int limit = 5]) {
    final sorted = projects.entries.toList()
      ..sort((a, b) => b.value.score.compareTo(a.value.score));
    return sorted.take(limit).toList();
  }
}

/// Local, offline activity statistics.
///
/// Records counters only — never file contents — and stores them as JSON under
/// the app documents directory. Like [LocalAuditService] it deliberately does
/// not import `ApiClient` or `AuthStore`, so no offline build can upload it.
class LocalStatsService extends ChangeNotifier {
  LocalStatsService({
    LocalStoreBackend? backend,
    DateTime Function()? clock,
    this.flushDelay = const Duration(milliseconds: 400),
  }) : _backend = backend ?? const LocalFileBackend('local_stats.json'),
       _clock = clock ?? DateTime.now;

  static final LocalStatsService instance = LocalStatsService();

  /// How long a write is coalesced before it runs. `Duration.zero` makes every
  /// write immediate, which is what tests use so no timer outlives the test.
  final Duration flushDelay;

  final LocalStoreBackend _backend;
  final DateTime Function() _clock;

  final Map<String, LocalDayStats> _days = {};
  final Map<String, LocalProjectStats> _projects = {};
  final Map<String, int> _extensions = {};
  int _usageMillis = 0;

  bool _loaded = false;
  Future<void>? _loading;
  Timer? _writeTimer;
  Future<void>? _writes;
  bool _dirty = false;

  bool get isLoaded => _loaded;

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

  static String dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// The [LocalDayStats] for today, created on demand.
  LocalDayStats _today() => _days.putIfAbsent(
    dayKey(_clock()),
    LocalDayStats.new,
  );

  LocalProjectStats _project(String? name) => _projects.putIfAbsent(
    (name == null || name.isEmpty) ? '未命名项目' : name,
    LocalProjectStats.new,
  );

  /// Records an editor save, including the estimated line delta.
  ///
  /// [previousLineCount] and [newLineCount] come from the editor, which already
  /// has both buffers at save time; the difference is an estimate, so it is
  /// described that way in the UI.
  Future<void> recordSave({
    String? project,
    String? path,
    int? previousLineCount,
    int? newLineCount,
  }) async {
    final day = _today();
    day.saves++;
    day.filesEdited++;
    _project(project).edits++;
    if (previousLineCount != null && newLineCount != null) {
      final delta = newLineCount - previousLineCount;
      if (delta > 0) {
        day.linesAdded += delta;
      } else if (delta < 0) {
        day.linesRemoved += -delta;
      }
    }
    _touchExtension(path);
    await _commit();
  }

  /// Records that a file was edited in some other way (e.g. a rename inside the
  /// editor), without counting a save.
  Future<void> recordFileEdited({String? project, String? path}) async {
    final day = _today();
    day.filesEdited++;
    if (project != null) day.projectsEdited++;
    _project(project).edits++;
    _touchExtension(path);
    await _commit();
  }

  Future<void> recordFileCreated({String? project, String? path}) async {
    final day = _today();
    day.filesCreated++;
    _project(project).edits++;
    _touchExtension(path);
    await _commit();
  }

  Future<void> recordFileDeleted({String? project, String? path}) async {
    final day = _today();
    day.filesDeleted++;
    _touchExtension(path);
    await _commit();
  }

  Future<void> recordFileRenamed({String? project, String? path}) async {
    final day = _today();
    day.filesRenamed++;
    _touchExtension(path);
    await _commit();
  }

  Future<void> recordProjectOpened({String? project}) async {
    final day = _today();
    day.projectOpens++;
    _project(project).opens++;
    await _commit();
  }

  Future<void> recordRun({required bool succeeded, String? project}) async {
    final day = _today();
    if (succeeded) {
      day.runsSucceeded++;
    } else {
      day.runsFailed++;
    }
    _project(project).runs++;
    await _commit();
  }

  Future<void> recordTerminalCommand() async {
    _today().terminalCommands++;
    await _commit();
  }

  /// Adds editing time, in milliseconds.
  Future<void> addEditingTime(Duration duration) async {
    if (duration <= Duration.zero) return;
    _today().editingMillis += duration.inMilliseconds;
    await _commit();
  }

  /// Adds app usage time, in milliseconds.
  Future<void> addUsageTime(Duration duration) async {
    if (duration <= Duration.zero) return;
    _today().usageMillis += duration.inMilliseconds;
    _usageMillis += duration.inMilliseconds;
    await _commit();
  }

  void _touchExtension(String? path) {
    if (path == null || path.isEmpty) return;
    final extension = p.extension(path).toLowerCase();
    if (extension.isEmpty) return;
    _extensions[extension] = (_extensions[extension] ?? 0) + 1;
  }

  Future<void> _commit() async {
    _dirty = true;
    notifyListeners();
    _scheduleWrite();
  }

  /// Whether a write is worth scheduling.
  ///
  /// Recording is only persisted once the store has been loaded, because until
  /// then there is no resolved storage location and arming a timer would leave
  /// one pending in environments that never load (widget tests, for example).
  /// The in-memory counters are not lost: [load] picks up whatever is already
  /// recorded, and the next write after it includes everything.
  bool get _shouldPersist => _loaded;

  /// Builds the summary the page renders. Pure: no I/O, no mutation.
  LocalStatsSummary summarise() {
    final totals = LocalDayStats();
    final days = <DateTime, LocalDayStats>{};
    for (final entry in _days.entries) {
      final date = _parseDayKey(entry.key);
      if (date == null) continue;
      days[date] = entry.value;
      totals.addFrom(entry.value);
    }
    totals.usageMillis = _usageMillis;

    final languages = _extensions.entries
        .map((entry) => LocalLanguageCount(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return LocalStatsSummary(      totals: totals,
      days: days,
      projects: Map.unmodifiable(_projects),
      languages: languages,
      currentStreak: currentStreak(),
      longestStreak: longestStreak(),
      last7: trend(7),
      last30: trend(30),
      usageMillis: _usageMillis,
    );
  }

  static DateTime? _parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  /// Whether a day counts as active. Editing time alone counts, so a long
  /// session with few operations still keeps the streak alive.
  bool _isActive(LocalDayStats? day) =>
      day != null && (day.activityCount > 0 || day.editingMillis > 0);

  /// Consecutive active days ending today or yesterday.
  ///
  /// Yesterday is included so the streak is not reported as broken during a day
  /// the user has not started working yet.
  int currentStreak() {
    var cursor = _clock();
    var streak = 0;
    final todayActive = _isActive(_days[dayKey(cursor)]);
    if (!todayActive) {
      // Allow the streak to end yesterday without resetting to zero.
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
      if (!_isActive(_days[dayKey(cursor)])) return 0;
    }
    while (_isActive(_days[dayKey(cursor)])) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  /// The longest run of active days on record.
  int longestStreak() {
    if (_days.isEmpty) return 0;
    final active = _days.entries
        .where((entry) => _isActive(entry.value))
        .map((entry) => _parseDayKey(entry.key))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (active.isEmpty) return 0;
    var longest = 1;
    var run = 1;
    for (var i = 1; i < active.length; i++) {
      final previous = active[i - 1];
      final expected = DateTime(
        previous.year,
        previous.month,
        previous.day + 1,
      );
      if (active[i] == expected) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }
    return longest;
  }

  /// Activity counts for the last [days] days, oldest first.
  List<LocalTrendPoint> trend(int days) {
    final now = _clock();
    return [
      for (var offset = days - 1; offset >= 0; offset--)
        () {
          final date = DateTime(now.year, now.month, now.day - offset);
          final day = _days[dayKey(date)];
          return LocalTrendPoint(
            date,
            (day?.activityCount ?? 0) + (day?.editingMillis ?? 0) ~/ 60000,
          );
        }(),
    ];
  }

  /// The busiest day count in the last [days] days, for chart scaling.
  int peakInLast(int days) {
    var peak = 0;
    for (final point in trend(days)) {
      if (point.value > peak) peak = point.value;
    }
    return peak;
  }

  Future<void> clear() async {
    _days.clear();
    _projects.clear();
    _extensions.clear();
    _usageMillis = 0;
    _dirty = true;
    notifyListeners();
    await _writeNow();
  }

  /// Serialises everything as JSON for the export action.
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'exportedAt': _clock().toIso8601String(),
    'usageMillis': _usageMillis,
    'days': {
      for (final entry in _days.entries) entry.key: entry.value.toJson(),
    },
    'projects': {
      for (final entry in _projects.entries) entry.key: entry.value.toJson(),
    },
    'extensions': _extensions,
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
        if (decoded is Map) {
          _usageMillis = (decoded['usageMillis'] as num?)?.toInt() ?? 0;
          final days = decoded['days'];
          if (days is Map) {
            for (final entry in days.entries) {
              if (entry.value is Map) {
                _days[entry.key.toString()] = LocalDayStats.fromJson(
                  (entry.value as Map).cast<String, Object?>(),
                );
              }
            }
          }
          final projects = decoded['projects'];
          if (projects is Map) {
            for (final entry in projects.entries) {
              if (entry.value is Map) {
                _projects[entry.key.toString()] = LocalProjectStats.fromJson(
                  (entry.value as Map).cast<String, Object?>(),
                );
              }
            }
          }
          final extensions = decoded['extensions'];
          if (extensions is Map) {
            for (final entry in extensions.entries) {
              _extensions[entry.key.toString()] =
                  (entry.value as num?)?.toInt() ?? 0;
            }
          }
        }
      }
    } on Object catch (error) {
      debugPrint('LocalStatsService load failed: $error');
      _days.clear();
      _projects.clear();
      _extensions.clear();
      _usageMillis = 0;
    } finally {
      _loaded = true;
      notifyListeners();
      // Anything recorded before the store was loaded is still in memory and
      // now has somewhere to go.
      if (_dirty) _scheduleWrite();
    }
  }

  /// Throttles writes so a burst of operations costs one write.
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
            'usageMillis': _usageMillis,
            'days': {
              for (final entry in _days.entries) entry.key: entry.value.toJson(),
            },
            'projects': {
              for (final entry in _projects.entries)
                entry.key: entry.value.toJson(),
            },
            'extensions': _extensions,
          }),
        );
      } on Object catch (error) {
        debugPrint('LocalStatsService write failed: $error');
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
