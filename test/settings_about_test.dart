import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
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

      expect(find.text(profile.appTitle), findsOneWidget);
      expect(find.text('离线代码编辑器。管理本地项目，编写代码，学习教程与示例。'), findsOneWidget);
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
      expect(find.text('轻量代码编辑器与开发者社区。管理项目，编写代码，分享你的经验。'), findsOneWidget);
      expect(find.textContaining('离线代码编辑器'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
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
  expect(find.byType(AboutDialog), findsOneWidget);
}
