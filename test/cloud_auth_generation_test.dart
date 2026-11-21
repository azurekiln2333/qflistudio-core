// Static-validated regression sources. Runtime execution belongs to cloud CI.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _ProfileApi api;
  late AuthStore auth;
  const sameUser = CommunityUser(
    id: 'user_a',
    username: 'a',
    nickname: 'a',
    bio: '',
    avatarColor: '#000000',
    points: 0,
    checkinStreak: 0,
    provider: 'test',
  );
  const otherUser = CommunityUser(
    id: 'user_b',
    username: 'b',
    nickname: 'b',
    bio: '',
    avatarColor: '#000000',
    points: 0,
    checkinStreak: 0,
    provider: 'test',
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-auth-generation-');
    api = _ProfileApi();
    auth = AuthStore(
      storageFile: File(p.join(root.path, 'auth.json')),
      api: api,
    );
    await auth.load();
    await auth.signIn('same-token', sameUser);
  });
  tearDown(() async {
    auth.dispose();
    await root.delete(recursive: true);
  });

  test(
    'session mutations advance synchronously, profiles and points do not',
    () async {
      final initial = auth.sessionGeneration;
      final signIn = auth.signIn('same-token', sameUser);
      expect(auth.sessionGeneration, initial + 1);
      await signIn;
      final points = auth.updatePoints(points: 2);
      expect(auth.sessionGeneration, initial + 1);
      await points;
      final clear = auth.clearLocalData();
      expect(auth.sessionGeneration, initial + 2);
      await clear;
      final load = auth.load();
      expect(auth.sessionGeneration, initial + 3);
      await load;
      final signOut = auth.signOut();
      expect(auth.sessionGeneration, initial + 4);
      await signOut;
    },
  );

  for (final update in [false, true]) {
    test(
      'stale ${update ? 'updateProfile' : 'refreshMe'} cannot beat same-token A-B-A',
      () async {
        final pending = update
            ? auth.updateProfile(nickname: 'pending')
            : auth.refreshMe();
        await api.started.future;
        final generation = auth.sessionGeneration;
        // Reuse the exact token AND exact user instance. Only a revision can see it.
        final b = auth.signIn('other-token', otherUser);
        final a = auth.signIn('same-token', sameUser);
        expect(auth.sessionGeneration, generation + 2);
        api.response.complete(otherUser);
        await pending;
        await Future.wait([b, a]);
        expect(auth.user, same(sameUser));
        expect(auth.token, 'same-token');
      },
    );
  }

  test('stale 401 cannot sign out a later same-token login', () async {
    final pending = auth.refreshMe();
    await api.started.future;
    final b = auth.signIn('other-token', otherUser);
    final a = auth.signIn('same-token', sameUser);
    api.response.completeError(ApiException('expired', statusCode: 401));
    await pending;
    await Future.wait([b, a]);
    expect(auth.token, 'same-token');
    expect(auth.user, same(sameUser));
  });

  test('delayed registry load cannot overwrite an adopted login', () async {
    final loading = auth.load();
    final signing = auth.signIn('new-token', otherUser);
    await Future.wait([loading, signing]);
    expect(auth.token, 'new-token');
    expect(auth.user, same(otherUser));
  });
}

class _ProfileApi extends ApiClient {
  final started = Completer<void>();
  final response = Completer<CommunityUser>();
  Future<CommunityUser> _wait() {
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  Future<CommunityUser> me(String token) => _wait();
  @override
  Future<CommunityUser> updateMe(
    String token, {
    String? nickname,
    String? bio,
    String? avatarColor,
  }) => _wait();
  @override
  Future<void> logout(String token) async {}
  @override
  Future<Map<String, dynamic>> cloudFileTree(String token, String id) async => {
    'files': [
      {'path': 'file', 'mtime': 1.0},
    ],
  };
  @override
  Future<Map<String, dynamic>> cloudReadFile(
    String token,
    String id,
    String path,
  ) async => {
    'content': base64Encode([1, 2, 3]),
  };
}
