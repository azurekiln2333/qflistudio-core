// The only place that speaks to the `herdr` CLI.
//
// Everything goes through the public command surface (`agent list`, `agent
// prompt`, `pane read`, ...). HerdrHost never reads Herdr's socket, config or
// state files: those are private to Herdr, and a version bump may move them.
//
// Process creation is injected as [HerdrProcessRunner] so tests assert argv and
// parse fixtures without spawning anything. `herdr` is never run through a
// shell: every argument is one argv element, so text that contains spaces,
// quotes or `;` reaches Herdr literally.

import 'dart:async';
import 'dart:convert';

import '../harness_host.dart' show HarnessCapability;
import 'herdr_models.dart';

typedef Json = Map<String, dynamic>;

/// Outcome of one CLI invocation.
class HerdrProcessResult {
  const HerdrProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.spawnError,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// `ENOENT` when the binary vanished between discovery and the call.
  final String? spawnError;

  bool get succeeded => !timedOut && spawnError == null && exitCode == 0;
}

/// Starts `herdr` with [argv] and captures its output.
///
/// Implementations must not run a shell, must bound captured output and must
/// kill the child when [timeout] expires.
typedef HerdrProcessRunner =
    Future<HerdrProcessResult> Function(
      List<String> argv, {
      String? workingDirectory,
      required Duration timeout,
    });

/// Whether [path] exists and is executable. Injected so discovery is testable
/// without touching the real filesystem.
typedef HerdrPathProbe = bool Function(String path);

/// Lists the subdirectories of [path]; empty when it does not exist.
typedef HerdrDirectoryLister = List<String> Function(String path);

/// Resolves the Herdr executable, or null when it is not installed.
///
/// The optional arguments of the platform implementation are deliberately not
/// part of the type: a host only says "use the user setting if there is one".
typedef HerdrExecutableLocator =
    Future<String?> Function({String? explicitPath});

/// Why a Herdr call failed, so the UI can branch without parsing prose.
enum HerdrFailure {
  /// The executable is missing or cannot run.
  unavailable,

  /// Herdr is installed but its server is not running.
  serverDown,
  invalidArgument,
  notFound,
  agentBlocked,
  agentNotReady,
  promptStalled,
  timeout,
  failed,
}

class HerdrException implements Exception {
  const HerdrException(this.failure, this.message, {this.herdrCode});

  final HerdrFailure failure;

  /// Chinese, user-facing: the Agents surface shows this verbatim.
  final String message;

  /// Raw Herdr code (`agent_blocked`, `pane_not_found`, ...) when there is one.
  final String? herdrCode;

  @override
  String toString() => message;
}

/// Typed wrapper over the `herdr` command line.
class HerdrCli {
  HerdrCli({
    required this.executable,
    required HerdrProcessRunner runner,
    this.timeout = const Duration(seconds: 30),
  }) : _runner = runner;

  /// Absolute path, or the bare name when PATH resolution is intended.
  final String executable;
  final Duration timeout;
  final HerdrProcessRunner _runner;

  /// Herdr's own agent kinds. Reused from the remote-control mirror so the two
  /// layers cannot drift.
  static const List<String> agentKinds = <String>[
    'pi',
    'claude',
    'codex',
    'gemini',
    'cursor',
    'devin',
    'agy',
    'cline',
    'omp',
    'mastracode',
    'opencode',
    'copilot',
    'kimi',
    'kiro',
    'droid',
    'amp',
    'grok',
    'hermes',
    'kilo',
    'qodercli',
    'qwen',
    'letta',
    'maki',
    'muse',
  ];

  /// Logical key names accepted by `agent send-keys` / `pane send-keys`.
  static const List<String> keyNames = <String>[
    'enter',
    'esc',
    'tab',
    'shift+tab',
    'backspace',
    'delete',
    'up',
    'down',
    'left',
    'right',
    'home',
    'end',
    'pageup',
    'pagedown',
    'ctrl+a',
    'ctrl+b',
    'ctrl+c',
    'ctrl+d',
    'ctrl+e',
    'ctrl+k',
    'ctrl+l',
    'ctrl+n',
    'ctrl+p',
    'ctrl+r',
    'ctrl+u',
    'ctrl+w',
  ];

