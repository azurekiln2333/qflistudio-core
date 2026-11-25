import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/agent_context_indicator.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/shell/workbench_theme.dart';
import 'package:qfli_studio_core/vibe_coding/agent_context_usage.dart';

Finder _surfaceFor(Finder item, ColorScheme scheme) => find
    .ancestor(
      of: item,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Material && widget.color == scheme.surfaceContainer,
      ),
    )
    .first;

void _expectSurface(
  WidgetTester tester,
  Finder item,
  ColorScheme scheme,
  Rect viewport,
) {
  final surface = _surfaceFor(item, scheme);
  expect(surface, findsOneWidget);
  final material = tester.widget<Material>(surface);
  expect(material.elevation, 2);
  expect(material.shadowColor, scheme.shadow);
  expect(material.surfaceTintColor, Colors.transparent);
  final shape = material.shape! as RoundedRectangleBorder;
  expect(shape.side, BorderSide.none);
  expect(shape.borderRadius, BorderRadius.circular(4));
  // Verify the painted surface, not its transparent menu-only layout gutter.
  // The pinned SDK's reservedPadding limits size but not fallback placement.
  final surfaceRect = tester.getRect(surface);
  final painted = shape
      .getOuterPath(Offset.zero & surfaceRect.size)
      .getBounds()
      .shift(surfaceRect.topLeft);
  expect(painted.left, greaterThanOrEqualTo(viewport.left + 8));
  expect(painted.top, greaterThanOrEqualTo(viewport.top + 8));
  expect(painted.right, lessThanOrEqualTo(viewport.right - 8));
  expect(painted.bottom, lessThanOrEqualTo(viewport.bottom - 8));
  final itemRect = tester.getRect(item);
  expect(itemRect.left, closeTo(painted.left, 0.01));
  expect(itemRect.right, closeTo(painted.right, 0.01));
  expect(itemRect.top - painted.top, closeTo(8, 0.01));
  expect(painted.bottom - itemRect.bottom, closeTo(8, 0.01));
}

