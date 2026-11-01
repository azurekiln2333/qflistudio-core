import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../store/auth_store.dart';
import 'api_client.dart';
import 'app_paths.dart';
import 'studio_profile.dart';

/// Rows returned by the points endpoints. Kept as the server's JSON maps so
/// the migration UI can render optional fields without another model layer.
typedef PointsRows = List<Map<String, dynamic>>;

/// `/api/users/me/points`: the current balance and its ledger entries.
class PointsHistory {
  const PointsHistory({required this.points, required this.entries});

  final int points;
  final PointsRows entries;
}

/// One independently loaded section of the points screen.
///
/// A section owns its own data, loading flag, error and cache day. Sections
/// never wait for each other, so an unavailable endpoint cannot blank the
/// whole screen. Listeners only rebuild the tab that renders this section.
class PointsSection<T> extends ChangeNotifier {
  PointsSection(this.id);

  final String id;
  T? _value;
  bool _loading = false;
  String? _error;
  String? _day;
  int _generation = 0;

  T? get value => _value;
  bool get loading => _loading;
  String? get error => _error;

  bool isFresh(String today) => _value != null && _day == today;

  /// Drops the account-scoped value and invalidates any in-flight response.
  void reset() {
    _generation++;
    _value = null;
    _loading = false;
    _error = null;
    _day = null;
    notifyListeners();
  }

  /// Applies a value restored from the per-account cache. Never overwrites a
  /// value that a live request already produced.
  bool restore(T value, String? day) {
    if (_value != null || _loading) return false;
    _value = value;
    _day = day;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Marks the section unavailable without contacting the server.
  void unavailable(String message) {
    _generation++;
    _loading = false;
    _error = message;
    notifyListeners();
  }
}

/// Points/rewards state with per-section loading, caching and deduplication.
///
/// Responsibilities:
/// - every section loads independently and concurrently;
/// - identical requests share one in-flight future;
/// - responses for a previous token/account are discarded;
/// - the cache is per account and per section, so a fresh section is not
///   fetched again merely because a sibling section expired;
/// - populated content is kept while a refresh runs.
class PointsFeed extends ChangeNotifier {
  PointsFeed({
    required this.auth,
    ApiClient? client,
    DateTime Function()? clock,
    Future<String?> Function()? cacheDirectory,
  }) : _client = client ?? ApiClient.instance,
       _clock = clock ?? DateTime.now,
       _cacheDirectory = cacheDirectory {
    _accountId = auth.user?.id;
    _token = auth.token;
    _admin = auth.user?.isAdmin == true;
    auth.addListener(_handleAuthChange);
  }

  final AuthStore auth;
  final ApiClient _client;
  final DateTime Function() _clock;
  final Future<String?> Function()? _cacheDirectory;

  final PointsSection<PointsRows> rewards = PointsSection<PointsRows>(
    'rewards',
  );
  final PointsSection<PointsHistory> ledger = PointsSection<PointsHistory>(
    'ledger',
  );
  final PointsSection<PointsRows> orders = PointsSection<PointsRows>('orders');
  final PointsSection<PointsRows> adminOrders = PointsSection<PointsRows>(
    'adminOrders',
  );

  final Map<String, Future<void>> _inflight = {};
  final Map<String, Future<void>> _tails = {};
  Future<void>? _writes;
  Future<void>? _initialized;
  File? _cacheFile;
  String? _cacheUserId;
  String? _accountId;
  String? _token;
  bool _admin = false;
  bool _disposed = false;
  int _balanceRevision = 0;

  bool get offline => StudioProfile.current?.offlineOnly == true;

  /// Points to show in the header. Prefers the signed-in account because the
  /// server updates it after mutations and check-ins.
  int get availablePoints => auth.user?.points ?? ledger.value?.points ?? 0;

