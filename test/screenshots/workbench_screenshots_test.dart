// Opt-in real-widget captures. CI only: QFLI_SCREENSHOTS=1.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/editor/agent/agent_dock.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/github/github_auth_controller.dart';
import 'package:qfli_studio_core/github/github_credential_store.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/harness_session_target.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/hub/harness_hosts.dart';
import 'package:qfli_studio_core/harness/ui/hub_chat_view.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/shell/agent_runtime_factory.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/large_screen_workbench.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';
import 'package:re_editor/re_editor.dart';

import '../support/fake_harness_host.dart';

final bool _enabled = Platform.environment['QFLI_SCREENSHOTS'] == '1';
const _screenshotRoot = ValueKey('workbench-screenshot-root');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory? root;
  PathProviderPlatform? previousPaths;
  StudioProfile? previousProfile;
  setUpAll(() async {
    if (!_enabled) return;
    root = await Directory.systemTemp.createTemp('qfli-workbench-shots-');
    previousPaths = PathProviderPlatform.instance;
    previousProfile = StudioProfile.current;
    PathProviderPlatform.instance = _Paths(root!.path);
    StudioProfile.current = const StudioProfile(
      id: 'screenshots',
      appTitle: 'QFLI Studio',
      templates: [],
      supportedFileExtensions: ['.dart'],
      entryFileNames: ['main.dart'],
      productKey: StudioProductCatalog.qfliStudioKey,
    );
    // Use the real shell/editor with deterministic hosts and no PTY discovery.
    HarnessHosts.overrideForTesting((_) => []);
    await AppPaths.storageDirectory();
    await TaskActivityService.instance.initialize();
    await _loadRealFonts();
  });
  tearDownAll(() async {
    if (!_enabled) return;
    HarnessHosts.overrideForTesting(null);
    StudioProfile.current = previousProfile;
    PathProviderPlatform.instance = previousPaths!;
    if (root != null && root!.existsSync()) {
      await root!.delete(recursive: true);
    }
  });
  testWidgets('capture required workbench scenes with verified navigation', (
    tester,
  ) async {
    const configurations = <({Size size, String name, AppFormFactor factor})>[
      (size: Size(1440, 900), name: '1440x900', factor: AppFormFactor.desktop),
      (size: Size(1024, 768), name: '1024x768', factor: AppFormFactor.desktop),
      (size: Size(1180, 820), name: '1180x820', factor: AppFormFactor.tablet),
    ];
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.view.reset);
    for (final configuration in configurations) {
      for (final theme in ['light', 'dark']) {
        await _configuration(tester, root!, configuration, theme);
      }
    }
  }, skip: !_enabled);
}

