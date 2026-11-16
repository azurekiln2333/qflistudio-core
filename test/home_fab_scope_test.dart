import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/home_project_tabs.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

/// The home FAB creates what the visible tab implies (R1).
///
/// On the cloud scope it opens the cloud project dialog the overflow menu used
/// to own; on every other scope it keeps opening the local project dialog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_home_fab_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
  });

  setUp(() {
    originalProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'studio',
      appTitle: 'QFLIStudio+',
      templates: [ProjectTemplate.java],
      isOffline: false,
      productKey: StudioProductCatalog.qfliStudioKey,
    );
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  for (final scope in ['全部项目', '历史项目', '收藏项目', '工作区']) {
    testWidgets('on $scope the FAB opens the local project dialog', (
      tester,
    ) async {
      final fixture = await _mount(tester, root, loggedIn: true);
      await _selectScope(tester, scope);
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);

      // The local dialog names the project and picks a type; the cloud dialog
      // uploads instead and has no type selector.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('新建项目'),
        ),
        findsOneWidget,
      );
      expect(find.text('项目类型'), findsOneWidget);
      expect(find.text('新建云端项目'), findsNothing);
      expect(tester.takeException(), isNull);
      fixture.dispose();
    });
  }

  testWidgets('on the cloud scope the FAB opens the cloud project dialog', (
    tester,
  ) async {
    final fixture = await _mount(tester, root, loggedIn: true);
    await _selectScope(tester, '云端项目');
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('新建云端项目'), findsOneWidget);
    expect(find.text('项目类型'), findsOneWidget);
    expect(tester.takeException(), isNull);
    fixture.dispose();
  });

  testWidgets('the cloud scope FAB asks for a session instead of creating', (
    tester,
  ) async {
    // A cloud scope with no session is possible: the scope is decided by the
    // product, not by whether someone has signed in yet.
    final fixture = await _mount(tester, root);
    await _selectScope(tester, '云端项目');
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('请先在「我的」页登录，再新建云端项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
    fixture.dispose();
  });
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(label)),
  );
  await _settle(tester);
}

Future<_Fixture> _mount(
  WidgetTester tester,
  Directory root, {
  bool loggedIn = false,
}) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final fixture = _Fixture.create(root);
  await tester.runAsync(fixture.projects.load);
  if (loggedIn) {
    await tester.runAsync(
      () => fixture.auth.signIn(
        'token-fab',
        const CommunityUser(
          id: 'u1',
          username: 'tester',
          nickname: 'Tester',
          bio: '',
          avatarColor: '#2196F3',
          points: 0,
          checkinStreak: 0,
          provider: 'local',
        ),
      ),
    );
    await _settle(tester);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeTab(
        store: fixture.projects,
        auth: fixture.auth,
        settings: fixture.settings,
        tabOrderStore: HomeTabOrderStore(backend: LocalMemoryBackend()),
      ),
    ),
  );
  await _settle(tester);
  return fixture;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

class _Fixture {
  _Fixture(this.directory, this.projects, this.auth, this.settings);

  final Directory directory;
  final ProjectStore projects;
  final AuthStore auth;
  final SettingsStore settings;

  factory _Fixture.create(Directory root) {
    final directory = root.createTempSync('fab_');
    final projectDirectory = Directory(p.join(directory.path, 'Alpha'))
      ..createSync();
    File(
      p.join(projectDirectory.path, 'Main.java'),
    ).writeAsStringSync('class Main {}');
    final project = Project.create(
      name: 'Alpha',
      path: projectDirectory.path,
      language: 'Java',
      type: 'java',
    );
    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'projects': [project.toJson()],
        }),
      );
    return _Fixture(
      directory,
      ProjectStore(storageFile: registry),
      AuthStore(),
      SettingsStore(),
    );
  }

  void dispose() {
    projects.dispose();
    auth.dispose();
    settings.dispose();
  }
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
