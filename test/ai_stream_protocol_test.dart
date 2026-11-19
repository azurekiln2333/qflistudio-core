// 三种直连协议的流式解析：思考、正文、多段工具调用参数与收尾结果。
//
// 样本是录制的 SSE，放在 test/fixtures/ai_stream/；样本里只有示例数据，
// 不含真实密钥与真实用户内容。字节流按小片切开，顺带验证跨块的行与多字节字符。
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

/// prd AC10：三种协议各有一组流式样本，覆盖思考、正文与工具调用。
void main() {
  setUp(() {
    StudioProfile.current = null;
  });

  group('recorded streams', () {
    for (final protocol in AiProtocol.values) {
      test(
        '${protocol.id} emits the same event order and one result',
        () async {
          final events = await _decode(protocol, _fixtureName(protocol));

          expect(_kinds(events), [
            'reasoning',
            'reasoning',
            'content',
            'content',
            'tool',
            'tool',
            'completed',
          ], reason: protocol.id);
          expect(_reasoningOf(events), _expectedReasoning[protocol]);
          expect(_contentOf(events), _expectedContent[protocol]);
          expect(_toolNames(events), ['0:web_search', '1:web_fetch']);

          final result = _resultOf(events);
          expect(result.model, 'fixture-reasoner', reason: protocol.id);
          expect(
            result.content,
            _expectedContent[protocol],
            reason: protocol.id,
          );
          expect(
            result.reasoning,
            _expectedReasoning[protocol],
            reason: protocol.id,
          );
          expect(
            result.toolCalls.map((call) => call['function']['name']),
            ['web_search', 'web_fetch'],
            reason: protocol.id,
          );
          expect(
            jsonDecode(
              result.toolCalls.first['function']['arguments'] as String,
            ),
            {'query': '示例 查询'},
            reason: protocol.id,
          );
          expect(
            jsonDecode(
              result.toolCalls.last['function']['arguments'] as String,
            ),
            {'url': 'https://example.com'},
            reason: protocol.id,
          );
          expect(
            result.rawMessage['reasoning_content'],
            _expectedReasoning[protocol],
            reason: protocol.id,
          );
        },
      );
    }

    test('messages keeps the thinking signature for the next round', () async {
      final result = _resultOf(
        await _decode(AiProtocol.messages, _fixtureName(AiProtocol.messages)),
      );

      final blocks = (result.rawMessage['reasoning_blocks'] as List)
          .cast<Map>();
      expect(blocks, hasLength(1));
      expect(blocks.single['type'], 'thinking');
      expect(
        blocks.single['thinking'],
        _expectedReasoning[AiProtocol.messages],
      );
      expect(blocks.single['signature'], 'c2lnbmF0dXJlLWZpeHR1cmU=');
    });

    test('usage rides along with the result', () async {
      final chat = _resultOf(
        await _decode(AiProtocol.chat, _fixtureName(AiProtocol.chat)),
      );
      expect(chat.usage?['total_tokens'], 46);

      final responses = _resultOf(
        await _decode(AiProtocol.responses, _fixtureName(AiProtocol.responses)),
      );
      expect(responses.usage?['total_tokens'], 69);

      final messages = _resultOf(
        await _decode(AiProtocol.messages, _fixtureName(AiProtocol.messages)),
      );
      expect(messages.usage?['output_tokens'], 48);
    });

    test('a chat stream without [DONE] still finishes once', () async {
      final bytes = utf8.encode(
        'data: {"model":"fixture-reasoner","choices":'
        '[{"delta":{"content":"只有正文。"}}]}\n',
      );
      final events = await AiService.decodeEventStream(
        AiProtocol.chat,
        _chunked(bytes),
        model: 'fixture-reasoner',
      ).toList();

      expect(events.whereType<AiTurnCompleted>(), hasLength(1));
      expect(_resultOf(events).content, '只有正文。');
      expect(_resultOf(events).reasoning, isEmpty);
    });

    test('a reasoning-only stream is a failed turn', () async {
      final bytes = utf8.encode(
        'data: {"model":"fixture-reasoner","choices":'
        '[{"delta":{"reasoning_content":"只想不说。"}}]}\n'
        'data: [DONE]\n',
      );

      await expectLater(
        AiService.decodeEventStream(
          AiProtocol.chat,
          _chunked(bytes),
          model: 'fixture-reasoner',
        ).toList(),
        throwsA(isA<AiException>()),
      );
    });

    test('blank lines, comments and unknown events are ignored', () async {
      final bytes = utf8.encode(
        ': keep-alive\n\n'
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","index":0,'
        '"delta":{"type":"text_delta","text":"好。"}}\n\n'
        'data: {"type":"content_block_stop","index":0}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n',
      );
      final events = await AiService.decodeEventStream(
        AiProtocol.messages,
        _chunked(bytes),
        model: 'fixture-model',
      ).toList();

      expect(_contentOf(events), '好。');
      expect(_resultOf(events).content, '好。');
    });
  });

  group('non-SSE replies', () {
    test('a JSON reply decodes whole and emits one event', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = ApiClient(
        transport: MockClient.streaming((request, bodyStream) async {
          bodies.add(
            jsonDecode(await utf8.decoder.bind(bodyStream).join())
                as Map<String, dynamic>,
          );
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'output': [
                    {
                      'type': 'reasoning',
                      'summary': [
                        {'type': 'summary_text', 'text': '上游没有流式。'},
                      ],
                    },
                    {
                      'type': 'message',
                      'content': [
                        {'type': 'output_text', 'text': '整段回复。'},
                      ],
                    },
                  ],
                }),
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final events = await api
          .aiChatStream(
            token: 'local-token',
            messages: const [
              {'role': 'user', 'content': '你好'},
            ],
            endpoint: const AiEndpoint.direct(
              baseUrl: 'https://example.test/v1',
              apiKey: 'local-key',
              model: 'fixture-model',
              protocol: AiProtocol.responses,
            ),
          )
          .toList();

      expect(events, hasLength(1));
      final result = _resultOf(events);
      expect(result.content, '整段回复。');
      expect(result.reasoning, '上游没有流式。');
      expect(result.model, 'fixture-model');
      // 请求仍然要求流式，上游不支持才回退成整段。
      expect(bodies.single['stream'], isTrue);
    });
  });

  group('thinking round trip', () {
    test('chat re-sends reasoning_content on the assistant turn', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.chat,
        model: 'm',
        messages: [
          {'role': 'user', 'content': '问'},
          {'role': 'assistant', 'content': '答', 'reasoning_content': '想过这件事。'},
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': '结果'},
        ],
      );

      final messages = (body['messages'] as List).cast<Map>();
      expect(messages[1]['reasoning_content'], '想过这件事。');
      expect(messages[0].containsKey('reasoning_content'), isFalse);
      expect(messages[2].containsKey('reasoning_content'), isFalse);
    });

    test('messages puts thinking blocks before text and tool_use', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: [
          {'role': 'user', 'content': '问'},
          {
            'role': 'assistant',
            'content': '答',
            'reasoning_content': '想过这件事。',
            'reasoning_blocks': [
              {'type': 'thinking', 'thinking': '想过这件事。', 'signature': 'sig-1'},
              {'type': 'redacted_thinking', 'data': 'redacted-1'},
            ],
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'web_search',
                  'arguments': '{"query": "示例"}',
                },
              },
            ],
          },
        ],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'web_search',
              'parameters': {'type': 'object'},
            },
          },
        ],
      );

      final assistant =
          ((body['messages'] as List).cast<Map>())[1]['content'] as List;
      expect(assistant.map((block) => block['type']), [
        'thinking',
        'redacted_thinking',
        'text',
        'tool_use',
      ]);
      expect(assistant[0]['signature'], 'sig-1');
      expect(assistant[1]['data'], 'redacted-1');
    });

    test('a messages reply re-encodes with its signature intact', () async {
      final result = _resultOf(
        await _decode(AiProtocol.messages, _fixtureName(AiProtocol.messages)),
      );
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: [
          {'role': 'user', 'content': '问'},
          result.rawMessage,
        ],
        thinking: true,
      );

      final assistant =
          ((body['messages'] as List).cast<Map>())[1]['content'] as List;
      expect(assistant.first['type'], 'thinking');
      expect(assistant.first['signature'], 'c2lnbmF0dXJlLWZpeHR1cmU=');
      expect(
        assistant.first['thinking'],
        _expectedReasoning[AiProtocol.messages],
      );
    });

    test('responses never sends reasoning back', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.responses,
        model: 'm',
        messages: [
          {'role': 'assistant', 'content': '答', 'reasoning_content': '想过这件事。'},
        ],
      );

      expect(jsonEncode(body), isNot(contains('想过这件事')));
    });
  });

  // prd AC11：开关关闭时不出现思考参数，打开时出现。
  group('thinking switch', () {
    const history = [
      {'role': 'user', 'content': '你好'},
    ];

    test('responses adds reasoning only when the switch is on', () {
      final off = AiService.encodeRequest(
        protocol: AiProtocol.responses,
        model: 'm',
        messages: history,
      );
      expect(off.containsKey('reasoning'), isFalse);

      final on = AiService.encodeRequest(
        protocol: AiProtocol.responses,
        model: 'm',
        messages: history,
        thinking: true,
      );
      expect(on['reasoning'], {'summary': 'auto'});
    });

    test('messages adds thinking and raises max_tokens when on', () {
      final off = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: history,
      );
      expect(off.containsKey('thinking'), isFalse);
      expect(off['max_tokens'], AiService.defaultMaxTokens);

      final on = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: history,
        thinking: true,
      );
      expect(on['thinking'], {
        'type': 'enabled',
        'budget_tokens': AiService.thinkingBudgetTokens,
      });
      expect(on['max_tokens'], AiService.thinkingMaxTokens);
    });

    test('an explicit max_tokens above the floor is kept', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'm',
        messages: history,
        maxTokens: 32000,
        thinking: true,
      );
      expect(body['max_tokens'], 32000);
    });

    test('chat never carries a thinking parameter', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.chat,
        model: 'm',
        messages: history,
        thinking: true,
      );
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning'), isFalse);
    });

    test('stream is only set when asked for', () {
      for (final protocol in AiProtocol.values) {
        final off = AiService.encodeRequest(
          protocol: protocol,
          model: 'm',
          messages: history,
        );
        expect(off.containsKey('stream'), isFalse, reason: protocol.id);

        final on = AiService.encodeRequest(
          protocol: protocol,
          model: 'm',
          messages: history,
          stream: true,
        );
        expect(on['stream'], isTrue, reason: protocol.id);
      }
    });
  });
}

