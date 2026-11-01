// 直连兜底的真实网络验收：不经过中转，设备端直接访问搜索源与目标站点。
//
// 门控：只有设置 QFLI_DEBUG_BASE_URL（或 QFLI_WEB_DIRECT=1）才运行，
// 避免 CI 与离线环境因外网抖动误报。凭据只从环境变量读取。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart';

void main() {
  final baseUrl = Platform.environment['QFLI_DEBUG_BASE_URL'];
  final enabled = (baseUrl != null && baseUrl.isNotEmpty) ||
      Platform.environment['QFLI_WEB_DIRECT'] == '1';
  final skip = enabled
      ? false
      : 'Set QFLI_DEBUG_BASE_URL or QFLI_WEB_DIRECT=1 to run live checks.';

  final client = IOClient(
    HttpClient()..findProxy = (_) => 'DIRECT',
  );
  tearDownAll(client.close);

  test(
    'direct Bing RSS search returns real titles, URLs and snippets',
    () async {
      final results = await fetchDirectRssForTest('Flutter 教程', client);
      expect(results, isNotEmpty);
      for (final item in results) {
        expect(item['title'], isNotEmpty);
        expect(item['url'], startsWith('http'));
      }
      // 至少一条真实站点，而不是模板或占位链接。
      expect(
        results.map((r) => r['url']).join('\n'),
        matches(RegExp(r'https?://[a-z0-9.-]*flutter')),
      );
      // ignore: avoid_print
      print('direct RSS: ${results.first['title']} | ${results.first['url']}');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'direct fetch of a public page returns real cleaned text',
    () async {
      final page = await fetchDirectPageForTest(
        Uri.parse('https://flutter.dev/'),
        client,
      );
      expect(page.title.isNotEmpty || page.text.isNotEmpty, isTrue);
      expect(page.text.length, greaterThan(200));
      // ignore: avoid_print
      print('direct fetch: ${page.title} / ${page.text.length} chars');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'direct SSRF guard still rejects internal targets',
    () async {
      for (final url in [
        'http://127.0.0.1/',
        'http://localhost:8080/',
        'http://169.254.169.254/latest/meta-data/',
      ]) {
        Object? caught;
        try {
          await fetchDirectPageForTest(Uri.parse(url), client);
        } on Object catch (error) {
          caught = error;
        }
        expect(caught, isNotNull, reason: '$url 必须被拒绝');
        expect(caught.toString(), contains('拒绝'), reason: url);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'a http.Client built from dart:io works for the direct path',
    () async {
      final wrapper = IOClient(
        HttpClient()..findProxy = (_) => 'DIRECT',
      );
      final results = await fetchDirectRssForTest('dart language', wrapper);
      expect(results, isNotEmpty);
      wrapper.close();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}