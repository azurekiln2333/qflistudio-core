import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../community/models.dart';
import '../store/auth_store.dart';
import 'api_client.dart';
import 'app_paths.dart';
import 'studio_profile.dart';

class _PendingTaskEvent {
  const _PendingTaskEvent(this.id, this.userId, this.day, this.key);

  final String id;
  final String userId;
  final String day;
  final String key;

  factory _PendingTaskEvent.fromJson(Map<String, dynamic> json) =>
      _PendingTaskEvent(
        json['id'] as String,
        json['userId'] as String,
        json['day'] as String,
        json['key'] as String,
      );

  Map<String, String> toJson() => {
    'id': id,
    'userId': userId,
    'day': day,
    'key': key,
  };
}

/// Persists local activity before sending it, then caches the server task view.
class TaskActivityService extends ChangeNotifier {
  TaskActivityService({
    File? storageFile,
    ApiClient? client,
    DateTime Function()? clock,
  }) : _storageOverride = storageFile,
       _client = client ?? ApiClient.instance,
       _clock = clock ?? DateTime.now;

  static final TaskActivityService instance = TaskActivityService();

  final File? _storageOverride;
  final ApiClient _client;
  final DateTime Function() _clock;
  final Map<String, DailyTasksSnapshot> _snapshots = {};
  final Map<String, String> _fetchedDays = {};
  final Map<String, int> _dailyCounts = {};
  final Map<String, int> _totalCounts = {};
  final Map<String, Map<String, dynamic>> _calendars = {};
  final List<_PendingTaskEvent> _pending = [];
  final Map<String, Future<void>> _taskRefreshes = {};
  Future<void>? _initializing;
  Future<void>? _writes;
  Future<void> _syncQueue = Future<void>.value();
  File? _storage;
  DateTime? _retryAfter;
  String? _lastError;
  int _lastReward = 0;

  String get today => _date(_clock());
  String? get lastError => _lastError;
  int get lastReward => _lastReward;

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static void report(AuthStore auth, String key) {
    unawaited(
      instance.record(auth, key).catchError((Object error) {
        instance._lastError = '本地操作记录失败：$error';
        instance.notifyListeners();
      }),
    );
  }

  Future<void> initialize() => _initializing ??= _read();

