import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../community/models.dart';
import '../config/api_config.dart';
import '../config/client_platform.dart';
import 'ai_service.dart';
import 'ai_turn_event.dart';

export 'ai_turn_event.dart';
import 'connection_probe.dart';
import 'studio_profile.dart';

/// AI 请求走哪条链路。
///
/// [relay] 用服务端密钥与固定模型，客户端只提交消息和工具。
/// [direct] 直接用用户在设置里填的地址、密钥、模型和协议，密钥只在本机内存。
enum AiRoute { relay, direct }

/// 一次 AI 调用的连接参数。[AiEndpoint.relay] 忽略除 [protocol] 之外的字段。
class AiEndpoint {
  const AiEndpoint.relay({this.protocol = AiProtocol.chat})
    : route = AiRoute.relay,
      baseUrl = '',
      apiKey = '',
      model = '',
      thinking = false;

  const AiEndpoint.direct({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.protocol = AiProtocol.chat,
    this.thinking = false,
  }) : route = AiRoute.direct;

  final AiRoute route;
  final String baseUrl;
  final String apiKey;
  final String model;
  final AiProtocol protocol;

  /// 直连时是否请求思考过程。只影响 Responses 与 Messages 的请求字段。
  final bool thinking;

  /// 是否具备直连所需的必要参数；中转链路恒为 true。
  bool get isUsable => switch (route) {
    AiRoute.relay => true,
    AiRoute.direct => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty,
  };

  /// 日志安全的描述：不含地址细节，也不含密钥。
  @override
  String toString() => switch (route) {
    AiRoute.relay => 'AiEndpoint.relay(${protocol.id})',
    AiRoute.direct => 'AiEndpoint.direct(${protocol.id})',
  };
}

/// 一次 AI 回合的结果。中转与直连返回同一形状，调用方无需分支。
class AiChatResult {
  const AiChatResult({
    required this.model,
    required this.content,
    required this.rawMessage,
    this.usage,
    this.aiGenerated = true,
    this.reasoning = '',
  });

  /// 用一条内部助手消息构造结果，替三个协议解码器与流式组装共用。
  ///
  /// 形状不合法时抛 [ApiException]，与中转响应的失败文案一致。
  factory AiChatResult.fromMessage({
    required String model,
    required Map<String, dynamic> message,
    Map<String, dynamic>? usage,
    bool aiGenerated = true,
  }) {
    final content = message['content'];
    final calls = message['tool_calls'];
    if (message['role'] != 'assistant' ||
        (content != null && content is! String) ||
        (calls != null && calls is! List) ||
        (content == null && (calls == null || (calls as List).isEmpty))) {
      throw ApiException('AI 响应格式无效');
    }
    final reasoning = message['reasoning_content'];
    return AiChatResult(
      model: model,
      content: content is String ? content : '',
      rawMessage: Map<String, dynamic>.from(message),
      usage: usage,
      aiGenerated: aiGenerated,
      reasoning: reasoning is String ? reasoning : '',
    );
  }

  final String model;

  /// 本轮完整的思考内容；模型没有思考时为空串。
  ///
  /// 回传给上游用的原始字段留在 [rawMessage]：Chat 与中转是
  /// `reasoning_content`，直连 Messages 是 `reasoning_blocks`。
  final String reasoning;

  /// 助手文本；只有工具调用时可能为空。
  final String content;

  /// 原样保留的助手消息（含 [tool_calls]），用于下一轮对话。
  final Map<String, dynamic> rawMessage;

  final Map<String, dynamic>? usage;

  /// 该回复是否由 AI 生成，客户端据此显示“内容由AI生成”。
  ///
  /// 服务端 `/api/ai/chat` 现在返回 `aiGenerated: true`（整改任务书 §3-W2）。
  /// 缺字段时按“是 AI”处理：这条链路上的回复本来就来自模型，宁可多标。
  final bool aiGenerated;

  /// 原样保留的工具调用，顺序即服务端返回顺序。
  List<Map<String, dynamic>> get toolCalls {
    final calls = rawMessage['tool_calls'];
    if (calls is! List) return const [];
    return [
      for (final call in calls)
        if (call is Map) Map<String, dynamic>.from(call),
    ];
  }
}

/// 可用模型；[reasoningEfforts] 为空表示不提供推理强度选择。
class AiModelInfo {
  const AiModelInfo({required this.id, this.reasoningEfforts = const []});

  final String id;