  String get _today {
    final now = _clock();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  /// Restores the per-account cache once, then refreshes sections that are not
  /// already fresh for today.
  Future<void> initialize() async {
    if (offline) {
      for (final section in _sections) {
        section.unavailable('离线版不提供积分功能');
      }
      return;
    }
    final active = _initialized;
    if (active != null) return active;
    final started = _restoreAndRefresh();
    _initialized = started;
    try {
      await started;
    } catch (_) {
      // A transient failure must not make every later initialize() rethrow.
      if (identical(_initialized, started)) _initialized = null;
      rethrow;
    }
  }

  List<PointsSection<Object?>> get _sections => [
    rewards,
    ledger,
    orders,
    adminOrders,
  ];

  Future<void> _restoreAndRefresh() async {
    await _restore();
    if (_disposed) return;
    await refreshAll();
  }

  Future<void> refreshAll({bool force = false, bool afterMutation = false}) {
    final futures = <Future<void>>[
      refreshRewards(force: force, afterMutation: afterMutation),
      refreshLedger(force: force, afterMutation: afterMutation),
      refreshOrders(force: force, afterMutation: afterMutation),
      if (_admin)
        refreshAdminOrders(force: force, afterMutation: afterMutation),
    ];
    return Future.wait(futures);
  }

  /// Records a mutation that changed the authoritative balance (for example a
  /// redemption). A ledger GET that started before this point must not publish
  /// its older balance afterwards, even when the two totals happen to match.
  void noteBalanceMutation() {
    _balanceRevision++;
  }

  Future<void> refreshRewards({
    bool force = false,
    bool afterMutation = false,
  }) => _load(
    rewards,
    (token) => _client.rewardItems(token, admin: _admin),
    force: force,
    afterMutation: afterMutation,
  );

  Future<void> refreshLedger({
    bool force = false,
    bool afterMutation = false,
  }) => _load(
    ledger,
    (token) async {
      final history = await _client.pointHistory(token);
      return PointsHistory(points: history.points, entries: history.entries);
    },
    force: force,
    afterMutation: afterMutation,
  );

  Future<void> refreshOrders({
    bool force = false,
    bool afterMutation = false,
  }) => _load(
    orders,
    (token) => _client.redemptions(token),
    force: force,
    afterMutation: afterMutation,
  );

  Future<void> refreshAdminOrders({
    bool force = false,
    bool afterMutation = false,
  }) {
    if (!_admin) return Future<void>.value();
    return _load(
      adminOrders,
      (token) => _client.redemptions(token, admin: true),
      force: force,
      afterMutation: afterMutation,
    );
  }

  Future<void> _load<T>(
    PointsSection<T> section,
    Future<T> Function(String token) fetch, {
    required bool force,
    bool afterMutation = false,
    bool fromTail = false,
  }) {
    if (_disposed || offline) return Future<void>.value();
    final token = auth.token;
    final userId = auth.user?.id;
    if (token == null || userId == null) return Future<void>.value();

    final active = _inflight[section.id];
    final queued = _tails[section.id];

    if (afterMutation) {
      // The mutation's result supersedes anything that started before it.
      // Start a fresh request now instead of joining a pre-mutation tail; the
      // newer generation makes the older response discard itself.
      _tails.remove(section.id);
      return _start(section, token, userId, fetch);
    }

    if (active != null) {
      // Deduplicate: an identical request is already on the wire. Forced
      // refreshes share a single trailing request per section, so repeated
      // taps cannot queue a chain of sequential fetches.
      if (!force) return active;
      if (fromTail) return active;
      if (queued != null) return queued;
      return _queueAfter(section, fetch, active, token, userId);
    }
    if (!force && section.isFresh(_today)) return Future<void>.value();

    return _start(section, token, userId, fetch);
  }

  Future<void> _start<T>(
    PointsSection<T> section,
    String token,
    String userId,
    Future<T> Function(String token) fetch,
  ) {
    final future = _run(section, token, userId, fetch);
    _inflight[section.id] = future;
    return future.whenComplete(() {
      if (identical(_inflight[section.id], future)) {
        _inflight.remove(section.id);
      }
    });
  }

  Future<void> _queueAfter<T>(
    PointsSection<T> section,
    Future<T> Function(String token) fetch,
    Future<void> previous,
    String token,
    String userId,
  ) {
    final generation = section._generation;
    late final Future<void> tail;
    tail = previous.catchError((Object _) {}).then((_) {
      if (section._generation != generation ||
          auth.token != token ||
          auth.user?.id != userId) {
        // A newer request (for example a mutation refresh) already superseded
        // this tail; starting another fetch would only duplicate it.
        if (identical(_tails[section.id], tail)) {
          _tails.remove(section.id);
        }
        return Future<void>.value();
      }
      if (identical(_inflight[section.id], previous)) {
        _inflight.remove(section.id);
      }
      // Keep this tail registered while its request runs so further manual
      // taps coalesce into it; fromTail prevents returning this same future.
      return _load(section, fetch, force: true, fromTail: true);
    });
    _tails[section.id] = tail;
    return tail.whenComplete(() {
      if (identical(_tails[section.id], tail)) {
        _tails.remove(section.id);
      }
    });
  }

  Future<void> _run<T>(
    PointsSection<T> section,
    String token,
    String userId,
    Future<T> Function(String token) fetch,
  ) async {
    final generation = ++section._generation;
    // Baseline behavior: a ledger GET snapshot is only allowed to publish its
    // balance when no mutation (check-in, redemption) changed it while the
    // request was in flight. The revision also covers mutations whose total
    // happens to equal the pre-mutation balance.
    final startingPoints = auth.user?.points;
    final revision = _balanceRevision;
    section._loading = true;
    section._error = null;
    section.notifyListeners();
    try {
      final value = await fetch(token);
      if (_disposed || generation != section._generation) return;
      if (auth.token != token || auth.user?.id != userId) return;
      section._value = value;
      section._day = _today;
      section._error = null;
      section._loading = false;
      section.notifyListeners();
      if (section == ledger && value is PointsHistory) {
        // A newer mutation balance always wins over this GET's older snapshot.
        if (revision == _balanceRevision &&
            auth.user?.points == startingPoints &&
            auth.user?.points != value.points) {
          try {
            await auth.updatePoints(points: value.points);
          } on FileSystemException {
            // AuthStore applies and notifies the balance before persisting, so
            // a failed auth.json write must not turn an otherwise successful
            // ledger load into an initialize() failure.
          }
        }
      }
      await _persistCache();
    } on ApiException catch (error) {
      if (_disposed || generation != section._generation) return;
      if (auth.token != token || auth.user?.id != userId) return;
      section._error = error.message;
      section._loading = false;
      section.notifyListeners();
    } finally {
      if (!_disposed && generation == section._generation && section._loading) {
        section._loading = false;
        section.notifyListeners();
      }
    }
  }

  void _handleAuthChange() {
    if (_disposed) return;
    final userId = auth.user?.id;
    final admin = auth.user?.isAdmin == true;
    final token = auth.token;
    final accountChanged = userId != _accountId || admin != _admin;
    // A rotated token invalidates every request issued with the old one, even
    // though the account itself is unchanged.
    final tokenChanged = token != _token;
    if (!accountChanged && !tokenChanged) return;
    _token = token;
    if (accountChanged) {
      _accountId = userId;
      _admin = admin;
      _cacheFile = null;
      _cacheUserId = null;
      for (final section in _sections) {
        section.reset();
      }
    }
    // Old-token futures discard their results, so drop the deduplication
    // registry; otherwise initialize() would wait on them and never issue a
    // new-token request for a section that is still empty.
    _inflight.clear();
    _tails.clear();
    _initialized = null;
    if (userId != null && token != null) {
      unawaited(initialize().catchError((Object _) {}));
    }
  }

  Future<void> _restore() async {
    final userId = auth.user?.id;
    if (userId == null || offline) return;
    try {
      final root =
          await (_cacheDirectory?.call() ?? AppPaths.storageDirectory());
      if (root == null || auth.user?.id != userId) return;
      final file = File(p.join(root, 'points_$userId.json'));
      _cacheFile = file;
      _cacheUserId = userId;
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || auth.user?.id != userId) return;
      final json = Map<String, dynamic>.from(data);
      if (json['sections'] is Map) {
        final sections = Map<String, dynamic>.from(json['sections'] as Map);
        _restoreSection(rewards, sections['rewards'], _decodeRowsOrNull);
        _restoreSection(ledger, sections['ledger'], _decodeHistory);
        _restoreSection(orders, sections['orders'], _decodeRowsOrNull);
        _restoreSection(
          adminOrders,
          sections['adminOrders'],
          _decodeRowsOrNull,
        );
      } else {
        // Version 1 wrote one flat day for every section.
        final day = json['day'] as String?;
        if (day == null) return;
        rewards.restore(_decodeRows(json['items']), day);
        ledger.restore(
          PointsHistory(
            points: (json['points'] as num?)?.toInt() ?? 0,
            entries: _decodeRows(json['ledger']),
          ),
          day,
        );
        orders.restore(_decodeRows(json['orders']), day);
        adminOrders.restore(_decodeRows(json['adminOrders']), day);
      }
    } on Object {
      // A missing, damaged or unreadable cache is replaced by live sections.
    }
  }

