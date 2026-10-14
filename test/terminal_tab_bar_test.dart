import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

/// Geometry and hit-testing contract for the terminal session tab bar.
///
/// Three regressions are pinned here, all of them user-visible:
///
/// 1. A tab's label used to be the full `Terminal <id>` string, so a single pill
///    measured ~148 px and a couple of tabs pushed the bar into scrolling. The
///    pill is now bounded by `maxTabWidth` and ellipsises.
/// 2. The header painted an opaque colour but did not *absorb* pointer events,
///    so a tap in the gap beside the tabs reached the widget beneath the pane
///    (the editor on mobile) and moved focus there.
/// 3. A single local session could not be closed at all, because the close
///    button was gated on `sessions.length > 1`.
void main() {
  late _TabFixture fixture;

  setUp(() => fixture = _TabFixture());
  tearDown(() => fixture.dispose());

  group('tab width', () {
    testWidgets('the label is the session id, not the full `Terminal <id>`', (
      tester,
    ) async {
      await fixture.mount(tester);

      // The full label does not fit a tab; the id alone identifies it.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Terminal 1'), findsNothing);
    });

    testWidgets('a single tab stays within the width cap', (tester) async {
      await fixture.mount(tester);

      final pill = fixture.pillFinder;
      expect(pill, findsOneWidget);
      expect(
        tester.getSize(pill).width,
        lessThanOrEqualTo(TerminalPanelMetrics.maxTabWidth),
        reason: 'the pill must respect the width cap',
      );
      expect(
        tester.getSize(pill).height,
        closeTo(TerminalPanelMetrics.tabHeight, 0.5),
        reason:
            'the width change must not disturb the height the user signed '
            'off on',
      );
    });

    testWidgets('the pill stays inside the cap even on a very narrow pane', (
      tester,
    ) async {
      // A phone-width pane with several tabs is the case the cap exists for:
      // without it the pills would push the action buttons off screen and the
      // bar would scroll much sooner than necessary.
      await fixture.mount(tester, size: const Size(280, 300));
      for (var i = 0; i < 5; i++) {
        fixture.pane.addSession();
        await tester.pump();
      }

      for (final pill in fixture.allPills.evaluate()) {
        expect(
          tester.getSize(find.byWidget(pill.widget)).width,
          lessThanOrEqualTo(TerminalPanelMetrics.maxTabWidth),
        );
      }
      // The trailing action buttons must still be laid out inside the pane.
      final menu = find.byTooltip('终端操作');
      expect(menu, findsOneWidget);
      expect(
        tester.getRect(menu).right,
        lessThanOrEqualTo(tester.getRect(find.byType(TerminalPane)).right),
      );
    });

    testWidgets('the label text is configured to ellipsise', (tester) async {
      // Directly pins the text configuration: the `Text` widget must allow a
      // single ellipsised line, which is what keeps a label from overflowing.
      await fixture.mount(tester);
      final label = tester.widget<Text>(find.text('1'));
      expect(label.overflow, TextOverflow.ellipsis);
      expect(label.maxLines, 1);
      expect(label.softWrap, isFalse);
    });

    testWidgets('many tabs stay inside the cap and the bar scrolls', (
      tester,
    ) async {
      // A narrow pane with several sessions: the labels must not push the action
      // buttons off screen, and the bar must remain horizontally scrollable.
      await fixture.mount(tester, size: const Size(320, 300));
      for (var i = 0; i < 4; i++) {
        fixture.pane.addSession();
        await tester.pump();
      }

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      expect(scrollView.scrollDirection, Axis.horizontal);

      for (final pill in fixture.allPills.evaluate()) {
        final width = tester.getSize(find.byWidget(pill.widget)).width;
        expect(width, lessThanOrEqualTo(TerminalPanelMetrics.maxTabWidth));
      }
    });
  });

  group('tab bar hit testing', () {
    testWidgets('tapping the empty tab bar area takes no focus', (tester) async {
      await fixture.mount(tester);

      final bar = tester.getRect(find.byType(SingleChildScrollView).first);
      // Far right of the row, past the single pill: the blank part of the bar.
      await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
        reason: 'the header must not hand focus to any control',
      );
    });

    testWidgets('a header button tap does not take focus from the prompt', (
      tester,
    ) async {
      await fixture.mount(tester);
      fixture.pane.focusInput();
      await tester.pump();
      expect(fixture.pane.inputHasFocus, isTrue);

      // The header's own controls are chrome; tapping one must leave the caret
      // where it was rather than blurring the prompt.
      await tester.tap(find.byTooltip('终端操作'));
      await tester.pumpAndSettle();
      // Dismiss the opened menu without choosing anything.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(
        fixture.pane.inputHasFocus,
        isTrue,
        reason: 'header chrome must not steal focus from the prompt',
      );
    });

    testWidgets('touching the header neither activates nor collapses', (
      tester,
    ) async {
      var activated = 0;
      await fixture.mount(tester, onActivated: () => activated++);

      final bar = tester.getRect(find.byType(SingleChildScrollView).first);
      await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
      await tester.pumpAndSettle();

      // Activation focuses the prompt and raises the soft keyboard, so header
      // chrome (tabs, "more", collapse) must not trigger it.
      expect(activated, 0);
      // `collapsed` is owned by the caller; the pane must not flip it on its own
      // when header chrome is touched.
      expect(
        tester.widget<TerminalPane>(find.byType(TerminalPane)).collapsed,
        isFalse,
      );
    });
  });

  group('closing tabs', () {
    testWidgets('a single tab offers a close button', (tester) async {
      await fixture.mount(tester);

      expect(
        fixture.tabCloseFinder,
        findsOneWidget,
        reason: 'the only tab must still be closable',
      );
    });

    testWidgets('closing the only tab replaces it with a cleared session', (
      tester,
    ) async {
      await fixture.mount(tester);
      fixture.pane.focusInput();
      await tester.pump();
      expect(fixture.pane.inputHasFocus, isTrue);

      await tester.tap(fixture.tabCloseFinder);
      await tester.pumpAndSettle();

      // The pane must never end up with nothing to show: the closed session is
      // replaced by a fresh one, so the tab count is unchanged and the prompt is
      // cleared.
      expect(fixture.tabCloseFinder, findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // The caret moves to the fresh session's prompt; leaving no focused
      // input would let focus fall back to the editor and raise its IME.
      expect(
        fixture.pane.inputHasFocus,
        isTrue,
        reason: 'the replacement session must take the caret',
      );
    });

    testWidgets('closing one of several tabs removes it', (tester) async {
      await fixture.mount(tester);
      fixture.pane.addSession();
      await tester.pump();
      expect(fixture.pane.sessionCount, 2);

      await tester.tap(fixture.tabCloseFinder.first);
      await tester.pumpAndSettle();

      expect(fixture.pane.sessionCount, 1);
    });
  });
}

class _TabFixture {
  final directory = Directory.systemTemp.createTempSync('qfli_tab_');
  final auth = AuthStore();
  final key = GlobalKey<TerminalPaneState>();

  TerminalPaneState get pane => key.currentState!;

  /// The session pills sit inside the header's horizontal scroll view. A pill is
  /// the `ConstrainedBox` that caps each tab's width.
  Finder get allPills => find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(ConstrainedBox),
  );

  Finder get pillFinder => allPills.first;

  /// Only the per-tab close button lives inside the tab bar; the pane's own
  /// close button is a sibling of the scroll view.
  Finder get tabCloseFinder => find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byIcon(Icons.close),
  );

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(600, 300),
    VoidCallback? onActivated,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: TerminalPane(
                key: key,
                workingDirectory: directory.path,
                auth: auth,
                onlineEnabled: false,
                onActivated: onActivated,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void dispose() {
    auth.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
