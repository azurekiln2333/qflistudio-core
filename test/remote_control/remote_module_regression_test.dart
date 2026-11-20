// Regressions for the remote-control migration review (reports/remote-review.md,
// findings R1-R3). New in phase 05; there is no source file to port.
//
// These tests deliberately use the real widgets, the real `Navigator` (default
// route transitions included) and the real wire frames of a scripted agent. They
// assert what the desktop would see - `herdr_watch`, `herdr_send_text`,
// `herdr_send_keys`, `herdr_prompt`, `send`, `close_session` - and the selection
// the UI would render, rather than lease internals.
//
// Not run locally: the coordinator's phase rules forbid local suites. Cloud CI
// owns execution; see reports/phase-05-review-fixes.md.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/remote_control/pages/herdr_terminal_screen.dart';
import 'package:qfli_studio_core/remote_control/pages/home_screen.dart';
import 'package:qfli_studio_core/remote_control/pages/pair_screen.dart';
import 'package:qfli_studio_core/remote_control/pages/session_screen.dart';
import 'package:qfli_studio_core/remote_control/remote_computer_page.dart';
import 'package:qfli_studio_core/remote_control/state/herdr_controller.dart';
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart';
import 'package:qfli_studio_core/remote_control/state/remote_store.dart';
import 'package:qfli_studio_core/remote_control/widgets/herdr_terminal.dart';
import 'package:qfli_studio_core/remote_control/widgets/herdr_terminal_rows.dart';
import 'package:qfli_studio_core/remote_control/widgets/module_exit.dart';
import 'package:qfli_studio_core/remote_control/widgets/session_card.dart';

import '../support/fake_relay.dart';
import '../support/remote_control_app.dart';
import 'herdr_test.dart'
    show availabilityJson, paneJson, tabJson, workspaceJson;

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

const String _terminalSessionId = 't1';
const String _claudeSessionId = 'c1';

/// Desktop focused pane. A terminal screen follows it when nothing is remembered.
const String _paneA = 'wJ:p2';

/// Second pane, selected explicitly (a chip tap) in the route tests.
const String _paneB = 'wJ:p3';

Map<String, dynamic> _terminalSession() => sessionJson(
  _terminalSessionId,
  kind: 'terminal',
  status: 'running',
  title: '桌面终端',
);

Map<String, dynamic> _claudeSession() =>
    sessionJson(_claudeSessionId, status: 'idle', title: 'Claude 会话');

List<Map<String, dynamic>> _panes() => <Map<String, dynamic>>[
  paneJson(paneId: _paneA, name: 'shell', focused: true),
  paneJson(paneId: _paneB, name: 'scratch'),
];

/// A healthy agent that also answers the Herdr requests these tests need.
///
/// The base handler from `fake_relay.dart` keeps the hello/info/list_sessions
/// handshake and the default `ack` for everything else; this layer only adds the
/// `herdr_*` replies, so the controller reaches `canControl` with two panes.
FakeSocket _agent({List<Map<String, dynamic>>? sessions}) {
  final socket = healthyAgent(
    sessions:
        sessions ??
        <Map<String, dynamic>>[_terminalSession(), _claudeSession()],
    capabilities: const <String>['terminal', 'herdr'],
  );
  final base = socket.onSend!;
  socket.onSend = (s, frame) {
    final data = frame['data'];
    if (data is! Map<String, dynamic> ||
        !(data['type'] as String? ?? '').startsWith('herdr_')) {
      base(s, frame);
      return;
    }
    final id = data['id'];
    scheduleMicrotask(() {
      switch (data['type']) {
        case 'herdr_info':
          s.msg(<String, dynamic>{
            'kind': 'herdr_info',
            'id': id,
            'availability': availabilityJson(),
          });
        case 'herdr_workspaces':
          s.msg(<String, dynamic>{
            'kind': 'herdr_workspaces',
            'id': id,
            'workspaces': <Map<String, dynamic>>[workspaceJson()],
          });
        case 'herdr_agents':
          s.msg(<String, dynamic>{
            'kind': 'herdr_agents',
            'id': id,
            'agents': <Map<String, dynamic>>[],
          });
        case 'herdr_tabs':
          s.msg(<String, dynamic>{
            'kind': 'herdr_tabs',
            'id': id,
            'workspaceId': data['workspaceId'],
            'tabs': <Map<String, dynamic>>[
              tabJson(workspaceId: data['workspaceId'] as String),
            ],
          });
        case 'herdr_panes':
          s.msg(<String, dynamic>{
            'kind': 'herdr_panes',
            'id': id,
            'workspaceId': data['workspaceId'],
            'panes': _panes(),
          });
        case 'herdr_watch':
          s.msg(<String, dynamic>{
            'kind': 'herdr_watch_result',
            'id': id,
            'paneId': data['paneId'],
          });
        default:
          s.msg(<String, dynamic>{'kind': 'ack', 'id': id});
      }
    });
  };
  return socket;
}

