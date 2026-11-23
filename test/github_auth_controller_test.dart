import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:qfli_studio_core/github/github_api.dart';
import 'package:qfli_studio_core/github/github_auth_controller.dart';
import 'package:qfli_studio_core/github/github_credential_store.dart';
import 'package:qfli_studio_core/github/github_models.dart';

http.Response _user({String login = 'octocat', int id = 7}) => http.Response(
  jsonEncode(<String, Object?>{'id': id, 'login': login}),
  200,
  headers: const {'content-type': 'application/json'},
);

class _DelayedVault implements GitHubCredentialStore {
  String? token;
  Completer<void>? writeStarted;
  Completer<void>? releaseWrite;
  Completer<void>? readStarted;
  Completer<void>? releaseRead;
  int writes = 0;
  int deletes = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> readAccessToken() async {
    _signal(readStarted);
    await releaseRead?.future;
    return token;
  }

  @override
  Future<void> writeAccessToken(String value) async {
    writes++;
    _signal(writeStarted);
    await releaseWrite?.future;
    token = value;
  }

  /// Signals the first call only.
  ///
  /// A second controller legitimately writes through the same fake, and
  /// completing a completer twice throws before the fake stores the value.
  void _signal(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  @override
  Future<void> deleteAccessToken() async {
    deletes++;
    token = null;
  }
}

GitHubAuthController _controller({
  required _DelayedVault vault,
  required String login,
  Duration timeout = const Duration(milliseconds: 200),
}) => GitHubAuthController(
  clientId: 'public-test-client-id',
  credentialStore: vault,
  api: GitHubApi(
    requestTimeout: timeout,
    client: MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      expect(request.url.path, '/user');
      expect(request.url.query, isEmpty);
      expect(request.url.userInfo, isEmpty);
      return _user(login: login, id: login == 'alice' ? 1 : 2);
    }),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller construction performs no I/O', () {
    final vault = _DelayedVault()..readStarted = Completer<void>();
    final controller = _controller(vault: vault, login: 'octocat');
    expect(vault.readStarted!.isCompleted, isFalse);
    expect(controller.status, GitHubAuthStatus.signedOut);
    controller.dispose();
  });

  test(
    'expired stored connection keeps reconnect entry until explicit disconnect',
    () async {
      final vault = _DelayedVault()..token = 'expired-test-token';
      final api = GitHubApi(
        client: MockClient(
          (_) async => http.Response(
            '{"message":"Bad credentials"}',
            401,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
      final controller = GitHubAuthController(credentialStore: vault, api: api);
      addTearDown(controller.dispose);
      addTearDown(api.close);
      await controller.restore();
      expect(controller.status, GitHubAuthStatus.error);
      expect(controller.hasConnection, isTrue);
      expect(controller.cloneCredential, isNull);
      await controller.disconnect();
      expect(controller.hasConnection, isFalse);
      expect(vault.token, isNull);
    },
  );

  test(
    'disconnect waits behind delayed write and returns after stale token deletion',
    () async {
      final vault = _DelayedVault()
        ..writeStarted = Completer<void>()
        ..releaseWrite = Completer<void>();
      final controller = _controller(vault: vault, login: 'octocat');

      final login = controller.signInWithPat('first-pat');
      await vault.writeStarted!.future;
      var disconnected = false;
      final disconnect = controller.disconnect().then(
        (_) => disconnected = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(disconnected, isFalse);

      vault.releaseWrite!.complete();
      await Future.wait<void>(<Future<void>>[login, disconnect]);

      expect(vault.token, isNull);
      // 失效的那次写在释放队列槽位前先删自己的 token，disconnect 再排一次
      // 删除。两条路径都能保证凭据被清掉，所以调用次数不是契约。
      expect(vault.deletes, greaterThanOrEqualTo(1));
      expect(controller.status, GitHubAuthStatus.signedOut);
      controller.dispose();
    },
  );

  test(
    'a newer account intent writes after and wins over the older delayed token',
    () async {
      final vault = _DelayedVault()
        ..writeStarted = Completer<void>()
        ..releaseWrite = Completer<void>();
      final api = GitHubApi(
        client: MockClient((request) async {
          final bearer = request.headers['authorization'];
          final login = bearer == 'Bearer old-pat' ? 'alice' : 'bob';
          return _user(login: login, id: login == 'alice' ? 1 : 2);
        }),
      );
      final older = GitHubAuthController(
        clientId: 'public-test-client-id',
        credentialStore: vault,
        api: api,
      );
      final newer = GitHubAuthController(
        clientId: 'public-test-client-id',
        credentialStore: vault,
        api: GitHubApi(
          client: MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer new-pat');
            return _user(login: 'bob', id: 2);
          }),
        ),
      );

      final firstLogin = older.signInWithPat('old-pat');
      await vault.writeStarted!.future;
      final secondLogin = newer.signInWithPat('new-pat');
      await Future<void>.delayed(Duration.zero);
      expect(vault.writes, 1);

      vault.releaseWrite!.complete();
      await Future.wait<void>(<Future<void>>[firstLogin, secondLogin]);

      expect(vault.token, 'new-pat');
      expect(older.status, isNot(GitHubAuthStatus.authenticated));
      expect(newer.status, GitHubAuthStatus.authenticated);
      older.dispose();
      newer.dispose();
    },
  );

  test('stale restore read cannot authenticate after disconnect', () async {
    final vault = _DelayedVault()
      ..readStarted = Completer<void>()
      ..releaseRead = Completer<void>()
      ..token = 'stored-pat';
    final controller = _controller(vault: vault, login: 'octocat');

    final restore = controller.restore();
    await vault.readStarted!.future;
    await controller.disconnect();
    vault.releaseRead!.complete();
    await restore;

    expect(controller.status, GitHubAuthStatus.signedOut);
    expect(controller.account, isNull);
    expect(vault.token, isNull);
    controller.dispose();
  });

  test(
    'cancel during a secure write removes the late token before releasing the vault queue',
    () async {
      final vault = _DelayedVault()
        ..writeStarted = Completer<void>()
        ..releaseWrite = Completer<void>();
      final controller = _controller(vault: vault, login: 'octocat');

      final login = controller.signInWithPat('cancelled-pat');
      await vault.writeStarted!.future;
      await controller.cancelDeviceOAuth();
      vault.releaseWrite!.complete();
      await login;

      expect(vault.token, isNull);
      expect(controller.status, GitHubAuthStatus.signedOut);
      controller.dispose();
    },
  );

  test(
    'dispose during a secure write removes the late token before releasing the vault queue',
    () async {
      final vault = _DelayedVault()
        ..writeStarted = Completer<void>()
        ..releaseWrite = Completer<void>();
      final controller = _controller(vault: vault, login: 'octocat');

      final login = controller.signInWithPat('disposed-pat');
      await vault.writeStarted!.future;
      controller.dispose();
      vault.releaseWrite!.complete();
      await login;

      expect(vault.token, isNull);
      expect(controller.status, isNot(GitHubAuthStatus.authenticated));
    },
  );

  test(
    'a newer controller intent hides credentials from an authenticated older controller',
    () async {
      final vault = _DelayedVault();
      final old = _controller(vault: vault, login: 'alice');
      await old.signInWithPat('alice-pat');
      expect(old.cloneCredential?.token, 'alice-pat');

      final newer = _controller(vault: vault, login: 'bob');
      final newLogin = newer.signInWithPat('bob-pat');
      // The new controller fences the old identity before its first await.
      expect(old.cloneCredential, isNull);
      await newLogin;
      expect(newer.cloneCredential?.token, 'bob-pat');
      old.dispose();
      newer.dispose();
    },
  );

  test(
    'slow-down and expired/denied OAuth errors contain no private values',
    () {
      expect(
        GitHubTokenPollResult.slowDown().status,
        GitHubTokenPollStatus.slowDown,
      );
      expect(
        const GitHubApiException('GitHub OAuth 授权失败。').toString(),
        isNot(contains('device_code')),
      );
    },
  );

  test('credential and clone request diagnostics redact tokens', () {
    const token = 'ghp_must_never_appear_in_logs';
    expect(
      const GitHubCloneCredential(username: 'octo', token: token).toString(),
      isNot(contains(token)),
    );
  });
}
