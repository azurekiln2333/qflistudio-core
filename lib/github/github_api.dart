import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'github_models.dart';

/// Minimal HTTP boundary for OAuth and GitHub REST.
///
/// Injectable to make controller regressions hermetic in cloud CI. Requests are
/// always sent to fixed GitHub origins; pagination `next` links are validated
/// before following them.
class GitHubApi {
  GitHubApi({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Duration requestTimeout;

  static final Uri apiOrigin = Uri.https('api.github.com', '/');
  static final Uri webOrigin = Uri.https('github.com', '/');
  static const String _apiVersion = '2022-11-28';
  static const String _userAgent = 'QFLIStudio';

  final http.Client _client;
  bool _closed = false;

  Future<GitHubDeviceCode> requestDeviceCode(String clientId) async {
    final response = await _postForm(
      webOrigin.replace(path: '/login/device/code'),
      <String, String>{'client_id': clientId, 'scope': 'repo'},
      oauth: true,
    );
    final body = _decodeObject(response);
    final deviceCode = _requiredString(body, 'device_code');
    final userCode = _requiredString(body, 'user_code');
    final verification = Uri.tryParse(
      _requiredString(body, 'verification_uri'),
    );
    final expiresIn = _positiveInt(body['expires_in'], fallback: 900);
    final interval = _positiveInt(body['interval'], fallback: 5);
    if (verification == null ||
        verification.scheme != 'https' ||
        verification.host != 'github.com' ||
        verification.path != '/login/device') {
      throw const GitHubApiException('GitHub 返回了无效的验证地址。');
    }
    return GitHubDeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verification,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      pollingInterval: Duration(seconds: interval),
    );
  }

  Future<GitHubTokenPollResult> pollDeviceToken({
    required String clientId,
    required String deviceCode,
  }) async {
    final response = await _postForm(
      webOrigin.replace(path: '/login/oauth/access_token'),
      <String, String>{
        'client_id': clientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
      oauth: true,
      allowErrorStatus: true,
    );
    final body = _decodeObject(response, allowOAuthError: true);
    final token = body['access_token'];
    if (token is String && token.isNotEmpty) {
      return GitHubTokenPollResult.authorized(token);
    }
    final error = body['error'];
    return switch (error) {
      'authorization_pending' => const GitHubTokenPollResult.pending(),
      'slow_down' => const GitHubTokenPollResult.slowDown(),
      'access_denied' => const GitHubTokenPollResult.denied(),
      'expired_token' => const GitHubTokenPollResult.expired(),
      _ => GitHubTokenPollResult.failed(_safeOAuthError(error)),
    };
  }

  Future<GitHubAccount> getAuthenticatedUser(String token) async {
    final response = await _get(apiOrigin.replace(path: '/user'), token);
    final body = _decodeObject(response);
    final id = body['id'];
    final login = body['login'];
    if (id is! num || login is! String || login.trim().isEmpty) {
      throw const GitHubApiException('GitHub 用户资料格式无效。');
    }
    return GitHubAccount(
      id: id.toInt(),
      login: login,
      name: body['name'] is String ? body['name'] as String : null,
      avatarUrl: body['avatar_url'] is String
          ? body['avatar_url'] as String
          : null,
    );
  }

  Future<GitHubRepositoryPage> listRepositories({
    required String token,
    Uri? pageUri,
    int page = 1,
  }) async {
    final uri =
        pageUri ??
        apiOrigin.replace(
          path: '/user/repos',
          queryParameters: <String, String>{
            'visibility': 'all',
            'affiliation': 'owner,collaborator,organization_member',
            'per_page': '100',
            'page': '$page',
            'sort': 'full_name',
            'direction': 'asc',
          },
        );
    _validateRepositoryPageUri(uri);
    final response = await _get(uri, token);
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const GitHubApiException('GitHub 仓库列表格式无效。');
    }
    if (decoded is! List) {
      throw const GitHubApiException('GitHub 仓库列表格式无效。');
    }
    final repositories = <GitHubRepository>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) repositories.add(_repository(item));
    }
    return GitHubRepositoryPage(
      repositories: repositories,
      nextPageUri: _nextLink(response.headers['link']),
    );
  }

  Future<http.Response> _get(Uri uri, String token) {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(_headers(token: token));
    return _send(request, abort: abort);
  }

  Future<http.Response> _postForm(
    Uri uri,
    Map<String, String> fields, {
    bool oauth = false,
    bool allowErrorStatus = false,
  }) {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(_headers(oauth: oauth));
    request.bodyFields = fields;
    return _send(request, abort: abort, allowErrorStatus: allowErrorStatus);
  }

  Map<String, String> _headers({String? token, bool oauth = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'User-Agent': _userAgent,
        if (!oauth) 'X-GitHub-Api-Version': _apiVersion,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _send(
    http.AbortableRequest request, {
    required Completer<void> abort,
    bool allowErrorStatus = false,
  }) async {
    if (_closed) throw const GitHubApiException('GitHub API 客户端已关闭。');
    final timer = Timer(requestTimeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final streamed = await _client.send(request).timeout(requestTimeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(requestTimeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        // Never follow redirects on an authenticated request. In particular,
        // credentials must not be forwarded to a different host.
        throw const GitHubApiException('GitHub 返回了重定向，已停止认证请求。');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (allowErrorStatus && response.statusCode == 400) return response;
        throw _statusException(response.statusCode);
      }
      return response;
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const GitHubApiException('GitHub 请求超时，请检查网络后重试。');
    } on GitHubApiException {
      rethrow;
    } on Object {
      throw const GitHubApiException('无法连接 GitHub，请检查网络后重试。');
    } finally {
      timer.cancel();
    }
  }

  Map<String, dynamic> _decodeObject(
    http.Response response, {
    bool allowOAuthError = false,
  }) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // A malformed response is turned into a sanitized API error below.
    }
    if (allowOAuthError && response.statusCode == 400) {
      throw const GitHubApiException('GitHub OAuth 响应格式无效。');
    }
    throw const GitHubApiException('GitHub 返回了无效响应。');
  }

  GitHubRepository _repository(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final fullName = json['full_name'];
    final owner = json['owner'];
    final ownerLogin = owner is Map ? owner['login'] : null;
    final cloneUrl = json['clone_url'];
    final htmlUrl = json['html_url'];
    if (id is! num ||
        name is! String ||
        fullName is! String ||
        ownerLogin is! String ||
        cloneUrl is! String ||
        htmlUrl is! String) {
      throw const GitHubApiException('GitHub 仓库条目格式无效。');
    }
    final safeClone = _cleanCloneUrl(cloneUrl);
    final safeHtml = _cleanHtmlUrl(htmlUrl);
    return GitHubRepository(
      id: id.toInt(),
      name: name,
      fullName: fullName,
      ownerLogin: ownerLogin,
      isPrivate: json['private'] == true,
      htmlUrl: safeHtml,
      cloneUrl: safeClone,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      defaultBranch: json['default_branch'] is String
          ? json['default_branch'] as String
          : null,
      archived: json['archived'] == true,
    );
  }

  String _cleanCloneUrl(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(
          r'^/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$',
        ).hasMatch(uri.path)) {
      throw const GitHubApiException('GitHub 返回了无效的克隆地址。');
    }
    return uri.replace(userInfo: '', query: null, fragment: null).toString();
  }

  String _cleanHtmlUrl(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const GitHubApiException('GitHub 返回了无效的仓库地址。');
    }
    return uri.toString();
  }

  void _validateRepositoryPageUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'api.github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.path != '/user/repos' ||
        uri.hasFragment) {
      throw const GitHubApiException('GitHub 分页地址无效，已停止请求。');
    }
  }

  Uri? _nextLink(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    for (final part in header.split(',')) {
      final match = RegExp(
        r'<([^>]+)>\s*;\s*rel="([^"]+)"',
      ).firstMatch(part.trim());
      if (match == null || match.group(2) != 'next') continue;
      final uri = Uri.tryParse(match.group(1)!);
      if (uri == null) return null;
      _validateRepositoryPageUri(uri);
      return uri;
    }
    return null;
  }

  GitHubApiException _statusException(int status) => switch (status) {
    401 => const GitHubApiException('GitHub 凭据无效或已撤销，请重新登录。'),
    403 => const GitHubApiException('GitHub 拒绝了请求；请检查授权范围或稍后重试。'),
    404 => const GitHubApiException('GitHub API 未找到请求的资源。'),
    429 => const GitHubApiException('GitHub 请求过于频繁，请稍后重试。'),
    >= 500 => const GitHubApiException('GitHub 服务暂时不可用，请稍后重试。'),
    _ => const GitHubApiException('GitHub 请求失败，请稍后重试。'),
  };

  String _safeOAuthError(Object? error) => switch (error) {
    'device_flow_disabled' => 'GitHub OAuth 应用尚未启用 Device Flow。',
    'unsupported_grant_type' => 'GitHub 未启用 OAuth Device Flow。',
    'incorrect_client_credentials' => 'GitHub OAuth 应用配置无效。',
    _ => 'GitHub OAuth 授权失败。',
  };

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw const GitHubApiException('GitHub OAuth 响应缺少必要字段。');
    }
    return value;
  }

  int _positiveInt(Object? value, {required int fallback}) =>
      value is num && value > 0 ? value.toInt() : fallback;

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

