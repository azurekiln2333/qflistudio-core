import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/content/asset_content_repository.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

import 'support/content_catalog_fixture.dart';

/// Run after applying the Home integration snippet in content/handoff.md.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('qfli_home_content_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
    await TaskActivityService.instance.initialize();
  });

  setUp(() {
    originalProfile = StudioProfile.current;
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          if (message == null) return null;
          final key = utf8.decode(
            message.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          final source = key.endsWith(AssetContentRepository.tutorialAsset)
              ? tutorialSource
              : key.endsWith(AssetContentRepository.exampleAsset)
              ? exampleSource
              : null;
          return source == null
              ? null
              : ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
        });
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  testWidgets(
    'Home calls the custom content factory once for both retained tabs',
    (tester) async {
      _useCompactSurface(tester);
      var calls = 0;
      late FixtureContentRepository repository;
      StudioProfile.current = _profile(
        factory: () {
          calls++;
          return repository = FixtureContentRepository(fixtureCatalog());
        },
      );
      final stores = _Stores();
      addTearDown(stores.dispose);
      await tester.pumpWidget(_app(stores));
      await _selectTab(tester, 2);
      final tutorials = tester.widget<LocalTutorialsTab>(
        find.byType(LocalTutorialsTab),
      );
      expect(tutorials.repository, same(repository));
      expect(find.text('Java lesson 0-0'), findsOneWidget);
      await _selectTab(tester, 3);
      final examples = tester.widget<ExampleCodeTab>(
        find.byType(ExampleCodeTab),
      );
      expect(examples.repository, same(repository));
      await _waitFor(
        tester,
        () => find.text('Java example 0').evaluate().isNotEmpty,
      );
      expect(calls, 1);
      await _selectTab(tester, 0);
      await _selectTab(tester, 2);
      await _selectTab(tester, 3);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Home supplies the same asset repository when the factory is null',
    (tester) async {
      _useCompactSurface(tester);
      StudioProfile.current = _profile();
      final stores = _Stores();
      addTearDown(stores.dispose);
      await tester.pumpWidget(_app(stores));
      await _selectTab(tester, 2);
      final tutorials = tester.widget<LocalTutorialsTab>(
        find.byType(LocalTutorialsTab),
      );
      expect(tutorials.repository, isA<AssetContentRepository>());
      await _waitFor(
        tester,
        () => find.text('Java lesson 0-0').evaluate().isNotEmpty,
      );
      await _selectTab(tester, 3);
      final examples = tester.widget<ExampleCodeTab>(
        find.byType(ExampleCodeTab),
      );
      expect(examples.repository, same(tutorials.repository));
      await _waitFor(
        tester,
        () => find.text('Java example 0').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

StudioProfile _profile({ContentRepository Function()? factory}) =>
    StudioProfile(
      id: 'java',
      appTitle: 'QFLIJVMX',
      templates: const [ProjectTemplate.empty],
      productKey: StudioProductCatalog.jvmxKey,
      isOffline: true,
      contentRepositoryFactory: factory,
    );

MaterialApp _app(_Stores stores) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light,
  home: HomePage(
    store: stores.projects,
    auth: stores.auth,
    settings: stores.settings,
  ),
);

void _useCompactSurface(WidgetTester tester) {
  // Keep the NavigationBar under test regardless of the runner's default view.
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _selectTab(WidgetTester tester, int index) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final destinations = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byWidgetPredicate((widget) => widget is InkResponse),
  );
  expect(destinations, findsNWidgets(5));
  await tester.tap(destinations.at(index));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  // Let actual I/O/isolate work progress; these durations are polling and route
  // animation steps, never assertions about how quickly content must load.
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (condition()) return;
  }
  fail('The Home catalog did not appear');
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

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getExternalStoragePath() async => path;
}
