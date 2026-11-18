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
import 'package:qfli_studio_core/pages/home_project_tabs.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/widgets/collapsed_search_field.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

/// Home search collapsed behind an icon (R5).
///
/// The field is the shared [CollapsedSearchField]; Home only decides when it is
/// shown. Filtering still matches project names and paths, and collapsing clears
/// the filter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_home_search_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
  });

  setUp(() {
    originalProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'studio',
      appTitle: 'QFLIStudioN',
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

  testWidgets('home shows only a search icon until it is tapped', (
    tester,
  ) async {
    final fixture = await _mount(tester, root);

    expect(find.byType(CollapsedSearchButton), findsOneWidget);
    expect(find.byType(CollapsedSearchField), findsNothing);
    expect(find.byKey(const ValueKey('home-project-search-field')), findsNothing);
    // The collapsed state keeps the product title.
    expect(find.text('QFLIStudioN'), findsOneWidget);

    await tester.tap(find.byType(CollapsedSearchButton));
    await _settle(tester);

    expect(find.byType(CollapsedSearchField), findsOneWidget);
    expect(find.text('QFLIStudioN'), findsNothing);
    // Expanding hides the FAB and the overflow menu, as before.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    fixture.dispose();
  });

  testWidgets('typing filters the list and clearing restores it', (
    tester,
  ) async {
    final fixture = await _mount(tester, root);
    await tester.tap(find.byType(CollapsedSearchButton));
    await _settle(tester);

    final field = find.byKey(const ValueKey('home-project-search-field'));
    await tester.enterText(field, 'alpha');
    await _settle(tester);
    expect(_visibleNames(tester), unorderedEquals(['Alpha']));

    await tester.enterText(field, 'nothing-matches');
    await _settle(tester);
    expect(_visibleNames(tester), isEmpty);
    expect(find.text('未找到匹配的项目'), findsOneWidget);

    // The clear button empties the query without collapsing the bar.
    await tester.tap(find.byTooltip('清屏'));
    await _settle(tester);
    expect(_visibleNames(tester), unorderedEquals(['Alpha', 'Beta']));
    expect(find.byType(CollapsedSearchField), findsOneWidget);
    fixture.dispose();
  });

  testWidgets('searching shows the all-projects list, not the current tab', (
    tester,
  ) async {
    final fixture = await _mount(tester, root);
    // The first tab is 历史项目, which lists projects in store order and has no
    // language chips. Only the all-projects scope has the chips and sorts by
    // name, so those two facts tell the lists apart.
    expect(
      find.byKey(const ValueKey('home-scope-page-history')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(FilterChip), findsNothing);
    final byName = [..._visibleNames(tester)]..sort();
    expect(byName, ['Alpha', 'Beta']);
    expect(_visibleNames(tester), isNot(equals(byName)));

    await tester.tap(find.byType(CollapsedSearchButton));
    await _settle(tester);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(FilterChip), findsWidgets);
    expect(_visibleNames(tester), byName);
    fixture.dispose();
  });

  testWidgets('path matching is unchanged', (tester) async {
    final fixture = await _mount(tester, root);
    await tester.tap(find.byType(CollapsedSearchButton));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('home-project-search-field')),
      'beta',
    );
    await _settle(tester);
    expect(_visibleNames(tester), ['Beta']);
    fixture.dispose();
  });

  testWidgets('collapsing the search clears the filter', (tester) async {
    final fixture = await _mount(tester, root);
    await tester.tap(find.byType(CollapsedSearchButton));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('home-project-search-field')),
      'beta',
    );
    await _settle(tester);
    expect(_visibleNames(tester), ['Beta']);

    await tester.tap(find.byTooltip('退出搜索'));
    await _settle(tester);
    expect(find.byType(CollapsedSearchField), findsNothing);
    expect(_visibleNames(tester), unorderedEquals(['Alpha', 'Beta']));
    // Reopening starts from an empty field, and the unfiltered all-projects
    // list is back.
    await tester.tap(find.byType(CollapsedSearchButton));
    await _settle(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('home-project-search-field')),
    );
    expect(field.controller!.text, isEmpty);
    expect(_visibleNames(tester), unorderedEquals(['Alpha', 'Beta']));
    fixture.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the field stays inside the toolbar at text scale $scale', (
      tester,
    ) async {
      final fixture = await _mount(tester, root, textScale: scale, width: 340);
      await tester.tap(find.byType(CollapsedSearchButton));
      await _settle(tester);

      final field = find.byKey(const ValueKey('home-project-search-field'));
      final bar = tester.getRect(find.byType(AppBar));
      final input = tester.getRect(field);
      expect(input.top, greaterThanOrEqualTo(bar.top));
      expect(input.bottom, lessThanOrEqualTo(bar.bottom));
      expect(tester.takeException(), isNull);
      fixture.dispose();
    });
  }
}

/// Names of the project cards on screen right now.
///
/// Reads the cards rather than the text widgets, so a neighbouring page that
/// [TabBarView] keeps alive cannot contribute names to the result.
List<String> _visibleNames(WidgetTester tester) => [
  for (final element in find
      .byType(ProjectCard, skipOffstage: true)
      .evaluate())
    (element.widget as ProjectCard).project.name,
];

Future<_Fixture> _mount(
  WidgetTester tester,
  Directory root, {
  double textScale = 1,
  double width = 700,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final fixture = _Fixture.create(root);
  await tester.runAsync(fixture.projects.load);
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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
  _Fixture(this.directory, this.projects);

  final Directory directory;
  final ProjectStore projects;
  final auth = AuthStore();
  final settings = SettingsStore();

  factory _Fixture.create(Directory root) {
    final directory = root.createTempSync('search_');
    Project make(String name) {
      final projectDirectory = Directory(p.join(directory.path, name))
        ..createSync();
      File(
        p.join(projectDirectory.path, 'Main.java'),
      ).writeAsStringSync('class Main {}');
      return Project.create(
        name: name,
        path: projectDirectory.path,
        language: 'Java',
        type: 'java',
      );
    }

    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'projects': [make('Alpha').toJson(), make('Beta').toJson()],
        }),
      );
    return _Fixture(directory, ProjectStore(storageFile: registry));
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
