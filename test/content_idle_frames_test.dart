import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
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
import 'package:qfli_studio_core/widgets/code_snippet.dart';

import 'support/content_catalog_fixture.dart';

// Run this suite again with --dart-define=CONTENT_IDLE_OHOS=true. Each process
// initializes AppTheme's cached ThemeData under its actual target platform.
const _useOhos = bool.fromEnvironment('CONTENT_IDLE_OHOS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;
  final platformVariant = TargetPlatformVariant.only(
    _useOhos ? TargetPlatform.ohos : TargetPlatform.android,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('qfli_content_idle_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
    await TaskActivityService.instance.initialize();
  });

  setUp(() => originalProfile = StudioProfile.current);

  tearDown(() => StudioProfile.current = originalProfile);

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  testWidgets(
    'Home examples and detail stop scheduling frames while idle',
    (tester) async {
      final stores = _Stores();
      addTearDown(stores.dispose);
      final repository = FixtureContentRepository(fixtureCatalog());
      await _mountHome(tester, stores, repository);
      await _selectTab(tester, 3);
      await _waitForExamples(tester);
      await _finishFiniteAnimations(tester);
      await _expectIdle(tester, 'examples catalog');

      await tester.tap(find.text('Java example 0'));
      await _finishFiniteAnimations(tester);
      expect(find.byType(ExampleDetailPage), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'System.out.println("example 0");');
      await _expectIdle(tester, 'unfocused editable example');

      await tester.enterText(
        find.byType(TextField),
        'System.out.println("changed");',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _finishFiniteAnimations(tester);
      expect(field.controller!.text, 'System.out.println("changed");');
      await _expectIdle(tester, 'example after editing and releasing focus');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platformVariant,
  );

  testWidgets(
    'hidden loading tutorial stops ticking and resumes on return',
    (tester) async {
      final stores = _Stores();
      addTearDown(stores.dispose);
      final repository = _PendingTutorialRepository(fixtureCatalog());
      await _mountHome(tester, stores, repository);
      await _selectTab(tester, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _expectAnimating(tester);

      await _selectTab(tester, 3);
      await _waitForExamples(tester);
      await _finishFiniteAnimations(tester);
      expect(
        find.byType(LocalTutorialsTab, skipOffstage: false),
        findsOneWidget,
      );
      expect(repository.tutorialsReady.isCompleted, isFalse);
      await _expectIdle(tester, 'examples with a retained loading tutorial');

      await tester.tap(find.text('Java example 0'));
      await _finishFiniteAnimations(tester);
      await _expectIdle(tester, 'detail with a retained loading tutorial');
      await tester.pageBack();
      await _finishFiniteAnimations(tester);
      await _selectTab(tester, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _expectAnimating(tester);
      expect(repository.tutorialRequests, 1);

      repository.tutorialsReady.complete();
      await _finishFiniteAnimations(tester);
      expect(find.text('Java lesson 0-0'), findsOneWidget);
      await _expectIdle(tester, 'tutorial after loading completes');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platformVariant,
  );

  testWidgets(
    'static selectable CodeSnippet does not request idle frames',
    (tester) async {
      final example = fixtureCatalog().examples.first;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CodeSnippet(
              example: ExampleCode(
                id: example.id,
                type: example.type,
                title: example.title,
                summary: example.summary,
                code: example.code,
                output: example.expectedOutput,
              ),
            ),
          ),
        ),
      );
      await _finishFiniteAnimations(tester);
      await _expectIdle(tester, 'static tutorial code');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platformVariant,
  );
}

Future<void> _mountHome(
  WidgetTester tester,
  _Stores stores,
  ContentRepository repository,
) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  StudioProfile.current = StudioProfile(
    id: 'java',
    appTitle: 'QFLIJVMX',
    templates: const [ProjectTemplate.empty],
    productKey: StudioProductCatalog.jvmxKey,
    isOffline: true,
    contentRepositoryFactory: () => repository,
  );
  await tester.pumpWidget(
    QfliApp(
      store: stores.projects,
      auth: stores.auth,
      settings: stores.settings,
    ),
  );
  await _finishFiniteAnimations(tester);
  expect(
    Theme.of(tester.element(find.byType(HomePage))).platform,
    _useOhos ? TargetPlatform.ohos : TargetPlatform.android,
  );
}

Future<void> _selectTab(WidgetTester tester, int index) async {
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

Future<void> _waitForExamples(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (find.text('Java example 0').evaluate().isNotEmpty) return;
    // Saved examples use actual filesystem IO, independent of the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  fail('The example catalog did not appear');
}

Future<void> _finishFiniteAnimations(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

Future<void> _expectIdle(WidgetTester tester, String state) async {
  // Finite route, navigation and ink animations have already completed. These
  // pumps advance two seconds, including delayed cursor/animation callbacks;
  // the page must not schedule another frame on any sampled frame boundary.
  // A post-frame callback does not itself request a frame. It also catches a
  // timer requesting a frame that pump renders before hasScheduledFrame is read.
  var drewIdleFrame = false;
  tester.binding.addPostFrameCallback((_) => drewIdleFrame = true);
  for (var frame = 0; frame < 20; frame++) {
    expect(tester.binding.hasScheduledFrame, isFalse, reason: state);
    expect(tester.binding.transientCallbackCount, 0, reason: state);
    await tester.pump(const Duration(milliseconds: 100));
    expect(drewIdleFrame, isFalse, reason: state);
  }
  expect(tester.binding.hasScheduledFrame, isFalse, reason: state);
  expect(tester.binding.transientCallbackCount, 0, reason: state);
}

Future<void> _expectAnimating(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

MaterialApp _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light,
  home: home,
);

class _PendingTutorialRepository extends FixtureContentRepository {
  _PendingTutorialRepository(super.catalog);

  final tutorialsReady = Completer<void>();
  var tutorialRequests = 0;

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async {
    tutorialRequests++;
    await tutorialsReady.future;
    return super.tutorials(filter: filter);
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
