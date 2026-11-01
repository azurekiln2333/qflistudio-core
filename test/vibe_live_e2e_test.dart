// 实时验收：在 flutter test 运行器下跑三个真实场景。
//
// 只有 `QFLI_DEBUG_BASE_URL`、`QFLI_DEBUG_API_KEY`、`QFLI_DEBUG_MODEL` 三个
// 环境变量都在时才执行；缺一个就整体跳过，报告也不会被写。
//
//   (cd qfli_studio_core && flutter test --no-pub test/vibe_live_e2e_test.dart)
//
// 报告落在系统临时目录的 `.artifacts/vibe-e2e/`，不进任何仓库。报告只含上游
// 主机名、模型名、协议名和密钥长度；密钥本身不会被打印、不会写盘。
//
// 为什么用 flutter test 而不是 dart run：本包依赖 Flutter，`dart run` 无法加载
// `dart:ui`。`tool/vibe_e2e.dart` 保留给 SDK 侧适配后的宿主。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/vibe_e2e_report.dart';
import '../tool/vibe_e2e_runner.dart';
import '../tool/vibe_e2e_scenarios.dart';

void main() {
  final runtime = VibeE2eRuntime.fromEnvironment();
  final skipReason = runtime == null
      ? '缺少 QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL'
      : null;

  test(
    'live scenarios report real tool results against the debug upstream',
    () async {
      final startedAt = DateTime.now();
      final active = runtime!;
      final results = <VibeE2eScenarioResult>[];
      try {
        for (final scenario in vibeE2eScenarios) {
          final result = await runVibeE2eScenario(scenario, active);
          results.add(result);
          // 每个场景单独打印一行摘要，便于 CI 里直接看到结论。
          stdout.writeln(vibeE2eLine(result.toJson()));
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

      final skipped = results
          .where((result) => result.status == VibeE2eStatus.skipped)
          .toList();
      final failed = results
          .where((result) => result.status == VibeE2eStatus.failed)
          .toList();
      // 跳过必须有理由；失败必须带真实证据。
      for (final result in skipped) {
        expect(result.skipReason, isNotNull, reason: result.key);
      }
      for (final result in failed) {
        expect(
          result.assertions.any((assertion) => !assertion.ok),
          isTrue,
          reason: '${result.key} 失败但没有失败断言',
        );
      }

      // 调试上游可达时，至少一个场景必须真的跑起来（通过或失败都算跑过）。
      if (skipped.length == results.length) {
        fail('全部场景跳过：${skipped.first.skipReason}');
      }
      expect(failed, isEmpty, reason: '失败场景：${failed.map((r) => r.key)}');
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
