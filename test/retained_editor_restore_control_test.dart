import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/retained_editor_restore_control.dart';

/// Focused tests for the draggable floating restore control.
///
/// These mount the control directly rather than through the full app, so they
/// pin the control's own contracts (drag, collapse/expand, bounded layout) and
/// stay independent of the editor/session wiring covered by
/// `retained_editor_test.dart`.
void main() {
  /// Mounts the control inside a fixed host box so layout maths is explicit.
  Future<RetainedEditorRestoreControlState> mount(
    WidgetTester tester, {
    required Size hostSize,
    String? projectName = 'Alpha',
    bool visible = true,
    bool interactive = true,
    bool hasMultipleSessions = false,
    double? reserveBottom,
    double textScale = 1,
    FakeViewPadding padding = const FakeViewPadding(),
    VoidCallback? onRestore,
    ValueChanged<BuildContext>? onSelect,
    RestoreControlMode initialMode = RestoreControlMode.expanded,
    RestoreControlPosition? initialPosition,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final key = GlobalKey<RetainedEditorRestoreControlState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SizedBox(
              width: hostSize.width,
              height: hostSize.height,
              child: RetainedEditorRestoreControl(
                key: key,
                visible: visible,
                interactive: interactive,
                projectName: projectName,
                hasMultipleSessions: hasMultipleSessions,
                reserveBottom: reserveBottom,
                initialMode: initialMode,
                initialPosition: initialPosition,
                onRestore: onRestore ?? () {},
                onSelect: onSelect ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return key.currentState!;
  }

  Finder expandedBar() =>
      find.byKey(const ValueKey('restore-control-expanded'));
  Finder collapsedCircle() =>
      find.byKey(const ValueKey('restore-control-collapsed'));

  /// Performs a real pan gesture on the control and releases it.
  ///
  /// Travel is sent as several move events because a single large `moveBy` is
  /// swallowed by pan recognition. The first move deliberately overshoots
  /// Flutter's touch slop so the recorded origin is the settled one; the
  /// slop distance itself is subtracted from the reported travel.
  ///
  /// Returns the position after the gesture.
  Future<RestoreControlPosition> panBy(
    WidgetTester tester,
    Offset travel, {
    Finder? target,
  }) async {
    final control = target ?? expandedBar();
    final gesture = await tester.startGesture(tester.getCenter(control));
    // Consume the recognizer's slop first so it does not eat the travel below.
    const slopStep = Offset(-24, -24);
    await gesture.moveBy(slopStep);
    await tester.pump();
    final start = tester.getRect(control).topLeft;

    const steps = 8;
    final step = Offset(travel.dx / steps, travel.dy / steps);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    return RestoreControlPosition(start.dx, start.dy);
  }

  testWidgets('expanded bar is shown with the project name and restores', (
    tester,
  ) async {
    var restored = 0;
    final state = await mount(
      tester,
      hostSize: const Size(400, 600),
      onRestore: () => restored++,
    );
    expect(state.mode, RestoreControlMode.expanded);
    expect(expandedBar(), findsOneWidget);
    expect(find.textContaining('返回编辑器 · Alpha'), findsOneWidget);

    await tester.tap(find.textContaining('返回编辑器 ·'));
    expect(restored, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('circle tap EXPANDS the control rather than restoring', (
    tester,
  ) async {
    // PRD: the collapsed circle expands on tap. Restoring from a bare tap on a
    // 48dp target would silently resume a session, so this is pinned.
    var restored = 0;
    final state = await mount(
      tester,
      hostSize: const Size(400, 600),
      initialMode: RestoreControlMode.collapsed,
      onRestore: () => restored++,
    );
    expect(state.mode, RestoreControlMode.collapsed);
    expect(collapsedCircle(), findsOneWidget);
    expect(expandedBar(), findsNothing);

    await tester.tap(collapsedCircle());
    await tester.pump();
    expect(state.mode, RestoreControlMode.expanded);
    expect(expandedBar(), findsOneWidget);
    expect(collapsedCircle(), findsNothing);
    expect(restored, 0, reason: 'tapping the circle must not restore');
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded bar collapses to the circle via the collapse action', (
    tester,
  ) async {
    final state = await mount(tester, hostSize: const Size(400, 600));
    final expanded = tester.getRect(expandedBar());
    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await tester.pump();
    expect(state.mode, RestoreControlMode.collapsed);
    expect(collapsedCircle(), findsOneWidget);
    final collapsed = tester.getRect(collapsedCircle());
    expect(collapsed.right, closeTo(expanded.right, 0.01));
    expect(collapsed.center.dy, closeTo(expanded.center.dy, 0.01));

    await tester.tap(collapsedCircle());
    await tester.pump();
    expect(tester.getRect(expandedBar()), expanded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode survives hide/show and interactive toggles', (
    tester,
  ) async {
    // The host keeps this widget mounted; visibility is a property, so the
    // user's collapse choice must not be lost when the control is hidden.
    final key = GlobalKey<RetainedEditorRestoreControlState>();
    Widget build({required bool visible, bool interactive = true}) =>
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: SizedBox(
                width: 400,
                height: 600,
                child: RetainedEditorRestoreControl(
                  key: key,
                  visible: visible,
                  interactive: interactive,
                  projectName: 'Alpha',
                  hasMultipleSessions: false,
                  onRestore: () {},
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build(visible: true));
    await tester.pump();
    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await tester.pump();
    expect(key.currentState!.mode, RestoreControlMode.collapsed);

    // Hide (as the host does while an editor is visible or a modal is open).
    await tester.pumpWidget(build(visible: false));
    await tester.pump();
    expect(collapsedCircle(), findsNothing);
    expect(key.currentState!.mode, RestoreControlMode.collapsed);

    // Freeze input for a modal without unmounting.
    await tester.pumpWidget(build(visible: false, interactive: false));
    await tester.pump();
    expect(key.currentState!.mode, RestoreControlMode.collapsed);

    // Show again: still collapsed, same state object.
    await tester.pumpWidget(build(visible: true));
    await tester.pump();
    expect(collapsedCircle(), findsOneWidget);
    expect(key.currentState!.mode, RestoreControlMode.collapsed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging moves the control and starts from the painted bounds', (
    tester,
  ) async {
    final state = await mount(tester, hostSize: const Size(400, 600));
    final before = await panBy(tester, const Offset(-80, -120));
    final after = state.position!;
    final rect = tester.getRect(expandedBar());
    // Exactness: the painted control and the stored position agree, and the
    // drag moved it by the requested travel.
    expect(after.dx, closeTo(rect.left, 1));
    expect(after.dy, closeTo(rect.top, 1));
    expect(after.dx, closeTo(before.dx - 80, 1));
    expect(after.dy, closeTo(before.dy - 120, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all drag updates before a frame contribute to movement', (
    tester,
  ) async {
    final state = await mount(
      tester,
      hostSize: const Size(400, 600),
      initialPosition: const RestoreControlPosition(100, 300),
    );
    final gesture = await tester.startGesture(tester.getCenter(expandedBar()));
    await gesture.moveBy(const Offset(-24, -24));
    await tester.pump();
    final before = tester.getRect(expandedBar()).topLeft;

    // Touch devices can deliver several updates between display frames.
    // Deliberately avoid pumping until all three updates have arrived.
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(-8, -12));
    }
    await tester.pump();

    final after = tester.getRect(expandedBar()).topLeft;
    expect(after.dx, closeTo(before.dx - 24, 1));
    expect(after.dy, closeTo(before.dy - 36, 1));
    expect(state.position, RestoreControlPosition(after.dx, after.dy));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag past an edge clamps and does not store a hidden residue', (
    tester,
  ) async {
    // Regression: accumulating the raw pointer total from a drag-start snapshot
    // let the stored position run far off-screen while the paint stayed clamped,
    // so the control looked frozen and the user had to drag all the discarded
    // distance back before anything moved.
    final state = await mount(tester, hostSize: const Size(400, 600));
    final bar = expandedBar();
    final start = tester.getCenter(bar);
    final gesture = await tester.startGesture(start);
    // Many small moves, each well past the top-left edge.
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(-20, -20));
      await tester.pump();
    }
    final clampedRect = tester.getRect(bar);
    expect(clampedRect.left, greaterThanOrEqualTo(0));
    expect(clampedRect.top, greaterThanOrEqualTo(0));

    // The stored value must stay within one delta of what is painted, not
    // hundreds of pixels beyond it.
    final stored = state.position!;
    expect((stored.dx - clampedRect.left).abs(), lessThanOrEqualTo(20.5));
    expect((stored.dy - clampedRect.top).abs(), lessThanOrEqualTo(20.5));

    // Dragging back by one step moves the control by exactly that step.
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    final movedRect = tester.getRect(bar);
    expect(movedRect.left, closeTo(clampedRect.left + 20, 1));
    expect(movedRect.top, closeTo(clampedRect.top + 20, 1));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('position survives hide/show and mode changes', (tester) async {
    final key = GlobalKey<RetainedEditorRestoreControlState>();
    Widget build(bool visible) => MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SizedBox(
            width: 400,
            height: 600,
            child: RetainedEditorRestoreControl(
              key: key,
              visible: visible,
              projectName: 'Alpha',
              hasMultipleSessions: false,
              onRestore: () {},
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(true));
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(expandedBar()));
    await gesture.moveBy(const Offset(0, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-100, -200));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final dragged = key.currentState!.position!;
    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pumpWidget(build(true));
    await tester.pump();
    expect(key.currentState!.position, dragged);

    // Mode changes share the right edge, and a round trip restores the bar.
    final expanded = tester.getRect(expandedBar());
    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await tester.pump();
    final collapsed = tester.getRect(collapsedCircle());
    expect(collapsed.right, closeTo(expanded.right, 0.01));
    expect(collapsed.center.dy, closeTo(expanded.center.dy, 0.01));
    await tester.tap(collapsedCircle());
    await tester.pump();
    expect(key.currentState!.position, dragged);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding a dragged circle uses its right edge then clamps', (
    tester,
  ) async {
    final state = await mount(
      tester,
      hostSize: const Size(400, 600),
      initialMode: RestoreControlMode.collapsed,
    );
    await panBy(tester, const Offset(-20, -80), target: collapsedCircle());
    final draggedCircle = tester.getRect(collapsedCircle());
    await tester.tap(collapsedCircle());
    await tester.pump();
    final expanded = tester.getRect(expandedBar());
    expect(expanded.right, closeTo(draggedCircle.right, 0.01));
    expect(expanded.center.dy, closeTo(draggedCircle.center.dy, 0.01));

    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await tester.pump();
    await panBy(tester, const Offset(-500, 0), target: collapsedCircle());
    final edgeCircle = tester.getRect(collapsedCircle());
    await tester.tap(collapsedCircle());
    await tester.pump();
    final edgeBar = tester.getRect(expandedBar());
    expect(edgeBar.left, closeTo(edgeCircle.left, 0.01));
    expect(edgeBar.right, lessThanOrEqualTo(400));
    expect(edgeBar.center.dy, closeTo(edgeCircle.center.dy, 0.01));
    expect(state.position, RestoreControlPosition(edgeBar.left, edgeBar.top));

    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await tester.pump();
    expect(
      tester.getRect(collapsedCircle()).right,
      closeTo(edgeBar.right, 0.01),
    );
    await tester.tap(collapsedCircle());
    await tester.pump();
    expect(tester.getRect(expandedBar()), edgeBar);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bottom keyboard inset keeps the control above it', (
    tester,
  ) async {
    // `SafeArea` applies `padding` but not `viewInsets`, so the host converts
    // the keyboard height into reserved bottom space. Without that the control
    // clamps to the bottom of the window and sits behind the keyboard.
    const hostSize = Size(400, 600);
    const keyboard = 280.0;
    final key = GlobalKey<RetainedEditorRestoreControlState>();
    Widget build({required double bottomInset}) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: bottomInset),
          ),
          child: SizedBox(
            width: hostSize.width,
            height: hostSize.height,
            child: RetainedEditorRestoreControl(
              key: key,
              visible: true,
              projectName: 'Alpha',
              hasMultipleSessions: false,
              reserveBottom: bottomInset,
              onRestore: () {},
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(bottomInset: 0));
    await tester.pump();
    final withoutKeyboard = tester.getRect(expandedBar());

    await tester.pumpWidget(build(bottomInset: keyboard));
    await tester.pump();
    final withKeyboard = tester.getRect(expandedBar());

    expect(
      withKeyboard.bottom,
      lessThanOrEqualTo(hostSize.height - keyboard),
      reason: 'the control must move above the keyboard',
    );
    expect(
      withKeyboard.bottom,
      lessThan(withoutKeyboard.bottom),
      reason: 'opening the keyboard lifts the control',
    );
    // The stored position must be re-clamped, not left behind the keyboard.
    expect(
      key.currentState!.position!.dy,
      lessThanOrEqualTo(hostSize.height - keyboard),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden zero-size layout cannot seed the position', (
    tester,
  ) async {
    // Regression: laying out the placeholder while hidden reported a zero child
    // size, which seeded a bogus default so the first visible frame appeared at
    // the top-left instead of the resting corner.
    final key = GlobalKey<RetainedEditorRestoreControlState>();
    Widget build({
      required bool visible,
      required String? projectName,
      Size hostSize = const Size(400, 600),
    }) => MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SizedBox(
            width: hostSize.width,
            height: hostSize.height,
            child: RetainedEditorRestoreControl(
              key: key,
              visible: visible,
              projectName: projectName,
              hasMultipleSessions: false,
              onRestore: () {},
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    // Start with no session: mounted, hidden, placeholder layout only.
    await tester.pumpWidget(build(visible: false, projectName: null));
    await tester.pump();

    // Become restorable: it must rest at the bottom-right corner, not (0,0).
    await tester.pumpWidget(build(visible: true, projectName: 'Alpha'));
    await tester.pump();
    final rect = tester.getRect(expandedBar());
    expect(rect.right, greaterThan(300), reason: 'rests on the right edge');
    expect(rect.bottom, greaterThan(400), reason: 'rests on the bottom edge');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long names, 2x text and a small host stay inside the bounds', (
    tester,
  ) async {
    const longName = '这是一个用于验证窄屏恢复控件的很长很长的工程名称';
    await mount(
      tester,
      hostSize: const Size(300, 420),
      projectName: longName,
      textScale: 2,
      reserveBottom: 120,
    );
    final rect = tester.getRect(expandedBar());
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(300));
    expect(rect.bottom, lessThanOrEqualTo(420));
    // The reserved bottom band must remain free for Home's FAB.
    expect(rect.bottom, lessThanOrEqualTo(420 - 120));

    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await tester.pump();
    final collapsed = tester.getRect(collapsedCircle());
    expect(collapsed.right, closeTo(rect.right, 0.01));
    expect(collapsed.center.dy, closeTo(rect.center.dy, 0.01));
    await tester.tap(collapsedCircle());
    await tester.pump();
    expect(tester.getRect(expandedBar()), rect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clamps inside a safe area with insets', (tester) async {
    await mount(
      tester,
      hostSize: const Size(320, 500),
      padding: const FakeViewPadding(top: 40, bottom: 30, left: 12, right: 12),
      textScale: 2,
      projectName: 'Alpha',
    );
    final safe = tester.getRect(find.byType(SafeArea).last);
    final rect = tester.getRect(expandedBar());
    expect(rect.left, greaterThanOrEqualTo(safe.left - 0.5));
    expect(rect.top, greaterThanOrEqualTo(safe.top - 0.5));
    expect(rect.right, lessThanOrEqualTo(safe.right + 0.5));
    expect(rect.bottom, lessThanOrEqualTo(safe.bottom + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden control is isolated from input, focus and semantics', (
    tester,
  ) async {
    var restored = 0;
    await mount(
      tester,
      hostSize: const Size(400, 600),
      visible: false,
      onRestore: () => restored++,
    );
    expect(expandedBar(), findsNothing);
    expect(collapsedCircle(), findsNothing);
    // Offstage subtree: no hit target, and tapping the area does nothing.
    await tester.tapAt(const Offset(380, 560));
    expect(restored, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed circle sits at the same bounded position', (
    tester,
  ) async {
    await mount(
      tester,
      hostSize: const Size(300, 400),
      initialMode: RestoreControlMode.collapsed,
      reserveBottom: 100,
    );
    final rect = tester.getRect(collapsedCircle());
    expect(rect.right, lessThanOrEqualTo(300));
    expect(rect.bottom, lessThanOrEqualTo(300));
    expect(
      rect.width,
      closeTo(RetainedEditorRestoreControlState.debugCircleDiameter, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
