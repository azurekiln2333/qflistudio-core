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
import 'package:qfli_studio_core/interop/interop_runner.dart';
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart'
    show vibeToolSpecsWithWeb, vibeWebToolsAvailable;
import 'vibe_e2e_local_executor.dart';
import 'vibe_e2e_report.dart';
import 'vibe_e2e_scenarios.dart';
import 'vibe_e2e_transport.dart';
import 'vibe_e2e_web_check.dart';

/// 验收会话用的令牌与传输不碰用户账号，这里只是一个非空占位。
const String kVibeE2eFixtureToken = 'qfli-vibe-e2e-fixture';

/// 在线终端用的令牌：来自环境变量，不是调试上游密钥。
///
/// `run_command` 走 `/api/terminal/exec/stream`，需要本站登录令牌。
/// 缺它时场景会如实报出终端不可用，而不是伪造成功。
const String kVibeE2eTerminalTokenVariable = 'QFLI_E2E_TERMINAL_TOKEN';

/// 场景上报的额外开关变量名：把跳过的原因写明在报告里。
/// 云终端缺令牌时报告里的说明；本机执行器不依赖它。
const String kVibeE2eTerminalTokenMissing =
    '云终端需要 QFLI_E2E_TERMINAL_TOKEN（本站登录令牌，不是调试上游密钥），'
    '默认走本机执行器';

/// 场景运行所需的环境：已就绪的调试上游传输。
class VibeE2eRuntime {
  const VibeE2eRuntime({
    required this.transport,
    required this.protocol,
    required this.credentials,
    this.searchToolsAvailable = false,
    this.terminalToken,
  });

  final VibeDebugTransport transport;
  final AiProtocol protocol;
  final VibeE2eCredentials credentials;
  final bool searchToolsAvailable;

  /// 在线终端令牌；为空时 `run_command` 会真实失败并如实上报。
  final String? terminalToken;

  /// 在线终端是否具备运行条件。
  bool get hasTerminal =>
      terminalToken != null && terminalToken!.trim().isNotEmpty;