  /// 服务端声明的推理强度选项；空列表表示该模型不支持或未声明。
  final List<String> reasoningEfforts;
}

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
  ApiClient({
    http.Client? transport,
    ConnectionProbe? probe,
    Duration? aiFirstByteTimeout,
    Duration? aiIdleTimeout,
  }) : _transport = transport,
       _probe = probe ?? const SocketConnectionProbe(),
       _aiFirstByteTimeout = aiFirstByteTimeout ?? _aiTimeout,
       _aiIdleTimeout = aiIdleTimeout ?? _aiTimeout;

  final http.Client? _transport;
  final ConnectionProbe _probe;

  /// 流式回合的首字节超时。测试注入短值，不真等 90 秒。
  final Duration _aiFirstByteTimeout;

  /// 流式回合两段数据之间的空闲超时。
  final Duration _aiIdleTimeout;
  // 延迟创建并复用连接，不在应用首帧初始化网络。
  late final http.Client _http = _transport ?? http.Client();

  static final ApiClient instance = ApiClient();

  void close() => _http.close();

  Map<String, String> _headers({String? token}) => {
    'content-type': 'application/json',
    'x-client-platform': ClientPlatform.header,
    if (token != null) 'authorization': 'Bearer $token',
  };

  static void _requireOnline() {
    if (StudioProfile.current?.offlineOnly == true) {
      throw ApiException(
        '离线模式下不可访问在线服务',
        details: const {'code': 'OFFLINE_ONLY'},
      );
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, Object>? query,
    String? token,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    _requireOnline();
    final uri = ApiConfig.endpoint(path, query);
    final clock = Stopwatch()..start();
    try {
      // [abortTrigger] 完成时真正中断在途请求（取消、退出页面）。
      final request =
          (abortTrigger == null
                ? http.Request(method, uri)
                : http.AbortableRequest(
                    method,
                    uri,
                    abortTrigger: abortTrigger,
                  ))
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
        final payload = data is Map ? Map<String, dynamic>.from(data) : null;
        final serverError = payload?['error'] is String
            ? _clip(payload!['error'] as String, 200)
            : '';
        final headerId = response.headers['x-request-id'];
        final bodyId = payload?['requestId'];
        final requestId = headerId != null && headerId.trim().isNotEmpty
            ? headerId.trim()
            : (bodyId is String && bodyId.isNotEmpty ? bodyId : null);
        var message = serverError.isNotEmpty
            ? serverError
            : '服务器 ${uri.host} 返回 ${response.statusCode}，请稍后重试';
        if (response.statusCode >= 500 && requestId != null) {
          message = '$message\n请求编号：$requestId';
        }
        throw ApiException(
          message,
          statusCode: response.statusCode,
          details: {
            ...?payload,
            ..._failureDetails(
              phase: 'http',
              method: method,
              uri: uri,
              elapsed: clock.elapsed,
              statusCode: response.statusCode,
              serverError: serverError.isNotEmpty ? serverError : text,
              requestId: requestId,
            ),
          },
        );
      }
      if (data != null && data is! Map && data is! List) {
        throw ApiException(
          '服务响应异常，请稍后重试',
          details: _failureDetails(
            phase: 'response',
            method: method,
            uri: uri,
            elapsed: clock.elapsed,
          ),
        );
      }
      return data;
    } on http.RequestAbortedException {
      throw ApiException('请求已取消');
    } on SocketException catch (e) {
      final phase = _phaseOfSocket(e);
      final osMessage = _osMessageOf(e);
      throw ApiException(
        _failureMessage(phase, uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: phase,
          method: method,
          uri: uri,
          elapsed: clock.elapsed,
          exception: e.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on TimeoutException catch (e) {
      final osMessage = _osMessageOf(e);
      throw ApiException(
        _failureMessage('timeout', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'timeout',
          method: method,
          uri: uri,
          elapsed: clock.elapsed,
          exception: e.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on http.ClientException catch (e) {
      final osMessage = _osMessageOf(e);
      throw ApiException(
        _failureMessage('connect', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'connect',
          method: method,
          uri: uri,
          elapsed: clock.elapsed,
          exception: e.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on HandshakeException catch (e) {
      final osMessage = _osMessageOf(e);
      throw ApiException(
        _failureMessage('tls', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'tls',
          method: method,
          uri: uri,
          elapsed: clock.elapsed,
          exception: e.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on FormatException {
      throw ApiException(
        '服务响应异常，请稍后重试',
        details: _failureDetails(
          phase: 'response',
          method: method,
          uri: uri,
          elapsed: clock.elapsed,
          exception: 'FormatException',
        ),
      );
    } on HttpException catch (e) {
      final osMessage = _osMessageOf(e);
      throw ApiException(
        _failureMessage('http', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'http',
          method: method,
          uri: uri,
          elapsed: clock.elapsed,
          exception: e.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    }
  }

  /// 一次失败的结构化说明。只放进「详情」，不含授权头、令牌、正文与查询串。
  static Map<String, dynamic> _failureDetails({
    required String phase,
    required String method,
    required Uri uri,
    required Duration elapsed,
    String exception = '',
    String osMessage = '',
    int? statusCode,
    String? serverError,
    String? requestId,
  }) {
    final details = <String, dynamic>{
      'phase': phase,
      if (exception.isNotEmpty) 'exception': exception,
      if (osMessage.trim().isNotEmpty) 'osMessage': osMessage.trim(),
      'host': uri.host,
      'method': method,
      'path': uri.path,
      'elapsedMs': elapsed.inMilliseconds,
      'statusCode': ?statusCode,
    };
    final server = serverError?.trim() ?? '';
    if (server.isNotEmpty) details['serverError'] = _clip(server, 200);
    final id = requestId?.trim() ?? '';
    if (id.isNotEmpty) details['requestId'] = id;
    return details;
  }

  /// 一句话说清哪里坏了：带主机名和失败的那一步。
  ///
  /// 「请检查设备时间」只在证书过期或尚未生效时出现；其他握手失败不提设备时间。
  static String _failureMessage(
    String phase,
    String host, {
    String osMessage = '',
  }) {
    switch (phase) {
      case 'dns':
        return '找不到服务器 $host：域名解析失败，请检查网络和 DNS 设置';
      case 'connect':
        return '连不上服务器 $host：连接被拒绝或网络不通';
      case 'tls':
        if (_isCertificateTimeProblem(osMessage)) {
          return '连不上服务器 $host：TLS 握手失败，证书已过期或尚未生效，请检查设备时间';
        }
        return '连不上服务器 $host：TLS 握手失败，握手被断开';
      case 'timeout':
        return '连不上服务器 $host：等待响应超时';
      case 'http':
        return '连不上服务器 $host：连接在传输中被中断';
      case 'response':
        return '服务器 $host 返回的内容无法解析';
      default:
        return '连不上服务器 $host';
    }
  }

  /// 证书是不是过期或尚未生效。系统原文的措辞各平台不同，只认这两种。
  static bool _isCertificateTimeProblem(String osMessage) {
    final text = osMessage.toLowerCase();
    return text.contains('expired') || text.contains('not yet valid');
  }

  /// [SocketException] 是解析失败还是连不上。判断不了就按连接失败处理。
  static String _phaseOfSocket(SocketException error) {
    final text = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    const dnsMarkers = [
      'failed host lookup',
      'nodename nor servname',
      'name or service not known',
      'no address associated',
      'temporary failure in name resolution',
    ];
    for (final marker in dnsMarkers) {
      if (text.contains(marker)) return 'dns';
    }
    return 'connect';
  }

  /// 系统给出的原文，用于「详情」的「系统信息」一行。
  static String _osMessageOf(Object error) {
    if (error is SocketException) {
      final os = error.osError?.message;
      return os != null && os.isNotEmpty ? os : error.message;
    }
    if (error is HandshakeException) return error.message;
    if (error is TlsException) return error.message;
    if (error is HttpException) return error.message;
    if (error is TimeoutException) return error.message ?? '';
    if (error is http.ClientException) return error.message;
    return error.toString();
  }

  static String _clip(String text, int max) {
    final trimmed = text.trim();
    return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
  }

  // ---- 连接诊断 ----

  /// 每一步的超时。真机上 TLS 被拦时通常卡在这一步。
  static const Duration probeStepTimeout = Duration(seconds: 6);

  /// 逐步检查到 API 服务器的连接：域名解析、TCP 连接、TLS 握手。
  ///
  /// 只连 API 服务器，不连任何其他主机。每一步独立超时。
  /// 返回可直接显示的多行文本；本方法不抛异常。
  Future<String> probeConnection() async {
    final uri = Uri.parse(ApiConfig.baseUrl);
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final lines = <String>['服务器：$host'];

    final dns = await _probeStep(() => _probe.lookup(host));
    if (!dns.ok) {
      lines.add('① 域名解析：失败，${dns.describe()}');
      lines.add('结论：域名解析失败，请检查网络和 DNS 设置。');
      return lines.join('\n');
    }
    lines.add('① 域名解析：成功，${dns.addresses.join('、')}（${_seconds(dns.elapsed)}）');

    final connect = await _probeStep(() async {
      await _probe.connect(host, port);
      return const <String>[];
    });
    if (!connect.ok) {
      lines.add('② TCP 连接 $port：失败，${connect.describe()}');
      lines.add('结论：服务器的 $port 端口连不上，可能端口不通或被网络拦截。');
      return lines.join('\n');
    }
    lines.add('② TCP 连接 $port：成功（${_seconds(connect.elapsed)}）');

    if (uri.scheme == 'https') {
      final tls = await _probeStep(() async {
        await _probe.handshake(host, port);
        return const <String>[];
      });
      if (!tls.ok) {
        lines.add('③ TLS 握手：失败，${tls.describe()}');
        if (_isCertificateTimeProblem(tls.osMessage)) {
          lines.add('结论：服务器证书已过期或尚未生效。检查设备时间，或稍后重试。');
        } else {
          lines.add(
            '结论：能连到服务器的 IP，但 TLS 握手被断开。'
            '常见原因：当前网络拦截了这个域名，或服务器证书、代理配置有问题。'
            '试试换一个网络，比如手机流量。',
          );
        }
        return lines.join('\n');
      }
      lines.add('③ TLS 握手：成功（${_seconds(tls.elapsed)}）');
    }

    lines.add('结论：到服务器的连接正常。问题可能在服务端返回的内容，稍后重试。');
    return lines.join('\n');
  }

  Future<_ProbeStep> _probeStep(Future<List<String>> Function() step) async {
    final clock = Stopwatch()..start();
    try {
      final addresses = await step().timeout(probeStepTimeout);
      return _ProbeStep(ok: true, elapsed: clock.elapsed, addresses: addresses);
    } on TimeoutException {
      return _ProbeStep(
        ok: false,
        elapsed: clock.elapsed,
        osMessage: '${probeStepTimeout.inSeconds} 秒内没有响应',
        exception: 'TimeoutException',
      );
    } on Object catch (error) {
      return _ProbeStep(
        ok: false,
        elapsed: clock.elapsed,
        osMessage: _osMessageOf(error),
        exception: error.runtimeType.toString(),
      );
    }
  }

  static String _seconds(Duration elapsed) =>
      '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒';

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

  Future<HuaweiLoginResult> huaweiLogin(String authorizationCode) async {
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
      return HuaweiLoginResult.binding(
        bindingId,
        data['phoneAvailable'] == true,
      );
    }
    return HuaweiLoginResult.signedIn(
      data['token'] as String,
      CommunityUser.fromJson(data['user']),
    );
  }

  Future<({String token, CommunityUser user})> skipHuaweiBinding(
    String bindingId,
  ) async {
    final data =
        await _send(
              'POST',
              '/api/auth/huawei/skip',
              body: {'bindingId': bindingId},
            )
            as Map<String, dynamic>;
    return (
      token: data['token'] as String,
      user: CommunityUser.fromJson(data['user']),
    );
  }

  Future<({String token, CommunityUser user})> bindHuaweiAccount(
    String bindingId,
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
              '/api/auth/huawei/bind',
              body: {
                'bindingId': bindingId,
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
    final data =
        await _send(
              'GET',
              '/api/users/me/checkins',
              token: token,
              query: {'month': value},
            )
            as Map<String, dynamic>;
    return [
      for (final row in data['days'] as List? ?? const [])
        DateTime.parse((row as Map)['date'].toString()),
    ];
  }

  Future<({int reward, bool duplicate, DailyTasksSnapshot snapshot})>
  reportTaskEvent(String token, String key, String eventId, String day) async {
    final data =
        await _send(
              'POST',
              '/api/users/me/task-events',
              token: token,
              body: {'key': key, 'eventId': eventId, 'day': day},
            )
            as Map<String, dynamic>;
    return (
      reward: (data['reward'] as num?)?.toInt() ?? 0,
      duplicate: data['duplicate'] == true,
      snapshot: DailyTasksSnapshot.fromJson(data),
    );
  }

  Future<({int points, List<Map<String, dynamic>> entries})> pointHistory(
    String token,
  ) async {
    final data =
        await _send('GET', '/api/users/me/points', token: token)
            as Map<String, dynamic>;
    return (
      points: (data['points'] as num).toInt(),
      entries: [
        for (final row in data['entries'] as List? ?? const [])
          Map<String, dynamic>.from(row as Map),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> rewardItems(
    String token, {
    bool admin = false,
  }) async {
    final data =
        await _send(
              'GET',
              admin ? '/api/users/admin/rewards' : '/api/users/me/rewards',
              token: token,
            )
            as Map<String, dynamic>;
    return [
      for (final row in data['items'] as List? ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> redemptions(
    String token, {
    bool admin = false,
  }) async {
    final data =
        await _send(
              'GET',
              admin
                  ? '/api/users/admin/redemptions'
                  : '/api/users/me/redemptions',
              token: token,
            )
            as Map<String, dynamic>;
    return [
      for (final row in data['items'] as List? ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<int> redeem(String token, String id) async {
    final data =
        await _send('POST', '/api/users/me/rewards/$id/redeem', token: token)
            as Map<String, dynamic>;
    return (data['points'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> taskConfig(String token) async {
    final data =
        await _send('GET', '/api/users/admin/tasks', token: token)
            as Map<String, dynamic>;
    return [
      for (final row in data['items'] as List? ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<void> updateTaskConfig(
    String token,
    String key,
    int reward,
    bool enabled,
    int targetCount,
  ) async {
    await _send(
      'PATCH',
      '/api/users/admin/tasks/$key',
      token: token,
      body: {'reward': reward, 'enabled': enabled, 'targetCount': targetCount},
    );
  }

  Future<void> saveReward(
    String token, {
    String? id,
    required String title,
    required String description,
    required int cost,
    required int stock,
    bool enabled = true,
  }) async {
    await _send(
      id == null ? 'POST' : 'PATCH',
      id == null ? '/api/users/admin/rewards' : '/api/users/admin/rewards/$id',
      token: token,
      body: {
        'title': title,
        'description': description,
        'cost': cost,
        'stock': stock,
        if (id != null) 'enabled': enabled,
      },
    );
  }

  Future<void> fulfillRedemption(String token, String id) async {
    await _send(
      'PATCH',
      '/api/users/admin/redemptions/$id',
      token: token,
      body: {'status': 'fulfilled'},
    );
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

  /// 举报帖子、评论或用户（contracts.md C 节）。
  ///
  /// 返回 `{id, status}`。`targetType` 只接受 `post` / `comment` / `user`，
  /// 其余值在本地就拒绝，不让无效请求打到服务端。
  Future<({String id, String status})> report({
    required String token,
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    if (!const {'post', 'comment', 'user'}.contains(targetType)) {
      throw ApiException('举报目标类型无效');
    }
    final data =
        await _send(
              'POST',
              '/api/reports',
              token: token,
              body: {
                'targetType': targetType,
                'targetId': targetId,
                'reason': reason,
              },
            )
            as Map<String, dynamic>;
    final id = data['id'];
    if (id is! String || id.isEmpty) throw ApiException('举报响应无效');
    return (id: id, status: data['status'] as String? ?? 'pending');
  }

  // ---- 账号 ----

  /// 永久注销当前账号（contracts.md C 节）。
  ///
  /// 只有在用户二次确认后调用；[confirm] 固定为契约里的确认词。
  /// 成功后服务端立即吊销本账号全部会话，调用方必须清本地登录态。
  Future<void> deactivateAccount(
    String token, {
    String confirm = 'DEACTIVATE',
  }) async {
    await _send(
      'POST',
      '/api/users/me/deactivate',
      token: token,
      body: {'confirm': confirm},
    );
  }

  // ---- 在线终端 ----

  static const _terminalTimeout = Duration(seconds: 110);

  /// 终端执行流。
  ///
  /// [abortTrigger] 完成时中断在途 HTTP，取消才能真的停掉远程进程。
  Stream<TerminalEvent> terminalEvents(
    String token,
    String command, {
    List<Map<String, String>>? files,
    Future<void>? abortTrigger,
  }) async* {
    _requireOnline();
    final uri = ApiConfig.endpoint('/api/terminal/exec/stream');
    final clock = Stopwatch()..start();
    try {
      final request =
          (abortTrigger == null
                ? http.Request('POST', uri)
                : http.AbortableRequest(
                    'POST',
                    uri,
                    abortTrigger: abortTrigger,
                  ))
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
          details: _failureDetails(
            phase: 'http',
            method: 'POST',
            uri: uri,
            elapsed: clock.elapsed,
            statusCode: response.statusCode,
            serverError: body,
            requestId: response.headers['x-request-id'],
          ),
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
      if (!completed) {
        // 中断（MockClient 与真实 AbortableRequest 都会先结束字节流）
        // 不算终端故障：取消是预期路径，直接结束流。
        var aborted = false;
        abortTrigger?.then(
          (_) => aborted = true,
          onError: (_) => aborted = true,
        );
        await Future<void>.delayed(Duration.zero);
        if (aborted) return;
        throw ApiException('终端连接已中断，未收到执行结果');
      }
    } on TimeoutException catch (error) {
      // 文案不变：终端面板的旧文案仍在用。
      throw ApiException(
        '终端连接超时，请重试',
        details: _failureDetails(
          phase: 'timeout',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: _osMessageOf(error),
        ),
      );
    } on http.RequestAbortedException {
      // 取消是预期路径：不向调用方谎报错误，直接结束流。
      return;
    } on SocketException catch (error) {
      final phase = _phaseOfSocket(error);
      final osMessage = _osMessageOf(error);
      throw ApiException(
        '无法连接终端：$osMessage',
        details: _failureDetails(
          phase: phase,
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        '终端连接已中断',
        details: _failureDetails(
          phase: 'connect',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: _osMessageOf(error),
        ),
      );
    } on HandshakeException catch (error) {
      final osMessage = _osMessageOf(error);
      throw ApiException(
        '连不上终端服务器 ${uri.host}：TLS 握手失败',
        details: _failureDetails(
          phase: 'tls',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on FormatException {
      throw ApiException(
        '终端响应格式无效',
        details: _failureDetails(
          phase: 'response',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: 'FormatException',
        ),
      );
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

  // ---- AI 编程助手 ----

  /// 服务端默认 60 s，这里留出转接与网络余量。
  static const _aiTimeout = Duration(seconds: 90);

  /// 模型目录的超时。列表只是选择器的装饰，不能拖住会话打开。
  static const _aiModelsTimeout = Duration(seconds: 8);

  /// 一次模型回合。
  ///
  /// [endpoint] 为空或为 relay 时走服务端转接 `/api/ai/chat`（需登录令牌）。
  /// direct 时直接用用户配置的地址、密钥、模型与协议直连上游，不经过本站。
  /// 两条链路返回同一内部形状，[VibeCodingController] 无需分支。
  ///
  /// [abortTrigger] 完成时真正终止在途 HTTP 请求。
  /// [model] 为空时沿用设置或服务端默认；[reasoningEffort] 只在客户端显式
  /// 选择时下发，默认为 null，不改变现有行为。
  Future<AiChatResult> aiChat({
    required String token,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    AiEndpoint? endpoint,
    String? model,
    String? reasoningEffort,
  }) async {
    final target = endpoint ?? const AiEndpoint.relay();
    final requested = model?.trim() ?? '';
    final effort = reasoningEffort?.trim() ?? '';
    if (target.route == AiRoute.direct) {
      return _aiChatDirect(
        target,
        messages: messages,
        tools: tools,
        abortTrigger: abortTrigger,
        model: requested.isEmpty ? null : requested,
        reasoningEffort: effort.isEmpty ? null : effort,
      );
    }
    final data =
        await _send(
              'POST',
              '/api/ai/chat',
              token: token,
              timeout: _aiTimeout,
              abortTrigger: abortTrigger,
              body: {
                'messages': messages,
                'tools': ?tools,
                'model': ?(requested.isEmpty ? null : requested),
                'reasoning_effort': ?(effort.isEmpty ? null : effort),
              },
            )
            as Map<String, dynamic>;
    return _decodeAiResult(data);
  }

  /// 一次模型回合的事件流。参数与 [aiChat] 相同。
  ///
  /// 中转走 `/api/ai/chat/stream` 的 NDJSON，直连按协议解析上游 SSE。
  /// 两条链路产出同一种事件流，Agent 循环不按协议分支。
  /// 取消时中断在途请求并结束流，不抛未处理的异常。
  Stream<AiTurnEvent> aiChatStream({
    required String token,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    AiEndpoint? endpoint,
    String? model,
    String? reasoningEffort,
  }) {
    final target = endpoint ?? const AiEndpoint.relay();
    final requested = model?.trim() ?? '';
    final effort = reasoningEffort?.trim() ?? '';
    if (target.route == AiRoute.direct) {
      return _aiChatStreamDirect(
        target,
        messages: messages,
        tools: tools,
        abortTrigger: abortTrigger,
        model: requested.isEmpty ? null : requested,
        reasoningEffort: effort.isEmpty ? null : effort,
      );
    }
    return _aiChatStreamRelay(
      token,
      messages: messages,
      tools: tools,
      abortTrigger: abortTrigger,
      model: requested.isEmpty ? null : requested,
      reasoningEffort: effort.isEmpty ? null : effort,
    );
  }

  /// 可用模型列表；[endpoint] 为直连时返回空列表。
  ///
  /// 直连模式下游地址与模型由用户自己填，没有统一的目录接口，
  /// 这里不探测也不猜，调用方回退到设置里的单个模型。
  Future<List<AiModelInfo>> aiModels({
    required String token,
    AiEndpoint? endpoint,
  }) async {
    final target = endpoint ?? const AiEndpoint.relay();
    if (target.route == AiRoute.direct) return const [];
    final data =
        await _send(
              'GET',
              '/api/ai/models',
              token: token,
              timeout: _aiModelsTimeout,
            )
            as Map<String, dynamic>;
    final list = data['data'];
    if (list is! List) return const [];
    final models = <AiModelInfo>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.trim().isEmpty) continue;
      final efforts = <String>[];
      final raw = entry['reasoning_efforts'];
      if (raw is List) {
        for (final effort in raw) {
          if (effort is String && effort.trim().isNotEmpty) {
            efforts.add(effort.trim());
          }
        }
      }
      models.add(AiModelInfo(id: id.trim(), reasoningEfforts: efforts));
    }
    return models;
  }

  /// 直连上游：编码、发送、解码均由 [AiService] 完成。
  ///
  /// 离线产品在这里被策略拦下，不构造任何请求。密钥不进入异常文案。
  Future<AiChatResult> _aiChatDirect(
    AiEndpoint endpoint, {
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    String? model,
    String? reasoningEffort,
  }) async {
    _requireOnline();
    if (!endpoint.isUsable) {
      throw ApiException(
        '请先在 AI 接口设置中填写地址与模型',
        details: const {'code': 'AI_NOT_CONFIGURED'},
      );
    }
    final uri = Uri.parse(
      AiService.endpoint(endpoint.baseUrl, endpoint.protocol),
    );
    if (!uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ApiException('AI 接口地址无效，需要 http 或 https');
    }
    final body = AiService.encodeRequest(
      protocol: endpoint.protocol,
      model: model ?? endpoint.model.trim(),
      messages: messages,
      tools: tools,
      reasoningEffort: reasoningEffort,
      thinking: endpoint.thinking,
    );
    final request =
        (abortTrigger == null
              ? http.Request('POST', uri)
              : http.AbortableRequest('POST', uri, abortTrigger: abortTrigger))
          ..followRedirects = false
          ..headers.addAll(
            AiService.headers(endpoint.protocol, apiKey: endpoint.apiKey),
          )
          ..headers['x-client-platform'] = ClientPlatform.header
          ..body = jsonEncode(body);
    final clock = Stopwatch()..start();
    try {
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_aiTimeout);
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode >= 300) {
        final headerId = response.headers['x-request-id'];
        throw ApiException(
          _aiErrorMessage(response.statusCode, text),
          statusCode: response.statusCode,
          details: _failureDetails(
            phase: 'http',
            method: 'POST',
            uri: uri,
            elapsed: clock.elapsed,
            exception: 'HttpStatus',
            statusCode: response.statusCode,
            serverError: text,
            requestId: headerId,
          ),
        );
      }
      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw ApiException(
          'AI 接口返回了无法解析的内容',
          details: _failureDetails(
            phase: 'response',
            method: 'POST',
            uri: uri,
            elapsed: clock.elapsed,
          ),
        );
      }
      return _decodeAiResult({
        'model': model ?? endpoint.model.trim(),
        'message': AiService.decodeReply(endpoint.protocol, decoded),
      });
    } on SocketException catch (error) {
      final phase = _phaseOfSocket(error);
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage(phase, uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: phase,
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on TimeoutException catch (error) {
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('timeout', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'timeout',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on http.RequestAbortedException {
      throw ApiException('请求已取消', details: const {'code': 'ABORTED'});
    } on HandshakeException catch (error) {
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('tls', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'tls',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on http.ClientException catch (error) {
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('connect', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'connect',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on FormatException {
      throw ApiException(
        'AI 接口返回了无法解析的内容',
        details: _failureDetails(
          phase: 'response',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: 'FormatException',
        ),
      );
    } on AiException catch (error) {
      throw ApiException(error.message);
    }
  }

  // ---- AI 事件流：中转与直连 ----

  /// 中转：POST `/api/ai/chat/stream`，按行读 NDJSON 事件。
  ///
  /// 旧服务端没有这个路由（404 或 405）时回退到整轮的 `/api/ai/chat`，
  /// 只发一个 [AiTurnCompleted]，因此服务端与客户端谁先上线都可以。
  Stream<AiTurnEvent> _aiChatStreamRelay(
    String token, {
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    String? model,
    String? reasoningEffort,
  }) async* {
    _requireOnline();
    final isAborted = _abortFlag(abortTrigger);
    final uri = ApiConfig.endpoint('/api/ai/chat/stream');
    final clock = Stopwatch()..start();
    try {
      final request =
          (abortTrigger == null
                ? http.Request('POST', uri)
                : http.AbortableRequest(
                    'POST',
                    uri,
                    abortTrigger: abortTrigger,
                  ))
            ..followRedirects = false
            ..headers.addAll(_headers(token: token))
            ..headers['accept'] = 'application/x-ndjson'
            ..body = jsonEncode({
              'messages': messages,
              'tools': ?tools,
              'model': ?model,
              'reasoning_effort': ?reasoningEffort,
            });
      final response = await _http.send(request).timeout(_aiFirstByteTimeout);
      if (response.statusCode == 404 || response.statusCode == 405) {
        await _drain(response.stream);
        try {
          yield AiTurnCompleted(
            await aiChat(
              token: token,
              messages: messages,
              tools: tools,
              abortTrigger: abortTrigger,
              model: model,
              reasoningEffort: reasoningEffort,
            ),
          );
        } on ApiException {
          if (isAborted()) return;
          rethrow;
        }
        return;
      }
      if (response.statusCode != 200) {
        final text = await _idleBound(
          _cutAt(response.stream, abortTrigger),
        ).transform(utf8.decoder).join();
        throw ApiException(
          _aiErrorMessage(response.statusCode, text),
          statusCode: response.statusCode,
          details: _failureDetails(
            phase: 'http',
            method: 'POST',
            uri: uri,
            elapsed: clock.elapsed,
            statusCode: response.statusCode,
            serverError: text,
            requestId: response.headers['x-request-id'],
          ),
        );
      }
      final lines = _idleBound(
        _cutAt(response.stream, abortTrigger),
      ).transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        final text = line.trim();
        if (text.isEmpty) continue;
        Object? decoded;
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          throw ApiException('AI 流式响应格式无效');
        }
        if (decoded is! Map<String, dynamic>) {
          throw ApiException('AI 流式响应格式无效');
        }
        switch (decoded['type']) {
          case 'reasoning':
            final piece = decoded['text'];
            if (piece is String && piece.isNotEmpty) {
              yield AiReasoningDelta(piece);
            }
          case 'content':
            final piece = decoded['text'];
            if (piece is String && piece.isNotEmpty) {
              yield AiContentDelta(piece);
            }
          case 'tool_call':
            final index = decoded['index'];
            final name = decoded['name'];
            if (index is int && name is String && name.isNotEmpty) {
              yield AiToolCallStarted(index: index, name: name);
            }
          case 'result':
            yield AiTurnCompleted(_decodeAiResult(decoded));
            return;
          case 'error':
            throw _aiStreamError(decoded);
          default:
            // `start` 和以后新增的事件只承载元信息，这里忽略。
            break;
        }
      }
      if (isAborted()) return;
      throw ApiException(
        'AI 流式响应提前结束',
        details: _failureDetails(
          phase: 'response',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
        ),
      );
    } on http.RequestAbortedException {
      return;
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error) {
      if (isAborted()) return;
      throw ApiException(
        _failureMessage('timeout', uri.host, osMessage: _osMessageOf(error)),
        details: _failureDetails(
          phase: 'timeout',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: _osMessageOf(error),
        ),
      );
    } on SocketException catch (error) {
      final phase = _phaseOfSocket(error);
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage(phase, uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: phase,
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on HandshakeException catch (error) {
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('tls', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'tls',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on http.ClientException catch (error) {
      if (isAborted()) return;
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('connect', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'connect',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    }
  }

  /// 直连：按协议编码请求。响应是 SSE 就按协议解析，否则整体解码。
  Stream<AiTurnEvent> _aiChatStreamDirect(
    AiEndpoint endpoint, {
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    String? model,
    String? reasoningEffort,
  }) async* {
    _requireOnline();
    if (!endpoint.isUsable) {
      throw ApiException(
        '请先在 AI 接口设置中填写地址与模型',
        details: const {'code': 'AI_NOT_CONFIGURED'},
      );
    }
    final isAborted = _abortFlag(abortTrigger);
    final selectedModel = model ?? endpoint.model.trim();
    final uri = Uri.parse(
      AiService.endpoint(endpoint.baseUrl, endpoint.protocol),
    );
    if (!uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ApiException('AI 接口地址无效，需要 http 或 https');
    }
    final body = AiService.encodeRequest(
      protocol: endpoint.protocol,
      model: selectedModel,
      messages: messages,
      tools: tools,
      reasoningEffort: reasoningEffort,
      stream: true,
      thinking: endpoint.thinking,
    );
    final clock = Stopwatch()..start();
    try {
      final request =
          (abortTrigger == null
                ? http.Request('POST', uri)
                : http.AbortableRequest(
                    'POST',
                    uri,
                    abortTrigger: abortTrigger,
                  ))
            ..followRedirects = false
            ..headers.addAll(
              AiService.headers(endpoint.protocol, apiKey: endpoint.apiKey),
            )
            ..headers['x-client-platform'] = ClientPlatform.header
            ..headers['accept'] = 'text/event-stream'
            ..body = jsonEncode(body);
      final response = await _http.send(request).timeout(_aiFirstByteTimeout);
      if (response.statusCode >= 300) {
        final text = await _idleBound(
          _cutAt(response.stream, abortTrigger),
        ).transform(utf8.decoder).join();
        throw ApiException(
          _aiErrorMessage(response.statusCode, text),
          statusCode: response.statusCode,
          details: _failureDetails(
            phase: 'http',
            method: 'POST',
            uri: uri,
            elapsed: clock.elapsed,
            exception: 'HttpStatus',
            statusCode: response.statusCode,
            serverError: text,
            requestId: response.headers['x-request-id'],
          ),
        );
      }
      if (!AiService.isEventStream(response.headers['content-type'])) {
        // 上游不支持流式：整体解码，只发一个完成事件。
        final text = await _idleBound(
          _cutAt(response.stream, abortTrigger),
        ).transform(utf8.decoder).join();
        final decoded = text.isEmpty ? null : jsonDecode(text);
        if (decoded is! Map<String, dynamic>) {
          throw ApiException(
            'AI 接口返回了无法解析的内容',
            details: _failureDetails(
              phase: 'response',
              method: 'POST',
              uri: uri,
              elapsed: clock.elapsed,
            ),
          );
        }
        yield AiTurnCompleted(
          _decodeAiResult({
            'model': selectedModel,
            'message': AiService.decodeReply(endpoint.protocol, decoded),
          }),
        );
        return;
      }
      await for (final event in AiService.decodeEventStream(
        endpoint.protocol,
        _idleBound(_cutAt(response.stream, abortTrigger)),
        model: selectedModel,
      )) {
        // 取消后不再收尾，已显示的增量由调用方保留。
        if (isAborted()) return;
        yield event;
      }
    } on http.RequestAbortedException {
      return;
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error) {
      if (isAborted()) return;
      throw ApiException(
        _failureMessage('timeout', uri.host, osMessage: _osMessageOf(error)),
        details: _failureDetails(
          phase: 'timeout',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: _osMessageOf(error),
        ),
      );
    } on SocketException catch (error) {
      final phase = _phaseOfSocket(error);
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage(phase, uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: phase,
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on HandshakeException catch (error) {
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('tls', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'tls',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on http.ClientException catch (error) {
      if (isAborted()) return;
      final osMessage = _osMessageOf(error);
      throw ApiException(
        _failureMessage('connect', uri.host, osMessage: osMessage),
        details: _failureDetails(
          phase: 'connect',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: error.runtimeType.toString(),
          osMessage: osMessage,
        ),
      );
    } on FormatException {
      throw ApiException(
        'AI 接口返回了无法解析的内容',
        details: _failureDetails(
          phase: 'response',
          method: 'POST',
          uri: uri,
          elapsed: clock.elapsed,
          exception: 'FormatException',
        ),
      );
    } on AiException catch (error) {
      throw ApiException(error.message);
    }
  }

  /// 监听取消。取消后流直接结束，不再收尾。
  static bool Function() _abortFlag(Future<void>? abortTrigger) {
    final state = <bool>[false];
    unawaited(
      abortTrigger?.then<void>(
        (_) => state[0] = true,
        onError: (Object _) => state[0] = true,
      ),
    );
    return () => state[0];
  }

  /// 在 [abortTrigger] 完成时结束 [source]。
  ///
  /// 假客户端与真实的 `AbortableRequest` 都不保证立刻关流，这里统一收尾，
  /// 取消后不留悬挂订阅。
  static Stream<T> _cutAt<T>(Stream<T> source, Future<void>? abortTrigger) {
    if (abortTrigger == null) return source;
    final controller = StreamController<T>();
    late final StreamSubscription<T> subscription;
    var closed = false;
    void finish() {
      if (closed) return;
      closed = true;
      unawaited(subscription.cancel());
      unawaited(controller.close());
    }

    subscription = source.listen(
      (value) {
        if (!closed) controller.add(value);
      },
      onError: (Object error, StackTrace stack) {
        if (closed) return;
        closed = true;
        controller
          ..addError(error, stack)
          ..close();
        unawaited(subscription.cancel());
      },
      onDone: finish,
    );
    unawaited(
      abortTrigger.then<void>((_) => finish(), onError: (Object _) => finish()),
    );
    controller.onCancel = () {
      if (closed) return;
      closed = true;
      unawaited(subscription.cancel());
    };
    return controller.stream;
  }

  /// 任意两段数据之间超过空闲超时就失败结束。
  Stream<List<int>> _idleBound(Stream<List<int>> bytes) => bytes.timeout(
    _aiIdleTimeout,
    onTimeout: (sink) => sink.addError(
      ApiException('AI 接口响应超时', details: const {'phase': 'timeout'}),
    ),
  );

  /// 丢掉响应体并释放连接。回退路径不需要它。
  static Future<void> _drain(Stream<List<int>> stream) async {
    try {
      await stream.drain<void>();
    } catch (_) {
      // 回退路径读失败不影响结果。
    }
  }

  /// 流内 error 事件：状态码与文案按 [_aiErrorMessage] 的规则。
  static ApiException _aiStreamError(Map<String, dynamic> event) {
    final raw = event['status'];
    final status = raw is int && raw >= 100 && raw <= 599 ? raw : 502;
    final error = event['error'];
    final detail = error is String ? error.trim() : '';
    return ApiException(
      detail.isEmpty
          ? _aiErrorMessage(status, '')
          : _aiErrorMessage(status, jsonEncode({'error': detail})),
      statusCode: status,
    );
  }

  /// 上游错误体 → 用户可读文案。不回显响应头，也不回显请求中的密钥。
  static String _aiErrorMessage(int status, String text) {
    var message = 'AI 接口错误（$status）';
    var detail = '';
    try {
      final data = jsonDecode(text);
      if (data is Map && data['error'] is Map) {
        final error = data['error'] as Map;
        if (error['message'] is String) detail = error['message'] as String;
      } else if (data is Map && data['error'] is String) {
        detail = data['error'] as String;
      } else if (data is Map && data['message'] is String) {
        detail = data['message'] as String;
      }
    } on FormatException {
      detail = '';
    }
    if (detail.trim().isNotEmpty) message = '$message：${detail.trim()}';
    return message;
  }

  /// 联网检索：服务端代理搜索，密钥只在服务端。
  ///
  /// 返回 `{provider, results:[{title,url,snippet}]}`。
  Future<Map<String, dynamic>> aiWebSearch(
    String token,
    String query, {
    int limit = 8,
  }) async {
    return await _send(
          'POST',
          '/api/ai/web_search',
          token: token,
          timeout: const Duration(seconds: 30),
          body: {'query': query, 'limit': limit},
        )
        as Map<String, dynamic>;
  }

  /// 联网抓取：服务端做 SSRF 校验与正文提取。
  ///
  /// 返回 `{url, title, text, truncated}`。
  Future<Map<String, dynamic>> aiWebFetch(String token, String url) async {
    return await _send(
          'POST',
          '/api/ai/web_fetch',
          token: token,
          timeout: const Duration(seconds: 30),
          body: {'url': url},
        )
        as Map<String, dynamic>;
  }

  /// 校验并转换一次助手消息；两条链路共用。
  static AiChatResult _decodeAiResult(Map<String, dynamic> data) {
    final model = data['model'];
    final message = data['message'];
    if (model is! String || model.isEmpty || message is! Map) {
      throw ApiException('AI 响应格式无效');
    }
    final usage = data['usage'];
    return AiChatResult.fromMessage(
      model: model,
      message: Map<String, dynamic>.from(message),
      usage: usage is Map ? Map<String, dynamic>.from(usage) : null,
      aiGenerated: data['aiGenerated'] != false,
    );
  }
}

/// 诊断中某一步的结果。失败时写系统原文和异常类型名。
class _ProbeStep {
  const _ProbeStep({
    required this.ok,
    required this.elapsed,
    this.addresses = const [],
    this.osMessage = '',
    this.exception = '',
  });

  final bool ok;
  final Duration elapsed;
  final List<String> addresses;
  final String osMessage;
  final String exception;

  /// 「失败，HandshakeException（6.0 秒）」这种片段。
  String describe() {
    final name = exception.isEmpty ? '未知错误' : exception;
    return '$name（${ApiClient._seconds(elapsed)}）';
  }
}

/// 调试用：dump 响应（release 无操作）。
void debugLogResponse(Object? data) {
  if (kDebugMode) {
    debugPrint('[api] $data');
  }
}
