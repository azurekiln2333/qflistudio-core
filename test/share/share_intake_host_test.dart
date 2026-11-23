import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/share/share_inbox.dart';
import 'package:qfli_studio_core/share/share_intake.dart';
import 'package:qfli_studio_core/share/share_intake_host.dart';

/// 只发事件的收件箱，不碰通道。
class _FakeInbox implements ShareInbox {
  final StreamController<ShareInboxBatch> controller =
      StreamController<ShareInboxBatch>.broadcast();
  final List<String> discarded = <String>[];
  int sweepCalls = 0;
  ShareInboxBatch? pendingOnStart;

  @override
  Stream<ShareInboxBatch> get incoming => controller.stream;

  @override
  Future<void> start() async {
    final pending = pendingOnStart;
    if (pending != null) controller.add(pending);
  }

  @override
  Future<void> discard(String batchId) async => discarded.add(batchId);

  @override
  Future<void> sweep() async => sweepCalls++;

  @override
  void dispose() {
    unawaited(controller.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final project = Project(
    id: 'p1',
    name: '示例项目',
    path: 'demo',
    createdAt: DateTime(2025, 1, 1),
    lastOpenedAt: DateTime(2025, 1, 1),
  );

  ShareInboxBatch batch(String id) => ShareInboxBatch(
    id: id,
    files: const <SharedIncomingFile>[
      SharedIncomingFile(path: '/tmp/a.txt', name: 'a.txt', bytes: 3),
    ],
    coldStart: false,
    source: 'send',
  );

  Future<
    ({
      _FakeInbox inbox,
      GlobalKey<NavigatorState> key,
      ValueNotifier<bool> ready,
    })
  >
  pumpApp(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('首页')),
      ),
    );
    await tester.pumpAndSettle();
    return (inbox: _FakeInbox(), key: key, ready: ready);
  }

  testWidgets('就绪后收到批次会弹面板，处理后删批次并清一次', (tester) async {
    final app = await pumpApp(tester);
    final copies = <String>[];
    final host = ShareIntakeHost(
      inbox: app.inbox,
      navigatorKey: app.key,
      projects: () => <Project>[project],
      sessionsOf: (_) => const [],
      ready: app.ready,
      onCopy: (batch, project, subdirectory) async {
        copies.add(subdirectory);
        return ShareIntakeResult(
          project: project,
          relativePaths: const <String>['inbox/a.txt'],
        );
      },
      onAttach: (batch, project, sessionId) async {},
    );
    addTearDown(host.dispose);
    await host.start();
    app.inbox.controller.add(batch('b1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('share-intake-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-intake-into-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-project-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-subdir-inbox')));
    await tester.pumpAndSettle();

    expect(copies, <String>['inbox']);
    expect(app.inbox.discarded, <String>['b1']);
    // 启动一次，处理完一批再来一次。
    expect(app.inbox.sweepCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('未就绪时先排队，就绪后再弹', (tester) async {
    final app = await pumpApp(tester);
    app.ready.value = false;
    final host = ShareIntakeHost(
      inbox: app.inbox,
      navigatorKey: app.key,
      projects: () => <Project>[project],
      sessionsOf: (_) => const [],
      ready: app.ready,
      onCopy: (batch, project, subdirectory) async =>
          ShareIntakeResult(project: project, relativePaths: const <String>[]),
      onAttach: (batch, project, sessionId) async {},
    );
    addTearDown(host.dispose);
    await host.start();
    app.inbox.controller.add(batch('b2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-intake-sheet')), findsNothing);

    app.ready.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-intake-sheet')), findsOneWidget);
  });

  testWidgets('取消后不删批次', (tester) async {
    final app = await pumpApp(tester);
    final host = ShareIntakeHost(
      inbox: app.inbox,
      navigatorKey: app.key,
      projects: () => <Project>[project],
      sessionsOf: (_) => const [],
      ready: app.ready,
      onCopy: (batch, project, subdirectory) async =>
          ShareIntakeResult(project: project, relativePaths: const <String>[]),
      onAttach: (batch, project, sessionId) async {},
    );
    addTearDown(host.dispose);
    await host.start();
    app.inbox.controller.add(batch('b3'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('share-intake-cancel')));
    await tester.pumpAndSettle();

    expect(app.inbox.discarded, isEmpty);
  });
}