  static final RegExp _paneId = RegExp(r'^w[0-9A-Za-z]+:p[0-9A-Za-z]+$');

  static final RegExp _ctrlKey = RegExp(r'^ctrl\+[a-z]$');

  static bool isPaneId(String value) => _paneId.hasMatch(value);

  // -------------------------------------------------------------------------
  // Discovery and health
  // -------------------------------------------------------------------------

  /// `herdr --version` → `0.9.3`, or throws [HerdrFailure.unavailable].
  Future<String> version() async {
    final result = await _invoke(const <String>['--version']);
    if (result.timedOut) {
      throw const HerdrException(HerdrFailure.timeout, '检查 Herdr 版本超时');
    }
    final match = RegExp(
      r'^herdr\s+(\S+)\s*$',
      multiLine: true,
    ).firstMatch(result.stdout);
    if (!result.succeeded || match == null) {
      throw HerdrException(
        HerdrFailure.unavailable,
        _firstLine(result.stderr).isEmpty
            ? '无法运行 Herdr（退出码 ${result.exitCode}）'
            : '无法运行 Herdr：${_firstLine(result.stderr)}',
      );
    }
    return match.group(1)!;
  }

  /// `herdr status` prints indented `key: value` text, not JSON.
  Future<HerdrServerStatus> serverStatus() async {
    final result = await _invoke(const <String>['status']);
    if (!result.succeeded) {
      throw HerdrException(
        HerdrFailure.serverDown,
        'Herdr 服务不可用：${_firstLine(result.stderr).isEmpty ? '退出码 ${result.exitCode}' : _firstLine(result.stderr)}',
      );
    }
    return _parseStatus(result.stdout);
  }

