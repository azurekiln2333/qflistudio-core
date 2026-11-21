import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../community/models.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';
import '../services/app_paths.dart';

/// 登录状态与个人资料的持久化（auth.json）。
class AuthStore extends ChangeNotifier {
  AuthStore({File? storageFile, ApiClient? api})
    : _storageOverride = storageFile,
      _api = api ?? ApiClient.instance;

  final ApiClient _api;

  final File? _storageOverride;
  File? _storage;
  Future<void>? _writes;

  String? _token;
  CommunityUser? _user;
  int _sessionGeneration = 0;

  /// Advances before any session-adoption or sign-out await. Profile and points
  /// updates intentionally do not change this identity revision.
  int get sessionGeneration => _sessionGeneration;

  bool get isLoggedIn => _token != null && _user != null;
  String? get token => _token;
  CommunityUser? get user => _user;

  Future<void> load() async {
    final generation = ++_sessionGeneration;
    try {
      final storage = _storageOverride ?? await _resolveStorage();
      if (_sessionGeneration != generation) return;
      _storage = storage;
      final exists = await storage.exists();
      if (_sessionGeneration != generation) return;
      if (exists) {
        final text = await storage.readAsString();
        if (_sessionGeneration != generation) return;
        final data = jsonDecode(text) as Map<String, dynamic>;
        final source = data['serviceOrigin'] ?? data['serverUrl'];
        final trusted = source is String && ApiConfig.ownsSession(source);
        _token = trusted ? data['token'] as String? : null;
        _user = null;
        if (trusted && data['user'] is Map) {
          _user = CommunityUser.fromJson(
            Map<String, dynamic>.from(data['user'] as Map),
          );
        }
        // 移除旧服务器配置；不同来源的登录信息不会发送给官方服务。
        if (data.containsKey('serverUrl') || !trusted) await _persist();
      }
    } catch (_) {
      if (_sessionGeneration != generation) return;
      // 配置损坏时按未登录处理。
      _token = null;
      _user = null;
    }
    if (_sessionGeneration == generation) notifyListeners();
  }

  Future<File> _resolveStorage() async {
    final base = await AppPaths.storageDirectory();
    if (base == null) throw const FileSystemException('未找到可写目录');
    return File(p.join(base, 'auth.json'));
  }

  Future<void> _persist() {
    final file = _storage;
    if (file == null) return Future.value();
    final generation = _sessionGeneration;
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'serviceOrigin': ApiConfig.origin,
      if (_token != null) 'token': _token,
      if (_user != null)
        'user': {
          'id': _user!.id,
          'gatewayUserId': ?_user!.gatewayUserId,
          'username': _user!.username,
          'nickname': _user!.nickname,
          'bio': _user!.bio,
          'avatarColor': _user!.avatarColor,
          'avatarUrl': _user!.avatarUrl,
          'points': _user!.points,
          'checkinStreak': _user!.checkinStreak,
          'growth': _user!.growth.toJson(),
          'provider': _user!.provider,
          'isAdmin': _user!.isAdmin,
        },
    });
    Future<void> write() async {
      if (_sessionGeneration != generation) return;
      await file.parent.create(recursive: true);
      if (_sessionGeneration != generation) return;
      // No await between the final session fence and the credential write.
      file.writeAsStringSync(encoded, flush: true);
    }

    final previous = _writes;
    return _writes = previous == null
        ? write()
        : previous.catchError((Object _) {}).then((_) => write());
  }

  Future<void> signIn(String token, CommunityUser user) async {
    ++_sessionGeneration;
    _token = token;
    _user = user;
    await _persist();
    notifyListeners();
  }

  /// 手动下拉刷新资料；头像由独立 URL 缓存管理。
  Future<void> refreshMe() async {
    final token = _token;
    final generation = _sessionGeneration;
    final client = _api;
    if (token == null) return;
    try {
      final fresh = await client.me(token);
      if (_token != token || _sessionGeneration != generation) return;
      _user = fresh;
      await _persist();
      if (_sessionGeneration == generation) notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401 &&
          _token == token &&
          _sessionGeneration == generation) {
        await signOut();
      }
    }
  }

  Future<void> updateProfile({String? nickname, String? bio}) async {
    final token = _token;
    final generation = _sessionGeneration;
    final client = _api;
    if (token == null) return;
    final fresh = await client.updateMe(token, nickname: nickname, bio: bio);
    if (_token != token || _sessionGeneration != generation) return;
    _user = fresh;
    await _persist();
    if (_sessionGeneration == generation) notifyListeners();
  }

  Future<void> updatePoints({
    int? points,
    int? streak,
    UserGrowth? growth,
  }) async {
    if (_user == null) return;
    _user = CommunityUser(
      id: _user!.id,
      gatewayUserId: _user!.gatewayUserId,
      username: _user!.username,
      nickname: _user!.nickname,
      bio: _user!.bio,
      avatarColor: _user!.avatarColor,
      avatarUrl: _user!.avatarUrl,
      points: points ?? _user!.points,
      checkinStreak: streak ?? _user!.checkinStreak,
      provider: _user!.provider,
      isAdmin: _user!.isAdmin,
      growth: growth ?? _user!.growth,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> signOut() async {
    ++_sessionGeneration;
    final token = _token;
    _token = null;
    _user = null;
    await _persist();
    notifyListeners();
    if (token != null) unawaited(_revokeSession(token));
  }

  /// 清空本地登录态，**不**联系服务端。
  ///
  /// 用于两条路径：注销成功（服务端已吊销全部会话）和撤回隐私政策同意。
  /// 两条都不该再调 `/api/auth/logout`：前者令牌已失效，后者要在停止处理
  /// 个人信息的前提下结束登录。
  Future<void> clearLocalData() async {
    ++_sessionGeneration;
    _token = null;
    _user = null;
    await _persist();
    notifyListeners();
  }

  Future<void> _revokeSession(String token) async {
    try {
      await _api.logout(token);
    } on ApiException {
      // Local sign-out still completes when the server cannot be reached.
    }
  }
}
