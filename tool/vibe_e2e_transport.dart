/// 调试上游直连传输：让验收驱动在 `flutter test` 运行器下真实调用模型。
///
/// 只用于 `tool/vibe_e2e.dart` 与 `test/vibe_live_e2e_test.dart`。生产代码走
/// `/api/ai/chat`，客户端从不持有上游密钥；这里之所以需要密钥，是因为验收
/// 要脱离后端中转单独证明协议与工具循环可用。
///
/// 边界：
/// - 密钥只来自调用方传入的环境变量读取结果，本文件不读文件、不写日志。
/// - 网络错误统一转成 `ApiException`，文案里永不拼接请求头与密钥。
/// - 工具调用形状沿用 `AiService.decodeReply`，控制器因此无感。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart' show ApiException;

/// 一次模型回复；字段与 `AiChatResult` 对齐，供验收驱动直接消费。
class VibeDebugChatReply {
  const VibeDebugChatReply({
    required this.model,
    required this.content,
    required this.rawMessage,
  });

  final String model;
  final String content;

  /// OpenAI Chat 形状的助手消息，含 `tool_calls`。
  final Map<String, dynamic> rawMessage;

  List<Map<String, dynamic>> get toolCalls {
    final calls = rawMessage['tool_calls'];
    if (calls is! List) return const [];
    return [
      for (final call in calls)
        if (call is Map) Map<String, dynamic>.from(call),
    ];
  }
}

/// 调试上游直连客户端。
class VibeDebugTransport {
  VibeDebugTransport({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.protocol = AiProtocol.chat,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 180),
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final AiProtocol protocol;
  final Duration timeout;
  final http.Client _client;

  /// 本传输会真实发出请求，因此永远"支持"。
  bool get isSupported => true;

  /// 实际请求的端点，供报告记录（不含密钥）。
  Uri get endpoint => Uri.parse(AiService.endpoint(baseUrl, protocol));

  void close() => _client.close();

  /// 发送一次会话；失败抛 [ApiException]，文案不含密钥。
  Future<VibeDebugChatReply> chat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
  }) async {
    final body = AiService.encodeRequest(
      protocol: protocol,
      model: model.trim(),
      messages: messages,
      tools: tools,
    );
    final request =
        (abortTrigger == null
              ? http.Request('POST', endpoint)
              : http.AbortableRequest(
                  'POST',
                  endpoint,
                  abortTrigger: abortTrigger,
                ))
          ..followRedirects = false
          ..headers.addAll(AiService.headers(protocol, apiKey: apiKey))
          ..body = jsonEncode(body);

    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        '调试上游 ${timeout.inSeconds} 秒无响应',
        details: const {'code': 'DEBUG_TIMEOUT'},
      );
    } on http.RequestAbortedException {
      throw ApiException('请求已取消', details: const {'code': 'ABORTED'});
    } on SocketException catch (error) {
      // 只取操作系统错误码，不拼接 URI。
      throw ApiException(
        '无法连接调试上游：${error.osError?.message ?? '网络不可达'}',
        details: const {'code': 'DEBUG_SOCKET'},
      );
    } on HandshakeException {
      throw ApiException(
        '调试上游 TLS 握手失败，请检查设备时间',
        details: const {'code': 'DEBUG_TLS'},
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        '调试上游连接失败：${_redact(error.message)}',
        details: const {'code': 'DEBUG_CLIENT'},
      );
    }

    final text = utf8.decode(response.bodyBytes);
    Object? data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      data = null;
    }
    if (response.statusCode >= 300) {
      final message = data is Map && data['error'] is Map
          ? (data['error']['message'] ?? data['error'])
          : (data is Map ? data['error'] : null);
      throw ApiException(
        '调试上游返回 ${response.statusCode}：${_redact('$message')}',
        statusCode: response.statusCode,
        details: const {'code': 'DEBUG_UPSTREAM'},
      );
    }
    if (data is! Map<String, dynamic>) {
      throw ApiException(
        '调试上游返回了无法解析的内容',
        details: const {'code': 'DEBUG_DECODE'},
      );
    }
    final Map<String, dynamic> assistant;
    try {
      assistant = AiService.decodeReply(protocol, data);
    } on AiException catch (error) {
      throw ApiException(
        error.message,
        details: const {'code': 'DEBUG_DECODE'},
      );
    }
    final content = assistant['content'];
    return VibeDebugChatReply(
      model: data['model'] is String ? data['model'] as String : model,
      content: content is String ? content : '',
      rawMessage: assistant,
    );
  }

  /// 把可能出现的密钥片段从文案里抹掉，再交给上层或报告。
  String _redact(String value) {
    final key = apiKey.trim();
    if (key.isEmpty) return value;
    return value.replaceAll(key, '[REDACTED]');
  }
}
