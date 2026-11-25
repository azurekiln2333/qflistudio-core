import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/shell/ui_zoom.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

const _transform = ValueKey('ui-zoom-transform');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scale clamps, steps and survives reloading settings', () async {
    final directory = await Directory.systemTemp.createTemp('ui-zoom-');
    final file = File('${directory.path}/settings.json');
    final settings = SettingsStore(storageFile: file);
    final restored = SettingsStore(storageFile: file);
    try {
      await settings.load();
      for (var i = 0; i < 3; i++) {
        await settings.setUiScale(settings.uiScale + 0.1);
      }
      expect(settings.uiScale, 1.3);
      await restored.load();
      expect(restored.uiScale, 1.3);
      await settings.setLargeScreenSymbolBar(true);
      await restored.load();
      expect(restored.largeScreenSymbolBar, isTrue);
      await settings.setUiScale(5);
      expect(settings.uiScale, 2);
      await settings.setUiScale(-1);
      expect(settings.uiScale, 0.5);
      await settings.setUiScale(1);
      expect(settings.uiScale, 1);
    } finally {
      settings.dispose();
      restored.dispose();
      await directory.delete(recursive: true);
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('$platform zoom wins over a consuming editor focus handler', (
      tester,
    ) async {
      final settings = SettingsStore();
      final node = FocusNode();
      final previousPlatformOverride = debugDefaultTargetPlatformOverride;
      var swallowed = 0;
      try {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          _app(
            settings,
            Focus(
              focusNode: node,
              onKeyEvent: (_, _) {
                swallowed++;
                return KeyEventResult.handled;
              },
              child: const SizedBox.expand(),
            ),
          ),
        );
        node.requestFocus();
        await tester.pump();
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        for (var i = 0; i < 3; i++) {
          await _key(tester, LogicalKeyboardKey.equal, modifier: modifier);
        }
        expect(settings.uiScale, 1.3);
        expect(find.text('界面缩放 130%'), findsOneWidget);
        await tester.sendKeyDownEvent(modifier);
        final afterModifier = swallowed;
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        expect(swallowed, afterModifier);
        await tester.sendKeyUpEvent(modifier);
        expect(settings.uiScale, 1.2);
        await _key(tester, LogicalKeyboardKey.numpadAdd, modifier: modifier);
        expect(settings.uiScale, 1.3);
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        expect(HardwareKeyboard.instance.isShiftPressed, isTrue);
        expect(
          platform == TargetPlatform.macOS
              ? HardwareKeyboard.instance.isMetaPressed
              : HardwareKeyboard.instance.isControlPressed,
          isTrue,
        );
        final beforePlus = swallowed;
        _dispatchZoomKey(
          LogicalKeyboardKey.add,
          PhysicalKeyboardKey.equal,
          isDown: true,
          character: '+',
        );
        expect(settings.uiScale, 1.4);
        expect(swallowed, beforePlus);
        _dispatchZoomKey(
          LogicalKeyboardKey.add,
          PhysicalKeyboardKey.equal,
          isDown: false,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        await _key(
          tester,
          LogicalKeyboardKey.equal,
          modifier: modifier,
          shift: true,
        );
        expect(settings.uiScale, 1.5);
        await _key(
          tester,
          LogicalKeyboardKey.numpadSubtract,
          modifier: modifier,
        );
        expect(settings.uiScale, 1.4);
        await _key(tester, LogicalKeyboardKey.numpad0, modifier: modifier);
        expect(settings.uiScale, 1);
        expect(find.byKey(_transform), findsNothing);
        await _key(tester, LogicalKeyboardKey.equal, modifier: modifier);
        await _key(tester, LogicalKeyboardKey.digit0, modifier: modifier);
        expect(settings.uiScale, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const ValueKey('ui-zoom-feedback')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        // The early global handler must not outlive the widget.
        await _key(tester, LogicalKeyboardKey.equal, modifier: modifier);
        expect(settings.uiScale, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        node.dispose();
        settings.dispose();
        // Restore before TestWidgetsFlutterBinding checks foundation invariants.
        debugDefaultTargetPlatformOverride = previousPlatformOverride;
      }
    });
  }

  testWidgets('scales layout and every inset without scaling text twice', (
    tester,
  ) async {
    final settings = SettingsStore()..uiScale = 2;
    late MediaQueryData actual;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.all(20),
            viewPadding: EdgeInsets.all(24),
            viewInsets: EdgeInsets.only(bottom: 200),
            systemGestureInsets: EdgeInsets.all(16),
            textScaler: TextScaler.linear(1.25),
          ),
          child: UiZoom(settings: settings, child: child!),
        ),
        home: Builder(
          builder: (context) {
            actual = MediaQuery.of(context);
            return const SizedBox.expand(key: ValueKey('zoom-layout'));
          },
        ),
      ),
    );
    expect(actual.size, const Size(400, 300));
    expect(actual.padding, const EdgeInsets.all(10));
    expect(actual.viewPadding, const EdgeInsets.all(12));
    expect(actual.viewInsets.bottom, 100);
    expect(actual.systemGestureInsets, const EdgeInsets.all(8));
    expect(actual.textScaler.scale(12), 15);
    final box = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('zoom-layout')),
    );
    expect(box.size, const Size(400, 300));
    expect(box.localToGlobal(const Offset(50, 50)), const Offset(100, 100));
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  for (final scale in [0.5, 2.0]) {
    testWidgets('scaled clicks, drags and text-selection hit tests at $scale', (
      tester,
    ) async {
      final settings = SettingsStore()..uiScale = scale;
      var taps = 0;
      var drag = 0.0;
      final field = TextEditingController(text: 'abcdefghijklmnop');
      await tester.pumpWidget(
        _app(
          settings,
          Scaffold(
            body: Column(
              children: [
                GestureDetector(
                  key: const ValueKey('zoom-target'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  onHorizontalDragUpdate: (event) => drag += event.delta.dx,
                  child: const SizedBox(width: 160, height: 60),
                ),
                TextField(controller: field),
              ],
            ),
          ),
        ),
      );
      final target = find.byKey(const ValueKey('zoom-target'));
      final center = tester.getCenter(target);
      await tester.tapAt(center);
      expect(taps, 1);
      await tester.dragFrom(center, Offset(60 * scale, 0));
      expect(drag, greaterThan(0));
      final editable = find.byType(EditableText);
      await tester.tap(editable);
      await tester.pump();
      final render = tester.state<EditableTextState>(editable).renderEditable;
      final point =
          tester.getTopLeft(editable) + Offset(50 * scale, 10 * scale);
      final selectedPosition = render.getPositionForPoint(point);
      // Finish the first tap's double-tap window before testing a new caret.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(point);
      await tester.pump();
      expect(field.selection.isValid, isTrue);
      expect(field.selection.baseOffset, selectedPosition.offset);
      await tester.pumpWidget(const SizedBox());
      field.dispose();
      settings.dispose();
    });
  }

  testWidgets(
    'navigator/dialog and focused child state survive 100% boundary',
    (tester) async {
      final settings = SettingsStore();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => UiZoom(settings: settings, child: child!),
          home: const Scaffold(body: TextField()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'retained');
      final original = navigator.currentState;
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      await settings.setUiScale(1.1);
      await tester.pump();
      expect(navigator.currentState, same(original));
      expect(tester.state(find.byType(EditableText)), same(editable));
      expect(find.text('retained'), findsOneWidget);
      expect(editable.widget.focusNode.hasFocus, isTrue);
      showDialog<void>(
        context: editable.context,
        builder: (_) => const AlertDialog(content: Text('scaled dialog')),
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('scaled dialog'),
          matching: find.byKey(_transform),
        ),
        findsOneWidget,
      );
      await _key(tester, LogicalKeyboardKey.digit0);
      expect(find.byKey(_transform), findsNothing);
      expect(find.text('scaled dialog'), findsOneWidget);
      expect(navigator.currentState, same(original));
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets('desktop modified wheel zooms without scrolling descendants', (
    tester,
  ) async {
    final settings = SettingsStore();
    final scroll = ScrollController();
    await tester.pumpWidget(
      _app(
        settings,
        ListView(
          controller: scroll,
          children: List.generate(
            100,
            (i) => SizedBox(height: 60, child: Text('$i')),
          ),
        ),
        wheel: true,
      ),
    );
    Future<void> wheel(double delta) async {
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: const Offset(200, 200),
          kind: PointerDeviceKind.mouse,
          scrollDelta: Offset(0, delta),
        ),
      );
      await tester.pump();
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(-40);
    expect(settings.uiScale, 1.1);
    expect(scroll.offset, 0);
    await wheel(40);
    expect(settings.uiScale, 1);
    expect(scroll.offset, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await wheel(40);
    expect(settings.uiScale, 1);
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    settings.dispose();
  });

  testWidgets('tablet ignores wheel and disabled phone ignores saved zoom', (
    tester,
  ) async {
    final settings = SettingsStore()..uiScale = 1.5;
    await tester.pumpWidget(_app(settings, const SizedBox.expand()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(100, 100),
        kind: PointerDeviceKind.mouse,
        scrollDelta: Offset(0, -40),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(settings.uiScale, 1.5);
    await tester.pumpWidget(
      _app(settings, const Text('phone'), enabled: false, wheel: true),
    );
    expect(find.byKey(_transform), findsNothing);
    await _key(tester, LogicalKeyboardKey.equal);
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(100, 100),
        kind: PointerDeviceKind.mouse,
        scrollDelta: Offset(0, -40),
      ),
    );
    expect(settings.uiScale, 1.5);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}

Widget _app(
  SettingsStore settings,
  Widget child, {
  bool enabled = true,
  bool wheel = false,
}) => MaterialApp(
  builder: (_, navigator) => UiZoom(
    settings: settings,
    enabled: enabled,
    mouseWheelEnabled: wheel,
    child: navigator!,
  ),
  home: child,
);

void _dispatchZoomKey(
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey, {
  required bool isDown,
  String? character,
}) {
  final event = isDown
      ? KeyDownEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          character: character,
          timeStamp: Duration.zero,
        )
      : KeyUpEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          timeStamp: Duration.zero,
        );
  HardwareKeyboard.instance.handleKeyEvent(event);
  // Exercise the same FocusManager message path as the simulator without the
  // platform raw-event lookup, which has no Windows mapping for logical Add.
  // ignore: deprecated_member_use
  // ignore: deprecated_member_use
  ServicesBinding.instance.keyEventManager.keyMessageHandler?.call(
    // ignore: deprecated_member_use
    KeyMessage([event], null),
  );
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  PhysicalKeyboardKey? physicalKey,
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  // Logical '+' has no same-named physical key; preserve the supplied key pair.
  await tester.sendKeyEvent(key, physicalKey: physicalKey);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}
