// R1 鸿蒙本地运行工具下载指引的回归用例。
//
// 这些用例只在云 CI 上运行，本地不执行。它们覆盖下载入口与链接两层：
// 目录数据完整、九个独立链接、当前语言排在最前、注入打开方式收到准确 URI、
// 打开失败给出复制与重试、320 宽加 2 倍字号不溢出。
//
// 系统安装与 AppGallery 跳转需要真机，这里不做，也不探测安装状态。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/interop/ohos_runtime_catalog.dart';
import 'package:qfli_studio_core/interop/ohos_runtime_guide.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

/// 目录里全部九项的顺序，与用户理解一致。
const List<String> _expectedIds = <String>[
  'java',
  'cpp',
  'go',
  'dart',
  'python',
  'sql',
  'web',
  'rust',
  'studio',
];

const _expectedBundles = <String>[
  'com.azurekiln.qfli.java',
  'com.azurekiln.qfli.cpp',
  'com.azurekiln.qfli.go',
  'com.azurekiln.qfli.dart',
  'com.azurekiln.qfli.pyflow',
  'com.azurekiln.qfli.sql',
  'com.azurekiln.qfli.web',
  'com.azurekiln.qfli.rust',
  'com.azurekiln.qflistudio',
];

/// AppGallery 链接的固定前缀。
const String _storePrefix =
    'https://appgallery.huawei.com/app/detail?id=';

/// 卡片按钮的三种界面文案，随本地化变化。
const List<String> _downloadLabels = <String>['下载', '下載', 'Download'];

