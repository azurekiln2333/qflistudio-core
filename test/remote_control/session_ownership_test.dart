// Cloud-only regressions for overlapping PTY and Claude route subscriptions.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/remote_control/pages/session_screen.dart';
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart';
import 'package:qfli_studio_core/remote_control/state/remote_store.dart';
import 'package:qfli_studio_core/remote_control/state/session_view.dart';

import '../support/fake_relay.dart';
import '../support/remote_control_app.dart';

class _Agent {
  _Agent(String kind) {
    socket = healthyAgent(
      sessions: <Map<String, dynamic>>[
        sessionJson('a', kind: kind, status: 'running'),
        sessionJson('b', kind: kind, status: 'running'),
      ],
    );
    final respond = socket.onSend!;
    socket.onSend = (wire, frame) {
      final data = frame['data'];
      if (data is Map<String, dynamic>) {
        final id = data['sessionId'];
        if (data['type'] == 'subscribe') {
          if (holdSubscriptions) {
            held.add(data);
            return;
          }
          subscribed.add(id as String);
        } else if (data['type'] == 'unsubscribe') {
          subscribed.remove(id);
        }
      }
      respond(wire, frame);
    };
  }

  late final FakeSocket socket;
  final Set<String> subscribed = <String>{};
  final List<Map<String, dynamic>> held = <Map<String, dynamic>>[];
  bool holdSubscriptions = false;

  List<Map<String, dynamic>> requests(String type) =>
      socket.requests.where((request) => request['type'] == type).toList();

  void output(String id, String kind, int seq, String text) {
    // Model the agent's actual subscription gate: an erroneous unsubscribe
    // prevents output delivery, instead of letting the fixture hide the bug.
    if (!subscribed.contains(id)) return;
    socket.msg(<String, dynamic>{
      'kind': 'event',
      'sessionId': id,
      'event': <String, dynamic>{
        'kind': kind == 'terminal' ? 'terminal_output' : 'assistant',
        if (kind == 'terminal') 'data': text else 'text': text,
        'seq': seq,
        'ts': seq,
      },
    });
  }
}

Future<RemoteController> _connect(
  WidgetTester tester,
  List<_Agent> agents,
) async {
  final store = RemoteStore.memory();
  await store.setPairing(
    const Pairing(
      relayUrl: 'wss://fixture/ws',
      agentId: 'fixture',
      secret: 'fixture',
    ),
  );
  var next = 0;
  final controller = RemoteController(
    store: store,
    connector: (_) async => agents[next++].socket,
  );
  final owner = TestControllerOwner(controller);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    owner.dispose();
  });
  controller.connect();
  await tester.pump();
  await tester.pump();
  expect(controller.session('a'), isNotNull);
  return controller;
}

void _expectOutput(SessionView view, String kind, String text) {
  if (kind == 'terminal') {
    expect(view.terminal.buffer.getText(), contains(text));
  } else {
    expect(
      view.events.whereType<AssistantEvent>().map((event) => event.text),
      contains(text),
    );
  }
}

