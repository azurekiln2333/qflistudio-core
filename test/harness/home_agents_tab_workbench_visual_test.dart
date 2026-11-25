@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/hub/agents_snapshot.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/home_agents_tab.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import '../support/fake_harness_host.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required Brightness brightness,
    bool workbench = true,
    void Function(AgentsIndexRow)? onOpen,
    void Function(AgentsIndexRow)? onDetails,
  }) async {
    final root = Directory.systemTemp.createTempSync('agents-visual-');
    final auth = AuthStore();
    final projects = ProjectStore();
    final settings = SettingsStore();
    final layout = LargeScreenController();
    final hosts = [
      FakeHarnessHost(
        id: 'local',
        label: 'Local computer',
        kind: HarnessHostKind.local,
        initialSessions: [
          fakeSession(
            hostId: 'local',
            id: 'a',
            title: 'Local task',
            cwd: '/alpha',
          ),
        ],
      ),
      FakeHarnessHost(
        id: 'remote',
        label: 'Remote computer',
        kind: HarnessHostKind.remote,
        initialSessions: [
          fakeSession(
            hostId: 'remote',
            id: 'b',
            title: 'Remote task',
            cwd: '/beta',
          ),
        ],
      ),
    ];
    final hub = HarnessHub(hosts: hosts, desktop: AppPaths.isDesktop);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await hub.shutdown();
      layout.dispose();
      settings.dispose();
      projects.dispose();
      auth.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final key = GlobalKey<HomeAgentsTabState>();
    final tab = HomeAgentsTab(
      key: key,
      auth: auth,
      store: projects,
      settings: settings,
      harnessHub: hub,
      remoteHostOpener: () async => null,
      sessionRoot: root,
      snapshotStore: AgentsSnapshotStore(backend: LocalMemoryBackend()),
      onOpenSession: onOpen ?? (_) {},
      onOpenDetails: onDetails ?? (_) {},
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: brightness,
            ),
            visualDensity: AppPaths.isDesktop
                ? VisualDensity.compact
                : VisualDensity.standard,
            materialTapTargetSize: AppPaths.isDesktop
                ? MaterialTapTargetSize.shrinkWrap
                : MaterialTapTargetSize.padded,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: workbench
                    ? LargeScreenScope(controller: layout, child: tab)
                    : tab,
              ),
            ),
          ),
        ),
      );
      final watch = Stopwatch()..start();
      while ((key.currentState?.rows.length ?? 0) != 2 &&
          watch.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await tester.pump();
      }
      // Complete real directory IO too, not only the hub's initial event.
      await key.currentState!.refresh();
      await tester.pump();
    });
    await tester.pump(const Duration(seconds: 3));
  }

  for (final size in [const Size(1440, 900), const Size(1024, 768)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'workbench Agents geometry, search and roles: $size $brightness',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AgentsIndexRow? opened;
          AgentsIndexRow? detailed;
          await mount(
            tester,
            brightness: brightness,
            onOpen: (row) => opened = row,
            onDetails: (row) => detailed = row,
          );

          final header = find.byKey(const ValueKey('agents-workbench-header'));
          final row = find.byKey(const ValueKey('agents-row-local:a'));
          expect(tester.getSize(header).height, AppPaths.isDesktop ? 40 : 48);
          expect(tester.getSize(row).height, AppPaths.isDesktop ? 32 : 48);
          expect(
            find.byKey(const ValueKey('agents-host-local')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('agents-host-remote')),
            findsOneWidget,
          );
          final context = tester.element(header);
          final scheme = Theme.of(context).colorScheme;
          expect(
            tester
                .widget<Material>(
                  find.byKey(const ValueKey('agents-workbench-panel')),
                )
                .color,
            scheme.surfaceContainerLow,
          );
          final search = tester.widget<TextField>(
            find.byKey(const ValueKey('agents-workbench-search')),
          );
          expect(search.decoration!.fillColor, scheme.surfaceContainerHigh);
          final ink = tester.widget<InkWell>(row);
          expect(ink.mouseCursor, SystemMouseCursors.click);
          expect(
            ink.overlayColor!.resolve({WidgetState.hovered}),
            scheme.onSurface.withValues(alpha: 0.08),
          );
          expect(
            ink.overlayColor!.resolve({WidgetState.pressed}),
            scheme.onSurface.withValues(alpha: 0.10),
          );
          expect(
            ink.overlayColor!.resolve({WidgetState.focused}),
            scheme.onSurface.withValues(alpha: 0.10),
          );

          await tester.tap(find.text('Local task'));
          expect(opened?.session.id, 'a');
          await tester.tap(
            find.byKey(const ValueKey('agents-details-local:a')),
          );
          expect(detailed?.session.id, 'a');
          await tester.enterText(find.byType(TextField), 'Remote');
          await tester.pump();
          expect(find.text('Local task'), findsNothing);
          expect(find.text('Remote task'), findsOneWidget);
          expect(find.byKey(const ValueKey('agents-host-local')), findsNothing);
          await tester.enterText(find.byType(TextField), 'beta');
          await tester.pump();
          expect(
            find.text('Remote task'),
            findsOneWidget,
            reason: 'Paths are searchable too.',
          );
          await tester.enterText(find.byType(TextField), 'no-such-session');
          await tester.pump();
          expect(find.text('没有匹配的会话'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('agents-workbench-search')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('agents-workbench-refresh')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'without workbench scope the phone list keeps its original presentation',
    (tester) async {
      await mount(tester, brightness: Brightness.light, workbench: false);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('agents-workbench-header')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('agents-row-local:a'))).height,
        greaterThan(48),
      );
      expect(find.textContaining('alpha'), findsOneWidget);
    },
  );
}