  Future<void> _read() async {
    if (_storageOverride != null) {
      _storage = _storageOverride;
    } else {
      final root = await AppPaths.storageDirectory();
      _storage = root == null ? null : File(p.join(root, 'daily_tasks.json'));
    }
    final file = _storage;
    if (file == null || !await file.exists()) {
      notifyListeners();
      return;
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final snapshots = json['snapshots'] as Map? ?? const {};
      for (final entry in snapshots.entries) {
        _snapshots[entry.key.toString()] = DailyTasksSnapshot.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      _fetchedDays.addAll(
        Map<String, String>.from(json['fetchedDays'] as Map? ?? const {}),
      );
      _dailyCounts.addAll(
        Map<String, int>.from(json['dailyCounts'] as Map? ?? const {}),
      );
      _totalCounts.addAll(
        Map<String, int>.from(json['totalCounts'] as Map? ?? const {}),
      );
      for (final entry in (json['calendars'] as Map? ?? const {}).entries) {
        _calendars[entry.key.toString()] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
      for (final row in json['pending'] as List? ?? const []) {
        _pending.add(
          _PendingTaskEvent.fromJson(Map<String, dynamic>.from(row as Map)),
        );
      }
    } on Object {
      _lastError = '每日任务缓存读取失败，请下拉刷新';
    }
    notifyListeners();
  }

  Future<void> _persist() {
    final file = _storage;
    if (file == null) return Future<void>.value();
    final encoded = jsonEncode({
      'version': 1,
      'snapshots': {
        for (final entry in _snapshots.entries) entry.key: entry.value.toJson(),
      },
      'fetchedDays': _fetchedDays,
      'dailyCounts': _dailyCounts,
      'totalCounts': _totalCounts,
      'calendars': _calendars,
      'pending': [for (final event in _pending) event.toJson()],
    });
    Future<void> write() async {
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    }

    final previous = _writes;
    return _writes = previous == null
        ? write()
        : previous.catchError((Object _) {}).then((_) => write());
  }

  String _scope(AuthStore auth) => auth.user?.id ?? 'local';
  String _dailyKey(String userId, String day, String key) =>
      '$userId|$day|$key';

  int countToday(AuthStore auth, String key) =>
      _dailyCounts[_dailyKey(_scope(auth), today, key)] ?? 0;

  int countLast7Days(AuthStore auth, String key) {
    final now = _clock();
    var count = 0;
    for (var offset = 0; offset < 7; offset++) {
      final day = _date(DateTime(now.year, now.month, now.day - offset));
      count += _dailyCounts[_dailyKey(_scope(auth), day, key)] ?? 0;
    }
    return count;
  }

  int countAllTime(AuthStore auth, String key) =>
      _totalCounts['${_scope(auth)}|$key'] ?? 0;

  int pendingCount(AuthStore auth) =>
      _pending.where((event) => event.userId == auth.user?.id).length;

  DailyTasksSnapshot? snapshotFor(AuthStore auth) {
    final userId = auth.user?.id;
    if (userId == null) return null;
    final cached = _snapshots[userId];
    if (cached == null || _fetchedDays[userId] == today) return cached;
    return DailyTasksSnapshot(
      day: today,
      checkedToday: false,
      streak: cached.streak,
      points: auth.user?.points ?? cached.points,
      growth: cached.growth,
      tasks: [
        for (final task in cached.tasks)
          TaskInfo(
            key: task.key,
            eventKey: task.eventKey,
            label: task.label,
            done: false,
            reward: task.reward,
            progress: 0,
            target: task.target,
          ),
      ],
    );
  }

  List<TaskInfo> visibleTasks(AuthStore auth) {
    final snapshot = snapshotFor(auth);
    if (snapshot == null) return const [];
    final extra = <String, int>{};
    for (final event in _pending) {
      if (event.userId != auth.user?.id || event.day != snapshot.day) continue;
      extra.update(event.key, (value) => value + 1, ifAbsent: () => 1);
    }
    return [
      for (final task in snapshot.tasks)
        task.withProgress(task.progress + (extra[task.eventKey] ?? 0)),
    ];
  }

  Future<void> record(AuthStore auth, String key) async {
    if (!const {'create_project', 'open_project', 'save_file'}.contains(key)) {
      return;
    }
    await initialize();
    final userId = _scope(auth);
    final day = today;
    final dailyKey = _dailyKey(userId, day, key);
    _dailyCounts[dailyKey] = (_dailyCounts[dailyKey] ?? 0) + 1;
    final totalKey = '$userId|$key';
    _totalCounts[totalKey] = (_totalCounts[totalKey] ?? 0) + 1;
    if (StudioProfile.current?.offlineOnly != true &&
        auth.token != null &&
        auth.user != null) {
      final random = Random.secure();
      final id =
          'event_${List<int>.generate(16, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
      _pending.add(_PendingTaskEvent(id, userId, day, key));
    }
    try {
      await _persist();
    } on FileSystemException catch (error) {
      _lastError = '本地操作缓存保存失败：${error.message}';
    }
    notifyListeners();
    if (StudioProfile.current?.offlineOnly == true) return;
    unawaited(
      syncPending(auth).catchError((Object error) {
        _lastError = '操作同步失败：$error';
        notifyListeners();
      }),
    );
  }

  Future<void> syncPending(AuthStore auth, {bool force = false}) async {
    await initialize();
    if (StudioProfile.current?.offlineOnly == true) return;
    final token = auth.token;
    final userId = auth.user?.id;
    if (token == null || userId == null) return;
    if (!force && _retryAfter != null && _clock().isBefore(_retryAfter!)) {
      return;
    }
    _syncQueue = _syncQueue.catchError((Object _) {}).then((_) async {
      while (StudioProfile.current?.offlineOnly != true &&
          auth.token == token &&
          auth.user?.id == userId) {
        final index = _pending.indexWhere((event) => event.userId == userId);
        if (index < 0) return;
        final event = _pending[index];
        try {
          final result = await _client.reportTaskEvent(
            token,
            event.key,
            event.id,
            event.day,
          );
          _pending.remove(event);
          _snapshots[userId] = result.snapshot;
          _fetchedDays[userId] = today;
          _lastReward = result.reward;
          _lastError = null;
          _retryAfter = null;
          await _persist();
          await auth.updatePoints(
            points: result.snapshot.points,
            streak: result.snapshot.streak,
            growth: result.snapshot.growth,
          );
          notifyListeners();
        } on ApiException catch (error) {
          if (error.statusCode == 400) {
            _pending.remove(event);
            await _persist();
            _lastError = '部分本地操作无法同步：${error.message}';
            notifyListeners();
            continue;
          }
          _lastError = '有 ${pendingCount(auth)} 次操作待同步：${error.message}';
          _retryAfter = _clock().add(const Duration(seconds: 30));
          notifyListeners();
          return;
        }
      }
    });
    await _syncQueue;
  }

  Future<void> refreshIfDue(AuthStore auth, {bool force = false}) async {
    await initialize();
    if (StudioProfile.current?.offlineOnly == true) return;
    final token = auth.token;
    final userId = auth.user?.id;
    if (token == null || userId == null) return;
    final active = _taskRefreshes[userId];
    if (active != null) {
      await active;
      if (!force) return;
    }
    final refresh = _refreshTasks(auth, token, userId, force);
    _taskRefreshes[userId] = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_taskRefreshes[userId], refresh)) {
        _taskRefreshes.remove(userId);
      }
    }
  }

  Future<void> _refreshTasks(
    AuthStore auth,
    String token,
    String userId,
    bool force,
  ) async {
    try {
      if (StudioProfile.current?.offlineOnly == true) return;
      if (_pending.any((event) => event.userId == userId)) {
        await syncPending(auth, force: true);
      }
      if (StudioProfile.current?.offlineOnly == true) return;
      if (!force && _fetchedDays[userId] == today && _snapshots[userId] != null) {
        return;
      }
      final snapshot = await _client.tasks(token);
      if (auth.token != token || auth.user?.id != userId) return;
      _snapshots[userId] = snapshot;
      _fetchedDays[userId] = today;
      _lastError = null;
      await _persist();
      await auth.updatePoints(
        points: snapshot.points,
        streak: snapshot.streak,
        growth: snapshot.growth,
      );
      notifyListeners();
    } on ApiException catch (error) {
      _lastError = error.message;
      notifyListeners();
    } on FileSystemException catch (error) {
      _lastError = '任务缓存保存失败：${error.message}';
      notifyListeners();
    }
  }

  Future<({bool alreadyChecked, int reward, int streak})> checkin(
    AuthStore auth,
  ) async {
    await initialize();
    final token = auth.token!;
    final result = await _client.checkin(token);
    final userId = auth.user?.id;
    if (auth.token == token && userId != null) {
      _snapshots[userId] = result.snapshot;
      _fetchedDays[userId] = today;
      final key = '$userId|${today.substring(0, 7)}';
      final days = <String>{
        ...(_calendars[key]?['days'] as List? ?? const []).cast<String>(),
      };
      days.add(today);
      _calendars[key] = {'fetchedDay': today, 'days': days.toList()..sort()};
      await _persist();
      await auth.updatePoints(
        points: result.snapshot.points,
        streak: result.snapshot.streak,
        growth: result.snapshot.growth,
      );
      notifyListeners();
    }
    return (
      alreadyChecked: result.alreadyChecked,
      reward: result.reward,
      streak: result.streak,
    );
  }

  List<DateTime> cachedCalendar(AuthStore auth, DateTime month) {
    final key =
        '${_scope(auth)}|${month.year}-${month.month.toString().padLeft(2, '0')}';
    return [
      for (final day in _calendars[key]?['days'] as List? ?? const [])
        ?DateTime.tryParse(day.toString()),
    ];
  }

  Future<void> refreshCalendarIfDue(
    AuthStore auth,
    DateTime month, {
    bool force = false,
  }) async {
    await initialize();
    final token = auth.token;
    final userId = auth.user?.id;
    if (token == null || userId == null) return;
    final key =
        '$userId|${month.year}-${month.month.toString().padLeft(2, '0')}';
    if (!force && _calendars[key]?['fetchedDay'] == today) return;
    final days = await _client.checkinDays(token, month);
    if (auth.token != token || auth.user?.id != userId) return;
    _calendars[key] = {
      'fetchedDay': today,
      'days': [for (final date in days) _date(date)],
    };
    await _persist();
    notifyListeners();
  }
}