Future<void> _configuration(
  WidgetTester tester,
  Directory root,
  ({Size size, String name, AppFormFactor factor}) configuration,
  String theme,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = configuration.size;
  final stem = '${configuration.name}-$theme';
  final fixture = (await tester.runAsync(() => _fixture(root, theme)))!;
  try {
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenshotRoot,
        child: QfliApp(
          store: fixture.store,
          auth: fixture.auth,
          settings: fixture.settings,
          formFactor: configuration.factor,
          githubController: fixture.github,
        ),
      ),
    );
    await _wait(
      tester,
      () =>
          find.byType(LargeScreenWorkbench).evaluate().length == 1 &&
          find.byType(HomeTab).evaluate().length == 1,
      '$stem workbench',
    );
    final shell = tester.widget<LargeScreenWorkbench>(
      find.byType(LargeScreenWorkbench),
    );
    final context = tester.element(find.byType(HomeTab, skipOffstage: false));
    final layout = LargeScreenScope.maybeOf(context)!;
    expect(
      LargeScreenScope.isDesktop(context),
      configuration.factor == AppFormFactor.desktop,
    );
    final explorer = find.byKey(
      WorkbenchActivityRail.activityKey(WorkbenchActivity.explorer),
    );
    expect(find.text('资源管理器'), findsOneWidget);

    // R5/V9: Start/Recent is visible only while the Explorer panel is hidden.
    await _tap(tester, explorer);
    await _wait(
      tester,
      () =>
          !layout.sidebarVisible &&
          find.byType(WorkbenchWelcome).evaluate().length == 1,
      '$stem welcome',
    );
    expect(layout.sidebarVisible, isFalse);
    expect(find.byType(WorkbenchWelcome), findsOneWidget);
    await _capture(tester, '$stem-welcome.png');
    await _tap(tester, explorer);
    expect(layout.explorerPage, ExplorerPage.projects);
    expect(layout.sidebarVisible, isTrue);
    final added = await tester.runAsync(
      () => fixture.store.addExisting(fixture.sample.path),
    );
    final project = added?.project;
    if (project == null) {
      throw StateError(added?.error ?? 'Sample registration failed');
    }
    await _wait(
      tester,
      () =>
          layout.explorerPage == ExplorerPage.projects &&
          layout.sidebarVisible &&
          find
                  .byKey(ValueKey('workbench-project-${project.id}'))
                  .evaluate()
                  .length ==
              1,
      '$stem project registration',
    );
    expect(
      find.byKey(ValueKey('workbench-project-${project.id}')),
      findsOneWidget,
    );
    await _capture(tester, '$stem-explorer-projects.png');

    await _tap(tester, find.byKey(ValueKey('workbench-project-${project.id}')));
    final sourceFile = find.descendant(
      of: find.byType(FileExplorer),
      matching: find.text('main.dart'),
    );
    // A new project has no saved editor tabs. Open its real file-tree entry.
    await _wait(
      tester,
      () =>
          find.byType(EditorPage).evaluate().length == 1 &&
          sourceFile.evaluate().length == 1,
      '$stem file tree',
    );
    expect(layout.explorerPage, ExplorerPage.files);
    await _tap(tester, sourceFile);
    await _wait(
      tester,
      () =>
          _editor(tester).current?.name == 'main.dart' &&
          find.byType(CodeEditor).evaluate().length == 1,
      '$stem open source file',
    );
    final retainedEditor = tester.state(find.byType(EditorPage));
    expect(find.byType(FileExplorer), findsOneWidget);
    expect(find.byType(CodeEditor), findsOneWidget);
    await _capture(tester, '$stem-explorer-files-editor.png');

    // Resolve the lazy built-in runtime before opening the fake external
    // session. AgentDock insertion changes the conversation's ancestors.
    layout.toggleSidebar();
    final agentHost = tester
        .widget<AgentEntryButton>(find.byType(AgentEntryButton))
        .host;
    await _tap(tester, find.byKey(const ValueKey('editor-agent-toggle')));
    await _wait(
      tester,
      () =>
          agentHost.activated &&
          identical(agentHost.runtime, fixture.runtime) &&
          agentHost.error == null &&
          tester
              .widget<AgentEntryButton>(find.byType(AgentEntryButton))
              .active &&
          (configuration.size.width < 1100
              ? find.byType(WorkbenchAgentPane).evaluate().length == 1
              : find.byType(AgentDock).evaluate().length == 1),
      '$stem Agent runtime',
      describe: () =>
          'activated=${agentHost.activated}, runtime=${agentHost.runtime}, '
          'error=${agentHost.error}, docks=${find.byType(AgentDock).evaluate().length}',
    );
    // Reuse the same retained editor with the session fixture used by hub tests.
    shell.editors.open(
      project: project,
      auth: fixture.auth,
      store: fixture.store,
      settings: fixture.settings,
      harnessSession: const HarnessSessionTarget(
        hostId: 'local',
        sessionId: 'screenshot',
      ),
      harnessHub: fixture.hub,
    );
    await _wait(
      tester,
      () =>
          identical(fixture.hub.activeHandle, fixture.handle) &&
          find.byType(HubChatView).evaluate().length == 1 &&
          identical(
            tester.widget<HubChatView>(find.byType(HubChatView)).handle,
            fixture.handle,
          ) &&
          (configuration.size.width < 1100 ||
              find.byType(AgentDock).evaluate().length == 1),
      '$stem Agent conversation',
      describe: () =>
          'active=${fixture.hub.activeSession?.id}, '
          'handle=${identical(fixture.hub.activeHandle, fixture.handle)}, '
          'chats=${find.byType(HubChatView).evaluate().length}',
    );
    fixture.handle.addEvent(
      TranscriptEvent(
        id: 'greeting',
        role: TranscriptRole.assistant,
        text: '已打开示例项目，可以开始编辑。',
        at: DateTime(2026, 11, 25),
      ),
    );
    await _wait(
      tester,
      () =>
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is ChatMessageTile &&
                    widget.message.id == 'greeting' &&
                    widget.message.text == '已打开示例项目，可以开始编辑。',
              )
              .evaluate()
              .length ==
          1,
      '$stem rendered Agent transcript',
    );
    expect(tester.state(find.byType(EditorPage)), same(retainedEditor));
    expect(find.byType(HubChatView), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-chat-list')), findsOneWidget);
    if (configuration.size.width >= 1100) {
      expect(find.byType(AgentDock), findsOneWidget);
      expect(find.byType(CodeEditor), findsOneWidget);
    } else {
      // The designed medium-pane switch shows Agent instead of source.
      expect(find.byType(CodeEditor), findsNothing);
    }
    await _capture(tester, '$stem-editor-agent.png');

    await _tap(
      tester,
      find.byKey(WorkbenchActivityRail.activityKey(WorkbenchActivity.settings)),
    );
    await _wait(
      tester,
      () =>
          layout.activity == WorkbenchActivity.settings &&
          find.byType(SettingsPage).evaluate().length == 1 &&
          find.byKey(const ValueKey('settings-ui-zoom')).evaluate().length == 1,
      '$stem settings',
    );
    expect(layout.activity, WorkbenchActivity.settings);
    expect(find.byType(SettingsPage), findsOneWidget);
    final appearanceCategory = find.widgetWithText(ListTile, '外观与体验');
    expect(appearanceCategory, findsOneWidget);
    expect(tester.widget<ListTile>(appearanceCategory).selected, isTrue);
    expect(find.byKey(const ValueKey('settings-ui-zoom')), findsOneWidget);
    await _capture(tester, '$stem-settings.png');

    await _tap(tester, explorer);
    if (layout.sidebarVisible) layout.toggleSidebar();
    await _settle(tester);
    if (find.byType(CodeEditor).evaluate().isEmpty) {
      await _tap(tester, find.byKey(const ValueKey('editor-agent-toggle')));
    }
    await _wait(
      tester,
      () =>
          layout.activity == WorkbenchActivity.explorer &&
          _editor(tester).current?.name == 'main.dart' &&
          find.byType(CodeEditor).evaluate().length == 1,
      '$stem restored source editor',
    );
    expect(tester.state(find.byType(EditorPage)), same(retainedEditor));
    expect(find.byType(CodeEditor), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('workbench-editor-more')));
    await _wait(
      tester,
      () =>
          find.byKey(const ValueKey('workbench-menu-save')).evaluate().length ==
          1,
      '$stem More menu',
    );
    expect(find.byKey(const ValueKey('workbench-menu-save')), findsOneWidget);
    expect(find.byType(MenuItemButton), findsWidgets);
    await _capture(tester, '$stem-more-menu.png');
    await _tap(tester, find.byKey(const ValueKey('workbench-editor-more')));
    expect(find.byKey(const ValueKey('workbench-menu-save')), findsNothing);
    expect(tester.takeException(), isNull);
  } finally {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await fixture.hub.shutdown();
      await fixture.runtime.sessions.flush();
    });
    resetStudioAgentRuntime();
    fixture.runtime.sessions.dispose();
    fixture.github.dispose();
    fixture.settings.dispose();
    fixture.auth.dispose();
    fixture.store.dispose();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await fixture.directory.delete(recursive: true);
    });
  }
}

