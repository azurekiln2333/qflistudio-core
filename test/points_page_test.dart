import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/pages/points_page.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

const _headers = {'content-type': 'application/json; charset=utf-8'};

CommunityUser _user({
  String id = 'user_a',
  int points = 10,
  bool admin = false,
}) => CommunityUser(
  id: id,
  username: 'tester',
  nickname: 'Tester',
  bio: '',
  avatarColor: '#2196F3',
  points: points,
  checkinStreak: 0,
  provider: 'local',
  isAdmin: admin,
);

http.Response _json(Object value) =>
    http.Response(jsonEncode(value), 200, headers: _headers);

List<Map<String, dynamic>> _ledgerEntries(int count) => [
  for (var index = 1; index <= count; index++)
    {
      'kind': 'task',
      'reference_id': 'task:create_project',
      'amount': index,
      'balance_after': index,
      'created_at': '2026-10-23 10:00',
    },
];

Map<String, dynamic> _reward({int stock = 5, int cost = 10}) => {
  'id': 'r1',
  'title': '测试兑换',
  'description': '兑换说明',
  'cost': cost,
  'stock': stock,
  'enabled': 1,
};

class _Backend {
  _Backend({
    this.gateRewards = false,
    this.gateLedger = false,
    this.entryCount = 3,
    this.rewardCost = 10,
    this.ledgerPoints = 10,
  });

  final bool gateRewards;
  final bool gateLedger;
  final int entryCount;
  final int rewardCost;
  final int ledgerPoints;
  final Completer<void> rewardsGate = Completer<void>();
  final Completer<void> ledgerGate = Completer<void>();
  final Completer<void> redeemGate = Completer<void>();
  bool gateRedeem = false;
  bool redeemed = false;
  int rewardCalls = 0;
  int ledgerCalls = 0;
  int orderCalls = 0;
  int redeemCalls = 0;

  List<Map<String, dynamic>> _orders() => [
    if (redeemed)
      {
        'id': 'o1',
        'item_title': '测试兑换',
        'cost': rewardCost,
        'status': 'pending',
        'created_at': '2026-10-23 11:00',
        'user_id': 'user_a',
      },
  ];

  late final ApiClient client = ApiClient(
    transport: MockClient((request) async {
      final path = request.url.path;
      final authorization = request.headers['authorization'];
      if (path.endsWith('/users/me/rewards') ||
          path.endsWith('/users/admin/rewards')) {
        rewardCalls++;
        if (gateRewards) await rewardsGate.future;
        return _json({
          'items': [
            _reward(stock: redeemed ? rewardCost - 1 : 5, cost: rewardCost),
          ],
        });
      }
      if (path.endsWith('/users/me/points')) {
        ledgerCalls++;
        if (gateLedger) await ledgerGate.future;
        // A different signed-in account has its own balance.
        final points = authorization == 'Bearer token-b'
            ? 50
            : (redeemed ? 0 : ledgerPoints);
        return _json({'points': points, 'entries': _ledgerEntries(entryCount)});
      }
      if (path.endsWith('/users/me/redemptions') ||
          path.endsWith('/users/admin/redemptions')) {
        orderCalls++;
        return _json({'items': _orders()});
      }
      if (request.method == 'POST' && path.endsWith('/rewards/r1/redeem')) {
        redeemCalls++;
        if (gateRedeem) await redeemGate.future;
        redeemed = true;
        return _json({'points': 0});
      }
      return http.Response('not found', 404);
    }),
  );
}

/// Signs in without `load()`, so no auth file I/O runs inside the fake-async
/// widget test. The page only reads token, user and points.
Future<AuthStore> _auth(CommunityUser user) async {
  final auth = AuthStore();
  await auth.signIn('token-a', user);
  return auth;
}

/// Applies the balance in memory like [AuthStore], then fails the disk write.
class _DiskFailAuth extends AuthStore {
  int updateCalls = 0;

  @override
  Future<void> updatePoints({
    int? points,
    int? streak,
    UserGrowth? growth,
  }) async {
    updateCalls++;
    await super.updatePoints(points: points, streak: streak, growth: growth);
    throw const FileSystemException('disk full');
  }
}