  static HerdrServerStatus _parseStatus(String text) {
    String? clientVersion;
    int? clientProtocol;
    String? serverVersion;
    String? socket;
    var serverRunning = false;
    var section = '';
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      if (rawLine.trim().isEmpty) continue;
      final indented = RegExp(r'^\s').hasMatch(rawLine);
      final match = RegExp(
        r'^\s*([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$',
      ).firstMatch(rawLine);
      if (match == null) continue;
      final key = match.group(1)!.toLowerCase();
      final value = match.group(2)!.trim();
      if (!indented && value.isEmpty) {
        section = key;
        continue;
      }
      if (section == 'client') {
        if (key == 'version') clientVersion = value;
        if (key == 'protocol') clientProtocol = int.tryParse(value);
      } else if (section == 'server') {
        if (key == 'status') serverRunning = value.toLowerCase() == 'running';
        if (key == 'version') serverVersion = value;
        if (key == 'socket') socket = value;
      }
    }
    return HerdrServerStatus(
      clientVersion: clientVersion,
      clientProtocol: clientProtocol,
      serverRunning: serverRunning,
      serverVersion: serverVersion,
      socket: socket,
    );
  }

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Future<List<HerdrAgentInfo>> agents() async {
    final result = await _json(const <String>['agent', 'list']);
    return _asList(result['agents']).map(HerdrAgentInfo.fromJson).toList();
  }

  Future<List<HerdrWorkspaceInfo>> workspaces() async {
    final result = await _json(const <String>['workspace', 'list']);
    return _asList(
      result['workspaces'],
    ).map(HerdrWorkspaceInfo.fromJson).toList();
  }

  Future<HerdrAgentInfo> agent(String target) async {
    final result = await _json(<String>[
      'agent',
      'get',
      _requireTarget(target),
    ]);
    final raw = result['agent'];
    if (raw is! Json) {
      throw const HerdrException(HerdrFailure.failed, 'Herdr 未返回 agent 信息');
    }
    return HerdrAgentInfo.fromJson(raw);
  }

  /// `pane read` prints raw screen text, not JSON.
  Future<String> readPane(
    String paneId, {
    String source = 'recent',
    int lines = 200,
    bool ansi = false,
  }) async {
    final result = await _invoke(<String>[
      'pane',
      'read',
      _requirePaneId(paneId),
      '--source',
      _requireReadSource(source),
      '--lines',
      '${lines < 1 ? 1 : lines}',
      if (ansi) '--ansi',
    ], timeout: timeout);
    if (result.timedOut) {
      throw HerdrException(HerdrFailure.timeout, '读取面板 $paneId 超时');
    }
    final raw = result.stdout;
    // A failed read still prints a JSON error envelope; never show that as
    // terminal output.
    final error = _errorEnvelope(raw);
    if (error != null) {
      throw _failureFromEnvelope(error);
    }
    if (!result.succeeded && raw.trim().isEmpty) {
      throw HerdrException(
        HerdrFailure.failed,
        _firstLine(result.stderr).isEmpty
            ? '读取面板失败（退出码 ${result.exitCode}）'
            : _firstLine(result.stderr),
      );
    }
    return raw;
  }

  // -------------------------------------------------------------------------
  // Input
  // -------------------------------------------------------------------------

  /// Submits [text] as a task to the agent in [target].
  ///
  /// Never retried by callers: Herdr rejects a blocked agent before writing
  /// anything, and a stalled submission must be inspected on the desktop.
  Future<HerdrCommandReport> prompt(
    String target,
    String text, {
    bool wait = false,
    int? timeoutMs,
  }) async {
    final args = <String>['agent', 'prompt', _requireTarget(target), text];
    var budget = timeout;
    if (timeoutMs != null) {
      args.addAll(<String>['--timeout', '$timeoutMs']);
      budget = Duration(milliseconds: timeoutMs + 10000);
    }
    if (wait) {
      args.add('--wait');
      if (timeoutMs == null) {
        args.addAll(<String>['--timeout', '120000']);
        budget = const Duration(milliseconds: 130000);
      }
    }
    final result = await _json(args, timeout: budget);
    return HerdrCommandReport.fromResult(result, '已向 $target 发送提示词');
  }

  /// Types literal text into a pane (terminal semantics, not a prompt).
  Future<HerdrCommandReport> sendText(String paneId, String text) async {
    final result = await _json(<String>[
      'pane',
      'send-text',
      _requirePaneId(paneId),
      text,
    ], allowEmpty: true);
    return HerdrCommandReport.fromResult(result, '已写入面板 $paneId');
  }

  /// Sends logical keys to a pane (pane id) or to a named agent.
  ///
  /// The two are different verbs: `agent send-keys` needs an agent, so a shell
  /// pane — which hosts none — could never receive Enter or an arrow key.
  Future<HerdrCommandReport> sendKeys(String target, List<String> keys) async {
    final t = _requireTarget(target);
    final list = <String>[for (final key in keys) _requireKey(key)];
    if (list.isEmpty) {
      throw const HerdrException(HerdrFailure.invalidArgument, '没有要发送的按键');
    }
    final argv = isPaneId(t)
        ? <String>['pane', 'send-keys', t, ...list]
        : <String>['agent', 'send-keys', t, ...list];
    final result = await _json(argv, allowEmpty: true);
    return HerdrCommandReport.fromResult(result, '已发送按键 ${list.join(' ')}');
  }

  /// Blocks until [target] reaches one of [until] (default: idle/done/blocked).
  ///
  /// This is the status-refresh primitive: a long wait instead of tight polling.
  /// A timeout is normal and reported as [HerdrFailure.timeout] so the caller can
  /// simply refresh the list and wait again.
  Future<HerdrCommandReport> wait(
    String target, {
    List<HerdrAgentStatus> until = const <HerdrAgentStatus>[],
    Duration budget = const Duration(seconds: 20),
  }) async {
    final args = <String>['agent', 'wait', _requireTarget(target)];
    for (final status in until) {
      args.addAll(<String>['--until', status.name]);
    }
    args.addAll(<String>['--timeout', '${budget.inMilliseconds}']);
    final result = await _json(
      args,
      timeout: budget + const Duration(seconds: 5),
    );
    return HerdrCommandReport.fromResult(result, '$target 已到达等待状态');
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Creates a workspace and returns its root pane id.
  Future<String> createWorkspace({
    required String cwd,
    String? label,
    bool focus = false,
  }) async {
    final result = await _json(<String>[
      'workspace',
      'create',
      '--cwd',
      cwd,
      if (label != null && label.trim().isNotEmpty) ...<String>[
        '--label',
        label.trim(),
      ],
      focus ? '--focus' : '--no-focus',
    ], timeout: const Duration(seconds: 60));
    final pane = result['root_pane'];
    final paneId = pane is Json ? pane['pane_id'] : null;
    if (paneId is! String || paneId.isEmpty) {
      throw const HerdrException(HerdrFailure.failed, 'Herdr 未返回新工作区的面板');
    }
    return paneId;
  }

  /// Starts a supported agent in an existing interactive pane.
  Future<HerdrAgentInfo> startAgent({
    required String name,
    required String kind,
    required String paneId,
    List<String> args = const <String>[],
  }) async {
    if (!agentKinds.contains(kind)) {
      throw HerdrException(
        HerdrFailure.invalidArgument,
        'Herdr 不支持 $kind 这个 agent',
      );
    }
    final result = await _json(<String>[
      'agent',
      'start',
      _requireAgentName(name),
      '--kind',
      kind,
      '--pane',
      _requirePaneId(paneId),
      if (args.isNotEmpty) ...<String>['--', ...args],
    ], timeout: const Duration(seconds: 320));
    final raw = result['agent'];
    if (raw is! Json) {
      throw const HerdrException(HerdrFailure.failed, 'Herdr 未返回启动后的 agent 信息');
    }
    return HerdrAgentInfo.fromJson(raw);
  }

  /// Closes [paneId]. Ending a session; the caller must have confirmed first.
  Future<void> closePane(String paneId) async {
    await _json(<String>['pane', 'close', _requirePaneId(paneId)]);
  }

  // -------------------------------------------------------------------------
  // Plumbing
  // -------------------------------------------------------------------------

  Future<HerdrProcessResult> _invoke(
    List<String> argv, {
    Duration? timeout,
    String? workingDirectory,
  }) async {
    final result = await _runner(
      argv,
      workingDirectory: workingDirectory,
      timeout: timeout ?? this.timeout,
    );
    if (result.spawnError != null) {
      throw HerdrException(
        HerdrFailure.unavailable,
        result.spawnError == 'ENOENT'
            ? '找不到 Herdr，请先安装或设置 Herdr 路径'
            : '无法启动 Herdr：${result.spawnError}',
      );
    }
    return result;
  }

  Future<Json> _json(
    List<String> argv, {
    Duration? timeout,
    bool allowEmpty = false,
  }) async {
    final result = await _invoke(argv, timeout: timeout);
    if (result.timedOut) {
      throw HerdrException(HerdrFailure.timeout, 'herdr ${argv.first} 超时');
    }
    final text = result.stdout.trim();
    if (text.isEmpty) {
      // Void mutations legitimately print nothing on success.
      if (allowEmpty && result.succeeded) return const <String, dynamic>{};
      throw HerdrException(
        HerdrFailure.failed,
        'Herdr 没有返回内容（${_firstLine(result.stderr).ifEmpty('退出码 ${result.exitCode}')}）',
      );
    }
    final decoded = _tryDecode(text);
    final error = _errorEnvelope(text);
    if (error != null) throw _failureFromEnvelope(error);
    if (decoded == null) {
      throw HerdrException(
        HerdrFailure.failed,
        'Herdr 返回了无法解析的内容：${_firstLine(text)}',
      );
    }
    final parsed = decoded['result'];
    if (parsed is! Json) {
      throw const HerdrException(
        HerdrFailure.failed,
        'Herdr 返回的内容缺少 result 字段',
      );
    }
    return parsed;
  }

  HerdrException _failureFromEnvelope(_HerdrErrorEnvelope error) {
    final code = error.code;
    switch (code) {
      case 'pane_not_found':
        return HerdrException(
          HerdrFailure.notFound,
          '面板不存在或已关闭（${error.message}）',
          herdrCode: code,
        );
      case 'agent_not_found':
        return HerdrException(
          HerdrFailure.notFound,
          '找不到该 agent，可能已退出或改名（${error.message}）',
          herdrCode: code,
        );
      case 'agent_blocked':
        return HerdrException(
          HerdrFailure.agentBlocked,
          'agent 正在等待确认或提问，请先在电脑上处理（${error.message}）',
          herdrCode: code,
        );
      case 'agent_not_ready':
        return HerdrException(
          HerdrFailure.agentNotReady,
          'agent 还没准备好接收输入，请稍候再试（${error.message}）',
          herdrCode: code,
        );
      case 'agent_prompt_stalled':
        return HerdrException(
          HerdrFailure.promptStalled,
          '提示已发送但未观察到 agent 开始工作，请到电脑上确认，不要重复发送（${error.message}）',
          herdrCode: code,
        );
      case 'pane_send_failed':
        return HerdrException(
          HerdrFailure.failed,
          '无法向面板写入，请检查当前面板状态和终端内容以确认输入是否已送达；不会自动重发（${error.message}）',
          herdrCode: code,
        );
      case 'connection_closed':
        return HerdrException(
          HerdrFailure.failed,
          '输入连接已断开，无法确认本次输入是否送达；不会自动重发（${error.message}）',
          herdrCode: code,
        );
      case 'timeout':
        return HerdrException(
          HerdrFailure.timeout,
          '等待超时（${error.message}）',
          herdrCode: code,
        );
      default:
        return HerdrException(
          HerdrFailure.failed,
          error.message.isEmpty ? 'Herdr 返回了未知错误' : error.message,
          herdrCode: code,
        );
    }
  }

  static String _requireTarget(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const HerdrException(HerdrFailure.invalidArgument, '缺少 agent 目标');
    }
    // A leading dash would be read as a flag by the CLI, and control characters
    // break Herdr's own single-line labels.
    if (trimmed.startsWith('-') ||
        trimmed.contains(RegExp(r'[\u0000-\u001f]'))) {
      throw const HerdrException(HerdrFailure.invalidArgument, 'agent 目标不合法');
    }
    return trimmed;
  }

  static String _requireAgentName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('-') ||
        trimmed.contains(RegExp(r'[\u0000-\u001f]'))) {
      throw const HerdrException(HerdrFailure.invalidArgument, 'agent 名称不合法');
    }
    return trimmed;
  }

  static String _requirePaneId(String value) {
    if (!isPaneId(value)) {
      throw HerdrException(HerdrFailure.invalidArgument, '面板 ID 不合法：$value');
    }
    return value;
  }

  static String _requireKey(String key) {
    if (!keyNames.contains(key) && !_ctrlKey.hasMatch(key)) {
      throw HerdrException(HerdrFailure.invalidArgument, '不支持的按键：$key');
    }
    return key;
  }

  static String _requireReadSource(String source) {
    const sources = <String>[
      'visible',
      'recent',
      'recent-unwrapped',
      'detection',
    ];
    if (!sources.contains(source)) {
      throw HerdrException(HerdrFailure.invalidArgument, '不支持的读取来源：$source');
    }
    return source;
  }

  static List<Json> _asList(Object? value) => <Json>[
    if (value is List)
      for (final item in value)
        if (item is Json) item,
  ];

  static Json? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Json ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static _HerdrErrorEnvelope? _errorEnvelope(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') || !trimmed.contains('"error"')) return null;
    final decoded = _tryDecode(trimmed);
    if (decoded == null) return null;
    final error = decoded['error'];
    if (error is! Json) return null;
    return _HerdrErrorEnvelope(
      code: error['code'] is String ? error['code'] as String : null,
      message: error['message'] is String ? error['message'] as String : '',
    );
  }

  static String _firstLine(String text) {
    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return '';
  }
}

