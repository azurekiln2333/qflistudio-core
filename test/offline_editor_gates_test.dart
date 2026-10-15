@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// Offline-only gating for the two editor/settings entries that reach the
/// network:
///
///   * the editor «more» popup `Git` and `从云端拉取` items (GitPage runs
///     push/pull/remote), and
///   * the profile tab's `设置 → AI 助手 → 个人 AI 接口` section.
///
/// An offline-only product must not render either; a networked product must
/// keep both. Each case is asserted against the real `EditorPage` / `ProfileTab`
/// widget so a future regression in the gate is caught here, not on device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Fixture fixture;
  late StudioProfile? previousProfile;
  late Directory pathRoot;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    // A real path provider keeps `AppPaths.storageDirectory()` on its fast path;
    // without it the 2 s `.timeout` guard leaves a pending timer that fails the
    // test on teardown.
    pathRoot = await Directory.systemTemp.createTemp('qfli_gates_paths_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(pathRoot.path);
    await AppPaths.storageDirectory();
  });

  setUp(() {
    previousProfile = StudioProfile.current;
    fixture = _Fixture();
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    await fixture.dispose();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (pathRoot.existsSync()) pathRoot.deleteSync(recursive: true);
  });

  group('editor popup', () {
    testWidgets('offline-only hides Git and cloud pull', (tester) async {
      fixture.installProfile(offlineOnly: true);
      await fixture.mountEditor(tester);
      await _openPopup(tester);

      expect(find.text('Git'), findsNothing);
      expect(find.text('从云端拉取'), findsNothing);
      // The popup still opens and offers the local entries.
      expect(find.text('打开终端'), findsWidgets);
      expect(find.text('设置'), findsWidgets);
    });

    testWidgets('networked keeps Git', (tester) async {
      fixture.installProfile(offlineOnly: false);
      await fixture.mountEditor(tester);
      await _openPopup(tester);

      expect(find.text('Git'), findsOneWidget);
      expect(find.text('设置'), findsWidgets);
    });
  });

  group('profile settings route', () {
    testWidgets('offline-only hides the AI assistant section', (tester) async {
      StudioProfile.current = fixture.profileFor(offlineOnly: true);
      await _mountProfile(tester, fixture.stores);
      await _openSettings(tester);

      expect(find.text('设置'), findsWidgets);
      expect(find.text('AI 助手'), findsNothing);
      expect(find.text('个人 AI 接口'), findsNothing);
      // Local sections remain reachable.
      expect(find.text('外观与体验'), findsOneWidget);
      expect(find.text('编辑器'), findsOneWidget);
    });

    testWidgets('networked keeps the AI assistant section', (tester) async {
      StudioProfile.current = fixture.profileFor(offlineOnly: false);
      await _mountProfile(tester, fixture.stores);
      await _openSettings(tester);

      expect(find.text('AI 助手'), findsOneWidget);
      expect(find.text('个人 AI 接口'), findsOneWidget);
    });
  });
}

Future<void> _openPopup(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mountProfile(WidgetTester tester, _Stores stores) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      home: Scaffold(
        body: ProfileTab(
          auth: stores.auth,
          settings: stores.settings,
          store: stores.projects,
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('设置').first);
  await tester.tap(find.text('设置').first);
  // Drain the route transition and any short-lived page timers (the profile
  // activity layer schedules a 2 s refresh) so the tree can be disposed.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Stores {
  final projects = ProjectStore();
  final auth = AuthStore();
  final settings = SettingsStore();

  void dispose() {
    projects.dispose();
    auth.dispose();
    settings.dispose();
  }
}

class _Fixture {
  final directory = Directory.systemTemp.createTempSync('qfli_offline_gates_');
  final stores = _Stores();
  late final Project project;
  var _disposed = false;

  _Fixture() {
    final projectDirectory = Directory(p.join(directory.path, 'project'))
      ..createSync();
    project = Project.create(name: 'gate project', path: projectDirectory.path);
    File(
      p.join(project.path, 'main.dart'),
    ).writeAsStringSync('void main() {}\n');
    final config = File(ProjectConfig.configPath(project.path));
    config.parent.createSync();
    config.writeAsStringSync(
      jsonEncode({'version': 1, 'entryFile': 'main.dart'}),
    );
  }

  StudioProfile profileFor({required bool offlineOnly}) => StudioProfile(
    id: 'gates',
    appTitle: 'Gates',
    templates: const [],
    isOffline: offlineOnly,
    offlineOnly: offlineOnly,
    entryFileNames: const ['main.dart'],
    supportedFileExtensions: const ['.dart'],
  );

  void installProfile({required bool offlineOnly}) {
    StudioProfile.current = profileFor(offlineOnly: offlineOnly);
  }

  Future<void> mountEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    addTearDown(() async {
      // Unmount while `tester` is valid so EditorPage.dispose can flush its
      // unawaited history write, then drain both zones before deleting.
      await tester.pumpWidget(const SizedBox.shrink());
      await _deleteTree(tester, directory);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: project,
          auth: stores.auth,
          store: stores.projects,
          settings: stores.settings,
          initialOpenPath: 'main.dart',
        ),
      ),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byIcon(Icons.more_vert).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stores.dispose();
  }
}

Future<void> _deleteTree(WidgetTester tester, Directory directory) async {
  FileSystemException? lastError;
  for (var round = 0; round < 50; round++) {
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      lastError = error;
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }
  throw lastError!;
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}
