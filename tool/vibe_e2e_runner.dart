/// 验收场景执行器：把控制器跑一轮并收敛成报告条目。
///
/// 两个入口共用这里的逻辑：
/// - `tool/vibe_e2e.dart`（`dart run`，需要能被 SDK 侧适配后调用）
/// - `test/vibe_live_e2e_test.dart`（`flutter test`，当前唯一能加载本包的宿主）
///
/// 这里不做断言以外的裁剪：阶段、工具调用、真实退出码和超时都原样进入报告。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart'
    show vibeToolSpecs;
import 'vibe_e2e_report.dart';
import 'vibe_e2e_scenarios.dart';
import 'vibe_e2e_transport.dart';

/// 验收会话用的令牌与传输不碰用户账号，这里只是一个非空占位。
const String kVibeE2eFixtureToken = 'qfli-vibe-e2e-fixture';

/// 场景运行所需的环境：已就绪的调试上游传输。
class VibeE2eRuntime {
  const VibeE2eRuntime({
    required this.transport,
    required this.protocol,
    required this.credentials,
    this.searchToolsAvailable = false,
  });

  final VibeDebugTransport transport;
  final AiProtocol protocol;
  final VibeE2eCredentials credentials;
  final bool searchToolsAvailable;

  /// 用环境凭据构造运行器；变量缺失返回 null。
  ///
  /// [protocol] 缺省为 `chat_completions`，与调试上游实测可用路径一致。
  static VibeE2eRuntime? fromEnvironment({
    AiProtocol protocol = AiProtocol.chat,
    Map<String, String>? environment,
    bool searchToolsAvailable = false,
  }) {
    final credentials = VibeE2eCredentials.fromEnvironment(environment);
    if (credentials == null) return null;
    return VibeE2eRuntime(
      transport: VibeDebugTransport(
        baseUrl: credentials.baseUrl,
        apiKey: credentials.apiKey,
        model: credentials.model,
        protocol: protocol,
      ),
      protocol: protocol,
      credentials: credentials,
      searchToolsAvailable: searchToolsAvailable,
    );
  }

  /// 报告里的协议名；与 [AiProtocol] 的 id 一致，便于对回设置页。
  String get protocolId => protocol.id;

  /// 当前工具表是否已带检索工具。
  bool get hasSearchTools =>
      searchToolsAvailable || vibeE2eHasSearchTools(vibeToolSpecs());
  void close() => transport.close();
}

/// 按 [vibeE2eScenarios] 顺序跑选中的场景，返回报告条目。
Future<List<VibeE2eScenarioResult>> runVibeE2eScenarios({
  required VibeE2eRuntime? runtime,
  String? only,
  void Function(VibeE2eScenarioResult result)? onResult,
}) async {
  final selected = [
    for (final scenario in vibeE2eScenarios)
      if (only == null || only == scenario.key) scenario,
  ];
  final results = <VibeE2eScenarioResult>[];
  for (final scenario in selected) {
    final result = await runVibeE2eScenario(scenario, runtime);
    results.add(result);
    onResult?.call(result);
  }
  return results;
}

