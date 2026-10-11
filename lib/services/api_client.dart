import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../community/models.dart';
import '../config/api_config.dart';

/// API 调用异常：message 为用户可读文案。
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details = const {}});

  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;

  @override
  String toString() => message;
}

class HuaweiLoginResult {
  const HuaweiLoginResult.signedIn(this.token, this.user)
      : bindingId = null,
        phoneAvailable = false;

  const HuaweiLoginResult.binding(this.bindingId, this.phoneAvailable)
      : token = null,
        user = null;

  final String? token;
  final CommunityUser? user;
  final String? bindingId;
  final bool phoneAvailable;
}

enum TerminalEventType { progress, stdout, stderr, result }

class TerminalEvent {
  const TerminalEvent(
    this.type, {
    this.stage,
    this.position,
    this.text,
    this.exitCode,
  });

  final TerminalEventType type;
  final String? stage;
  final int? position;
  final String? text;
  final int? exitCode;

  static TerminalEvent decode(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw ApiException('终端响应格式无效');
    }
    switch (value['type']) {
      case 'progress':
        final stage = value['stage'];
        final position = value['position'];
        if (stage is! String ||
            !const {
              'queued',
              'initializing',
              'ready',
              'uploading',
              'running',
              'cleaning',
            }.contains(stage) ||
            (position != null &&
                (position is! int || position < 1 || position > 8))) {
          throw ApiException('终端进度响应无效');
        }
        return TerminalEvent(
          TerminalEventType.progress,
          stage: stage,
          position: position as int?,
        );
      case 'stdout':
      case 'stderr':
        final text = value['text'];
        if (text is! String) throw ApiException('终端输出响应无效');
        return TerminalEvent(
          value['type'] == 'stdout'
              ? TerminalEventType.stdout
              : TerminalEventType.stderr,
          text: text,
        );
      case 'result':
        final code = value['exitCode'];
        if (code is! int ||
            code < 0 ||
            code > 255 ||
            value['cwd'] != '/workspace') {
          throw ApiException('终端结果响应无效');
        }
        return TerminalEvent(TerminalEventType.result, exitCode: code);
      case 'error':
        final message = value['message'];
        throw ApiException(
          message is String ? message : '在线终端执行失败',
          statusCode: value['status'] is int ? value['status'] as int : null,
        );
      default:
        throw ApiException('未知的终端响应');
    }
  }
}

/// azurekiln-qfli-server 的 HTTP 客户端。
class ApiClient {
  ApiClient({http.Client? transport}) : _transport = transport;

  final http.Client? _transport;
  // 延迟创建并复用连接，不在应用首帧初始化网络。
  late final http.Client _http = _transport ?? http.Client();

  static final ApiClient instance = ApiClient();

  void close() => _http.close();

