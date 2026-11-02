@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/services/account_erasure_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

/// Account erasure (整改任务书 §3-W3、§4 第 7 条).
///
/// The order matters more than the happy path: the local session must survive a
/// server failure, otherwise the user believes the account is gone while it is
/// still there and still logged in elsewhere.
void main() {
  late StudioProfile? previousProfile;
  late Directory root;
  late Directory storage;
  late HttpServer server;
  late List<String> received;
  late int respondWith;
  late Map<String, dynamic> respondBody;

  const user = CommunityUser(
    id: '42',
    username: 'demo',
    nickname: 'Demo',
    bio: '',
    avatarColor: '#2196F3',
    points: 0,
    checkinStreak: 0,
    provider: 'huawei',
  );

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
    root = await Directory.systemTemp.createTemp('qfli_erasure_');
    storage = Directory(p.join(root.path, 'storage'));
    await storage.create(recursive: true);
    received = [];
    respondWith = 200;
    respondBody = {'status': 'deactivated'};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add('${request.method} ${request.uri.path} $body');
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = respondWith;
      request.response.write(jsonEncode(respondBody));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (root.existsSync()) root.deleteSync(recursive: true);
    StudioProfile.current = previousProfile;
  });

  Future<AuthStore> signedInStore() async {
    final store = AuthStore(
      storageFile: File(p.join(storage.path, 'auth.json')),
    );
    await store.load();
    await store.signIn('token-1', user);
    return store;
  }

  AccountErasureService service() => AccountErasureService(
    client: ApiClient(transport: _Loopback(server.port)),
    storageResolverOverride: () async => storage.path,
  );

  test('sends the contract confirm word and clears the session', () async {
    final store = await signedInStore();
    expect(store.isLoggedIn, isTrue);

    final result = await service().erase(store);

    expect(result.succeeded, isTrue);
    expect(received, hasLength(1));
    expect(received.single, startsWith('POST /api/users/me/deactivate'));
    expect(received.single, contains('DEACTIVATE'));
    expect(store.isLoggedIn, isFalse);
    expect(store.token, isNull);
  });

  test('keeps the session when the server refuses', () async {
    final store = await signedInStore();
    respondWith = 409;
    respondBody = {'error': '账号状态冲突，请稍后重试', 'errorKey': 'conflict'};

    final result = await service().erase(store);

    expect(result.succeeded, isFalse);
    expect(result.outcome, AccountErasureOutcome.failed);
    expect(result.message, contains('冲突'));
    // The account still exists on the server: the local session must survive.
    expect(store.isLoggedIn, isTrue);
    expect(store.token, 'token-1');
  });

  test('never fakes success when the server is unreachable', () async {
    final store = await signedInStore();
    // Build the service while the port is still readable, then take the server
    // away: the request must fail the way an offline device would.
    final offline = AccountErasureService(
      client: ApiClient(transport: _DeadTransport(server.port)),
      storageResolverOverride: () async => storage.path,
    );
    await server.close(force: true);

    final result = await offline.erase(store);

    expect(result.succeeded, isFalse);
    expect(result.outcome, AccountErasureOutcome.failed);
    expect(store.isLoggedIn, isTrue);
    // Reopen for the shared tearDown close().
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  test('refuses to run without a session', () async {
    final store = AuthStore(storageFile: File(p.join(storage.path, 'a.json')));
    await store.load();
    final result = await service().erase(store);
    expect(result.succeeded, isFalse);
    expect(result.message, contains('登录'));
    expect(received, isEmpty);
  });

  test('deletes only the local session artefacts, not the projects', () async {
    final store = await signedInStore();
    final avatar = Directory(p.join(storage.path, 'avatars'));
    final projects = Directory(p.join(storage.path, 'projects', 'demo'));
    final audit = File(p.join(storage.path, 'local_audit.json'));
    for (final directory in [avatar, projects]) {
      await directory.create(recursive: true);
      await File(p.join(directory.path, 'x.txt')).writeAsString('x');
    }
    await audit.writeAsString('[]');

    final result = await service().erase(store);

    expect(result.succeeded, isTrue);
    expect(avatar.existsSync(), isFalse, reason: '头像缓存属于账号数据');
    expect(audit.existsSync(), isFalse, reason: '本地审计属于账号数据');
    expect(projects.existsSync(), isTrue, reason: '本地项目是用户自己的文件，不在注销授权范围内');
  });

  test('clearLocalData signs out without calling the server', () async {
    final store = await signedInStore();
    received.clear();
    await store.clearLocalData();
    expect(store.isLoggedIn, isFalse);
    expect(received, isEmpty);
  });

  test('local cleanup failure does not undo a server deletion', () async {
    final store = await signedInStore();
    await Directory(p.join(storage.path, 'avatars')).create(recursive: true);
    final failing = AccountErasureService(
      client: ApiClient(transport: _Loopback(server.port)),
      storageResolverOverride: () async => storage.path,
      directoryDeleterOverride: (_) async =>
          throw const FileSystemException('locked'),
    );

    final result = await failing.erase(store);

    expect(result.succeeded, isTrue);
    expect(store.isLoggedIn, isFalse);
  });
}

class _DeadTransport extends http.BaseClient {
  _DeadTransport(this.port);

  final int port;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('offline', request.url);
  }

  @override
  void close() {}
}

class _Loopback extends http.BaseClient {
  _Loopback(this.port) : _delegate = http.Client();

  final http.Client _delegate;
  final int port;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final local = http.Request(
      request.method,
      Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        path: request.url.path,
      ),
    )..headers.addAll(request.headers);
    local.bodyBytes = (request as http.Request).bodyBytes;
    return _delegate.send(local);
  }

  @override
  void close() => _delegate.close();
}
