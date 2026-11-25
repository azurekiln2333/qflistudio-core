import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import 'support/content_catalog_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('pi-d-ui-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    await AppPaths.storageDirectory();
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  setUp(() {
    originalProfile = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() => StudioProfile.current = originalProfile);

  testWidgets('settings uses a 240dp category rail and 720dp detail column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsStore(
      storageFile: File('${root.path}/settings.json'),
    );
    final shell = LargeScreenController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
      settings.dispose();
    });

    await tester.pumpWidget(
      _app(
        LargeScreenScope(
          controller: shell,
          child: SettingsPage(settings: settings, showAi: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.ancestor(
      of: find.text('外观与体验').first,
      matching: find.byType(ListView),
    );
    expect(rail, findsWidgets);
    expect(find.byType(AppBar), findsNothing);
    // 设置 repeats on a large screen: rail heading, page heading, and one
    // shortcut row title. Assert the rail heading specifically, since a bare
    // text count would pin unrelated shortcut content.
    expect(
      find.descendant(
        of: find.byType(ListTile).first,
        matching: find.text('外观与体验'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-ui-zoom'))).width,
      lessThanOrEqualTo(720),
    );
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('项目回收站'), findsNothing);

    final editorCategory = find.ancestor(
      of: find.text('编辑器').first,
      matching: find.byType(ListTile),
    );
    await tester.tap(editorCategory.first);
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsNothing);
    expect(find.text('编辑器字体'), findsOneWidget);

    final dataCategory = find.ancestor(
      of: find.text('数据与存储').first,
      matching: find.byType(ListTile),
    );
    await tester.tap(dataCategory.first);
    await tester.pumpAndSettle();
    expect(find.text('项目回收站').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large-screen profile and tools use page headings without AppBars',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final shell = LargeScreenController();
      final auth = AuthStore(storageFile: File('${root.path}/auth.json'));
      final settings = SettingsStore(
        storageFile: File('${root.path}/settings.json'),
      );
      final store = ProjectStore(
        storageFile: File('${root.path}/projects.json'),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        shell.dispose();
        auth.dispose();
        settings.dispose();
        store.dispose();
      });

      await tester.pumpWidget(
        _app(
          LargeScreenScope(
            controller: shell,
            child: ProfileTab(auth: auth, settings: settings, store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('我的'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          LargeScreenScope(
            controller: shell,
            child: FunctionsTab(onOpenTerminal: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('工具'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone keeps the AppBar, flat list, and no category rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsStore(
      storageFile: File('${root.path}/phone-settings.json'),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    });

    // No LargeScreenScope here: this is the untouched phone path.
    await tester.pumpWidget(
      _app(SettingsPage(settings: settings, showAi: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // The 240dp category rail and the zoom row are large-screen only.
    expect(find.byKey(const ValueKey('settings-ui-zoom')), findsNothing);

    await tester.pumpWidget(_app(const FunctionsTab(onOpenTerminal: _noop)));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone tutorial keeps its original AppBar title style', (
    tester,
  ) async {
    final shell = LargeScreenController();
    addTearDown(() => shell.dispose());

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final title = appBar.title! as Text;
    final context = tester.element(find.byType(AppBar));
    final theme = Theme.of(context);
    expect(
      title.style,
      theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-screen tutorial content uses a responsive card grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final shell = LargeScreenController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
    });

    await tester.pumpWidget(
      _app(
        LargeScreenScope(
          controller: shell,
          child: TutorialCenterPage(
            language: 'java',
            repository: FixtureContentRepository(fixtureCatalog()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Card), findsWidgets);
    await tester.tap(find.byTooltip('搜索标题、简介或知识点'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-query')), findsOneWidget);
    expect(find.byTooltip('退出搜索'), findsOneWidget);
    await tester.tap(find.byTooltip('退出搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-query')), findsNothing);

    final first = tester.getRect(find.text('Java lesson 0-0'));
    final second = tester.getRect(find.text('Java lesson 0-1'));
    expect(first.top, closeTo(second.top, 1));
    expect(first.left, isNot(second.left));

    tester.view.physicalSize = const Size(620, 1000);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(Card).first).width,
      greaterThanOrEqualTo(280),
    );
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF6750A4),
  ),
  home: home,
);

class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
