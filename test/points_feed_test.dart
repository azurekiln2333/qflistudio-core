import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/points_feed.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

const _headers = {'content-type': 'application/json; charset=utf-8'};

CommunityUser _user(String id, {int points = 0, bool admin = false}) =>
    CommunityUser(
      id: id,
      username: id,
      nickname: id,
      bio: '',
      avatarColor: '#2196F3',
      points: points,
      checkinStreak: 0,
      provider: 'local',
      isAdmin: admin,
    );

http.Response _json(Object value) =>
    http.Response(jsonEncode(value), 200, headers: _headers);

Map<String, dynamic> _reward(String id) => {
  'id': id,
  'title': '兑换 $id',
  'description': '说明',
  'cost': 10,
  'stock': 5,
  'enabled': 1,
};

Map<String, dynamic> _entry(int amount) => {
  'kind': 'task',
  'reference_id': 'task:create_project',
  'amount': amount,
  'balance_after': amount,
  'created_at': '2026-10-23 10:00',
};

Future<AuthStore> _auth(File file, String token, CommunityUser user) async {
  final auth = AuthStore(storageFile: file);
  await auth.load();
  await auth.signIn(token, user);
  return auth;
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met');
}

Future<void> _deleteTemp(Directory dir) async {
  // A discarded account flow may still flush its cache just after the test
  // body returns; retry briefly instead of failing cleanup.
  for (var attempt = 0; attempt < 40; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  test(
    'sections load independently and identical requests are deduplicated',
    () async {
      final dir = await Directory.systemTemp.createTemp('qfli-points-feed-');
      addTearDown(() => _deleteTemp(dir));
      final auth = await _auth(
        File(p.join(dir.path, 'auth.json')),
        'token-a',
        _user('user_a', points: 10),
      );

      var rewardCalls = 0;
      var ledgerCalls = 0;
      var orderCalls = 0;
      final rewardsGate = Completer<void>();
      final client = ApiClient(
        transport: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/users/me/rewards')) {
            rewardCalls++;
            await rewardsGate.future;
            return _json({
              'items': [_reward('r1')],
            });
          }
          if (path.endsWith('/users/me/points')) {
            ledgerCalls++;
            return _json({
              'points': 42,
              'entries': [_entry(42)],
            });
          }
          if (path.endsWith('/users/me/redemptions')) {
            orderCalls++;
            return _json({'items': []});
          }
          return http.Response('not found', 404);
        }),
      );
      final feed = PointsFeed(
        auth: auth,
        client: client,
        clock: () => DateTime(2026, 10, 23),
        cacheDirectory: () async => dir.path,
      );
      addTearDown(feed.dispose);

      final initialized = feed.initialize();
      await _until(() => feed.ledger.value != null);

      // The ledger and orders completed even though rewards is still on the wire.
      expect(feed.ledger.value?.points, 42);
      expect(feed.ledger.value?.entries, hasLength(1));
      expect(feed.orders.value, isEmpty);
      expect(feed.rewards.loading, true);
      expect(feed.rewards.value, isNull);
      expect(auth.user?.points, 42);

      // A second request while the first is in flight reuses it.
      final duplicate = feed.refreshRewards();
      await pumpEventQueue();
      expect(rewardCalls, 1);
      rewardsGate.complete();
      await initialized;
      await duplicate;
      expect(feed.rewards.value, hasLength(1));
      expect(feed.rewards.loading, false);
      expect(rewardCalls, 1);
      expect(ledgerCalls, 1);
      expect(orderCalls, 1);
    },
  );

  test('cache is per section, per account and per day', () async {
    final dir = await Directory.systemTemp.createTemp('qfli-points-cache-');
    addTearDown(() => _deleteTemp(dir));
    final auth = await _auth(
      File(p.join(dir.path, 'auth.json')),
      'token-a',
      _user('user_a', points: 5),
    );

    // Only rewards is stale for today; the other sections must not refetch.
    final cache = File(p.join(dir.path, 'points_user_a.json'));
    await cache.writeAsString(
      jsonEncode({
        'version': 2,
        'userId': 'user_a',
        'sections': {
          'rewards': {
            'day': '2026-10-22',
            'data': [_reward('old')],
          },
          'ledger': {
            'day': '2026-10-23',
            'data': {
              'points': 5,
              'entries': [_entry(5)],
            },
          },
          'orders': {'day': '2026-10-23', 'data': []},
          'adminOrders': {'day': '2026-10-23', 'data': []},
        },
      }),
    );

    var rewardCalls = 0;
    var ledgerCalls = 0;
    var orderCalls = 0;
    final client = ApiClient(
      transport: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/users/me/rewards')) {
          rewardCalls++;
          return _json({
            'items': [_reward('fresh')],
          });
        }
        if (path.endsWith('/users/me/points')) {
          ledgerCalls++;
          return _json({'points': 99, 'entries': []});
        }
        if (path.endsWith('/users/me/redemptions')) {
          orderCalls++;
          return _json({'items': []});
        }
        return http.Response('not found', 404);
      }),
    );
    final feed = PointsFeed(
      auth: auth,
      client: client,
      clock: () => DateTime(2026, 10, 23),
      cacheDirectory: () async => dir.path,
    );

    await feed.initialize();
    expect(rewardCalls, 1);
    expect(ledgerCalls, 0);
    expect(orderCalls, 0);
    expect(feed.rewards.value?.single['id'], 'fresh');
    expect(feed.ledger.value?.points, 5);

    // A new day invalidates every section, but a fresh cache does not refetch.
    final freshClient = ApiClient(
      transport: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/users/me/rewards')) {
          rewardCalls++;
          return _json({
            'items': [_reward('day2')],
          });
        }
        if (path.endsWith('/users/me/points')) {
          ledgerCalls++;
          return _json({'points': 7, 'entries': []});
        }
        if (path.endsWith('/users/me/redemptions')) {
          orderCalls++;
          return _json({'items': []});
        }
        return http.Response('not found', 404);
      }),
    );
    final nextDay = PointsFeed(
      auth: auth,
      client: freshClient,
      clock: () => DateTime(2026, 10, 24),
      cacheDirectory: () async => dir.path,
    );
    await nextDay.initialize();
    expect(rewardCalls, 2);
    expect(ledgerCalls, 1);
    expect(orderCalls, 1);

    // Stop the first-day feeds before switching accounts so only feedB drives
    // the counters from here on.
    feed.dispose();
    nextDay.dispose();

    // A different account never reads user_a's file.
    await auth.signIn('token-b', _user('user_b', points: 1));
    var accountBPoints = 0;
    final clientB = ApiClient(
      transport: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/users/me/rewards')) {
          return _json({'items': []});
        }
        if (path.endsWith('/users/me/points')) {
          accountBPoints++;
          return _json({'points': 1, 'entries': []});
        }
        if (path.endsWith('/users/me/redemptions')) {
          return _json({'items': []});
        }
        return http.Response('not found', 404);
      }),
    );
    final feedB = PointsFeed(
      auth: auth,
      client: clientB,
      clock: () => DateTime(2026, 10, 24),
      cacheDirectory: () async => dir.path,
    );
    addTearDown(feedB.dispose);
    await feedB.initialize();
    expect(feedB.ledger.value?.points, 1);
    expect(accountBPoints, 1);
  });

  test('a response from the previous account is discarded', () async {
    final dir = await Directory.systemTemp.createTemp('qfli-points-stale-');
    addTearDown(() => _deleteTemp(dir));
    final auth = await _auth(
      File(p.join(dir.path, 'auth.json')),
      'token-a',
      _user('user_a', points: 10),
    );

    final accountAGate = Completer<void>();
    final client = ApiClient(
      transport: MockClient((request) async {
        final path = request.url.path;
        final token = request.headers['authorization'];
        if (path.endsWith('/users/me/rewards')) {
          return _json({'items': []});
        }
        if (path.endsWith('/users/me/points')) {
          if (token == 'Bearer token-a') {
            await accountAGate.future;
            return _json({'points': 42, 'entries': []});
          }
          return _json({'points': 7, 'entries': []});
        }
        if (path.endsWith('/users/me/redemptions')) {
          return _json({'items': []});
        }
        return http.Response('not found', 404);
      }),
    );
    final feed = PointsFeed(
      auth: auth,
      client: client,
      clock: () => DateTime(2026, 10, 23),
      cacheDirectory: () async => dir.path,
    );
    addTearDown(feed.dispose);

    final initialized = feed.initialize();
    await _until(() => feed.ledger.loading);
    expect(feed.ledger.loading, true);

    await auth.signIn('token-b', _user('user_b', points: 7));
    await _until(() => feed.ledger.value?.points == 7);
    expect(feed.ledger.value?.points, 7);

    accountAGate.complete();
    await initialized.catchError((Object _) {});
    await feed.refreshAll();
    await pumpEventQueue();
    // The late user_a response must not overwrite user_b.
    expect(feed.ledger.value?.points, 7);
    expect(auth.user?.id, 'user_b');
  });

  test(
    'a delayed ledger response cannot overwrite a newer mutation balance',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'qfli-points-mutation-',
      );
      addTearDown(() => _deleteTemp(dir));
      final auth = await _auth(
        File(p.join(dir.path, 'auth.json')),
        'token-a',
        _user('user_a', points: 10),
      );

      final gate = Completer<void>();
      var calls = 0;
      final client = ApiClient(
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/users/me/points')) {
            calls++;
            if (calls == 1) {
              await gate.future;
              // Snapshot taken before the mutation landed.
              return _json({
                'points': 10,
                'entries': [_entry(10)],
              });
            }
            return _json({
              'points': 20,
              'entries': [_entry(20)],
            });
          }
          return http.Response('not found', 404);
        }),
      );
      final feed = PointsFeed(
        auth: auth,
        client: client,
        clock: () => DateTime(2026, 10, 23),
        cacheDirectory: () async => null,
      );
      addTearDown(feed.dispose);

      final refresh = feed.refreshLedger();
      await _until(() => feed.ledger.loading);
      // A check-in/redemption lands while the GET is still on the wire.
      await auth.updatePoints(points: 20);
      gate.complete();
      await refresh;

      expect(feed.ledger.value?.points, 10);
      // The newer mutation balance wins; the older GET must not undo it.
      expect(auth.user?.points, 20);
      expect(feed.availablePoints, 20);

      await feed.refreshLedger(force: true);
      expect(calls, 2);
      expect(feed.ledger.value?.points, 20);
      expect(auth.user?.points, 20);
    },
  );

  test(
    'a token rotation for the same account restarts invalidated loads',
    () async {
      final dir = await Directory.systemTemp.createTemp('qfli-points-token-');
      addTearDown(() => _deleteTemp(dir));
      final auth = await _auth(
        File(p.join(dir.path, 'auth.json')),
        'token-a',
        _user('user_a', points: 10),
      );

      final gate = Completer<void>();
      final ledgerTokens = <String>[];
      final client = ApiClient(
        transport: MockClient((request) async {
          final path = request.url.path;
          final token = request.headers['authorization'] ?? '';
          if (path.endsWith('/users/me/rewards')) {
            return _json({'items': []});
          }
          if (path.endsWith('/users/me/points')) {
            ledgerTokens.add(token);
            if (token == 'Bearer token-a') {
              await gate.future;
              return _json({'points': 10, 'entries': []});
            }
            return _json({'points': 42, 'entries': []});
          }
          if (path.endsWith('/users/me/redemptions')) {
            return _json({'items': []});
          }
          return http.Response('not found', 404);
        }),
      );
      final feed = PointsFeed(
        auth: auth,
        client: client,
        clock: () => DateTime(2026, 10, 23),
        cacheDirectory: () async => dir.path,
      );
      addTearDown(feed.dispose);

      final initial = feed.initialize();
      await _until(() => feed.ledger.loading);

      // Same account, rotated token: the old-token ledger request is invalidated.
      await auth.signIn('token-b', _user('user_a', points: 10));
      await _until(() => feed.ledger.value?.points == 42);

      gate.complete();
      await initial.catchError((Object _) {});
      await feed.refreshAll();

      expect(
        ledgerTokens.where((token) => token == 'Bearer token-b'),
        hasLength(1),
      );
      expect(feed.ledger.value?.points, 42);
      expect(auth.user?.points, 42);
      expect(auth.token, 'token-b');
    },
  );

  test('concurrent forced refreshes share one trailing request', () async {
    final dir = await Directory.systemTemp.createTemp('qfli-points-force-');
    addTearDown(() => _deleteTemp(dir));
    final auth = await _auth(
      File(p.join(dir.path, 'auth.json')),
      'token-a',
      _user('user_a', points: 10),
    );

    final firstGate = Completer<void>();
    final tailGate = Completer<void>();
    var calls = 0;
    final client = ApiClient(
      transport: MockClient((request) async {
        if (request.url.path.endsWith('/users/me/points')) {
          calls++;
          if (calls == 1) {
            await firstGate.future;
            return _json({'points': 10, 'entries': []});
          }
          if (calls == 2) {
            await tailGate.future;
            return _json({'points': 20, 'entries': []});
          }
          return _json({'points': 30, 'entries': []});
        }
        return http.Response('not found', 404);
      }),
    );
    final feed = PointsFeed(
      auth: auth,
      client: client,
      clock: () => DateTime(2026, 10, 23),
      cacheDirectory: () async => null,
    );
    addTearDown(feed.dispose);

    final first = feed.refreshLedger(force: true);
    await _until(() => calls == 1);
    // Ten taps while the first request is blocked must queue exactly one more.
    final forced = [
      for (var index = 0; index < 10; index++) feed.refreshLedger(force: true),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);

    firstGate.complete();
    await _until(() => calls == 2);
    // Ten more taps while the trailing request runs coalesce into that same
    // request instead of queueing a third fetch.
    final forcedAgain = [
      for (var index = 0; index < 10; index++) feed.refreshLedger(force: true),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);

    tailGate.complete();
    await first;
    await Future.wait([...forced, ...forcedAgain]);
    expect(calls, 2);
    expect(feed.ledger.value?.points, 20);
    expect(auth.user?.points, 20);
  });

  test('a failed auth write does not fail a successful ledger load', () async {
    final dir = await Directory.systemTemp.createTemp('qfli-points-authio-');
    addTearDown(() => _deleteTemp(dir));
    final authDir = Directory(p.join(dir.path, 'authdir'));
    final auth = AuthStore(
      storageFile: File(p.join(authDir.path, 'auth.json')),
    );
    await auth.load();
    await auth.signIn('token-a', _user('user_a', points: 10));
    // Replace the auth directory with a file so the next write fails.
    await authDir.delete(recursive: true);
    await File(authDir.path).writeAsString('blocked');

    final client = ApiClient(
      transport: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/users/me/points')) {
          return _json({
            'points': 42,
            'entries': [_entry(42)],
          });
        }
        if (path.endsWith('/users/me/rewards')) {
          return _json({'items': []});
        }
        if (path.endsWith('/users/me/redemptions')) {
          return _json({'items': []});
        }
        return http.Response('not found', 404);
      }),
    );
    final feed = PointsFeed(
      auth: auth,
      client: client,
      clock: () => DateTime(2026, 10, 23),
      cacheDirectory: () async => null,
    );
    addTearDown(feed.dispose);

    // initialize() must complete even though auth.json cannot be written.
    await feed.initialize();
    expect(feed.ledger.value?.points, 42);
    expect(auth.user?.points, 42);
  });

  test(
    'a mutation refresh supersedes a blocked pre-mutation request',
    () async {
      final dir = await Directory.systemTemp.createTemp('qfli-points-mutate-');
      addTearDown(() => _deleteTemp(dir));
      final auth = await _auth(
        File(p.join(dir.path, 'auth.json')),
        'token-a',
        _user('user_a', points: 10),
      );

      var ledgerCalls = 0;
      final gates = [Completer<void>(), Completer<void>()];
      final client = ApiClient(
        transport: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/users/me/points')) {
            final call = ledgerCalls++;
            if (call < gates.length) await gates[call].future;
            final points = call == 0 ? 100 : 80;
            return _json({
              'points': points,
              'entries': [_entry(points)],
            });
          }
          if (path.endsWith('/users/me/rewards')) {
            return _json({'items': []});
          }
          if (path.endsWith('/users/me/redemptions')) {
            return _json({'items': []});
          }
          return http.Response('not found', 404);
        }),
      );
      final feed = PointsFeed(
        auth: auth,
        client: client,
        clock: () => DateTime(2026, 10, 23),
        cacheDirectory: () async => null,
      );
      addTearDown(feed.dispose);

      final first = feed.refreshLedger();
      await _until(() => ledgerCalls == 1);
      // A manual refresh queued behind the blocked request would normally be
      // reused by a later forced refresh.
      final manual = feed.refreshLedger(force: true);
      await Future<void>.delayed(Duration.zero);

      feed.noteBalanceMutation();
      final mutation = feed.refreshLedger(force: true, afterMutation: true);
      // The mutation refresh must not join the pre-mutation tail: its request
      // starts immediately even though the first response is still blocked.
      await _until(() => ledgerCalls == 2);
      expect(feed.ledger.value, isNull);

      gates[1].complete();
      await mutation;
      expect(feed.ledger.value?.points, 80);
      expect(auth.user?.points, 80);

      // The late pre-mutation response cannot replace the newer data.
      gates[0].complete();
      await first;
      await manual;
      expect(feed.ledger.value?.points, 80);
      expect(auth.user?.points, 80);
      expect(ledgerCalls, 2);
    },
  );

  test(
    'a mutation refresh supersedes an already-running manual tail',
    () async {
      final dir = await Directory.systemTemp.createTemp('qfli-points-tail-');
      addTearDown(() => _deleteTemp(dir));
      final auth = await _auth(
        File(p.join(dir.path, 'auth.json')),
        'token-a',
        _user('user_a', points: 100),
      );
      final firstGate = Completer<void>();
      final tailGate = Completer<void>();
      final tailStarted = Completer<void>();
      var calls = 0;
      final client = ApiClient(
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/users/me/points')) {
            final call = ++calls;
            if (call == 1) await firstGate.future;
            if (call == 2) {
              tailStarted.complete();
              await tailGate.future;
            }
            final points = call < 3 ? 100 : 80;
            return _json({
              'points': points,
              'entries': [_entry(points)],
            });
          }
          return http.Response('not found', 404);
        }),
      );
      addTearDown(client.close);
      final feed = PointsFeed(
        auth: auth,
        client: client,
        clock: () => DateTime(2026, 10, 23),
        cacheDirectory: () async => null,
      );
      addTearDown(feed.dispose);

      final first = feed.refreshLedger();
      final manual = feed.refreshLedger(force: true);
      firstGate.complete();
      await tailStarted.future;

      feed.noteBalanceMutation();
      await auth.updatePoints(points: 80);
      await feed.refreshLedger(force: true, afterMutation: true);
      expect(calls, 3);
      expect(feed.ledger.value?.points, 80);

      tailGate.complete();
      await Future.wait([first, manual]);
      expect(calls, 3);
      expect(feed.ledger.value?.points, 80);
      expect(auth.user?.points, 80);
    },
  );

  test(
    'a delayed ledger cannot overwrite a mutation balance of equal total',
    () async {
      final dir = await Directory.systemTemp.createTemp('qfli-points-rev-');
      addTearDown(() => _deleteTemp(dir));
      final auth = await _auth(
        File(p.join(dir.path, 'auth.json')),
        'token-a',
        _user('user_a', points: 100),
      );

      final gate = Completer<void>();
      var calls = 0;
      final client = ApiClient(
        transport: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/users/me/points')) {
            calls++;
            await gate.future;
            return _json({
              'points': 80,
              'entries': [_entry(80)],
            });
          }
          if (path.endsWith('/users/me/rewards')) {
            return _json({'items': []});
          }
          if (path.endsWith('/users/me/redemptions')) {
            return _json({'items': []});
          }
          return http.Response('not found', 404);
        }),
      );
      final feed = PointsFeed(
        auth: auth,
        client: client,
        clock: () => DateTime(2026, 10, 23),
        cacheDirectory: () async => null,
      );
      addTearDown(feed.dispose);

      final load = feed.refreshLedger();
      await _until(() => calls == 1);
      // A mutation publishes a balance whose total happens to equal the value
      // captured when the GET started, so comparing totals alone is insufficient.
      feed.noteBalanceMutation();
      await auth.updatePoints(points: 100);
      gate.complete();
      await load;

      expect(auth.user?.points, 100);
      expect(feed.ledger.value?.points, 80);
    },
  );
}
