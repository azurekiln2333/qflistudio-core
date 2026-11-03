@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/ai_panel.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/ai_file_header.dart';
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';

/// 整改任务书 §3-W3、§4 第 9 条：官方转发与文件标识。
///
/// 两条断言都对着真正的缺口：
/// - 只隐藏设置入口不够，升级前存下的自定义地址仍会被用上；
/// - 没有注释语法的文件不能为了打标识而变得无法解析。
void main() {
  /// 测试用的最小产品档位；null 表示保持默认（不开放自定义接口）。
  StudioProfile profile(bool? allowCustom) => StudioProfile(
    id: 'test-product',
    appTitle: 'Test',
    templates: const [],
    allowCustomAiEndpoint: allowCustom ?? false,
  );

  group('official products ignore a saved AI endpoint', () {
    late StudioProfile previous;

    setUp(() {
      previous = StudioProfile.current ?? profile(null);
    });

    tearDown(() {
      StudioProfile.current = previous;
    });

    test('the released OHOS profile never routes to a saved address', () {
      StudioProfile.current = profile(false);
      final settings = SettingsStore()
        ..aiBaseUrl = 'http://127.0.0.1:9'
        ..aiApiKey = 'sk-stale'
        ..aiModel = 'stale-model'
        ..aiProtocol = AiProtocol.messages;

      final endpoint = AiPanel.endpointFor(settings);
      expect(endpoint.route, AiRoute.relay);
      expect(endpoint.baseUrl, isEmpty);
      expect(endpoint.apiKey, isEmpty);
      // 日志安全的描述里也不能带出旧地址。
      expect(endpoint.toString(), isNot(contains('127.0.0.1')));
      settings.dispose();
    });

    test('a product that opts in still uses the user endpoint', () {
      StudioProfile.current = profile(true);
      final settings = SettingsStore()
        ..aiBaseUrl = 'https://api.example.test'
        ..aiApiKey = 'sk-user'
        ..aiModel = 'user-model'
        ..aiProtocol = AiProtocol.responses;

      final endpoint = AiPanel.endpointFor(settings);
      expect(endpoint.route, AiRoute.direct);
      expect(endpoint.baseUrl, 'https://api.example.test');
      expect(endpoint.model, 'user-model');
      expect(endpoint.protocol, AiProtocol.responses);
      settings.dispose();
    });

    test('an opted-in product with empty settings falls back to the relay', () {
      StudioProfile.current = profile(true);
      final settings = SettingsStore()..aiBaseUrl = '';
      expect(AiPanel.endpointFor(settings).route, AiRoute.relay);
      settings.dispose();
    });
  });

  group('relay chat needs a signed-in token', () {
    test('a reply travels through the injected sender', () async {
      StudioProfile.current = profile(false);
      final sent = <List<Map<String, dynamic>>>[];
      final pieces = await AiService.relayChat(
        systemPrompt: '系统提示',
        messages: [
          (role: 'user', content: '用户提问'),
        ],
        send: (history) async {
          sent.add(history);
          return const AiChatResult(
            model: 'server-side',
            content: '转发的回复',
            rawMessage: {'role': 'assistant', 'content': '转发的回复'},
          );
        },
      ).join();
      expect(pieces, '转发的回复');
      expect(sent.single.first['role'], 'system');
      expect(sent.single.last['content'], '用户提问');
    });
  });

  group('files without comment syntax still carry the mark', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('ai-mark-');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a written JSON file keeps its bytes and gains a sidecar', () async {
      final files = VibeProjectFiles(projectRoot: root.path);
      final marked = addAiGeneratedHeader('data.json', '{"a":1}');
      final result = await files.write('data.json', marked.content);
      final sidecar = await files.writeAiMarkSidecar(
        path: aiGeneratedSidecarPath(result.relativePath),
        content: marked.sidecarContent!,
      );

      final body = await File(p.join(root.path, 'data.json')).readAsString();
      expect(jsonDecode(body), {'a': 1});
      expect(sidecar, 'data.json.ai-generated');
      final note = await File(
        p.join(root.path, 'data.json.ai-generated'),
      ).readAsString();
      expect(note, contains(kAiGeneratedFileNote));
    });

    test('the sidecar stays inside the project root', () async {
      final files = VibeProjectFiles(projectRoot: root.path);
      final written = await files.writeAiMarkSidecar(
        path: 'sub/dir/a.csv.ai-generated',
        content: 'x',
      );
      expect(written, 'sub/dir/a.csv.ai-generated');
      expect(
        File(p.join(root.path, 'sub', 'dir', 'a.csv.ai-generated')).existsSync(),
        isTrue,
      );
    });
  });
}

