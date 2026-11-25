import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/tools/tool_state_store.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart';
import 'package:qfli_studio_core/widgets/tools_browser.dart';

void main() {
  testWidgets(
    'R22/V10 store setup completes compact two-column writes',
    (tester) async {
      final fixture = _ToolsBrowserFixture();
      try {
        await fixture.initialize();
        await fixture.store.settled();
        expect(fixture.store.density, ToolCardDensity.compact);
        expect(fixture.store.cardColumns, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final width in [1200.0, 950.0, 620.0]) {
    testWidgets(
      'R22/V10 workbench at $width reflows cards without changing phone preferences',
      (tester) async {
        final fixture = _ToolsBrowserFixture();
        try {
          await fixture.initialize();
          await fixture.mount(tester, 1200, workbench: true);
          if (width != 1200) {
            await fixture.mount(tester, width, workbench: true);
          }
          final first = tester.getRect(find.widgetWithText(ToolCard, 'Tool 0'));
          final second = tester.getRect(
            find.widgetWithText(ToolCard, 'Tool 1'),
          );
          expect(first.width, greaterThanOrEqualTo(280));
          if (width >= 640) {
            expect(second.top, closeTo(first.top, 0.1));
            expect(second.left - first.right, closeTo(16, 0.1));
          } else {
            expect(second.left, closeTo(first.left, 0.1));
            expect(second.top - first.bottom, closeTo(16, 0.1));
          }
          expect(find.byType(SegmentedButton<ToolCardDensity>), findsNothing);
          expect(fixture.store.density, ToolCardDensity.compact);
          expect(fixture.store.cardColumns, 2);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  testWidgets(
    'R22/V10 phone at 420 restores rows and preference controls after workbench',
    (tester) async {
      final fixture = _ToolsBrowserFixture();
      try {
        await fixture.initialize();
        await fixture.mount(tester, 620, workbench: true);
        await fixture.mount(tester, 420, workbench: false);
        expect(find.byType(ToolRow), findsWidgets);
        expect(find.byType(ToolCard), findsNothing);
        expect(find.byType(SegmentedButton<ToolCardDensity>), findsOneWidget);
        expect(fixture.store.density, ToolCardDensity.compact);
        expect(fixture.store.cardColumns, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'R22/V10 phone density change retains the saved two-column grid',
    (tester) async {
      final fixture = _ToolsBrowserFixture();
      try {
        await fixture.initialize();
        await fixture.mount(tester, 420, workbench: false);
        expect(find.byType(ToolRow), findsWidgets);
        expect(find.byType(ToolCard), findsNothing);
        expect(find.byType(SegmentedButton<ToolCardDensity>), findsOneWidget);
        await fixture.store.setDensity(ToolCardDensity.standard);
        await tester.pump();
        final grid = tester.widget<SliverGrid>(find.byType(SliverGrid).first);
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          2,
        );
        expect(fixture.store.density, ToolCardDensity.standard);
        expect(fixture.store.cardColumns, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _ToolsBrowserFixture {
  final store = ToolStateStore(backend: LocalMemoryBackend());
  final shell = LargeScreenController();

  Future<void> initialize() async {
    await store.setDensity(ToolCardDensity.compact);
    await store.setCardColumns(2);
  }

  Widget _browser() => ToolsBrowser(
    state: store,
    isMainApp: false,
    sections: [
      ToolsBrowserSection(
        title: 'Grid fixtures',
        icon: Icons.build,
        entries: [
          for (var i = 0; i < 6; i++)
            ToolsBrowserEntry(
              id: 'fixture-$i',
              icon: Icons.code,
              title: 'Tool $i',
              subtitle: 'Fixture',
              description: 'Offline fixture',
              onTap: () {},
            ),
        ],
      ),
    ],
  );

  Future<void> mount(
    WidgetTester tester,
    double width, {
    required bool workbench,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: workbench
              ? LargeScreenScope(controller: shell, child: _browser())
              : _browser(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      // Keep this await inside testWidgets' fake-async zone. In addTearDown,
      // the completed write future queues its listener in a zone no longer pumped.
      await store.settled();
    } finally {
      store.dispose();
      shell.dispose();
      tester.view.reset();
    }
  }
}
