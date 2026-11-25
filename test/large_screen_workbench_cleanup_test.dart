import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/chat/composer_draft.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/ui/agents_entry.dart';
import 'package:qfli_studio_core/shell/workbench_session_view.dart';
import 'package:qfli_studio_core/harness/harness_session_target.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/large_screen_workbench.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';
import 'package:qfli_studio_core/shell/workbench_explorer.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';
import 'support/fake_harness_host.dart';

Future<void> _finishExplorerTransition(WidgetTester tester) async {
  await tester.pump();
  // The interpolation simulation finishes strictly after its duration.
  await tester.pump(
    WorkbenchExplorer.duration + const Duration(milliseconds: 16),
  );
}

class _FilePanel extends StatefulWidget {
  const _FilePanel({super.key});

  @override
  State<_FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends State<_FilePanel> {
  @override
  Widget build(BuildContext context) => const Text('Retained file panel');
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

Finder _projectLabel(String name) => find.descendant(
  of: find.byType(WorkbenchProjectRow),
  matching: find.text(name),
);

/// Avoids starting real runtimes: these tests exercise the shell and Home's
/// project-open boundary, while the existing host suite covers editor state.
class _Editors extends RetainedEditorController {
  final _opened =
      <({String key, Project project, SavedWorkspace? workspace})>[];
  String? active;
  final resumed = <String>[];

  void statusChanged() => notifyListeners();

  @override
  bool get isVisible => active != null;
  @override
  String? get activeSessionKey => active;
  @override
  Project? get activeProject =>
      _opened.where((session) => session.key == active).firstOrNull?.project;

  @override
  List<({String key, Project project, SavedWorkspace? workspace})>
  get sessionInfos => [
    for (final session in _opened)
      (
        key: session.key,
        project: session.project,
        workspace: session.workspace,
      ),
  ];

  @override
  void open({
    required Project project,
    required AuthStore auth,
    required ProjectStore store,
    required SettingsStore settings,
    String? initialOpenPath,
    SavedWorkspace? workspace,
    List<Project>? workspaceProjects,
    WorkspaceStore? workspaceStore,
    bool revealAgentPane = false,
    HarnessSessionTarget? harnessSession,
    HarnessHub? harnessHub,
    ComposerDraft? composerPrefill,
  }) {
    final key = 'test:${project.id}';
    if (!_opened.any((session) => session.key == key)) {
      _opened.add((key: key, project: project, workspace: workspace));
    }
    active = key;
    notifyListeners();
  }

  @override
  void resumeSession(String key) {
    resumed.add(key);
    active = key;
    notifyListeners();
  }

  @override
  void minimize() {
    active = null;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  StudioProfile? previousProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('workbench_cleanup_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    await AppPaths.storageDirectory();
    await TaskActivityService.instance.initialize();
  });
  tearDownAll(() async {
    PathProviderPlatform.instance = previousPaths;
    if (root.existsSync()) await root.delete(recursive: true);
  });
  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'java',
      appTitle: 'Workbench test',
      templates: [ProjectTemplate.java],
      isOffline: true,
    );
  });
  tearDown(() => StudioProfile.current = previousProfile);

  Future<({LargeScreenController layout, _Editors editors})> mount(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthStore();
    final settings = SettingsStore();
    final store = ProjectStore(
      storageFile: File(p.join(root.path, 'projects.json')),
    );
    final editors = _Editors();
    await tester.runAsync(() async {
      await store.load();
      for (final name in ['Alpha', 'Beta']) {
        final directory = Directory(p.join(root.path, name));
        await directory.create(recursive: true);
        await store.addExisting(directory.path);
      }
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      editors.dispose();
      auth.dispose();
      settings.dispose();
      store.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LargeScreenWorkbench(
          editors: editors,
          store: store,
          auth: auth,
          settings: settings,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return (
      layout: LargeScreenScope.maybeOf(tester.element(find.byType(HomeTab)))!,
      editors: editors,
    );
  }

  Future<void> project(WidgetTester tester, String name) async {
    await tester.tap(_projectLabel(name));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  testWidgets('R4: unresolved session uses the real retained center overlay', (
    tester,
  ) async {
    final fixture = await mount(tester);
    await project(tester, 'Alpha');
    final sessionKey = fixture.editors.activeSessionKey;
    final retainedHost = tester.element(
      find.byKey(const ValueKey('workbench-editor-host')),
    );
    fixture.layout.showProjects();
    await tester.pump();
    await _finishExplorerTransition(tester);
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    final info = HarnessSessionInfo(
      id: 'missing',
      hostId: 'local',
      providerId: 'pi',
      title: 'Standalone conversation',
      status: HarnessSessionStatus.idle,
      capabilities: const {HarnessCapability.transcript},
      cwd: p.join(root.path, 'missing-session-root'),
    );
    final handle = FakeSessionHandle(info: info);
    final hub = HarnessHub(
      hosts: [
        FakeHarnessHost(
          id: 'local',
          label: 'Local',
          kind: HarnessHostKind.local,
          initialSessions: [info],
          openHandler: (_) async => handle,
        ),
      ],
      desktop: true,
    );
    await tester.runAsync(
      () => openAgentSession(
        tester.element(find.byType(HomeTab)),
        row: AgentsIndexRow(
          session: info,
          hostLabel: 'Local',
          hostKind: HarnessHostKind.local,
        ),
        auth: home.auth,
        store: home.store,
        settings: home.settings,
        harnessHub: hub,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(WorkbenchSessionView), findsOneWidget);
    expect(find.textContaining('先打开一个项目'), findsNothing);
    expect(fixture.editors.activeSessionKey, sessionKey);
    expect(
      tester.element(
        find.byKey(
          const ValueKey('workbench-editor-host'),
          skipOffstage: false,
        ),
      ),
      same(retainedHost),
    );
    await project(tester, 'Beta');
    expect(find.byType(WorkbenchSessionView), findsNothing);
    expect(fixture.editors.activeProject!.name, 'Beta');
    expect(fixture.layout.explorerPage, ExplorerPage.files);
    expect(handle.detachCount, 1);
    expect(handle.stopCount, 0);
    await hub.shutdown();
    expect(tester.takeException(), isNull);
  });

  testWidgets('project clicks switch to Files and resume the same live key', (
    tester,
  ) async {
    final fixture = await mount(tester);
    final layout = fixture.layout;
    final editors = fixture.editors;
    layout.showCenterOverlay((_) => const Text('Conversation'));
    await tester.pump();
    expect(find.text('Conversation'), findsOneWidget);
    await project(tester, 'Alpha');
    final alpha = editors.activeSessionKey;
    expect(layout.centerOverlay, isNull);
    expect(layout.explorerPage, ExplorerPage.files);
    expect(editors.sessionInfos, hasLength(1));
    await tester.tap(find.byKey(WorkbenchExplorer.backKey));
    await tester.pump();
    await _finishExplorerTransition(tester);
    expect(editors.activeSessionKey, alpha);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await project(tester, 'Alpha');
    expect(editors.resumed.last, alpha);
    expect(editors.sessionInfos, hasLength(1));
    expect(layout.explorerPage, ExplorerPage.files);
    layout.showCenterOverlay((_) => const Text('Another conversation'));
    await tester.pump();
    editors.statusChanged(); // A popup/status notification is not an open.
    await tester.pump();
    expect(find.text('Another conversation'), findsOneWidget);
    layout.showProjects();
    await tester.pump();
    await _finishExplorerTransition(tester);
    await project(tester, 'Alpha');
    expect(layout.centerOverlay, isNull);
    expect(editors.activeSessionKey, alpha);
    layout.showProjects();
    await tester.pump();
    await _finishExplorerTransition(tester);
    await project(tester, 'Beta');
    expect(editors.activeProject!.name, 'Beta');
    expect(editors.sessionInfos, hasLength(2));
    expect(layout.explorerPage, ExplorerPage.files);
    layout.showProjects();
    await tester.pump();
    await _finishExplorerTransition(tester);
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    await project(tester, 'Alpha');
    expect(editors.activeSessionKey, alpha);
    expect(editors.sessionInfos, hasLength(2));
    // A promoted workspace must resume its exact key, not create standalone.
    final current = editors._opened.first;
    final now = DateTime(2026, 11, 25);
    editors._opened[0] = (
      key: 'workspace:kept',
      project: current.project,
      workspace: SavedWorkspace(
        id: 'kept',
        name: 'Kept workspace',
        createdAt: now,
        updatedAt: now,
        members: const [],
      ),
    );
    editors.active = 'workspace:kept';
    editors.statusChanged();
    layout.showProjects();
    await tester.pump();
    await _finishExplorerTransition(tester);
    await project(tester, 'Alpha');
    expect(editors.activeSessionKey, 'workspace:kept');
    expect(editors.resumed.last, 'workspace:kept');
    expect(editors.sessionInfos, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible Explorer does not duplicate the welcome project list', (
    tester,
  ) async {
    await mount(tester);
    final welcome = find.byType(WorkbenchWelcome);
    expect(welcome, findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);

    await tester.tap(
      find.byKey(WorkbenchActivityRail.activityKey(WorkbenchActivity.explorer)),
    );
    await tester.pump();
    expect(welcome, findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'file panel survives Explorer pages, activities and compact resize',
    (tester) async {
      final fixture = await mount(tester);
      await project(tester, 'Alpha');
      final owner = Object();
      fixture.layout.registerFiles(
        owner,
        (_) => const _FilePanel(key: ValueKey('retained-test-files')),
      );
      fixture.layout.activateFiles(owner);
      await tester.pump();
      await tester.pump();
      final panel = tester.state(find.byType(_FilePanel));
      fixture.layout.showProjects();
      await tester.pump();
      await _finishExplorerTransition(tester);
      expect(find.byType(_FilePanel), findsNothing);
      expect(panel.mounted, isTrue);
      expect(
        tester.state(find.byType(_FilePanel, skipOffstage: false)),
        same(panel),
      );
      fixture.layout.showFiles();
      await tester.pump();
      await _finishExplorerTransition(tester);
      expect(tester.state(find.byType(_FilePanel)), same(panel));
      await tester.tap(
        find.byKey(WorkbenchActivityRail.activityKey(WorkbenchActivity.agents)),
      );
      await tester.pump();
      expect(find.byType(_FilePanel), findsNothing);
      await tester.tap(
        find.byKey(
          WorkbenchActivityRail.activityKey(WorkbenchActivity.explorer),
        ),
      );
      await tester.pump();
      expect(tester.state(find.byType(_FilePanel)), same(panel));
      tester.view.physicalSize = const Size(500, 800);
      await tester.pump();
      expect(tester.state(find.byType(_FilePanel)), same(panel));
      await tester.tap(
        find.byKey(
          WorkbenchActivityRail.activityKey(WorkbenchActivity.explorer),
        ),
      );
      await tester.pump();
      expect(find.byType(_FilePanel), findsNothing);
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pump();
      await tester.tap(
        find.byKey(
          WorkbenchActivityRail.activityKey(WorkbenchActivity.explorer),
        ),
      );
      await tester.pump();
      expect(tester.state(find.byType(_FilePanel)), same(panel));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overlay keeps editor host mounted and sidebar usable', (
    tester,
  ) async {
    final fixture = await mount(tester);
    final host = tester.state(find.byType(RetainedEditorHost));
    fixture.layout.showCenterOverlay((_) => const Text('Conversation'));
    await tester.pump();
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.byType(RetainedEditorHost), findsNothing);
    expect(host.mounted, isTrue);
    final home = tester.state(find.byType(HomeTab));
    expect(home.mounted, isTrue);
    fixture.layout.closeCenterOverlay();
    await tester.pump();
    expect(tester.state(find.byType(RetainedEditorHost)), same(host));
    expect(find.text('Conversation'), findsNothing);
    expect(tester.state(find.byType(HomeTab)), same(home));
  });

  testWidgets(
    'shell notices stay centered inside the central area at each width',
    (tester) async {
      final fixture = await mount(tester);
      final home = tester.element(find.byType(HomeTab));
      final messenger = ScaffoldMessenger.of(home);
      final center = find.byKey(const ValueKey('workbench-center-scaffold'));
      for (final width in [1440.0, 1200.0, 1024.0, 500.0]) {
        tester.view.physicalSize = Size(width, 850);
        await tester.pump();
        for (final sidebarVisible in [true, false]) {
          fixture.layout.select(WorkbenchActivity.explorer, toggle: false);
          if (!sidebarVisible) fixture.layout.toggleSidebar();
          await tester.pump();
          messenger.showSnackBar(
            const SnackBar(content: Text('Central notice')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          // V11 concerns the painted surface, not MD3's expanding Align.
          final notice = find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          );
          expect(notice, findsOneWidget);
          expect(
            Scaffold.of(tester.element(notice)),
            same(tester.state<ScaffoldState>(center)),
          );
          expect(ScaffoldMessenger.of(tester.element(notice)), same(messenger));
          final centralRect = tester.getRect(center);
          final centerLeft =
              WorkbenchActivityRail.width +
              (!fixture.layout.compact && sidebarVisible
                  ? fixture.layout.sidebarWidth
                  : 0);
          expect(centralRect.left, closeTo(centerLeft, 1));
          expect(centralRect.right, closeTo(width, 1));
          final noticeRect = tester.getRect(notice);
          expect(noticeRect.center.dx, closeTo(centralRect.center.dx, 1));
          expect(noticeRect.width, greaterThan(0));
          expect(noticeRect.width, lessThanOrEqualTo(480));
          expect(noticeRect.left, greaterThanOrEqualTo(centralRect.left));
          expect(noticeRect.right, lessThanOrEqualTo(centralRect.right));
          messenger.removeCurrentSnackBar();
          await tester.pump();
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workbench project search stays visible and filters the retained panel',
    (tester) async {
      await mount(tester);
      final home = find.byType(HomeTab);
      final field = find.descendant(
        of: home,
        matching: find.byKey(const ValueKey('workbench-project-search')),
      );
      expect(field, findsOneWidget);
      expect(
        find.descendant(of: home, matching: find.byType(AppBar)),
        findsNothing,
      );
      expect(
        find.descendant(of: home, matching: find.byType(TabBar)),
        findsNothing,
      );
      await tester.enterText(field, 'Alpha');
      await tester.pump();
      // The query also appears in EditableText. Check project row labels.
      expect(_projectLabel('Alpha'), findsOneWidget);
      expect(_projectLabel('Beta'), findsNothing);
      await tester.enterText(field, '');
      await tester.pump();
      expect(_projectLabel('Alpha'), findsOneWidget);
      expect(_projectLabel('Beta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shell shortcuts select rather than toggle and use platform modifier',
    (tester) async {
      final fixture = await mount(tester);
      Future<void> key(LogicalKeyboardKey key, {bool shift = false}) async {
        final modifier = Platform.isMacOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }

      await key(LogicalKeyboardKey.keyB);
      expect(fixture.layout.sidebarVisible, isFalse);
      await key(LogicalKeyboardKey.keyE, shift: true);
      expect(fixture.layout.activity, WorkbenchActivity.explorer);
      expect(fixture.layout.sidebarVisible, isTrue);
      await key(LogicalKeyboardKey.keyE, shift: true);
      expect(fixture.layout.sidebarVisible, isTrue);
      await key(LogicalKeyboardKey.keyA, shift: true);
      expect(fixture.layout.activity, WorkbenchActivity.agents);
      await key(LogicalKeyboardKey.comma);
      expect(fixture.layout.activity, WorkbenchActivity.settings);
      expect(find.byType(WorkbenchActivityRail), findsOneWidget);
      expect(WorkbenchActivity.values, hasLength(6));
      expect(WorkbenchActivityRail.primary, [
        WorkbenchActivity.explorer,
        WorkbenchActivity.agents,
      ]);
      expect(find.byTooltip(RegExp(r'Shift\+E')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
