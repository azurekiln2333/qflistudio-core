// 中转流：NDJSON 事件、流内错误、旧服务端回退、取消与空闲超时。
//
// 用假的 http.Client 覆盖传输层，不碰网络。超时值由构造参数注入，
// 测试不会真的等 90 秒。
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

const _history = [
  {'role': 'user', 'content': '用工具查一下'},
];

const _relayResult = {
  'type': 'result',
  'model': 'fixture-reasoner',
  'aiGenerated': true,
  'message': {
    'role': 'assistant',
    'content': '我先搜索。',
    'reasoning_content': '先想清楚再查。',
    'tool_calls': [
      {
        'id': 'call_fixture_1',
        'type': 'function',
        'function': {'name': 'web_search', 'arguments': '{"query": "示例 查询"}'},
      },
    ],
  },
  'usage': {'prompt_tokens': 9, 'completion_tokens': 12, 'total_tokens': 21},
};

void main() {
  late StudioProfile? previous;

  setUp(() {
    previous = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() {
    StudioProfile.current = previous;
  });

  test('NDJSON events map onto the turn event stream', () async {
    final requests = <http.Request>[];
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      transport: MockClient.streaming((request, bodyStream) async {
        requests.add(
          http.Request(request.method, request.url)
            ..headers.addAll(request.headers),
        );
        bodies.add(
          jsonDecode(await utf8.decoder.bind(bodyStream).join())
              as Map<String, dynamic>,
        );
        return _ndjson(200, [
          {'type': 'start', 'model': 'fixture-reasoner', 'aiGenerated': true},
          {'type': 'reasoning', 'text': '先想清楚'},
          {'type': 'reasoning', 'text': '再查。'},
          {'type': 'content', 'text': '我先搜索。'},
          {'type': 'tool_call', 'index': 0, 'name': 'web_search'},
          _relayResult,
        ]);
      }),
    );

    final events = await api
        .aiChatStream(token: 'local-token', messages: _history)
        .toList();

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/ai/chat/stream');
    expect(requests.single.headers['authorization'], 'Bearer local-token');
    expect(bodies.single['messages'], _history);
    expect(bodies.single.containsKey('model'), isFalse);

    expect(
      [
        for (final event in events)
          switch (event) {
            AiReasoningDelta() => 'reasoning',
            AiContentDelta() => 'content',
            AiToolCallStarted() => 'tool',
            AiTurnCompleted() => 'completed',
          },
      ],
      ['reasoning', 'reasoning', 'content', 'tool', 'completed'],
    );

    expect(
      events.whereType<AiReasoningDelta>().map((event) => event.text).join(),
      '先想清楚再查。',
    );
    final tool = events.whereType<AiToolCallStarted>().single;
    expect(tool.index, 0);
    expect(tool.name, 'web_search');

    final result = events.whereType<AiTurnCompleted>().single.result;
    expect(result.content, '我先搜索。');
    expect(result.reasoning, '先想清楚再查。');
    expect(result.usage?['total_tokens'], 21);
    expect(result.toolCalls.single['id'], 'call_fixture_1');
  });

  test('an error event becomes an ApiException with its status', () async {
    final api = ApiClient(
      transport: MockClient.streaming(
        (request, bodyStream) async => _ndjson(200, [
          {'type': 'start', 'model': 'fixture-reasoner'},
          {'type': 'error', 'status': 502, 'error': '上游超出限额'},
        ]),
      ),
    );

    await expectLater(
      api.aiChatStream(token: 'local-token', messages: _history).toList(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 502)
            .having((error) => error.message, 'message', contains('上游超出限额')),
      ),
    );
  });

  for (final status in [404, 405]) {
    test('HTTP $status falls back to the whole-turn endpoint', () async {
      final paths = <String>[];
      final api = ApiClient(
        transport: MockClient.streaming((request, bodyStream) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/ai/chat/stream') {
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              status,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'model': 'fixture-reasoner',
                  'message': {
                    'role': 'assistant',
                    'content': '整段回复。',
                    'reasoning_content': '整段思考。',
                  },
                }),
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final events = await api
          .aiChatStream(token: 'local-token', messages: _history)
          .toList();

      expect(paths, ['/api/ai/chat/stream', '/api/ai/chat']);
      expect(events, hasLength(1));
      final result = (events.single as AiTurnCompleted).result;
      expect(result.content, '整段回复。');
      expect(result.reasoning, '整段思考。');
    });
  }

  for (final status in [200, 404, 405]) {
    test(
      'reasoning history respects relay capabilities for HTTP $status',
      () async {
        final history = <Map<String, dynamic>>[
          {
            'role': 'assistant',
            'content': 'Previous answer',
            'reasoning_content': 'Previous reasoning',
            'reasoning_blocks': [
              {
                'type': 'thinking',
                'thinking': 'Private protocol block',
                'signature': 'fixture',
              },
            ],
            'tool_calls': <dynamic>[],
          },
          {'role': 'user', 'content': 'Continue'},
        ];
        final original = jsonEncode(history);
        final requests = <String>[];
        final api = ApiClient(
          transport: MockClient.streaming((request, bodyStream) async {
            requests.add(request.url.path);
            final body =
                jsonDecode(await utf8.decoder.bind(bodyStream).join()) as Map;
            final sent = (body['messages'] as List).first as Map;
            expect(sent.containsKey('reasoning_blocks'), isFalse);
            if (request.url.path.endsWith('/stream')) {
              expect(sent['reasoning_content'], 'Previous reasoning');
              if (status == 200) return _ndjson(200, [_relayResult]);
              return http.StreamedResponse(
                const Stream<List<int>>.empty(),
                status,
              );
            }
            expect(sent.keys.toSet(), {'role', 'content', 'tool_calls'});
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(_relayResult))),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final result = await api
            .aiChatStream(token: 'fixture', messages: history)
            .toList();
        expect(result.whereType<AiTurnCompleted>(), hasLength(1));
        expect(requests.length, status == 200 ? 1 : 2);
        expect(jsonEncode(history), original);
      },
    );
  }

  test('whole-turn relay projects history without mutating it', () async {
    final history = <Map<String, dynamic>>[
      {
        'role': 'assistant',
        'content': 'answer',
        'reasoning_content': 'thinking',
        'reasoning_blocks': <dynamic>[],
      },
    ];
    final original = jsonEncode(history);
    final api = ApiClient(
      transport: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['messages'], [
          {'role': 'assistant', 'content': 'answer'},
        ]);
        return http.Response.bytes(
          utf8.encode(jsonEncode(_relayResult)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await api.aiChat(token: 'fixture', messages: history);
    expect(jsonEncode(history), original);
  });

  test('HTTP 400 does not retry the conversation', () async {
    var count = 0;
    final api = ApiClient(
      transport: MockClient.streaming((request, body) async {
        count++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"invalid history"}')),
          400,
        );
      }),
    );
    await expectLater(
      api.aiChatStream(token: 'fixture', messages: _history).toList(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
    );
    expect(count, 1);
  });

  test('a non-200 stream response is reported before any event', () async {
    final api = ApiClient(
      transport: MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'error': '登录已过期'}))),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      api.aiChatStream(token: 'local-token', messages: _history).toList(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having((error) => error.message, 'message', contains('登录已过期')),
      ),
    );
  });

  // prd AC6：取消是预期路径，已经发出的增量保留，流不抛错。
  test('cancelling ends the stream without an error', () async {
    final abort = Completer<void>();
    final pending = StreamController<List<int>>();
    final api = ApiClient(
      transport: MockClient.streaming((request, bodyStream) async {
        pending.add(
          utf8.encode(
            '${jsonEncode({'type': 'start', 'model': 'fixture-reasoner'})}\n',
          ),
        );
        pending.add(
          utf8.encode(
            '${jsonEncode({'type': 'reasoning', 'text': '想了一下。'})}\n',
          ),
        );
        return http.StreamedResponse(
          pending.stream,
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      }),
    );

    final events = <AiTurnEvent>[];
    await for (final event in api.aiChatStream(
      token: 'local-token',
      messages: _history,
      abortTrigger: abort.future,
    )) {
      events.add(event);
      if (event is AiReasoningDelta) abort.complete();
    }
    await pending.close();

    expect(events.whereType<AiTurnCompleted>(), isEmpty);
    expect(events.whereType<AiReasoningDelta>().map((event) => event.text), [
      '想了一下。',
    ]);
  });

  test('a silent stream fails on the injected idle timeout', () async {
    final pending = StreamController<List<int>>();
    final api = ApiClient(
      aiIdleTimeout: const Duration(milliseconds: 40),
      transport: MockClient.streaming((request, bodyStream) async {
        pending.add(
          utf8.encode(
            '${jsonEncode({'type': 'start', 'model': 'fixture-reasoner'})}\n',
          ),
        );
        return http.StreamedResponse(
          pending.stream,
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      }),
    );

    await expectLater(
      api.aiChatStream(token: 'local-token', messages: _history).toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    await pending.close();
  });

  test('a stream that stops before the result fails', () async {
    final api = ApiClient(
      transport: MockClient.streaming(
        (request, bodyStream) async => _ndjson(200, [
          {'type': 'start', 'model': 'fixture-reasoner'},
          {'type': 'content', 'text': '说到一半'},
        ]),
      ),
    );

    await expectLater(
      api.aiChatStream(token: 'local-token', messages: _history).toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('提前结束'),
        ),
      ),
    );
  });
}

http.StreamedResponse _ndjson(int status, List<Map<String, dynamic>> events) =>
    http.StreamedResponse(
      Stream.value(utf8.encode('${events.map(jsonEncode).join('\n')}\n')),
      status,
      headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
    );
