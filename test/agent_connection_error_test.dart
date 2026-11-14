import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/config/api_config.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/connection_probe.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/vibe_coding/agent_request_scheduler.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

/// API 服务器主机名。诊断和错误文案都要写它。
final host = Uri.parse(ApiConfig.baseUrl).host;

/// 假网络层：三步都按配置失败，并记录被访问的主机。
class FakeProbe implements ConnectionProbe {
  FakeProbe({
    this.lookupError,
    this.connectError,
    this.handshakeError,
    this.addresses = const ['172.67.140.164', '104.21.70.240'],
  });

  final Object? lookupError;
  final Object? connectError;
  final Object? handshakeError;
  final List<String> addresses;

  final List<String> touchedHosts = [];
  final List<int> touchedPorts = [];

  @override
  Future<List<String>> lookup(String host) async {
    touchedHosts.add(host);
    if (lookupError != null) throw lookupError!;
    return addresses;
  }

  @override
  Future<void> connect(String host, int port) async {
    touchedHosts.add(host);
    touchedPorts.add(port);
    if (connectError != null) throw connectError!;
  }

  @override
  Future<void> handshake(String host, int port) async {
    touchedHosts.add(host);
    touchedPorts.add(port);
    if (handshakeError != null) throw handshakeError!;
  }
}

ApiClient throwingClient(Object error) =>
    ApiClient(transport: MockClient((_) async => throw error));

/// 跑一次中转 AI 调用，返回捕获到的异常。
Future<ApiException> chatFailure(
  ApiClient client, {
  String token = 'sk-local-token-never-in-detail',
}) async {
  try {
    await client.aiChat(
      token: token,
      messages: [
        {'role': 'user', 'content': '你好'},
      ],
    );
  } on ApiException catch (error) {
    return error;
  }
  fail('应当抛出 ApiException');
}

