import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/ai_panel.dart';
import 'package:qfli_studio_core/editor/editor_output_panel.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:re_editor/re_editor.dart';

/// Pad layout contract for the real [EditorPage].
///
/// These tests mount the actual page and measure rectangles from its render
/// objects. They never assert against a mock or a copy of the layout maths: a
/// regression that only exists in the real widget tree has to fail here.
///
/// The contract, stated once:
///
/// 1. Width >= 720 is wide. Below 720 the page keeps the phone layout: the file
///    tree moves to a drawer and no sidebar slot is laid out.
/// 2. On a wide page the sidebar occupies one horizontal slot and the full body
///    height. It never sits above the bottom panels.
/// 3. Every bottom panel (terminal, Problems, Output, AI) is laid out inside
///    the right-hand column. No panel may start left of the column's left edge,
///    so no panel can stretch underneath the sidebar.
/// 4. Focus mode (the collapsed editor) keeps the same panel placement and
///    still confines panels to the right column.
/// 5. A soft-keyboard inset shrinks the body; the page must keep the panel
///    inside the right column and must not overflow.
void main() {
  late Directory directory;
  late ProjectStore store;
  late Project project;
  // Created per test. A ChangeNotifier disposed in tearDown must never be
  // reused by the next test, so these cannot live at `main` scope.
  late AuthStore auth;
  late SettingsStore settings;
  StudioProfile? previous;

  setUp(() async {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'pad-layout-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
      // EditorProblemsBar renders its status entry only when an analyzer is
      // present. Without one the Problems panel is unreachable, so the layout
      // under test could not be opened at all.
      codeAnalyzer: _FakeAnalyzer(),
    );
    auth = AuthStore();
    settings = SettingsStore();
    directory = await Directory.systemTemp.createTemp('qfli_pad_layout_');
    Directory(p.join(directory.path, 'app', 'src')).createSync(recursive: true);
    File(
      p.join(directory.path, 'app', 'src', 'main.dart'),
    ).writeAsStringSync('void main() {\n  print(1);\n}\n');
    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync('{"projects": []}');
    store = ProjectStore(storageFile: registry);
    await store.load();
    await store.addExisting(p.join(directory.path, 'app'));
    project = store.projects.single;
  });

  tearDown(() async {
    StudioProfile.current = previous;
    // Each test that mounted a page unmounts it through `mount`'s teardown
    // before this runs, so no timer or listener can reach a disposed object
    // from here.
    auth.dispose();
    settings.dispose();
    store.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // A queued history write may still hold a handle on Windows.
    }
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Unmount the page before the stores are disposed. EditorPage owns timers
    // and listeners that would otherwise fire against a dead ChangeNotifier
    // while the next test sets up.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          initialOpenPath: p.join(project.path, 'src', 'main.dart'),
        ),
      ),
    );
    await _pumpUntil(tester, () => find.byType(CodeEditor).evaluate().isNotEmpty);
    // The sidebar reveal is an AnimatedAlign(200ms). Measuring before it
    // settles reads a half-width or zero-left column, which looks like a
    // layout failure but is only the animation mid-flight.
    await tester.pump(const Duration(milliseconds: 300));
  }

  Rect slot(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey<String>(key)));

  /// Expands the wide-layout sidebar when it is still in its default hidden
  /// state. The sidebar starts hidden by design, and `AnimatedAlign` needs the
  /// 200 ms reveal to finish before its rect is meaningful.
  Future<void> ensureSidebarVisible(WidgetTester tester) async {
    final open = find.byTooltip('打开文件树');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
      // The tap schedules setState. The next frame builds the new widthFactor
      // and only then does the reveal animation start, so it needs its own
      // pump before the duration is advanced.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    // The toggle must have actually flipped. `editor-sidebar-slot` alone is not
    // proof: the slot exists with zero width while the reveal is collapsed.
    expect(
      find.byTooltip('收起文件树'),
      findsOneWidget,
      reason: 'the wide sidebar must be expanded, not merely present',
    );
    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsOneWidget,
      reason: 'the wide sidebar must be present after expanding it',
    );
  }

  TerminalPaneState terminalState(WidgetTester tester) => tester
      .state<TerminalPaneState>(
        // The terminal is deliberately offstage while another panel is shown,
        // so the finder must look through offstage widgets.
        find.byType(TerminalPane, skipOffstage: false),
      );

  testWidgets('the 720 breakpoint decides between drawer and sidebar', (
    tester,
  ) async {
    await mount(tester, const Size(719, 900));
    // One pixel below the breakpoint: phone layout, no sidebar slot at all.
    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsNothing,
      reason: 'a 719 wide body must not lay out the sidebar slot',
    );
    expect(find.byType(FileExplorer), findsNothing);
    expect(tester.takeException(), isNull);

    await mount(tester, const Size(720, 900));
    // Exactly at the breakpoint: wide layout, the sidebar slot exists.
    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsOneWidget,
      reason: '720 is wide, so the sidebar slot must be laid out',
    );
    expect(find.byType(FileExplorer), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('below 720 the file tree opens in the drawer, not a sidebar', (
    tester,
  ) async {
    await mount(tester, const Size(600, 900));

    // Phone layout: the file tree is not inline.
    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsNothing,
    );
    expect(find.byType(FileExplorer), findsNothing);

    // The toolbar control opens the real drawer, which then holds the tree.
    await tester.tap(find.byTooltip('打开文件树'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FileExplorer), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsNothing,
      reason: 'the drawer must not create a wide-layout sidebar slot',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sidebar is full height and never overlaps the panels', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    await ensureSidebarVisible(tester);

    final column = slot(tester, 'editor-right-column');
    final body = slot(tester, 'editor-body-wide');
    final card = tester.getRect(find.byType(FileExplorer).first);

    // Full body height: the file tree is a vertical slot, not a strip above
    // the editor. The card is inset 12 px top and bottom.
    expect(
      card.height,
      closeTo(body.height - 24, 1.5),
      reason: 'the sidebar card must span the body height minus its margins',
    );

    // The card is exactly 300 px wide (Breakpoints.sidebarWidth), inset 12 px
    // on the left. A layout that stretches the sidebar by an extra margin must
    // fail here, not pass with a loosened expectation.
    expect(card.width, closeTo(300, 1.5));
    expect(card.left, closeTo(12, 1.5));

    // The right column starts after the card and its 12 px right margin. The
    // sidebar cell is 12 + 300 + 12 = 324 px, and nothing about it may move
    // the column further right.
    expect(
      card.right,
      lessThanOrEqualTo(column.left + 0.5),
      reason: 'the sidebar card must not extend into the right column',
    );
    expect(column.left, closeTo(324, 1.5));
  });

  testWidgets('Problems panel is laid out inside the right column', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    // Expand the sidebar first. With it collapsed the column spans the body,
    // so a panel inside the column proves nothing about the left slot.
    await ensureSidebarVisible(tester);
    await _openProblems(tester);

    final column = slot(tester, 'editor-right-column');
    final card = tester.getRect(find.byType(FileExplorer).first);
    final problems = tester.getRect(find.byType(EditorProblemsPanel));
    expect(
      problems.left,
      greaterThanOrEqualTo(column.left - 0.5),
      reason: 'the panel must start at or after the right column',
    );
    expect(problems.left, greaterThanOrEqualTo(card.right - 0.5));
    expect(problems.right, lessThanOrEqualTo(column.right + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Output panel is laid out inside the right column', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    await ensureSidebarVisible(tester);
    await _openPanelMenu(tester, 'Output · 输出');

    final column = slot(tester, 'editor-right-column');
    final card = tester.getRect(find.byType(FileExplorer).first);
    final output = tester.getRect(find.byType(EditorOutputPanel));
    expect(
      output.left,
      greaterThanOrEqualTo(column.left - 0.5),
      reason: 'the panel must start at or after the right column',
    );
    expect(output.left, greaterThanOrEqualTo(card.right - 0.5));
    expect(output.right, lessThanOrEqualTo(column.right + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the terminal panel is laid out inside the right column', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    await ensureSidebarVisible(tester);
    await _openPanelMenu(tester, '打开终端');

    final column = slot(tester, 'editor-right-column');
    final body = slot(tester, 'editor-body-wide');
    final card = tester.getRect(find.byType(FileExplorer).first);
    final terminal = tester.getRect(find.byType(TerminalPane));
    expect(
      terminal.left,
      greaterThanOrEqualTo(column.left - 0.5),
      reason: 'the panel must start at or after the right column',
    );
    expect(terminal.left, greaterThanOrEqualTo(card.right - 0.5));
    expect(terminal.right, lessThanOrEqualTo(column.right + 0.5));
    expect(terminal.top, greaterThanOrEqualTo(column.top - 0.5));
    // The sidebar keeps its full height while the terminal is open: the panel
    // shares the column, it does not take over the left slot or shorten it.
    expect(
      card.height,
      closeTo(body.height - 24, 1.5),
      reason: 'the sidebar stays full height while a panel is open',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the AI panel is laid out inside the right column', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    await ensureSidebarVisible(tester);
    await _openPanelMenu(tester, 'AI 助手');

    final column = slot(tester, 'editor-right-column');
    final card = tester.getRect(find.byType(FileExplorer).first);
    final ai = tester.getRect(find.byType(AiPanel));
    expect(
      ai.left,
      greaterThanOrEqualTo(column.left - 0.5),
      reason: 'the panel must start at or after the right column',
    );
    expect(ai.left, greaterThanOrEqualTo(card.right - 0.5));
    expect(ai.right, lessThanOrEqualTo(column.right + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide phone keeps the sidebar and refuses to overflow', (
    tester,
  ) async {
    // 800 is wide but not a Pad: the layout rule is width based, so the same
    // sidebar contract must hold and nothing may overflow vertically.
    await mount(tester, const Size(800, 600));
    await ensureSidebarVisible(tester);

    final column = slot(tester, 'editor-right-column');
    final card = tester.getRect(find.byType(FileExplorer).first);
    expect(card.right, lessThanOrEqualTo(column.left + 0.5));
    expect(tester.takeException(), isNull);

    await _openProblems(tester);
    final problems = tester.getRect(find.byType(EditorProblemsPanel));
    expect(problems.left, greaterThanOrEqualTo(column.left - 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus mode keeps panels inside the right column', (tester) async {
    // Focus mode is owned by an inline document contribution. The product's
    // editor calls `InlineDocumentRequest.setFocusMode` from one of its
    // actions, so the test builds the smallest contribution that exposes such
    // an action and fires it through the real toolbar button.
    StudioProfile.current = StudioProfile(
      id: 'pad-focus-test',
      appTitle: 'QFLIStudioN',
      templates: const [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
      codeAnalyzer: const _FakeAnalyzer(),
      supportedFileExtensions: const ['.dart'],
      inlineDocumentEditorFactory: (request) => _FocusDocumentEditor(request),
    );

    await mount(tester, const Size(1280, 900));
    // Expand the sidebar first, so entering focus mode is what removes it.
    await ensureSidebarVisible(tester);
    await _openPanelMenu(tester, 'Output · 输出');

    // Enter focus mode through the contribution's own action.
    final focusAction = find.byKey(
      const ValueKey<String>('inline-action-focus'),
    );
    expect(
      focusAction,
      findsOneWidget,
      reason: 'the inline document action must be reachable',
    );
    await tester.tap(focusAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // In focus mode the sidebar is not part of the body, so no slot exists.
    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsNothing,
      reason: 'focus mode drops the sidebar slot',
    );

    final column = slot(tester, 'editor-right-column');
    final output = tester.getRect(find.byType(EditorOutputPanel));
    expect(output.left, greaterThanOrEqualTo(column.left - 0.5));
    expect(output.right, lessThanOrEqualTo(column.right + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the terminal state survives panel switches and a resize', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));

    // Open the real terminal through its menu entry.
    await _openPanelMenu(tester, '打开终端');
    expect(
      find.byType(TerminalPane, skipOffstage: false),
      findsOneWidget,
    );
    final terminalBefore = terminalState(tester);

    // Switch to the AI panel. The terminal is kept, only offstage, so its
    // state object must be the same one.
    await _openPanelMenu(tester, 'AI 助手');
    expect(find.byType(AiPanel), findsOneWidget);
    expect(
      identical(terminalBefore, terminalState(tester)),
      isTrue,
      reason: 'switching to the AI panel must not recreate the terminal',
    );

    // Switch to Problems and back to the terminal. Every hop is checked so a
    // single dropped element cannot pass.
    await _openProblems(tester);
    expect(
      identical(terminalBefore, terminalState(tester)),
      isTrue,
      reason: 'switching to Problems must not recreate the terminal',
    );

    await _openPanelMenu(tester, '打开终端');
    expect(
      find.byType(TerminalPane, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      identical(terminalBefore, terminalState(tester)),
      isTrue,
      reason: 'returning to the terminal must reuse the same state',
    );

    // Cross the 720 breakpoint both ways. A Pad/phone resize must not rebuild
    // the terminal session either.
    tester.view.physicalSize = const Size(400, 800);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      identical(terminalBefore, terminalState(tester)),
      isTrue,
      reason: 'shrinking below 720 must not recreate the terminal',
    );

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      identical(terminalBefore, terminalState(tester)),
      isTrue,
      reason: 'growing past 720 must not recreate the terminal',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a keyboard inset keeps the panel inside the right column', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 900));
    await _openProblems(tester);

    final columnBefore = slot(tester, 'editor-right-column');

    // Simulate a soft keyboard: the inset shrinks the Scaffold body by 320px.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 300));

    final column = slot(tester, 'editor-right-column');
    expect(column.height, lessThan(columnBefore.height));
    expect(column.left, closeTo(columnBefore.left, 1.5));
    expect(column.right, closeTo(columnBefore.right, 1.5));

    // The panel keeps to the column and the page stays overflow free.
    if (find.byType(EditorProblemsPanel).evaluate().isNotEmpty) {
      final problems = tester.getRect(find.byType(EditorProblemsPanel));
      expect(problems.left, greaterThanOrEqualTo(column.left - 0.5));
      expect(problems.right, lessThanOrEqualTo(column.right + 0.5));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor state survives a phone to Pad resize', (tester) async {
    // Start narrow so the page builds the phone layout and the drawer path.
    await mount(tester, const Size(400, 800));
    final editorBefore = tester.state<State>(find.byType(CodeEditor));

    // Grow past the breakpoint: the same page must upgrade to wide layout
    // without rebuilding the editor element from scratch.
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('editor-sidebar-slot')),
      findsOneWidget,
    );
    final editorAfter = tester.state<State>(find.byType(CodeEditor));
    expect(
      identical(editorBefore, editorAfter),
      isTrue,
      reason: 'crossing the breakpoint must not recreate the editor state',
    );
    expect(tester.takeException(), isNull);
  });
}

/// Opens the Problems panel through its real status-bar trigger.
Future<void> _openProblems(WidgetTester tester) async {
  final status = find.byKey(const ValueKey<String>('editor-problems-status'));
  expect(status, findsOneWidget, reason: 'Problems status must be reachable');
  await tester.tap(status);
  await _pumpUntil(
    tester,
    () => find.byType(EditorProblemsPanel).evaluate().isNotEmpty,
  );
}

/// Opens a bottom panel through its real More-menu entry.
///
/// The finder is scoped to `PopupMenuItem` because several labels also appear
/// inside the panels themselves, and a bare `find.text` can match more than
/// one element or hit the popup barrier instead of the item.
Future<void> _openPanelMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多'));
  final entry = find.widgetWithText(PopupMenuItem<String>, label);
  await _pumpUntil(tester, () => entry.evaluate().isNotEmpty);
  // Let the popup route finish its open transition before tapping. Tapping a
  // mid-flight item lands on the modal barrier and silently does nothing.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(entry);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(entry);
  // Rebuild with the new panel selection, then let the popup route close.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: 'the editor operation did not finish');
}

/// Minimal analyzer. The Problems panel only needs a non-null analyzer to make
/// its status entry reachable. The content is irrelevant to layout.
class _FakeAnalyzer implements CodeAnalyzer {
  const _FakeAnalyzer();

  @override
  Future<CodeAnalysisResult> analyze(CodeAnalysisRequest request) async =>
      const CodeAnalysisResult();
}

/// Smallest inline document contribution that can toggle focus mode.
///
/// The page surfaces [actions] as toolbar buttons keyed by
/// `inline-action-<id>` and routes them through the real invoke path, so this
/// reaches focus mode the same way a product editor does.
class _FocusDocumentEditor extends InlineDocumentEditor {
  _FocusDocumentEditor(this.request);

  final InlineDocumentRequest request;

  @override
  Widget build(BuildContext context, Widget sourceEditor) => sourceEditor;

  @override
  List<InlineDocumentAction> get actions => <InlineDocumentAction>[
    InlineDocumentAction(
      id: 'focus',
      label: '专注模式',
      icon: Icons.fullscreen,
      invoke: (_) => request.setFocusMode(true),
    ),
  ];
}
