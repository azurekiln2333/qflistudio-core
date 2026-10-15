import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/tutorial_service.dart';
import 'package:qfli_studio_core/store/project_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'c',
      appTitle: StudioProductCatalog.forge,
      templates: [],
      isOffline: true,
    );
    TutorialService.clearCache();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
  });

  test('离线档位不默认加入联网能力', () {
    expect(StudioProfile.current!.isOffline, isTrue);
  });

  testWidgets('教程页和示例代码页读取本地 C JSON', (tester) async {
    const repository = _FixtureContentRepository();
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'CN'),
        supportedLocales: StudioLocalizations.supportedLocales,
        localizationsDelegates: [
          StudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: LocalTutorialsTab(language: 'c', repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final l10n = StudioLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.tutorial), findsOneWidget);
    expect(find.text('C 001: 数据建模与不变量'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'CN'),
        supportedLocales: StudioLocalizations.supportedLocales,
        localizationsDelegates: [
          StudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ExampleCodeTab(language: 'c', repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(l10n.examples), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
    expect(find.text('#include <stdio.h>'), findsNothing);
    expect(find.text('C 示例 001: 数据建模与不变量'), findsOneWidget);
    await tester.tap(find.text('C 示例 001: 数据建模与不变量'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
  });

  group('FunctionsTab inline tools tab', () {
    Widget host({
      required StudioProfile profile,
      VoidCallback? onOpenContentTool,
      VoidCallback? onOpenTerminal,
    }) {
      StudioProfile.current = profile;
      return MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: StudioLocalizations.supportedLocales,
        localizationsDelegates: const [
          StudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FunctionsTab(
          store: ProjectStore(),
          onOpenTerminal: onOpenTerminal ?? () {},
          onOpenContentTool: onOpenContentTool,
        ),
      );
    }

    testWidgets('档位提供 toolsTabBuilder 时直接渲染产品工具，不再有「功能」入口', (tester) async {
      final profile = StudioProfile(
        id: 'java',
        appTitle: StudioProductCatalog.jvmx,
        templates: [],
        isOffline: true,
        toolsTabBuilder: (store, onOpenTerminal) => ListView(
          children: [
            const Card(child: Text('INLINE_TOOL_CARD')),
            TextButton(
              onPressed: onOpenTerminal,
              child: const Text('INLINE_TERMINAL_CARD'),
            ),
          ],
        ),
      );
      var terminalTaps = 0;
      await tester.pumpWidget(
        host(
          profile: profile,
          onOpenContentTool: () {},
          onOpenTerminal: () => terminalTaps++,
        ),
      );
      await tester.pump();

      expect(find.text('INLINE_TOOL_CARD'), findsOneWidget);
      expect(find.text('INLINE_TERMINAL_CARD'), findsOneWidget);
      final l10n = StudioLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );
      expect(find.text(l10n.functions), findsNothing);
      expect(find.byIcon(Icons.terminal), findsNothing);

      await tester.tap(find.text('INLINE_TERMINAL_CARD'));
      await tester.pump();
      expect(terminalTaps, 1);
    });

    testWidgets('档位没有 toolsTabBuilder 时保留终端卡片与「功能」入口', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          profile: const StudioProfile(
            id: 'c',
            appTitle: StudioProductCatalog.forge,
            templates: [],
            isOffline: true,
          ),
          onOpenContentTool: () => opened++,
        ),
      );
      await tester.pump();

      final l10n = StudioLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );
      expect(find.byIcon(Icons.terminal), findsOneWidget);
      expect(find.text(l10n.functions), findsWidgets);

      await tester.tap(find.text(l10n.functions).first);
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('旧调用可省略 store，终端和功能入口仍可点击', (tester) async {
      var terminalTaps = 0;
      var contentTaps = 0;
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
          home: FunctionsTab(
            onOpenTerminal: () => terminalTaps++,
            onOpenContentTool: () => contentTaps++,
          ),
        ),
      );
      await tester.pump();

      final l10n = StudioLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );
      expect(find.byIcon(Icons.terminal), findsOneWidget);
      expect(find.text(l10n.functions), findsWidgets);

      await tester.tap(find.byIcon(Icons.terminal));
      await tester.pump();
      expect(terminalTaps, 1);

      await tester.tap(find.text(l10n.functions).first);
      await tester.pump();
      expect(contentTaps, 1);
    });

    testWidgets('没有 onOpenContentTool 时不渲染「功能」入口，终端卡片仍在', (tester) async {
      await tester.pumpWidget(
        host(
          profile: const StudioProfile(
            id: 'c',
            appTitle: StudioProductCatalog.forge,
            templates: [],
            isOffline: true,
          ),
        ),
      );
      await tester.pump();

      final l10n = StudioLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );
      expect(find.text(l10n.functions), findsNothing);
      expect(find.byIcon(Icons.terminal), findsOneWidget);
    });

    testWidgets('widget 上的 toolsTabBuilder 优先于档位上的', (tester) async {
      StudioProfile.current = StudioProfile(
        id: 'c',
        appTitle: StudioProductCatalog.forge,
        templates: [],
        isOffline: true,
        toolsTabBuilder: (store, onOpenTerminal) =>
            const Center(child: Text('PROFILE_BUILDER_CARD')),
      );
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
          home: FunctionsTab(
            store: ProjectStore(),
            onOpenTerminal: () {},
            onOpenContentTool: () {},
            toolsTabBuilder: (store, onOpenTerminal) =>
                const Center(child: Text('WIDGET_BUILDER_CARD')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('WIDGET_BUILDER_CARD'), findsOneWidget);
      expect(find.text('PROFILE_BUILDER_CARD'), findsNothing);
      final l10n = StudioLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );
      expect(find.text(l10n.functions), findsNothing);
    });
  });
}

class _FixtureContentRepository implements ContentRepository {
  const _FixtureContentRepository();

  static const _tutorial = TutorialContent(
    id: 'c-tutorial-001',
    language: 'c',
    type: 'c',
    locale: 'zh-CN',
    level: 'beginner',
    title: 'C 001: 数据建模与不变量',
    summary: 'A C tutorial',
    concepts: ['arrays'],
    source: 'fixture',
    license: 'fixture',
    updatedAt: '2026-09-22',
    lessons: [
      TutorialLessonContent(
        id: 'c-tutorial-001-lesson',
        title: '实现：数据建模与不变量',
        summary: 'Run a C example',
        concepts: ['output'],
        explain: 'Explain the example',
        code: '#include <stdio.h>',
        output: 'ok',
        exercises: [],
      ),
    ],
  );

  static const _example = ExampleContent(
    id: 'c-example-001',
    language: 'c',
    type: 'c',
    locale: 'zh-CN',
    level: 'beginner',
    title: 'C 示例 001: 数据建模与不变量',
    summary: 'A C example',
    concepts: ['output'],
    source: 'fixture',
    license: 'fixture',
    updatedAt: '2026-09-22',
    code: '#include <stdio.h>',
    expectedOutput: 'ok',
    inputFixtures: {},
    templateType: 'c',
  );

  static const _catalog = ContentCatalog(
    schemaVersion: 1,
    tutorials: [_tutorial],
    examples: [_example],
  );

  @override
  Future<ContentCatalog> load() async => _catalog;

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async => [
    for (final entry in _catalog.tutorials)
      if (filter.matches(entry)) entry,
  ];

  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async => [
    for (final entry in _catalog.examples)
      if (filter.matches(entry)) entry,
  ];
}
