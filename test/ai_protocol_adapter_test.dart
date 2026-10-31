// Protocol adapter fixtures. Reply shapes are trimmed copies of real responses
// from the debug upstream, so a shape change in any protocol breaks a test.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/ai_service.dart';

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': '搜索互联网',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  },
];

/// History after one completed tool round, in the internal Chat shape.
List<Map<String, dynamic>> _history() => [
  {'role': 'system', 'content': '你是助手。'},
  {'role': 'user', 'content': '用 web_search 查今天新闻。'},
  {
    'role': 'assistant',
    'content': '我来搜索。',
    'tool_calls': [
      {
        'id': 'call_00_demo',
        'type': 'function',
        'function': {
          'name': 'web_search',
          'arguments': '{"query": "今日新闻"}',
        },
      },
    ],
  },
  {
    'role': 'tool',
    'tool_call_id': 'call_00_demo',
    'content': '1. 示例标题\n   https://example.com\n   示例摘要',
  },
];

/// Real `/chat/completions` reply (trimmed).
const _chatReply = {
  'id': 'chatcmpl-1',
  'object': 'chat.completion',
  'choices': [
    {
      'index': 0,
      'message': {
        'role': 'assistant',
        'content': '先搜索。',
        'tool_calls': [
          {
            'id': 'call_00_PEbyMGIiJmCAjKbpxGMZ8615',
            'type': 'function',
            'function': {
              'name': 'web_search',
              'arguments': '{"query": "今日新闻 2026年"}',
            },
          },
        ],
      },
      'finish_reason': 'tool_calls',
    },
  ],
};

/// Real `/responses` reply (trimmed).
const _responsesReply = {
  'id': 'resp_00b50dac',
  'object': 'response',
  'status': 'completed',
  'output': [
    {
      'id': 'msg_af08b0f8',
      'type': 'message',
      'status': 'completed',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': '我会先搜索今天的新闻。', 'annotations': []},
      ],
    },
    {
      'id': 'fc_4077f509',
      'type': 'function_call',
      'status': 'completed',
      'call_id': 'call_00_D7yXuhf7JXW6nUTlJCbc8118',
      'name': 'web_search',
      'arguments': '{"query": "今日新闻 头条"}',
    },
  ],
  'usage': {'input_tokens': 277, 'output_tokens': 45, 'total_tokens': 322},
};

/// Real `/v1/messages` reply (trimmed).
const _messagesReply = {
  'id': '528fcd6e88c34a81b00a56fdc928647e',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': '结果里只有示例数据，我换个查询。'},
  ],
  'stop_reason': 'end_turn',
  'usage': {'input_tokens': 332, 'output_tokens': 148},
};

const _messagesToolReply = {
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': '搜索中。'},
    {
      'type': 'tool_use',
      'id': 'toolu_01abc',
      'name': 'web_search',
      'input': {'query': 'Flutter 教程', 'limit': 3},
    },
  ],
  'stop_reason': 'tool_use',
};

