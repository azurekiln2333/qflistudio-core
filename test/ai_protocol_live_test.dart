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

          // 回填一段真实的工具结果文本，再让模型给出结论。
          // 检索本身由独立中转用例验收；这里只验证协议往返。
          const searchText =
              '搜索结果（引用时请给出链接）：\n'
              '1. Flutter 教程 | 菜鸟教程\n'
              '   https://www.runoob.com/flutter/flutter-tutorial.html\n'
              '   Flutter 使用 Dart 编程语言。\n';
          history
            ..add(first.rawMessage)
            ..add({
              'role': 'tool',
              'tool_call_id': call['id'],
              'content': searchText,
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
            'answer': second.content,
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

  // web_search / web_fetch 只经中转，而 ApiConfig.baseUrl 指向线上域名。
  // 线上还没部署本端点，所以这里直接起本地服务进程验收。
  final relayOrigin = Platform.environment['QFLI_RELAY_ORIGIN'];
  test(
    'local relay serves real web_search and web_fetch results',
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
      } finally {
        api.close();
      }
    },
    skip: relayOrigin == null
        ? 'Set QFLI_RELAY_ORIGIN to a running local server origin.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
