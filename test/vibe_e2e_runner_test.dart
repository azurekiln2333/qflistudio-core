/// 运行器冒烟：不依赖网络，只确认运行器对外形状、跳过语义与报告脱敏。
///
/// 真实工具循环的验证在 `test/vibe_live_e2e_test.dart`（需要 `QFLI_DEBUG_*`）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart'
    show vibeWebToolsAvailable;

import '../tool/vibe_e2e_report.dart';
import '../tool/vibe_e2e_runner.dart';
import '../tool/vibe_e2e_scenarios.dart';

const _env = {
  'QFLI_DEBUG_BASE_URL': 'https://debug.invalid/v1',
  'QFLI_DEBUG_API_KEY': 'sk-offline-fixture-key-0123456789',
  'QFLI_DEBUG_MODEL': 'offline-model',
};

void main() {
  test(
    'runtime is null without credentials and every scenario skips',
    () async {
      final runtime = VibeE2eRuntime.fromEnvironment(environment: const {});
      expect(runtime, isNull);
      final results = await runVibeE2eScenarios(runtime: runtime);
      expect(results, hasLength(vibeE2eScenarios.length));
      for (final result in results) {
        expect(result.status, VibeE2eStatus.skipped);
        expect(result.skipReason, contains('QFLI_DEBUG_BASE_URL'));
        expect(result.tools, isEmpty);
      }
    },
  );

  test('runtime builds a direct transport from the environment', () async {
    final runtime = VibeE2eRuntime.fromEnvironment(environment: _env);
    expect(runtime, isNotNull);
    addTearDown(runtime!.close);
    expect(runtime.protocol, AiProtocol.chat);
    expect(runtime.protocolId, 'chat');
    expect(runtime.transport.endpoint.path, '/v1/chat/completions');
    expect(
      runtime.transport.endpoint.toString().contains(
        _env['QFLI_DEBUG_API_KEY']!,
      ),
      isFalse,
    );
  });

  test('environment摘要 keeps host, model and length only', () {
    final runtime = VibeE2eRuntime.fromEnvironment(environment: _env)!;
    addTearDown(runtime.close);
    final report = buildVibeE2eReport(
      generatedAt: DateTime.utc(2026, 11, 1),
      runtime: runtime,
      scenarios: [
        VibeE2eScenarioResult(
          key: 'static_site',
          status: VibeE2eStatus.skipped,
          phase: 'idle',
          durationMs: 0,
          skipReason: '本机未连接',
        ),
      ],
    );
    final json = report.toJson();
    expect(vibeE2eReportProblems(json), isEmpty);
    final environment = json['environment'] as Map;
    expect(environment['baseHost'], 'debug.invalid');
    expect(environment['keyLength'], _env['QFLI_DEBUG_API_KEY']!.length);
    expect(environment['keyPresent'], isTrue);
    expect(jsonEncode(json).contains(_env['QFLI_DEBUG_API_KEY']!), isFalse);
  });

  test('search scenario is no longer skipped by a missing tool', () {
    final runtime = VibeE2eRuntime.fromEnvironment(
      environment: _env,
      searchToolsAvailable: false,
    )!;
    addTearDown(runtime.close);
    // A 已把 web 工具接进控制器，只有离线产品才会关掉它们。
    expect(vibeWebToolsAvailable, isTrue);
    expect(runtime.hasSearchTools, isTrue);
    final search = vibeE2eScenarios.firstWhere((s) => s.key == 'web_search');
    expect(search.requiresSearchTools, isTrue);
  });

  test('scenario table keeps its three keys', () {
    expect(vibeE2eScenarios.map((s) => s.key), [
      'static_site',
      'python_fix_loop',
      'web_search',
    ]);
  });
}