/// 跑一个场景。缺运行时或检索工具时返回 skipped，绝不伪造通过。
Future<VibeE2eScenarioResult> runVibeE2eScenario(
  VibeE2eScenario scenario,
  VibeE2eRuntime? runtime,
) async {
  final startedAt = DateTime.now();
  int elapsed() => DateTime.now().difference(startedAt).inMilliseconds;

  if (runtime == null) {
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: VibeE2eStatus.skipped,
      phase: VibePhase.idle.name,
      durationMs: elapsed(),
      skipReason:
          '缺少 QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL',
    );
  }
  if (scenario.requiresSearchTools && !runtime.hasSearchTools) {
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: VibeE2eStatus.skipped,
      phase: VibePhase.idle.name,
      durationMs: elapsed(),
      skipReason: '检索工具未发布，等 web_search / web_fetch 进入 vibeToolSpecs',
    );
  }

  final previousProfile = StudioProfile.current;
  StudioProfile.current = null;
  final root = await Directory.systemTemp.createTemp('qfli-vibe-e2e-');
  final changed = <String>[];
  final api = _TransportBackedApiClient(runtime.transport);
  VibeCodingController? controller;
  try {
    await scenario.prepare?.call(root.path);
    controller = VibeCodingController(
      api: api,
      tokenProvider: () => kVibeE2eFixtureToken,
      projectRoot: root.path,
      projectName: 'Vibe E2E ${scenario.key}',
      language: scenario.language,
      onFileChanged: changed.add,
    );
    final active = controller;
    final finished = Completer<void>();
    var started = false;
    void observe() {
      if (active.phase == VibePhase.running) started = true;
      if (!started || !active.canSend || finished.isCompleted) return;
      finished.complete();
    }

    active.addListener(observe);
    active.send(scenario.prompt);
    var timedOut = false;
    try {
      await finished.future.timeout(scenario.timeout);
    } on TimeoutException {
      timedOut = true;
    } finally {
      active.removeListener(observe);
    }
    if (timedOut && active.canCancel) await active.cancel();

    final toolCalls = active.messages
        .map((message) => message.tool)
        .whereType<VibeToolCall>()
        .toList();
    final outcome = VibeE2eScenarioOutcome(
      projectRoot: root.path,
      phase: active.phase,
      toolCalls: toolCalls,
      messages: active.messages,
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
      phase: active.phase.name,
      durationMs: elapsed(),
      lastError: active.lastError,
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
        await api.resetTerminal(kVibeE2eFixtureToken);
      } on Object {
        // 会话回收失败不影响证据。
      }
      controller.dispose();
    }
    StudioProfile.current = previousProfile;
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // 临时目录交给系统回收。
    }
  }
}

/// 组装一份报告；缺运行时只写 `keyPresent: false`。
VibeE2eReport buildVibeE2eReport({
  required DateTime generatedAt,
  required VibeE2eRuntime? runtime,
  required List<VibeE2eScenarioResult> scenarios,
  String? driverRevision,
}) => VibeE2eReport(
  generatedAt: generatedAt,
  environment: runtime == null
      ? {
          'protocol': 'backend_default',
          'keyPresent': false,
          'missing':
              'QFLI_DEBUG_BASE_URL / QFLI_DEBUG_API_KEY / QFLI_DEBUG_MODEL',
        }
      : runtime.credentials.redacted(protocol: runtime.protocolId),
  scenarios: scenarios,
  driverRevision: driverRevision,
);

/// 被测仓库 HEAD，便于把报告对回代码。
String? vibeE2eGitRevision({String? workingDirectory}) {
  try {
    final result = Process.runSync(
      'git',
      ['rev-parse', '--short', 'HEAD'],
      workingDirectory:
          workingDirectory ??
          p.dirname(p.dirname(Platform.script.toFilePath())),
    );
    if (result.exitCode != 0) return null;
    final text = (result.stdout as String).trim();
    return text.isEmpty ? null : text;
  } on Object {
    return null;
  }
}

/// 只需要工具方法的最小 `ApiClient` 替身。
///
/// 生产 `ApiClient.aiChat` 走 `/api/ai/chat`；验收要直连调试上游，而控制器
/// 只依赖这一个方法，因此这里做窄替身而不是改生产类。
class _TransportBackedApiClient implements ApiClient {
  _TransportBackedApiClient(this._transport);

  final VibeDebugTransport _transport;

  @override
  Future<AiChatResult> aiChat({
    required String token,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<void>? abortTrigger,
    AiEndpoint? endpoint,
  }) async {
    // 控制器当前不传 endpoint；传了 relay 说明有人把它接回了生产链路。
    final target = endpoint ?? const AiEndpoint.relay();
    if (target.route != AiRoute.direct) {
      throw ApiException(
        '验收替身只直连调试上游，不经过中转',
        details: const {'code': 'VIBE_E2E_RELAY_REFUSED'},
      );
    }
    final reply = await _transport.chat(
      messages: messages,
      tools: tools,
      abortTrigger: abortTrigger,
    );
    return AiChatResult(
      model: reply.model,
      content: reply.content,
      rawMessage: reply.rawMessage,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('验收替身只实现 aiChat，调用了 ${invocation.memberName}');

  @override
  String toString() =>
      'VibeE2eApiClient(${_transport.protocol.id} ${_transport.endpoint.host})';
}

/// 让报告 JSON 保持可读；供入口脚本直接复用缩进设置。
String encodeVibeE2eReport(Map<String, Object?> json) =>
    const JsonEncoder.withIndent('  ').convert(json);
