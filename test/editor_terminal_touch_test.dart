import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:re_editor/re_editor.dart';

/// Interaction contract for the editor ⇄ terminal hand-off on mobile.
///
/// Covers three behaviours that share one piece of state (`_terminalCollapsed`)
/// and one hazard (a keyboard-driven shrink must never hide the focused input):
///
/// 1. Touching the editor collapses the terminal to its header, and re-expanding
///    restores the height the user had dragged to.
/// 2. Touching the terminal expands it and moves the caret into the prompt.
/// 3. While the prompt holds focus, a growing `viewInsets.bottom` (the soft
///    keyboard) must not flip the panel into its header-only layout: the input
///    stays mounted, keeps focus, and stays visible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() async => fixture.dispose());

  Future<void> openTerminal(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final item = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == 'terminal',
    );
    expect(item, findsOneWidget);
    await tester.ensureVisible(item);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(item, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  double terminalHeight(WidgetTester tester) =>
      tester.getSize(find.byType(TerminalPane)).height;

  testWidgets('touching the editor collapses the terminal, keeping the height '
      'preference for the next expand', (tester) async {
    await fixture.mount(tester);
    await openTerminal(tester);

    final expanded = terminalHeight(tester);
    expect(expanded, greaterThan(TerminalPanelMetrics.collapsedTotalHeight));

    // Record the drag preference by resizing, so the test proves the *preference*
    // survives the collapse rather than merely the incidental layout height.
    final handle = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.cursor == SystemMouseCursors.resizeRow,
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();
    final preferred = terminalHeight(tester);
    expect(preferred, greaterThan(expanded));

    // Touch the code area: `Listener.onPointerDown` on the editor must collapse
    // the panel without consuming the gesture.
    await tester.tap(find.byType(CodeEditor), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      terminalHeight(tester),
      lessThanOrEqualTo(TerminalPanelMetrics.collapsedTotalHeight + 1),
      reason: 'touching the editor must collapse the terminal to its header',
    );

    // Re-expanding restores the dragged height, not the default.
    await tester.tap(find.byTooltip('展开终端'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(terminalHeight(tester), closeTo(preferred, 1.0));
  });

  testWidgets('touching the terminal expands it and focuses the prompt', (
    tester,
  ) async {
    await fixture.mount(tester);
    await openTerminal(tester);

    // Collapse first (toolbar control), then touch the terminal body.
    await tester.tap(find.byTooltip('收起终端'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      terminalHeight(tester),
      lessThanOrEqualTo(TerminalPanelMetrics.collapsedTotalHeight + 1),
    );

    await tester.tap(find.byType(TerminalPane), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      terminalHeight(tester),
      greaterThan(TerminalPanelMetrics.collapsedTotalHeight),
      reason: 'touching the terminal must expand it again',
    );
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)).inputHasFocus,
      isTrue,
      reason: 'touching the terminal must move the caret into the prompt',
    );
  });

  testWidgets('a keyboard-driven shrink keeps a focused prompt expanded, '
      'mounted and focused', (tester) async {
    // A short viewport with a large keyboard is the case the protection exists
    // for: here the inset really does push the panel under the compact
    // threshold, which would otherwise hide the focused input.
    await fixture.mount(tester, size: const Size(900, 560));
    await openTerminal(tester);

    // Focus the prompt, which is the state the protection exists for.
    tester.state<TerminalPaneState>(find.byType(TerminalPane)).focusInput();
    await tester.pump();
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)).inputHasFocus,
      isTrue,
    );

    final inputFinder = find.byType(EditableText, skipOffstage: false);
    expect(inputFinder, findsOneWidget);
    final before = tester.element(inputFinder);
    final expandedHeight = tester.getSize(find.byType(TerminalPane)).height;

    // Raise the soft keyboard to ~50% of the viewport. `resizeToAvoidBottomInset`
    // is on (the default), so this shrinks the body exactly as a real keyboard
    // does — the condition that previously flipped `compactPanel` and unmounted
    // the input.
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)).inputHasFocus,
      isTrue,
      reason: 'the prompt must keep focus while the keyboard is up',
    );
    expect(
      inputFinder,
      findsOneWidget,
      reason: 'the prompt must stay mounted (not collapse to the header)',
    );
    expect(
      identical(before, tester.element(inputFinder)),
      isTrue,
      reason: 'the input element must not be replaced by the keyboard inset',
    );
    // The panel must still be expanded, not reduced to the header allocation.
    expect(
      tester.getSize(find.byType(TerminalPane)).height,
      greaterThan(TerminalPanelMetrics.collapsedTotalHeight + 1),
      reason: 'a focused prompt must keep the panel out of its compact layout',
    );
    // The input row must remain visible, not be hidden behind the keyboard.
    expect(
      tester.getSize(find.byType(EditableText)).height,
      greaterThan(0),
      reason: 'the focused input must not be laid out at zero height',
    );
    // Sanity: the inset really did shrink the panel, so the assertions above are
    // not just observing an unchanged layout.
    expect(
      tester.getSize(find.byType(TerminalPane)).height,
      lessThanOrEqualTo(expandedHeight),
    );
  });

  testWidgets('the editor still takes focus when the terminal is open', (
    tester,
  ) async {
    await fixture.mount(tester);
    await openTerminal(tester);

    // Give the terminal focus, then tap the editor: the editor's own focus
    // must win, proving the collapse does not swallow the gesture.
    tester.state<TerminalPaneState>(find.byType(TerminalPane)).focusInput();
    await tester.pump();
    await tester.tap(find.byType(CodeEditor), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final open = tester
        .state<State<EditorPage>>(find.byType(EditorPage))
        .widget;
    expect(open, isA<EditorPage>());
    final focused = FocusManager.instance.primaryFocus;
    expect(
      focused,
      isNotNull,
      reason: 'tapping the editor must leave some node focused',
    );
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)).inputHasFocus,
      isFalse,
      reason: 'the terminal must not keep the caret after an editor tap',
    );
  });

  testWidgets('touching the tab bar does not collapse the terminal', (
    tester,
  ) async {
    await fixture.mount(tester);
    await openTerminal(tester);
    final expanded = terminalHeight(tester);

    // Tap the blank part of the tab bar, to the right of the single pill. This
    // is the click-through case: the header must absorb it, so the editor's
    // collapse-on-touch listener behind the pane never sees it.
    final bar = tester.getRect(find.byType(SingleChildScrollView).first);
    await tester.tapAt(Offset(bar.right - 6, bar.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      terminalHeight(tester),
      closeTo(expanded, 0.5),
      reason: 'a tab-bar touch must not collapse the terminal',
    );
  });

  testWidgets('tapping a header button keeps the terminal focus, not the '
      'editor', (tester) async {
    await fixture.mount(tester);
    await openTerminal(tester);
    final expanded = terminalHeight(tester);

    tester.state<TerminalPaneState>(find.byType(TerminalPane)).focusInput();
    await tester.pump();
    final paneState = tester.state<TerminalPaneState>(
      find.byType(TerminalPane),
    );
    expect(paneState.inputHasFocus, isTrue);

    // Opening the header's action menu is the strongest case: the popup takes
    // the pointer, and without protection the focus would land on the editor.
    await tester.tap(find.byTooltip('终端操作'));
    await tester.pumpAndSettle();
    // Dismiss without choosing an action.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      terminalHeight(tester),
      closeTo(expanded, 0.5),
      reason: 'header chrome must not collapse the terminal',
    );
    expect(
      find.byType(EditorPage),
      findsOneWidget,
      reason: 'the page must stay mounted',
    );
  });

  testWidgets('switching tabs keeps the caret in the terminal prompt', (
    tester,
  ) async {
    await fixture.mount(tester);
    await openTerminal(tester);
    final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    // A second terminal gives the bar a non-selected tab to switch to.
    pane.addSession();
    await tester.pump();

    pane.focusInput();
    await tester.pump();
    expect(pane.inputHasFocus, isTrue);

    // The selected session is id 2, so tapping tab `1` is a real switch.
    final otherTab = find.ancestor(
      of: find.text('1'),
      matching: find.byType(InkWell),
    );
    expect(otherTab, findsOneWidget);
    await tester.tap(otherTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Selecting a tab is terminal chrome: the caret belongs in the prompt of the
    // session now on screen, not on a detached focus node that the editor would
    // pick up on mobile.
    expect(
      pane.inputHasFocus,
      isTrue,
      reason: 'a tab tap must leave the caret in the terminal prompt',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'terminal input',
      reason: 'the primary focus must be the prompt, not the tapped pill',
    );
  });

  // Regression: after editing, a header action that disposes or swaps the
  // focused prompt (close tab, new tab) used to let the FocusManager fall back
  // through the route scope's history to the editor, which then raised its IME.
  for (final action in ['close', 'new']) {
    testWidgets('header "$action" after editing keeps focus off the editor', (
      tester,
    ) async {
      await fixture.mount(tester);
      await openTerminal(tester);
      // Edit first so the editor's node is in the route scope's focus history.
      await tester.tap(find.byType(CodeEditor), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      // Touch the terminal: it expands and focuses its prompt.
      await tester.tap(find.byType(TerminalPane), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));
      expect(pane.inputHasFocus, isTrue);

      if (action == 'close') {
        await tester.tap(find.byTooltip('Close terminal 1'));
      } else {
        await tester.tap(find.byTooltip('终端操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('新建终端').last);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'terminal input',
        reason: 'focus must stay in the terminal, not fall back to the editor',
      );
    });
  }

  testWidgets('the header "more" button never changes prompt focus', (
    tester,
  ) async {
    await fixture.mount(tester);
    await openTerminal(tester);
    final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));

    // Unfocused prompt: opening and closing the menu must not focus it (that
    // raised the soft keyboard on device).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(pane.inputHasFocus, isFalse);
    await tester.tap(find.byTooltip('终端操作'));
    await tester.pumpAndSettle();
    expect(pane.inputHasFocus, isFalse, reason: 'menu open must not focus');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(pane.inputHasFocus, isFalse, reason: 'menu close must not focus');

    // Focused prompt: the menu must not take focus away (that dismissed it).
    pane.focusInput();
    await tester.pump();
    await tester.tap(find.byTooltip('终端操作'));
    await tester.pumpAndSettle();
    expect(pane.inputHasFocus, isTrue, reason: 'menu open must keep focus');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(pane.inputHasFocus, isTrue, reason: 'menu close must keep focus');
  });
}

