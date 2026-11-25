import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
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
  Brightness brightness = Brightness.light,
  AppFormFactor formFactor = AppFormFactor.desktop,
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
    ThemeData(useMaterial3: true, brightness: brightness),
    formFactor: formFactor,
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

    for (final brightness in Brightness.values) {
      for (final factor in [AppFormFactor.desktop, AppFormFactor.tablet]) {
        testWidgets('$brightness $factor bottom feedback stays in capsules', (
          tester,
        ) async {
          final calls = <WorkbenchActivity>[];
          await _pump(
            tester,
            _host(
              WorkbenchActivityRail(
                selected: WorkbenchActivity.settings,
                onSelected: calls.add,
              ),
              brightness: brightness,
              formFactor: factor,
            ),
          );
          final scheme = Theme.of(
            tester.element(find.byType(WorkbenchActivityRail)),
          ).colorScheme;
          final settings = find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.settings),
          );
          final avatar = find.byKey(WorkbenchActivityRail.avatarKey);
          Finder capsule(Finder control) => find.descendant(
            of: control,
            matching: find.byKey(const ValueKey('workbench-rail-capsule')),
          );
          Finder layer(Finder control) => find.descendant(
            of: control,
            matching: find.byKey(const ValueKey('workbench-rail-state-layer')),
          );
          ShapeDecoration state(Finder control) =>
              tester.widget<DecoratedBox>(layer(control)).decoration
                  as ShapeDecoration;
          for (final control in [settings, avatar]) {
            expect(tester.getSize(control), const Size(80, 48));
            expect(tester.getSize(capsule(control)), const Size(56, 32));
            expect(tester.getSize(layer(control)), const Size(56, 32));
            final button = tester.widget<TextButton>(
              find.descendant(of: control, matching: find.byType(TextButton)),
            );
            for (final states in [
              <WidgetState>{},
              {WidgetState.hovered},
              {WidgetState.focused},
              {WidgetState.pressed},
            ]) {
              expect(
                button.style!.overlayColor!.resolve(states),
                Colors.transparent,
              );
              expect(
                button.style!.backgroundColor!.resolve(states),
                Colors.transparent,
              );
              expect(button.style!.side!.resolve(states), BorderSide.none);
            }
          }
          final selected = tester.widget<AnimatedContainer>(capsule(settings));
          final decoration = selected.decoration! as ShapeDecoration;
          expect(decoration.color, scheme.secondaryContainer);
          expect(decoration.shape, isA<StadiumBorder>());
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          try {
            await mouse.moveTo(tester.getCenter(settings));
            await tester.pumpAndSettle();
            expect(
              state(settings).color,
              scheme.onSurface.withValues(alpha: 0.08),
            );
            expect(tester.getSize(layer(settings)), const Size(56, 32));
            await mouse.moveTo(Offset.zero);
            await tester.pumpAndSettle();
            final press = await tester.startGesture(tester.getCenter(avatar));
            await tester.pump();
            expect(
              state(avatar).color,
              scheme.onSurface.withValues(alpha: 0.10),
            );
            expect(tester.getSize(layer(avatar)), const Size(56, 32));
            await press.cancel();
            await tester.pumpAndSettle();
            final ink = find.descendant(
              of: settings,
              matching: find.byType(InkWell),
            );
            Focus.of(
              tester.element(
                find
                    .descendant(of: ink, matching: find.byType(MouseRegion))
                    .first,
              ),
            ).requestFocus();
            tester.binding.focusManager.applyFocusChangesIfNeeded();
            await tester.pumpAndSettle();
            expect(
              state(settings).color,
              scheme.onSurface.withValues(alpha: 0.10),
            );
            expect(
              (state(settings).shape as StadiumBorder).side.color,
              scheme.primary,
            );
            expect(
              find.byKey(const ValueKey('workbench-focus-outline')),
              findsNothing,
              reason: 'Bottom rail focus must not outline the whole 80dp row.',
            );
            // The visual capsule is small, but tablet-sized outer padding is
            // still actionable and keyboard activation keeps working.
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.tapAt(tester.getTopLeft(avatar) + const Offset(2, 2));
            await tester.pumpAndSettle();
            expect(calls, [
              WorkbenchActivity.settings,
              WorkbenchActivity.profile,
            ]);
          } finally {
            await mouse.removePointer();
          }
          await _pump(
            tester,
            _host(
              WorkbenchActivityRail(
                selected: WorkbenchActivity.profile,
                onSelected: calls.add,
              ),
              brightness: brightness,
              formFactor: factor,
            ),
          );
          final profileDecoration =
              tester.widget<AnimatedContainer>(capsule(avatar)).decoration!
                  as ShapeDecoration;
          expect(profileDecoration.color, scheme.secondaryContainer);
          expect(profileDecoration.shape, isA<StadiumBorder>());
          expect(tester.getSize(capsule(avatar)), const Size(56, 32));
          expect(tester.takeException(), isNull);
        });
      }
    }

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

  // R5/V9, round 4: Explorer owns all project actions. The center is a
  // read-only reminder, not a duplicate set of buttons or focus targets.
  group('WorkbenchShortcutHints', () {
    for (final brightness in Brightness.values) {
      for (final factor in [AppFormFactor.desktop, AppFormFactor.tablet]) {
        testWidgets(
          '$brightness $factor hints are muted, aligned and passive',
          (tester) async {
            await _pump(
              tester,
              _host(
                const WorkbenchShortcutHints(),
                brightness: brightness,
                formFactor: factor,
              ),
            );
            final hints = find.byType(WorkbenchShortcutHints);
            final context = tester.element(hints);
            final theme = Theme.of(context);
            final table = find.byKey(
              const ValueKey('workbench-shortcut-hints'),
            );
            final labels = [
              'New project',
              'Open folder',
              'Clone repository',
              'Explorer',
              'Agents',
              'Settings',
              'Interface zoom',
            ];
            final keys = [
              'Ctrl+Shift+N',
              'Ctrl+O',
              'Ctrl+Shift+G',
              'Ctrl+Shift+E',
              'Ctrl+Shift+A',
              'Ctrl+,',
              'Ctrl+= / Ctrl+-',
            ];
            expect(tester.widget<Table>(table).children, hasLength(7));
            for (var index = 0; index < labels.length; index++) {
              expect(find.text(labels[index]), findsOneWidget);
              final key = find.text(shortcutLabel(keys[index]));
              expect(key, findsOneWidget);
              expect(
                tester.getTopLeft(key).dx,
                closeTo(
                  tester.getTopLeft(find.text(shortcutLabel(keys.first))).dx,
                  0.01,
                ),
              );
              expect(
                DefaultTextStyle.of(tester.element(key)).style.color,
                theme.colorScheme.onSurfaceVariant,
              );
            }
            expect(
              find.descendant(of: hints, matching: find.byType(TextButton)),
              findsNothing,
            );
            expect(
              find.descendant(of: hints, matching: find.byType(IconButton)),
              findsNothing,
            );
            expect(
              find.descendant(of: hints, matching: find.byType(InkWell)),
              findsNothing,
            );
            // A scroll view may expose scrolling gestures, but none of its
            // hint text may acquire a command/tap semantics action.
            final semantics = tester.ensureSemantics();
            try {
              await tester.pump();
              for (final label in labels) {
                expect(
                  tester
                      .getSemantics(find.text(label))
                      .getSemanticsData()
                      .hasAction(SemanticsAction.tap),
                  isFalse,
                );
              }
            } finally {
              semantics.dispose();
            }
            final focus = Focus.of(context);
            expect(focus.traversalDescendants, isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'Chinese hints localize and offline mode hides unavailable clone',
      (tester) async {
        await _pump(
          tester,
          _host(
            const WorkbenchShortcutHints(includeClone: false),
            locale: const Locale('zh', 'CN'),
          ),
        );
        for (final label in ['新建项目', '打开文件夹', '资源管理器', '设置', '界面缩放']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('克隆仓库'), findsNothing);
        expect(find.text(shortcutLabel('Ctrl+Shift+G')), findsNothing);
      },
    );

    testWidgets('narrow hint list wraps and scrolls without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(
          const WorkbenchShortcutHints(),
          size: const Size(260, 180),
          textScale: 2,
        ),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('platform label helper supplies command symbols for every hint', () {
      for (final keys in [
        'Ctrl+Shift+N',
        'Ctrl+O',
        'Ctrl+Shift+G',
        'Ctrl+Shift+E',
        'Ctrl+Shift+A',
        'Ctrl+,',
        'Ctrl+= / Ctrl+-',
      ]) {
        expect(shortcutLabel(keys, macOS: true), keys.replaceAll('Ctrl', '⌘'));
      }
    });
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
