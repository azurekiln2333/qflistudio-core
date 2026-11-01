/// Vibe Coding 端到端验收驱动。
///
/// 用法（在 qfli_studio_core 目录）：
///   set QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL
///   dart run tool/vibe_e2e.dart [--scenario key] [--out 报告路径]
///       [--protocol chat_completions|responses|messages]
///
/// 行为：
/// - 缺任一 `QFLI_DEBUG_*` 时全部场景记为 skipped，退出码 0。
/// - 凭据只在进程内使用，报告只含主机名和长度。
/// - 报告默认写到系统临时目录的 `.artifacts/vibe-e2e/`，不进仓库。
///
/// 宿主限制：本包依赖 Flutter，`dart run` 无法加载 `dart:ui`。当前能真正跑
/// 通实时场景的宿主是 `test/vibe_live_e2e_test.dart`（`flutter test`）。本文件
/// 与它共用 `tool/vibe_e2e_runner.dart`，等 SDK 侧适配提供可加载的宿主后即可
/// 直接使用。
library;

import 'dart:io';

import 'package:qfli_studio_core/services/ai_service.dart';

import 'vibe_e2e_report.dart';
import 'vibe_e2e_runner.dart';
import 'vibe_e2e_scenarios.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }
  final startedAt = DateTime.now();
  final runtime = VibeE2eRuntime.fromEnvironment(
    protocol: AiProtocol.parse(options.protocol),
  );

  final results = await runVibeE2eScenarios(
    runtime: runtime,
    only: options.scenario,
    onResult: (result) => stdout.writeln(vibeE2eLine(result.toJson())),
  );
  if (results.isEmpty) {
    stderr.writeln('未知场景 ${options.scenario}');
    exitCode = 2;
    return;
  }

  final report = buildVibeE2eReport(
    generatedAt: startedAt,
    runtime: runtime,
    scenarios: results,
    driverRevision: vibeE2eGitRevision(),
  );
  final file = options.out == null
      ? VibeE2eReportWriter.defaultFile(startedAt)
      : File(options.out!);
  await VibeE2eReportWriter.write(file, report);
  stdout.writeln('报告: ${file.path}');
  stdout.writeln('结论: ${report.status.value}');
  runtime?.close();

  if (report.status == VibeE2eStatus.failed) exitCode = 1;
}

class _Options {
  _Options({
    required this.scenario,
    required this.out,
    required this.protocol,
    required this.help,
  });

  final String? scenario;
  final String? out;
  final String protocol;
  final bool help;

  static _Options parse(List<String> args) {
    String? scenario;
    String? out;
    var protocol = AiProtocol.chat.id;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? next() => i + 1 < args.length ? args[++i] : null;
      switch (arg) {
        case '--scenario':
          scenario = next();
        case '--out':
          out = next();
        case '--protocol':
          protocol = next() ?? protocol;
        case '--help':
        case '-h':
          help = true;
        default:
          stderr.writeln('忽略未知参数 $arg');
      }
    }
    return _Options(
      scenario: scenario,
      out: out,
      protocol: protocol,
      help: help,
    );
  }
}

const String _usage =
    'dart run tool/vibe_e2e.dart [--scenario static_site|python_fix_loop|web_search]\n'
    '    [--out 报告路径] [--protocol chat_completions|responses|messages]\n\n'
    '环境变量：QFLI_DEBUG_BASE_URL、QFLI_DEBUG_API_KEY、QFLI_DEBUG_MODEL。\n'
    '变量缺失时全部场景跳过，退出码 0。\n'
    '实时场景当前请在 qfli_studio_core 里用：\n'
    '    flutter test --no-pub test/vibe_live_e2e_test.dart';