void main() {
  group('目录数据', () {
    test('九个条目按用户顺序排列，标识唯一', () {
      expect(ohosRuntimeApps, hasLength(9));
      expect([for (final app in ohosRuntimeApps) app.id], _expectedIds);
      expect(
        {for (final app in ohosRuntimeApps) app.id},
        hasLength(9),
        reason: '每项 id 唯一，同时是图标文件名',
      );
    });

    test('九个 bundle 名与图标互不相同', () {
      expect(
        {for (final app in ohosRuntimeApps) app.bundleName},
        hasLength(9),
        reason: 'bundle 名重复会让两个工具指向同一个安装页',
      );
      expect(
        {for (final app in ohosRuntimeApps) app.iconAsset},
        hasLength(9),
        reason: '图标路径重复会让两张卡片显示同一个图标',
      );
    });

    test('每个图标路径落在 product_icons 目录且跟随 id', () {
      for (final app in ohosRuntimeApps) {
        expect(app.iconAsset, 'assets/product_icons/${app.id}.png');
      }
    });

    test('每个打开链接指向自己的 bundle 名', () {
      expect(ohosRuntimeApps.map((app) => app.bundleName), _expectedBundles);
      for (final app in ohosRuntimeApps) {
        final uri = app.storeUri;
        expect(uri.toString(), startsWith(_storePrefix));
        expect(
          uri.queryParameters['id'],
          app.bundleName,
          reason: '链接的 id 参数必须等于该工具的 bundle 名',
        );
        expect(uri.queryParameters['channelId'], 'SHARE');
        expect(uri.queryParameters['source'], 'appshare');
      }
      expect(
        {for (final app in ohosRuntimeApps) app.storeUri.toString()},
        hasLength(9),
        reason: '九个链接必须互不相同',
      );
    });

    test('产品名取自产品目录常量', () {
      expect(ohosRuntimeApps[0].name, StudioProductCatalog.jvmx);
      expect(ohosRuntimeApps[1].name, StudioProductCatalog.forge);
      expect(ohosRuntimeApps[2].name, StudioProductCatalog.goShift);
      expect(ohosRuntimeApps[3].name, StudioProductCatalog.dartWing);
      expect(ohosRuntimeApps[4].name, StudioProductCatalog.pyFlow);
      expect(ohosRuntimeApps[5].name, StudioProductCatalog.sqlab);
      expect(ohosRuntimeApps[6].name, StudioProductCatalog.webForge);
      expect(ohosRuntimeApps[7].name, StudioProductCatalog.rustCore);
      expect(ohosRuntimeApps[8].name, StudioProductCatalog.qfliStudio);
    });

    test('Studio 是多语言编辑器，不与任何语言相关', () {
      final studio = ohosRuntimeApps[8];
      expect(studio.id, 'studio');
      expect(studio.languages, isEmpty);
      expect(studio.supports('python'), isFalse);
      expect(studio.languageLabel, '多语言编辑器');
    });

    test('supports 忽略大小写与两端空白，并覆盖 C 与 C++', () {
      final cpp = ohosRuntimeApps[1];
      expect(cpp.supports('c'), isTrue);
      expect(cpp.supports('C++'), isTrue);
      expect(cpp.supports('  CPP  '), isTrue);
      expect(cpp.supports('java'), isFalse);

      final web = ohosRuntimeApps[6];
      expect(web.supports('TypeScript'), isTrue);
      expect(web.supports('html'), isTrue);

      final java = ohosRuntimeApps[0];
      expect(java.supports('Java'), isTrue);
      expect(java.supports(null), isFalse);
      expect(java.supports(''), isFalse);
      expect(java.supports('   '), isFalse);
    });
  });

  group('页面', () {
    testWidgets('当前语言排在最前并说明本项目使用它', (tester) async {
      await _pumpGuide(tester, language: 'python');

      expect(find.text('本地运行工具'), findsOneWidget);
      expect(
        find.textContaining(StudioProductCatalog.pyFlow),
        findsWidgets,
      );
      // 提示语点名首选工具，同时不隐藏其它工具。
      expect(find.textContaining('这个项目使用'), findsOneWidget);

      final order = await _appNamesByRow(tester);
      expect(
        order.first,
        StudioProductCatalog.pyFlow,
        reason: 'Python 项目应把 PyFlow 排到最前',
      );
    });

    testWidgets('不认识的语言回落到目录顺序，且不出现推荐说明', (tester) async {
      await _pumpGuide(tester, language: 'kotlin');

      expect(find.textContaining('这个项目使用'), findsNothing);
      final order = await _appNamesByRow(tester);
      expect(
        order.first,
        StudioProductCatalog.jvmx,
        reason: '无匹配语言时按目录顺序，Java 排在最前',
      );
    });

    testWidgets('没有语言时按目录原顺序显示', (tester) async {
      await _pumpGuide(tester);

      expect(find.textContaining('这个项目使用'), findsNothing);
      final order = await _appNamesByRow(tester);
      expect(order.first, StudioProductCatalog.jvmx);
    });

    testWidgets('点击下载把该工具的确切链接交给注入的打开方式', (tester) async {
      final opened = <Uri>[];
      await _pumpGuide(tester, opened: opened);

      final python = ohosRuntimeApps[4];
      await _bringIntoView(tester, python.name);
      await _tapDownloadFor(tester, python.name);

      expect(opened, hasLength(1));
      expect(opened.single, python.storeUri);
      expect(
        opened.single.toString(),
        'https://appgallery.huawei.com/app/detail'
        '?id=com.azurekiln.qfli.pyflow&channelId=SHARE&source=appshare',
      );
    });

    testWidgets('九张卡片都能滚到并带自己的包内图标', (tester) async {
      await _pumpGuide(tester);

      for (final app in ohosRuntimeApps) {
        final bytes = await rootBundle.load('packages/qfli_studio_core/${app.iconAsset}');
        expect(bytes.lengthInBytes, greaterThan(0));
        await _bringIntoView(tester, app.name);
        final image = tester.widget<Image>(
          find.descendant(
            of: find.ancestor(
              of: find.text(app.name),
              matching: find.byType(Card),
            ),
            matching: find.byType(Image),
          ),
        );
        final provider = image.image as AssetImage;
        expect(provider.assetName, app.iconAsset);
        expect(
          provider.package,
          'qfli_studio_core',
          reason: '资源必须带包名，否则宿主 App 找不到',
        );
      }
    });

    testWidgets('打开失败时给出复制链接与重试，并显示可复制的地址', (tester) async {
      await _pumpGuide(
        tester,
        openStore: (uri) async => throw StateError('模拟平台拒绝打开'),
      );

      final java = ohosRuntimeApps[0];
      await _bringIntoView(tester, java.name);
      await _tapDownloadFor(tester, java.name);
      await tester.pumpAndSettle();

      expect(find.text('无法打开 AppGallery'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 失败地址要能被选中复制，而不是只给一句套话。
      final shown = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(shown.data, java.storeUri.toString());
    });

    testWidgets('复制链接把失败地址写入剪贴板并提示已复制', (tester) async {
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            clipboard.add('${args['text']}');
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

      await _pumpGuide(
        tester,
        openStore: (uri) async => throw StateError('模拟平台拒绝打开'),
      );

      final java = ohosRuntimeApps[0];
      await _bringIntoView(tester, java.name);
      await _tapDownloadFor(tester, java.name);
      await tester.pumpAndSettle();

      await tester.tap(find.text('复制链接'));
      await tester.pumpAndSettle();

      expect(clipboard, [java.storeUri.toString()]);
      expect(find.text('已复制链接'), findsOneWidget);
      // 复制后对话框关闭，用户回到列表。
      expect(find.text('无法打开 AppGallery'), findsNothing);
    });

    testWidgets('重试重新走同一次下载，成功后再无错误对话框', (tester) async {
      final opened = <Uri>[];
      var fail = true;
      await _pumpGuide(
        tester,
        openStore: (uri) async {
          opened.add(uri);
          if (fail) throw StateError('首次失败');
        },
      );

      final java = ohosRuntimeApps[0];
      await _bringIntoView(tester, java.name);
      await _tapDownloadFor(tester, java.name);
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(opened, hasLength(2));
      expect(opened.last, java.storeUri);
      expect(find.text('无法打开 AppGallery'), findsNothing);
    });

    testWidgets('320 宽加 2 倍字号仍能渲染全部九项且不溢出', (tester) async {
      await _pumpGuide(
        tester,
        physicalSize: const Size(320, 800),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      for (final app in ohosRuntimeApps) {
        await _bringIntoView(tester, app.name);
        expect(tester.takeException(), isNull);
      }
      expect(find.text(ohosRuntimeApps.last.name), findsOneWidget);
    });

    testWidgets('窄屏大字号下失败对话框仍可读可操作', (tester) async {
      await _pumpGuide(
        tester,
        physicalSize: const Size(320, 800),
        textScale: 2,
        openStore: (uri) async => throw StateError('模拟平台拒绝打开'),
      );

      final java = ohosRuntimeApps[0];
      await _bringIntoView(tester, java.name);
      await _tapDownloadFor(tester, java.name);
      await tester.pumpAndSettle();

      // 对话框可滚动，标题与两个动作都在。
      expect(tester.takeException(), isNull);
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.scrollable, isTrue, reason: '大字号下内容必须可滚动');
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });
}

/// 按行从上到下取当前渲染出来的工具名。
///
/// 网格是懒加载的，这里只比较已建出的卡片，足以判断谁排在最前。
Future<List<String>> _appNamesByRow(WidgetTester tester) async {
  final entries = <(Offset, String)>[];
  for (final app in ohosRuntimeApps) {
    final finder = find.text(app.name);
    if (finder.evaluate().isEmpty) continue;
    entries.add((tester.getTopLeft(finder.first), app.name));
  }
  entries.sort((a, b) {
    final row = a.$1.dy.compareTo(b.$1.dy);
    return row != 0 ? row : a.$1.dx.compareTo(b.$1.dx);
  });
  return [for (final entry in entries) entry.$2];
}

/// 把某张卡片滚进可见区。
///
/// 网格有缓存范围：finder 能找到不代表它在屏幕内，所以找到之后仍要
/// [WidgetTester.ensureVisible]，否则点击会落空。
Future<void> _bringIntoView(WidgetTester tester, String name) async {
  final target = find.text(name);
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      target,
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

/// 点掉 [name] 那张卡片里的下载按钮。
Future<void> _tapDownloadFor(WidgetTester tester, String name) async {
  final card = find.ancestor(of: find.text(name), matching: find.byType(Card));
  final button = find.descendant(
    of: card,
    matching: find.byWidgetPredicate(
      (widget) => widget is Text && _downloadLabels.contains(widget.data),
    ),
  );
  await tester.ensureVisible(button.first);
  await tester.pumpAndSettle();
  await tester.tap(button.first);
  await tester.pump();
}

/// 挂载指引页。默认注入一个只记录不改环境的打开方式。
Future<void> _pumpGuide(
  WidgetTester tester, {
  String? language,
  List<Uri>? opened,
  Future<void> Function(Uri)? openStore,
  Size physicalSize = const Size(900, 1000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final opener = openStore ?? (Uri uri) async => opened?.add(uri);

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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: OhosRuntimeGuide(language: language, openStore: opener),
    ),
  );
  // 本地化 delegate 是异步加载的，必须等到它落地后再断言文案。
  await tester.pumpAndSettle();
}