void main() {
  // R21/V6: native MenuAnchor panels inherit a borderless MD3 surface even
  // through editor overlays. Keep true shadows in this visual regression suite.
  for (final brightness in Brightness.values) {
    for (final factor in [AppFormFactor.desktop, AppFormFactor.tablet]) {
      testWidgets('$brightness $factor menu surfaces stay inside every edge', (
        tester,
      ) async {
        const size = Size(640, 480);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        final focus = FocusNode();
        final controller = MenuController();
        final theme = WorkbenchTheme.from(
          ThemeData(useMaterial3: true, brightness: brightness),
          formFactor: factor,
        );
        final scheme = theme.colorScheme;
        const itemKey = ValueKey('menu-surface-item');
        const anchorKey = ValueKey('menu-surface-anchor');
        try {
          for (final corner in [
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ]) {
            // Include an editor-like nested overlay, not only the root route.
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Overlay.wrap(
                    child: Align(
                      alignment: corner,
                      child: MenuAnchor(
                        controller: controller,
                        menuChildren: [
                          MenuItemButton(
                            key: itemKey,
                            focusNode: focus,
                            onPressed: () {},
                            child: const Text('Command'),
                          ),
                        ],
                        builder: (context, controller, _) => IconButton(
                          key: anchorKey,
                          onPressed: controller.open,
                          icon: const Icon(Icons.more_vert),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.byKey(anchorKey));
            await tester.pumpAndSettle();
            final item = find.byKey(itemKey);
            expect(controller.isOpen, isTrue);
            _expectSurface(tester, item, scheme, Offset.zero & size);
            expect(
              tester.getSize(item).height,
              factor == AppFormFactor.desktop ? 32 : 48,
            );
            focus.requestFocus();
            tester.binding.focusManager.applyFocusChangesIfNeeded();
            await tester.pumpAndSettle();
            expect(focus.hasPrimaryFocus, isTrue);
            _expectSurface(tester, item, scheme, Offset.zero & size);
            expect(
              find.byKey(const ValueKey('workbench-focus-outline')),
              findsNothing,
              reason: 'Keyboard focus belongs to a menu item, not the panel.',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(controller.isOpen, isFalse);
            expect(find.byKey(itemKey), findsNothing);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          focus.dispose();
          debugDisableShadows = shadows;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      });
    }
  }

  testWidgets('custom context popover keeps the inherited surface gutter', (
    tester,
  ) async {
    const size = Size(640, 480);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final theme = WorkbenchTheme.from(
      ThemeData(useMaterial3: true),
      formFactor: AppFormFactor.desktop,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AgentContextIndicator(
                usage: AgentContextUsage(estimatedInputTokens: 900),
                reportedCapacity: 1000,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('agent-context-capacity')));
      await tester.pumpAndSettle();

      final content = find.byKey(
        const ValueKey('agent-context-capacity-menu-content'),
      );
      expect(content, findsOneWidget);
      final menu = find
          .ancestor(
            of: content,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material &&
                  widget.color == theme.colorScheme.surfaceContainerHigh &&
                  widget.elevation == 2,
            ),
          )
          .first;
      expect(menu, findsOneWidget);
      final material = tester.widget<Material>(menu);
      final shape = material.shape! as RoundedRectangleBorder;
      final rect = tester.getRect(menu);
      final visible = shape
          .getOuterPath(Offset.zero & rect.size)
          .getBounds()
          .shift(rect.topLeft);
      expect(visible.left, greaterThanOrEqualTo(8));
      expect(visible.top, greaterThanOrEqualTo(8));
      expect(visible.right, lessThanOrEqualTo(size.width - 8));
      expect(visible.bottom, lessThanOrEqualTo(size.height - 8));
      final contentRect = tester.getRect(content);
      expect(contentRect.left - visible.left, closeTo(0, 0.01));
      expect(visible.right - contentRect.right, closeTo(0, 0.01));
      expect(contentRect.top - visible.top, closeTo(8, 0.01));
      expect(visible.bottom - contentRect.bottom, closeTo(8, 0.01));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('context menu placement and submenus share the surface gutter', (
    tester,
  ) async {
    const size = Size(640, 480);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final controller = MenuController();
    final base = ThemeData(useMaterial3: true);
    final theme = WorkbenchTheme.from(base, formFactor: AppFormFactor.desktop);
    final style = theme.menuTheme.style!;
    final shape = style.shape!.resolve({})!;
    const bounds = Rect.fromLTWH(0, 0, 240, 160);
    expect(shape.getOuterPath(bounds).getBounds(), bounds.deflate(8));
    expect(
      shape.copyWith(side: BorderSide.none).getOuterPath(bounds).getBounds(),
      bounds.deflate(8),
    );
    expect(shape.scale(1).getOuterPath(bounds).getBounds(), bounds.deflate(8));
    expect(
      ShapeBorder.lerp(
        shape,
        shape.copyWith(side: BorderSide.none),
        0.5,
      )!.getOuterPath(bounds).getBounds(),
      bounds.deflate(8),
    );
    expect(base.menuTheme.style, isNull);
    const itemKey = ValueKey('context-menu-item');
    const nestedKey = ValueKey('submenu-item');
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: MenuAnchor(
              controller: controller,
              menuChildren: [
                MenuItemButton(
                  key: itemKey,
                  onPressed: () {},
                  child: const Text('Context command'),
                ),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      for (final position in [
        Offset.zero,
        const Offset(639, 0),
        const Offset(0, 479),
        const Offset(639, 479),
      ]) {
        controller.open(position: position);
        await tester.pumpAndSettle();
        _expectSurface(
          tester,
          find.byKey(itemKey),
          theme.colorScheme,
          Offset.zero & size,
        );
        controller.close();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: MenuAnchor(
                controller: controller,
                menuChildren: [
                  SubmenuButton(
                    menuChildren: [
                      MenuItemButton(
                        key: nestedKey,
                        onPressed: () {},
                        child: const Text('Nested command'),
                      ),
                    ],
                    child: const Text('Submenu'),
                  ),
                ],
                child: const SizedBox(width: 48, height: 48),
              ),
            ),
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submenu'));
      await tester.pumpAndSettle();
      _expectSurface(
        tester,
        find.byKey(nestedKey),
        theme.colorScheme,
        Offset.zero & size,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