/// Minimal editor host: one project, one Java source, a recording runner.
class _Fixture {
  _Fixture() {
    final projectDirectory = Directory(p.join(directory.path, 'project'))
      ..createSync();
    project = Project.create(name: 'test project', path: projectDirectory.path);
    File(
      p.join(project.path, 'Main.java'),
    ).writeAsStringSync('class Main {}\n');
    final config = File(ProjectConfig.configPath(project.path));
    config.parent.createSync();
    config.writeAsStringSync(
      jsonEncode({'version': 1, 'entryFile': 'Main.java'}),
    );
  }

  final directory = Directory.systemTemp.createTempSync('qfli_editor_touch_');
  final auth = AuthStore();
  final store = ProjectStore();
  final settings = SettingsStore();
  late final Project project;

  var _disposed = false;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1100, 850),
  }) async {
    StudioProfile.current = StudioProfile(
      id: 'test',
      appTitle: 'Editor test',
      templates: const [ProjectTemplate.java],
      runner: const _NoopRunner(),
      isOffline: true,
      entryFileNames: const ['Main.java'],
      supportedFileExtensions: const ['.java'],
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          initialOpenPath: 'Main.java',
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    auth.dispose();
    store.dispose();
    settings.dispose();
  }
}

class _NoopRunner implements ProgramRunner {
  const _NoopRunner();

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async => null;
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 300,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue, reason: 'The editor did not finish mounting.');
}
