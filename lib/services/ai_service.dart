import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

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

  /// 设置界面显示的协议名与端点。
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

  /// 开启思考时 Anthropic 要求的 thinking 预算。
  static const int thinkingBudgetTokens = 8192;

  /// 开启思考时 Anthropic 的 max_tokens 下限。预算必须小于它。
  static const int thinkingMaxTokens = 16384;

  /// 由用户填写的接口地址推导端点。
  ///
  /// - 已含目标路径（如 `/chat/completions`）：原样使用，支持完整自定义端点。
  /// - 以 `/v1` 结尾：追加协议路径。
  /// - 其余：追加 `/v1` 加协议路径。
  static String endpoint(
    String baseUrl, [
    AiProtocol protocol = AiProtocol.chat,
  ]) {
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
  ///
  /// [reasoningEffort] 只在 Chat 与 Responses 协议下发 `reasoning_effort`。
  /// Anthropic Messages 没有等价字段，传了也不写，避免猜一个不存在的参数。
  ///
  /// [stream] 为真时各协议下发 `stream: true`。
  /// [thinking] 为真时 Responses 加 `reasoning.summary`，Messages 加
  /// `thinking` 并抬高 `max_tokens`。Chat 由模型自己决定是否思考，不加参数。
  static Map<String, dynamic> encodeRequest({
    required AiProtocol protocol,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    String? reasoningEffort,
    bool stream = false,
    bool thinking = false,
  }) => switch (protocol) {
    AiProtocol.chat => _encodeChat(
      model,
      messages,
      tools,
      maxTokens,
      reasoningEffort,
      stream,
    ),
    AiProtocol.responses => _encodeResponses(
      model,
      messages,
      tools,
      reasoningEffort,
      stream,
      thinking,
    ),
    AiProtocol.messages => _encodeMessages(
      model,
      messages,
      tools,
      maxTokens,
      stream,
      thinking,
    ),
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

  /// 把协议原生的 SSE 字节流转成统一回合事件。
  ///
  /// [model] 是请求里用的模型名。上游在流里给了模型名时以流里的为准。
  /// 单行 JSON 在主 isolate 解码，服务端已限制单行长度。
  /// `[DONE]`、`message_stop`、`response.completed` 或字节流完结都会收尾，
  /// 每轮只产出一个 [AiTurnCompleted]。
  static Stream<AiTurnEvent> decodeEventStream(
    AiProtocol protocol,
    Stream<List<int>> bytes, {
    required String model,
  }) async* {
    final state = _StreamState(protocol, model);
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      for (final event in state.feed(line)) {
        yield event;
      }
    }
    for (final event in state.finish()) {
      yield event;
    }
  }

  /// 推理强度的统一清洗：只接受短参数值，其余当未设置。
  static String? _effort(String? value) {
    final effort = value?.trim().toLowerCase() ?? '';
    if (effort.isEmpty || effort.length > 16) return null;
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(effort)) return null;
    return effort;
  }

  // ---- OpenAI Chat ----

  static Map<String, dynamic> _encodeChat(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    String? reasoningEffort,
    bool stream,
  ) => <String, dynamic>{
    'model': model,
    'messages': [
      for (final message in messages)
        _chatMessage(message, allowToolCalls: message['role'] == 'assistant'),
    ],
    if (tools != null && tools.isNotEmpty) 'tools': tools,
    'max_tokens': ?maxTokens,
    'reasoning_effort': ?_effort(reasoningEffort),
    if (stream) 'stream': true,
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
      out['tool_calls'] = [for (final call in calls) _openAiCall(call)];
    }
    // 思考模式下带 tools 时，此前的助手消息必须原样回传 reasoning_content。
    // 只有上游返回过思考内容才会有这个字段，因此不会发给不认识它的上游。
    final reasoning = message['reasoning_content'];
    if (role == 'assistant' && reasoning is String && reasoning.isNotEmpty) {
      out['reasoning_content'] = reasoning;
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
      'id': id is String && id.isNotEmpty
          ? id
          : _synthesizeId(function['name']),
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
    final reasoning = message['reasoning_content'];
    return _assistant(
      content is String ? content : '',
      calls.isEmpty ? null : calls,
      reasoning: reasoning is String ? reasoning : '',
    );
  }

  // ---- OpenAI Responses ----

  static Map<String, dynamic> _encodeResponses(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? reasoningEffort,
    bool stream,
    bool thinking,
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
      'reasoning_effort': ?_effort(reasoningEffort),
      if (stream) 'stream': true,
      if (thinking) 'reasoning': const {'summary': 'auto'},
      if (tools != null && tools.isNotEmpty)
        'tools': [for (final tool in tools) _responsesTool(tool)],
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
      if (function['parameters'] is Map) 'parameters': function['parameters'],
    };
  }

  static Map<String, dynamic> _decodeResponses(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is! List) throw const AiException('AI 接口返回了无法解析的内容');
    final texts = <String>[];
    final calls = <Map<String, dynamic>>[];
    final reasoning = StringBuffer();
    for (final item in output) {
      if (item is! Map) continue;
      if (item['type'] == 'reasoning') {
        reasoning.write(_reasoningText(item));
        continue;
      }
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
    return _assistant(
      texts.join('\n'),
      calls.isEmpty ? null : calls,
      reasoning: reasoning.toString(),
    );
  }

  /// Responses 的 reasoning 项：优先取 summary 文本，其次取 content 文本。
  static String _reasoningText(Map item) {
    for (final key in const ['summary', 'content']) {
      final parts = item[key];
      if (parts is! List) continue;
      final buffer = StringBuffer();
      for (final part in parts) {
        if (part is! Map) continue;
        final text = part['text'];
        if (text is String && text.isNotEmpty) buffer.write(text);
      }
      if (buffer.isNotEmpty) return buffer.toString();
    }
    return '';
  }

  // ---- Anthropic Messages ----

  static Map<String, dynamic> _encodeMessages(
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    bool stream,
    bool thinking,
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
          // 开启思考的工具循环要求把 thinking 块放回该消息最前面，签名一起带上。
          final recorded = message['reasoning_blocks'];
          if (recorded is List) {
            for (final block in recorded) {
              final encoded = _reasoningBlock(block);
              if (encoded != null) blocks.add(encoded);
            }
          }
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
    final budget = maxTokens ?? defaultMaxTokens;
    return {
      'model': model,
      'max_tokens': thinking && budget < thinkingMaxTokens
          ? thinkingMaxTokens
          : budget,
      if (system.isNotEmpty) 'system': system.join('\n\n'),
      'messages': merged,
      if (stream) 'stream': true,
      if (thinking)
        'thinking': const {
          'type': 'enabled',
          'budget_tokens': thinkingBudgetTokens,
        },
      if (tools != null && tools.isNotEmpty)
        'tools': [for (final tool in tools) _messagesTool(tool)],
    };
  }

  /// 历史里的思考块 → Anthropic content 块。只认两种类型，其余丢弃。
  static Map<String, dynamic>? _reasoningBlock(Object? block) {
    if (block is! Map) return null;
    if (block['type'] == 'thinking') {
      final thinking = block['thinking'];
      if (thinking is! String || thinking.isEmpty) return null;
      final signature = block['signature'];
      return {
        'type': 'thinking',
        'thinking': thinking,
        if (signature is String && signature.isNotEmpty) 'signature': signature,
      };
    }
    if (block['type'] == 'redacted_thinking') {
      final data = block['data'];
      if (data is! String || data.isEmpty) return null;
      return {'type': 'redacted_thinking', 'data': data};
    }
    return null;
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
    final reasoning = StringBuffer();
    final reasoningBlocks = <Map<String, dynamic>>[];
    for (final block in content) {
      if (block is! Map) continue;
      if (block['type'] == 'thinking' || block['type'] == 'redacted_thinking') {
        final recorded = _reasoningBlock(block);
        if (recorded == null) continue;
        reasoningBlocks.add(recorded);
        final thinking = recorded['thinking'];
        if (thinking is String) reasoning.write(thinking);
        continue;
      }
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
    return _assistant(
      texts.join('\n'),
      calls.isEmpty ? null : calls,
      reasoning: reasoning.toString(),
      reasoningBlocks: reasoningBlocks.isEmpty ? null : reasoningBlocks,
    );
  }

  // ---- 共用 ----

  static Map<String, dynamic> _assistant(
    String content,
    List<Map<String, dynamic>>? calls, {
    String reasoning = '',
    List<Map<String, dynamic>>? reasoningBlocks,
  }) {
    if (content.isEmpty && (calls == null || calls.isEmpty)) {
      throw const AiException('AI 接口返回了无法解析的内容');
    }
    return {
      'role': 'assistant',
      'content': content.isEmpty ? null : content,
      'tool_calls': ?calls,
      if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
      'reasoning_blocks': ?reasoningBlocks,
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
        segments.add(
          AiSegment.code(content.substring(bodyStart), lang: lang, path: path),
        );
        cursor = content.length;
        break;
      }
      segments.add(
        AiSegment.code(
          content.substring(bodyStart, close),
          lang: lang,
          path: path,
        ),
      );
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
      throw const AiException('请先在设置中填写 AI 接口地址');
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
      for (final entry in headers(protocol, apiKey: apiKey).entries) {
        request.headers.set(entry.key, entry.value);
      }
      final body = streaming
          ? {
              ...encodeRequest(
                protocol: protocol,
                model: model.trim(),
                messages: history,
              ),
              'stream': true,
            }
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

  /// 官方转发：经本公司服务器 `/api/ai/chat` 请求。
  ///
  /// 正式版只走这条链路（整改任务书 §3-W3、§4 第 9 条）。
  /// [send] 由调用方提供已登录令牌，负责真正发出请求。
  /// 服务端一次返回完整回复，这里按段产出，保持调用方统一的流接口。
  /// 失败时把 [ApiException] 换成 [AiException]，文案取服务端 message。
  static Stream<String> relayChat({
    required List<({String role, String content})> messages,
    required Future<AiChatResult> Function(List<Map<String, dynamic>>) send,
    String? systemPrompt,
  }) async* {
    final history = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      for (final m in messages) {'role': m.role, 'content': m.content},
    ];
    final AiChatResult result;
    try {
      result = await send(history);
    } on ApiException catch (e) {
      throw AiException(e.message);
    }
    if (result.content.isNotEmpty) yield result.content;
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

/// 一轮 SSE 的增量累积器：只做解码，不做 IO。
///
/// 增量事件只用于显示，完成事件里的结果才是这一轮的权威值。
class _StreamState {
  _StreamState(this.protocol, String model) : _model = model;

  final AiProtocol protocol;
  String _model;

  final StringBuffer _text = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final List<_ToolCall> _tools = [];
  Map<String, dynamic> _usage = const {};
  Map<String, dynamic>? _finalResponse;
  bool _completed = false;

  /// Messages 的内容块按出现顺序保存，收尾时整块交给 `_decodeMessages`。
  final List<Map<String, dynamic>> _blocks = [];
  final Map<int, Map<String, dynamic>> _blocksByIndex = {};
  final Map<int, StringBuffer> _partialJson = {};

  List<AiTurnEvent> feed(String raw) {
    if (_completed) return const [];
    final line = raw.trim();
    if (line.isEmpty || line.startsWith(':') || line.startsWith('event:')) {
      return const [];
    }
    if (!line.startsWith('data:')) return const [];
    final payload = line.substring(5).trim();
    if (payload.isEmpty) return const [];
    if (payload == '[DONE]') return finish();
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    return switch (protocol) {
      AiProtocol.chat => _feedChat(decoded),
      AiProtocol.responses => _feedResponses(decoded),
      AiProtocol.messages => _feedMessages(decoded),
    };
  }

  List<AiTurnEvent> finish() {
    if (_completed) return const [];
    _completed = true;
    return switch (protocol) {
      AiProtocol.chat => [AiTurnCompleted(_chatResult())],
      AiProtocol.responses => [AiTurnCompleted(_responsesResult())],
      AiProtocol.messages => [AiTurnCompleted(_messagesResult())],
    };
  }

  // ---- Chat ----

  List<AiTurnEvent> _feedChat(Map<String, dynamic> data) {
    final events = <AiTurnEvent>[];
    _captureModel(data['model']);
    _mergeUsage(data['usage']);
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return events;
    final first = choices.first;
    if (first is! Map) return events;
    final delta = first['delta'];
    if (delta is! Map) return events;
    final reasoning = _firstText([
      delta['reasoning_content'],
      delta['reasoning'],
    ]);
    if (reasoning.isNotEmpty) {
      _reasoning.write(reasoning);
      events.add(AiReasoningDelta(reasoning));
    }
    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      _text.write(content);
      events.add(AiContentDelta(content));
    }
    final calls = delta['tool_calls'];
    if (calls is! List) return events;
    for (final entry in calls) {
      if (entry is! Map) continue;
      final index = entry['index'];
      final tool = _tool('chat:${index is int ? index : _tools.length}');
      final id = entry['id'];
      if (id is String && id.isNotEmpty) tool.id = id;
      final function = entry['function'];
      if (function is! Map) continue;
      final name = function['name'];
      if (name is String && name.isNotEmpty && tool.name.isEmpty) {
        tool.name = name;
        events.add(AiToolCallStarted(index: tool.position, name: name));
      }
      final arguments = function['arguments'];
      if (arguments is String) tool.arguments.write(arguments);
    }
    return events;
  }

  AiChatResult _chatResult() {
    final calls = <Map<String, dynamic>>[
      for (final tool in _tools)
        if (tool.name.isNotEmpty) tool.toChatCall(),
    ];
    return AiChatResult.fromMessage(
      model: _model,
      message: AiService._assistant(
        _text.toString(),
        calls.isEmpty ? null : calls,
        reasoning: _reasoning.toString(),
      ),
      usage: _usageOrNull,
    );
  }

  // ---- Responses ----

  List<AiTurnEvent> _feedResponses(Map<String, dynamic> data) {
    final events = <AiTurnEvent>[];
    switch (data['type']) {
      case 'response.created':
        final response = data['response'];
        if (response is Map) _captureModel(response['model']);
      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        final delta = data['delta'];
        if (delta is String && delta.isNotEmpty) {
          _reasoning.write(delta);
          events.add(AiReasoningDelta(delta));
        }
      case 'response.output_text.delta':
        final delta = data['delta'];
        if (delta is String && delta.isNotEmpty) {
          _text.write(delta);
          events.add(AiContentDelta(delta));
        }
      case 'response.output_item.added':
        events.addAll(_outputItemAdded(data));
      case 'response.function_call_arguments.delta':
        final delta = data['delta'];
        if (delta is String && delta.isNotEmpty) {
          _tool(_responseSlot(null, data)).arguments.write(delta);
        }
      case 'response.completed':
        final response = data['response'];
        if (response is Map) {
          _captureModel(response['model']);
          _mergeUsage(response['usage']);
          _finalResponse = Map<String, dynamic>.from(response);
        }
        return events..addAll(finish());
      case 'response.failed':
      case 'error':
        throw AiException(_streamError(data));
      default:
        break;
    }
    return events;
  }

  List<AiTurnEvent> _outputItemAdded(Map<String, dynamic> data) {
    final item = data['item'];
    if (item is! Map || item['type'] != 'function_call') return const [];
    final tool = _tool(_responseSlot(item, data));
    final id = _firstText([item['call_id'], item['id']]);
    if (id.isNotEmpty) tool.id = id;
    final arguments = item['arguments'];
    if (arguments is String) tool.arguments.write(arguments);
    final name = item['name'];
    if (name is! String || name.isEmpty || tool.name.isNotEmpty) {
      return const [];
    }
    tool.name = name;
    return [AiToolCallStarted(index: tool.position, name: name)];
  }

  /// 工具调用的稳定键：优先 item id，其次 output_index。
  String _responseSlot(Map? item, Map<String, dynamic> data) {
    final id = _firstText([if (item != null) item['id'], data['item_id']]);
    if (id.isNotEmpty) return 'item:$id';
    final index = data['output_index'];
    return 'output:${index is int ? index : _tools.length}';
  }

  AiChatResult _responsesResult() {
    final finalResponse = _finalResponse;
    final reply = finalResponse != null
        ? AiService._decodeResponses(finalResponse)
        : AiService._decodeResponses({'output': _assembledOutput()});
    // 上游可能不返回 reasoning 项：用已经收到的摘要补齐本轮思考文本。
    if ((reply['reasoning_content'] as String?)?.isNotEmpty != true &&
        _reasoning.isNotEmpty) {
      reply['reasoning_content'] = _reasoning.toString();
    }
    return AiChatResult.fromMessage(
      model: _model,
      message: reply,
      usage: _usageOrNull,
    );
  }

  List<Map<String, dynamic>> _assembledOutput() => [
    if (_reasoning.isNotEmpty)
      {
        'type': 'reasoning',
        'summary': [
          {'type': 'summary_text', 'text': _reasoning.toString()},
        ],
      },
    if (_text.isNotEmpty)
      {
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': _text.toString()},
        ],
      },
    for (final tool in _tools)
      if (tool.name.isNotEmpty)
        {
          'type': 'function_call',
          'call_id': tool.id,
          'name': tool.name,
          'arguments': tool.argumentsText,
        },
  ];

  // ---- Messages ----

  List<AiTurnEvent> _feedMessages(Map<String, dynamic> data) {
    final events = <AiTurnEvent>[];
    switch (data['type']) {
      case 'message_start':
        _messageStart(data);
      case 'content_block_start':
        events.addAll(_contentBlockStart(data));
      case 'content_block_delta':
        events.addAll(_contentBlockDelta(data));
      case 'content_block_stop':
        _contentBlockStop(data);
      case 'message_delta':
        _mergeUsage(data['usage']);
      case 'message_stop':
        return events..addAll(finish());
      case 'error':
        throw AiException(_streamError(data));
      default:
        break;
    }
    return events;
  }

  void _messageStart(Map<String, dynamic> data) {
    final message = data['message'];
    if (message is! Map) return;
    _captureModel(message['model']);
    _mergeUsage(message['usage']);
  }

  List<AiTurnEvent> _contentBlockStart(Map<String, dynamic> data) {
    final index = data['index'];
    final block = data['content_block'];
    if (index is! int || block is! Map) return const [];
    switch (block['type']) {
      case 'thinking':
        final initial = block['thinking'];
        final stored = <String, dynamic>{
          'type': 'thinking',
          'thinking': initial is String ? initial : '',
        };
        _blocksByIndex[index] = stored;
        _blocks.add(stored);
        if (initial is! String || initial.isEmpty) return const [];
        _reasoning.write(initial);
        return [AiReasoningDelta(initial)];
      case 'redacted_thinking':
        final redacted = block['data'];
        final stored = <String, dynamic>{
          'type': 'redacted_thinking',
          'data': redacted is String ? redacted : '',
        };
        _blocksByIndex[index] = stored;
        _blocks.add(stored);
      case 'text':
        final initial = block['text'];
        final stored = <String, dynamic>{
          'type': 'text',
          'text': initial is String ? initial : '',
        };
        _blocksByIndex[index] = stored;
        _blocks.add(stored);
        if (initial is! String || initial.isEmpty) return const [];
        _text.write(initial);
        return [AiContentDelta(initial)];
      case 'tool_use':
        final tool = _tool('block:$index');
        final input = block['input'];
        final stored = <String, dynamic>{
          'type': 'tool_use',
          'id': block['id'] is String ? block['id'] : '',
          'name': block['name'] is String ? block['name'] : '',
          'input': input is Map
              ? Map<String, dynamic>.from(input)
              : const <String, dynamic>{},
        };
        _blocksByIndex[index] = stored;
        _blocks.add(stored);
        final id = block['id'];
        if (id is String && id.isNotEmpty) tool.id = id;
        if (input is Map && input.isNotEmpty) {
          tool.arguments.write(jsonEncode(input));
        }
        final name = block['name'];
        if (name is! String || name.isEmpty) return const [];
        tool.name = name;
        return [AiToolCallStarted(index: tool.position, name: name)];
      default:
        break;
    }
    return const [];
  }

  List<AiTurnEvent> _contentBlockDelta(Map<String, dynamic> data) {
    final index = data['index'];
    final delta = data['delta'];
    if (index is! int || delta is! Map) return const [];
    final target = _blocksByIndex[index];
    switch (delta['type']) {
      case 'thinking_delta':
        final thinking = delta['thinking'];
        if (thinking is! String || thinking.isEmpty) return const [];
        _reasoning.write(thinking);
        if (target != null && target['type'] == 'thinking') {
          target['thinking'] = '${target['thinking']}$thinking';
        }
        return [AiReasoningDelta(thinking)];
      case 'signature_delta':
        final signature = delta['signature'];
        if (signature is String &&
            signature.isNotEmpty &&
            target != null &&
            target['type'] == 'thinking') {
          target['signature'] = signature;
        }
      case 'text_delta':
        final text = delta['text'];
        if (text is! String || text.isEmpty) return const [];
        _text.write(text);
        if (target != null && target['type'] == 'text') {
          target['text'] = '${target['text']}$text';
        }
        return [AiContentDelta(text)];
      case 'input_json_delta':
        final partial = delta['partial_json'];
        if (partial is String && partial.isNotEmpty) {
          (_partialJson[index] ??= StringBuffer()).write(partial);
        }
      default:
        break;
    }
    return const [];
  }

  void _contentBlockStop(Map<String, dynamic> data) {
    final index = data['index'];
    if (index is! int) return;
    final partial = _partialJson.remove(index);
    final block = _blocksByIndex[index];
    if (block == null || block['type'] != 'tool_use') return;
    if (partial == null) return;
    block['input'] = _decodeToolInput(partial.toString());
  }

  AiChatResult _messagesResult() {
    final content = _blocks.isNotEmpty
        ? _blocks
        : <Map<String, dynamic>>[
            if (_text.isNotEmpty) {'type': 'text', 'text': _text.toString()},
            for (final tool in _tools)
              if (tool.name.isNotEmpty)
                {
                  'type': 'tool_use',
                  'id': tool.id,
                  'name': tool.name,
                  'input': _decodeToolInput(tool.argumentsText),
                },
          ];
    return AiChatResult.fromMessage(
      model: _model,
      message: AiService._decodeMessages({'content': content}),
      usage: _usageOrNull,
    );
  }

  static Map<String, dynamic> _decodeToolInput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const {};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // 参数不是完整 JSON 时按空对象，交给上游报校验错误。
    }
    return const {};
  }

  // ---- 共用 ----

  Map<String, dynamic>? get _usageOrNull => _usage.isEmpty ? null : _usage;

  void _captureModel(Object? value) {
    if (value is String && value.isNotEmpty) _model = value;
  }

  void _mergeUsage(Object? usage) {
    if (usage is! Map) return;
    _usage = {..._usage, ...Map<String, dynamic>.from(usage)};
  }

  _ToolCall _tool(String slot) {
    for (final tool in _tools) {
      if (tool.slot == slot) return tool;
    }
    final tool = _ToolCall(slot, _tools.length);
    _tools.add(tool);
    return tool;
  }

  static String _firstText(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  static String _streamError(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    if (data['message'] is String) return data['message'] as String;
    return 'AI 接口返回了无法解析的内容';
  }
}

/// 一个正在累积的工具调用。[position] 是本轮内的出现顺序。
class _ToolCall {
  _ToolCall(this.slot, this.position);

  final String slot;
  final int position;
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  String get argumentsText => arguments.isEmpty ? '{}' : arguments.toString();

  Map<String, dynamic> toChatCall() => {
    'id': id.isEmpty ? AiService._synthesizeId(name) : id,
    'type': 'function',
    'function': {'name': name, 'arguments': argumentsText},
  };
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
