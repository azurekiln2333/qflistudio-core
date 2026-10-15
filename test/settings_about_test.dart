import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/about_page.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  StudioProfile? originalProfile;

  setUp(() {
    originalProfile = StudioProfile.current;
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  for (final (language, profile) in const [
    (
      'Python',
      StudioProfile(
        id: 'python',
        appTitle: StudioProductCatalog.pyFlow,
        templates: [],
        isOffline: true,
      ),
    ),
    (
      'Java',
      StudioProfile(
        id: 'java',
        appTitle: StudioProductCatalog.jvmx,
        templates: [],
        offlineOnly: true,
      ),
    ),
  ]) {
    testWidgets('About identifies offline ${profile.appTitle}', (tester) async {
      StudioProfile.current = profile;

      await _openAbout(tester);

      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.text(profile.appTitle), findsOneWidget);
      expect(find.text('版本 $kQfliAboutVersion'), findsOneWidget);
      expect(find.textContaining('$language 开发工具'), findsOneWidget);
      expect(find.textContaining('管理本地项目'), findsOneWidget);
      expect(find.textContaining('教程与示例'), findsOneWidget);
      expect(find.textContaining('内置终端'), findsOneWidget);
      expect(find.textContaining('编译和运行'), findsNothing);
      expect(find.textContaining('开发者社区'), findsNothing);
      expect(find.textContaining('云端'), findsNothing);
      expect(find.text(StudioProductCatalog.qfliStudio), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Java advertises JDK execution only for an available runtime', (
    tester,
  ) async {
    StudioProfile.current = const StudioProfile(
      id: 'custom-java',
      appTitle: StudioProductCatalog.jvmx,
      productKey: StudioProductCatalog.jvmxKey,
      templates: [],
      isOffline: true,
      runtimeStatus: 'available',
    );

    await _openAbout(tester);

    expect(find.textContaining('Java 开发工具'), findsOneWidget);
    expect(find.textContaining('JDK（javac / java）'), findsOneWidget);
    expect(find.textContaining('在本地编译和运行程序'), findsOneWidget);
    expect(find.textContaining('available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (key, subject) in const [
    (StudioProductCatalog.webForgeKey, 'Web 项目编辑工具'),
    (StudioProductCatalog.sqlabKey, 'SQL 学习与编辑工具'),
    (StudioProductCatalog.jsonKey, 'JSON 数据编辑工具'),
    (StudioProductCatalog.noteKey, 'Markdown 写作工具'),
  ]) {
    testWidgets('About describes $key without claiming compiled execution', (
      tester,
    ) async {
      StudioProfile.current = StudioProfile(
        id: 'custom',
        appTitle: StudioProductCatalog.products[key]!,
        productKey: key,
        templates: const [],
        offlineOnly: true,
        runtimeStatus: 'available',
      );

      await _openAbout(tester);

      expect(find.textContaining(subject), findsOneWidget);
      expect(find.textContaining('编译和运行'), findsNothing);
      expect(find.textContaining('开发者社区'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unregistered offline products use their actual templates', (
    tester,
  ) async {
    StudioProfile.current = const StudioProfile(
      id: 'custom',
      appTitle: 'Custom Studio',
      templates: [ProjectTemplate.empty, ProjectTemplate.kotlin],
      offlineOnly: true,
    );

    await _openAbout(tester);

    expect(find.textContaining('Kotlin 开发工具'), findsOneWidget);
    expect(find.textContaining('空项目'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('About and licenses show the rounded host app icon', (
    tester,
  ) async {
    StudioProfile.current = null;
    final assets = _HostIconBundle();

    await _openAbout(tester, bundle: assets);

    expect(_iconProvider(tester).assetName, 'assets/app_icon.png');
    expect(_iconProvider(tester).package, isNull);
    expect(assets.loadedAssets, contains('assets/app_icon.png'));
    final clipping = tester.widget<ClipRRect>(
      find.ancestor(of: find.byType(Image), matching: find.byType(ClipRRect)),
    );
    expect(clipping.borderRadius, BorderRadius.circular(20));
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byIcon(Icons.code_rounded), findsNothing);
    expect(find.byIcon(Icons.apps_rounded), findsNothing);

    await tester.ensureVisible(find.text('开源许可'));
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(_iconProvider(tester).assetName, 'assets/app_icon.png');
    expect(find.byIcon(Icons.code_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About opens the standard open-source licenses page', (
    tester,
  ) async {
    StudioProfile.current = null;

    await _openAbout(tester);
    expect(find.text('开源许可'), findsOneWidget);

    await tester.ensureVisible(find.text('开源许可'));
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'QQ group is selectable and copies exact digits from both actions',
    (tester) async {
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _openAbout(tester);
      expect(find.text('反馈与交流'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, '694120628'), findsOneWidget);
      await tester.ensureVisible(find.text('复制群号'));
      await tester.tap(find.text('复制群号'));
      await tester.pump();

      expect(copied, [
        <String, Object>{'text': '694120628'},
      ]);
      expect(find.text('群号已复制，可粘贴到 QQ 搜索'), findsOneWidget);

      await tester.tap(find.text('QQ 交流群'));
      await tester.pump();
      expect(copied, [
        <String, Object>{'text': '694120628'},
        <String, Object>{'text': '694120628'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clipboard failure offers manual copy without reporting success',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard_unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _openAbout(tester);
      await tester.ensureVisible(find.text('复制群号'));
      await tester.tap(find.text('复制群号'));
      await tester.pump();

      expect(find.text('复制失败，请长按群号手动复制'), findsOneWidget);
      expect(find.text('群号已复制，可粘贴到 QQ 搜索'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving About while copying does not use a disposed context', (
    tester,
  ) async {
    final completion = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') await completion.future;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _openAbout(tester);
    await tester.ensureVisible(find.text('复制群号'));
    await tester.tap(find.text('复制群号'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    completion.complete();
    await tester.pump();

    expect(find.byType(AboutPage), findsNothing);
    expect(find.text('群号已复制，可粘贴到 QQ 搜索'), findsNothing);
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
      _withHostIcon(
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
    await tester.scrollUntilVisible(
      find.text('复制群号'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('694120628'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('开源许可'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('开源许可'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAbout(WidgetTester tester, {AssetBundle? bundle}) async {
  await tester.pumpWidget(
    _withHostIcon(
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
      bundle: bundle,
    ),
  );
  await tester.tap(find.text('About'));
  await tester.pumpAndSettle();
}

Widget _withHostIcon(Widget child, {AssetBundle? bundle}) =>
    DefaultAssetBundle(bundle: bundle ?? _HostIconBundle(), child: child);

AssetImage _iconProvider(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image).first).image;
  return (image is ResizeImage ? image.imageProvider : image) as AssetImage;
}

/// Core widget tests supply the host asset without bundling any product logo.
class _HostIconBundle extends CachingAssetBundle {
  final loadedAssets = <String>{};
  static final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<ByteData> load(String key) async {
    loadedAssets.add(key);
    if (key == 'assets/app_icon.png') return ByteData.sublistView(_pixel);
    return rootBundle.load(key);
  }
}
