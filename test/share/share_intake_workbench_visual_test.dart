import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/share/share_inbox.dart';
import 'package:qfli_studio_core/share/share_intake_sheet.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';

void main() {
  final project = Project(
    id: 'p1',
    name: 'Example project',
    path: '/example',
    createdAt: DateTime(2026),
    lastOpenedAt: DateTime(2026),
  );
  final batch = ShareInboxBatch(
    id: 'visual-batch',
    files: const [
      SharedIncomingFile(
        path: '/inbox/main.dart',
        name: 'main.dart',
        bytes: 42,
      ),
    ],
    coldStart: false,
    source: 'share',
  );
  final session = AgentSessionMeta(
    id: 's1',
    projectId: 'p1',
    title: 'Existing session',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    messageCount: 1,
    preview: 'Continue',
  );

  Future<void> mount(
    WidgetTester tester, {
    required ValueChanged<ShareIntakeChoice?> onResult,
    bool workbench = true,
    Brightness brightness = Brightness.light,
    List<Project>? projects,
    ShareInboxBatch? incoming,
  }) async {
    final layout = LargeScreenController();
    addTearDown(layout.dispose);
    final launcher = Builder(
      builder: (context) => TextButton(
        onPressed: () async => onResult(
          await showShareIntakeSheet(
            context,
            batch: incoming ?? batch,
            projects: projects ?? [project],
            sessionsOf: (_) => [session],
          ),
        ),
        child: const Text('receive'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: workbench
              ? LargeScreenScope(controller: layout, child: launcher)
              : launcher,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.tap(find.text('receive'));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(1440, 900),
    const Size(1024, 768),
    const Size(1180, 820),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'share intake centered, bounded and usable: $size / $brightness',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ShareIntakeChoice? result;
          await mount(
            tester,
            brightness: brightness,
            onResult: (value) => result = value,
          );
          final dialog = find.byKey(const ValueKey('share-intake-dialog'));
          expect(dialog, findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          final surface = find
              .descendant(of: dialog, matching: find.byType(Material))
              .first;
          final rect = tester.getRect(surface);
          expect(rect.width, lessThanOrEqualTo(560));
          expect(rect.center.dx, closeTo(size.width / 2, 1));
          expect(rect.center.dy, closeTo(size.height / 2, 1));
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('share-intake-dialog-close')),
                )
                .height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(
            find.byKey(const ValueKey('share-intake-into-project')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('share-intake-project-p1')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('share-intake-back')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('share-intake-project-p1')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('share-intake-project-p1')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('share-intake-subdir-root')),
          );
          await tester.pumpAndSettle();
          expect(result, isA<ShareIntakeIntoProject>());
          final choice = result as ShareIntakeIntoProject;
          expect(choice.project, same(project));
          expect(choice.subdirectory, isEmpty);
          expect(dialog, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('workbench can attach to an existing session', (tester) async {
    ShareIntakeChoice? result;
    await mount(tester, onResult: (value) => result = value);
    await tester.tap(find.byKey(const ValueKey('share-intake-into-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-project-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-session-s1')));
    await tester.pumpAndSettle();
    expect((result as ShareIntakeIntoSession).sessionId, 's1');
  });

  testWidgets('workbench close cancels without choosing a destination', (
    tester,
  ) async {
    var completed = false;
    await mount(
      tester,
      onResult: (value) {
        completed = true;
        expect(value, isNull);
      },
    );
    await tester.tap(find.byKey(const ValueKey('share-intake-dialog-close')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'many shared files remain bounded and an empty registry is explained',
    (tester) async {
      final many = ShareInboxBatch(
        id: 'many',
        coldStart: false,
        source: 'share',
        files: [
          for (var i = 0; i < 20; i++)
            SharedIncomingFile(path: '/inbox/$i.txt', name: '$i.txt', bytes: 1),
        ],
      );
      await mount(tester, incoming: many, projects: [], onResult: (_) {});
      expect(find.text('另有 14 个文件'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-intake-into-project')));
      await tester.pumpAndSettle();
      expect(find.text('还没有项目。先建一个项目，再分享文件。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'share host navigator context finds the mounted workbench scope',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final layout = LargeScreenController();
      addTearDown(layout.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: LargeScreenScope(
            controller: layout,
            child: const Scaffold(body: Text('workbench')),
          ),
        ),
      );
      final pending = showShareIntakeSheet(
        navigatorKey.currentContext!,
        batch: batch,
        projects: [project],
        sessionsOf: (_) => [],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('share-intake-dialog')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byKey(const ValueKey('share-intake-dialog-close')));
      await tester.pumpAndSettle();
      expect(await pending, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('phone context retains bottom-sheet presentation and choices', (
    tester,
  ) async {
    ShareIntakeChoice? result;
    await mount(tester, workbench: false, onResult: (value) => result = value);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.byKey(const ValueKey('share-intake-dialog-close')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('share-intake-into-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-project-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-subdir-inbox')));
    await tester.pumpAndSettle();
    expect((result as ShareIntakeIntoProject).subdirectory, 'inbox');
  });
}