class _HerdrErrorEnvelope {
  const _HerdrErrorEnvelope({required this.code, required this.message});

  final String? code;
  final String message;
}

/// Summary of a completed control action, as far as the harness layer needs it.
class HerdrCommandReport {
  const HerdrCommandReport({required this.action, required this.summary});

  factory HerdrCommandReport.fromResult(Json result, String fallback) {
    final type = result['type'] is String ? result['type'] as String : 'ok';
    return HerdrCommandReport(action: type, summary: fallback);
  }

  final String action;
  final String summary;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// Provider descriptor for one Herdr agent kind.
class HerdrProviderSpec {
  const HerdrProviderSpec({
    required this.id,
    required this.label,
    required this.executable,
    this.verified = true,
  });

  final String id;
  final String label;

  /// Canonical executable Herdr launches for this kind.
  final String executable;

  /// Whether [executable] is a known-correct name. For a kind Herdr supports but
  /// this table does not list, the executable is only a guess, so its absence
  /// from PATH must not hide the entry.
  final bool verified;

  static const HerdrProviderSpec shell = HerdrProviderSpec(
    id: 'shell',
    label: 'Shell',
    executable: '',
  );

  static HerdrProviderSpec forKind(String kind) {
    for (final spec in _specs) {
      if (spec.id == kind) return spec;
    }
    // An unknown-but-supported Herdr kind still gets a truthful entry: its
    // executable name is the kind itself, which is how Herdr's manifests name
    // most of them.
    return HerdrProviderSpec(
      id: kind,
      label: kind,
      executable: kind,
      verified: false,
    );
  }

