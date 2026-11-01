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
      // 503 属于“中转不可用”，会回退直连；这里禁用回退，只看中转错误本身。
      final api = clientReturning({'error': '搜索服务未配置'}, status: 503);
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: api,
        token: 't',
        allowDirectFallback: false,
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

  group('direct fallback when the relay is not deployed', () {
    // 真实线上状态：/api/ai/web_search 返回 404。
    ApiClient relay404() => ApiClient(
      transport: MockClient(
        (_) async => http.Response('Cannot POST /api/ai/web_search', 404),
      ),
    );

    // 真实 Bing RSS 响应片段（与 2026-11-01 观测一致）。
    const realRss =
        '<?xml version="1.0" encoding="utf-8" ?><rss version="2.0">'
        '<channel><title>必应：Flutter 教程</title>'
        '<item><title>Flutter - Build apps for any screen</title>'
        '<link>https://flutter.dev/</link>'
        '<description>Flutter transforms the entire app development process.</description></item>'
        '<item><title><![CDATA[Flutter 教程 | 菜鸟教程]]></title>'
        '<link>https://www.runoob.com/flutter/flutter-tutorial.html</link>'
        '<description>Flutter 是 UI 工具包 &amp; 更多。</description></item>'
        '<item><title>Bad</title><link>javascript:alert(1)</link>'
        '<description>x</description></item>'
        '</channel></rss>';

    test('search falls back to a direct Bing RSS request', () async {
      final directCalls = <http.Request>[];
      final direct = MockClient((request) async {
        directCalls.add(request);
        // http.Response 默认按 latin1 编码，中文 RSS 必须用 bytes + UTF-8。
        return http.Response.bytes(
          utf8.encode(realRss),
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      });

      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'Flutter 教程'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;

      expect(result.ok, isTrue, reason: result.modelText);
      expect(result.direct, isTrue);
      expect(result.summary, contains('直连'));
      expect(result.modelText, contains('Flutter - Build apps for any screen'));
      expect(
        result.modelText,
        contains('https://www.runoob.com/flutter/flutter-tutorial.html'),
      );
      expect(result.modelText, contains('Flutter 教程 | 菜鸟教程'));
      expect(result.modelText, isNot(contains('javascript:')));

      expect(directCalls, hasLength(1));
      final url = directCalls.single.url;
      expect(url.host, 'www.bing.com');
      expect(url.queryParameters['format'], 'rss');
      expect(url.queryParameters['q'], 'Flutter 教程');
      expect(directCalls.single.headers['user-agent'], contains('Mozilla'));
    });

    test('fetch falls back to a direct request and extracts text', () async {
      final direct = MockClient(
        (request) async => http.Response(
          '<html><head><title>Demo &amp; Page</title>'
          '<style>.a{color:red}</style></head>'
          '<body><script>evil()</script><h1>正文标题</h1><p>第一段</p></body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/doc'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isTrue, reason: result.modelText);
      expect(result.direct, isTrue);
      expect(result.summary, contains('直连'));
      expect(result.modelText, contains('Demo & Page'));
      expect(result.modelText, contains('正文标题'));
      expect(result.modelText, isNot(contains('evil')));
      expect(result.modelText, isNot(contains('color:red')));
    });

    test('direct fetch rejects an internal redirect target', () async {
      var requests = 0;
      final direct = MockClient((request) async {
        requests++;
        return http.Response('', 302, headers: {
          'location': 'http://127.0.0.1/admin',
        });
      });
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/go'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('ssrf'));
      // 只跟一跳：拒绝发生在向内网发请求之前。
      expect(requests, 1);
    });

    test('direct fetch rejects a non-http scheme and metadata address', () async {
      final direct = MockClient((_) async => http.Response('secret', 200));
      for (final url in [
        'http://169.254.169.254/latest/meta-data/',
        'file:///etc/passwd',
      ]) {
        final result = (await executeVibeWebTool(
          name: 'web_fetch',
          arguments: {'url': url},
          api: relay404(),
          token: 't',
          directClient: direct,
        ))!;
        expect(result.ok, isFalse, reason: url);
      }
    });

    test('a 401 relay reply is not retried directly', () async {
      var directCalls = 0;
      final direct = MockClient((_) async {
        directCalls++;
        return http.Response.bytes(utf8.encode(realRss), 200);
      });
      final api = ApiClient(
        transport: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'error': '未登录'})),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: api,
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isFalse);
      expect(result.direct, isFalse);
      expect(directCalls, 0, reason: '业务拒绝不该触发直连');
    });

    test('a 5xx relay reply also falls back', () async {
      final direct = MockClient(
        (_) async => http.Response.bytes(utf8.encode(realRss), 200),
      );
      final api = ApiClient(
        transport: MockClient(
          // http.Response 默认按 latin1 编码，中文错误体必须声明 UTF-8。
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'error': '服务繁忙'})),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: api,
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isTrue, reason: result.modelText);
      expect(result.direct, isTrue);
    });

    test('fallback can be disabled', () async {
      var directCalls = 0;
      final direct = MockClient((_) async {
        directCalls++;
        return http.Response.bytes(utf8.encode(realRss), 200);
      });
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: relay404(),
        token: 't',
        directClient: direct,
        allowDirectFallback: false,
      ))!;
      expect(result.ok, isFalse);
      expect(directCalls, 0);
    });

    test('direct failure reports both paths honestly', () async {
      final direct = MockClient(
        (_) async => http.Response('gone', 500),
      );
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isFalse);
      expect(result.direct, isTrue);
      expect(result.modelText, contains('直连也失败'));
      expect(result.modelText, contains('404'));
    });
  });

  group('direct redirects', () {
    // 真实情况：www.bing.com 先 302 到 cn.bing.com，再返回 RSS。
    ApiClient relay404() => ApiClient(
      transport: MockClient(
        (_) async => http.Response('Cannot POST /api/ai/web_search', 404),
      ),
    );

    test('follows a 302 to a public host and parses the result', () async {
      final hops = <String>[];
      final direct = MockClient((request) async {
        hops.add(request.url.toString());
        if (request.url.host == 'www.bing.com') {
          return http.Response('', 302, headers: {
            'location':
                'https://cn.bing.com/search?q=Flutter&format=rss&count=3',
          });
        }
        return http.Response.bytes(
          utf8.encode(
            '<rss><channel>'
            '<item><title>区域站点结果</title>'
            '<link>https://cn.example/one</link>'
            '<description>正文摘要</description></item>'
            '</channel></rss>',
          ),
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      });

      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'Flutter'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;

      expect(result.ok, isTrue, reason: result.modelText);
      expect(result.direct, isTrue);
      expect(result.modelText, contains('区域站点结果'));
      expect(result.modelText, contains('https://cn.example/one'));
      // 两跳：原始地址 + 跳转后地址。
      expect(hops, hasLength(2));
      expect(hops.first, contains('www.bing.com'));
      expect(hops.last, contains('cn.bing.com'));
    });

    test('rejects a 302 that points at 127.0.0.1', () async {
      final hops = <String>[];
      final direct = MockClient((request) async {
        hops.add(request.url.toString());
        return http.Response('', 302, headers: {
          'location': 'http://127.0.0.1:8080/admin',
        });
      });

      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;

      expect(result.ok, isFalse);
      expect(result.modelText, contains('ssrf'));
      // 关键：内网地址一次都不应该被请求。
      expect(hops, hasLength(1));
      expect(hops.single, isNot(contains('127.0.0.1')));
    });

    test('rejects a redirect that downgrades to a non-http scheme', () async {
      final direct = MockClient(
        (_) async => http.Response('', 302, headers: {
          'location': 'file:///etc/passwd',
        }),
      );
      final result = (await executeVibeWebTool(
        name: 'web_search',
        arguments: const {'query': 'x'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('ssrf'));
    });

    test('stops after the redirect budget', () async {
      // 用字面公网 IP，避开 DNS 解析失败干扰跳数断言。
      var hops = 0;
      final direct = MockClient((request) async {
        hops++;
        return http.Response('', 302, headers: {'location': '/next'});
      });
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://93.184.216.34/start'},
        api: relay404(),
        token: 't',
        directClient: direct,
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('跳转'));
      // 初始请求 + kVibeDirectMaxRedirects 次跳转后停止。
      expect(hops, kVibeDirectMaxRedirects + 1);
    });
  });

  group('direct parsing and SSRF primitives', () {    test('parseBingRss handles CDATA and drops unsafe links', () {
      const xml =
          '<rss><channel>'
          '<item><title><![CDATA[A & B]]></title><link>https://a.example/</link>'
          '<description>x</description></item>'
          '<item><title>T2</title><link>javascript:void(0)</link></item>'
          '<item><title>T3</title><link></link></item>'
          '</channel></rss>';
      final results = parseBingRss(xml, 8);
      expect(results, hasLength(1));
      expect(results.single['title'], 'A & B');
      expect(results.single['url'], 'https://a.example/');
    });

    test('parseBingRss honours the limit', () {
      final xml = [
        '<rss>',
        for (var i = 0; i < 5; i++)
          '<item><title>T$i</title><link>https://e$i.example/</link>'
              '<description>s</description></item>',
        '</rss>',
      ].join();
      expect(parseBingRss(xml, 2), hasLength(2));
    });

    test('extractPageText and normalizePageText', () {
      // title 不进 body 文本；body 只保留正文并去空行。
      final page = extractPageText(
        '<html><head><title>T</title></head><body>\n\n  a   b \n<p>c</p>\n</body></html>',
      );
      expect(page.title, 'T');
      expect(page.text, 'a b\nc');
      expect(normalizePageText('  a \n\n\n b\t\tc  '), 'a\nb c');
    });

    test('assertPublicHost rejects names resolving to private addresses', () async {
      // 任一 DNS 记录落入内网就整体拒绝。
      Object? caught;
      try {
        await assertPublicHost(
          'mixed.example',
          resolve: (_) async => ['93.184.216.34', '10.1.2.3'],
        );
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isNotNull, reason: '内网记录必须被拒绝');
      expect(caught.toString(), contains('内网'));

      // 只有公网记录时放行，并回传解析结果。
      expect(
        await assertPublicHost(
          'ok.example',
          resolve: (_) async => ['93.184.216.34'],
        ),
        ['93.184.216.34'],
      );
    });

    test('assertPublicHost rejects localhost without a lookup', () async {
      var lookups = 0;
      Object? caught;
      try {
        await assertPublicHost(
          'api.localhost',
          resolve: (_) async {
            lookups++;
            return ['127.0.0.1'];
          },
        );
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isNotNull, reason: 'localhost 必须被拒绝');
      expect(caught.toString(), contains('本机'));
      expect(lookups, 0, reason: '不该为 localhost 发起解析');
    });
  });

  group('offline-only products', () {    test('both tools refuse with zero requests', () async {
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
