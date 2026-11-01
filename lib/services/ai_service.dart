import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// AI 回复中的一段内容：纯文本或代码块。
class AiSegment {
  const AiSegment.text(this.text)
      : isCode = false,
        code = null,
        lang = null,
        path = null;
  const AiSegment.code(this.code, {this.lang, this.path})
      : isCode = true,
        text = null;

  final bool isCode;
  final String? text;
  final String? code;

  /// 代码块语言（```python:src/main.py 的 python）。
  final String? lang;

  /// 代码块标注的目标文件路径（相对项目根），null 表示未指定。
  final String? path;
}

/// 上游接口协议。内部对话历史统一使用 OpenAI Chat 形状，
/// 由 [AiService.encodeRequest] / [AiService.decodeReply] 双向转换。
enum AiProtocol {
  /// `POST {base}/v1/chat/completions`。
  chat('chat'),

  /// `POST {base}/v1/responses`。
  responses('responses'),

  /// `POST {base}/v1/messages`（Anthropic Messages）。
  messages('messages');

  const AiProtocol(this.id);

  /// 持久化标识，写入 settings.json 后不再变更。
  final String id;

  /// 设置界面展示的协议名与端点。
  String get label => switch (this) {
    AiProtocol.chat => 'OpenAI Chat (/chat/completions)',
    AiProtocol.responses => 'OpenAI Responses (/responses)',
    AiProtocol.messages => 'Anthropic Messages (/messages)',
  };

  /// 端点相对路径（拼在推导出的根地址之后）。
  String get path => switch (this) {
    AiProtocol.chat => '/chat/completions',
    AiProtocol.responses => '/responses',
    AiProtocol.messages => '/messages',
  };

  /// 解析持久化标识；未知或空值回落到 Chat，保证旧设置可用。
  static AiProtocol parse(String? value) => switch (value) {
    'responses' => AiProtocol.responses,
    'messages' => AiProtocol.messages,
    _ => AiProtocol.chat,
  };
}

/// AI 服务：三种接口协议的端点推导、请求编码与回复解码。
///
/// 编解码是纯函数，不做 IO，也不持有密钥。
abstract final class AiService {
  static const Duration _timeout = Duration(seconds: 180);

  /// Anthropic Messages 必须带 max_tokens；未指定时用这个值。
  static const int defaultMaxTokens = 4096;

  /// 由用户填写的接口地址推导端点。
  ///
  /// - 已含目标路径（如 `/chat/completions`）：原样使用，支持完整自定义端点。
  /// - 以 `/v1` 结尾：追加协议路径。
  /// - 其余：追加 `/v1` 加协议路径。
  static String endpoint(String baseUrl, [AiProtocol protocol = AiProtocol.chat]) {
    var base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return base;
    final lowered = base.toLowerCase();
    if (lowered.endsWith(protocol.path) || lowered.endsWith('/v1/messages')) {
      return base;
    }
    if (lowered.endsWith('/v1')) return '$base${protocol.path}';
    return '$base/v1${protocol.path}';
  }

  /// [chat] 协议下的兼容名，保持既有调用方不变。
  static String endpointFor(
    String baseUrl, [
    AiProtocol protocol = AiProtocol.chat,
  ]) => endpoint(baseUrl, protocol);

  /// 一次请求需要设置的请求头；密钥为空时不发 authorization。
  ///
  /// 只设置协议必需字段。调用方不得把这里的值写入日志。
  static Map<String, String> headers(
    AiProtocol protocol, {
    String apiKey = '',
  }) {
    final key = apiKey.trim();
    return {
      'content-type': 'application/json',
      if (key.isNotEmpty) 'authorization': 'Bearer $key',
      if (protocol == AiProtocol.messages) 'anthropic-version': '2023-06-01',
    };
  }

  /// 把内部历史（OpenAI Chat 形状）编码成本协议的请求体。
  ///
  /// 输入消息只含 `role`、`content`、`tool_calls`、`tool_call_id`，
  /// 与 `/api/ai/chat` 接受的结构一致。
  static Map<String, dynamic> encodeRequest({
    required AiProtocol protocol,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
  }) => switch (protocol) {
    AiProtocol.chat => _encodeChat(model, messages, tools, maxTokens),
    AiProtocol.responses => _encodeResponses(model, messages, tools),
    AiProtocol.messages => _encodeMessages(model, messages, tools, maxTokens),
  };

