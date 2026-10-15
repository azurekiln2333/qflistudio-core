import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/about_page.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  StudioProfile? originalProfile;

  setUp(() {
    originalProfile = StudioProfile.current;
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  for (final profile in const [
    StudioProfile(
      id: 'python',
      appTitle: StudioProductCatalog.pyFlow,
      templates: [],
      isOffline: true,
    ),
    StudioProfile(
      id: 'java',
      appTitle: StudioProductCatalog.jvmx,
      templates: [],
      offlineOnly: true,
    ),
  ]) {
    testWidgets('About identifies offline ${profile.appTitle}', (tester) async {
      StudioProfile.current = profile;

      await _openAbout(tester);

      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.text(profile.appTitle), findsOneWidget);
      expect(find.text('版本 $kQfliAboutVersion'), findsOneWidget);
      expect(find.text(kQfliOfflineDescription), findsOneWidget);
      expect(find.textContaining('开发者社区'), findsNothing);
      expect(find.text(StudioProductCatalog.qfliStudio), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final profile in const <StudioProfile?>[
    null,
    StudioProfile(
      id: 'online',
      appTitle: 'Online Studio',
      templates: [],
      isOffline: true,
      offlineOnly: false,
    ),
  ]) {
    testWidgets('About preserves online ${profile?.appTitle ?? 'default'}', (
      tester,
    ) async {
      StudioProfile.current = profile;

      await _openAbout(tester);

      expect(
        find.text(profile?.appTitle ?? StudioProductCatalog.qfliStudio),
        findsOneWidget,
      );
      expect(find.text('版本 $kQfliAboutVersion'), findsOneWidget);
      expect(find.text(kQfliOnlineDescription), findsOneWidget);
      expect(find.textContaining('离线代码编辑器'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('About is a secondary page that Back closes', (tester) async {
    StudioProfile.current = null;

    await _openAbout(tester);
    expect(find.byType(AboutPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsNothing);
    expect(find.text('About'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About opens the standard open-source licenses page', (
    tester,
  ) async {
    StudioProfile.current = null;

    await _openAbout(tester);
    expect(find.text('开源许可'), findsOneWidget);

    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About stays scrollable and unbounded on narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    StudioProfile.current = const StudioProfile(
      id: 'long',
      appTitle: 'QFLIStudioWithAnExtremelyLongProductNameForLayout',
      templates: [],
      isOffline: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        // A MediaQuery placed *outside* MaterialApp is replaced by the one
        // `MaterialApp` builds from `View`; override inside `builder` so the
        // real render tree actually carries the 2x text scale.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const AboutPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
    // Prove the large text actually reached the page, not just a detached
    // wrapper: the AboutPage subtree sees a 2x scaler.
    final aboutContext = tester.element(find.byType(AboutPage));
    expect(MediaQuery.textScalerOf(aboutContext).scale(10), 20);
    expect(tester.takeException(), isNull);
    // At 2x text on a 320dp screen the whole body sits below the fold; the
    // page must scroll to reveal it without rendering overflow errors.
    await tester.scrollUntilVisible(find.text('开源许可'), 200);
    expect(find.text('开源许可'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAbout(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showQfliAbout(context),
            child: const Text('About'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('About'));
  await tester.pumpAndSettle();
}
