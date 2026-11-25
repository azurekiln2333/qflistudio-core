import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';
import 'package:qfli_studio_core/shell/workbench_explorer.dart';
import 'package:qfli_studio_core/shell/workbench_theme.dart';

void main() {
  // R21/V1: device family changes density, not a window-width heuristic.
  for (final brightness in Brightness.values) {
    for (final factor in [AppFormFactor.desktop, AppFormFactor.tablet]) {
      testWidgets('$brightness $factor scopes density, menus and notices', (
        tester,
      ) async {
        final base = ThemeData(useMaterial3: true, brightness: brightness);
        final theme = WorkbenchTheme.from(base, formFactor: factor);
        ThemeData? actual;
        await tester.pumpWidget(
          MaterialApp(
            theme: base,
            home: Theme(
              data: theme,
              child: Builder(
                builder: (context) {
                  actual = Theme.of(context);
                  return const Scaffold(body: Text('Workbench'));
                },
              ),
            ),
          ),
        );
        final desktop = factor == AppFormFactor.desktop;
        expect(
          actual!.visualDensity,
          desktop ? VisualDensity.compact : VisualDensity.standard,
        );
        expect(
          actual!.materialTapTargetSize,
          desktop
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
        );
        expect(
          actual!.tooltipTheme.waitDuration,
          const Duration(milliseconds: 500),
        );
        expect(actual!.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(actual!.snackBarTheme.width, lessThanOrEqualTo(480));
        expect(
          actual!.navigationRailTheme.indicatorColor,
          base.colorScheme.secondaryContainer,
        );
        expect(
          actual!.menuButtonTheme.style!.minimumSize!.resolve({})!.height,
          desktop ? 32 : 48,
        );
        final overlay = actual!.menuButtonTheme.style!.overlayColor!;
        expect(
          overlay.resolve({WidgetState.hovered}),
          base.colorScheme.onSurface.withValues(alpha: 0.08),
        );
        expect(
          overlay.resolve({WidgetState.pressed}),
          base.colorScheme.onSurface.withValues(alpha: 0.10),
        );
        expect(
          overlay.resolve({WidgetState.focused}),
          base.colorScheme.onSurface.withValues(alpha: 0.10),
        );
        expect(
          actual!.menuButtonTheme.style!.side!.resolve({
            WidgetState.focused,
          })!.color,
          base.colorScheme.primary,
        );
        // The shared phone theme was not mutated by the scoped copy.
        expect(base.visualDensity, VisualDensity.standard);
        expect(base.materialTapTargetSize, MaterialTapTargetSize.padded);
      });
    }
  }

  testWidgets(
    'custom controls add a focus ring without an extra focus target',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkbenchFocusOutline(
              child: TextButton(
                focusNode: node,
                onPressed: () {},
                child: const Text('Focusable'),
              ),
            ),
          ),
        ),
      );
      final outline = Focus.of(tester.element(find.byType(TextButton)));
      expect(outline.canRequestFocus, isFalse);
      expect(outline.skipTraversal, isTrue);
      expect(outline.traversalDescendants, orderedEquals([node]));
      expect(
        find.byKey(const ValueKey('workbench-focus-outline')),
        findsNothing,
      );
      node.requestFocus();
      tester.binding.focusManager.applyFocusChangesIfNeeded();
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
      expect(outline.hasFocus, isTrue);
      expect(
        find.byKey(const ValueKey('workbench-focus-outline')),
        findsOneWidget,
      );
      node.unfocus();
      // With no frame pending, pump flushes focus notifications after building.
      // Resolve them first so this frame renders the changed focus state.
      tester.binding.focusManager.applyFocusChangesIfNeeded();
      await tester.pump();
      expect(node.hasFocus, isFalse);
      expect(outline.hasFocus, isFalse);
      expect(
        find.byKey(const ValueKey('workbench-focus-outline')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  // R23/V7: drag the real gesture target past each bound, then double-click.
  testWidgets('sidebar divider clamps drag, keeps presentation and resets', (
    tester,
  ) async {
    final controller = LargeScreenController();
    addTearDown(controller.dispose);
    final owner = Object();
    controller.activateFiles(owner);
    controller.showFiles();
    final dividerWidth = WorkbenchSidebarDivider.desktopHitWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 400,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Stack(
                  children: [
                    Positioned(
                      left: controller.sidebarWidth - dividerWidth / 2,
                      top: 0,
                      bottom: 0,
                      width: dividerWidth,
                      child: WorkbenchSidebarDivider(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final divider = find.byKey(WorkbenchSidebarDivider.dividerKey);
    expect(tester.getSize(divider).width, 6);
    final region = find
        .ancestor(of: divider, matching: find.byType(MouseRegion))
        .first;
    expect(
      tester.widget<MouseRegion>(region).cursor,
      SystemMouseCursors.resizeColumn,
    );
    await tester.drag(divider, const Offset(1000, 0));
    await tester.pump();
    expect(controller.sidebarWidth, 480);
    await tester.drag(divider, const Offset(-1000, 0));
    await tester.pump();
    expect(controller.sidebarWidth, 220);
    expect(controller.explorerPage, ExplorerPage.files);
    expect(controller.activeEditor, same(owner));
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.sidebarWidth, 300);
    controller.setSidebarWidth(double.nan);
    controller.setSidebarWidth(double.infinity);
    expect(controller.sidebarWidth, 300);
  });

  testWidgets('touch workbench divider exposes a 48dp target', (tester) async {
    final controller = LargeScreenController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: Stack(
              children: [
                Positioned(
                  left:
                      controller.sidebarWidth -
                      WorkbenchSidebarDivider.touchHitWidth / 2,
                  top: 0,
                  bottom: 0,
                  width: WorkbenchSidebarDivider.touchHitWidth,
                  child: WorkbenchSidebarDivider(
                    controller: controller,
                    touchLayout: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(WorkbenchSidebarDivider.dividerKey)).width,
      48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('project panel has permanent compact search and menu shortcuts', (
    tester,
  ) async {
    final search = TextEditingController();
    addTearDown(search.dispose);
    String? query;
    var creates = 0;
    final project = Project.create(name: 'Current project', path: '/current');
    final theme = WorkbenchTheme.from(
      ThemeData(useMaterial3: true),
      formFactor: AppFormFactor.desktop,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: WorkbenchProjectsPanel(
              searchController: search,
              onSearchChanged: (value) => query = value,
              onCreate: () => creates++,
              onOpenFolder: () {},
              onClone: () {},
              filterItems: [
                MenuItemButton(
                  onPressed: () {},
                  child: const Text('All projects'),
                ),
              ],
              moreItems: [
                MenuItemButton(
                  onPressed: () {},
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyN,
                    control: true,
                    shift: true,
                  ),
                  child: const Text('New project command'),
                ),
              ],
              progress: const SizedBox.shrink(),
              body: ListView(
                children: [
                  WorkbenchProjectRow(
                    project: project,
                    current: true,
                    opened: true,
                    onOpen: () {},
                    menuItems: const [],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('workbench-project-header')))
          .height,
      40,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('workbench-project-search')))
          .height,
      36,
    );
    final row = find.byKey(ValueKey('workbench-project-${project.id}'));
    expect(tester.getSize(row).height, 32);
    final material = tester.widget<Material>(
      find.descendant(of: row, matching: find.byType(Material)).first,
    );
    expect(material.color, theme.colorScheme.secondaryContainer);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('workbench-project-search')),
      'alpha',
    );
    expect(query, 'alpha');
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    expect(creates, 1);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('New project command'), findsOneWidget);
    final menu = tester.widget<MenuItemButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MenuItemButton &&
            widget.child is Text &&
            (widget.child! as Text).data == 'New project command',
      ),
    );
    expect(menu.shortcut, isA<SingleActivator>());
    expect(find.textContaining('Ctrl'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
