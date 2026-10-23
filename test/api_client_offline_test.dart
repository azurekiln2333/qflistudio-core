import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:qfli_studio_core/config/api_config.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

const _offline = StudioProfile(
  id: 'offline-api-test',
  appTitle: 'Offline',
  templates: [],
  isOffline: true,
);

const _user = {
  'id': 12,
  'username': 'demo',
  'nickname': 'Local sentinel',
  'bio': '',
  'avatarColor': '#2196F3',
  'points': 10,
  'checkinStreak': 2,
  'provider': 'local',
  'isAdmin': false,
};

void main() {
  late StudioProfile? previousProfile;
  late HttpServer server;
  late _LoopbackTransport transport;
  late List<_ReceivedRequest> received;

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
    received = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = _LoopbackTransport(server.port);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add(
        _ReceivedRequest(
          request.method,
          request.uri,
          request.headers.value(HttpHeaders.authorizationHeader),
          body,
        ),
      );
      if (request.uri.path == '/api/terminal/exec/stream') {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-ndjson',
        );
        request.response.writeln(jsonEncode({'type': 'stdout', 'text': 'ok'}));
        request.response.writeln(
          jsonEncode({'type': 'result', 'exitCode': 0, 'cwd': '/workspace'}),
        );
      } else if (request.method == 'DELETE') {
        request.response.statusCode = HttpStatus.noContent;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(switch (request.uri.path) {
            '/api/health' => {'ok': true},
            '/api/auth/login' => {'token': 'local-token', 'user': _user},
            '/api/users/me' => {'user': _user},
            '/api/terminal/exec' => {
              'stdout': 'ok',
              'stderr': '',
              'exitCode': 0,
            },
            _ => {'items': [], 'id': 'local-project', 'ok': true},
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    transport.close();
    await server.close(force: true);
    StudioProfile.current = previousProfile;
  });

  for (final profile in [
    _offline,
    const StudioProfile(
      id: 'explicit-offline-api-test',
      appTitle: 'Explicit offline',
      templates: [],
      offlineOnly: true,
    ),
  ]) {
    test('${profile.id} denies every request path before transport', () async {
      StudioProfile.current = profile;
      final client = ApiClient(transport: transport);
      final operations = <String, Future<dynamic> Function()>{
        'GET': client.zones,
        'POST': () => client.cloudCreateProject('token', 'Local'),
        'PATCH': () => client.updateMe('token', nickname: 'Local'),
        'PUT': () => client.cloudWriteFile('token', 'id', 'file.txt', 'aGk='),
        'DELETE': () => client.cloudDeleteProject('token', 'id'),
        'authentication': () => client.login('demo', 'password'),
        'SQL': () => client.sqlQuery('token', source: 'SELECT 1'),
        'terminal': () => client.terminalExec('token', 'pwd'),
        'terminal stream': () => client.terminalEvents('token', 'pwd').toList(),
      };
      for (final operation in operations.entries) {
        await expectLater(
          operation.value(),
          throwsA(_offlineError),
          reason: operation.key,
        );
      }
      expect(await client.health(), isFalse);
      expect(transport.sends, 0);
      expect(received, isEmpty);
    });
  }

  test(
    'a previously online client and unlistened stream recheck policy',
    () async {
      final client = ApiClient(transport: transport);
      expect(await client.health(), isTrue);
      expect(received, hasLength(1));
      final stream = client.terminalEvents('token', 'pwd');

      StudioProfile.current = _offline;
      await expectLater(client.zones(), throwsA(_offlineError));
      await expectLater(stream.toList(), throwsA(_offlineError));
      expect(await client.health(), isFalse);
      expect(transport.sends, 1);
      expect(received, hasLength(1));

      StudioProfile.current = null;
      expect(await client.zones(), isEmpty);
      expect(received, hasLength(2));
    },
  );

  test(
    'offline denial precedes body and uploaded-content serialization',
    () async {
      StudioProfile.current = _offline;
      final client = ApiClient(transport: transport);
      final params = _UnreadableList<String?>();
      final files = _UnreadableList<Map<String, String>>();
      await expectLater(
        client.sqlQuery('token', source: 'SELECT ?', params: params),
        throwsA(_offlineError),
      );
      await expectLater(
        client.terminalEvents('token', 'pwd', files: files).toList(),
        throwsA(_offlineError),
      );
      expect(params.reads, 0);
      expect(files.reads, 0);
      expect(transport.sends, 0);
      expect(received, isEmpty);
    },
  );

  test('offline denial does not initialize the default HTTP client', () async {
    StudioProfile.current = _offline;
    var creations = 0;
    await HttpOverrides.runZoned(
      () async {
        final client = ApiClient();
        await expectLater(client.zones(), throwsA(_offlineError));
        await expectLater(
          client.terminalEvents('token', 'pwd').toList(),
          throwsA(_offlineError),
        );
      },
      createHttpClient: (_) {
        creations++;
        throw StateError('Offline request initialized an HTTP client');
      },
    );
    expect(creations, 0);
    expect(received, isEmpty);
  });

  test(
    'each caller retry is denied without reaching the local sentinel',
    () async {
      final client = ApiClient(transport: transport);
      StudioProfile.current = _offline;
      for (var attempt = 0; attempt < 3; attempt++) {
        await expectLater(client.zones(), throwsA(_offlineError));
      }
      expect(transport.sends, 0);
      expect(received, isEmpty);
    },
  );

  for (final profile in [
    null,
    const StudioProfile(
      id: 'online-api-test',
      appTitle: 'Online',
      templates: [],
      isOffline: true,
      offlineOnly: false,
    ),
  ]) {
    test(
      '${profile?.id ?? 'main'} retains real online request behavior',
      () async {
        StudioProfile.current = profile;
        final client = ApiClient(transport: transport);
        final login = await client.login('demo', 'password');
        expect(login.token, 'local-token');
        expect(await client.zones(), isEmpty);
        expect(
          (await client.cloudCreateProject(login.token, 'Local'))['id'],
          'local-project',
        );
        await client.cloudWriteFile(login.token, 'id', 'a b.txt', 'aGk=');
        expect(
          (await client.updateMe(login.token, nickname: 'Local')).id,
          '12',
        );
        await client.cloudDeleteProject(login.token, 'id');
        expect((await client.terminalExec(login.token, 'pwd')).stdout, 'ok');
        final events = await client.terminalEvents(login.token, 'pwd').toList();
        expect(events.map((event) => event.type), [
          TerminalEventType.stdout,
          TerminalEventType.result,
        ]);
        expect(events.last.exitCode, 0);
        expect(received.map((request) => request.method), [
          'POST',
          'GET',
          'POST',
          'PUT',
          'PATCH',
          'DELETE',
          'POST',
          'POST',
        ]);
        expect(received.map((request) => request.uri.path), [
          '/api/auth/login',
          '/api/zones',
          '/api/cloud/projects',
          '/api/cloud/projects/id/file',
          '/api/users/me',
          '/api/cloud/projects/id',
          '/api/terminal/exec',
          '/api/terminal/exec/stream',
        ]);
        final upload = received.singleWhere(
          (request) => request.method == 'PUT',
        );
        expect(upload.authorization, 'Bearer local-token');
        expect(jsonDecode(upload.body), {'path': 'a b.txt', 'content': 'aGk='});
        expect(transport.originalUris.map((uri) => uri.origin).toSet(), {
          ApiConfig.origin,
        });
        expect(transport.sends, received.length);
      },
    );
  }
}