void main() {
  group('AI 调用失败时给出结构化信息', () {
    test('域名解析失败记成 dns，文案带主机名', () async {
      final error = await chatFailure(
        throwingClient(
          SocketException('Failed host lookup: $host'),
        ),
      );

      expect(error.details['phase'], 'dns');
      expect(error.details['host'], host);
      expect(error.details['method'], 'POST');
      expect(error.details['path'], '/api/ai/chat');
      expect(error.details['exception'], 'SocketException');
      expect(error.details['osMessage'], contains('Failed host lookup'));
      expect(error.details['elapsedMs'], isA<int>());
      expect(error.message, contains(host));
      expect(error.message, contains('域名解析失败'));
      expect(error.message, isNot(contains('设备时间')));
    });

    test('连接被拒记成 connect', () async {
      final error = await chatFailure(
        throwingClient(const SocketException('Connection refused')),
      );

      expect(error.details['phase'], 'connect');
      expect(error.details['host'], host);
      expect(error.message, contains(host));
      expect(error.message, contains('连不上服务器'));
    });

    test('握手被断开记成 tls，不提设备时间', () async {
      final error = await chatFailure(
        throwingClient(
          HandshakeException('Connection terminated during handshake'),
        ),
      );

      expect(error.details['phase'], 'tls');
      expect(error.details['exception'], 'HandshakeException');
      expect(
        error.details['osMessage'],
        'Connection terminated during handshake',
      );
      expect(error.message, contains(host));
      expect(error.message, contains('TLS 握手失败'));
      // 设备时间只在证书过期或尚未生效时出现。
      expect(error.message, isNot(contains('设备时间')));
    });

    test('证书过期时才提设备时间', () async {
      final error = await chatFailure(
        throwingClient(
          HandshakeException(
            'CERTIFICATE_VERIFY_FAILED: certificate has expired',
          ),
        ),
      );

      expect(error.details['phase'], 'tls');
      expect(error.message, contains('设备时间'));
    });

    test('超时记成 timeout', () async {
      final error = await chatFailure(
        throwingClient(TimeoutException('没有响应')),
      );

      expect(error.details['phase'], 'timeout');
      expect(error.details['exception'], 'TimeoutException');
      expect(error.message, contains(host));
      expect(error.message, contains('超时'));
    });

    test('HTTP 502 带上状态码和 X-Request-Id', () async {
      final client = ApiClient(
        transport: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': '上游不可用'}),
            502,
            headers: {
              'content-type': 'application/json',
              'x-request-id': 'abc123',
            },
          ),
        ),
      );

      final error = await chatFailure(client);

      expect(error.statusCode, 502);
      expect(error.details['phase'], 'http');
      expect(error.details['statusCode'], 502);
      expect(error.details['requestId'], 'abc123');
      expect(error.details['serverError'], '上游不可用');
      expect(error.message, '上游不可用\n请求编号：abc123');
    });

    test('直连上游的失败同样带主机与路径', () async {
      final direct = ApiClient(
        transport: MockClient(
          (_) async => throw HandshakeException('Connection terminated'),
        ),
      );
      try {
        await direct.aiChat(
          token: 'sk-direct-token-000',
          messages: [
            {'role': 'user', 'content': '你好'},
          ],
          endpoint: const AiEndpoint.direct(
            baseUrl: 'https://api.deepseek.com',
            apiKey: 'sk-direct-token-000',
            model: 'deepseek-chat',
          ),
        );
        fail('应当抛出 ApiException');
      } on ApiException catch (error) {
        expect(error.details['phase'], 'tls');
        expect(error.details['host'], 'api.deepseek.com');
        expect(error.details['path'], '/v1/chat/completions');
        expect(error.message, contains('api.deepseek.com'));
      }
    });

    test('详情里找不到令牌', () async {
      const token = 'sk-secret-token-9f3a';
      final error = await chatFailure(
        throwingClient(
          HandshakeException('Connection terminated during handshake'),
        ),
        token: token,
      );

      final detail = jsonEncode(error.details);
      expect(detail, isNot(contains(token)));
      expect(detail, isNot(contains('Bearer')));
      expect(error.message, isNot(contains(token)));
    });
  });

  group('连接诊断逐步报告', () {
    test('域名解析失败给出 DNS 结论，只连 API 服务器', () async {
      final probe = FakeProbe(
        lookupError: SocketException('Failed host lookup: $host'),
      );
      final text = await ApiClient(probe: probe).probeConnection();

      expect(text, contains('服务器：$host'));
      expect(text, contains('① 域名解析：失败，SocketException'));
      expect(text, contains('结论：域名解析失败'));
      expect(text, isNot(contains('②')));
      expect(probe.touchedHosts, everyElement(host));
    });

    test('TCP 失败说明端口不通或被拦', () async {
      final probe = FakeProbe(
        connectError: const SocketException('Connection refused'),
      );
      final text = await ApiClient(probe: probe).probeConnection();

      expect(text, contains('① 域名解析：成功'));
      expect(text, contains('② TCP 连接 443：失败，SocketException'));
      expect(text, contains('结论：服务器的 443 端口连不上'));
      expect(probe.touchedPorts, everyElement(443));
    });

    test('TLS 握手被断开时指出常见原因', () async {
      final probe = FakeProbe(
        handshakeError: HandshakeException(
          'Connection terminated during handshake',
        ),
      );
      final text = await ApiClient(probe: probe).probeConnection();

      expect(text, contains('② TCP 连接 443：成功'));
      expect(text, contains('③ TLS 握手：失败，HandshakeException'));
      expect(text, contains('结论：能连到服务器的 IP，但 TLS 握手被断开'));
      expect(text, contains('当前网络拦截了这个域名'));
      expect(probe.touchedHosts, everyElement(host));
    });

    test('握手超时也算 TLS 失败', () async {
      final probe = FakeProbe(handshakeError: TimeoutException('没有响应'));
      final text = await ApiClient(probe: probe).probeConnection();

      expect(text, contains('③ TLS 握手：失败，TimeoutException'));
      expect(text, contains('结论：能连到服务器的 IP，但 TLS 握手被断开'));
    });

    test('全部成功时把问题指向服务端', () async {
      final text = await ApiClient(probe: FakeProbe()).probeConnection();

      expect(text, contains('① 域名解析：成功，172.67.140.164、104.21.70.240'));
      expect(text, contains('② TCP 连接 443：成功'));
      expect(text, contains('③ TLS 握手：成功'));
      expect(text, contains('结论：到服务器的连接正常'));
    });
  });

  group('会话错误信息', () {
    late Directory root;
    late Directory project;
    late FileAgentSessionStore store;

    setUp(() async {
      StudioProfile.current = null;
      root = Directory.systemTemp.createTempSync('agent-error-');
      project = Directory(p.join(root.path, 'proj'))
        ..createSync(recursive: true);
      store = FileAgentSessionStore(
        root: Directory(p.join(root.path, 'sessions')),
      );
      await store.load();
    });

    tearDown(() {
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 上偶发占用，临时目录可以留下。
      }
    });

    VibeAgentRuntime runtime(ApiClient api, {String? token = 'local-token'}) =>
        VibeAgentRuntime(
          api: api,
          tokenProvider: () => token,
          sessions: store,
          projectRootOf: (_) => project.path,
          scheduler: AgentRequestScheduler(retryDelays: const []),
        );

    Future<void> settle(AgentFacade facade) async {
      for (var i = 0; i < 600; i++) {
        if (facade.state != AgentRunState.running &&
            facade.state != AgentRunState.cancelling) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await facade.flush();
    }

    Future<AgentErrorInfo> failureOf(
      ApiClient api, {
      String token = 'local-token',
    }) async {
      final meta = await store.create('p1');
      final facade = await runtime(api, token: token).open('p1', meta.id);
      await facade.send('x', permission: AgentPermissionMode.autoAcceptEdits);
      await settle(facade);
      final info = facade.lastErrorInfo;
      expect(info, isNotNull, reason: '失败后应当有结构化信息');
      return info!;
    }

    test('TLS 握手失败的多行详情写明主机和步骤', () async {
      final info = await failureOf(
        throwingClient(
          HandshakeException('Connection terminated during handshake'),
        ),
      );

      expect(info.phase, AgentErrorPhase.tls);
      expect(info.host, host);
      expect(info.kind, AgentErrorKind.offline);
      expect(info.detail, contains('请求：POST /api/ai/chat'));
      expect(info.detail, contains('服务器：$host'));
      expect(info.detail, contains('失败步骤：TLS 握手'));
      expect(info.detail, contains('异常：HandshakeException'));
      expect(
        info.detail,
        contains('系统信息：Connection terminated during handshake'),
      );
      expect(info.detail, contains('用时：'));
      expect(info.detail, contains('设备时间：'));
      expect(info.detail, contains('建议：握手被断开，常见原因'));
    });

    test('HTTP 502 的详情带状态码和请求 ID', () async {
      final api = ApiClient(
        transport: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': '上游不可用'}),
            502,
            headers: {
              'content-type': 'application/json',
              'x-request-id': 'req-abc123',
            },
          ),
        ),
      );

      final info = await failureOf(api);

      expect(info.statusCode, 502);
      expect(info.phase, AgentErrorPhase.http);
      expect(info.host, host);
      expect(info.detail, contains('状态码：502'));
      expect(info.detail, contains('请求 ID：req-abc123'));
      expect(info.detail, contains('服务器：$host'));
    });

    test('详情里找不到令牌', () async {
      const token = 'sk-secret-token-7c1d';
      final info = await failureOf(
        throwingClient(
          HandshakeException('Connection terminated during handshake'),
        ),
        token: token,
      );

      expect(info.detail, isNot(contains(token)));
      expect(info.detail, isNot(contains('Bearer')));
    });

    test('运行时把诊断接到 API 服务器', () async {
      final probe = FakeProbe(
        handshakeError: HandshakeException(
          'Connection terminated during handshake',
        ),
      );
      final text = await runtime(
        ApiClient(probe: probe),
      ).diagnoseConnection();

      expect(text, contains('服务器：$host'));
      expect(text, contains('③ TLS 握手：失败'));
      expect(probe.touchedHosts, everyElement(host));
    });
  });
}
