import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_project_scopes_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
    await TaskActivityService.instance.initialize();
  });

  setUp(() {
    originalProfile = StudioProfile.current;
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets(
    'offline products keep all, history and favorite scopes with language chips hidden',
    (tester) async {
      StudioProfile.current = _profile(offlineOnly: true, showHomeTabs: false);
      final fixture = await _mount(tester, root);

      _expectScopeLabels(['全部项目', '历史项目', '收藏项目']);
      expect(find.text('云端项目'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(_visibleProjectNames(tester), ['Alpha', 'Middle', 'Zulu']);

      await _selectScope(tester, '历史项目');
      // The registry is deliberately not in name or recency order. History
      // must keep ProjectStore's newest-first order rather than reuse All.
      expect(_visibleProjectNames(tester), ['Zulu', 'Middle', 'Alpha']);

      await _selectScope(tester, '收藏项目');
      // CloudOnly is also starred, but cannot leak into an offline scope.
      expect(_visibleProjectNames(tester), ['Middle']);

      // A real store update must refresh the selected scope too.
      final alpha = fixture.projects.projects.singleWhere(
        (project) => project.name == 'Alpha',
      );
      await tester.runAsync(() => fixture.projects.setFavorite(alpha, true));
      await _settle(tester);
      expect(_visibleProjectNames(tester), ['Middle', 'Alpha']);

      await _selectScope(tester, '全部项目');
      expect(_visibleProjectNames(tester), ['Alpha', 'Middle', 'Zulu']);
      expect(find.byType(FilterChip), findsNothing);
    },
  );

  for (final showHomeTabs in [true, false]) {
    testWidgets(
      'networked products keep cloud scope with showHomeTabs=$showHomeTabs',
      (tester) async {
        StudioProfile.current = _profile(
          offlineOnly: false,
          showHomeTabs: showHomeTabs,
        );
        await _mount(tester, root);

        _expectScopeLabels(['全部项目', '历史项目', '收藏项目', '云端项目']);
        expect(
          find.byType(FilterChip),
          showHomeTabs ? findsWidgets : findsNothing,
        );
        expect(_visibleProjectNames(tester), [
          'Alpha',
          'CloudOnly',
          'Middle',
          'Zulu',
        ]);

        await _selectScope(tester, '云端项目');
        expect(_visibleProjectNames(tester), ['CloudOnly']);
      },
    );
  }
}

StudioProfile _profile({
  required bool offlineOnly,
  required bool showHomeTabs,
}) => StudioProfile(
  id: 'java',
  appTitle: 'QFLIJVMX',
  templates: const [ProjectTemplate.java],
  isOffline: true,
  offlineOnly: offlineOnly,
  showHomeTabs: showHomeTabs,
  productKey: StudioProductCatalog.jvmxKey,
);

Future<_Fixture> _mount(WidgetTester tester, Directory root) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final fixture = _Fixture.create(root);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    fixture.projects.dispose();
    fixture.auth.dispose();
    fixture.settings.dispose();
    // ProjectStore reads/writes use dart:io and compute. Leave the fake-async
    // boundary before removing this test's real fixture directory.
    await tester.runAsync(() => fixture.directory.delete(recursive: true));
  });
  await tester.runAsync(() => fixture.projects.load());
  expect(fixture.projects.projects, hasLength(4));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      home: HomePage(
        store: fixture.projects,
        auth: fixture.auth,
        settings: fixture.settings,
      ),
    ),
  );
  await _settle(tester);
  return fixture;
}

void _expectScopeLabels(List<String> labels) {
  final bar = find.byType(TabBar);
  expect(bar, findsOneWidget);
  for (final label in labels) {
    expect(
      find.descendant(of: bar, matching: find.text(label)),
      findsOneWidget,
    );
  }
  expect(
    find.descendant(of: bar, matching: find.byType(Tab)),
    findsNWidgets(labels.length),
  );
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text(label),
  );
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await _settle(tester);
}

List<String> _visibleProjectNames(WidgetTester tester) => tester
    .widgetList<ProjectCard>(find.byType(ProjectCard).hitTestable())
    .map((card) => card.project.name)
    .toList();

Future<void> _settle(WidgetTester tester) async {
  // Match home_navigation_test's bounded pumps: the real Home can keep timers
  // alive, so these tests must not wait indefinitely for pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

class _Fixture {
  _Fixture(this.directory, this.projects);

  final Directory directory;
  final ProjectStore projects;
  final auth = AuthStore();
  final settings = SettingsStore();

  factory _Fixture.create(Directory root) {
    final directory = root.createTempSync('registry_');
    Project project(
      String name,
      int lastOpenedDay, {
      bool favorite = false,
      String? cloudId,
    }) {
      final projectDirectory = Directory(p.join(directory.path, name))
        ..createSync();
      File(
        p.join(projectDirectory.path, 'Main.java'),
      ).writeAsStringSync('class Main {}');
      return Project(
        id: name,
        name: name,
        path: projectDirectory.path,
        createdAt: DateTime.utc(2026),
        lastOpenedAt: DateTime.utc(2026, 1, lastOpenedDay),
        favorite: favorite,
        cloudId: cloudId,
        language: 'Java',
        type: 'java',
      );
    }

    final projects = [
      project('Middle', 2, favorite: true),
      project('Alpha', 1),
      project('CloudOnly', 4, favorite: true, cloudId: 'scope-cloud'),
      project('Zulu', 3),
    ];
    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'projects': [for (final project in projects) project.toJson()],
        }),
      );
    return _Fixture(directory, ProjectStore(storageFile: registry));
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
