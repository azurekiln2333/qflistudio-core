import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/local_stats_audit_pages.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/services/local_audit_service.dart';
import 'package:qfli_studio_core/services/local_stats_service.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

/// Widget tests for the local stats and audit entries and pages.
///
/// They must appear for **every** product, offline or not, which is the
/// opposite of the server-backed 签到与积分 / 管理 sections.
///
/// Every service under test is injected with an in-memory backend and a zero
/// flush delay, so no file IO and no throttling timer exists to keep the test
/// process alive. `pumpAndSettle` is avoided for the same reason.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? originalProfile;

  setUp(() {
    originalProfile = StudioProfile.current;
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  /// A bounded pump pair; these pages keep timers and scroll physics alive, so
  /// `pumpAndSettle` cannot be used.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  LocalStatsService buildStats() => LocalStatsService(
    backend: LocalMemoryBackend(),
    clock: () => DateTime(2026, 5, 10, 9),
    flushDelay: Duration.zero,
  );

  LocalAuditService buildAudit() => LocalAuditService(
    backend: LocalMemoryBackend(),
    clock: () => DateTime(2026, 5, 10, 9),
    flushDelay: Duration.zero,
  );

  Future<void> mountProfile(
    WidgetTester tester, {
    required bool offlineOnly,
  }) async {
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'QFLIJVMX',
      templates: const [ProjectTemplate.empty],
      isOffline: offlineOnly,
      offlineOnly: offlineOnly,
    );
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final projects = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(() {
      projects.dispose();
      auth.dispose();
      settings.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          StudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN')],
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: ProfileTab(
            auth: auth,
            settings: settings,
            store: projects,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  group('profile entries', () {
    testWidgets('an offline product shows the local stats and audit entries', (
      tester,
    ) async {
      await mountProfile(tester, offlineOnly: true);
      // The local section is present even though every server entry is hidden.
      expect(find.text('本机记录'), findsOneWidget);
      expect(find.text('本地统计'), findsOneWidget);
      expect(find.text('本地审计'), findsOneWidget);
      // And the server entries really are still hidden, so the two paths are
      // genuinely separate.
      expect(find.text('签到与积分'), findsNothing);
      expect(find.text('管理'), findsNothing);
    });

    testWidgets('a networked product shows both local and server entries', (
      tester,
    ) async {
      await mountProfile(tester, offlineOnly: false);
      expect(find.text('本机记录'), findsOneWidget);
      expect(find.text('本地统计'), findsOneWidget);
      // qflistudio keeps its own pages: neither was replaced.
      expect(find.text('签到与积分'), findsOneWidget);
    });

    testWidgets('the local stats entry opens the page', (tester) async {
      await mountProfile(tester, offlineOnly: true);
      // Tap through to the page, then let its load settle inside `runAsync` so
      // the singleton's real file backend can resolve its directory without a
      // pending timer aborting the test.
      await tester.runAsync(() async {
        await tester.tap(find.text('本地统计'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(find.byType(LocalStatsPage), findsOneWidget);
    });

    testWidgets('the local audit entry opens the page', (tester) async {
      await mountProfile(tester, offlineOnly: true);
      await tester.runAsync(() async {
        await tester.tap(find.text('本地审计'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(find.byType(LocalAuditPage), findsOneWidget);
    });
  });

  group('LocalStatsPage', () {
    Future<void> mountPage(
      WidgetTester tester,
      LocalStatsService service,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: LocalStatsPage(service: service)),
      );
      await settle(tester);
    }

    testWidgets('renders the counters it has recorded', (tester) async {
      final service = buildStats();
      addTearDown(service.dispose);
      await service.load();
      await service.recordSave(
        project: 'demo',
        path: 'Main.java',
        previousLineCount: 3,
        newLineCount: 9,
      );
      await service.recordRun(succeeded: true, project: 'demo');

      await mountPage(tester, service);
      expect(find.text('本地统计'), findsOneWidget);
      expect(find.text('概览'), findsOneWidget);
      // One save and one successful run are reflected in the grid.
      expect(find.text('1'), findsWidgets);
      expect(find.text('+6'), findsOneWidget);
    });

    testWidgets('renders the streak, trend and distribution sections', (
      tester,
    ) async {
      final service = buildStats();
      addTearDown(service.dispose);
      await service.load();
      await service.recordFileEdited(project: 'demo', path: 'A.java');

      await mountPage(tester, service);
      expect(find.text('连续天数'), findsOneWidget);
      expect(find.text('当前连续'), findsOneWidget);
      expect(find.text('最长连续'), findsOneWidget);
      expect(find.text('近 7 天'), findsOneWidget);
      expect(find.text('近 30 天'), findsOneWidget);
      expect(find.text('活动热力图'), findsOneWidget);
      expect(find.text('语言分布'), findsOneWidget);
      expect(find.text('.java'), findsOneWidget);
    });

    testWidgets('an empty store renders without error', (tester) async {
      final service = buildStats();
      addTearDown(service.dispose);
      await service.load();
      await mountPage(tester, service);
      expect(find.text('还没有编辑记录'), findsOneWidget);
      expect(find.text('还没有项目记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LocalAuditPage', () {
    Future<void> mountPage(
      WidgetTester tester,
      LocalAuditService service,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: LocalAuditPage(service: service)),
      );
      await settle(tester);
    }

    testWidgets('lists recorded entries and filters by kind', (tester) async {
      final service = buildAudit();
      addTearDown(service.dispose);
      await service.load();
      await service.record(
        kind: LocalAuditKind.create,
        action: '创建项目 alpha',
        project: 'alpha',
      );
      await service.record(
        kind: LocalAuditKind.run,
        action: '运行 Main.java',
        project: 'alpha',
      );

      await mountPage(tester, service);
      expect(find.text('本地审计'), findsOneWidget);
      expect(find.text('创建项目 alpha'), findsOneWidget);
      expect(find.text('运行 Main.java'), findsOneWidget);

      // Filtering to runs only hides the create entry.
      await tester.tap(find.widgetWithText(FilterChip, '运行'));
      await settle(tester);
      expect(find.text('创建项目 alpha'), findsNothing);
      expect(find.text('运行 Main.java'), findsOneWidget);
    });

    testWidgets('search narrows the list', (tester) async {
      final service = buildAudit();
      addTearDown(service.dispose);
      await service.load();
      await service.record(kind: LocalAuditKind.save, action: '保存 alpha.java');
      await service.record(kind: LocalAuditKind.save, action: '保存 beta.java');

      await mountPage(tester, service);
      await tester.enterText(find.byType(TextField), 'beta');
      await settle(tester);
      expect(find.text('保存 beta.java'), findsOneWidget);
      expect(find.text('保存 alpha.java'), findsNothing);
    });

    testWidgets('an empty log shows the empty state', (tester) async {
      final service = buildAudit();
      addTearDown(service.dispose);
      await service.load();
      await mountPage(tester, service);
      expect(find.text('没有符合条件的记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
