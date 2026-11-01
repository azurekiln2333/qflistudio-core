/// 验收环境探测：把每个前置条件单独探一次，输出不含任何凭据。
///
/// 用法（环境变量已在当前进程里）：
///   dart run tool/vibe_e2e_probe.dart
///
/// 只报告状态码、耗时、异常类型；不打印请求头、令牌和密钥。
library;

import 'dart:convert';
import 'dart:io';

import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';

/// 用一个极小会话探测某种协议是否可达。
Future<void> probeProtocol(AiProtocol protocol) async {
  final base = Platform.environment['QFLI_DEBUG_BASE_URL']!;
  final key = Platform.environment['QFLI_DEBUG_API_KEY']!;
  final model = Platform.environment['QFLI_DEBUG_MODEL']!;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final uri = Uri.parse(AiService.endpoint(base, protocol));
  final body = AiService.encodeRequest(
    protocol: protocol,
    model: model,
    messages: const [
      {'role': 'user', 'content': 'reply with the single word ok'},
    ],
  );
  final started = DateTime.now();
  try {
    final request = await client.postUrl(uri);
    for (final e in AiService.headers(protocol, apiKey: key).entries) {
      request.headers.set(e.key, e.value);
    }
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(
      const Duration(seconds: 150),
    );
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 60));
    final ms = DateTime.now().difference(started).inMilliseconds;
    stdout.writeln(
      '${protocol.id} ${uri.path} -> ${response.statusCode} ${ms}ms '
      'bytes=${text.length}',
    );
    if (response.statusCode >= 300) {
      final head = text.length > 220 ? text.substring(0, 220) : text;
      stdout.writeln('   head: $head');
    }
  } on Object catch (error) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    stdout.writeln('${protocol.id} ${uri.path} -> ERROR ${ms}ms');
    stdout.writeln(
      '   ${error.runtimeType}: '
      '${error.toString().replaceAll(key, '[REDACTED]')}',
    );
  } finally {
    client.close(force: true);
  }
}

/// 探测本站中转：在线终端、联网检索、联网抓取。
Future<void> probeRelay() async {
  final token = Platform.environment['QFLI_E2E_TERMINAL_TOKEN']?.trim();
  if (token == null || token.isEmpty) {
    stdout.writeln(
      'relay -> 跳过：未设置 QFLI_E2E_TERMINAL_TOKEN（需要本站登录令牌）',
    );
    return;
  }
  final api = ApiClient();
  Future<void> attempt(String label, Future<void> Function() call) async {
    final started = DateTime.now();
    try {
      await call();
      final ms = DateTime.now().difference(started).inMilliseconds;
      stdout.writeln('$label -> ok ${ms}ms');
    } on Object catch (error) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      stdout.writeln('$label -> ERROR ${ms}ms');
      stdout.writeln('   ${error.runtimeType}: $error');
    }
  }

  await attempt('me(/api/users/me)', () async {
    final me = await api.me(token);
    stdout.writeln('   用户: ${me.username}');
  });
  await attempt('terminal', () async {
    final events = await api
        .terminalEvents(token, 'echo probe-ok; python3 -V')
        .toList()
        .timeout(const Duration(seconds: 90));
    final outputs = events
        .where((e) => e.type == TerminalEventType.stdout)
        .map((e) => e.text)
        .join();
    final codes = events
        .where((e) => e.type == TerminalEventType.result)
        .map((e) => e.exitCode)
        .join(',');
    stdout.writeln('   exit=${codes.isEmpty ? 'none' : codes} out=${outputs.trim()}');
  });
  await attempt('web_search', () async {
    final data = await api.aiWebSearch(token, 'HarmonyOS NEXT SDK');
    final results = data['results'];
    stdout.writeln(
      '   results=${results is List ? results.length : 0} '
      'provider=${data['provider']}',
    );
  });
  api.close();
}

Future<void> main(List<String> args) async {
  final only = args.isEmpty ? null : args.first;
  if (only == null || only == 'protocols') {
    for (final protocol in AiProtocol.values) {
      await probeProtocol(protocol);
    }
  }
  if (only == null || only == 'relay') {
    await probeRelay();
  }
}
