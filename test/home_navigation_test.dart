import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

/// Navigation contract for the shared home shell.
///
/// Two behaviours are pinned here:
///
/// 1. Each tab carries its own title, and only the home tab shows the product
///    name (taken from `StudioProfile.appTitle`, never hard-coded).
/// 2. The profile page is always reachable, including for an offline-only
///    product. It used to be swapped for the examples tab whenever
///    `isOffline` was set, which made the page unreachable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_nav_');
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

  StudioProfile profileFor({bool offlineOnly = true}) => StudioProfile(
    id: 'java',
    appTitle: 'QFLIJVMX',
    templates: const [ProjectTemplate.empty],
    runner: const _NoopRunner(),
    isOffline: true,
    offlineOnly: offlineOnly,
    productKey: StudioProductCatalog.jvmxKey,
  );

  testWidgets('only the home tab shows the product name', (tester) async {
    StudioProfile.current = profileFor();
    final stores = _Stores();
    addTearDown(stores.dispose);

    await tester.pumpWidget(_app(stores));
    // Bounded pump: the home shell keeps a periodic timer alive, so
    // `pumpAndSettle` never returns.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Home shows the profile's app title.
    expect(find.text('QFLIJVMX'), findsWidgets);

    // The other tabs must not repeat it.
    for (final index in [1, 2, 3, 4]) {
      await _selectTab(tester, index);
      expect(
        find.text('QFLIJVMX'),
        findsNothing,
        reason: 'tab $index must not render the product name',
      );
    }
  });

  testWidgets('each tab has its own title', (tester) async {
    StudioProfile.current = profileFor();
    final stores = _Stores();
    addTearDown(stores.dispose);

    await tester.pumpWidget(_app(stores));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The destinations carry the labels, and the tool tab's page titles itself.
    expect(find.text('工具'), findsWidgets);
    expect(find.text('教程'), findsWidgets);
    expect(find.text('示例代码'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });

  testWidgets('the profile tab is reachable for an offline-only product', (
    tester,
  ) async {
    StudioProfile.current = profileFor();
    final stores = _Stores();
    addTearDown(stores.dispose);

    await tester.pumpWidget(_app(stores));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Five destinations, and the last one is the profile page rather than the
    // examples tab that used to replace it.
    await _selectTab(tester, 4);
    expect(find.byType(ProfileTab), findsOneWidget);
    expect(find.text('未登录'), findsNothing);
  });

  testWidgets('an offline-only profile page hides every login entry', (
    tester,
  ) async {
    StudioProfile.current = profileFor();
    final stores = _Stores();
    addTearDown(stores.dispose);

    await tester.pumpWidget(
      _app(stores, home: _profileHost(stores)),
    );
    await tester.pumpAndSettle();

    // No account surface at all: header, login prompt, statistics, sign-out and
    // the networked check-in sections.
    expect(find.text('未登录'), findsNothing);
    expect(find.text('签到与积分'), findsNothing);
    expect(find.text('每日任务'), findsNothing);
    expect(find.text('积分兑换'), findsNothing);
    expect(find.text('退出登录'), findsNothing);

    // The local-only sections must survive.
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('a networked profile page keeps the login entry', (tester) async {
    StudioProfile.current = profileFor(offlineOnly: false);
    final stores = _Stores();
    addTearDown(stores.dispose);

    await tester.pumpWidget(
      _app(stores, home: _profileHost(stores)),
    );
    await tester.pumpAndSettle();

    // The default keeps the previous behaviour, so other products are untouched.
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('签到与积分'), findsOneWidget);
  });
}

Widget _profileHost(_Stores stores) => Scaffold(
  body: ProfileTab(
    auth: stores.auth,
    settings: stores.settings,
    store: stores.projects,
  ),
);

Widget _app(_Stores stores, {Widget? home}) => MaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  // Pin the locale: the labels under test are the Chinese ones.
  locale: const Locale('zh', 'CN'),
  home:
      home ??
      HomePage(
        store: stores.projects,
        auth: stores.auth,
        settings: stores.settings,
      ),
);

Future<void> _selectTab(WidgetTester tester, int index) async {
  // The rendered destination controls are private `InkResponse` subclasses in
  // order, so pick the nth tappable region of the bar. Tapping the label text
  // directly does not work: it is not the hit target.
  final items = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byWidgetPredicate((widget) => widget is InkResponse),
  );
  expect(items, findsNWidgets(5), reason: 'five destinations are tappable');
  await tester.tap(items.at(index));
  // `pumpAndSettle` never settles here: the home shell keeps a periodic
  // activity/cloud timer running. Pump a bounded number of frames instead, long
  // enough for the 220 ms page animation.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _Stores {
  final projects = ProjectStore();
  final auth = AuthStore();
  final settings = SettingsStore();
  final directory = Directory.systemTemp.createTempSync('qfli_nav_stores_');

  void dispose() {
    projects.dispose();
    auth.dispose();
    settings.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

class _NoopRunner implements ProgramRunner {
  const _NoopRunner();

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    return null;
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
