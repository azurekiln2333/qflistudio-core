/// Vibe Coding 端到端验收驱动。
///
/// 用法（在 qfli_studio_core 目录）：
///   set QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL
///   dart run tool/vibe_e2e.dart [--scenario key] [--out 报告路径] [--transport 名称]
///
/// 行为：
/// - 缺任一 `QFLI_DEBUG_*` 时全部场景记为 skipped，退出码 0。
/// - 凭据只在进程内使用，报告只含主机名和长度。
/// - 报告默认写到系统临时目录的 `.artifacts/vibe-e2e/`，不进仓库。
///
/// 当前夹具状态：生产 `ApiConfig.baseUrl` 是编译期常量，调试上游适配由
/// Pi B 发布。适配未就绪时场景记为 skipped 并写明原因，绝不伪造通过。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

import 'vibe_e2e_report.dart';
import 'vibe_e2e_scenarios.dart';

/// 后端中转用的会话令牌；验收不碰用户账号。
const String _fixtureToken = 'qfli-vibe-e2e-fixture';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }
  final startedAt = DateTime.now();
  final credentials = VibeE2eCredentials.fromEnvironment();

  final selected = [
    for (final scenario in vibeE2eScenarios)
      if (options.scenario == null || options.scenario == scenario.key)
        scenario,
  ];
  if (selected.isEmpty) {
    stderr.writeln('未知场景 ${options.scenario}');
    exitCode = 2;
    return;
  }

  final results = <VibeE2eScenarioResult>[];
  for (final scenario in selected) {
    final result = await _runScenario(scenario, credentials, options);
    results.add(result);
    stdout.writeln(vibeE2eLine(result.toJson()));
  }

  final report = VibeE2eReport(
    generatedAt: startedAt,
    environment:
        credentials?.redacted(protocol: options.protocol) ??
        {
          'protocol': options.protocol,
          'keyPresent': false,
          'missing':
              'QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL',
        },
    scenarios: results,
    driverRevision: _gitRevision(),
  );
  final file = options.out == null
      ? VibeE2eReportWriter.defaultFile(startedAt)
      : File(options.out!);
  await VibeE2eReportWriter.write(file, report);
  stdout.writeln('报告: ${file.path}');
  stdout.writeln('结论: ${report.status.value}');

  if (report.status == VibeE2eStatus.failed) exitCode = 1;
}

