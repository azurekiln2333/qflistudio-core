@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
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
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/editor_selection_toolbar.dart';
import 'package:qfli_studio_core/editor/symbols_bar.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/harness_session_target.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/hub_chat_view.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/shortcut_label.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';
import 'package:re_editor/re_editor.dart';

import 'support/fake_agent.dart';
import 'support/fake_harness_host.dart';

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
    Brightness brightness = Brightness.light,
    double? editorWidth,
    ValueNotifier<bool>? retainedVisibility,
    ValueNotifier<bool>? centerVisible,
    AppFormFactor? formFactor,
    HarnessHub? suppliedHub,
    HarnessSessionTarget? target,
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
      retainedVisibility: retainedVisibility,
      agentEnabled: agent,
      agentRuntime: runtime,
      harnessHub: suppliedHub ?? hub,
      initialHarnessSession: target,
      ownsHarnessHub: false,
      composerDefaults: _MemoryDefaults(),
    );
    if (workbench) {
      editor = LargeScreenScope(
        controller: shell,
        formFactor: formFactor,
        child: editor,
      );
    }
    if (editorWidth != null) {
      editor = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: editorWidth, child: editor),
      );
    }
    if (centerVisible != null) {
      editor = ValueListenableBuilder<bool>(
        valueListenable: centerVisible,
        child: editor,
        builder: (context, visible, child) => Offstage(
          offstage: !visible,
          child: TickerMode(enabled: visible, child: child!),
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: workbench
            ? ThemeData(colorSchemeSeed: Colors.indigo, brightness: brightness)
            : null,
        home: editor,
      ),
    );
    await _waitFor(tester, () => find.byType(CodeEditor).evaluate().isNotEmpty);
    await _frames(tester);
  }

  EditorController editor(WidgetTester tester) {
    // R21/V5: the workbench owns a single status bar instead of the phone
    // EditorProblemsBar. Both presentations still observe the same controller.
    final problems = find.byType(EditorProblemsBar);
    if (problems.evaluate().isNotEmpty) {
      return tester.widget<EditorProblemsBar>(problems.first).analysis.editor;
    }
    return tester
        .widgetList<ListenableBuilder>(
          find.descendant(
            of: find.byType(EditorPage),
            matching: find.byType(ListenableBuilder),
          ),
        )
        .map((builder) => builder.listenable)
        .whereType<EditorController>()
        .first;
  }

  Future<void> focusEditor(WidgetTester tester) async {
    editor(tester).current!.focusNode.requestFocus();
    await tester.pump();
  }

  // Keep the desktop platform for the whole callback, not just mount().
  // Restoring Android while the editor is alive changes EditorBottomInset's
  // wrapper topology on the next rebuild and reparents its GlobalKey subtree.
  // The variant restores the override before the binding's invariant checks.
  void desktopTest(String description, WidgetTesterCallback callback) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(
        Platform.isMacOS
            ? TargetPlatform.macOS
            : Platform.isWindows
            ? TargetPlatform.windows
            : TargetPlatform.linux,
      ),
    );
  }

  desktopTest(
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

  desktopTest('workbench save menu invokes the enabled editor action', (
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

  desktopTest('large-screen scope still hides chrome below tablet width', (
    tester,
  ) async {
    await mount(tester, size: const Size(500, 900));
    expect(find.byType(EditorQuickBar), findsNothing);
    expect(find.byType(SymbolsBar), findsNothing);
    expect(find.byTooltip('打开文件树'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  desktopTest('Agent collapse releases all width and retains its pane', (
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

  desktopTest(
    'R2/R20: an existing workbench editor follows a replacement shared hub',
    (tester) async {
      await mount(tester, agent: true);
      final before = tester.state(find.byType(EditorPage));
      final source = editor(tester).current!.controller;
      final session = HarnessSessionInfo(
        id: 'existing',
        hostId: 'local',
        providerId: 'pi',
        title: 'Existing project session',
        status: HarnessSessionStatus.idle,
        capabilities: const {HarnessCapability.transcript},
        cwd: root.path,
      );
      final handle = FakeSessionHandle(info: session);
      final replacement = HarnessHub(
        hosts: [
          FakeHarnessHost(
            id: 'local',
            label: 'Local',
            kind: HarnessHostKind.local,
            initialSessions: [session],
            openHandler: (_) async => handle,
          ),
        ],
        desktop: true,
      );
      addTearDown(() => replacement.dispose());
      await mount(
        tester,
        agent: true,
        suppliedHub: replacement,
        target: const HarnessSessionTarget(
          hostId: 'local',
          sessionId: 'existing',
        ),
      );
      await _waitFor(tester, () => identical(replacement.activeHandle, handle));
      expect(tester.state(find.byType(EditorPage)), same(before));
      expect(editor(tester).current!.controller, same(source));
      expect(find.byType(HubChatView), findsOneWidget);
      expect(hub.activeHandle, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  desktopTest(
    'R21/R23: injected tablet keeps touch chrome and Agent separator',
    (tester) async {
      await mount(
        tester,
        agent: true,
        size: const Size(1440, 900),
        formFactor: AppFormFactor.tablet,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('workbench-editor-title-bar')))
            .height,
        48,
      );
      await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
      await _frames(tester);
      final separator = find.byKey(const ValueKey('agent-pane-resize-handle'));
      final pane = find.byKey(const ValueKey('workbench-agent-pane'));
      expect(tester.getSize(separator).width, 48);
      expect(tester.getSize(separator).width + tester.getSize(pane).width, 400);
      await tester.tap(find.byKey(const ValueKey('workbench-editor-more')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('workbench-menu-save')))
            .height,
        48,
      );
      expect(tester.takeException(), isNull);
    },
  );

  desktopTest('medium workbench switches Agent and editor in place', (
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

  desktopTest('panel shortcuts restore last panel and retain terminal state', (
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

  desktopTest('terminal focus keeps W J L away from editor actions', (
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

  desktopTest('Ctrl and Cmd tab navigation wrap and close uses dirty guard', (
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

  // R21/V4–V9, R23/R24: visual and interaction regressions run in cloud CI.
  for (final size in [const Size(1440, 900), const Size(1024, 768)]) {
    for (final brightness in Brightness.values) {
      desktopTest('MD3 editor chrome ${size.width} ${brightness.name}', (
        tester,
      ) async {
        Directory(p.join(root.path, '.git')).createSync();
        File(
          p.join(root.path, '.git', 'HEAD'),
        ).writeAsStringSync('ref: refs/heads/workbench\n');
        await mount(tester, size: size, brightness: brightness);
        expect(find.byType(AppBar), findsNothing);
        expect(find.text(project.name), findsNothing);
        expect(find.byType(TabBar), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('workbench-editor-title-bar')))
              .height,
          AppPaths.isDesktop ? 40 : 48,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('workbench-editor-status')))
              .height,
          AppPaths.isDesktop ? 24 : 48,
        );
        final tab = find.byKey(
          ValueKey('workbench-tab-${p.join(root.path, 'main.dart')}'),
        );
        expect(tester.getSize(tab).height, 36);
        final scheme = Theme.of(tester.element(tab)).colorScheme;
        expect(tester.widget<Material>(tab).color, scheme.surface);
        final border =
            tester
                    .widgetList<Container>(
                      find.descendant(
                        of: tab,
                        matching: find.byType(Container),
                      ),
                    )
                    .map((container) => container.decoration)
                    .whereType<BoxDecoration>()
                    .first
                    .border!
                as Border;
        expect(border.bottom.width, 2);
        expect(border.bottom.color, scheme.primary);
        await _waitFor(
          tester,
          () => find.text('workbench').evaluate().isNotEmpty,
        );
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('workbench-status-branch')))
              .dx,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('workbench-panel-buttons')),
                )
                .dx,
          ),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('workbench-panel-terminal')))
              .height,
          AppPaths.isDesktop ? 24 : 48,
        );
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsWidgets);
        final save = tester.widget<MenuItemButton>(
          find.byKey(const ValueKey('workbench-menu-save')),
        );
        expect(save.shortcut, isA<SingleActivator>());
        final shortcut = save.shortcut! as SingleActivator;
        expect(shortcut.trigger, LogicalKeyboardKey.keyS);
        expect(shortcut.control, !Platform.isMacOS);
        expect(shortcut.meta, Platform.isMacOS);
        expect(find.text('保存'), findsOneWidget);
        // MenuItemButton paints a separate shortcut column, not a suffix in the label.
        expect(
          find.textContaining('Ctrl+S'),
          Platform.isMacOS ? findsNothing : findsOneWidget,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('workbench-menu-save')))
              .height,
          AppPaths.isDesktop ? 32 : 48,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _frames(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  desktopTest(
    'IDE tabs show dirty dots and hover close with guarded context actions',
    (tester) async {
      await mount(tester);
      final controller = editor(tester);
      final mainPath = p.join(root.path, 'main.dart');
      final otherPath = p.join(root.path, 'other.dart');
      await tester.runAsync(() => controller.openPath(otherPath));
      await _frames(tester);
      final inactive = find.byKey(ValueKey('workbench-tab-$mainPath'));
      final active = find.byKey(ValueKey('workbench-tab-$otherPath'));
      final scheme = Theme.of(tester.element(inactive)).colorScheme;
      expect(tester.widget<Material>(inactive).color, scheme.surfaceContainer);
      expect(
        find.byKey(ValueKey('workbench-tab-close-$mainPath')),
        findsNothing,
      );
      controller.current!.controller.text = 'const other = 2;\n';
      await tester.pump();
      expect(
        find.byKey(ValueKey('workbench-tab-dirty-$otherPath')),
        findsOneWidget,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(0, 500));
      await mouse.moveTo(tester.getCenter(active));
      await tester.pump();
      expect(
        find.byKey(ValueKey('workbench-tab-dirty-$otherPath')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('workbench-tab-close-$otherPath')),
        findsOneWidget,
      );
      await mouse.moveTo(const Offset(0, 500));
      await mouse.removePointer();
      await tester.pump();
      await tester.tap(active, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final close = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('workbench-tab-menu-close_this')),
      );
      expect(
        (close.shortcut! as SingleActivator).trigger,
        LogicalKeyboardKey.keyW,
      );
      await tester.tap(
        find.byKey(const ValueKey('workbench-tab-menu-close_this')),
      );
      await tester.pumpAndSettle();
      expect(find.text('未保存的更改'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.files, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  desktopTest('Agent separator clamps width, resets and retains the dock', (
    tester,
  ) async {
    await mount(tester, agent: true, size: const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
    await _frames(tester);
    final handle = find.byKey(const ValueKey('agent-pane-resize-handle'));
    final slot = find.byKey(const ValueKey('workbench-agent-pane'));
    final dock = tester.element(find.byType(AgentDock));
    final column = find.byKey(const ValueKey('editor-right-column'));
    expect(tester.getSize(slot).width + tester.getSize(handle).width, 400);
    expect(
      tester
          .widget<MouseRegion>(
            find
                .descendant(of: handle, matching: find.byType(MouseRegion))
                .first,
          )
          .cursor,
      SystemMouseCursors.resizeColumn,
    );
    Future<void> dragBy(double dx) async {
      final gesture = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      // The first move wins the drag arena against double-tap. With the
      // default DragStartBehavior.start it is not an onUpdate displacement.
      await gesture.moveBy(Offset(dx.sign * 24, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      await gesture.up();
      await _frames(tester);
    }

    await dragBy(-1000);
    expect(tester.getSize(slot).width + 8, 720);
    expect(tester.getSize(column).width, greaterThan(0));
    await dragBy(1000);
    expect(tester.getSize(slot).width + 8, 320);
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(handle);
    await _frames(tester);
    expect(tester.getSize(slot).width + 8, 400);
    expect(tester.element(find.byType(AgentDock)), same(dock));
    await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
    await _frames(tester);
    expect(handle, findsNothing);
    expect(tester.getSize(slot).width, 0);
    expect(tester.takeException(), isNull);
  });

  desktopTest(
    'Agent width yields space to a narrow center without a second editor',
    (tester) async {
      await mount(tester, agent: true, editorWidth: 600);
      final source = editor(tester).current!.controller;
      await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
      await _frames(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-right-column'))).width,
        240,
      );
      expect(
        tester
                .getSize(find.byKey(const ValueKey('workbench-agent-pane')))
                .width +
            8,
        360,
      );
      expect(find.byType(CodeEditor), findsOneWidget);
      expect(editor(tester).current!.controller, same(source));
      expect(tester.takeException(), isNull);
    },
  );

  desktopTest('empty editor actions show shortcuts and keep shell ownership', (
    tester,
  ) async {
    await mount(tester, agent: true);
    editor(tester).closeAll();
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('workbench-editor-empty')),
      findsOneWidget,
    );
    for (final shortcut in ['Ctrl+N', 'Ctrl+Shift+E', 'Ctrl+L', 'Ctrl+`']) {
      expect(find.text(shortcutLabel(shortcut)), findsOneWidget);
    }
    final owner = shell.activeEditor;
    await tester.tap(find.byKey(const ValueKey('workbench-empty-explorer')));
    await tester.pump();
    expect(shell.activeEditor, same(owner));
    expect(shell.sidebarVisible, isTrue);
    expect(shell.activity.name, anyOf('files', 'explorer'));
    expect(find.byType(EditorPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workbench-empty-new')));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('新建文件')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-empty-new')),
      findsOneWidget,
      reason: 'The empty-state action remains mounted behind the dialog.',
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final close in ['current', 'all', 'deleted']) {
    desktopTest(
      'closing $close tabs during an Agent breakpoint move releases hover routes',
      (tester) async {
        final router = GestureBinding.instance.pointerRouter;
        final routesBeforeMount = router.debugGlobalRouteCount;
        await mount(tester, agent: true, size: const Size(1440, 900));
        final controller = editor(tester);
        final closed = controller.current!;
        final page = tester.state(find.byType(EditorPage));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 500));
        final tab = find.byKey(ValueKey('workbench-tab-${closed.path}'));
        final closeButton = find.byKey(
          ValueKey('workbench-tab-close-${closed.path}'),
        );
        expect(tab, findsOneWidget);
        await mouse.moveTo(tester.getCenter(closeButton));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);

        // The GlobalKey column reattaches its old render tree before updating
        // its children at this breakpoint. Closed resources must survive that
        // reconciliation even though the public model is already empty.
        tester.view.physicalSize = const Size(900, 900);
        switch (close) {
          case 'current':
            controller.closeAt(controller.currentIndex);
          case 'all':
            controller.closeAll();
          case 'deleted':
            controller.closePathsUnder(closed.path);
        }
        expect(controller.files, isEmpty);
        expect(controller.current, isNull);
        expect(
          ChangeNotifier.debugAssertNotDisposed(closed.diagnostics!),
          isTrue,
        );
        closed.controller.text = '// late notification from a retired buffer\n';
        expect(closed.dirty, isFalse);
        expect(closed.revision, 0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _frames(tester);
        expect(tester.state(find.byType(EditorPage)), same(page));
        expect(find.byType(AgentPaneSwitcher), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workbench-editor-empty')),
          findsOneWidget,
        );
        expect(find.byType(CodeEditor), findsNothing);
        expect(
          () => ChangeNotifier.debugAssertNotDisposed(closed.diagnostics!),
          throwsFlutterError,
          reason:
              'Release closed diagnostics after render-tree reconciliation.',
        );

        // Exercise real pointer routing after close, then reopen the same path
        // and hover its new close control before tearing down the whole page.
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('workbench-editor-more'))),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byKey(const ValueKey('workbench-empty-new')));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        await tester.tap(
          find.descendant(of: dialog, matching: find.text('取消')),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() => controller.openPath(closed.path));
        await _frames(tester);
        expect(controller.current, isNot(same(closed)));
        expect(find.byType(CodeEditor), findsOneWidget);
        await mouse.moveTo(
          tester.getCenter(
            find.byKey(ValueKey('workbench-tab-close-${closed.path}')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await mouse.moveTo(const Offset(0, 500));
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await _frames(tester);
        expect(router.debugGlobalRouteCount, routesBeforeMount);
        await tester.tapAt(const Offset(10, 10));
        expect(tester.takeException(), isNull);
      },
    );
  }

  desktopTest('selection context menu floats without replacing title tabs', (
    tester,
  ) async {
    final router = GestureBinding.instance.pointerRouter;
    final routesBeforeMount = router.debugGlobalRouteCount;
    await mount(tester);
    final controller = editor(tester).current!.controller;
    controller.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 4,
    );
    await tester.pump();
    expect(find.byType(SelectionToolbarBar), findsNothing);
    expect(
      find.byKey(const ValueKey('workbench-editor-title-bar')),
      findsOneWidget,
    );
    final source = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final visibility = ValueNotifier(true);
    source.toolbarController!.show(
      context: tester.element(find.byType(CodeEditor)),
      controller: controller,
      anchors: const TextSelectionToolbarAnchors(
        primaryAnchor: Offset(300, 300),
      ),
      layerLink: LayerLink(),
      visibility: visibility,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench-selection-menu')),
      findsOneWidget,
    );
    expect(find.text('复制'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(
      source.toolbarController,
      isNot(isA<MobileSelectionToolbarController>()),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 500));
    await mouse.moveTo(tester.getCenter(find.text('复制')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('workbench-selection-menu')),
      findsNothing,
    );
    // A real desktop secondary click supplies anchors but no renderRect.
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodeEditor)) + const Offset(100, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench-selection-menu')),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(controller.selectedText, controller.text);
    expect(
      find.byKey(const ValueKey('workbench-selection-menu')),
      findsNothing,
    );
    await mouse.moveTo(const Offset(0, 500));
    await mouse.removePointer();
    visibility.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    expect(router.debugGlobalRouteCount, routesBeforeMount);
    await tester.tapAt(const Offset(10, 10));
    expect(tester.takeException(), isNull);
  });

  desktopTest('workbench file tree is flat, compact and follows current file', (
    tester,
  ) async {
    final controller = EditorController(project: project);
    await tester.runAsync(
      () => controller.openPath(p.join(root.path, 'main.dart')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: FileExplorer(
              largeScreen: true,
              project: project,
              editor: controller,
              store: store,
              settings: settings,
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    final mainRow = find.byKey(
      ValueKey('file-row-${p.join(root.path, 'main.dart')}'),
    );
    final otherRow = find.byKey(
      ValueKey('file-row-${p.join(root.path, 'other.dart')}'),
    );
    await _waitFor(tester, () => mainRow.evaluate().isNotEmpty);
    expect(find.byType(Card), findsNothing);
    expect(tester.getSize(mainRow).height, AppPaths.isDesktop ? 28 : 40);
    final ink = find.descendant(of: mainRow, matching: find.byType(Ink)).first;
    final scheme = Theme.of(tester.element(mainRow)).colorScheme;
    final decoration = tester.widget<Ink>(ink).decoration! as BoxDecoration;
    expect(decoration.color, scheme.secondaryContainer);
    expect(decoration.borderRadius, BorderRadius.zero);
    final mainLeft = tester.getTopLeft(mainRow).dx;
    final listLeft = tester.getTopLeft(find.byType(ListView)).dx;
    expect(mainLeft, listLeft);
    await tester.tap(otherRow);
    await _waitFor(tester, () => controller.current?.name == 'other.dart');
    await tester.pump();
    expect(
      (tester.widget<Ink>(ink).decoration! as BoxDecoration).color,
      isNull,
    );
    final selectedInk = find
        .descendant(of: otherRow, matching: find.byType(Ink))
        .first;
    expect(
      (tester.widget<Ink>(selectedInk).decoration! as BoxDecoration).color,
      scheme.secondaryContainer,
    );
    expect(tester.takeException(), isNull);
  });

  // Review regressions: these tests are authored for cloud CI, not run locally.
  desktopTest('source shortcuts remain owned by the editor without an Agent', (
    tester,
  ) async {
    await mount(tester);
    final source = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final bindings = source.shortcutsActivatorsBuilder!;
    const defaults = DefaultCodeShortcutsActivatorsBuilder();
    for (final type in CodeShortcutType.values) {
      expect(
        bindings.build(type),
        type == CodeShortcutType.save ? isEmpty : equals(defaults.build(type)),
        reason: 'Only save delegates to the page when no Agent is installed',
      );
    }
    final controller = editor(tester).current!.controller;
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 5,
    );
    await focusEditor(tester);
    expect(editor(tester).current!.focusNode.hasFocus, isTrue);
    final sourceShortcuts = tester.widgetList<Shortcuts>(
      find.descendant(
        of: find.byType(CodeEditor),
        matching: find.byType(Shortcuts),
      ),
    );
    expect(
      sourceShortcuts.any(
        (shortcuts) => shortcuts.shortcuts.values.any(
          (intent) => intent is CodeShortcutLineSelectIntent,
        ),
      ),
      isTrue,
      reason: 'Exercise the desktop shortcut tree, not the mobile fallback.',
    );
    await _shortcut(tester, LogicalKeyboardKey.keyL, meta: Platform.isMacOS);
    await _frames(tester);
    expect(controller.selection.isCollapsed, isFalse);
    expect(controller.selectedText, contains('void main()'));
    expect(tester.takeException(), isNull);
  });

  desktopTest('save shortcuts reach page persistence from focused code', (
    tester,
  ) async {
    await mount(tester);
    for (final meta in [false, true]) {
      final changed = 'void main() { /* keyboard save $meta */ }\n';
      editor(tester).current!.controller.text = changed;
      await tester.pump();
      expect(editor(tester).current!.dirty, isTrue);
      await focusEditor(tester);
      await _shortcut(tester, LogicalKeyboardKey.keyS, meta: meta);
      await _waitFor(tester, () => !editor(tester).current!.dirty);
      expect(File(p.join(root.path, 'main.dart')).readAsStringSync(), changed);
    }
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1440, 900), const Size(900, 900)]) {
    desktopTest(
      'More retains Agent new and stop-all actions at ${size.width}',
      (tester) async {
        final session = await runtime.sessions.create(project.id);
        await mount(tester, agent: true, size: size);
        await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
        await _frames(tester);
        await tester.tap(find.byKey(const ValueKey('workbench-editor-more')));
        await tester.pumpAndSettle();
        final stop = find.byKey(const ValueKey('workbench-menu-agent-stop'));
        expect(tester.widget<MenuItemButton>(stop).onPressed, isNull);
        // Enablement must update even while the menu is already open.
        runtime.liveStatuses[session.id] = AgentLiveStatus.running;
        runtime.notifyLive();
        await tester.pump();
        expect(tester.widget<MenuItemButton>(stop).onPressed, isNotNull);
        await tester.tap(stop);
        await _frames(tester);
        expect(runtime.cancelAllCount, 1);
        final count = runtime.sessions.sessionsOf(project.id).length;
        await tester.tap(find.byKey(const ValueKey('workbench-editor-more')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('workbench-menu-agent-new-session')),
        );
        await _frames(tester);
        expect(runtime.sessions.sessionsOf(project.id), hasLength(count + 1));
        expect(find.byType(EditorQuickBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final hideWithTicker in [false, true]) {
    desktopTest(
      'selection menu closes when retained center hides ($hideWithTicker)',
      (tester) async {
        final visible = ValueNotifier(true);
        final toolbarVisible = _TrackedVisibility(true);
        await mount(
          tester,
          retainedVisibility: hideWithTicker ? null : visible,
          centerVisible: hideWithTicker ? visible : null,
        );
        final source = tester.widget<CodeEditor>(find.byType(CodeEditor));
        source.toolbarController!.show(
          context: tester.element(find.byType(CodeEditor)),
          controller: editor(tester).current!.controller,
          anchors: const TextSelectionToolbarAnchors(
            primaryAnchor: Offset(300, 300),
          ),
          layerLink: LayerLink(),
          visibility: toolbarVisible,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workbench-selection-menu')),
          findsOneWidget,
        );
        visible.value = false;
        await _frames(tester);
        expect(
          find.byKey(const ValueKey('workbench-selection-menu')),
          findsNothing,
        );
        expect(toolbarVisible.listening, isFalse);
        visible.value = true;
        await _frames(tester);
        expect(find.byType(CodeEditor), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await _frames(tester);
        visible.dispose();
        toolbarVisible.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  desktopTest('medium Agent switch closes the editor selection menu', (
    tester,
  ) async {
    await mount(tester, agent: true, size: const Size(900, 900));
    final source = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final visibility = _TrackedVisibility(true);
    source.toolbarController!.show(
      context: tester.element(find.byType(CodeEditor)),
      controller: editor(tester).current!.controller,
      anchors: const TextSelectionToolbarAnchors(
        primaryAnchor: Offset(300, 300),
      ),
      layerLink: LayerLink(),
      visibility: visibility,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench-selection-menu')),
      findsOneWidget,
    );
    await focusEditor(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyL);
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('workbench-selection-menu')),
      findsNothing,
    );
    expect(visibility.listening, isFalse);
    visibility.dispose();
    expect(tester.takeException(), isNull);
  });

  desktopTest('constrained Agent resize follows its visible separator', (
    tester,
  ) async {
    await mount(tester, agent: true, editorWidth: 600);
    await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
    await _frames(tester);
    final handle = find.byKey(const ValueKey('agent-pane-resize-handle'));
    final slot = find.byKey(const ValueKey('workbench-agent-pane'));
    expect(tester.getSize(slot).width + 8, 360);
    final start = tester.getCenter(handle);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    // Cross slop first, then measure an in-progress 12dp movement. Starting
    // from the hidden 400dp preference incorrectly leaves the separator still.
    final before = tester.getCenter(handle).dx;
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    expect(tester.getCenter(handle).dx - before, closeTo(12, 0.1));
    await gesture.up();
    await _frames(tester);
    expect(tester.getSize(slot).width + 8, inInclusiveRange(320, 348));
    expect(tester.takeException(), isNull);
  });

  desktopTest('problem count is read-only beside the sole panel button', (
    tester,
  ) async {
    await mount(tester);
    final count = find.byKey(const ValueKey('workbench-status-problems'));
    expect(tester.widget(count), isA<SizedBox>());
    await tester.tap(count);
    await _frames(tester);
    expect(find.byType(EditorProblemsPanel), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workbench-panel-problems')));
    await _frames(tester);
    expect(find.byType(EditorProblemsPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  desktopTest('new file shortcut creates and opens a file; F5 uses runner', (
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
