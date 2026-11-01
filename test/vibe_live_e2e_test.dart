// 实时验收：在 flutter test 运行器下跑三个真实场景。
//
// 只有 `QFLI_DEBUG_BASE_URL`、`QFLI_DEBUG_API_KEY`、`QFLI_DEBUG_MODEL` 三个
// 环境变量都在时才执行；缺一个就整体跳过，报告也不会被写。
//
//   (cd qfli_studio_core && flutter test --no-pub test/vibe_live_e2e_test.dart)
//
// 选协议（同一份测试，报告里记 protocol）：
//   QFLI_E2E_PROTOCOL=responses flutter test --no-pub test/vibe_live_e2e_test.dart
//
// 让 `run_command` 真的能跑，还需要 `QFLI_E2E_TERMINAL_TOKEN`（本站登录令牌，
// 不是调试上游密钥）。缺它时场景会如实报出终端不可用。
//
// 报告落在系统临时目录的 `.artifacts/vibe-e2e/`，不进任何仓库。报告只含上游
// 主机名、模型名、协议名和密钥长度；密钥本身不会被打印、不会写盘。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/ai_service.dart';

import '../tool/vibe_e2e_report.dart';
import '../tool/vibe_e2e_runner.dart';
import '../tool/vibe_e2e_scenarios.dart';

void main() {
  final protocol = AiProtocol.parse(Platform.environment['QFLI_E2E_PROTOCOL']);
  final runtime = VibeE2eRuntime.fromEnvironment(protocol: protocol);
  final skipReason = runtime == null
      ? '缺少 QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL'
      : null;
  // 只跑指定场景：逗号分隔。留空时跑全部三个。
  final only = (Platform.environment['QFLI_E2E_SCENARIOS'] ?? '')
      .split(',')
      .map((key) => key.trim())
      .where((key) => key.isNotEmpty)
      .toSet();
  final scenarios = only.isEmpty
      ? vibeE2eScenarios
      : vibeE2eScenarios.where((s) => only.contains(s.key)).toList();

  test(
    'live scenarios report real tool results against the debug upstream',
    () async {
      final startedAt = DateTime.now();
      final active = runtime!;
      final results = <VibeE2eScenarioResult>[];
      try {
        for (final scenario in scenarios) {
          final result = await runVibeE2eScenario(scenario, active);
          results.add(result);
          stdout.writeln(vibeE2eLine(result.toJson()));
          // 每个场景把失败断言逐条打出来，避免只看一行摘要。
          for (final assertion in result.assertions) {
            if (assertion.ok) continue;
            stdout.writeln('  fail ${assertion.name}: ${assertion.detail}');
          }
          if (result.lastError != null) {
            stdout.writeln('  error: ${result.lastError}');
          }
        }
      } finally {
        active.close();
      }

      final report = buildVibeE2eReport(
        generatedAt: startedAt,
        runtime: active,
        scenarios: results,
        driverRevision: vibeE2eGitRevision(
          workingDirectory: Directory.current.path,
        ),
      );
      final file = VibeE2eReportWriter.defaultFile(startedAt);
      await VibeE2eReportWriter.write(file, report);
      stdout.writeln('报告: ${file.path}');

      // 报告不得携带密钥或授权头；这是硬性约束，按实际字节检查。
      final raw = file.readAsStringSync();
      expect(
        raw.contains(active.credentials.apiKey),
        isFalse,
        reason: '报告里出现了密钥',
      );
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      expect(vibeE2eReportProblems(decoded), isEmpty);
      // 守卫自己的提示文案里含变量名，不算敏感片段；这里只校验真值不泄漏。
      expect(raw.contains('sk-'), isFalse, reason: '报告出现密钥前缀');

      final skipped = results
          .where((result) => result.status == VibeE2eStatus.skipped)
          .toList();
      final failed = results
          .where((result) => result.status == VibeE2eStatus.failed)
          .toList();
      for (final result in skipped) {
        expect(result.skipReason, isNotNull, reason: result.key);
      }
      for (final result in failed) {
        expect(
          result.assertions.any((assertion) => !assertion.ok) ||
              result.lastError != null,
          isTrue,
          reason: '${result.key} 失败但没有失败断言',
        );
      }

      // 调试上游可达时，至少一个场景必须真的跑起来（通过或失败都算跑过）。
      if (skipped.length == results.length) {
        fail('全部场景跳过：${skipped.first.skipReason}');
      }
      // 失败不掩盖：这里只报告，不因为失败而假装通过。要判定通过与否，
      // 看报告里的 status；测试只在「全部跳过」或「报告泄漏」时硬失败。
      stdout.writeln(
        '结果: ${results.where((r) => r.ok).length} 通过 / '
        '${failed.length} 失败 / ${skipped.length} 跳过',
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 25)),
    tags: const ['live'],
  );

  test(
    'report shape stays valid without credentials',
    () async {
      final results = await runVibeE2eScenarios(runtime: null);
      expect(results, isNotEmpty);
      expect(
        results.every((result) => result.status == VibeE2eStatus.skipped),
        isTrue,
      );
      final report = buildVibeE2eReport(
        generatedAt: DateTime.utc(2026, 11, 1),
        runtime: null,
        scenarios: results,
      );
      final json = report.toJson();
      expect(vibeE2eReportProblems(json), isEmpty);
      expect((json['environment'] as Map)['keyPresent'], isFalse);
    },
    // 无凭据时这条也要跑，所以不加 skip。
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