void main() {
  for (final kind in <String>['terminal', 'claude']) {
    testWidgets('$kind replacement retains streaming and replay ownership', (
      tester,
    ) async {
      final first = _Agent(kind);
      final second = _Agent(kind);
      final third = _Agent(kind);
      final controller = await _connect(tester, <_Agent>[first, second, third]);
      final view = controller.view(controller.session('a')!);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: remoteTestTheme(),
          home: const Scaffold(body: Text('host')),
        ),
      );
      MaterialPageRoute<void> route() => MaterialPageRoute<void>(
        builder: (_) => SessionScreen(controller: controller, view: view),
      );
      unawaited(navigator.currentState!.push(route()));
      await tester.pumpAndSettle();
      first.output('a', kind, 1, 'first');
      await tester.pump();
      expect(view.lastSeq, 1);

      navigator.currentState!.pop();
      unawaited(navigator.currentState!.push(route()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(SessionScreen, skipOffstage: false), findsNWidgets(2));
      expect(first.requests('subscribe'), hasLength(1));
      expect(first.requests('unsubscribe'), isEmpty);

      // Reconnect while both routes exist. Only one subscription is restored.
      controller.connect();
      await tester.pump();
      expect(second.requests('subscribe'), hasLength(1));
      expect(second.requests('subscribe').single['afterSeq'], 1);
      await tester.pumpAndSettle();
      expect(find.byType(SessionScreen), findsOneWidget);
      expect(second.requests('unsubscribe'), isEmpty);
      second.output('a', kind, 1, 'duplicate');
      second.output('a', kind, 2, 'survived');
      await tester.pumpAndSettle();
      expect(view.lastSeq, 2);
      _expectOutput(view, kind, 'survived');
      if (kind == 'terminal') {
        expect(view.terminal.buffer.getText(), isNot(contains('duplicate')));
        view.terminal.textInput('typed after replacement');
        await tester.pump();
        expect(
          second.requests('terminal_input').last['data'],
          'typed after replacement',
        );
        expect(view.terminal.onResize, isNotNull);
      } else {
        expect(view.events.whereType<AssistantEvent>(), hasLength(2));
      }

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(second.requests('unsubscribe'), hasLength(1));
      controller.connect();
      await tester.pump();
      expect(third.requests('subscribe'), isEmpty);
      expect(
        <_Agent>[
          first,
          second,
          third,
        ].expand((a) => a.requests('close_session')),
        isEmpty,
      );
    });
  }

  testWidgets('A to B to A releases only the obsolete route owners', (
    tester,
  ) async {
    final agent = _Agent('claude');
    final controller = await _connect(tester, <_Agent>[agent]);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: remoteTestTheme(),
        home: const Scaffold(body: Text('host')),
      ),
    );
    void push(String id) => unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            controller: controller,
            view: controller.view(controller.session(id)!),
          ),
        ),
      ),
    );
    push('a');
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    push('b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    navigator.currentState!.pop();
    push('a');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(agent.subscribed, <String>{'a'});
    expect(agent.requests('unsubscribe').map((r) => r['sessionId']), <String>[
      'b',
    ]);
    agent.output('a', 'claude', 1, 'returned');
    await tester.pumpAndSettle();
    expect(find.text('returned'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(agent.requests('unsubscribe').map((r) => r['sessionId']), <String>[
      'b',
      'a',
    ]);
  });

  testWidgets('pending failure cannot remove a replacement ownership group', (
    tester,
  ) async {
    final agent = _Agent('claude');
    final controller = await _connect(tester, <_Agent>[agent]);
    final oldOwner = Object();
    final newOwner = Object();
    agent.holdSubscriptions = true;
    final oldRequest = controller.subscribe('a', owner: oldOwner);
    final oldFailure = expectLater(oldRequest, throwsA(isA<RemoteException>()));
    controller.unsubscribe('a', owner: oldOwner);
    controller.unsubscribe('a', owner: oldOwner);
    agent.holdSubscriptions = false;
    await controller.subscribe('a', owner: newOwner);
    agent.socket.msg(<String, dynamic>{
      'kind': 'error',
      'id': agent.held.single['id'],
      'message': 'old request failed',
    });
    await tester.pump();
    await oldFailure;
    expect(agent.requests('unsubscribe'), hasLength(1));
    expect(agent.subscribed, <String>{'a'});
    await controller.subscribe('a', owner: newOwner);
    expect(
      agent.requests('subscribe'),
      hasLength(2),
      reason: 'the old failure did not remove the new request',
    );
    controller.unsubscribe('a', owner: newOwner);
    controller.unsubscribe('a', owner: newOwner);
    await tester.pump();
    expect(agent.requests('unsubscribe'), hasLength(2));
    expect(agent.subscribed, isEmpty);
  });

  testWidgets('overlapping owners share subscription failure and can retry', (
    tester,
  ) async {
    final agent = _Agent('claude');
    final controller = await _connect(tester, <_Agent>[agent]);
    final firstOwner = Object();
    final secondOwner = Object();
    agent.holdSubscriptions = true;
    final first = expectLater(
      controller.subscribe('a', owner: firstOwner),
      throwsA(isA<RemoteException>()),
    );
    final second = expectLater(
      controller.subscribe('a', owner: secondOwner),
      throwsA(isA<RemoteException>()),
    );
    expect(agent.held, hasLength(1));
    agent.socket.msg(<String, dynamic>{
      'kind': 'error',
      'id': agent.held.single['id'],
      'message': 'retry required',
    });
    await tester.pump();
    await Future.wait(<Future<void>>[first, second]);
    agent.holdSubscriptions = false;
    await controller.subscribe('a', owner: secondOwner);
    controller.unsubscribe('a', owner: firstOwner);
    await tester.pump();
    expect(agent.requests('unsubscribe'), isEmpty);
    expect(agent.subscribed, <String>{'a'});
    controller.unsubscribe('a', owner: secondOwner);
    await tester.pump();
    expect(agent.requests('unsubscribe'), hasLength(1));
  });
}