void main() {
  group('AiProtocol', () {
    test('ids and labels are stable', () {
      expect(AiProtocol.values.map((p) => p.id), [
        'chat',
        'responses',
        'messages',
      ]);
      expect(AiProtocol.chat.label, 'OpenAI Chat (/chat/completions)');
      expect(AiProtocol.responses.label, 'OpenAI Responses (/responses)');
      expect(AiProtocol.messages.label, 'Anthropic Messages (/messages)');
    });

    test('parse falls back to chat for unknown and null', () {
      expect(AiProtocol.parse('responses'), AiProtocol.responses);
      expect(AiProtocol.parse('messages'), AiProtocol.messages);
      expect(AiProtocol.parse('chat'), AiProtocol.chat);
      expect(AiProtocol.parse('anthropic'), AiProtocol.chat);
      expect(AiProtocol.parse(null), AiProtocol.chat);
      expect(AiProtocol.parse(''), AiProtocol.chat);
    });

    test('endpoint derivation per protocol', () {
      expect(
        AiService.endpointFor('https://x.com', AiProtocol.responses),
        'https://x.com/v1/responses',
      );
      expect(
        AiService.endpointFor('https://x.com/v1/', AiProtocol.messages),
        'https://x.com/v1/messages',
      );
      expect(
        AiService.endpointFor(
          'https://x.com/v1/chat/completions',
          AiProtocol.chat,
        ),
        'https://x.com/v1/chat/completions',
      );
      expect(
        AiService.endpointFor('http://127.0.0.1:11434/v1', AiProtocol.chat),
        'http://127.0.0.1:11434/v1/chat/completions',
      );
    });

    test('headers add anthropic-version only for messages', () {
      expect(
        AiService.headers(AiProtocol.chat, apiKey: 'k')['anthropic-version'],
        isNull,
      );
      expect(
        AiService.headers(AiProtocol.messages)['anthropic-version'],
        '2023-06-01',
      );
      expect(AiService.headers(AiProtocol.chat, apiKey: ' ').keys, [
        'content-type',
      ]);
    });
  });

  group('chat protocol', () {
    test('encodes history unchanged', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.chat,
        model: 'deepseek-v4.1-flash',
        messages: _history(),
        tools: _tools,
      );
      expect(body['model'], 'deepseek-v4.1-flash');
      expect(body['max_tokens'], isNull);
      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.map((m) => m['role']), [
        'system',
        'user',
        'assistant',
        'tool',
      ]);
      expect(messages[2]['tool_calls'][0]['id'], 'call_00_demo');
      expect(messages[3]['tool_call_id'], 'call_00_demo');
      expect((body['tools'] as List).single['type'], 'function');
    });

    test('decodes a real tool-call reply', () {
      final reply = AiService.decodeReply(AiProtocol.chat, _chatReply);
      expect(reply['role'], 'assistant');
      expect(reply['content'], '先搜索。');
      final call = (reply['tool_calls'] as List).single as Map;
      expect(call['id'], 'call_00_PEbyMGIiJmCAjKbpxGMZ8615');
      expect(call['function']['name'], 'web_search');
      expect(
        jsonDecode(call['function']['arguments'] as String),
        {'query': '今日新闻 2026年'},
      );
    });

    test('rejects unusable replies', () {
      expect(
        () => AiService.decodeReply(AiProtocol.chat, {'choices': []}),
        throwsA(isA<AiException>()),
      );
      expect(
        () => AiService.decodeReply(AiProtocol.chat, {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': null},
            },
          ],
        }),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('responses protocol', () {
    test('encodes input items, instructions and flat tools', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.responses,
        model: 'deepseek-v4.1-flash',
        messages: _history(),
        tools: _tools,
      );
      expect(body['instructions'], '你是助手。');
      expect(body['store'], false);
      expect(body.containsKey('max_tokens'), isFalse);
      final input = (body['input'] as List).cast<Map>();
      expect(input.first['role'], 'user');
      expect(input.first['content'][0]['type'], 'input_text');
      final assistant = input[1];
      expect(assistant['content'][0]['type'], 'output_text');
      final call = assistant['content'][1];
      expect(call['type'], 'function_call');
      expect(call['call_id'], 'call_00_demo');
      expect(call['name'], 'web_search');
      expect(call['arguments'], '{"query": "今日新闻"}');
      expect(input.last['type'], 'function_call_output');
      expect(input.last['call_id'], 'call_00_demo');
      final tool = (body['tools'] as List).single as Map;
      expect(tool['name'], 'web_search');
      expect(tool.containsKey('function'), isFalse);
      expect(tool['parameters']['required'], ['query']);
    });

    test('decodes a real replies with text and function_call', () {
      final reply = AiService.decodeReply(AiProtocol.responses, _responsesReply);
      expect(reply['content'], '我会先搜索今天的新闻。');
      final call = (reply['tool_calls'] as List).single as Map;
      expect(call['id'], 'call_00_D7yXuhf7JXW6nUTlJCbc8118');
      expect(call['function']['arguments'], '{"query": "今日新闻 头条"}');
    });

    test('decodes a text-only reply without tool_calls key', () {
      final reply = AiService.decodeReply(AiProtocol.responses, {
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '完成。'},
            ],
          },
        ],
      });
      expect(reply['content'], '完成。');
      expect(reply.containsKey('tool_calls'), isFalse);
    });

    test('rejects a reply without usable output', () {
      expect(
        () => AiService.decodeReply(AiProtocol.responses, {'output': []}),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('messages protocol', () {
    test('hoists system, maps tool_use and merges tool results', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'deepseek-v4.1-flash',
        messages: _history(),
        tools: _tools,
      );
      expect(body['system'], '你是助手。');
      expect(body['max_tokens'], AiService.defaultMaxTokens);
      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
      expect(messages[0]['content'][0]['type'], 'text');
      final assistant = messages[1]['content'] as List;
      expect(assistant[0], {'type': 'text', 'text': '我来搜索。'});
      final use = assistant[1] as Map;
      expect(use['type'], 'tool_use');
      expect(use['id'], 'call_00_demo');
      // Anthropic 要对象形式的 input，这里必须是解码后的 Map。
      expect(use['input'], {'query': '今日新闻'});
      final result = (messages[2]['content'] as List).single as Map;
      expect(result['type'], 'tool_result');
      expect(result['tool_use_id'], 'call_00_demo');
      expect(result['content'], contains('示例标题'));
      final tool = (body['tools'] as List).single as Map;
      expect(tool['name'], 'web_search');
      expect(tool['input_schema']['required'], ['query']);
    });

    test('merges consecutive same-role messages and starts with user', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: [
          {
            'role': 'assistant',
            'content': '开场白',
          },
          {'role': 'user', 'content': 'a'},
          {'role': 'user', 'content': 'b'},
          {'role': 'tool', 'tool_call_id': 't1', 'content': 'r1'},
          {'role': 'tool', 'tool_call_id': 't2', 'content': 'r2'},
        ],
      );
      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.first['role'], 'user');
      // 补位 user 后：起点 user，再被 assistant 打断，末尾两条 tool_result 合成
      // 一个 user。同角色相邻消息在每一段内部合并。
      expect(messages.map((m) => m['role']), [
        'user',
        'assistant',
        'user',
      ]);
      final blocks = messages.last['content'] as List;
      expect(blocks.where((b) => b['type'] == 'text').length, 2);
      expect(blocks.where((b) => b['type'] == 'tool_result').length, 2);
    });

    test('respects an explicit max_tokens', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: const [],
        maxTokens: 128,
      );
      expect(body['max_tokens'], 128);
    });

    test('decodes a real text reply', () {
      final reply = AiService.decodeReply(
        AiProtocol.messages,
        _messagesReply,
      );
      expect(reply['content'], contains('示例数据'));
      expect(reply.containsKey('tool_calls'), isFalse);
      expect(reply['role'], 'assistant');
    });

    test('decodes a tool_use reply into JSON arguments', () {
      final reply = AiService.decodeReply(
        AiProtocol.messages,
        _messagesToolReply,
      );
      expect(reply['content'], '搜索中。');
      final call = (reply['tool_calls'] as List).single as Map;
      expect(call['id'], 'toolu_01abc');
      expect(call['function']['name'], 'web_search');
      expect(jsonDecode(call['function']['arguments'] as String), {
        'query': 'Flutter 教程',
        'limit': 3,
      });
    });

    test('rejects a reply with an empty content list', () {
      expect(
        () => AiService.decodeReply(AiProtocol.messages, {'content': []}),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('cross-protocol round trip', () {
    test('each protocol decodes to the internal assistant shape', () {
      for (final protocol in AiProtocol.values) {
        final data = switch (protocol) {
          AiProtocol.chat => _chatReply,
          AiProtocol.responses => _responsesReply,
          AiProtocol.messages => _messagesToolReply,
        };
        final reply = AiService.decodeReply(protocol, data);
        expect(reply['role'], 'assistant', reason: protocol.id);
        final calls = reply['tool_calls'];
        expect(calls, isA<List>(), reason: protocol.id);
        final call = (calls as List).first as Map;
        expect(call['id'], isA<String>(), reason: protocol.id);
        expect(call['type'], 'function', reason: protocol.id);
        expect(
          jsonDecode(call['function']['arguments'] as String),
          isA<Map>(),
          reason: protocol.id,
        );
      }
    });

    test('decoded history re-encodes without losing the tool round', () {
      for (final protocol in AiProtocol.values) {
        final reply = AiService.decodeReply(
          protocol,
          switch (protocol) {
            AiProtocol.chat => _chatReply,
            AiProtocol.responses => _responsesReply,
            AiProtocol.messages => _messagesToolReply,
          },
        );
        final call = (reply['tool_calls'] as List).first as Map;
        final followUp = [
          for (final message in _history())
            if (message['role'] != 'assistant' &&
                message['role'] != 'tool')
              message,
          reply,
          {
            'role': 'tool',
            'tool_call_id': call['id'],
            'content': '1. 结果',
          },
        ];
        final body = AiService.encodeRequest(
          protocol: protocol,
          model: 'm',
          messages: followUp,
        );
        final encoded = jsonEncode(body);
        expect(encoded, contains(call['id'] as String), reason: protocol.id);
      }
    });

    test('synthesizes a stable id when the upstream omits one', () {
      final first = AiService.decodeReply(AiProtocol.responses, {
        'output': [
          {
            'type': 'function_call',
            'name': 'web_fetch',
            'arguments': '{}',
          },
        ],
      });
      final second = AiService.decodeReply(AiProtocol.responses, {
        'output': [
          {
            'type': 'function_call',
            'name': 'web_fetch',
            'arguments': '{}',
          },
        ],
      });
      final a = ((first['tool_calls'] as List).single as Map)['id'];
      final b = ((second['tool_calls'] as List).single as Map)['id'];
      expect(a, isA<String>());
      expect((a as String).startsWith('call_web_fetch_'), isTrue);
      expect(a, isNot(b));
    });
  });
}
