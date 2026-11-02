@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/config/agreement_config.dart';
import 'package:qfli_studio_core/pages/auth/agreement_page.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// Settings-page compliance entries (整改任务书 §3-W3、§4 第 8 条).
///
/// The acceptance criterion is a click budget: the agreements must be reachable
/// from the main screen in at most four taps. The path is
/// 主界面 → 我的 → 设置 → 本页分组, so the entries have to be on the first
/// Settings screen — a second level would already be five taps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? previousProfile;
  late Directory root;
  late PathProviderPlatform originalPaths;
  late _Stores stores;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_settings_compliance_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'compliance',
      appTitle: 'Compliance',
      templates: [],
    );
    stores = _Stores();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    stores.dispose();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    AuthStore? auth,
    bool showAi = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The host channel is absent in a widget test; make that explicit instead of
    // depending on how the binding reports an unmocked channel.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('qflistudio/platform'),
      (call) async => call.method == 'requestPrivacyWithdraw' ? false : null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('qflistudio/platform'),
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: stores.settings,
          auth: auth,
          store: stores.projects,
          showAi: showAi,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('agreement configuration', () {
    test('the privacy policy is the exact hosted address from the task', () {
      expect(
        privacyPolicyUrl,
        'https://agreement-drcn.hispace.dbankcloud.cn/index.html'
        '?lang=zh&agreementId=2045441424513576896',
      );
      expect(privacyPolicyAvailable, isTrue);
    });

    test('the user agreement stays empty until the operator supplies it', () {
      // Documented leftover: the AGC-hosted user agreement URL is a user item.
      expect(userAgreementUrl, '');
      expect(userAgreementAvailable, isFalse);
    });
  });

  group('account and privacy section', () {
    testWidgets('shows all four entries on the first settings screen', (
      tester,
    ) async {
      final auth = await _signedIn(stores);
      await pumpSettings(tester, auth: auth);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('注销账号'),
        240,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(find.text('账户与隐私'), findsOneWidget);
      expect(find.text('用户协议'), findsOneWidget);
      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('撤回隐私政策同意'), findsOneWidget);
      expect(find.text('注销账号'), findsOneWidget);
      // An unpublished agreement says so rather than hiding the entry.
      expect(find.textContaining('暂未发布'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the privacy entry opens the shared agreement page', (
      tester,
    ) async {
      final auth = await _signedIn(stores);
      await pumpSettings(tester, auth: auth);
      await tester.scrollUntilVisible(
        find.text('隐私政策'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('隐私政策'));
      await tester.pumpAndSettle();

      final page = tester.widget<AgreementPage>(find.byType(AgreementPage));
      expect(page.title, '隐私政策');
      expect(page.url, privacyPolicyUrl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erase and withdraw are disabled while signed out', (
      tester,
    ) async {
      // The section exists for a sign-in capable product, so pass the store but
      // leave it signed out.
      await pumpSettings(tester, auth: stores.auth);
      await tester.scrollUntilVisible(
        find.text('注销账号'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_tileEnabled(tester, '注销账号'), isFalse);
      expect(_tileEnabled(tester, '撤回隐私政策同意'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an offline product has no account section at all', (
      tester,
    ) async {
      StudioProfile.current = const StudioProfile(
        id: 'offline',
        appTitle: 'Offline',
        templates: [],
        offlineOnly: true,
      );
      final auth = await _signedIn(stores);
      await pumpSettings(tester, auth: auth);
      expect(find.text('账户与隐私'), findsNothing);
      expect(find.text('注销账号'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('withdrawing consent signs out and never claims a host call', (
      tester,
    ) async {
      final auth = await _signedIn(stores);
      await pumpSettings(tester, auth: auth);
      await tester.scrollUntilVisible(
        find.text('撤回隐私政策同意'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('撤回隐私政策同意'));
      await tester.pumpAndSettle();

      // First confirmation dialog.
      expect(find.text('确认撤回'), findsOneWidget);
      await tester.tap(find.text('确认撤回'));
      // The handler reads the platform channel through an async guard, so a
      // plain settle can race; pump until the sign-out is visible.
      for (var i = 0; i < 10 && auth.isLoggedIn; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(auth.isLoggedIn, isFalse);
      await tester.pumpAndSettle();

      // Without a hosted privacy statement the UI must point at system settings.
      expect(find.textContaining('系统设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erasure needs the typed confirmation word', (tester) async {
      final auth = await _signedIn(stores);
      await pumpSettings(tester, auth: auth);
      await tester.scrollUntilVisible(
        find.text('注销账号'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('注销账号'));
      await tester.pumpAndSettle();

      expect(find.textContaining('不可恢复'), findsWidgets);
      await tester.tap(find.text('继续注销'));
      await tester.pumpAndSettle();

      expect(find.textContaining('DEACTIVATE'), findsWidgets);
      // Cancelling the confirmation word must leave the session alone.
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(auth.isLoggedIn, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('custom AI endpoint', () {
    testWidgets('is hidden when the product only allows the official relay', (
      tester,
    ) async {
      await pumpSettings(tester, showAi: true);
      // The whole AI section is absent: an entry that does nothing is worse
      // than no entry. Scroll to the bottom so an off-screen match counts.
      await tester.scrollUntilVisible(
        find.text('数据与存储'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('AI 助手'), findsNothing);
      expect(find.text('个人 AI 接口'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is offered when the product opts in', (tester) async {
      StudioProfile.current = const StudioProfile(
        id: 'desktop',
        appTitle: 'Desktop',
        templates: [],
        allowCustomAiEndpoint: true,
      );
      await pumpSettings(tester, showAi: true);
      await tester.scrollUntilVisible(
        find.text('个人 AI 接口'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('个人 AI 接口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

bool _tileEnabled(WidgetTester tester, String label) {
  final tile = tester.widget<ListTile>(
    find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
  );
  return tile.enabled;
}

Future<AuthStore> _signedIn(_Stores stores) async {
  await stores.auth.signIn(
    'token-1',
    const CommunityUser(
      id: '7',
      username: 'demo',
      nickname: 'Demo',
      bio: '',
      avatarColor: '#2196F3',
      points: 0,
      checkinStreak: 0,
      provider: 'huawei',
    ),
  );
  return stores.auth;
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
  _TemporaryPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}