const _expectedReasoning = {
  AiProtocol.chat: '先确认用户要查什么。这一步不需要工具。',
  AiProtocol.responses: '先确认用户要查什么。',
  AiProtocol.messages: '先确认用户要查什么。',
};

const _expectedContent = {
  AiProtocol.chat: '我先查一下示例资料。然后再抓取页面。',
  AiProtocol.responses: '我先查一下示例资料。',
  AiProtocol.messages: '我先查一下示例资料。',
};

String _fixtureName(AiProtocol protocol) => switch (protocol) {
  AiProtocol.chat => 'chat_thinking_tools.sse',
  AiProtocol.responses => 'responses_thinking_tools.sse',
  AiProtocol.messages => 'messages_thinking_tools.sse',
};

List<int> _fixture(String name) =>
    File(p.join('test', 'fixtures', 'ai_stream', name)).readAsBytesSync();

/// 切得很碎：一行常常跨多个块，多字节字符也会被切开。
Stream<List<int>> _chunked(List<int> bytes, [int size = 5]) async* {
  for (var start = 0; start < bytes.length; start += size) {
    final end = start + size > bytes.length ? bytes.length : start + size;
    yield bytes.sublist(start, end);
  }
}

Future<List<AiTurnEvent>> _decode(AiProtocol protocol, String name) =>
    AiService.decodeEventStream(
      protocol,
      _chunked(_fixture(name)),
      model: 'fixture-reasoner',
    ).toList();

List<String> _kinds(List<AiTurnEvent> events) => [
  for (final event in events)
    switch (event) {
      AiReasoningDelta() => 'reasoning',
      AiContentDelta() => 'content',
      AiToolCallStarted() => 'tool',
      AiTurnCompleted() => 'completed',
    },
];

String _reasoningOf(List<AiTurnEvent> events) =>
    events.whereType<AiReasoningDelta>().map((event) => event.text).join();

String _contentOf(List<AiTurnEvent> events) =>
    events.whereType<AiContentDelta>().map((event) => event.text).join();

List<String> _toolNames(List<AiTurnEvent> events) => [
  for (final event in events.whereType<AiToolCallStarted>())
    '${event.index}:${event.name}',
];

AiChatResult _resultOf(List<AiTurnEvent> events) =>
    events.whereType<AiTurnCompleted>().single.result;