EditorController _editor(WidgetTester tester) => tester
    .widgetList<ListenableBuilder>(
      find.descendant(
        of: find.byType(EditorPage),
        matching: find.byType(ListenableBuilder),
      ),
    )
    .map((builder) => builder.listenable)
    .whereType<EditorController>()
    .first;

Future<void> _settle(WidgetTester tester) async {
  // Progress indicators may remain alive; pump bounded frames rather than settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String scene, {
  String Function()? describe,
}) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    expect(tester.takeException(), isNull, reason: 'Waiting for $scene');
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  throw StateError(
    'QFLI_SCREENSHOTS: $scene did not become ready'
    '${describe == null ? '' : ' (${describe()})'}',
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: 'Before capture: $name');
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenshotRoot),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Screenshot encoding failed: $name');
      final file = File(p.join('build', 'screenshots', name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });
}

Future<_Fixture> _fixture(Directory root, String theme) async {
  final directory = await root.createTemp('scene-');
  final sample = Directory(p.join(directory.path, 'Screenshot Sample'));
  await sample.create();
  await File(
    p.join(sample.path, 'main.dart'),
  ).writeAsString("void main() {\n  print('QFLI screenshot sample');\n}\n");
  final store = ProjectStore(
    storageFile: File(p.join(directory.path, 'projects.json')),
  );
  final settings = SettingsStore(
    storageFile: File(p.join(directory.path, 'settings.json')),
  );
  final auth = AuthStore(
    storageFile: File(p.join(directory.path, 'auth.json')),
  );
  await store.load();
  await settings.load();
  await auth.load();
  await settings.setThemeMode(theme);
  // RetainedEditorController has no runtime injection seam. Prepare the normal
  // application runtime outside fake time, using this suite's isolated storage.
  // Signed-out auth avoids model/network work; external sessions remain fake.
  resetStudioAgentRuntime();
  final runtime = await studioAgentRuntime(
    auth: auth,
    store: store,
    settings: settings,
  );
  // load() can leave legacy migration running after returning an index.
  await (runtime.sessions as FileAgentSessionStore).migrationDone;
  await runtime.sessions.flush();
  final info = HarnessSessionInfo(
    id: 'screenshot',
    hostId: 'local',
    providerId: 'pi',
    title: 'Screenshot conversation',
    status: HarnessSessionStatus.idle,
    capabilities: const {
      HarnessCapability.transcript,
      HarnessCapability.prompt,
    },
    cwd: sample.path,
  );
  final handle = FakeSessionHandle(info: info);
  final hub = HarnessHub(
    hosts: [
      FakeHarnessHost(
        id: 'local',
        label: 'Screenshot host',
        kind: HarnessHostKind.local,
        initialSessions: [info],
        openHandler: (_) async => handle,
      ),
    ],
    desktop: true,
  );
  return _Fixture(
    directory,
    sample,
    store,
    settings,
    auth,
    GitHubAuthController(credentialStore: _EmptyCredentialStore()),
    hub,
    handle,
    runtime,
  );
}

