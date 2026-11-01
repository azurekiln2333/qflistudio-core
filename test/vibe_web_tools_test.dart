import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart';

void main() {
  late StudioProfile? previous;
  late List<http.BaseRequest> sent;
  late List<String> bodies;

  setUp(() {
    previous = StudioProfile.current;
    StudioProfile.current = null;
    sent = [];
    bodies = [];
  });

  tearDown(() {
    StudioProfile.current = previous;
  });

  ApiClient clientReturning(Object body, {int status = 200}) {
    return ApiClient(
      transport: MockClient((request) async {
        sent.add(request);
        bodies.add(request.body);
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  group('specs', () {
    test('two tools with OpenAI function shape', () {
      final specs = vibeWebToolSpecs();
      expect(specs.map((s) => s['function']['name']), [
        'web_search',
        'web_fetch',
      ]);
      for (final spec in specs) {
        expect(spec['type'], 'function');
        expect(spec['function']['parameters']['type'], 'object');
        expect(
          spec['function']['parameters']['additionalProperties'],
          isFalse,
        );
      }
    });

    test('names are recognised and local specs are untouched', () {
      expect(kVibeWebToolNames, {'web_search', 'web_fetch'});
      expect(isVibeWebTool('web_search'), isTrue);
      expect(isVibeWebTool('read_file'), isFalse);
      final combined = vibeToolSpecsWithWeb();
      expect(combined.length, vibeToolSpecs().length + 2);
      expect(
        combined.map((s) => s['function']['name']),
        containsAll(['list_files', 'web_search', 'web_fetch']),
      );
    });

    test('non-web tool names return null so callers fall through', () async {
      final result = await executeVibeWebTool(
        name: 'read_file',
        arguments: const {'path': 'a.txt'},
        api: clientReturning({}),
        token: 't',
      );
      expect(result, isNull);
      expect(sent, isEmpty);
    });
  });

  group('web_search', () {
    test('formats real results with title, url and snippet', () async {
      final api = clientReturning({
        'provider': 'bing-rss',
        'results': [
          {
            'title': 'Flutter 教程 | 菜鸟教程',
            'url': 'https://www.runoob.com/flutter/flutter-tutorial.html',
            'snippet': 'Flutter 使用 Dart 编程语言。',
          },
          {'title': 'No url item', 'url': '', 'snippet': 'dropped'},
        ],
      });
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': ' Flutter 教程 '},
        api: api,
        token: 'token-1',
      ))!;
      expect(result.ok, isTrue);
      expect(result.summary, '1 条结果');
      expect(result.modelText, contains('Flutter 教程 | 菜鸟教程'));
      expect(
        result.modelText,
        contains('https://www.runoob.com/flutter/flutter-tutorial.html'),
      );
      expect(result.modelText, contains('Flutter 使用 Dart 编程语言。'));
      expect(result.modelText, isNot(contains('No url item')));

      expect(sent.single.url.path, '/api/ai/web_search');
      expect(sent.single.headers['authorization'], 'Bearer token-1');
      expect(jsonDecode(bodies.single), {
        'query': 'Flutter 教程',
        'limit': kVibeWebMaxResults,
      });
    });

    test('empty results are reported honestly, not as success text', () async {
      final api = clientReturning({'results': <Object>[]});
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'zzzz-no-such'},
        api: api,
        token: 't',
      ))!;
      expect(result.ok, isTrue);
      expect(result.summary, '没有结果');
      expect(result.modelText, contains('没有找到'));
    });

    test('rejects an empty or overlong query before any request', () async {
      final api = clientReturning({});
      final empty = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': '   '},
        api: api,
        token: 't',
      ))!;
      expect(empty.ok, isFalse);
      expect(empty.modelText, contains('error(error)'));
      final long = (await executeVibeWebTool(
        name: 'web_search',
        arguments: {'query': 'x' * 201},
        api: api,
        token: 't',
      ))!;
      expect(long.ok, isFalse);
      expect(sent, isEmpty);
    });

    test('server errors become tool failures, not exceptions', () async {
      final api = clientReturning({'error': '搜索服务未配置'}, status: 503);
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: api,
        token: 't',
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('搜索服务未配置'));
    });
  });

  group('web_fetch', () {
    test('returns cleaned text and caps its length', () async {
      final api = clientReturning({
        'url': 'https://flutter.dev/',
        'title': 'Flutter',
        'text': 'A' * (kVibeWebMaxFetchChars + 50),
        'truncated': true,
      });
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://flutter.dev/'},
        api: api,
        token: 't',
      ))!;
      expect(result.ok, isTrue);
      expect(result.modelText, contains('Flutter'));
      expect(result.modelText, contains('已截断'));
      expect(result.modelText.length, lessThan(kVibeWebMaxFetchChars + 200));
      expect(sent.single.url.path, '/api/ai/web_fetch');
    });

    test('reports a page without body text honestly', () async {
      final api = clientReturning({
        'url': 'https://example.com/',
        'title': '',
        'text': '',
        'truncated': false,
      });
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/'},
        api: api,
        token: 't',
      ))!;
      expect(result.ok, isTrue);
      expect(result.summary, '页面没有正文');
    });

    for (final url in [
      'http://127.0.0.1/',
      'http://localhost:8080/admin',
      'http://169.254.169.254/latest/meta-data/',
      'http://10.0.0.5/',
      'http://192.168.1.1/',
      'http://[::1]/',
      'http://100.64.1.1/',
    ]) {
      test('SSRF guard rejects $url without a request', () async {
        final api = clientReturning({});
        final result = (await executeVibeWebTool(
          name: 'web_fetch',
          arguments: {'url': url},
          api: api,
          token: 't',
        ))!;
        expect(result.ok, isFalse);
        expect(result.modelText, contains('error(ssrf)'));
        expect(sent, isEmpty);
      });
    }

    test('rejects non-http schemes and credentials', () async {
      final api = clientReturning({});
      for (final url in [
        'file:///etc/passwd',
        'ftp://example.com/a',
        'https://user:pass@example.com/',
        'not a url',
      ]) {
        final result = (await executeVibeWebTool(
          name: 'web_fetch',
          arguments: {'url': url},
          api: api,
          token: 't',
        ))!;
        expect(result.ok, isFalse, reason: url);
      }
      expect(sent, isEmpty);
    });

    test('blocked host helper matches the guard used by the tool', () {
      for (final host in [
        'localhost',
        'a.localhost',
        '127.0.0.1',
        '10.1.2.3',
        '172.20.0.1',
        '192.168.0.1',
        '169.254.169.254',
        '::1',
        'fd00::1',
        'fe80::1',
      ]) {
        expect(isBlockedFetchHost(host), isTrue, reason: host);
      }
      for (final host in ['example.com', '8.8.8.8', '2606:4700::1111']) {
        expect(isBlockedFetchHost(host), isFalse, reason: host);
      }
    });
  });

  group('offline-only products', () {
    test('both tools refuse with zero requests', () async {
      StudioProfile.current = StudioProfile(
        id: 'offline',
        appTitle: 'Offline',
        templates: [],
        offlineOnly: true,
      );
      expect(vibeWebToolsAvailable, isFalse);
      final api = clientReturning({});
      for (final call in [
        ('web_search', <String, dynamic>{'query': 'x'}),
        ('web_fetch', <String, dynamic>{'url': 'https://example.com/'}),
      ]) {
        final result = (await executeVibeWebTool(
          name: call.$1,
          arguments: call.$2,
          api: api,
          token: 't',
        ))!;
        expect(result.ok, isFalse);
        expect(result.modelText, contains('error(OFFLINE_ONLY)'));
      }
      expect(sent, isEmpty);
    });

    test('onlineAllowed=false behaves like an offline product', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: api,
        token: 't',
        onlineAllowed: () => false,
      ))!;
      expect(result.ok, isFalse);
      expect(sent, isEmpty);
    });

    test('a missing token is reported without a request', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: api,
        token: '',
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('error(auth)'));
      expect(sent, isEmpty);
    });

    test('the main product keeps both tools', () {
      expect(vibeWebToolsAvailable, isTrue);
      expect(offlineOnlyProduct(), isFalse);
    });
  });
}
