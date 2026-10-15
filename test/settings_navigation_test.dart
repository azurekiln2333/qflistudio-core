@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/about_page.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_backup_service.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/picker_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// Navigation and data-labelling contract for the real Settings/Profile UI:
///
///   * Both the `ProfileTab` “关于” entry and the `SettingsPage` “关于” entry
///     must open the shared `AboutPage` through their real `onTap` handlers —
///     not by importing the helper directly in the test — so a regression in
///     the page wiring (a raw `AboutDialog`, a dead button, a missing export)
///     fails here.
///   * The backup/restore section must describe the full-data `.qfliz` archive
///     and must no longer offer the old single-project JSON export/import.
///
/// Paths are backed by a temporary provider so nothing touches real user data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? previousProfile;
  late Directory pathRoot;
  late PathProviderPlatform originalPaths;
  late _Stores stores;

  setUpAll(() async {
    pathRoot = await Directory.systemTemp.createTemp(
      'qfli_settings_nav_paths_',
    );
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(pathRoot.path);
    // Resolve once so the path provider stays on its fast path; without it the
    // 2 s `.timeout` guard can leave a pending timer that fails teardown.
    await AppPaths.storageDirectory();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (pathRoot.existsSync()) pathRoot.deleteSync(recursive: true);
  });

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'nav',
      appTitle: 'NavStudio',
      productKey: 'nav',
      templates: [],
      isOffline: true,
    );
    stores = _Stores();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    stores.dispose();
  });

  group('SettingsPage About entry', () {
    testWidgets('taps through to the shared AboutPage and Back returns', (
      tester,
    ) async {
      await _pumpSettingsPage(tester, stores);

      expect(find.byType(SettingsPage), findsOneWidget);
      final entry = find.text('关于 NavStudio');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.text('NavStudio'), findsOneWidget);
      expect(find.text('版本 $kQfliAboutVersion'), findsOneWidget);

      // The AppBar's leading BackButton returns to Settings.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses full-backup .qfliz wording, not project JSON actions', (
      tester,
    ) async {
      await _pumpSettingsPage(tester, stores);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('导出全部数据'),
        240,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(find.text('导出全部数据'), findsOneWidget);
      expect(find.textContaining('.qfliz'), findsWidgets);
      expect(find.text('导入全部数据'), findsOneWidget);

      // The old single-project JSON export/import actions are gone.
      expect(find.textContaining('导出项目'), findsNothing);
      expect(find.textContaining('导入项目'), findsNothing);
      expect(find.textContaining('.qfli.json'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsPage backup UI', () {
    late Directory backupRoot;
    String? savedSuggestedName;

    setUp(() {
      backupRoot = Directory.systemTemp.createTempSync('qfli_nav_root_');
      // A dedicated private root keeps the real export/import off user data.
      AppBackupService.rootOverride = backupRoot.path;
      // Force the native picker channel even on the desktop VM test host so the
      // mocked handler (not file_selector) drives the flow.
      PickerService.forcePlatformChannel = true;
      savedSuggestedName = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qflistudio/platform'),
            (call) async {
              if (call.method == 'saveDocument') {
                savedSuggestedName =
                    (call.arguments as Map?)?['suggestedName'] as String?;
              }
              // Always cancel so no real file is written; the UI still runs the
              // full "choose target" path.
              return null;
            },
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qflistudio/platform'),
            null,
          );
      AppBackupService.rootOverride = null;
      PickerService.forcePlatformChannel = false;
      if (backupRoot.existsSync()) backupRoot.deleteSync(recursive: true);
    });

    testWidgets('export suggests a .qfliz name based on the product key', (
      tester,
    ) async {
      await _pumpSettingsPage(tester, stores);
      await tester.scrollUntilVisible(
        find.text('导出全部数据'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('导出全部数据'));
      // A progress indicator animates while the operation runs, so settle with
      // bounded pumps rather than `pumpAndSettle`, which never completes.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(savedSuggestedName, isNotNull);
      expect(savedSuggestedName, endsWith('.qfliz'));
      // Product-key based, and never the old project JSON name.
      expect(savedSuggestedName, contains('nav'));
      expect(savedSuggestedName, isNot(contains('.qfli.json')));
      // Cancelling the picker must leave both entries enabled again and the
      // progress row gone.
      expect(find.text('导出全部数据'), findsOneWidget);
      expect(_tileEnabled(tester, '导出全部数据'), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('export busy state disables both entries and shows progress', (
      tester,
    ) async {
      // Keep the save-location future pending so the busy UI is observable.
      final completer = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qflistudio/platform'),
            (call) async {
              if (call.method == 'saveDocument') return completer.future;
              return null;
            },
          );

      await _pumpSettingsPage(tester, stores);
      await tester.scrollUntilVisible(
        find.text('导出全部数据'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('导出全部数据'));
      await tester.pump();

      // While busy: progress row visible, both tiles disabled.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(_tileEnabled(tester, '导出全部数据'), isFalse);
      expect(_tileEnabled(tester, '导入全部数据'), isFalse);

      completer.complete(null);
      // Busy spinner animates until the save future resolves; bounded pumps
      // avoid `pumpAndSettle` never completing on the progress indicator.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Target cancelled: busy cleared, both tiles enabled again.
      expect(_tileEnabled(tester, '导出全部数据'), isTrue);
      expect(_tileEnabled(tester, '导入全部数据'), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposal during picker skips compression and file write', (
      tester,
    ) async {
      // The picker returns a real local destination, so if the disposal guard
      // were missing the post-export `File.copy` would create this file.
      final destination = p.join(backupRoot.path, 'should-not-exist.qfliz');
      final completer = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qflistudio/platform'),
            (call) async {
              if (call.method == 'saveDocument') return completer.future;
              return null;
            },
          );

      await _pumpSettingsPage(tester, stores);
      await tester.scrollUntilVisible(
        find.text('导出全部数据'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('导出全部数据'));
      await tester.pump();

      // Dispose the page while the picker future is still pending.
      await tester.pumpWidget(const SizedBox.shrink());

      completer.complete({'path': destination});
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // No compression, no destination write, and no post-dispose error.
      expect(File(destination).existsSync(), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('ProfileTab About entry', () {
    testWidgets('taps through to the shared AboutPage and Back returns', (
      tester,
    ) async {
      await _pumpProfileTab(tester, stores);

      expect(find.byType(ProfileTab), findsOneWidget);
      final entry = find.text('关于 NavStudio');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.text('NavStudio'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(ProfileTab), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpSettingsPage(WidgetTester tester, _Stores stores) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app(home: SettingsPage(settings: stores.settings)));
  await tester.pumpAndSettle();
}

/// Whether the `ListTile` whose title is [label] is enabled.
bool _tileEnabled(WidgetTester tester, String label) {
  final tile = tester.widget<ListTile>(
    find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
  );
  return tile.enabled;
}

Future<void> _pumpProfileTab(WidgetTester tester, _Stores stores) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _app(
      home: Scaffold(
        body: ProfileTab(
          auth: stores.auth,
          settings: stores.settings,
          store: stores.projects,
        ),
      ),
    ),
  );
  // The profile activity layer schedules a short refresh; drain it so the
  // tree can settle and teardown is clean.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app({required Widget home}) => MaterialApp(
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  locale: const Locale('zh', 'CN'),
  home: home,
);

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
  _TemporaryPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}