/// 运行一个场景。任何异常都收敛为失败结果，报告照常写出。
Future<VibeE2eScenarioResult> _runScenario(
  VibeE2eScenario scenario,
  VibeE2eCredentials? credentials,
  _Options options,
) async {
  final startedAt = DateTime.now();
  int elapsed() => DateTime.now().difference(startedAt).inMilliseconds;

  if (credentials == null) {
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: VibeE2eStatus.skipped,
      phase: VibePhase.idle.name,
      durationMs: elapsed(),
      skipReason:
          '缺少 QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL',
    );
  }
  if (options.transport == null) {
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: VibeE2eStatus.skipped,
      phase: VibePhase.idle.name,
      durationMs: elapsed(),
      skipReason:
          '调试上游适配未就绪：ApiConfig.baseUrl 是编译期常量，'
          '等 Pi B 发布可注入入口后加 --transport',
    );
  }
  if (scenario.requiresSearchTools && !options.searchToolsReady) {
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: VibeE2eStatus.skipped,
      phase: VibePhase.idle.name,
      durationMs: elapsed(),
      skipReason: '检索工具未发布，等 Pi B 交付 web_search / web_fetch',
    );
  }

  final previousProfile = StudioProfile.current;
  StudioProfile.current = null;
  final root = await Directory.systemTemp.createTemp('qfli-vibe-e2e-');
  final changed = <String>[];
  final api = ApiClient();
  VibeCodingController? controller;
  try {
    await scenario.prepare?.call(root.path);
    controller = VibeCodingController(
      api: api,
      tokenProvider: () => _fixtureToken,
      projectRoot: root.path,
      projectName: 'Vibe E2E ${scenario.key}',
      language: scenario.language,
      onFileChanged: changed.add,
    );
    final controllerRef = controller;
    final finished = Completer<void>();
    var started = false;
    void observe() {
      if (controllerRef.phase == VibePhase.running) started = true;
      if (!started || !controllerRef.canSend || finished.isCompleted) return;
      finished.complete();
    }

    controllerRef.addListener(observe);
    controllerRef.send(scenario.prompt);
    var timedOut = false;
    try {
      await finished.future.timeout(scenario.timeout);
    } on TimeoutException {
      timedOut = true;
    } finally {
      controllerRef.removeListener(observe);
    }
    if (timedOut && controllerRef.canCancel) await controllerRef.cancel();

    final toolCalls = controllerRef.messages
        .map((message) => message.tool)
        .whereType<VibeToolCall>()
        .toList();
    final outcome = VibeE2eScenarioOutcome(
      projectRoot: root.path,
      phase: controllerRef.phase,
      toolCalls: toolCalls,
      messages: controllerRef.messages,
      changedFiles: changed,
    );
    final assertions = <VibeE2eAssertion>[
      if (timedOut)
        VibeE2eAssertion(
          name: 'within_timeout',
          ok: false,
          detail: '${scenario.timeout.inMinutes} 分钟超时',
        ),
      ...?scenario.assertions?.call(outcome),
    ];
    final passed = assertions.isNotEmpty && assertions.every((a) => a.ok);
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: passed ? VibeE2eStatus.passed : VibeE2eStatus.failed,
      phase: controllerRef.phase.name,
      durationMs: elapsed(),
      lastError: controllerRef.lastError,
      assistantReply: outcome.assistantReply,
      timeout: timedOut,
      tools: vibeE2eToolEvidence(toolCalls),
      assertions: assertions,
      extra: await vibeE2eFileEvidence(root.path),
    );
  } on Object catch (error, stack) {
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: VibeE2eStatus.failed,
      phase: controller?.phase.name ?? VibePhase.idle.name,
      durationMs: elapsed(),
      lastError: '$error',
      tools: vibeE2eToolEvidence(
        controller?.messages
                .map((message) => message.tool)
                .whereType<VibeToolCall>()
                .toList() ??
            const [],
      ),
      assertions: [
        VibeE2eAssertion(
          name: 'driver_exception',
          ok: false,
          detail: stack.toString().split('\n').first,
        ),
      ],
    );
  } finally {
    if (controller != null) {
      if (controller.canCancel) await controller.cancel();
      try {
        await api.resetTerminal(_fixtureToken);
      } on Object {
        // 会话回收失败不影响证据。
      }
      controller.dispose();
    }
    api.close();
    StudioProfile.current = previousProfile;
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // 临时目录由系统回收。
    }
  }
}

String? _gitRevision() {
  try {
    final result = Process.runSync('git', [
      'rev-parse',
      '--short',
      'HEAD',
    ], workingDirectory: p.dirname(p.dirname(Platform.script.toFilePath())));
    if (result.exitCode != 0) return null;
    final text = (result.stdout as String).trim();
    return text.isEmpty ? null : text;
  } on Object {
    return null;
  }
}

class _Options {
  _Options({
    required this.scenario,
    required this.out,
    required this.transport,
    required this.protocol,
    required this.searchToolsReady,
    required this.help,
  });

  final String? scenario;
  final String? out;
  final String? transport;
  final String protocol;
  final bool searchToolsReady;
  final bool help;

  static _Options parse(List<String> args) {
    String? scenario;
    String? out;
    String? transport;
    var protocol = 'backend_default';
    var searchToolsReady = false;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? next() => i + 1 < args.length ? args[++i] : null;
      switch (arg) {
        case '--scenario':
          scenario = next();
        case '--out':
          out = next();
        case '--transport':
          transport = next();
        case '--protocol':
          protocol = next() ?? protocol;
        case '--search-tools':
          searchToolsReady = true;
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
      transport: transport,
      protocol: protocol,
      searchToolsReady: searchToolsReady,
      help: help,
    );
  }
}

const String _usage =
    'dart run tool/vibe_e2e.dart [--scenario static_site|python_fix_loop|web_search]\n'
    '    [--out 报告路径] [--transport 适配名称] [--protocol chat_completions]\n'
    '    [--search-tools]\n\n'
    '环境变量：QFLI_DEBUG_BASE_URL、QFLI_DEBUG_API_KEY、QFLI_DEBUG_MODEL。\n'
    '变量缺失时全部场景跳过，退出码 0。';