  /// 把本协议的回复解码成内部助手消息。
  ///
  /// 返回 `{role: 'assistant', content, tool_calls?}`，与中转服务一致。
  /// 无法识别的结构抛 [AiException]。
  static Map<String, dynamic> decodeReply(
    AiProtocol protocol,
    Map<String, dynamic> data,
  ) => switch (protocol) {
    AiProtocol.chat => _decodeChat(data),
    AiProtocol.responses => _decodeResponses(data),
    AiProtocol.messages => _decodeMessages(data),
  };

  /// 由响应头选取响应体解析方式，供界面提示使用。
  static bool isEventStream(String? contentType) =>
      contentType != null && contentType.contains('text/event-stream');

  // ---- OpenAI Chat ----

  static Map<String, dynamic> _encodeChat(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
  ) => <String, dynamic>{
    'model': model,
    'messages': [
      for (final message in messages)
        _chatMessage(message, allowToolCalls: message['role'] == 'assistant'),
    ],
    if (tools != null && tools.isNotEmpty) 'tools': tools,
    'max_tokens': ?maxTokens,
  };

  static Map<String, dynamic> _chatMessage(
    Map<String, dynamic> message, {
    required bool allowToolCalls,
  }) {
    final role = _role(message['role']);
    final content = message['content'];
    final out = <String, dynamic>{
      'role': role,
      'content': content is String ? content : null,
    };
    if (role == 'tool') {
      final id = message['tool_call_id'];
      out['tool_call_id'] = id is String ? id : '';
      out['content'] = content is String ? content : '';
      return out;
    }
    final calls = message['tool_calls'];
    if (allowToolCalls && calls is List && calls.isNotEmpty) {
      out['tool_calls'] = [
        for (final call in calls) _openAiCall(call),
      ];
    }
    return out;
  }

  static Map<String, dynamic> _openAiCall(Object? call) {
    final map = call is Map ? call : const {};
    final function = map['function'] is Map
        ? Map<String, dynamic>.from(map['function'] as Map)
        : const <String, dynamic>{};
    final id = map['id'];
    return {
      'id': id is String && id.isNotEmpty ? id : _synthesizeId(function['name']),
      'type': 'function',
      'function': {
        'name': function['name'] is String ? function['name'] as String : '',
        'arguments': function['arguments'] is String
            ? function['arguments'] as String
            : '{}',
      },
    };
  }