/// Paired store, connected remote controller and (optionally) a Herdr controller.
class _Harness {
  _Harness(this.socket, this.remote, this.owner, this.store, this._herdr);

  final FakeSocket socket;
  final RemoteController remote;
  final TestControllerOwner owner;

  /// The store the controller was built with; `RemoteComputerPage` takes it so a
  /// test never reaches the private app directory.
  final RemoteStore store;

  final HerdrController? _herdr;

  HerdrController get herdr => _herdr!;

  /// Every `herdr_watch` pane id the desktop received, in order.
  ///
  /// A null entry is `herdr_watch(null)`: the client stopped streaming.
  List<String?> get watchFrames => <String?>[
    for (final r in socket.requests)
      if (r['type'] == 'herdr_watch') r['paneId'] as String?,
  ];

  List<Map<String, dynamic>> get sends => <Map<String, dynamic>>[
    for (final r in socket.requests)
      if (r['type'] == 'send') r,
  ];

  List<Map<String, dynamic>> get paneTexts => <Map<String, dynamic>>[
    for (final r in socket.requests)
      if (r['type'] == 'herdr_send_text') r,
  ];

  /// The live subscription id, or null when nothing is streamed.
  String? get watched => herdr.watchedPaneId;

  /// The remembered choice, which outlives the subscription.
  String? get remembered => herdr.preferredPaneId;

  /// Types of every request the app has put on the wire, in order.
  List<String> get requestTypes => <String>[
    for (final r in socket.requests) r['type'] as String,
  ];
}

Future<_Harness> _connect(
  WidgetTester tester, {
  bool withHerdr = true,
  bool start = true,
}) async {
  final store = RemoteStore.memory();
  await store.setPairing(
    const Pairing(
      relayUrl: 'wss://fixture/ws',
      agentId: 'fixture',
      secret: 'fixture',
      name: 'DESKTOP',
    ),
  );
  final socket = _agent();
  final remote = RemoteController(store: store, connector: (_) async => socket);
  final owner = TestControllerOwner(remote);
  final herdr = withHerdr ? HerdrController(remote) : null;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    herdr?.dispose();
    owner.dispose();
  });
  if (!start) return _Harness(socket, remote, owner, store, herdr);
  remote.connect();
  // The handshake and the first Herdr probe are microtask-driven.
  for (var i = 0; i < 30 && !remote.isOnline; i += 1) {
    await tester.pump();
  }
  expect(remote.isOnline, isTrue, reason: 'precondition: the link is up');
  if (herdr != null) {
    for (var i = 0; i < 30 && !herdr.canControl; i += 1) {
      await tester.pump();
    }
    expect(
      herdr.canControl,
      isTrue,
      reason: 'precondition: Herdr is controllable',
    );
    // Load the listing so `focusedPaneId` and the rows are populated.
    await herdr.refresh();
    await tester.pump();
  }
  return _Harness(socket, remote, owner, store, herdr);
}

/// A session card in the dashboard list.
///
/// The wide sidebar lists the same titles, so a bare `find.text` would match two
/// widgets; the card is only painted by the dashboard itself.
Finder _sessionCard(String title) => find.widgetWithText(SessionCard, title);

Future<void> _pumpDashboard(WidgetTester tester, RemoteController controller) =>
    pumpRemoteRoute(
      tester,
      _sessionCard('桌面终端'),
      ready: () =>
          controller.isOnline &&
          controller.session(_terminalSessionId) != null &&
          controller.session(_claudeSessionId) != null &&
          find.byType(SessionScreen, skipOffstage: false).evaluate().isEmpty,
    );

Future<void> _pumpSession(WidgetTester tester) => pumpRemoteRoute(
  tester,
  find.byType(SessionScreen, skipOffstage: false),
  ready: () =>
      tester.widget<SessionScreen>(find.byType(SessionScreen)).view.loaded,
);

