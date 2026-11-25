@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/editor/agent/agent_dock.dart';
import 'package:qfli_studio_core/editor/agent/agent_pane_switcher.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_output_panel.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/editor/editor_quick_bar.dart';
import 'package:qfli_studio_core/editor/symbols_bar.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:re_editor/re_editor.dart';

import 'support/fake_agent.dart';

void main() {
  late Directory root;
  late Project project;
  late ProjectStore store;
  late SettingsStore settings;
  late AuthStore auth;
  late LargeScreenController shell;
  late FakeAgentRuntime runtime;
  late HarnessHub hub;
  late _RecordingRunner runner;
  late StudioProfile? previousProfile;
  late Directory support;
  late PathProviderPlatform previousPaths;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('qfli_workbench_support_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(support.path);
    // Save reporting uses the application-owned service. Resolve its provider
    // timeout and real filesystem I/O outside the widget test's fake clock.
    await AppPaths.storageDirectory();
    await TaskActivityService.instance.initialize();
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousPaths;
    await support.delete(recursive: true);
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli_editor_workbench_');
    File(p.join(root.path, 'main.dart')).writeAsStringSync('void main() {}\n');
    File(
      p.join(root.path, 'other.dart'),
    ).writeAsStringSync('const other = 1;\n');
    project = Project.create(
      name: 'Workbench demo',
      path: root.path,
      language: 'Dart',
    );
    store = ProjectStore(storageFile: File(p.join(root.path, 'projects.json')));
    settings = SettingsStore(
      storageFile: File(p.join(root.path, 'settings.json')),
    );
    auth = AuthStore();
    shell = LargeScreenController();
    runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore());
    // No host discovery, native process probes or network access in this fixture.
    hub = HarnessHub(hosts: [], desktop: true);
    runner = _RecordingRunner();
    previousProfile = StudioProfile.current;
    StudioProfile.current = StudioProfile(
      id: 'editor-workbench-cleanup-test',
      appTitle: 'Editor test',
      templates: const [],
      productKey: StudioProductCatalog.qfliStudioKey,
      supportedFileExtensions: const ['.dart'],
      entryFileNames: const ['main.dart'],
      runner: runner,
    );
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    shell.dispose();
    hub.dispose();
    await runtime.fileEvents.close();
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Editor history writes can still be releasing a Windows handle.
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    bool workbench = true,
    bool agent = false,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    });
    Widget editor = EditorPage(
      project: project,
      auth: auth,
      store: store,
      settings: settings,
      initialOpenPath: p.join(root.path, 'main.dart'),
      onMinimize: () {},
      onClose: () {},
      agentEnabled: agent,
      agentRuntime: runtime,
      harnessHub: hub,
      ownsHarnessHub: false,
      composerDefaults: _MemoryDefaults(),
    );
    if (workbench) {
      editor = LargeScreenScope(controller: shell, child: editor);
    }
    await tester.pumpWidget(MaterialApp(home: editor));
    await _waitFor(tester, () => find.byType(CodeEditor).evaluate().isNotEmpty);
    await _frames(tester);
  }

  EditorController editor(WidgetTester tester) => tester
      .widget<EditorProblemsBar>(find.byType(EditorProblemsBar).first)
      .analysis
      .editor;

  Future<void> focusEditor(WidgetTester tester) async {
    editor(tester).current!.focusNode.requestFocus();
    await tester.pump();
  }

  testWidgets(
    'workbench hides duplicate chrome and follows symbol preference',
    (tester) async {
      await mount(tester);
      expect(find.byType(EditorQuickBar), findsNothing);
      expect(find.byType(SymbolsBar), findsNothing);
      expect(find.byTooltip('打开文件树'), findsNothing);
      expect(find.byTooltip('暂时收起编辑器'), findsNothing);
      expect(find.byIcon(Icons.undo), findsNothing);
      for (final id in ['terminal', 'output', 'problems', 'debug', 'ports']) {
        expect(find.byKey(ValueKey('workbench-panel-$id')), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('workbench-panel-buttons')),
        findsOneWidget,
      );

      final changed = settings.setLargeScreenSymbolBar(true);
      await _frames(tester);
      await changed;
      expect(find.byType(SymbolsBar), findsOneWidget);
      final hidden = settings.setLargeScreenSymbolBar(false);
      await _frames(tester);
      await hidden;
      expect(find.byType(SymbolsBar), findsNothing);

      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      for (final id in [
        'undo',
        'save',
        'find',
        'goto',
        'format',
        'git',
        'online_terminal',
        'close_editor',
      ]) {
        expect(find.byKey(ValueKey('workbench-menu-$id')), findsOneWidget);
      }
      for (final id in ['terminal', 'ai', 'settings', 'output', 'debug']) {
        expect(find.byKey(ValueKey('workbench-menu-$id')), findsNothing);
      }
      expect(
        find.byKey(const ValueKey('quick-fallback-terminal')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workbench save menu invokes the enabled editor action', (
    tester,
  ) async {
    await mount(tester);
    const changed = 'void main() { /* saved through menu */ }\n';
    editor(tester).current!.controller.text = changed;
    await tester.pump();
    expect(editor(tester).current!.dirty, isTrue);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-menu-save')));
    await _waitFor(tester, () => !editor(tester).current!.dirty);
    expect(File(p.join(root.path, 'main.dart')).readAsStringSync(), changed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone retains quick bar, symbols and editor navigation', (
    tester,
  ) async {
    await mount(tester, workbench: false, size: const Size(500, 900));
    expect(find.byType(EditorQuickBar), findsOneWidget);
    expect(find.byType(SymbolsBar), findsOneWidget);
    expect(find.byTooltip('打开文件树'), findsOneWidget);
    expect(find.byTooltip('暂时收起编辑器'), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-panel-buttons')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-screen scope still hides chrome below tablet width', (
    tester,
  ) async {
    await mount(tester, size: const Size(500, 900));
    expect(find.byType(EditorQuickBar), findsNothing);
    expect(find.byType(SymbolsBar), findsNothing);
    expect(find.byTooltip('打开文件树'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agent collapse releases all width and retains its pane', (
    tester,
  ) async {
    await mount(tester, agent: true);
    final column = find.byKey(const ValueKey('editor-right-column'));
    final collapsedWidth = tester.getSize(column).width;
    expect(find.byType(AgentDockRail), findsNothing);
    expect(find.byKey(const ValueKey('editor-agent-expand')), findsNothing);

    await focusEditor(tester);
    final selection = editor(tester).current!.controller.selection;
    await _shortcut(tester, LogicalKeyboardKey.keyL);
    await _frames(tester);
    expect(find.byType(AgentDock), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-agent-collapse')), findsNothing);
    expect(tester.getSize(column).width, closeTo(collapsedWidth - 400, 0.1));
    expect(
      editor(tester).current!.controller.selection,
      selection,
      reason: 'Ctrl+L must not be consumed by re_editor line selection',
    );
    final dock = tester.element(find.byType(AgentDock));

    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyL, meta: true);
    await _frames(tester);
    expect(tester.getSize(column).width, closeTo(collapsedWidth, 0.1));
    expect(find.byType(AgentDockRail), findsNothing);
    expect(
      tester.element(find.byType(AgentDock, skipOffstage: false)),
      same(dock),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium workbench switches Agent and editor in place', (
    tester,
  ) async {
    await mount(tester, agent: true, size: const Size(900, 900));
    expect(find.byType(AgentPaneSwitcher), findsOneWidget);
    final source = editor(tester).current!.controller;
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyL);
    await _frames(tester);
    expect(find.byType(CodeEditor), findsNothing);
    await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
    await _frames(tester);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(editor(tester).current!.controller, same(source));
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel shortcuts restore last panel and retain terminal state', (
    tester,
  ) async {
    await mount(tester);
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyJ);
    await _frames(tester);
    final terminal = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyJ);
    await _frames(tester);
    expect(find.byType(TerminalPane), findsNothing);

    await tester.tap(find.byKey(const ValueKey('workbench-panel-output')));
    await _frames(tester);
    expect(find.byType(EditorOutputPanel), findsOneWidget);
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyJ);
    await _frames(tester);
    expect(find.byType(EditorOutputPanel), findsNothing);
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyJ, meta: true);
    await _frames(tester);
    expect(find.byType(EditorOutputPanel), findsOneWidget);

    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.backquote);
    await _frames(tester);
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)),
      same(terminal),
    );
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.backquote, meta: true);
    await _frames(tester);
    expect(find.byType(TerminalPane), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal focus keeps W J L away from editor actions', (
    tester,
  ) async {
    await mount(tester, agent: true);
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.backquote);
    await _frames(tester);
    final terminal = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    terminal.requestInputFocus();
    await _frames(tester);
    expect(terminal.inputHasFocus, isTrue);
    for (final key in [
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyL,
    ]) {
      // The page must not even register these chords while the prompt owns focus.
      final pageShortcuts = find
          .descendant(
            of: find.byType(EditorPage),
            matching: find.byType(Shortcuts),
          )
          .first;
      final mapping = tester.widget<Shortcuts>(pageShortcuts).shortcuts;
      expect(mapping.containsKey(SingleActivator(key, control: true)), isFalse);
      expect(mapping.containsKey(SingleActivator(key, meta: true)), isFalse);
      await _shortcut(tester, key);
      await _frames(tester);
      expect(editor(tester).files, hasLength(1));
      expect(find.byType(TerminalPane), findsOneWidget);
      expect(find.byType(AgentDock), findsNothing);
      expect(terminal.inputHasFocus, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl and Cmd tab navigation wrap and close uses dirty guard', (
    tester,
  ) async {
    await mount(tester);
    final controller = editor(tester);
    final opening = controller.openPath(p.join(root.path, 'other.dart'));
    await _frames(tester);
    expect(await opening, isNull);
    expect(controller.currentIndex, 1);
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.tab);
    await _frames(tester);
    expect(controller.currentIndex, 0);
    await _shortcut(tester, LogicalKeyboardKey.tab, shift: true, meta: true);
    await _frames(tester);
    expect(controller.currentIndex, 1);
    controller.current!.controller.text = 'const changed = true;\n';
    await tester.pump();
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(find.text('未保存的更改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.files, hasLength(2));
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyW, meta: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存'));
    await _frames(tester);
    expect(controller.files, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new file shortcut creates and opens a file; F5 uses runner', (
    tester,
  ) async {
    await mount(tester);
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.text('新建文件'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'created');
    await tester.tap(find.text('创建'));
    await _waitFor(tester, () => editor(tester).files.length == 2);
    expect(editor(tester).current!.name, 'created.dart');
    expect(File(p.join(root.path, 'created.dart')).existsSync(), isTrue);
    await focusEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await _waitFor(tester, () => runner.entries.isNotEmpty);
    expect(runner.entries.single, p.join(root.path, 'main.dart'));
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool meta = false,
}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await _frames(tester, 1);
  }
  fail('Timed out waiting for editor I/O');
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

class _TrackedVisibility extends ValueNotifier<bool> {
  _TrackedVisibility(super.value);

  bool get listening => hasListeners;
}

class _MemoryDefaults implements ComposerDefaultsStore {
  final _values = <String, ComposerDefaults>{};

  @override
  Future<ComposerDefaults?> read(String projectId) async => _values[projectId];

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) async {
    _values[projectId] = defaults;
  }
}

class _RecordingRunner implements ProgramRunner {
  final entries = <String>[];

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    entries.add(entryFile);
    return ProgramRunResult(
      title: 'test run',
      stdout: const Stream.empty(),
      stderr: const Stream.empty(),
      exitCode: Future.value(0),
    );
  }
}