Widget _page(AuthStore auth, _Backend backend) => MaterialApp(
  home: PointsPage(
    auth: auth,
    client: backend.client,
    clock: () => DateTime(2026, 10, 23),
    // Null disables the on-disk cache; cache behavior is covered by
    // points_feed_test.dart with real file I/O.
    cacheDirectory: () async => null,
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('condition was not met');
}

void main() {
  testWidgets('a slow rewards section does not block other tabs', (
    tester,
  ) async {
    final auth = await _auth(_user());
    final backend = _Backend(gateRewards: true);

    await tester.pumpWidget(_page(auth, backend));
    await _pumpUntil(tester, () => backend.ledgerCalls == 1);
    await tester.pump(const Duration(milliseconds: 50));

    // The rewards request is still on the wire, yet the ledger tab is usable.
    expect(backend.rewardCalls, 1);
    await tester.tap(find.text('积分明细'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('创建项目 (1 次)'), findsWidgets);

    await tester.tap(find.text('兑换'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('测试兑换'), findsNothing);

    backend.rewardsGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('测试兑换'), findsOneWidget);
  });

  testWidgets(
    'tab switches keep content and scroll position without refetching',
    (tester) async {
      final auth = await _auth(_user());
      final backend = _Backend(entryCount: 30);

      await tester.pumpWidget(_page(auth, backend));
      await tester.pumpAndSettle();
      expect(backend.rewardCalls, 1);
      expect(backend.ledgerCalls, 1);
      expect(backend.orderCalls, 1);

      await tester.tap(find.text('积分明细'));
      await tester.pumpAndSettle();
      expect(find.text('+1'), findsOneWidget);

      await tester.drag(find.text('+1'), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('+1'), findsNothing);

      await tester.tap(find.text('兑换'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的兑换'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('积分明细'));
      await tester.pumpAndSettle();

      // The scroll offset survived, and no tab switch restarted a request.
      expect(find.text('+1'), findsNothing);
      expect(backend.rewardCalls, 1);
      expect(backend.ledgerCalls, 1);
      expect(backend.orderCalls, 1);
    },
  );

  testWidgets('header refresh reloads every section and redeem updates state', (
    tester,
  ) async {
    final auth = await _auth(_user());
    final backend = _Backend();

    await tester.pumpWidget(_page(auth, backend));
    await tester.pumpAndSettle();
    expect(backend.rewardCalls, 1);
    expect(backend.ledgerCalls, 1);
    expect(backend.orderCalls, 1);

    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(backend.rewardCalls, 2);
    expect(backend.ledgerCalls, 2);
    expect(backend.orderCalls, 2);

    await tester.tap(find.widgetWithText(FilledButton, '10 积分'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '兑换'));
    await tester.pumpAndSettle();

    expect(backend.redeemCalls, 1);
    expect(auth.user?.points, 0);
    expect(find.text('兑换已提交'), findsOneWidget);
    await tester.tap(find.text('我的兑换'));
    await tester.pumpAndSettle();
    expect(find.text('测试兑换'), findsOneWidget);

    // Let the snackbar timer expire so the test ends without pending timers.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('reward buttons re-evaluate when the balance arrives later', (
    tester,
  ) async {
    final auth = await _auth(_user(points: 0));
    final backend = _Backend(
      gateLedger: true,
      rewardCost: 100,
      ledgerPoints: 100,
    );

    await tester.pumpWidget(_page(auth, backend));
    await _pumpUntil(tester, () => backend.rewardCalls == 1);
    await tester.pump(const Duration(milliseconds: 50));

    // Rewards arrived first; the ledger (and therefore the balance) has not.
    final button = find.widgetWithText(FilledButton, '100 积分');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    backend.ledgerGate.complete();
    await _pumpUntil(tester, () {
      final finder = find.widgetWithText(FilledButton, '100 积分');
      if (finder.evaluate().isEmpty) return false;
      return tester.widget<FilledButton>(finder).onPressed != null;
    });
    expect(auth.user?.points, 100);
  });

  testWidgets('admin role change while mounted updates the shell', (
    tester,
  ) async {
    final auth = await _auth(_user());
    final backend = _Backend();

    await tester.pumpWidget(_page(auth, backend));
    await tester.pumpAndSettle();
    expect(find.byTooltip('新增兑换项'), findsNothing);
    expect(find.text('待处理'), findsNothing);
    expect(find.byType(Tab), findsNWidgets(3));

    await auth.signIn('token-a', _user(admin: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('新增兑换项'), findsOneWidget);
    expect(find.text('待处理'), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(4));

    await auth.signIn('token-a', _user());
    await tester.pumpAndSettle();
    expect(find.byTooltip('新增兑换项'), findsNothing);
    expect(find.text('待处理'), findsNothing);
    expect(find.byType(Tab), findsNWidgets(3));
  });

  testWidgets('a redemption response for a previous account is ignored', (
    tester,
  ) async {
    final auth = await _auth(_user(points: 10));
    final backend = _Backend()..gateRedeem = true;

    await tester.pumpWidget(_page(auth, backend));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '10 积分'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '兑换'));
    await _pumpUntil(tester, () => backend.redeemCalls == 1);

    // Switch accounts while the redemption request is still pending.
    await auth.signIn('token-b', _user(id: 'user_b', points: 50));
    await _pumpUntil(tester, () => backend.ledgerCalls == 2);
    await tester.pump(const Duration(milliseconds: 50));
    final rewardCalls = backend.rewardCalls;
    final ledgerCalls = backend.ledgerCalls;
    final orderCalls = backend.orderCalls;

    backend.redeemGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The old account's response must not toast, refresh or rewrite B.
    expect(auth.user?.id, 'user_b');
    expect(auth.user?.points, 50);
    expect(find.text('兑换已提交'), findsNothing);
    expect(backend.rewardCalls, rewardCalls);
    expect(backend.ledgerCalls, ledgerCalls);
    expect(backend.orderCalls, orderCalls);
  });

  testWidgets('a redemption survives a local points write failure', (
    tester,
  ) async {
    final auth = _DiskFailAuth();
    await auth.signIn('token-a', _user(points: 10));
    final backend = _Backend();

    await tester.pumpWidget(_page(auth, backend));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '10 积分'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '兑换'));
    await tester.pumpAndSettle();

    expect(backend.redeemCalls, 1);
    expect(auth.updateCalls, 1);
    // The balance was applied in memory before the failed disk write.
    expect(auth.user?.points, 0);
    expect(find.text('兑换已提交，但本地积分保存失败，请稍后刷新'), findsOneWidget);
    // The redemption is still treated as successful: stock, ledger and orders
    // refresh after the mutation instead of being skipped by the IO failure.
    expect(backend.rewardCalls, 2);
    expect(backend.ledgerCalls, 2);
    expect(backend.orderCalls, 2);

    await tester.tap(find.text('我的兑换'));
    await tester.pumpAndSettle();
    expect(find.text('测试兑换'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
