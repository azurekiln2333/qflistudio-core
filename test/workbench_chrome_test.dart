import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/shell/shortcut_label.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';
import 'package:qfli_studio_core/shell/workbench_theme.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  Size size = const Size(800, 600),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: StudioLocalizations.supportedLocales,
  theme: WorkbenchTheme.from(
    ThemeData(useMaterial3: true),
    formFactor: AppFormFactor.desktop,
  ),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  // R10/R21, V2: migrate separate Projects/Files and 52dp legacy assertions
  // to the single labeled 80dp MD3 Explorer destination (design §11.2).
  group('WorkbenchActivityRail MD3', () {
    testWidgets('four native destinations and two bottom controls dispatch', (
      tester,
    ) async {
      final tapped = <WorkbenchActivity>[];
      await _pump(
        tester,
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.explorer,
            onSelected: tapped.add,
            accountLabel: 'Ada',
          ),
        ),
      );
      for (final activity in [
        ...WorkbenchActivityRail.primary,
        ...WorkbenchActivityRail.secondary,
      ]) {
        await tester.tap(
          find.byKey(WorkbenchActivityRail.activityKey(activity)),
        );
        await tester.pump();
      }
      await tester.tap(
        find.byKey(
          WorkbenchActivityRail.activityKey(WorkbenchActivity.settings),
        ),
      );
      await tester.tap(find.byKey(WorkbenchActivityRail.avatarKey));
      expect(tapped, WorkbenchActivity.values);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(WorkbenchActivity.values, hasLength(6));
      expect(find.text('Explorer'), findsOneWidget);
      expect(find.text('Files'), findsNothing);
      expect(find.text('All projects'), findsNothing);
    });

    testWidgets(
      'selection follows the callback and repeating remains actionable',
      (tester) async {
        var selected = WorkbenchActivity.explorer;
        var calls = 0;
        await _pump(
          tester,
          _host(
            StatefulBuilder(
              builder: (context, setState) => WorkbenchActivityRail(
                selected: selected,
                onSelected: (value) => setState(() {
                  selected = value;
                  calls++;
                }),
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          0,
        );
        await tester.tap(
          find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.agents),
          ),
        );
        await tester.pumpAndSettle();
        expect(selected, WorkbenchActivity.agents);
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          1,
        );
        await tester.tap(
          find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.agents),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, 2);
        await tester.tap(
          find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.settings),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          isNull,
        );
      },
    );

    testWidgets('new destinations expose selection semantics and labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          _host(
            WorkbenchActivityRail(
              selected: WorkbenchActivity.explorer,
              onSelected: (_) {},
            ),
          ),
        );
        final context = tester.element(find.byType(NavigationRail));
        final l = StudioLocalizations.of(context);
        final material = MaterialLocalizations.of(context);
        final destinations = [
          (WorkbenchActivity.explorer, 'Explorer'),
          (WorkbenchActivity.agents, l.agentsTab),
          (WorkbenchActivity.tools, l.tools),
          (WorkbenchActivity.tutorial, l.tutorial),
        ];
        // R21/V2: native rail destinations expose tabs, not button semantics.
        for (var index = 0; index < destinations.length; index++) {
          final (activity, label) = destinations[index];
          final ordinal = material.tabLabel(
            tabIndex: index + 1,
            tabCount: destinations.length,
          );
          expect(
            tester.getSemantics(
              find.byKey(WorkbenchActivityRail.activityKey(activity)),
            ),
            isSemantics(
              label: '$label\n$ordinal',
              isButton: false,
              hasSelectedState: true,
              isSelected: activity == WorkbenchActivity.explorer,
              isFocusable: true,
              hasTapAction: true,
            ),
          );
        }
        for (final control in [
          WorkbenchActivityRail.activityKey(WorkbenchActivity.settings),
          WorkbenchActivityRail.avatarKey,
        ]) {
          expect(
            tester.getSemantics(find.byKey(control)),
            isSemantics(isButton: true, hasTapAction: true),
          );
        }
        expect(find.bySemanticsLabel('Files'), findsNothing);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      '80dp rail uses MD3 indicator, 24dp icons and shortcut tooltips',
      (tester) async {
        await _pump(
          tester,
          _host(
            WorkbenchActivityRail(
              selected: WorkbenchActivity.explorer,
              onSelected: (_) {},
            ),
          ),
        );
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(tester.getSize(find.byType(WorkbenchActivityRail)).width, 80);
        expect(rail.labelType, NavigationRailLabelType.all);
        expect(rail.useIndicator, isTrue);
        expect(rail.indicatorShape, isA<StadiumBorder>());
        final context = tester.element(find.byType(NavigationRail));
        expect(
          rail.indicatorColor,
          Theme.of(context).colorScheme.secondaryContainer,
        );
        for (final destination in rail.destinations) {
          final icon = (destination.icon as MouseRegion).child! as Tooltip;
          expect((icon.child! as Icon).size, 24);
        }
        expect(
          find.byTooltip('Explorer (${shortcutLabel('Ctrl+Shift+E')})'),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Agents (${shortcutLabel('Ctrl+Shift+A')})'),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(WorkbenchActivityRail.avatarKey)).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .getSize(
                find.byKey(
                  WorkbenchActivityRail.activityKey(WorkbenchActivity.settings),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
      },
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'short rail scrolls and keeps bottom avatar reachable at $scale text',
        (tester) async {
          final tapped = <WorkbenchActivity>[];
          await _pump(
            tester,
            _host(
              WorkbenchActivityRail(
                selected: WorkbenchActivity.explorer,
                onSelected: tapped.add,
              ),
              size: const Size(400, 240),
              textScale: scale,
            ),
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(WorkbenchActivityRail)).width, 80);
          await tester.tap(find.byKey(WorkbenchActivityRail.avatarKey));
          expect(tapped, [WorkbenchActivity.profile]);
        },
      );
    }

    testWidgets('avatar retains initial and missing-account fallback', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.profile,
            onSelected: (_) {},
            accountLabel: 'ada',
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      await _pump(
        tester,
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.profile,
            onSelected: (_) {},
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(WorkbenchActivityRail.avatarKey),
          matching: find.byIcon(Icons.person_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Chinese label is Explorer rather than the removed Files item',
      (tester) async {
        await _pump(
          tester,
          _host(
            WorkbenchActivityRail(
              selected: WorkbenchActivity.explorer,
              onSelected: (_) {},
            ),
            locale: const Locale('zh', 'CN'),
          ),
        );
        expect(find.text('资源管理器'), findsOneWidget);
        expect(find.text('文件'), findsNothing);
      },
    );
  });

  // R21/V9: replace one empty-state button with Start and Recent projects.
  group('WorkbenchWelcome', () {
    testWidgets('start actions dispatch and show platform shortcuts', (
      tester,
    ) async {
      var opens = 0;
      var creates = 0;
      var clones = 0;
      await _pump(
        tester,
        _host(
          WorkbenchWelcome(
            onOpenProject: () => opens++,
            onCreateProject: () => creates++,
            onCloneRepository: () => clones++,
          ),
        ),
      );
      await tester.tap(
        find.byTooltip('Add existing project (${shortcutLabel('Ctrl+O')})'),
      );
      await tester.tap(
        find.byTooltip('New project (${shortcutLabel('Ctrl+Shift+N')})'),
      );
      await tester.tap(
        find.byTooltip('Clone repository (${shortcutLabel('Ctrl+Shift+G')})'),
      );
      expect((opens, creates, clones), (1, 1, 1));
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Recent projects'), findsOneWidget);
    });

    testWidgets(
      'recent projects are ordered and dispatch their project identity',
      (tester) async {
        final earlier = Project.create(name: 'Earlier', path: '/earlier')
          ..lastOpenedAt = DateTime(2025);
        final latest = Project.create(name: 'Latest', path: '/latest')
          ..lastOpenedAt = DateTime(2026);
        Project? opened;
        await _pump(
          tester,
          _host(
            WorkbenchWelcome(
              onOpenProject: () {},
              projects: [earlier, latest],
              onOpenRecent: (value) => opened = value,
            ),
          ),
        );
        expect(
          tester.getTopLeft(find.text('Latest')).dy,
          lessThan(tester.getTopLeft(find.text('Earlier')).dy),
        );
        await tester.tap(find.text('Latest'));
        expect(opened, same(latest));
        expect(find.byType(Card), findsNothing);
        expect(find.byType(DataTable), findsNothing);
      },
    );

    testWidgets('narrow short welcome scrolls without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(
          WorkbenchWelcome(onOpenProject: () {}),
          size: const Size(200, 180),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
