import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/tools/ported/batch1.dart';
import 'package:qfli_studio_core/tools/ported/catalog.dart';
import 'package:qfli_studio_core/tools/ported/netrix_tool_page.dart';
import 'package:qfli_studio_core/tools/ported_tool.dart';
import 'package:qfli_studio_core/tools/ported_tools.dart';
import 'package:qfli_studio_core/tools/tool_audience.dart';
import 'package:qfli_studio_core/tools/tool_state_store.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart';
import 'package:qfli_studio_core/widgets/tools_browser.dart';

/// A store that never touches the disk.
ToolStateStore _store() =>
    ToolStateStore(backend: LocalMemoryBackend(), flushDelay: Duration.zero);

/// Mount the tools page for one audience.
Future<ToolStateStore> _mount(
  WidgetTester tester, {
  required bool isMainApp,
  Size size = const Size(1200, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final store = _store();
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
      home: Scaffold(
        body: ToolsBrowser(
          sections: const <ToolsBrowserSection>[],
          state: store,
          isMainApp: isMainApp,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// One already-run ported tool: open it, fill the fields, run it.
Future<void> _runTool(
  WidgetTester tester,
  PortedToolEntry entry, {
  Map<String, String> values = const <String, String>{},
}) async {
  await tester.tap(find.text(entry.tool.title).first);
  await tester.pumpAndSettle();
  expect(find.byType(NetrixToolPage), findsOneWidget);
  for (final MapEntry<String, String> value in values.entries) {
    final field = entry.tool.fields.firstWhere((f) => f.id == value.key);
    await tester.enterText(
      find.widgetWithText(TextFormField, field.label),
      value.value,
    );
    await tester.pump();
  }
  await tester.tap(find.text('运行工具').last);
  await tester.pumpAndSettle();
}

void main() {
  group('ported tool registry', () {
    test('every entry resolves to a netrix definition with a unique id', () {
      expect(allPortedTools, isNotEmpty);
      final ids = <String>[];
      for (final PortedToolEntry entry in allPortedTools) {
        expect(netrixToolIds, contains(entry.tool.id));
        expect(ids, isNot(contains(entry.tool.id)));
        expect(entry.batch, inInclusiveRange(1, 3));
        ids.add(entry.tool.id);
      }
    });

    test('merged ids are netrix ids that no batch registers', () {
      for (final String id in mergedNetrixIds) {
        expect(netrixToolIds, contains(id));
        expect(claimedNetrixIds, isNot(contains(id)));
      }
    });

    test('every netrix id is claimed, merged or still unclaimed', () {
      final pending = <String>[
        for (final String id in netrixToolIds)
          if (!claimedNetrixIds.contains(id) && !mergedNetrixIds.contains(id))
            id,
      ];
      expect(unclaimedNetrixIds, pending);
      expect(<String>{
        ...claimedNetrixIds,
        ...mergedNetrixIds,
        ...pending,
      }, netrixToolIds.toSet());
    });

    test('batch 1 holds the two text tools with no existing counterpart', () {
      expect(<String>[for (final e in portedBatch1) e.tool.id], ['hex', 'jwt']);
      expect(
        <String>[for (final e in portedBatch1) e.tool.title],
        ['Hex 编解码', 'JWT 查看器'],
      );
      for (final PortedToolEntry entry in portedBatch1) {
        expect(entry.audience, ToolAudience.qfliStudioMainApp);
      }
    });
  });

  group('audience', () {
    late StudioProfile? previousProfile;

    setUp(() {
      previousProfile = StudioProfile.current;
      StudioProfile.current = null;
    });

    tearDown(() {
      StudioProfile.current = previousProfile;
    });

    test('the main app counts as the main app, a language app does not', () {
      expect(ToolAudienceScope.isMainApp, isFalse);
      StudioProfile.current = const StudioProfile(
        id: StudioProductCatalog.qfliStudioKey,
        appTitle: StudioProductCatalog.qfliStudio,
        templates: <ProjectTemplate>[],
        isOffline: true,
      );
      expect(ToolAudienceScope.isMainApp, isTrue);
      StudioProfile.current = StudioProfile(
        id: StudioProductCatalog.forgeKey,
        productKey: StudioProductCatalog.forgeKey,
        appTitle: StudioProductCatalog.forge,
        templates: const <ProjectTemplate>[],
        isOffline: true,
      );
      expect(ToolAudienceScope.isMainApp, isFalse);
    });
    testWidgets('the main app shows every ported tool', (tester) async {
      await _mount(tester, isMainApp: true);
      for (final PortedToolEntry entry in portedToolsInScope(isMainApp: true)) {
        expect(
          find.text(entry.tool.title),
          findsOneWidget,
          reason: '${entry.tool.id} is missing from the tools page',
        );
      }
      // 4 个重复项已并入现有工具，不再作为单独条目出现。
      for (final String id in mergedNetrixIds) {
        expect(
          find.text(netrixTool(id).title),
          findsNothing,
          reason: '$id must be merged into its existing tool',
        );
      }
    });

    testWidgets('a language app shows none of them', (tester) async {
      await _mount(tester, isMainApp: false);
      for (final PortedToolEntry entry in allPortedTools) {
        expect(find.text(entry.tool.title), findsNothing);
      }
      expect(find.text('没有匹配的工具'), findsOneWidget);
    });
  });

  group('running ported tools', () {
    for (final PortedToolEntry entry in portedToolsInScope(isMainApp: true)) {
      testWidgets('${entry.tool.id} opens, runs and shows its result', (
        tester,
      ) async {
        await _mount(tester, isMainApp: true);
        final values = switch (entry.tool.id) {
          'hex' => <String, String>{'input': 'abc'},
          'jwt' => <String, String>{
            'token':
                'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.'
                'c2lnbmF0dXJl',
          },
          _ => const <String, String>{},
        };
        await _runTool(tester, entry, values: values);

        switch (entry.tool.id) {
          case 'hex':
            expect(find.text('Hex 编码完成'), findsOneWidget);
            expect(find.text('616263'), findsOneWidget);
          case 'jwt':
            expect(find.text('JWT 已解码'), findsOneWidget);
            expect(find.textContaining('"sub": "1234"'), findsWidgets);
            expect(find.text('仅解码，不代表签名有效。'), findsOneWidget);
          default:
            expect(find.text(entry.tool.title), findsWidgets);
        }
      });
    }

    testWidgets('hex decodes back and reports invalid input', (tester) async {
      final entry = allPortedTools.firstWhere((e) => e.tool.id == 'hex');
      await _mount(tester, isMainApp: true);
      await tester.tap(find.text(entry.tool.title).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('decode').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '616263');
      await tester.tap(find.text('运行工具').last);
      await tester.pumpAndSettle();
      expect(find.text('Hex 解码完成'), findsOneWidget);
      expect(find.text('abc'), findsWidgets);

      await tester.enterText(find.byType(TextFormField).last, 'zz');
      await tester.tap(find.text('运行工具').last);
      await tester.pumpAndSettle();
      expect(find.text('输入无效，请检查后重试。'), findsWidgets);
    });

    testWidgets('a required field blocks the run', (tester) async {
      final entry = allPortedTools.firstWhere((e) => e.tool.id == 'jwt');
      await _mount(tester, isMainApp: true);
      await tester.tap(find.text(entry.tool.title).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('运行工具').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('JWT'), findsWidgets);
      expect(find.text('JWT 已解码'), findsNothing);
    });
  });

  group('tool page state', () {
    testWidgets('opening a ported tool records it as recently used', (
      tester,
    ) async {
      final entry = allPortedTools.firstWhere((e) => e.tool.id == 'hex');
      final store = await _mount(tester, isMainApp: true);
      await tester.tap(find.text(entry.tool.title).first);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(store.recent, contains('hex'));
    });

    testWidgets('the density switch reaches the ported entries', (
      tester,
    ) async {
      final store = await _mount(tester, isMainApp: true);
      expect(store.density, ToolCardDensity.standard);
      await tester.tap(find.text('紧凑'));
      await tester.pumpAndSettle();
      expect(store.density, ToolCardDensity.compact);
      expect(find.byType(ToolRow), findsWidgets);
      await store.settled();
    });
  });
}