  static const List<HerdrProviderSpec> _specs = <HerdrProviderSpec>[
    HerdrProviderSpec(id: 'pi', label: 'Pi', executable: 'pi'),
    HerdrProviderSpec(id: 'claude', label: 'Claude Code', executable: 'claude'),
    HerdrProviderSpec(id: 'codex', label: 'Codex', executable: 'codex'),
    HerdrProviderSpec(id: 'gemini', label: 'Gemini CLI', executable: 'gemini'),
    HerdrProviderSpec(
      id: 'cursor',
      label: 'Cursor',
      executable: 'cursor-agent',
    ),
    HerdrProviderSpec(
      id: 'opencode',
      label: 'OpenCode',
      executable: 'opencode',
    ),
    HerdrProviderSpec(id: 'copilot', label: 'Copilot', executable: 'copilot'),
    HerdrProviderSpec(id: 'qwen', label: 'Qwen Code', executable: 'qwen'),
    HerdrProviderSpec(id: 'amp', label: 'Amp', executable: 'amp'),
    HerdrProviderSpec(id: 'cline', label: 'Cline', executable: 'cline'),
    HerdrProviderSpec(id: 'kimi', label: 'Kimi', executable: 'kimi'),
    HerdrProviderSpec(id: 'droid', label: 'Droid', executable: 'droid'),
    HerdrProviderSpec(id: 'grok', label: 'Grok', executable: 'grok'),
    HerdrProviderSpec(id: 'omp', label: 'omp', executable: 'omp'),
    HerdrProviderSpec(id: 'devin', label: 'Devin', executable: 'devin'),
  ];

  /// Capabilities every Herdr session has; kept next to the provider so a UI
  /// can render the menu without opening a session.
  static const Set<HarnessCapability> capabilities = <HarnessCapability>{
    HarnessCapability.terminal,
    HarnessCapability.prompt,
    HarnessCapability.stop,
  };
}