@immutable
class GitHubDeviceCode {
  const GitHubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.pollingInterval,
  });

  /// Private to the API/controller. Never exposed by the public view model.
  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration pollingInterval;
}

enum GitHubTokenPollStatus {
  authorized,
  pending,
  slowDown,
  denied,
  expired,
  failed,
}

@immutable
class GitHubTokenPollResult {
  const GitHubTokenPollResult._(this.status, {this.token, this.message});

  const GitHubTokenPollResult.authorized(String token)
    : this._(GitHubTokenPollStatus.authorized, token: token);

  const GitHubTokenPollResult.pending() : this._(GitHubTokenPollStatus.pending);

  const GitHubTokenPollResult.slowDown()
    : this._(GitHubTokenPollStatus.slowDown);

  const GitHubTokenPollResult.denied() : this._(GitHubTokenPollStatus.denied);

  const GitHubTokenPollResult.expired() : this._(GitHubTokenPollStatus.expired);

  const GitHubTokenPollResult.failed(String message)
    : this._(GitHubTokenPollStatus.failed, message: message);

  final GitHubTokenPollStatus status;
  final String? token;
  final String? message;
}

@immutable
class GitHubRepositoryPage {
  const GitHubRepositoryPage({required this.repositories, this.nextPageUri});

  final List<GitHubRepository> repositories;
  final Uri? nextPageUri;
}

class GitHubApiException implements Exception {
  const GitHubApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
