@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:qfli_studio_core/config/api_config.dart';
import 'package:qfli_studio_core/config/client_platform.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

import 'support/ohos_target.dart';

/// Contract C 节：every request carries `X-Client-Platform: <platform>-app/<版本>`.
///
/// The server records this header as the login platform (整改任务书 §4 第 1 条),
/// so a request without it, or with a non-ASCII value that `http` would reject,
/// is a compliance defect rather than a cosmetic one.
void main() {
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
  });

  group('ClientPlatform.header', () {
    test('maps every runtime platform to a documented prefix', () {
      expect(
        ClientPlatform.fromTargetPlatform(ohosPlatform),
        'harmonyos',
      );
      expect(
        ClientPlatform.fromTargetPlatform(TargetPlatform.android),
        'android',
      );
      expect(ClientPlatform.fromTargetPlatform(TargetPlatform.iOS), 'ios');
      expect(
        ClientPlatform.fromTargetPlatform(TargetPlatform.windows),
        'windows',
      );
      expect(ClientPlatform.fromTargetPlatform(TargetPlatform.macOS), 'macos');
      expect(ClientPlatform.fromTargetPlatform(TargetPlatform.linux), 'linux');
      // Every mapped prefix must be one the contract lists.
      for (final platform in TargetPlatform.values) {
        expect(
          ClientPlatform.knownPlatforms,
          contains(ClientPlatform.fromTargetPlatform(platform)),
          reason: '$platform',
        );
      }
    });

    test('keeps only ASCII and never returns an empty version', () {
      expect(ClientPlatform.sanitizeVersion('1.2.3'), '1.2.3');
      // A non-ASCII tag would make the whole request fail in `http`.
      expect(ClientPlatform.sanitizeVersion('1.0.0 内测'), '1.0.0');
      expect(
        ClientPlatform.sanitizeVersion('  \t '),
        ClientPlatform.fallbackVersion,
      );
      expect(
        ClientPlatform.sanitizeVersion(''),
        ClientPlatform.fallbackVersion,
      );
      expect(ClientPlatform.sanitizeVersion('a' * 100), hasLength(40));
    });

    test('uses the product client version and falls back to 1.0.0', () {
      expect(ClientPlatform.version, ClientPlatform.fallbackVersion);
      StudioProfile.current = const StudioProfile(
        id: 'header',
        appTitle: 'Header',
        templates: [],
        clientVersion: '2.3.4',
      );
      expect(ClientPlatform.version, '2.3.4');
      expect(ClientPlatform.header, endsWith('-app/2.3.4'));
    });

    test('header shape is <platform>-app/<version>', () {
      final parts = ClientPlatform.header.split('/');
      expect(parts, hasLength(2));
      expect(parts.first, endsWith('-app'));
      expect(
        ClientPlatform.knownPlatforms,
        contains(parts.first.split('-').first),
      );
      expect(parts.last, isNotEmpty);
      expect(parts.last.codeUnits.every((u) => u > 0x20 && u < 0x7f), isTrue);
    });
  });

  group('ApiClient sends the header', () {
    late HttpServer server;
    late List<Map<String, String>> received;
    late http.Client transport;

    setUp(() async {
      received = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        received.add({
          'path': request.uri.path,
          'method': request.method,
          'platform': request.headers.value('x-client-platform') ?? '',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(switch (request.uri.path) {
            '/api/posts' => {'id': 'post-1'},
            '/api/reports' => {'id': 'r1', 'status': 'pending'},
            '/api/users/me/deactivate' => {'status': 'deactivated'},
            _ => {'items': [], 'ok': true},
          }),
        );
        await request.response.close();
      });
      final delegate = IOClient(HttpClient());
      transport = _RewritingClient(delegate, server.port);
    });

    tearDown(() async {
      transport.close();
      await server.close(force: true);
    });

    test('a plain GET carries the header', () async {
      final client = ApiClient(transport: transport);
      await client.zones();
      expect(received, hasLength(1));
      expect(received.single['platform'], ClientPlatform.header);
    });

    test('an authenticated write carries both header and token', () async {
      final client = ApiClient(transport: transport);
      await client.createPost(
        token: 'tok',
        type: 'discussion',
        zoneId: 'z1',
        title: '标题',
        content: '内容内容内容',
        tags: const ['tag'],
      );
      expect(received.single['method'], 'POST');
      expect(received.single['platform'], ClientPlatform.header);
    });

    test('the terminal stream request carries the header too', () async {
      final client = ApiClient(transport: transport);
      // Only the request headers matter here, so a bare request is enough:
      // the stream endpoint answers JSON instead of NDJSON on purpose.
      final request = http.Request(
        'POST',
        ApiConfig.endpoint('/api/terminal/exec/stream'),
      )..headers['x-client-platform'] = ClientPlatform.header;
      await transport.send(request);
      expect(received.single['path'], '/api/terminal/exec/stream');
      expect(received.single['platform'], ClientPlatform.header);
      expect(client, isNotNull);
    });

    test('report and deactivate send the contract bodies', () async {
      final client = ApiClient(transport: transport);
      final report = await client.report(
        token: 'tok',
        targetType: 'post',
        targetId: 'p1',
        reason: '广告引流',
      );
      expect(report.id, 'r1');
      expect(report.status, 'pending');
      await client.deactivateAccount('tok');

      expect(received.map((r) => r['path']), [
        '/api/reports',
        '/api/users/me/deactivate',
      ]);
      expect(
        received.every((r) => r['platform'] == ClientPlatform.header),
        isTrue,
      );
    });

    test('an unknown report target type never reaches the wire', () async {
      final client = ApiClient(transport: transport);
      await expectLater(
        client.report(
          token: 'tok',
          targetType: 'profile',
          targetId: 'p1',
          reason: '其他',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(received, isEmpty);
    });
  });
}

/// Rewrites the official origin to the loopback test server.
class _RewritingClient extends http.BaseClient {
  _RewritingClient(this._delegate, this.port);

  final http.Client _delegate;
  final int port;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final local =
        http.Request(
            request.method,
            Uri(
              scheme: 'http',
              host: InternetAddress.loopbackIPv4.address,
              port: port,
              path: request.url.path,
              query: request.url.hasQuery ? request.url.query : null,
            ),
          )
          ..followRedirects = false
          ..headers.addAll(request.headers);
    return _delegate.send(local);
  }

  @override
  void close() => _delegate.close();
}
