import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/tools/ported/catalog.dart';
import 'package:qfli_studio_core/tools/ported/models.dart';
import 'package:qfli_studio_core/tools/ported/netrix_tool_page.dart';
import 'package:qfli_studio_core/tools/ported_tool.dart';
import 'package:qfli_studio_core/tools/ported_tools.dart';
import 'package:qfli_studio_core/tools/tool_state_store.dart';

import 'support/netrix_tool_samples.dart';

/// Everything here runs offline: HTTP(S) calls fail at once and the TCP tools
/// are pointed at a closed loopback port.
class _OfflineHttpClient implements HttpClient {
  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw SocketException('offline in the tools contract test');
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

ToolStateStore _store() =>
    ToolStateStore(backend: LocalMemoryBackend(), flushDelay: Duration.zero);

void main() {
  setUpAll(() => HttpOverrides.global = _OfflineHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  group('netrix registry contract', () {
    test('registered plus merged equals the 52 netrix tools', () {
      expect(netrixToolIds, hasLength(52));
      expect(unclaimedNetrixIds, isEmpty);
      expect(allPortedTools, hasLength(47));
      expect(mergedNetrixIds, hasLength(5));
      expect(
        <String>{...claimedNetrixIds, ...mergedNetrixIds},
        netrixToolIds.toSet(),
      );
    });

    test('every registered entry carries its netrix definition', () {
      for (final PortedToolEntry entry in allPortedTools) {
        final ToolDefinition definition = netrixTool(entry.tool.id);
        expect(identical(definition, entry.tool), isTrue, reason: entry.tool.id);
        expect(entry.audience.name, 'qfliStudioMainApp');
        expect(entry.tool.title, isNotEmpty);
        expect(entry.tool.titleEn, isNotEmpty);
        expect(entry.tool.description, isNotEmpty);
        expect(entry.tool.category, isNotNull);
      }
    });

    // Every tool runs once with its sample input. Offline tools must succeed;
    // a network tool may report a `ToolException` because the network is gone,
    // but it must finish and must not leak a timeout.
    //
    // `websocket` is excluded: `WebSocketChannel.connect` keeps retrying the
    // handshake under the offline HTTP override, so it cannot finish inside a
    // bounded test. It is covered by the validation test below instead.
    for (final String id in netrixToolIds) {
      if (mergedNetrixIds.contains(id) || id == 'websocket') continue;
      test('$id runs once with its sample input', () async {
        final ToolDefinition tool = netrixTool(id);
        final Map<String, String> values = netrixSampleValues(tool);
        final Object? result;
        try {
          result = await tool.run(values).timeout(const Duration(seconds: 20));
        } on ToolException catch (error) {
          expect(
            netrixNetworkToolIds.contains(id),
            isTrue,
            reason: '$id is offline but failed: ${error.message}',
          );
          expect(error.message, isNot('error_timeout'));
          return;
        }
        expect(result, isA<ToolResult>());
        final ToolResult typed = result as ToolResult;
        expect(typed.title, isNotEmpty);
      });
    }

    test('websocket rejects an unusable URL instead of hanging', () async {
      final ToolDefinition tool = netrixTool('websocket');
      await expectLater(
        tool.run(<String, String>{'url': 'not-a-url', 'message': 'ping'})
            .timeout(const Duration(seconds: 10)),
        throwsA(isA<ToolException>()),
      );
    });
  });

  group('netrix tool pages', () {
    testWidgets('every registered tool opens with its fields and run button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final store = _store();
      for (final PortedToolEntry entry in allPortedTools) {
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
            home: NetrixToolPage(tool: entry.tool, store: store),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(NetrixToolPage),
          findsOneWidget,
          reason: entry.tool.id,
        );
        expect(
          find.text(entry.tool.title),
          findsWidgets,
          reason: '${entry.tool.id} title',
        );
        expect(
          find.text(entry.tool.titleEn),
          findsOneWidget,
          reason: '${entry.tool.id} English name',
        );
        expect(
          find.text('运行工具'),
          findsOneWidget,
          reason: '${entry.tool.id} run button',
        );
        for (final ToolField field in entry.tool.fields) {
          expect(
            find.text(field.label),
            findsWidgets,
            reason: '${entry.tool.id} field ${field.id}',
          );
        }
        expect(tester.takeException(), isNull, reason: entry.tool.id);
      }
      await store.settled();
    });
  });
}
