import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  const history = [
    {'role': 'user', 'content': 'hi'},
  ];

  setUp(() {
    StudioProfile.current = null;
  });

  group('encodeRequest reasoning effort', () {
    test('adds reasoning_effort for the chat protocol', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.chat,
        model: 'demo',
        messages: history,
        reasoningEffort: 'high',
      );
      expect(body['reasoning_effort'], 'high');
    });

    test('omits reasoning_effort when unset or blank', () {
      for (final effort in [null, '', '   ']) {
        final body = AiService.encodeRequest(
          protocol: AiProtocol.chat,
          model: 'demo',
          messages: history,
          reasoningEffort: effort,
        );
        expect(
          body.containsKey('reasoning_effort'),
          isFalse,
          reason: '$effort',
        );
      }
    });

    test('adds reasoning_effort for the responses protocol', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.responses,
        model: 'demo',
        messages: history,
        reasoningEffort: 'medium',
      );
      expect(body['reasoning_effort'], 'medium');
    });

    test('never sends reasoning_effort to the messages protocol', () {
      final body = AiService.encodeRequest(
        protocol: AiProtocol.messages,
        model: 'demo',
        messages: history,
        reasoningEffort: 'high',
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('drops values that are not a plain short token', () {
      for (final effort in ['High Priority', 'a' * 40, '高', 'high;drop']) {
        final body = AiService.encodeRequest(
          protocol: AiProtocol.chat,
          model: 'demo',
          messages: history,
          reasoningEffort: effort,
        );
        expect(body.containsKey('reasoning_effort'), isFalse, reason: effort);
      }
    });
  });

  group('ApiClient.aiModels', () {
    late List<Map<String, dynamic>> bodies;

    ApiClient build(Object? payload, {int status = 200}) {
      bodies = [];
      return ApiClient(
        transport: MockClient.streaming((request, bodyStream) async {
          bodies.add({'method': request.method, 'path': request.url.path});
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(payload))),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    }

    test('parses ids and reasoning efforts from the relay', () async {
      final api = build({
        'object': 'list',
        'data': [
          {'id': 'fast', 'object': 'model'},
          {
            'id': 'think',
            'object': 'model',
            'reasoning_efforts': ['low', 'high', ''],
          },
          {'id': '', 'object': 'model'},
          'garbage',
        ],
      });

      final models = await api.aiModels(token: 'local-token');

      expect(models.map((model) => model.id), ['fast', 'think']);
      expect(models.first.reasoningEfforts, isEmpty);
      expect(models.last.reasoningEfforts, ['low', 'high']);
      expect(bodies.single['method'], 'GET');
      expect(bodies.single['path'], '/api/ai/models');
    });

    test('returns an empty list for direct mode without a request', () async {
      final api = build(const {'object': 'list', 'data': []});

      final models = await api.aiModels(
        token: 'local-token',
        endpoint: const AiEndpoint.direct(
          baseUrl: 'https://example.com/v1',
          apiKey: 'k',
          model: 'm',
        ),
      );

      expect(models, isEmpty);
      expect(bodies, isEmpty);
    });

    test('tolerates a malformed payload', () async {
      final api = build(const {'object': 'list'});
      expect(await api.aiModels(token: 'local-token'), isEmpty);
    });
  });
}
