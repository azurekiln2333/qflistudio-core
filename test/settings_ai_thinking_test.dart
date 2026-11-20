@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// 直连设置的「请求思考过程」开关（任务 11-19-agent-thinking-stream 的 R13、D6）。
///
/// 开关只在产品档位允许个人 AI 接口时出现，见 design §4.4。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? previousProfile;
  late Directory root;
  late PathProviderPlatform originalPaths;
  late SettingsStore settings;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_ai_thinking_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    // 先把存储路径解析掉，测试结束时不留悬挂的超时计时器。
    await AppPaths.storageDirectory();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() {
    previousProfile = StudioProfile.current;
    settings = SettingsStore();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    settings.dispose();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 宿主通道在测试里不存在，明确按无隐私托管处理。
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('qflistudio/platform'),
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('qflistudio/platform'),
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: settings)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showThinkingSwitch(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('请求思考过程'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a direct-mode product shows the thinking switch', (
    tester,
  ) async {
    StudioProfile.current = const StudioProfile(
      id: 'desktop',
      appTitle: 'Desktop',
      templates: [],
      allowCustomAiEndpoint: true,
    );
    await pumpSettings(tester);
    await showThinkingSwitch(tester);

    expect(find.text('请求思考过程'), findsOneWidget);
    expect(
      find.text('只对 Responses 与 Messages 协议生效。模型不支持思考时请关闭。'),
      findsOneWidget,
    );
    expect(settings.aiThinking, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the switch flips aiThinking', (tester) async {
    StudioProfile.current = const StudioProfile(
      id: 'desktop',
      appTitle: 'Desktop',
      templates: [],
      allowCustomAiEndpoint: true,
    );
    await pumpSettings(tester);
    await showThinkingSwitch(tester);

    await tester.tap(find.text('请求思考过程'));
    await tester.pumpAndSettle();
    expect(settings.aiThinking, isTrue);

    await tester.tap(find.text('请求思考过程'));
    await tester.pumpAndSettle();
    expect(settings.aiThinking, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a product without a direct mode hides the switch', (
    tester,
  ) async {
    StudioProfile.current = const StudioProfile(
      id: 'harmony',
      appTitle: 'Harmony',
      templates: [],
    );
    await pumpSettings(tester);

    expect(find.text('AI 助手'), findsNothing);
    expect(find.text('请求思考过程'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