  void _restoreSection<T>(
    PointsSection<T> section,
    Object? raw,
    T? Function(Object? data) decode,
  ) {
    if (raw is! Map) return;
    final entry = Map<String, dynamic>.from(raw);
    final value = decode(entry['data']);
    if (value == null) return;
    section.restore(value, entry['day'] as String?);
  }

  /// Returns null for a section that has never been fetched, so an unloaded
  /// section keeps showing its spinner instead of a misleading empty list.
  PointsRows? _decodeRowsOrNull(Object? data) {
    if (data is! List) return null;
    return [for (final row in data) Map<String, dynamic>.from(row as Map)];
  }

  PointsRows _decodeRows(Object? data) => _decodeRowsOrNull(data) ?? const [];

  PointsHistory? _decodeHistory(Object? data) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    return PointsHistory(
      points: (map['points'] as num?)?.toInt() ?? 0,
      entries: _decodeRows(map['entries']),
    );
  }

  Map<String, dynamic> _encodeSection<T>(
    PointsSection<T> section,
    Object? Function(T value) encode,
  ) => {
    'day': section._day,
    'data': section._value == null ? null : encode(section._value as T),
  };

  Future<void> _persistCache() {
    if (_disposed) return Future<void>.value();
    final userId = auth.user?.id;
    if (userId == null) return Future<void>.value();
    final file = _cacheFile;
    // Do not write one account's cache while another account is loaded.
    if (file == null || _cacheUserId != userId) return Future<void>.value();
    final encoded = jsonEncode({
      'version': 2,
      'userId': userId,
      'sections': {
        'rewards': _encodeSection(rewards, (rows) => rows),
        'ledger': _encodeSection(
          ledger,
          (history) => {'points': history.points, 'entries': history.entries},
        ),
        'orders': _encodeSection(orders, (rows) => rows),
        'adminOrders': _encodeSection(adminOrders, (rows) => rows),
      },
    });
    Future<void> write() async {
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    }

    final previous = _writes;
    return _writes = previous == null
        ? write().catchError((Object _) {})
        : previous
              .catchError((Object _) {})
              .then((_) => write().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_handleAuthChange);
    for (final section in _sections) {
      section.dispose();
    }
    super.dispose();
  }
}
