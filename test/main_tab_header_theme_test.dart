import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/about_page.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

import 'support/content_catalog_fixture.dart';

/// Pins the "main tab header" polish: every primary tab titles itself with
/// `titleLarge` tinted by `colorScheme.primary`, instead of the default AppBar
/// foreground. The colour is deliberately theme-driven so a brand-seed change
/// is reflected automatically.
///
/// The shared shell renders these pages for the offline language products
/// (including QFLIForge), so a regression here propagates to the device.
void main() {
  StudioProfile? originalProfile;

  setUp(() {
    originalProfile = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  /// Asserts the AppBar title [label] is tinted with the primary colour and
  /// sized like `titleLarge`.
  void expectPrimaryTitle(WidgetTester tester, String label) {
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(AppBar), matching: find.text(label)),
    );
    final context = tester.element(find.byType(AppBar));
    final theme = Theme.of(context);
    expect(
      text.style?.color,
      theme.colorScheme.primary,
      reason: '$label title must use colorScheme.primary',
    );
    expect(
      text.style?.fontSize,
      theme.textTheme.titleLarge?.fontSize,
      reason: '$label title must be sized like titleLarge',
    );
  }

  testWidgets('tools tab header uses the primary title colour', (tester) async {
    await _pump(tester, FunctionsTab(onOpenTerminal: () {}));
    expectPrimaryTitle(tester, '工具');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial tab header uses the primary title colour', (
    tester,
  ) async {
    await _pump(
      tester,
      LocalTutorialsTab(
        language: 'java',
        repository: FixtureContentRepository(fixtureCatalog()),
      ),
    );
    await tester.pumpAndSettle();
    expectPrimaryTitle(tester, '教程');
    expect(tester.takeException(), isNull);
  });

  testWidgets('examples tab header uses the primary title colour', (
    tester,
  ) async {
    await _pump(
      tester,
      ExampleCodeTab(
        language: 'java',
        repository: FixtureContentRepository(fixtureCatalog()),
      ),
    );
    await tester.pumpAndSettle();
    expectPrimaryTitle(tester, '示例代码');
    expect(tester.takeException(), isNull);
  });

  testWidgets('QFLIForge About shows its branding and feedback group', (
    tester,
  ) async {
    // Matches qfli_c's `forgeProfile`: offline-only Forge shell shipped to the
    // OHOS device. The About copy must describe C/C++ rather than the generic
    // online community text.
    StudioProfile.current = const StudioProfile(
      id: StudioProductCatalog.forgeKey,
      appTitle: StudioProductCatalog.forge,
      productKey: StudioProductCatalog.forgeKey,
      templates: [
        ProjectTemplate.empty,
        ProjectTemplate.c,
        ProjectTemplate.cpp,
      ],
      isOffline: true,
      offlineOnly: true,
    );

    await _pump(tester, const AboutPage());
    await tester.pumpAndSettle();

    expect(find.text(StudioProductCatalog.forge), findsOneWidget);
    expect(find.text('版本 $kQfliAboutVersion'), findsOneWidget);
    expect(find.textContaining('C / C++ 开发工具'), findsOneWidget);
    expect(find.text('反馈与交流'), findsOneWidget);
    expect(find.widgetWithText(SelectableText, '694120628'), findsOneWidget);
    expect(find.textContaining('开发者社区'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile tab header uses the primary title colour', (
    tester,
  ) async {
    final projects = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(() {
      projects.dispose();
      auth.dispose();
      settings.dispose();
    });

    await _pump(
      tester,
      ProfileTab(auth: auth, settings: settings, store: projects),
    );
    expectPrimaryTitle(tester, '我的');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: StudioLocalizations.supportedLocales,
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      home: home,
    ),
  );
  await tester.pump();
}