  Map<String, String> _headers({String? token}) => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, Object>? query,
    String? token,
    Duration? timeout,
  }) async {
    final uri = ApiConfig.endpoint(path, query);
    try {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll(_headers(token: token));
      if (body != null) request.body = jsonEncode(body);
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? ApiConfig.requestTimeout);
      final text = utf8.decode(response.bodyBytes);
      dynamic data;
      try {
        data = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        data = text;
      }
      if (response.statusCode >= 300) {
        var message = data is Map && data['error'] is String
            ? data['error'] as String
            : '服务暂时不可用（${response.statusCode}），请稍后重试';
        final requestId = data is Map ? data['requestId'] : null;
        if (response.statusCode >= 500 && requestId is String) {
          message = '$message\n请求编号：$requestId';
        }
        throw ApiException(
          message,
          statusCode: response.statusCode,
          details: data is Map ? Map<String, dynamic>.from(data) : const {},
        );
      }
      if (data != null && data is! Map && data is! List) {
        throw ApiException('服务响应异常，请稍后重试');
      }
      return data;
    } on SocketException catch (e) {
      throw ApiException('无法连接服务器：${e.message}');
    } on TimeoutException {
      throw ApiException('连接超时，请检查网络后重试');
    } on http.ClientException {
      throw ApiException('暂时无法连接服务，请检查网络后重试');
    } on HandshakeException {
      throw ApiException('无法建立安全连接，请检查设备时间或稍后重试');
    } on FormatException {
      throw ApiException('服务响应异常，请稍后重试');
    } on HttpException catch (e) {
      throw ApiException('网络错误：${e.message}');
    }
  }

  // ---- 认证 ----

  Future<String?> register({
    required String username,
    required String email,
    required String password,
    required String emailCode,
    String? nickname,
    String? captchaId,
    String? captchaCode,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/auth/register',
              body: {
                'username': username,
                'email': email,
                'password': password,
                'emailCode': emailCode,
                'captchaId': ?captchaId,
                'captchaCode': ?captchaCode,
                if (nickname != null && nickname.isNotEmpty)
                  'nickname': nickname,
              },
            )
            as Map<String, dynamic>;
    return data['message'] is String ? data['message'] as String : null;
  }

  Future<({String token, CommunityUser user})> login(
    String username,
    String password, {
    String? emailCode,
    String? totpCode,
    String? captchaId,
    String? captchaCode,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/auth/login',
              body: {
                'username': username,
                'password': password,
                'emailCode': ?emailCode,
                'totpCode': ?totpCode,
                'captchaId': ?captchaId,
                'captchaCode': ?captchaCode,
              },
            )
            as Map<String, dynamic>;
    return (
      token: data['token'] as String,
      user: CommunityUser.fromJson(data['user']),
    );
  }

  Future<({String? factor, bool captchaRequired, String? emailMasked})>
  loginRequirements(String username, String password) async {
    final data =
        await _send(
              'POST',
              '/api/auth/login/requirements',
              body: {'username': username, 'password': password},
            )
            as Map<String, dynamic>;
    return (
      factor: data['factor'] as String?,
      captchaRequired: data['captchaRequired'] == true,
      emailMasked: data['emailMasked'] as String?,
    );
  }

  /// OAuth2 网关授权页地址；未配置网关时抛 ApiException（501）。
  Future<String> oauth2Url() async {
    final data =
        await _send('GET', '/api/auth/oauth2/url') as Map<String, dynamic>;
    return data['url'] as String;
  }

  Future<({String token, CommunityUser user})> oauth2Complete(
    String code,
  ) async {
    final data =
        await _send('POST', '/api/auth/oauth2/complete', body: {'code': code})
            as Map<String, dynamic>;
    return (
      token: data['token'] as String,
      user: CommunityUser.fromJson(data['user']),
    );
  }

  Future<HuaweiLoginResult> huaweiLogin(
    String authorizationCode,
  ) async {
    final data =
        await _send(
              'POST',
              '/api/auth/huawei',
              body: {'authorizationCode': authorizationCode},
            )
            as Map<String, dynamic>;
    if (data['bindingRequired'] == true) {
      final bindingId = data['bindingId'];
      if (bindingId is! String || bindingId.isEmpty) {
        throw ApiException('华为绑定响应无效，请重新发起登录');
      }
      return HuaweiLoginResult.binding(bindingId, data['phoneAvailable'] == true);
    }
    return HuaweiLoginResult.signedIn(
      data['token'] as String,
      CommunityUser.fromJson(data['user']),
    );
  }

  Future<({String token, CommunityUser user})> skipHuaweiBinding(String bindingId) async {
    final data = await _send('POST', '/api/auth/huawei/skip', body: {'bindingId': bindingId}) as Map<String, dynamic>;
    return (token: data['token'] as String, user: CommunityUser.fromJson(data['user']));
  }

  Future<({String token, CommunityUser user})> bindHuaweiAccount(
    String bindingId, String username, String password, {
    String? emailCode, String? totpCode, String? captchaId, String? captchaCode,
  }) async {
    final data = await _send('POST', '/api/auth/huawei/bind', body: {
      'bindingId': bindingId, 'username': username, 'password': password,
      'emailCode': ?emailCode,
      'totpCode': ?totpCode,
      'captchaId': ?captchaId,
      'captchaCode': ?captchaCode,
    }) as Map<String, dynamic>;
    return (token: data['token'] as String, user: CommunityUser.fromJson(data['user']));
  }

  // ---- 用户 ----

  Future<String> sendRegistrationCode(String email) async {
    final data =
        await _send('POST', '/api/auth/email-code', body: {'email': email})
            as Map<String, dynamic>;
    return data['message'] as String? ?? '验证码已发送';
  }

  Future<({String id, String image})> captcha() async {
    final data =
        await _send('GET', '/api/auth/captcha') as Map<String, dynamic>;
    return (id: data['id'] as String, image: data['image'] as String);
  }

  Future<({String token, CommunityUser user})> completeHuaweiLogin(
    String challengeId,
    String code,
  ) async {
    final data =
        await _send(
              'POST',
              '/api/auth/huawei/complete',
              body: {'challengeId': challengeId, 'code': code},
            )
            as Map<String, dynamic>;
    return (
      token: data['token'] as String,
      user: CommunityUser.fromJson(data['user']),
    );
  }

  Future<void> logout(String token) async {
    await _send('POST', '/api/auth/logout', token: token);
  }

  Future<CommunityUser> me(String token) async {
    final data =
        await _send('GET', '/api/users/me', token: token)
            as Map<String, dynamic>;
    return CommunityUser.fromJson(data['user']);
  }

  Future<CommunityUser> updateMe(
    String token, {
    String? nickname,
    String? bio,
    String? avatarColor,
  }) async {
    final data =
        await _send(
              'PATCH',
              '/api/users/me',
              token: token,
              body: {
                'nickname': ?nickname,
                'bio': ?bio,
                'avatarColor': ?avatarColor,
              },
            )
            as Map<String, dynamic>;
    return CommunityUser.fromJson(data['user']);
  }

  /// 我的信息 + 社区统计（发帖/评论/点赞数）。
  Future<({CommunityUser user, int posts, int comments, int likes})>
  meWithStats(String token) async {
    final data =
        await _send('GET', '/api/users/me', token: token)
            as Map<String, dynamic>;
    final stats = (data['stats'] ?? {}) as Map<String, dynamic>;
    return (
      user: CommunityUser.fromJson(data['user'] as Map<String, dynamic>),
      posts: (stats['posts'] as num?)?.toInt() ?? 0,
      comments: (stats['comments'] as num?)?.toInt() ?? 0,
      likes: (stats['likes_given'] as num?)?.toInt() ?? 0,
    );
  }

  /// 我的帖子列表（最近 50 篇）。
  Future<List<Map<String, dynamic>>> myPosts(String token) async {
    final data =
        await _send('GET', '/api/users/me/posts', token: token)
            as Map<String, dynamic>;
    return [
      for (final item in (data['items'] as List? ?? []))
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<DailyTasksSnapshot> tasks(String token) async {
    final data =
        await _send('GET', '/api/users/me/tasks', token: token)
            as Map<String, dynamic>;
    return DailyTasksSnapshot.fromJson(data);
  }

  Future<
    ({
      int streak,
      int points,
      int reward,
      bool alreadyChecked,
      DailyTasksSnapshot snapshot,
    })
  >
  checkin(String token) async {
    final data =
        await _send('POST', '/api/users/me/checkin', token: token)
            as Map<String, dynamic>;
    return (
      streak: (data['streak'] as num?)?.toInt() ?? 0,
      points: (data['points'] as num?)?.toInt() ?? 0,
      reward: (data['reward'] as num?)?.toInt() ?? 0,
      snapshot: DailyTasksSnapshot.fromJson(data),
      alreadyChecked: data['alreadyChecked'] as bool? ?? false,
    );
  }

  Future<List<DateTime>> checkinDays(String token, DateTime month) async {
    final value = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final data = await _send('GET', '/api/users/me/checkins', token: token,
        query: {'month': value}) as Map<String, dynamic>;
    return [
      for (final row in data['days'] as List? ?? const [])
        DateTime.parse((row as Map)['date'].toString()),
    ];
  }

  Future<({int reward, bool duplicate, DailyTasksSnapshot snapshot})> reportTaskEvent(
      String token, String key, String eventId, String day) async {
    final data = await _send('POST', '/api/users/me/task-events', token: token,
        body: {'key': key, 'eventId': eventId, 'day': day}) as Map<String, dynamic>;
    return (
      reward: (data['reward'] as num?)?.toInt() ?? 0,
      duplicate: data['duplicate'] == true,
      snapshot: DailyTasksSnapshot.fromJson(data),
    );
  }

  Future<({int points, List<Map<String, dynamic>> entries})> pointHistory(String token) async {
    final data = await _send('GET', '/api/users/me/points', token: token) as Map<String, dynamic>;
    return (points: (data['points'] as num).toInt(), entries: [
      for (final row in data['entries'] as List? ?? const []) Map<String, dynamic>.from(row as Map),
    ]);
  }

  Future<List<Map<String, dynamic>>> rewardItems(String token, {bool admin = false}) async {
    final data = await _send('GET', admin ? '/api/users/admin/rewards' : '/api/users/me/rewards',
        token: token) as Map<String, dynamic>;
    return [for (final row in data['items'] as List? ?? const []) Map<String, dynamic>.from(row as Map)];
  }

  Future<List<Map<String, dynamic>>> redemptions(String token, {bool admin = false}) async {
    final data = await _send('GET', admin ? '/api/users/admin/redemptions' : '/api/users/me/redemptions',
        token: token) as Map<String, dynamic>;
    return [for (final row in data['items'] as List? ?? const []) Map<String, dynamic>.from(row as Map)];
  }

  Future<int> redeem(String token, String id) async {
    final data = await _send('POST', '/api/users/me/rewards/$id/redeem', token: token)
        as Map<String, dynamic>;
    return (data['points'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> taskConfig(String token) async {
    final data = await _send('GET', '/api/users/admin/tasks', token: token) as Map<String, dynamic>;
    return [for (final row in data['items'] as List? ?? const []) Map<String, dynamic>.from(row as Map)];
  }

  Future<void> updateTaskConfig(String token, String key, int reward,
      bool enabled, int targetCount) async {
    await _send('PATCH', '/api/users/admin/tasks/$key', token: token,
        body: {'reward': reward, 'enabled': enabled, 'targetCount': targetCount});
  }

  Future<void> saveReward(String token, {String? id, required String title,
      required String description, required int cost, required int stock, bool enabled = true}) async {
    await _send(id == null ? 'POST' : 'PATCH',
        id == null ? '/api/users/admin/rewards' : '/api/users/admin/rewards/$id', token: token,
        body: {'title': title, 'description': description, 'cost': cost, 'stock': stock,
          if (id != null) 'enabled': enabled});
  }

  Future<void> fulfillRedemption(String token, String id) async {
    await _send('PATCH', '/api/users/admin/redemptions/$id', token: token,
        body: {'status': 'fulfilled'});
  }

  // ---- 社区 ----

  Future<List<Zone>> zones() async {
    final data = await _send('GET', '/api/zones') as Map<String, dynamic>;
    return [
      for (final z in (data['items'] as List? ?? []))
        Zone.fromJson(z as Map<String, dynamic>),
    ];
  }

  Future<List<TagCount>> tags({String? type, String? zoneId}) async {
    final data =
        await _send(
              'GET',
              '/api/tags',
              query: {'type': ?type, 'zoneId': ?zoneId},
            )
            as Map<String, dynamic>;
    return [
      for (final t in (data['items'] as List? ?? []))
        TagCount.fromJson(t as Map<String, dynamic>),
    ];
  }

  Future<({List<Post> items, int total})> posts({
    String? type,
    String? zoneId,
    String? tag,
    String? keyword,
    int page = 1,
    String? token,
  }) async {
    final data =
        await _send(
              'GET',
              '/api/posts',
              token: token,
              query: {
                'type': ?type,
                'zoneId': ?zoneId,
                if (tag != null && tag.isNotEmpty) 'tag': tag,
                if (keyword != null && keyword.isNotEmpty) 'q': keyword,
                'page': page,
                'pageSize': 20,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final p in (data['items'] as List? ?? []))
          Post.fromJson(p as Map<String, dynamic>),
      ],
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Post> postDetail(String id, {String? token}) async {
    final data =
        await _send('GET', '/api/posts/$id', token: token)
            as Map<String, dynamic>;
    return Post.fromJson(data['post'] as Map<String, dynamic>);
  }

  Future<String> createPost({
    required String token,
    required String type,
    required String zoneId,
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/posts',
              token: token,
              body: {
                'type': type,
                'zoneId': zoneId,
                'title': title,
                'content': content,
                'tags': tags,
              },
            )
            as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<void> deletePost(String token, String id) async {
    await _send('DELETE', '/api/posts/$id', token: token);
  }

  Future<({bool liked, int likeCount})> toggleLike(
    String token,
    String postId,
  ) async {
    final data =
        await _send('POST', '/api/posts/$postId/like', token: token)
            as Map<String, dynamic>;
    return (
      liked: data['liked'] as bool,
      likeCount: (data['likeCount'] as num).toInt(),
    );
  }

  Future<List<Comment>> comments(String postId) async {
    final data =
        await _send('GET', '/api/posts/$postId/comments')
            as Map<String, dynamic>;
    return [
      for (final c in (data['items'] as List? ?? []))
        Comment.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<Comment> addComment(
    String token,
    String postId, {
    required String content,
    String? parentId,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/posts/$postId/comments',
              token: token,
              body: {'content': content, 'parentId': ?parentId},
            )
            as Map<String, dynamic>;
    return Comment.fromJson(data['comment'] as Map<String, dynamic>);
  }

  // ---- 在线终端 ----

  static const _terminalTimeout = Duration(seconds: 110);

  Stream<TerminalEvent> terminalEvents(
    String token,
    String command, {
    List<Map<String, String>>? files,
  }) async* {
    try {
      final request =
          http.Request('POST', ApiConfig.endpoint('/api/terminal/exec/stream'))
            ..followRedirects = false
            ..headers.addAll(_headers(token: token))
            ..headers['accept'] = 'application/x-ndjson'
            ..body = jsonEncode({'command': command, 'files': ?files});
      final response = await _http.send(request).timeout(_terminalTimeout);
      var bytes = 0;
      final bounded = response.stream.timeout(_terminalTimeout).map((chunk) {
        bytes += chunk.length;
        if (bytes > 2 * 1024 * 1024) throw ApiException('终端响应超出限额');
        return chunk;
      });
      if (response.statusCode != 200) {
        final body = await bounded.transform(utf8.decoder).join();
        Object? data;
        try {
          data = jsonDecode(body);
        } on FormatException {
          data = null;
        }
        throw ApiException(
          data is Map && data['error'] is String
              ? data['error'] as String
              : '在线终端不可用（${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      if (!(response.headers['content-type'] ?? '').startsWith(
        'application/x-ndjson',
      )) {
        throw ApiException('服务器尚未支持终端进度，请更新业务后端和终端服务');
      }
      var completed = false;
      await for (final line
          in bounded.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        if (utf8.encode(line).length > 700 * 1024) {
          throw ApiException('终端响应行超出限额');
        }
        if (completed) throw ApiException('终端返回重复结果');
        final event = TerminalEvent.decode(jsonDecode(line));
        completed = event.type == TerminalEventType.result;
        yield event;
      }
      if (!completed) throw ApiException('终端连接已中断，未收到执行结果');
    } on TimeoutException {
      throw ApiException('终端连接超时，请重试');
    } on SocketException catch (error) {
      throw ApiException('无法连接终端：${error.message}');
    } on http.ClientException {
      throw ApiException('终端连接已中断');
    } on HandshakeException {
      throw ApiException('无法建立终端安全连接');
    } on FormatException {
      throw ApiException('终端响应格式无效');
    }
  }

  Future<Map<String, dynamic>> terminalInfo(String token) async {
    return await _send('GET', '/api/terminal/pwd', token: token)
        as Map<String, dynamic>;
  }

  Future<void> resetTerminal(String token) async {
    await _send(
      'DELETE',
      '/api/terminal/session',
      token: token,
      timeout: _terminalTimeout,
    );
  }

  Future<({String stdout, String stderr, int exitCode})> terminalExec(
    String token,
    String command,
  ) async {
    final data =
        await _send(
              'POST',
              '/api/terminal/exec',
              token: token,
              timeout: _terminalTimeout,
              body: {'command': command},
            )
            as Map<String, dynamic>;
    return (
      stdout: data['stdout'] as String? ?? '',
      stderr: data['stderr'] as String? ?? '',
      exitCode: (data['exitCode'] as num?)?.toInt() ?? 1,
    );
  }

  // ---- 云 MySQL 练习库（与业务数据库隔离的独立 mysqld）----

  /// Server budget: 10 s queue plus an 8 s statement deadline.
  static const _sqlTimeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> sqlInfo(String token) async {
    return await _send('GET', '/api/sql/info', token: token)
        as Map<String, dynamic>;
  }

  /// One bound statement. [database] null selects the default schema and an
  /// empty string selects none. Returns the native SQLab result JSON.
  Future<Map<String, dynamic>> sqlQuery(
    String token, {
    String? database,
    required String source,
    List<String?> params = const [],
  }) async {
    return await _send(
          'POST',
          '/api/sql/query',
          token: token,
          timeout: _sqlTimeout,
          body: {'database': ?database, 'source': source, 'params': params},
        )
        as Map<String, dynamic>;
  }

  /// A multi-statement script; results before a failing statement are kept.
  Future<Map<String, dynamic>> sqlScript(
    String token, {
    String? database,
    required String source,
  }) async {
    return await _send(
          'POST',
          '/api/sql/script',
          token: token,
          timeout: _sqlTimeout,
          body: {'database': ?database, 'source': source},
        )
        as Map<String, dynamic>;
  }

  Future<void> sqlReset(String token) async {
    await _send(
      'DELETE',
      '/api/sql/databases',
      token: token,
      timeout: _sqlTimeout,
    );
  }

  // ---- 云端项目（私有云盘）----

  Future<List<Map<String, dynamic>>> cloudProjects(String token) async {
    final data =
        await _send('GET', '/api/cloud/projects', token: token)
            as Map<String, dynamic>;
    return [
      for (final p in (data['items'] as List? ?? []))
        Map<String, dynamic>.from(p as Map),
    ];
  }

  Future<Map<String, dynamic>> cloudCreateProject(
    String token,
    String name,
  ) async {
    return await _send(
          'POST',
          '/api/cloud/projects',
          token: token,
          body: {'name': name},
        )
        as Map<String, dynamic>;
  }

  Future<void> cloudDeleteProject(String token, String id) async {
    await _send('DELETE', '/api/cloud/projects/$id', token: token);
  }

  Future<Map<String, dynamic>> cloudFileTree(String token, String id) async {
    return await _send('GET', '/api/cloud/projects/$id/files', token: token)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cloudReadFile(
    String token,
    String id,
    String path,
  ) async {
    return await _send(
          'GET',
          '/api/cloud/projects/$id/file',
          token: token,
          query: {'path': path},
        )
        as Map<String, dynamic>;
  }

  Future<void> cloudWriteFile(
    String token,
    String id,
    String path,
    String base64Content,
  ) async {
    await _send(
      'PUT',
      '/api/cloud/projects/$id/file',
      token: token,
      body: {'path': path, 'content': base64Content},
    );
  }

  Future<void> cloudDeleteFile(String token, String id, String path) async {
    await _send(
      'DELETE',
      '/api/cloud/projects/$id/file',
      token: token,
      query: {'path': path},
    );
  }

  Future<({String stdout, String stderr, int exitCode})> cloudGit(
    String token,
    String id, {
    required String action,
    String? message,
    String? url,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/cloud/projects/$id/git',
              token: token,
              body: {'action': action, 'message': ?message, 'url': ?url},
            )
            as Map<String, dynamic>;
    return (
      stdout: data['stdout'] as String? ?? '',
      stderr: data['stderr'] as String? ?? '',
      exitCode: (data['exitCode'] as num?)?.toInt() ?? 1,
    );
  }

  /// 审计日志（仅管理员），分页倒序。
  Future<({List<Map<String, dynamic>> items, int total})> auditLogs(
    String token, {
    int page = 1,
    String? action,
    String? user,
  }) async {
    final data =
        await _send(
              'GET',
              '/api/audit',
              token: token,
              query: {
                'page': page,
                'pageSize': 50,
                'action': ?action,
                'user': ?user,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final r in (data['items'] as List? ?? []))
          Map<String, dynamic>.from(r as Map),
      ],
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<bool> health() async {
    try {
      final data = await _send('GET', '/api/health');
      return data is Map && data['ok'] == true;
    } on ApiException {
      return false;
    }
  }
}

/// 调试用：dump 响应（release 无操作）。
void debugLogResponse(Object? data) {
  if (kDebugMode) {
    debugPrint('[api] $data');
  }
}
