import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/tools/ported/batch1.dart';
import 'package:qfli_studio_core/tools/ported/batch2.dart';
import 'package:qfli_studio_core/tools/ported/batch3.dart';
import 'package:qfli_studio_core/tools/ported/catalog.dart';
import 'package:qfli_studio_core/tools/ported/models.dart';
import 'package:qfli_studio_core/tools/ported/netrix_tool_page.dart';
import 'package:qfli_studio_core/tools/ported_tool.dart';
import 'package:qfli_studio_core/tools/ported_tools.dart';
import 'package:qfli_studio_core/tools/tool_audience.dart';
import 'package:qfli_studio_core/tools/tool_state_store.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart';
import 'package:qfli_studio_core/widgets/tools_browser.dart';

import 'support/netrix_tool_samples.dart';

/// A store that never touches the disk.
ToolStateStore _store() =>
    ToolStateStore(backend: LocalMemoryBackend(), flushDelay: Duration.zero);

/// Mount the tools page for one audience.
Future<ToolStateStore> _mount(
  WidgetTester tester, {
  required bool isMainApp,
  // 52 个工具装在一页，测试用高视口把整页都排出来，避开滚动细节。
  Size size = const Size(1200, 14000),
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

/// Run one tool on its own page.
///
/// Mounting the page directly also avoids the two netrix tools that share a
/// Chinese title (`ip-range` and `ipv4-scope` are both “IPv4 地址范围”).
Future<void> _runTool(
  WidgetTester tester,
  PortedToolEntry entry, {
  Map<String, String> values = const <String, String>{},
  bool run = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
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
      home: NetrixToolPage(
        key: ValueKey<String>(entry.tool.id),
        tool: entry.tool,
        store: store,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(NetrixToolPage), findsOneWidget);
  for (final MapEntry<String, String> value in values.entries) {
    final field = entry.tool.fields.firstWhere((f) => f.id == value.key);
    // 下拉字段用工具自带的初始值，不需要也不能用 `enterText` 填。
    if (field.type == ToolFieldType.select) continue;
    if (value.value.isEmpty) continue;
    await tester.enterText(
      find.widgetWithText(TextFormField, field.label),
      value.value,
    );
    await tester.pump();
  }
  if (!run) return;
  await tester.tap(find.text('运行工具').last);
  await tester.pumpAndSettle();
}

/// The tools page is now long, so every entry has to be scrolled into view.
Future<void> _scrollToTitle(WidgetTester tester, String title) async {
  final target = find.text(title);
  if (target.evaluate().isNotEmpty) return;
  // 页头里还有横向的分类筛选条：只拖动纵向的那一个。
  final vertical = find.descendant(
    of: find.byType(ToolsBrowser),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
      description: 'vertical tools scrollable',
    ),
  );
  await tester.scrollUntilVisible(
    target,
    220,
    maxScrolls: 200,
    scrollable: vertical.first,
  );
  await tester.pump();
  // scrollUntilVisible 只保证已构建，最后一截可能还在视口外。
  await tester.ensureVisible(target.first);
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

    test('nothing is left unclaimed and all 52 tools are accounted for', () {
      expect(unclaimedNetrixIds, isEmpty);
      expect(netrixToolIds, hasLength(52));
      expect(claimedNetrixIds, hasLength(47));
      expect(mergedNetrixIds, hasLength(5));
      expect(claimedNetrixIds.length + mergedNetrixIds.length, 52);
      expect(
        <String>{...claimedNetrixIds, ...mergedNetrixIds},
        netrixToolIds.toSet(),
      );
    });

    test('the three batches are disjoint and add up to the registry', () {
      final batches = <int, List<String>>{
        1: <String>[for (final e in portedBatch1) e.tool.id],
        2: <String>[for (final e in portedBatch2) e.tool.id],
        3: <String>[for (final e in portedBatch3) e.tool.id],
      };
      expect(batches[1], hasLength(2));
      expect(batches[2], hasLength(27));
      expect(batches[3], hasLength(18));
      final seen = <String>{};
      for (final List<String> ids in batches.values) {
        for (final String id in ids) {
          expect(seen.add(id), isTrue, reason: '$id is registered twice');
        }
      }
      expect(seen, claimedNetrixIds);
    });

    test('batch 2 covers the 27 inventoried address and network tools', () {
      expect(<String>[for (final e in portedBatch2) e.tool.id], <String>[
        'subnet-calculator',
        'subnet-splitter',
        'range-to-cidr',
        'cidr-aggregate',
        'ip-converter',
        'wildcard-mask',
        'ip-inspector',
        'ip-membership',
        'ip-range',
        'prefix-mask',
        'mask-prefix',
        'ipv4-classifier',
        'ipv4-scope',
        'reachability',
        'port-check',
        'port-scan',
        'host-scan',
        'hostname-lookup',
        'dns-record',
        'public-ip',
        'local-interfaces',
        'http-request',
        'websocket',
        'mac-normalizer',
        'dns-propagation',
        'rdap',
        'tls-inspector',
      ]);
    });

    test('batch 3 covers the 18 remaining tools', () {
      expect(<String>[for (final e in portedBatch3) e.tool.id], <String>[
        'url-parser',
        'http-status',
        'port-reference',
        'headers-parser',
        'curl-builder',
        'reverse-dns',
        'dns-name',
        'query-parser',
        'query-builder',
        'http-content-type',
        'http-cache-control',
        'http-date',
        'basic-auth',
        'port-range',
        'cookie-parser',
        'url-join',
        'http-method',
        'dns-label',
      ]);
      expect(portedBatch3Ids, isNot(contains('timestamp-converter')));
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
        await _scrollToTitle(tester, entry.tool.title);
        expect(
          find.text(entry.tool.title),
          findsWidgets,
          reason: '${entry.tool.id} is missing from the tools page',
        );
      }
      // 5 个重复项已并入现有工具，不再作为单独条目出现。
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
    // 每个已登记的工具都打开一次，并用它自己的示例输入跑一次。
    // 网络类工具不在 widget 测试里跑（见 `netrixNetworkToolIds` 的注释），
    // 它们的 `run` 由 `test/netrix_tools_contract_test.dart` 用同一张示例表跑。
    for (final PortedToolEntry entry in portedToolsInScope(isMainApp: true)) {
      testWidgets('${entry.tool.id} opens and runs with its sample input', (
        tester,
      ) async {
        final values = <String, String>{
          ...netrixSampleValues(entry.tool),
          if (entry.tool.id == 'jwt')
            'token': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl',
        };
        if (entry.tool.id == 'hex') values['input'] = 'abc';
        final isNetwork = netrixNetworkToolIds.contains(entry.tool.id);
        await _runTool(tester, entry, values: values, run: !isNetwork);

        switch (entry.tool.id) {
          case 'hex':
            expect(find.text('Hex 编码完成'), findsOneWidget);
            expect(find.text('616263'), findsOneWidget);
          case 'jwt':
            expect(find.text('JWT 已解码'), findsOneWidget);
            expect(find.textContaining('"sub": "1234"'), findsWidgets);
            expect(find.text('仅解码，不代表签名有效。'), findsOneWidget);
          default:
            if (isNetwork) {
              // 网络工具在 widget 测试里不点运行按钮，只确认表单和按钮在。
              expect(find.text('运行工具').last, findsOneWidget);
            } else {
              expect(find.text(entry.tool.title), findsWidgets);
              expect(tester.takeException(), isNull);
            }
        }
      });
    }

    testWidgets('hex decodes back and reports invalid input', (tester) async {
      final entry = allPortedTools.firstWhere((e) => e.tool.id == 'hex');
      await _mount(tester, isMainApp: true);
      await _scrollToTitle(tester, entry.tool.title);
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
      await _scrollToTitle(tester, entry.tool.title);
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
      await _scrollToTitle(tester, entry.tool.title);
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

  group('shell tools tab', () {
    late StudioProfile? previousProfile;

    setUp(() => previousProfile = StudioProfile.current);

    tearDown(() {
      StudioProfile.current = previousProfile;
      ToolStateStore.instance.clearRecent();
    });

    Future<void> mountShell(WidgetTester tester, StudioProfile profile) async {
      StudioProfile.current = profile;
      tester.view.physicalSize = const Size(1200, 14000);
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
          home: FunctionsTab(
            store: ProjectStore(),
            onOpenTerminal: () {},
            onOpenContentTool: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the main app shell lists the ported tools', (tester) async {
      await mountShell(
        tester,
        const StudioProfile(
          id: StudioProductCatalog.qfliStudioKey,
          appTitle: StudioProductCatalog.qfliStudio,
          templates: <ProjectTemplate>[],
          isOffline: true,
        ),
      );
      for (final PortedToolEntry entry in portedToolsInScope(isMainApp: true)) {
        await _scrollToTitle(tester, entry.tool.title);
        expect(find.text(entry.tool.title), findsWidgets);
      }
      // 分类筛选条和分组标题都会出现这个分类名。
      expect(find.text('文本与编码'), findsWidgets);
    });

    testWidgets('a language app shell lists none of them', (tester) async {
      await mountShell(
        tester,
        StudioProfile(
          id: StudioProductCatalog.forgeKey,
          productKey: StudioProductCatalog.forgeKey,
          appTitle: StudioProductCatalog.forge,
          templates: const <ProjectTemplate>[],
          isOffline: true,
        ),
      );
      for (final PortedToolEntry entry in allPortedTools) {
        expect(find.text(entry.tool.title), findsNothing);
      }
      expect(find.text('文本与编码'), findsNothing);
      expect(find.text('字符/Unicode'), findsOneWidget);
    });
  });
}
