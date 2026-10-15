import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/content_tools_pages.dart';
import 'package:qfli_studio_core/pages/offline_tool_pages.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart';
import 'package:qfli_studio_core/pages/tools_grid.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart';

const _sharedPages = <(String, Type)>[
  ('字符/Unicode', UnicodeToolPage),
  ('Base64', Base64ToolPage),
  ('URL 编解码', UrlToolPage),
  ('正则测试', RegexToolPage),
  ('JSON 格式化', JsonToolPage),
  ('哈希摘要', HashToolPage),
  ('时间戳', TimestampToolPage),
  ('UUID 生成', UuidToolPage),
  ('颜色转换', ColorToolPage),
];

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

Future<void> _mount(
  WidgetTester tester, {
  Size size = const Size(420, 900),
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  Widget? home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF0B63CE),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: home ?? FunctionsTab(onOpenTerminal: () {}),
    ),
  );
  await _settle(tester);
}

Finder _card(String title) => find.byWidgetPredicate(
  (widget) => widget is ToolCard && widget.title == title,
  description: 'tool card $title',
);

Future<void> _revealCard(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    _card(title),
    220,
    scrollable: find
        .descendant(
          of: find.byType(ToolsGrid),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  // scrollUntilVisible ends with jumpTo; lay out the final sliver position.
  await tester.pump();
}

Future<void> _open(WidgetTester tester, String title) async {
  await _revealCard(tester, title);
  expect(_card(title).hitTestable(), findsOneWidget);
  await tester.tap(_card(title));
  await _settle(tester);
}

void main() {
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
  });

  testWidgets(
    'a product without custom tools opens all nine shared tools directly',
    (tester) async {
      var terminalTaps = 0;
      await _mount(
        tester,
        home: FunctionsTab(onOpenTerminal: () => terminalTaps++),
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('功能'), findsNothing);
      expect(
        commonTools.map((tool) => tool.title),
        _sharedPages.map((page) => page.$1),
      );

      await tester.tap(_card('终端'));
      await tester.pump();
      expect(terminalTaps, 1);

      for (final (title, pageType) in _sharedPages) {
        await _open(tester, title);
        expect(find.byType(pageType), findsOneWidget, reason: title);
        expect(tester.takeException(), isNull, reason: title);
        await tester.binding.handlePopRoute();
        await _settle(tester);
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('large text keeps all cards reachable in $brightness', (
      tester,
    ) async {
      var terminalTaps = 0;
      await _mount(
        tester,
        size: const Size(320, 640),
        brightness: brightness,
        textScaler: const TextScaler.linear(2),
        home: FunctionsTab(onOpenTerminal: () => terminalTaps++),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_card('终端')).height, greaterThan(132));
      await tester.tap(_card('终端'));
      expect(terminalTaps, 1);
      for (final (title, _) in _sharedPages) {
        await _revealCard(tester, title);
        expect(_card(title).hitTestable(), findsOneWidget, reason: title);
        expect(tester.takeException(), isNull, reason: title);
      }
    });
  }

  const products = [
    (
      StudioProductCatalog.forge,
      StudioProductCatalog.forgeKey,
      '功能',
      Icons.build_outlined,
      '功能',
    ),
    (
      StudioProductCatalog.dartWing,
      StudioProductCatalog.dartWingKey,
      '功能',
      Icons.build_outlined,
      '功能',
    ),
    (
      StudioProductCatalog.pyFlow,
      StudioProductCatalog.pyFlowKey,
      '功能',
      Icons.build_outlined,
      '功能',
    ),
    (
      StudioProductCatalog.webForge,
      StudioProductCatalog.webForgeKey,
      'Web 工具',
      Icons.language,
      '本地服务、HTTP 请求与编解码',
    ),
    (
      StudioProductCatalog.note,
      StudioProductCatalog.noteKey,
      'Markdown 编辑与预览',
      Icons.article_outlined,
      '预览',
    ),
  ];
  for (final (appTitle, id, title, icon, description) in products) {
    testWidgets('$appTitle retains its product entry beside shared tools', (
      tester,
    ) async {
      StudioProfile.current = StudioProfile(
        id: id,
        productKey: id,
        appTitle: appTitle,
        templates: const [],
        isOffline: true,
      );
      var opened = 0;
      await _mount(
        tester,
        home: FunctionsTab(
          onOpenTerminal: () {},
          onOpenContentTool: () => opened++,
        ),
      );
      await _revealCard(tester, title);
      final card = tester.widget<ToolCard>(_card(title));
      expect(card.icon, icon);
      expect(card.description, description);
      await tester.tap(_card(title));
      await tester.pump();
      expect(opened, 1);
      await _open(tester, 'Base64');
      expect(find.byType(Base64ToolPage), findsOneWidget);
    });
  }

  for (final size in const [Size(360, 640), Size(1200, 800)]) {
    for (final brightness in Brightness.values) {
      testWidgets('cards remain reachable at $size in $brightness', (
        tester,
      ) async {
        await _mount(tester, size: size, brightness: brightness);
        final context = tester.element(find.byType(ToolsGrid));
        expect(Theme.of(context).brightness, brightness);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        final terminal = tester.getRect(_card('终端'));
        expect(terminal.height, 132);
        await _revealCard(tester, '字符/Unicode');
        final first = tester.getRect(_card('字符/Unicode'));
        final second = tester.getRect(_card('Base64'));
        expect(first.size, terminal.size);
        expect(second.size, terminal.size);
        expect(_card('字符/Unicode').hitTestable(), findsOneWidget);
        if (size.width < 600) {
          expect(second.left, closeTo(first.left, 0.5));
          expect(second.top, greaterThan(first.top));
        } else {
          expect(second.top, closeTo(first.top, 0.5));
          expect(second.left, greaterThan(first.left));
        }
        await _revealCard(tester, 'Base64');
        expect(_card('Base64').hitTestable(), findsOneWidget);
        for (final (title, _) in _sharedPages.skip(2)) {
          await _revealCard(tester, title);
          final rect = tester.getRect(_card(title));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(_card(title).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$title at $size');
        }
      });
    }
  }

  testWidgets('product sections compose between terminal and shared cards', (
    tester,
  ) async {
    var customTaps = 0;
    await _mount(
      tester,
      size: const Size(1100, 2400),
      home: Scaffold(
        body: ToolsGrid(
          onOpenTerminal: () {},
          sections: [
            ToolSection(
              title: '产品工具',
              icon: Icons.code,
              tools: [
                ToolDefinition(
                  icon: Icons.code,
                  title: '专用转换',
                  description: '产品自己的能力',
                  onTap: () => customTaps++,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.byType(ToolCard), findsNWidgets(11));
    expect(
      tester.getTopLeft(_card('终端')).dy,
      lessThan(tester.getTopLeft(_card('专用转换')).dy),
    );
    expect(
      tester.getTopLeft(_card('专用转换')).dy,
      lessThan(tester.getTopLeft(_card('字符/Unicode')).dy),
    );
    await tester.tap(_card('专用转换'));
    await tester.pump();
    expect(customTaps, 1);
  });

  testWidgets(
    'the standalone grid includes shared tools without a terminal callback',
    (tester) async {
      await _mount(
        tester,
        size: const Size(1100, 2400),
        home: const Scaffold(body: ToolsGrid()),
      );
      expect(find.byType(ToolCard), findsNWidgets(9));
      expect(find.byIcon(Icons.terminal), findsNothing);
      expect(find.text('通用'), findsOneWidget);
      await _open(tester, 'Base64');
      expect(find.byType(Base64ToolPage), findsOneWidget);
    },
  );

  testWidgets('Base64 encodes, decodes and reports invalid input', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester, 'Base64');
    await tester.enterText(find.byType(TextField).first, '中 文');
    await tester.tap(find.text('编码'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '5LitIOaWhw==',
    );
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('解码'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '中 文',
    );
    await tester.enterText(find.byType(TextField).at(1), '%%%');
    await tester.tap(find.text('解码'));
    await tester.pump();
    expect(find.textContaining('解码失败'), findsOneWidget);
  });

  testWidgets(
    'Unicode handles supplementary code points and validates character count',
    (tester) async {
      await _mount(tester);
      await _open(tester, '字符/Unicode');
      await tester.enterText(find.byType(TextField), '😀');
      await tester.pump();
      expect(find.text('U+1F600'), findsOneWidget);
      expect(find.text(r'\uD83D\uDE00'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(find.text('请输入恰好一个字符（当前 2 个）'), findsOneWidget);
    },
  );

  testWidgets('URL codec preserves form spaces and plus signs', (tester) async {
    await _mount(tester);
    await _open(tester, 'URL 编解码');
    await tester.enterText(find.byType(TextField), 'a+b c');
    await tester.pump();
    expect(find.text('a%2Bb+c'), findsOneWidget);
    expect(find.text('a b c'), findsOneWidget);
  });

  testWidgets('hash results update and offer per-result copying', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester, '哈希摘要');
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text('5d41402abc4b2a76b9719d911017c592'), findsOneWidget);
    expect(find.byTooltip('复制MD5'), findsOneWidget);
    expect(find.byTooltip('复制SHA-1'), findsOneWidget);
    expect(find.byTooltip('复制SHA-256'), findsOneWidget);
  });

  testWidgets(
    'regex tester updates captured groups and reports invalid patterns',
    (tester) async {
      await _mount(tester);
      await _open(tester, '正则测试');
      expect(find.text('匹配 2 处'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, r'(?<word>[a-z]+)');
      await tester.pump();
      expect(find.textContaining('命名组：word=a'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '[');
      await tester.pump();
      expect(find.text('错误'), findsOneWidget);
    },
  );

  testWidgets('timestamp unit selector updates the conversion result', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester, '时间戳');
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.enterText(find.byType(TextField).at(1), '2024-01-02 03:04:05');
    await tester.pump();
    final epoch = DateTime(2024, 1, 2, 3, 4, 5).millisecondsSinceEpoch;
    expect(find.text('${epoch ~/ 1000}'), findsOneWidget);
    await tester.tap(find.text('毫秒'));
    await tester.pump();
    expect(find.text('$epoch'), findsOneWidget);
  });

  testWidgets('color conversion validates input and updates RGB output', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester, '颜色转换');
    await tester.enterText(find.byType(TextField), '#ff0000');
    await tester.pump();
    expect(find.text('rgb(255, 0, 0)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.pump();
    expect(find.byType(ToolError), findsOneWidget);
    expect(find.text('预览'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UUID page generates fresh v4 and deterministic name results', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester, 'UUID 生成');
    String randomValue() => tester
        .widget<ResultRow>(
          find.byWidgetPredicate(
            (widget) => widget is ResultRow && widget.label == 'UUID',
          ),
        )
        .value;
    final before = randomValue();
    expect(
      before,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    await tester.tap(find.text('重新生成'));
    await tester.pump();
    expect(randomValue(), isNot(before));
    expect(find.text('2ed6657d-e927-568b-95e1-2665a8aea6a2'), findsOneWidget);
  });

  testWidgets(
    'JSON card opens the existing formatter and copies formatted JSON',
    (tester) async {
      Object? clipboardArguments;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardArguments = call.arguments;
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
      await _mount(tester);
      await _open(tester, 'JSON 格式化');
      expect(find.byType(JsonToolPage), findsOneWidget);
      await tester.enterText(find.byType(TextField), '{"a":1}');
      await tester.tap(find.text('格式化 JSON'));
      await tester.pump();
      const formatted = '{\n  "a": 1\n}';
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        formatted,
      );
      await tester.tap(find.text('复制 JSON'));
      await tester.pump();
      expect(clipboardArguments, {'text': formatted});
      expect(find.text('已复制'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