Future<void> _pumpHost(WidgetTester tester) => pumpRemoteRoute(
  tester,
  find.text('Studio 主页'),
  ready: () =>
      find.byType(RemoteComputerPage, skipOffstage: false).evaluate().isEmpty,
);

void main() {
  // ---------------------------------------------------------------------------
  // R1: Claude structured sessions are never terminals
  // ---------------------------------------------------------------------------

  group('R1 Claude sessions are not terminals', () {
    testWidgets(
      'HomeScreen opens a Claude session without Herdr routing or a pane action',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // `HomeScreen` builds its own Herdr controller, so this test observes the
        // shared wire instead of a second controller.
        final h = await _connect(tester, withHerdr: false, start: false);
        await tester.pumpWidget(
          TestRemoteApp(store: h.store, controller: h.remote),
        );
        await _pumpDashboard(tester, h.remote);

        // --- the user watches a Herdr pane in the terminal session first, which
        // gives the module both an active focused pane and a remembered pane.
        await tester.tap(_sessionCard('桌面终端'));
        await _pumpSession(tester);
        expect(find.byType(SessionScreen), findsOneWidget);
        expect(find.byType(HerdrTerminalRows), findsOneWidget);
        expect(
          h.watchFrames.last,
          _paneA,
          reason: 'the terminal route follows the desktop focus',
        );

        // The user taps the other pane, as a chip tap does.
        await tester.tap(find.text('scratch'));
        await pumpRemoteUntil(
          tester,
          () => h.watchFrames.last == _paneB,
          reason: 'the selected pane receives the watch',
        );
        expect(
          h.watchFrames.last,
          _paneB,
          reason: 'the chip selection reached the desktop',
        );

        // Leaving the session stops its stream but keeps the choice.
        await tester.pageBack();
        await _pumpDashboard(tester, h.remote);
        expect(_sessionCard('Claude 会话'), findsOneWidget);
        expect(
          h.watchFrames.last,
          isNull,
          reason: 'nobody is watching that pane after the route closed',
        );

        final herdrBefore = h.requestTypes.where((t) => t.startsWith('herdr_'));

        // --- now open the Claude session. It must receive no Herdr controller.
        await tester.tap(_sessionCard('Claude 会话'));
        await _pumpSession(tester);
        expect(find.byType(SessionScreen), findsOneWidget);
        expect(
          find.byType(HerdrTerminalRows),
          findsNothing,
          reason: 'a Claude session has no Herdr rows',
        );
        expect(
          find.text('输入到面板，回车提交'),
          findsNothing,
          reason: 'a Claude composer must not offer a pane action',
        );
        final screen = tester.widget<SessionScreen>(find.byType(SessionScreen));
        expect(screen.view.info.isTerminal, isFalse);
        expect(
          screen.herdr,
          isNull,
          reason: 'the host boundary passes no Herdr controller to Claude',
        );

        await tester.enterText(find.byType(TextField), '只发给 Claude 的消息');
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await pumpRemoteUntil(
          tester,
          () => h.sends.length == 1,
          reason: 'the Claude send reaches the agent',
        );

        expect(h.sends, hasLength(1), reason: 'exactly one Claude send');
        expect(h.sends.single['sessionId'], _claudeSessionId);
        expect(h.sends.single['text'], '只发给 Claude 的消息');
        final herdrAfter = h.requestTypes.where(
          (t) =>
              t == 'herdr_send_text' ||
              t == 'herdr_send_keys' ||
              t == 'herdr_prompt',
        );
        expect(
          herdrAfter.length,
          herdrBefore.where(_isHerdrAction).length,
          reason: 'Claude text must never become a Herdr action',
        );
        expect(
          h.watchFrames.last,
          isNull,
          reason: 'opening a Claude route starts no watch',
        );
      },
    );

    testWidgets(
      'a directly built Claude SessionScreen ignores an injected Herdr controller',
      (tester) async {
        final h = await _connect(tester);

        // Stand-in for the terminal route that owns the live watch and the
        // remembered pane. The Claude screen must neither inherit nor clear it.
        final routeLease = h.herdr.claimPaneWatching();
        h.herdr.watchPane(routeLease, _paneB, explicit: true);
        await tester.pump();
        expect(h.watched, _paneB, reason: 'precondition: a pane is streaming');

        await tester.pumpWidget(
          MaterialApp(
            theme: remoteTestTheme(),
            home: SessionScreen(
              controller: h.remote,
              view: h.remote.view(SessionInfo.fromJson(_claudeSession())),
              // The unsafe injection this test exists for: a host that hands the
              // shared Herdr controller to every session kind.
              herdr: h.herdr,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HerdrTerminalRows), findsNothing);
        expect(find.text('输入到面板，回车提交'), findsNothing);
        expect(
          find.byTooltip('发送任务给该面板的 agent'),
          findsNothing,
          reason: 'no "send task to pane" affordance on a Claude session',
        );

        final requestsBefore = h.requestTypes.length;
        await tester.enterText(find.byType(TextField), '不要进终端');
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        expect(h.sends.single['sessionId'], _claudeSessionId);
        expect(h.sends.single['text'], '不要进终端');
        expect(
          h.paneTexts,
          isEmpty,
          reason: 'Claude text must not be typed into a desktop pane',
        );
        expect(
          h.requestTypes
              .skip(requestsBefore)
              .where((t) => t.startsWith('herdr_')),
          isEmpty,
          reason: 'the Claude screen performs no Herdr work at all',
        );
        expect(
          h.watched,
          _paneB,
          reason: 'an unrelated owner keeps its watch across the Claude screen',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // R2: route ownership of the live pane watch
  // ---------------------------------------------------------------------------

  group('R2 route ownership', () {
    /// A material route holding one pane-capable terminal screen.
    MaterialPageRoute<void> terminalRoute(_Harness h) =>
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            controller: h.remote,
            view: h.remote.view(SessionInfo.fromJson(_terminalSession())),
            herdr: h.herdr,
          ),
        );

    /// A material route holding a full-screen Herdr pane: its own lease and its
    /// own explicit pane selection after the first frame.
    MaterialPageRoute<void> paneRoute(_Harness h, String paneId) =>
        MaterialPageRoute<void>(
          builder: (_) => HerdrTerminalScreen(
            controller: h.remote,
            herdr: h.herdr,
            paneId: paneId,
          ),
        );

    testWidgets(
      'a same-pane replacement: the old route disposal cannot clear the new watch',
      (tester) async {
        final h = await _connect(tester);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('host')),
          ),
        );

        // Route A follows the desktop focus (pane A); the user then taps pane B,
        // so both the remembered choice and the live stream are pane B.
        nav.currentState!.push(terminalRoute(h));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final leaseA = h.herdr.activePaneLease!;
        h.herdr.watchPane(leaseA, _paneB, explicit: true);
        await tester.pumpAndSettle();
        expect(h.watched, _paneB);

        // Replace A with B in the same frame: the replacement claims ownership and
        // resumes the remembered pane B while A's reverse transition runs. A's
        // disposal must not send `herdr_watch(null)` afterwards.
        nav.currentState!.pop();
        nav.currentState!.push(terminalRoute(h));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final leaseB = h.herdr.activePaneLease!;
        expect(
          identical(leaseA, leaseB),
          isFalse,
          reason: 'a new route, a new lease',
        );
        expect(
          h.watched,
          _paneB,
          reason: 'B resumes the remembered pane before A is disposed',
        );

        // This is where A is actually disposed.
        await tester.pumpAndSettle();
        expect(
          h.watched,
          _paneB,
          reason: "the old route must not cancel the new route's watch",
        );
        expect(h.watchFrames.last, _paneB);
        expect(
          h.watchFrames.skipWhile((id) => id != _paneB),
          everyElement(_paneB),
          reason: 'no trailing herdr_watch(null) after B took over',
        );
        expect(
          find.byType(HerdrTerminal),
          findsOneWidget,
          reason: 'B still renders the pane, not a PTY fallback',
        );
        expect(
          tester.widget<HerdrTerminal>(find.byType(HerdrTerminal)).paneId,
          _paneB,
        );

        // The superseded lease is inert: it can neither move nor stop the watch.
        expect(
          h.herdr.watchPane(leaseA, _paneA, explicit: true),
          isFalse,
          reason: 'a stale route must not re-point the stream',
        );
        expect(h.watched, _paneB);
        expect(h.watchFrames.last, _paneB, reason: 'and no wire frame either');
      },
    );

    testWidgets('A to B to A keeps the watch with the newest route', (
      tester,
    ) async {
      final h = await _connect(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('host')),
        ),
      );

      // Route 1 watches pane A (the desktop focus); pane B is then remembered by a
      // chip tap, so the next route resumes B.
      nav.currentState!.push(terminalRoute(h));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.watched, _paneA);
      h.herdr.watchPane(h.herdr.activePaneLease!, _paneB, explicit: true);
      await tester.pumpAndSettle();

      // Route 2 watches pane B, then pane A becomes the remembered pane again:
      // the same id route 1 used, with a different owner.
      nav.currentState!.push(terminalRoute(h));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.watched, _paneB);
      h.herdr.watchPane(h.herdr.activePaneLease!, _paneA, explicit: true);
      await tester.pumpAndSettle();
      final leaseB = h.herdr.activePaneLease!;

      nav.currentState!.pop();
      nav.currentState!.push(terminalRoute(h));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final leaseA2 = h.herdr.activePaneLease!;
      expect(identical(leaseA2, leaseB), isFalse);
      expect(h.watched, _paneA, reason: 'route 3 resumes pane A');

      await tester.pumpAndSettle();
      expect(
        h.watched,
        _paneA,
        reason: 'the replaced route must not stop the watch on the reused id',
      );
      expect(h.watchFrames.last, _paneA);
      expect(
        h.herdr.watchPane(leaseB, _paneB, explicit: true),
        isFalse,
        reason: 'the replaced route cannot move the reused pane',
      );
      expect(h.watched, _paneA);
      expect(h.watchFrames.last, _paneA);
    });

    testWidgets('a stale deferred first watch is rejected', (tester) async {
      final h = await _connect(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('host')),
        ),
      );

      // Two pane routes pushed in one frame. Both `initState`s claim, so the second
      // supersedes the first *before* either deferred watch callback runs; the
      // first callback must then do nothing at all.
      nav.currentState!.push(paneRoute(h, _paneA));
      nav.currentState!.push(paneRoute(h, _paneB));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        h.watched,
        _paneB,
        reason: 'only the newer route may establish the initial watch',
      );
      expect(h.watchFrames, contains(_paneB));
      expect(
        h.watchFrames,
        isNot(contains(_paneA)),
        reason: 'the superseded route never asks the desktop for its pane',
      );
      expect(
        tester.widget<HerdrTerminal>(find.byType(HerdrTerminal)).paneId,
        _paneB,
      );
    });

    testWidgets('a Claude route opened over a terminal keeps the watch intact', (
      tester,
    ) async {
      final h = await _connect(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('host')),
        ),
      );

      nav.currentState!.push(terminalRoute(h));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      h.herdr.watchPane(h.herdr.activePaneLease!, _paneB, explicit: true);
      await tester.pumpAndSettle();
      expect(h.watched, _paneB);

      final before = h.watchFrames.length;
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            controller: h.remote,
            view: h.remote.view(SessionInfo.fromJson(_claudeSession())),
            // A host that injects the shared controller for every session kind.
            herdr: h.herdr,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(SessionScreen), findsOneWidget);
      expect(find.byType(HerdrTerminalRows), findsNothing);
      expect(
        h.watchFrames.skip(before),
        isEmpty,
        reason: 'opening Claude neither starts nor stops a pane stream',
      );
      expect(
        h.watched,
        _paneB,
        reason: 'the terminal route underneath still owns the watch',
      );
      expect(
        h.herdr.activePaneLease!.isActive,
        isTrue,
        reason: 'a Claude route claims no lease, so it cannot supersede one',
      );
    });

    testWidgets(
      'final owner disposal stops streaming but keeps the remembered pane',
      (tester) async {
        final h = await _connect(tester);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('host')),
          ),
        );

        nav.currentState!.push(terminalRoute(h));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        h.herdr.watchPane(h.herdr.activePaneLease!, _paneB, explicit: true);
        await tester.pumpAndSettle();
        expect(h.watched, _paneB);
        final lease = h.herdr.activePaneLease!;

        nav.currentState!.pop();
        await tester.pumpAndSettle();

        expect(
          h.watched,
          isNull,
          reason: 'nobody is looking at the pane anymore',
        );
        expect(
          h.watchFrames.last,
          isNull,
          reason: 'the desktop is told to stop',
        );
        expect(
          h.remembered,
          _paneB,
          reason: 'the choice outlives the route so the next visit resumes it',
        );
        expect(lease.isActive, isFalse);
        expect(
          h.watchFrames.where((id) => id == null).length,
          1,
          reason: 'one owner, one stop frame',
        );
        expect(
          h.herdr.watchPane(lease, _paneB),
          isFalse,
          reason: 'the released lease cannot restart the stream',
        );
        expect(h.watched, isNull);

        // Reopening resumes the remembered pane.
        nav.currentState!.push(terminalRoute(h));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(h.watched, _paneB);
        expect(
          tester.widget<HerdrTerminal>(find.byType(HerdrTerminal)).paneId,
          _paneB,
        );
      },
    );

    testWidgets('the pane rows act through their own route owner', (
      tester,
    ) async {
      final h = await _connect(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('host')),
        ),
      );

      // Route 1 selects pane B with a chip tap: the row is painted by route 1, so
      // its selection is accepted.
      nav.currentState!.push(terminalRoute(h));
      await tester.pump();
      await tester.pumpAndSettle();
      final rows = tester.widget<HerdrTerminalRows>(
        find.byType(HerdrTerminalRows),
      );
      expect(
        rows.lease,
        isNotNull,
        reason: 'the route passes its lease to the rows',
      );
      await tester.tap(find.text('scratch'));
      await tester.pumpAndSettle();
      expect(
        h.watched,
        _paneB,
        reason: 'the chip selection reached the desktop',
      );
      final oldLease = rows.lease!;

      // Replace the route. Route 2 owns the watch now.
      nav.currentState!.pop();
      nav.currentState!.push(terminalRoute(h));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final newRows = tester.widget<HerdrTerminalRows>(
        find.byType(HerdrTerminalRows).last,
      );
      expect(newRows.lease, h.herdr.activePaneLease);
      expect(identical(newRows.lease, oldLease), isFalse);

      await tester.pumpAndSettle();
      // The stale row's owner has no authority over the reused pane.
      expect(h.herdr.watchPane(oldLease, _paneA, explicit: true), isFalse);
      expect(h.watched, _paneB);
    });
  });

  // ---------------------------------------------------------------------------
  // R3: a visible return to Studio
  // ---------------------------------------------------------------------------

  group('R3 module exit', () {
    void setSize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// Pushes the module from the host home and waits for it to render.
    Future<void> open(
      WidgetTester tester, {
      required RemoteStore store,
      RemoteController? controller,
      VoidCallback? onExit,
    }) async {
      await tester.pumpWidget(
        TestRemoteHost(store: store, controller: controller, onExit: onExit),
      );
      await tester.pumpAndSettle();
      expect(find.text('Studio 主页'), findsOneWidget);
      await tester.tap(find.text('远程电脑'));
      if (controller != null && controller.pairing != null) {
        await _pumpDashboard(tester, controller);
      } else {
        await pumpRemoteRoute(tester, find.byType(PairScreen));
      }
      expect(find.byType(RemoteComputerPage), findsOneWidget);
    }

    for (final wide in <bool>[false, true]) {
      testWidgets(
        'paired, ${wide ? 'wide' : 'narrow'}: the visible exit returns to the host',
        (tester) async {
          setSize(tester, wide ? const Size(1280, 900) : const Size(430, 900));
          final h = await _connect(tester, withHerdr: false, start: false);
          await open(tester, store: h.store, controller: h.remote);

          expect(find.byType(HomeScreen), findsOneWidget);
          expect(
            find.byTooltip(moduleExitLabel),
            findsOneWidget,
            reason: 'the dashboard shows one visible exit control',
          );
          expect(
            find.text(moduleExitLabel),
            wide ? findsOneWidget : findsNothing,
            reason: wide
                ? 'the persistent sidebar repeats the action by name'
                : 'the closed drawer is not mounted',
          );

          await tester.tap(find.byTooltip(moduleExitLabel));
          await _pumpHost(tester);

          expect(find.text('Studio 主页'), findsOneWidget);
          expect(find.byType(RemoteComputerPage), findsNothing);
          expect(
            h.socket.requests.where((r) => r['type'] == 'close_session'),
            isEmpty,
            reason: 'leaving the module must not close a desktop session',
          );
          expect(
            h.socket.closed,
            isFalse,
            reason: 'the injected controller is caller-owned and stays open',
          );

          // The host still owns a live controller and can dispose it.
          expect(h.owner.disposed, isFalse);
          h.owner.dispose();
          expect(h.socket.closed, isTrue);
          expect(
            h.socket.requests.where((r) => r['type'] == 'close_session'),
            isEmpty,
          );
        },
      );

      testWidgets(
        'unpaired, ${wide ? 'wide' : 'narrow'}: the page-owned module also exits',
        (tester) async {
          setSize(tester, wide ? const Size(1280, 900) : const Size(430, 900));
          // No pairing: `connect()` returns immediately, so the page can own the
          // controller it builds without opening a socket in this test.
          final store = RemoteStore.memory();
          await open(tester, store: store);

          expect(find.text('连接你的电脑'), findsOneWidget);
          expect(
            find.byTooltip(moduleExitLabel),
            findsOneWidget,
            reason: 'the unpaired form shows the same visible exit',
          );
          expect(find.text(moduleExitLabel), findsOneWidget);

          final ownedController = tester
              .widget<PairScreen>(find.byType(PairScreen))
              .controller;
          var streamClosed = false;
          final notices = ownedController.codexNotices.listen(
            (_) {},
            onDone: () => streamClosed = true,
          );
          addTearDown(notices.cancel);

          await tester.tap(find.byTooltip(moduleExitLabel));
          await _pumpHost(tester);

          expect(find.text('Studio 主页'), findsOneWidget);
          expect(find.byType(RemoteComputerPage), findsNothing);
          expect(
            streamClosed,
            isTrue,
            reason: 'the owned controller is disposed',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('the drawer offers the exit in the narrow paired layout', (
      tester,
    ) async {
      setSize(tester, const Size(430, 900));
      final h = await _connect(tester, withHerdr: false, start: false);
      await open(tester, store: h.store, controller: h.remote);

      await tester.tap(find.byTooltip('工作空间'));
      await pumpRemoteUntil(
        tester,
        () =>
            find.byType(NavigationDrawer).evaluate().length == 1 &&
            tester.getTopLeft(find.byType(NavigationDrawer)).dx.abs() < 0.5,
        reason: 'the drawer has fully entered the viewport',
      );
      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(
        find.text(moduleExitLabel),
        findsOneWidget,
        reason: 'the open drawer carries its own exit entry',
      );

      await tester.tap(find.text(moduleExitLabel));
      await _pumpHost(tester);
      expect(find.text('Studio 主页'), findsOneWidget);
      expect(
        h.socket.requests.where((r) => r['type'] == 'close_session'),
        isEmpty,
      );
    });

    testWidgets('an injected exit callback replaces the default pop', (
      tester,
    ) async {
      setSize(tester, const Size(430, 900));
      final h = await _connect(tester, withHerdr: false, start: false);
      var exited = 0;
      await open(
        tester,
        store: h.store,
        controller: h.remote,
        onExit: () => exited += 1,
      );

      await tester.tap(find.byTooltip(moduleExitLabel));
      await _pumpDashboard(tester, h.remote);
      expect(exited, 1, reason: 'the host callback is authoritative');
      expect(
        find.byType(RemoteComputerPage),
        findsOneWidget,
        reason: 'the injected callback decides what happens, so nothing popped',
      );
    });

    testWidgets('internal back navigation still works inside the module', (
      tester,
    ) async {
      setSize(tester, const Size(1280, 900));
      final h = await _connect(tester, withHerdr: false, start: false);
      await open(tester, store: h.store, controller: h.remote);

      // The exit controls sit outside the inner navigator: a nested remote page
      // keeps its own back affordance, and leaving it lands on the dashboard.
      await tester.tap(_sessionCard('桌面终端'));
      await _pumpSession(tester);
      expect(find.byType(SessionScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byTooltip(moduleExitLabel),
        findsNothing,
        reason: 'the app bar belongs to the session route',
      );

      await tester.pageBack();
      await _pumpDashboard(tester, h.remote);
      expect(_sessionCard('桌面终端'), findsOneWidget);
      expect(find.byTooltip(moduleExitLabel), findsOneWidget);
      expect(
        h.socket.requests.where((r) => r['type'] == 'close_session'),
        isEmpty,
      );
    });
  });
}

/// Whether [type] is a Herdr action that writes to a pane.
bool _isHerdrAction(String type) =>
    type == 'herdr_send_text' ||
    type == 'herdr_send_keys' ||
    type == 'herdr_prompt';