class _Fixture {
  const _Fixture(
    this.directory,
    this.sample,
    this.store,
    this.settings,
    this.auth,
    this.github,
    this.hub,
    this.handle,
    this.runtime,
  );
  final Directory directory;
  final Directory sample;
  final ProjectStore store;
  final SettingsStore settings;
  final AuthStore auth;
  final GitHubAuthController github;
  final HarnessHub hub;
  final FakeSessionHandle handle;
  final AgentRuntime runtime;
}

class _EmptyCredentialStore implements GitHubCredentialStore {
  @override
  bool get isAvailable => true;
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<void> writeAccessToken(String token) async {}
  @override
  Future<void> deleteAccessToken() async {}
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

Future<void> _loadRealFonts() async {
  final mono = FontLoader('packages/qfli_studio_core/RobotoMono');
  for (final face in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
    mono.addFont(
      _asset('assets/fonts/roboto_mono/static/RobotoMono-$face.ttf'),
    );
  }
  await mono.load();
  // Flutter resolves the SDK cache font to this canonical asset key. Use the
  // bundle instead of guessing the SDK root or case-sensitive cache filename.
  final icons = FontLoader('MaterialIcons')
    ..addFont(_asset('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final candidates = await Directory('/usr/share/fonts/opentype/noto')
      .list(recursive: true, followLinks: false)
      .where(
        (file) =>
            file is File &&
            p.basename(file.path).toLowerCase().contains('notosanscjk') &&
            p.basename(file.path).toLowerCase().contains('regular'),
      )
      .cast<File>()
      .toList();
  candidates.sort((a, b) => a.path.compareTo(b.path));
  if (candidates.isEmpty) {
    throw StateError('Install fonts-noto-cjk before screenshot capture');
  }
  // Material typography defaults to Roboto on Linux. Supply real CJK glyphs
  // under that family as well, instead of leaving UI text on the Ahem test font.
  await _font('NotoSansCJK', candidates.first);
  await _font('Roboto', candidates.first);
}

Future<ByteData> _asset(String path) async {
  try {
    return await rootBundle.load(path);
  } on FlutterError {
    return rootBundle.load('packages/qfli_studio_core/$path');
  }
}

Future<void> _font(String family, File file) async {
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
  await loader.load();
}