  static Map<String, dynamic> _decodeChat(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiException('AI 接口返回了无法解析的内容');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    if (message is! Map) throw const AiException('AI 接口返回了无法解析的内容');
    final content = message['content'];
    if (content != null && content is! String) {
      throw const AiException('AI 接口返回了无法解析的内容');
    }
    final raw = message['tool_calls'];
    final calls = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final call in raw) {
        if (call is! Map) continue;
        final function = call['function'];
        if (function is! Map) continue;
        final name = function['name'];
        final arguments = function['arguments'];
        if (name is! String || name.isEmpty) continue;
        final id = call['id'];
        calls.add({
          'id': id is String && id.isNotEmpty ? id : _synthesizeId(name),
          'type': 'function',
          'function': {
            'name': name,
            'arguments': arguments is String ? arguments : '{}',
          },
        });
      }
    }
    return _assistant(
      content is String ? content : '',
      calls.isEmpty ? null : calls,
    );
  }

  // ---- OpenAI Responses ----

  static Map<String, dynamic> _encodeResponses(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  ) {
    final system = <String>[];
    final input = <Map<String, dynamic>>[];
    // 实测约束：newapi 的 Responses 兼容层拒绝带 type 的内容块
    // （`does not support input.N.content.M.content_type`），只接受字符串
    // content，加独立的 function_call / function_call_output 条目。
    // 真实 OpenAI Responses 也接受字符串 content，两边因此都兼容。
    for (final message in messages) {
      final role = _role(message['role']);
      final text = message['content'] is String
          ? message['content'] as String
          : '';
      switch (role) {
        case 'system':
          if (text.isNotEmpty) system.add(text);
        case 'user':
          input.add({'role': 'user', 'content': text});
        case 'assistant':
          if (text.isNotEmpty) {
            input.add({'role': 'assistant', 'content': text});
          }
          final calls = message['tool_calls'];
          if (calls is List) {
            for (final call in calls) {
              final encoded = _openAiCall(call);
              final function = encoded['function'] as Map<String, dynamic>;
              input.add({
                'type': 'function_call',
                'call_id': encoded['id'],
                'name': function['name'],
                'arguments': function['arguments'],
              });
            }
          }
        case 'tool':
          input.add({
            'type': 'function_call_output',
            'call_id': message['tool_call_id'] is String
                ? message['tool_call_id'] as String
                : '',
            'output': text,
          });
      }
    }
    return {
      'model': model,
      'input': input,
      if (system.isNotEmpty) 'instructions': system.join('\n\n'),
      'store': false,
      if (tools != null && tools.isNotEmpty)
        'tools': [
          for (final tool in tools) _responsesTool(tool),
        ],
    };
  }

  /// Chat 工具定义 `{type, function:{...}}` → Responses 顶层扁平定义。
  static Map<String, dynamic> _responsesTool(Map<String, dynamic> tool) {
    final function = tool['function'] is Map
        ? Map<String, dynamic>.from(tool['function'] as Map)
        : tool;
    return {
      'type': 'function',
      'name': function['name'],
      if (function['description'] is String)
        'description': function['description'],
      if (function['parameters'] is Map)
        'parameters': function['parameters'],
    };
  }

  static Map<String, dynamic> _decodeResponses(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is! List) throw const AiException('AI 接口返回了无法解析的内容');
    final texts = <String>[];
    final calls = <Map<String, dynamic>>[];
    for (final item in output) {
      if (item is! Map) continue;
      if (item['type'] == 'function_call') {
        final name = item['name'];
        if (name is! String || name.isEmpty) continue;
        final arguments = item['arguments'];
        final callId = item['call_id'] is String
            ? item['call_id'] as String
            : (item['id'] is String ? item['id'] as String : '');
        calls.add({
          'id': callId.isEmpty ? _synthesizeId(name) : callId,
          'type': 'function',
          'function': {
            'name': name,
            'arguments': arguments is String ? arguments : '{}',
          },
        });
        continue;
      }
      if (item['type'] != 'message') continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map) continue;
        if (part['type'] != 'output_text' && part['type'] != 'text') continue;
        final text = part['text'];
        if (text is String && text.isNotEmpty) texts.add(text);
      }
    }
    return _assistant(texts.join('\n'), calls.isEmpty ? null : calls);
  }

  // ---- Anthropic Messages ----

  static Map<String, dynamic> _encodeMessages(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
  ) {
    final system = <String>[];
    // Anthropic 要求 user/assistant 交替，相邻同角色消息必须合并。
    final merged = <Map<String, dynamic>>[];
    void push(String role, List<Map<String, dynamic>> blocks) {
      if (blocks.isEmpty) return;
      final last = merged.isEmpty ? null : merged.last;
      if (last != null && last['role'] == role) {
        (last['content'] as List).addAll(blocks);
      } else {
        merged.add({'role': role, 'content': blocks});
      }
    }

    for (final message in messages) {
      final role = _role(message['role']);
      final text = message['content'] is String
          ? message['content'] as String
          : '';
      switch (role) {
        case 'system':
          if (text.isNotEmpty) system.add(text);
        case 'user':
          push('user', [
            {'type': 'text', 'text': text},
          ]);
        case 'assistant':
          final blocks = <Map<String, dynamic>>[];
          if (text.isNotEmpty) blocks.add({'type': 'text', 'text': text});
          final calls = message['tool_calls'];
          if (calls is List) {
            for (final call in calls) {
              final encoded = _openAiCall(call);
              final function = encoded['function'] as Map<String, dynamic>;
              blocks.add({
                'type': 'tool_use',
                'id': encoded['id'],
                'name': function['name'],
                'input': _decodeArguments(function['arguments'] as String),
              });
            }
          }
          push('assistant', blocks);
        case 'tool':
          push('user', [
            {
              'type': 'tool_result',
              'tool_use_id': message['tool_call_id'] is String
                  ? message['tool_call_id'] as String
                  : '',
              'content': text,
            },
          ]);
      }
    }
    // Anthropic 要求首条消息是 user。
    if (merged.isNotEmpty && merged.first['role'] != 'user') {
      merged.insert(0, {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '继续。'},
        ],
      });
    }
    return {
      'model': model,
      'max_tokens': maxTokens ?? defaultMaxTokens,
      if (system.isNotEmpty) 'system': system.join('\n\n'),
      'messages': merged,
      if (tools != null && tools.isNotEmpty)
        'tools': [
          for (final tool in tools) _messagesTool(tool),
        ],
    };
  }

  /// Chat 工具定义 → Anthropic `input_schema` 定义。
  static Map<String, dynamic> _messagesTool(Map<String, dynamic> tool) {
    final function = tool['function'] is Map
        ? Map<String, dynamic>.from(tool['function'] as Map)
        : tool;
    return {
      'name': function['name'],
      if (function['description'] is String)
        'description': function['description'],
      'input_schema': function['parameters'] is Map
          ? function['parameters']
          : const {'type': 'object', 'properties': <String, dynamic>{}},
    };
  }

  static Map<String, dynamic> _decodeMessages(Map<String, dynamic> data) {
    final content = data['content'];
    if (content is! List) throw const AiException('AI 接口返回了无法解析的内容');
    final texts = <String>[];
    final calls = <Map<String, dynamic>>[];
    for (final block in content) {
      if (block is! Map) continue;
      if (block['type'] == 'text') {
        final text = block['text'];
        if (text is String && text.isNotEmpty) texts.add(text);
        continue;
      }
      if (block['type'] != 'tool_use') continue;
      final name = block['name'];
      if (name is! String || name.isEmpty) continue;
      final id = block['id'] is String ? block['id'] as String : '';
      final input = block['input'];
      calls.add({
        'id': id.isEmpty ? _synthesizeId(name) : id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': jsonEncode(input is Map ? input : const {}),
        },
      });
    }
    return _assistant(texts.join('\n'), calls.isEmpty ? null : calls);
  }

  // ---- 共用 ----

  static Map<String, dynamic> _assistant(
    String content,
    List<Map<String, dynamic>>? calls,
  ) {
    if (content.isEmpty && (calls == null || calls.isEmpty)) {
      throw const AiException('AI 接口返回了无法解析的内容');
    }
    return {
      'role': 'assistant',
      'content': content.isEmpty ? null : content,
      'tool_calls': ?calls,
    };
  }

  static String _role(Object? value) =>
      const {'system', 'user', 'assistant', 'tool'}.contains(value)
      ? value! as String
      : 'user';

  static int _syntheticSequence = 0;

  /// 上游未提供工具调用 id 时生成稳定可回的 id。
  static String _synthesizeId(Object? name) {
    final label = name is String && name.isNotEmpty ? name : 'tool';
    _syntheticSequence++;
    return 'call_${label}_$_syntheticSequence';
  }

  static Map<String, dynamic> _decodeArguments(String arguments) {
    if (arguments.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // 参数不是 JSON 对象时按空对象转发，上游会给出真实校验错误。
    }
    return const {};
  }

  // ---- 代码块解析（AI 助手面板）----

  /// 解析回复中的 ```代码块```，提取标注的文件路径。
  /// 支持三种栅栏标注：```lang:path、```path.ext、```lang。
  static List<AiSegment> parseSegments(String content) {
    final segments = <AiSegment>[];
    final fence = RegExp(r'^```(.*)$', multiLine: true);
    var cursor = 0;
    while (true) {
      final open = fence.firstMatch(content.substring(cursor));
      if (open == null) break;
      final textStart = cursor + open.start;
      if (textStart > cursor) {
        segments.add(AiSegment.text(content.substring(cursor, textStart)));
      }
      final info = open.group(1)!.trim();
      final lang = _fenceLang(info);
      final path = _fencePath(info);
      final bodyStart = cursor + open.end + 1; // 跳过栅栏行后的换行
      final close = content.indexOf('```', bodyStart);
      if (close < 0) {
        // 未闭合：剩余内容都算代码。
        segments.add(AiSegment.code(
          content.substring(bodyStart),
          lang: lang,
          path: path,
        ));
        cursor = content.length;
        break;
      }
      segments.add(AiSegment.code(
        content.substring(bodyStart, close),
        lang: lang,
        path: path,
      ));
      cursor = close + 3;
    }
    if (cursor < content.length) {
      segments.add(AiSegment.text(content.substring(cursor)));
    }
    return segments;
  }

  // ---- 直接模式：流式文本（Chat 协议）----

  /// 流式对话：逐段产出模型增量文本。
  ///
  /// [baseUrl]/[apiKey]/[model] 来自用户设置；[messages] 为完整对话历史。
  /// 仅 Chat 协议支持增量流；Responses / Messages 退化为一次非流式读取。
  static Stream<String> chat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<({String role, String content})> messages,
    String? systemPrompt,
    AiProtocol protocol = AiProtocol.chat,
  }) async* {
    final endpoint = endpointFor(baseUrl, protocol);
    if (endpoint.isEmpty) {
      throw const AiException('请先在设置中配置 AI 接口地址');
    }
    final uri = Uri.parse(endpoint);
    final history = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      for (final m in messages) {'role': m.role, 'content': m.content},
    ];
    final streaming = protocol == AiProtocol.chat;
    try {
      final request = await HttpClient()
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      for (final entry
          in headers(protocol, apiKey: apiKey).entries) {
        request.headers.set(entry.key, entry.value);
      }
      final body = streaming
          ? {...encodeRequest(
              protocol: protocol,
              model: model.trim(),
              messages: history,
            ), 'stream': true}
          : encodeRequest(
              protocol: protocol,
              model: model.trim(),
              messages: history,
            );
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      if (response.statusCode >= 400) {
        final text = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        throw AiException(_errorMessage(response.statusCode, text));
      }

      if (!streaming ||
          !isEventStream(response.headers.contentType?.mimeType)) {
        // 非流式响应：整体 JSON，按协议解码。
        final text = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_timeout);
        final data = jsonDecode(text);
        if (data is! Map<String, dynamic>) {
          throw const AiException('AI 接口返回了无法解析的内容');
        }
        final reply = decodeReply(protocol, data);
        final content = reply['content'];
        if (content is String && content.isNotEmpty) yield content;
        return;
      }

      await for (final raw
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        var line = raw.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;
        var payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        try {
          final data = jsonDecode(payload);
          final choices = data['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = (choices[0] as Map)['delta'];
            if (delta is Map && delta['content'] is String) {
              final piece = delta['content'] as String;
              if (piece.isNotEmpty) yield piece;
            }
          }
        } on FormatException {
          continue;
        }
      }
    } on SocketException catch (e) {
      throw AiException('无法连接 AI 接口：${e.message}');
    } on TimeoutException {
      throw AiException('AI 接口请求超时');
    } on HttpException catch (e) {
      throw AiException('网络错误：${e.message}');
    } on FormatException {
      throw AiException('AI 接口返回了无法解析的内容');
    }
  }

  /// 错误响应体 → 用户可读文案。不回显响应头或密钥。
  static String _errorMessage(int status, String text) {
    var message = '接口错误（$status）';
    try {
      final data = jsonDecode(text);
      if (data is Map && data['error'] is Map) {
        final inner = data['error'] as Map;
        if (inner['message'] is String) message = '${inner['message']}';
      } else if (data is Map && data['message'] is String) {
        message = data['message'] as String;
      } else if (data is Map && data['error'] is String) {
        message = data['error'] as String;
      }
    } on FormatException {
      if (text.trim().isNotEmpty) message = text.trim();
    }
    return message;
  }
}

class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 栅栏信息行 ```lang:path → 语言部分。
String _fenceLang(String info) {
  if (info.contains(':')) {
    return info.substring(0, info.indexOf(':')).trim();
  }
  return info;
}

/// 栅栏信息行 ```lang:path → 路径部分（无则 null）。
String? _fencePath(String info) {
  if (info.contains(':')) {
    final value = info.substring(info.indexOf(':') + 1).trim();
    return value.isEmpty ? null : value;
  }
  if (RegExp(r'\.[A-Za-z0-9]+$').hasMatch(info)) return info;
  return null;
}