Matcher get _offlineError => isA<ApiException>()
    .having((error) => error.details['code'], 'policy code', 'OFFLINE_ONLY')
    .having((error) => error.statusCode, 'HTTP status', isNull)
    .having((error) => error.message, 'message', contains('离线'));

class _ReceivedRequest {
  _ReceivedRequest(this.method, this.uri, this.authorization, this.body);

  final String method;
  final Uri uri;
  final String? authorization;
  final String body;
}

/// Every real socket goes to this test's loopback server, never the API origin.
class _LoopbackTransport extends http.BaseClient {
  _LoopbackTransport(this.port)
    : _delegate = HttpOverrides.runWithHttpOverrides(
        () => IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
        _RealHttpOverrides(),
      );

  final int port;
  final http.Client _delegate;
  final originalUris = <Uri>[];
  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    originalUris.add(request.url);
    final uri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: request.url.path,
      query: request.url.hasQuery ? request.url.query : null,
    );
    final local = http.Request(request.method, uri)
      ..followRedirects = request.followRedirects
      ..headers.addAll(request.headers)
      ..bodyBytes = await request.finalize().toBytes();
    return _delegate.send(local);
  }

  @override
  void close() => _delegate.close();
}

// Bypass Flutter's fake HTTP override for this explicitly loopback-only fixture.
class _RealHttpOverrides extends HttpOverrides {}

class _UnreadableList<T> extends ListBase<T> {
  int reads = 0;

  @override
  int get length {
    reads++;
    throw StateError('Offline request inspected content');
  }

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  T operator [](int index) {
    reads++;
    throw StateError('Offline request inspected content');
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('read only');
}