  /// 用环境凭据构造运行器；变量缺失返回 null。
  ///
  /// [protocol] 缺省为 `chat_completions`，与调试上游实测可用路径一致。
  static VibeE2eRuntime? fromEnvironment({
    AiProtocol protocol = AiProtocol.chat,
    Map<String, String>? environment,
    bool searchToolsAvailable = false,
  }) {
    final env = environment ?? Platform.environment;
    final credentials = VibeE2eCredentials.fromEnvironment(env);
    if (credentials == null) return null;
    final terminal = env[kVibeE2eTerminalTokenVariable]?.trim();
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
      terminalToken: terminal == null || terminal.isEmpty ? null : terminal,
    );
  }

  /// 报告里的协议名：直接使用设置页持久化的标识（`chat`/`responses`/`messages`）。
  String get protocolId => protocol.id;

  /// 当前工具表是否已带检索工具。
  bool get hasSearchTools =>
      searchToolsAvailable ||
      (vibeWebToolsAvailable && vibeE2eHasSearchTools(vibeToolSpecsWithWeb()));
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
  final terminalToken = runtime.terminalToken;
  final api = _TransportBackedApiClient(
    runtime.transport,
    tokenOverride: terminalToken,
  );
  VibeCodingController? controller;
  try {
    await scenario.prepare?.call(root.path);
    controller = VibeCodingController(
      api: api,
      tokenProvider: () => terminalToken ?? kVibeE2eFixtureToken,
      projectRoot: root.path,
      projectName: 'Vibe E2E ${scenario.key}',
      language: scenario.language,
      endpointProvider: () => AiEndpoint.direct(
        baseUrl: runtime.credentials.baseUrl,
        apiKey: runtime.credentials.apiKey,
        model: runtime.credentials.model,
        protocol: runtime.protocol,
      ),
      onFileChanged: changed.add,
      // 验收专用：run_command 改在宿主机真实执行，报告里记 executor=local。
      interopRunner: InteropRunner(
        transport: VibeLocalExecutionTransport(projectRoot: root.path),
      ),
    );
    final active = controller;
    final finished = Completer<void>();
    var started = false;
    // 实时采集每轮耗时：从用户请求开始，到该轮最后一个工具落定为止。
    final roundDurations = <int>[];
    var roundStart = DateTime.now();
    var lastToolIndex = 0;
    void observe() {
      if (active.phase == VibePhase.running) started = true;
      for (var i = lastToolIndex; i < active.messages.length; i++) {
        final message = active.messages[i];
        if (message.tool == null || message.pending) continue;
        roundDurations.add(
          DateTime.now().difference(roundStart).inMilliseconds,
        );
        roundStart = DateTime.now();
        lastToolIndex = i + 1;
      }
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
    // 轮数按真实助手回合计数：每个 assistant 回复（含工具调用）算一轮。
    final rounds = active.messages
        .where((message) => !message.isUser && message.tool == null)
        .length;
    // 单轮最长耗时：一轮含模型请求与工具执行，决定 524 风险。
    final slowestRound = roundDurations.isEmpty
        ? null
        : roundDurations.reduce((a, b) => a > b ? a : b);
    final extra = <String, Object?>{
      ...await vibeE2eFileEvidence(root.path),
      'roundDurationsMs': roundDurations,
      'executor': kVibeE2eLocalExecutor,
      'cloudTerminal': runtime.hasTerminal ? 'relay' : 'skipped',
      'cloudTerminalReason': runtime.hasTerminal
          ? '已配置本站登录令牌'
          : kVibeE2eTerminalTokenMissing,
      if (scenario.key == 'static_site') ...{
        'htmlCheck': checkVibeHtml(root.path, 'index.html').toJson(),
        'scriptLogic': vibeHtmlHasScriptLogic(
          File(p.join(root.path, 'app.js')).existsSync()
              ? File(p.join(root.path, 'app.js')).readAsStringSync()
              : '',
        ),
      },
    };
    return VibeE2eScenarioResult(
      key: scenario.key,
      status: passed ? VibeE2eStatus.passed : VibeE2eStatus.failed,
      phase: active.phase.name,
      durationMs: elapsed(),
      rounds: rounds,
      modelCalls: runtime.transport.callCount,
      slowestCallMs: runtime.transport.slowestCall?.inMilliseconds,
      slowestRoundMs: slowestRound,
      lastError: active.lastError,
      assistantReply: outcome.assistantReply,
      timeout: timedOut,
      tools: vibeE2eToolEvidence(toolCalls),
      assertions: assertions,
      extra: extra,
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
        await api.resetTerminal(terminalToken ?? kVibeE2eFixtureToken);
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

/// 只实现验收所需两个通道的 `ApiClient` 替身。
///
/// 模型回合直连调试上游，终端事件转发到生产 `terminalEvents`，因此
/// `run_command` 的真实退出码与输出不打折扣。其余成员一律抛错。
class _TransportBackedApiClient implements ApiClient {
  _TransportBackedApiClient(
    this._transport, {
    ApiClient? relay,
    this.tokenOverride,
  }) : _relay = relay ?? ApiClient();

  final VibeDebugTransport _transport;

  /// 真实在线终端（`/api/terminal/exec/stream`）。
  final ApiClient _relay;

  /// 终端令牌；为空时终端会如实报 401/不可用。
  final String? tokenOverride;

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
  Stream<TerminalEvent> terminalEvents(
    String token,
    String command, {
    List<Map<String, String>>? files,
    Future<void>? abortTrigger,
  }) => _relay.terminalEvents(
    token,
    command,
    files: files,
    abortTrigger: abortTrigger,
  );

  @override
  Future<void> resetTerminal(String token) => _relay.resetTerminal(token);

  @override
  Future<Map<String, dynamic>> aiWebSearch(
    String token,
    String query, {
    int limit = 8,
  }) => _relay.aiWebSearch(token, query, limit: limit);

  @override
  Future<Map<String, dynamic>> aiWebFetch(String token, String url) =>
      _relay.aiWebFetch(token, url);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('验收替身不支持 ${invocation.memberName}');

  @override
  String toString() =>
      'VibeE2eApiClient(${_transport.protocol.id} ${_transport.endpoint.host})';
}

/// 让报告 JSON 保持可读；供入口脚本直接复用缩进设置。
String encodeVibeE2eReport(Map<String, Object?> json) =>
    const JsonEncoder.withIndent('  ').convert(json);
