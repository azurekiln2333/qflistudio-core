// 真实接口验收：三种协议各完成一次工具调用回合，并跑通联网工具。
//
// 直接连调试上游，凭据只从环境变量读取，不进入仓库、日志或证据文件。
// 与中转验收（vibe_live_integration_test）分开，避免混淆两种链路。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart';

void main() {
  final baseUrl = Platform.environment['QFLI_DEBUG_BASE_URL'];
  final apiKey = Platform.environment['QFLI_DEBUG_API_KEY'];
  final model = Platform.environment['QFLI_DEBUG_MODEL'];
  final configured =
      baseUrl != null && baseUrl.isNotEmpty &&
      apiKey != null && apiKey.isNotEmpty &&
      model != null && model.isNotEmpty;

  ApiClient directClient() => ApiClient(
    transport: IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
  );

  AiEndpoint direct(AiProtocol protocol) => AiEndpoint.direct(
    baseUrl: baseUrl!,
    apiKey: apiKey!,
    model: model!,
    protocol: protocol,
  );

  late StudioProfile? previous;

  setUp(() {
    previous = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() => StudioProfile.current = previous);

  for (final protocol in AiProtocol.values) {
    test(
      '${protocol.id} completes one tool-call round on the debug upstream',
      () async {
        final api = directClient();
        final evidence = <String, Object?>{};
        try {
          final history = <Map<String, dynamic>>[
            {'role': 'system', 'content': '你必须先调用工具，不要凭猜测回答。'},
            {
              'role': 'user',
              'content': '用 web_search 查一下 "Flutter 教程"，只调用工具。',
            },
          ];
          final first = await api.aiChat(
            token: 'direct',
            messages: history,
            tools: vibeWebToolSpecs(),
            endpoint: direct(protocol),
          );
          expect(first.rawMessage['role'], 'assistant');
          expect(
            first.toolCalls,
            isNotEmpty,
            reason: '${protocol.id} 必须返回真实工具调用：${first.content}',
          );
          final call = first.toolCalls.first;
          expect(call['type'], 'function');
          expect(call['function']['name'], 'web_search');
          final args = jsonDecode(call['function']['arguments'] as String);
          expect(args, isA<Map>());
          expect((args['query'] as String).trim(), isNotEmpty);

          // 用真实搜索结果回填，再让模型给出结论。
          final search = (await executeVibeWebTool(
            name: 'web_search',
            arguments: Map<String, dynamic>.from(args),
            api: api,
            token: 'direct',
          ))!;
          expect(search.ok, isTrue, reason: search.modelText);
          expect(search.modelText, contains('http'));

          history
            ..add(first.rawMessage)
            ..add({
              'role': 'tool',
              'tool_call_id': call['id'],
              'content': search.modelText,
            });
          final second = await api.aiChat(
            token: 'direct',
            messages: history,
            tools: vibeWebToolSpecs(),
            endpoint: direct(protocol),
          );
          expect(second.content.trim(), isNotEmpty);
          expect(second.content, contains('http'));

          evidence[protocol.id] = {
            'toolName': call['function']['name'],
            'query': args['query'],
            'searchSummary': search.summary,
            'answer': second.content,
            'webToolSpecs': vibeWebToolSpecs().length,
          };
        } finally {
          api.close();
          final out = Directory('build/ai-live')..createSync(recursive: true);
          await File(
            p.join(out.path, '${protocol.id}.json'),
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
        }
      },
      skip: configured ? false : 'Set QFLI_DEBUG_BASE_URL/KEY/MODEL.',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  // web_fetch 与服务端代理搜索都走中转 `/api/ai/*`，需要已部署的服务器。
  // 未给出 origin 时跳过，而不是用直连参数去撞一个不存在的端点。
  final relayOrigin = Platform.environment['QFLI_RELAY_ORIGIN'];
  test(
    'relay web_search and web_fetch return real content',
    () async {
      final api = ApiClient();
      try {
        final search = (await executeVibeWebTool(
          name: 'web_search',
          arguments: const {'query': 'Flutter 教程'},
          api: api,
          token: relayOrigin!,
        ))!;
        expect(search.ok, isTrue, reason: search.modelText);
        expect(search.modelText, contains('http'));

        final page = (await executeVibeWebTool(
          name: 'web_fetch',
          arguments: const {'url': 'https://flutter.dev/'},
          api: api,
          token: relayOrigin,
        ))!;
        expect(page.ok, isTrue, reason: page.modelText);
        expect(page.modelText.toLowerCase(), contains('flutter'));
        expect(page.modelText.length, greaterThan(200));
      } finally {
        api.close();
      }
    },
    skip: relayOrigin == null
        ? 'Set QFLI_RELAY_ORIGIN and QFLI_RELAY_TOKEN for the deployed server.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
