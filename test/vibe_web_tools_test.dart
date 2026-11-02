import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart';

/// `web_fetch` stays, everything that could reach Bing or an arbitrary host
/// straight from the device is gone (整改任务书 §1、§3-W3、§4 第 9 条).
///
/// The acceptance criterion is literal: “客户端和服务端都没有 bing.com 的调用”.
/// So the retirement is asserted on the tool list, on the request the client
/// would send, and on the source of this very library.
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

  group('tool surface', () {
    test('only web_fetch remains, with the OpenAI function shape', () {
      final specs = vibeWebToolSpecs();
      expect(specs.map((s) => s['function']['name']), ['web_fetch']);
      for (final spec in specs) {
        expect(spec['type'], 'function');
        expect(spec['function']['parameters']['type'], 'object');
        expect(spec['function']['parameters']['additionalProperties'], isFalse);
      }
    });

    test('web_search is no longer a tool name', () {
      expect(kVibeWebToolNames, {'web_fetch'});
      expect(isVibeWebTool('web_search'), isFalse);
      expect(isVibeWebTool('web_fetch'), isTrue);
      expect(isVibeWebTool('read_file'), isFalse);
    });

    test('the combined list holds one web tool and every local tool', () {
      final combined = vibeToolSpecsWithWeb();
      expect(combined.length, vibeToolSpecs().length + 1);
      final names = combined.map((s) => s['function']['name']).toList();
      expect(names, contains('list_files'));
      expect(names, contains('web_fetch'));
      expect(names, isNot(contains('web_search')));
    });

    test(
      'calling web_search is refused locally and never reaches the wire',
      () async {
        final spec = vibeWebToolSpecs().single;
        expect(spec['function']['name'], isNot('web_search'));
        // A model can still emit a stale name; it must not fall through to a
        // network call.
        final result = await executeVibeWebTool(
          name: 'web_search',
          arguments: const {'query': 'Flutter'},
          api: clientReturning({}),
          token: 'token-1',
        );
        expect(result, isNull);
        expect(sent, isEmpty);
      },
    );

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

  group('no direct fallback', () {
    test(
      'a 404 from the relay is reported, not retried against the origin',
      () async {
        final api = clientReturning({
          'error': 'Cannot POST /api/ai/web_fetch',
        }, status: 404);
        final result = (await executeVibeWebTool(
          name: 'web_fetch',
          arguments: const {'url': 'https://example.com/a'},
          api: api,
          token: 'token-1',
        ))!;
        expect(result.ok, isFalse);
        // The SDK maps the relay error to the `network` code and keeps the server
        // text. What matters is that the failure is reported, not retried.
        expect(result.modelText, contains('error(network)'));
        expect(result.modelText, contains('Cannot POST'));
        // Exactly one request: no second hop anywhere.
        expect(sent, hasLength(1));
        expect(sent.single.url.path, '/api/ai/web_fetch');
      },
    );

    test('an injected direct client is never used', () async {
      var directCalls = 0;
      final direct = MockClient((request) async {
        directCalls++;
        return http.Response('<rss/>', 200);
      });
      final api = clientReturning({'error': 'down'}, status: 502);
      await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/a'},
        api: api,
        token: 'token-1',
        directClient: direct,
      );
      expect(directCalls, 0);
    });

    test('the library source no longer calls Bing or a search endpoint', () {
      // The acceptance criterion is about the code, so assert on code lines:
      // a comment may explain what was removed.
      final code = _readLibrarySource()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n')
          .toLowerCase();
      expect(code, isNot(contains('bing')));
      expect(code, isNot(contains('web_search')));
      expect(code, isNot(contains('directsearch')));
      expect(code, isNot(contains('directfetch')));
    });
  });

  group('web_fetch', () {
    test('formats the relayed page with title, url and text', () async {
      final api = clientReturning({
        'url': 'https://example.com/a',
        'title': '示例页面',
        'text': '正文第一行\n正文第二行',
        'truncated': false,
      });
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/a'},
        api: api,
        token: 'token-1',
      ))!;
      expect(result.ok, isTrue);
      expect(result.modelText, contains('示例页面'));
      expect(result.modelText, contains('https://example.com/a'));
      expect(result.modelText, contains('正文第一行'));
      expect(sent.single.url.path, '/api/ai/web_fetch');
      expect(sent.single.headers['authorization'], 'Bearer token-1');
      expect(jsonDecode(bodies.single), {'url': 'https://example.com/a'});
    });

    test('clips long text and marks the truncation', () async {
      final api = clientReturning({
        'title': 'long',
        'text': 'A' * (kVibeWebMaxFetchChars + 500),
        'truncated': true,
      });
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/long'},
        api: api,
        token: 'token-1',
      ))!;
      expect(result.ok, isTrue);
      expect(result.summary, contains('已截断'));
      expect(result.modelText, contains('…（已截断）'));
      expect(result.modelText.length, lessThan(kVibeWebMaxFetchChars + 500));
    });

    test('an empty body is a success with no text, not an error', () async {
      final api = clientReturning({'title': '', 'text': '   '});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/empty'},
        api: api,
        token: 'token-1',
      ))!;
      expect(result.ok, isTrue);
      expect(result.summary, contains('没有正文'));
    });
  });

  group('argument validation', () {
    test('a non-http scheme is rejected before any request', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'file:///etc/passwd'},
        api: api,
        token: 't',
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('error(ssrf)'));
      expect(sent, isEmpty);
    });

    test('credentials in the URL are rejected', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://user:pw@example.com/'},
        api: api,
        token: 't',
      ))!;
      expect(result.modelText, contains('error(ssrf)'));
      expect(sent, isEmpty);
    });

    test('loopback, private and metadata hosts are rejected', () async {
      final api = clientReturning({});
      for (final url in const [
        'http://localhost/x',
        'http://127.0.0.1/x',
        'http://10.1.2.3/x',
        'http://192.168.1.1/x',
        'http://169.254.169.254/latest/meta-data',
        'http://[::1]/x',
        'http://[fe80::1]/x',
        'http://[fc00::1]/x',
      ]) {
        final result = (await executeVibeWebTool(
          name: 'web_fetch',
          arguments: {'url': url},
          api: api,
          token: 't',
        ))!;
        expect(result.ok, isFalse, reason: url);
        expect(result.modelText, contains('error(ssrf)'), reason: url);
      }
      expect(sent, isEmpty);
    });

    test('a public host passes the local check', () {
      expect(isBlockedFetchHost('example.com'), isFalse);
      expect(isBlockedFetchHost('8.8.8.8'), isFalse);
      expect(isBlockedFetchHost('::ffff:8.8.8.8'), isFalse);
      expect(isBlockedFetchHost('[2606:4700::1111]'), isFalse);
      expect(isBlockedFetchHost('::ffff:127.0.0.1'), isTrue);
    });

    test('a missing url is an argument error', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {},
        api: api,
        token: 't',
      ))!;
      expect(result.ok, isFalse);
      expect(result.modelText, contains('error(error)'));
      expect(sent, isEmpty);
    });
  });

  group('policy gates', () {
    test('an offline product refuses before any network use', () async {
      StudioProfile.current = const StudioProfile(
        id: 'offline',
        appTitle: 'Offline',
        templates: [],
        offlineOnly: true,
      );
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/a'},
        api: api,
        token: 't',
      ))!;
      expect(result.modelText, contains('OFFLINE_ONLY'));
      expect(sent, isEmpty);
      expect(vibeWebToolsAvailable, isFalse);
    });

    test('a caller-supplied gate also refuses', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/a'},
        api: api,
        token: 't',
        onlineAllowed: () => false,
      ))!;
      expect(result.modelText, contains('OFFLINE_ONLY'));
      expect(sent, isEmpty);
    });

    test('a missing token refuses', () async {
      final api = clientReturning({});
      final result = (await executeVibeWebTool(
        name: 'web_fetch',
        arguments: const {'url': 'https://example.com/a'},
        api: api,
        token: '',
      ))!;
      expect(result.modelText, contains('error(auth)'));
      expect(sent, isEmpty);
    });
  });
}

/// Reads the library under test so the "no bing.com" claim is checked on code.
String _readLibrarySource() =>
    File('lib/vibe_coding/vibe_web_tools.dart').readAsStringSync();
