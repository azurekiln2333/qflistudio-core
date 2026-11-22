/// AI 编程会话控制器：真实的模型/工具循环。
///
/// 每轮把完整助手消息（含 tool_calls）和工具结果写回对话，工具只能操作
/// 项目内文件或在隔离在线终端执行命令。控制器不编造执行结果。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../interop/interop_runner.dart';
import '../services/ai_file_header.dart';
import '../services/api_client.dart';
import '../trellis/trellis_commands.dart';
import '../trellis/trellis_context.dart';
import 'agent_context_usage.dart';
import 'agent_request_scheduler.dart';
import 'vibe_loop_guard.dart';
import 'vibe_models.dart';
import 'vibe_plan.dart';
import 'vibe_rules.dart';
import 'vibe_skills.dart';
import 'vibe_tools.dart';
import 'vibe_web_tools.dart';

export 'vibe_loop_guard.dart'
    show
        VibeLoopGuard,
        VibeRoundFacts,
        vibeRoundBudget,
        kVibeBaseRounds,
        kVibeMaxRoundBudget;
export 'vibe_plan.dart'
    show
        VibePlanException,
        VibePlanItem,
        VibePlanStatus,
        kVibeMaxPlanItems,
        parseVibePlan,
        vibePlanAllDone;
export 'vibe_skills.dart'
    show
        VibeSkill,
        VibeSkillLibrary,
        VibeSkillSource,
        buildVibeSkillIndex,
        kVibeMaxSkillIndexChars,
        kVibeSkillMaxBodyChars,
        parseVibeSkill,
        vibePromptWantsWeb;
export 'vibe_models.dart';
export 'agent_context_usage.dart' show AgentContextCategory, AgentContextUsage;
export 'vibe_rules.dart'
    show
        hasTrellisWorkflow,
        kVibeTrellisRuleEntry,
        loadVibeRules,
        kVibeMaxRuleFileChars,
        kVibeMaxRulesChars,
        kVibeRuleFiles;
export 'vibe_tools.dart'
    show VibeProjectFiles, VibeSearchMatch, VibeToolException, VibeWriteResult;

/// 技能与计划的可替换来源；测试可注入固定实现。
abstract interface class VibeAgentContext {
  /// 当前可见技能（按名称排序）。
  Future<List<VibeSkill>> skills();

  /// 项目规则文本；没有规则时返回空串。
  Future<String> rules();
}

/// 默认实现：读项目目录、内置资产与仓库规则文件。
class VibeProjectAgentContext
    implements VibeAgentContext, VibeTrellisContextSource {
  VibeProjectAgentContext({
    required this.projectRoot,
    this.language = '',
    this.trellisLoader = const TrellisContextLoader(),
  });

  final String projectRoot;
  final String language;

  /// Trellis 上下文来源；注入会话开头的精简上下文。
  final TrellisContextLoader trellisLoader;

  @override
  Future<List<VibeSkill>> skills() => VibeSkillLibrary(
    projectRoot: projectRoot,
    language: language,
    // 索引只要名称与说明；正文由 use_skill 按需读盘。
    lazyBodies: true,
  ).load();

  @override
  Future<String> rules() async => loadVibeRules(projectRoot);

  @override
  Future<String> trellisContext() => trellisLoader.load(projectRoot);
}

/// 一次写盘审批请求。
///
/// 控制器在真正写盘前把请求交给宿主（会话层、界面）。返回 null 放行，
/// 返回字符串则作为拒绝原因写回工具结果。
class VibeWriteRequest {
  const VibeWriteRequest({
    required this.path,
    required this.summary,
    required this.isCreate,
    required this.bytes,
  });

  /// 相对项目根的路径。
  final String path;

  /// 直接可显示的改动摘要。
  final String summary;

  /// 是否新建文件（目标原本不存在）。
  final bool isCreate;

  /// 写入内容的字节数。
  final int bytes;
}

/// 编辑器集成使用的会话对象；UI 只读 [phase]、[messages] 等状态。
class VibeCodingController extends ChangeNotifier {
  VibeCodingController({
    required ApiClient api,
    required String? Function() tokenProvider,
    required String projectRoot,
    required String projectName,
    required String language,
    bool Function()? onlineAllowed,
    void Function(String relativePath)? onFileChanged,
    void Function(String? relativePath)? onFileRemoved,
    void Function(String message)? onNotice,
    VibeProjectFiles? files,
    int? maxRounds,
    VibeAgentContext? context,
    AiEndpoint Function()? endpointProvider,
    InteropRunner? interopRunner,
    Future<String?> Function(VibeWriteRequest request)? writeApproval,
    List<Map<String, dynamic>>? restoredHistory,
    String? modelId,
    String? reasoningEffort,
  }) : _api = api,
       _tokenProvider = tokenProvider,
       _projectName = projectName,
       _language = language,
       _onlineAllowed = onlineAllowed,
       _onFileChanged = onFileChanged,
       _onFileRemoved = onFileRemoved,
       _onNotice = onNotice,
       _files = files ?? VibeProjectFiles(projectRoot: projectRoot),
       _maxRounds = maxRounds,
       _context = context,
       _endpointProvider = endpointProvider,
       _interop = interopRunner,
       _modelId = modelId,
       _reasoningEffort = reasoningEffort {
    writeApprovalHook = writeApproval;
    _history.add({'role': 'system', 'content': _systemPrompt()});
    if (restoredHistory != null && restoredHistory.isNotEmpty) {
      _history.addAll(_sanitizeHistory(restoredHistory));
    }
  }

  final ApiClient _api;
  final String? Function() _tokenProvider;
  final String _projectName;
  final String _language;
  final bool Function()? _onlineAllowed;
  final void Function(String relativePath)? _onFileChanged;
  final void Function(String? relativePath)? _onFileRemoved;
  final void Function(String message)? _onNotice;
  final VibeProjectFiles _files;
  final int? _maxRounds;
  final VibeAgentContext? _context;

  /// 每轮读取一次：用户在设置里改协议或地址后立即生效，无需重建会话。
  final AiEndpoint Function()? _endpointProvider;

  /// 跨应用运行器；为 null 时只走在线终端。
  final InteropRunner? _interop;

  /// 写盘前审批；为 null 时不经审批直接写（现有编辑器集成保持原行为）。
  ///
  /// 会话层可在构造后替换，每次写盘都读当前值。
  Future<String?> Function(VibeWriteRequest request)? writeApprovalHook;

  /// 本轮指定的模型与推理强度；为 null 时沿用设置或服务端默认。
  String? _modelId;
  String? _reasoningEffort;

  late final VibeAgentContext _agent =
      _context ??
      VibeProjectAgentContext(
        projectRoot: _files.projectRoot,
        language: _language,
      );

  final List<Map<String, dynamic>> _history = [];
  AgentContextUsage? _cachedContextUsage;
  int? _lastReportedInputTokens;
  Map<AgentContextCategory, String> _contextSystemSections = const {};
  final List<VibeMessage> _messages = [];
  List<VibePlanItem> _plan = const [];
  List<VibeSkill> _skills = const [];
  String _rules = '';

  /// 本次会话的 Trellis 上下文；只读一次。
  String _trellis = '';
  bool _trellisLoaded = false;

  final List<String> _usedSkills = [];

  VibePhase _phase = VibePhase.idle;
  String? _lastError;
  Future<void>? _activeRun;
  Completer<void>? _abort;
  StreamSubscription<TerminalEvent>? _terminalSubscription;
  Completer<_ToolOutcome>? _commandCompletion;
  bool _cancelRequested = false;
  bool _disposed = false;
  bool _usedTerminal = false;

  /// 本轮终端不可用（未登录或会话过期）。
  bool _terminalUnavailable = false;

  /// 本次 send 已用过的搜索查询与网址，用于去重。
  final Set<String> _seenQueries = {};
  final Set<String> _seenUrls = {};

  /// 本次 send 成功的抓取次数，用于提醒模型开始总结。
  int _searchCount = 0;

  /// 本次 send 内是否有成功的写入，且内置 HTML 检查未报错。
  ///
  /// 跨轮累积：常见节奏是先写文件、下一轮才跑验证，重置会让判据失效。
  bool _wroteCleanThisSend = false;

  bool _roundHadFailures = false;

  /// 最近一次模型请求的原始异常；会话层据此分类错误文案。
  ApiException? _lastApiError;

  /// 正在流式输出的消息：下标 → 实时文本。
  ///
  /// 界面只监听这一个 notifier，对话列表不重建（design §6.1）。
  final Map<int, ValueNotifier<String>> _liveText = {};

  /// 增量先写这里，下一帧合并进 notifier。
  final Map<int, String> _liveBuffer = {};

  /// 已经结束的流式消息，等控制器销毁时统一释放。
  final List<ValueNotifier<String>> _retiredLive = [];

  bool _liveFlushScheduled = false;

  /// 正在流式输出的消息的实时文本。
  /// 不在流式中时返回 null。
  ValueListenable<String>? liveText(int index) => _liveText[index];

  /// 模型请求的并发门闸；为 null 时不限并发（现有行为）。
  AgentRequestScheduler? requestScheduler;

  /// 门闸里这个会话的键，通常就是会话 id。
  String? schedulerKey;

  VibePhase get phase => _phase;
  List<VibeMessage> get messages => List.unmodifiable(_messages);

  /// 当前计划；模型通过 todo 工具整体替换。
  List<VibePlanItem> get plan => _plan;

  /// 本次会话可用的技能（按名称排序）。
  List<VibeSkill> get skills => _skills;

  /// 本次会话已调用 use_skill 的技能名，按首次调用顺序去重。
  List<String> get usedSkills => List.unmodifiable(_usedSkills);

  int get maxRounds => _maxRounds ?? kVibeMaxRoundBudget;
  String? get lastError => _lastError;

  /// 最近一次模型请求的原始异常；不是接口错误时为 null。
  ApiException? get lastApiError => _lastApiError;

  /// 一句话说明正在做什么，例如「正在读取 lib/main.dart」。
  ///
  /// 只在有工具正在执行时非空；空闲、等待确认、已完成都返回 null。
  String? get activity {
    for (var index = _messages.length - 1; index >= 0; index--) {
      final message = _messages[index];
      final tool = message.tool;
      if (tool == null) continue;
      if (!message.pending) return null;
      return _activityLabel(tool);
    }
    return null;
  }

  static String _activityLabel(VibeToolCall tool) {
    final target = tool.summary.trim();
    return switch (tool.toolName) {
      'read_file' => target.isEmpty ? '正在读取文件' : '正在读取 $target',
      'write_file' => target.isEmpty ? '正在写入文件' : '正在写入 $target',
      'edit_file' => target.isEmpty ? '正在编辑文件' : '正在编辑 $target',
      'list_files' => target.isEmpty ? '正在查看目录' : '正在查看目录 $target',
      'search_text' => target.isEmpty ? '正在搜索' : '正在搜索 $target',
      'run_command' => '正在运行命令',
      'todo' => '正在更新计划',
      'use_skill' => '正在加载技能',
      'web_search' => '正在联网搜索',
      'web_fetch' => '正在读取网页',
      _ => '正在执行 ${tool.toolName}',
    };
  }

  /// 已发生的模型对话历史（含 system）：会话层用它做持久化。
  ///
  /// 未完成的 tool_calls 与对应 tool 回复以配对形式存在；一次 send 结束后
  /// 才适合保存。内容可能含项目文件片段，不得写入日志。
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  /// Cached request-context accounting. Streaming text does not rescan history.
  AgentContextUsage get contextUsage =>
      _cachedContextUsage ??= estimateAgentContextUsage(
        history: _history,
        tools: _toolSpecs(),
        systemSections: {
          AgentContextCategory.systemPrompt: _systemPrompt(),
          ..._contextSystemSections,
        },
        lastReportedInputTokens: _lastReportedInputTokens,
      );

  void _invalidateContextUsage() => _cachedContextUsage = null;

  /// 指定后续 send 使用的模型与推理强度；null 则回到默认。
  ///
  /// 推理强度只对支持的模型生效，服务端未放行时会被拒绝。
  void configureModel({String? modelId, String? reasoningEffort}) {
    _modelId = modelId;
    _reasoningEffort = reasoningEffort;
  }

  /// 登记本会话可读的项目外附件（只读，不能写、编辑、搜索）。
  void allowReadOnlyFiles(Iterable<String> paths) =>
      _files.allowReadOnlyFiles(paths);

  /// 恢复已有会话的模型历史（会话层在构造后调用）。
  ///
  /// 只收 `user` / `assistant` / 配对的 `tool`；其余条目丢弃。
  void restoreHistory(Iterable<Map<String, Object?>> entries) {
    final restored = _sanitizeHistory([
      for (final entry in entries) Map<String, dynamic>.from(entry),
    ]);
    if (restored.isEmpty) return;
    _history.addAll(restored);
    _invalidateContextUsage();
  }

  bool get canSend =>
      _phase != VibePhase.running && _phase != VibePhase.cancelling;
  bool get canCancel => _phase == VibePhase.running;
  String get projectRoot => _files.projectRoot;
  VibeProjectFiles get files => _files;

  /// 供编辑器在自身删除文件后同步会话视图。
  void notifyFileRemoved(String? relativePath) =>
      _onFileRemoved?.call(relativePath);

  /// 发送一条用户请求；结果进入 [messages] 与 [phase]。
  void send(String text) {
    if (_disposed) return;
    final prompt = text.trim();
    if (prompt.isEmpty) return;
    if (!canSend) {
      _notice('上一条任务仍在执行');
      return;
    }
    if (_onlineAllowed?.call() == false) {
      _fail('当前产品为离线模式，AI 编程需要联网');
      return;
    }
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      _fail('请先登录后使用 AI 编程');
      return;
    }
    _cancelRequested = false;
    _lastError = null;
    _lastApiError = null;
    _terminalUnavailable = false;
    _wroteCleanThisSend = false;
    _seenQueries.clear();
    _seenUrls.clear();
    _searchCount = 0;
    _phase = VibePhase.running;
    _messages.add(VibeMessage(isUser: true, text: prompt));
    _history.add({'role': 'user', 'content': prompt});
    _invalidateContextUsage();
    _trimHistory();
    _notify();
    _activeRun = _run(prompt);
  }

  /// 取消在途模型请求和终端执行；返回时本轮已停止并完成终端清理。
  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    _phase = VibePhase.cancelling;
    _notify();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    final subscription = _terminalSubscription;
    _terminalSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final completion = _commandCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(_cancelledOutcome());
    }
    await _activeRun;
    // 保持 cancelling 直到会话回收确认，避免迟到的 DELETE 杀掉下一任务。
    if (_usedTerminal) {
      _usedTerminal = false;
      await _resetTerminal();
    }
    if (!_disposed) _finish(VibePhase.cancelled);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    final subscription = _terminalSubscription;
    _terminalSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final completion = _commandCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(_cancelledOutcome());
    }
    _dropLiveNotifiers();
    super.dispose();
  }

  /// 释放流式消息的实时文本 notifier。
  ///
  /// 还挂着监听器的交给 GC：界面还没来得及摘监听器时，释放会报错。
  void _dropLiveNotifiers() {
    _liveBuffer.clear();
    _liveFlushScheduled = false;
    final notifiers = [..._liveText.values, ..._retiredLive];
    _liveText.clear();
    _retiredLive.clear();
    for (final notifier in notifiers) {
      if (!notifier.hasListeners) notifier.dispose();
    }
  }

  // ---- 循环 ----

  /// 一次 send 的主体：准备技能、规则与 Trellis 上下文，然后进入模型/工具循环。
  Future<void> _run(String prompt) async {
    _abort = Completer<void>();
    _usedTerminal = false;
    _usedSkills.clear();
    final guard = VibeLoopGuard();
    _finalizeOpenPlan(failed: true);
    final budget = _maxRounds ?? vibeRoundBudget(prompt);
    // 技能与规则读不到时退化为空，不阻断会话。
    _skills = await _readSkills();
    _rules = await _readRules();
    await _loadTrellis();
    final routed = await _routeSlashCommand(prompt);
    if (_cancelRequested || _disposed) return;
    guard.markSnapshot(await _projectSnapshot());
    _prepareContext(routed ?? prompt);
    try {
      for (var round = 0; round < budget; round++) {
        if (_cancelRequested || _disposed) {
          return;
        }
        final activeToken = _tokenProvider();
        if (activeToken == null || activeToken.isEmpty) {
          _fail('登录已过期，请重新登录');
          return;
        }
        final turn = _StreamTurn();
        final AiChatResult reply;
        try {
          Future<AiChatResult> request() {
            turn.reset();
            return _consumeTurn(turn, token: activeToken);
          }

          final scheduler = requestScheduler;
          reply = scheduler == null
              ? await request()
              : await scheduler.run(
                  schedulerKey ?? 'session',
                  request,
                  isCancelled: () => _cancelRequested || _disposed,
                  // 已经发出增量的回合不重试：否则界面会重复一段。
                  canRetry: () => !turn.emitted,
                );
        } on ApiException catch (error) {
          if (_cancelRequested || _disposed) {
            return;
          } else {
            _fail(error.message, apiError: error);
          }
          return;
        }
        if (_cancelRequested || _disposed) {
          return;
        }

        _calibrateReasoning(turn, reply);
        final calls = reply.toolCalls;
        final parsed = <_ParsedCall>[];
        for (final call in calls) {
          final id = call['id'];
          final function = call['function'];
          if (id is! String ||
              id.isEmpty ||
              function is! Map ||
              function['name'] is! String ||
              function['arguments'] is! String) {
            // 未写入历史，下一轮协议仍然有效。
            _fail('AI 返回了无效的工具调用');
            return;
          }
          parsed.add(
            _ParsedCall(
              id: id,
              name: function['name'] as String,
              arguments: function['arguments'] as String,
            ),
          );
        }

        final assistant = <String, dynamic>{
          'role': 'assistant',
          'content': reply.content.isEmpty && parsed.isNotEmpty
              ? null
              : reply.content,
        };
        if (calls.isNotEmpty) {
          assistant['tool_calls'] = calls;
        }
        _carryReasoning(assistant, reply);
        _history.add(assistant);
        _invalidateContextUsage();
        _calibrateContent(turn, reply);
        if (parsed.isEmpty) {
          _trimHistory();
          _finish(VibePhase.succeeded);
          return;
        }

        final answered = <String>{};
        final facts = VibeRoundFacts();
        _roundHadFailures = false;
        _terminalUnavailable = false;
        for (final call in parsed) {
          if (_cancelRequested || _disposed) {
            _finalizeCancelled(parsed, answered, null, null);
            return;
          }
          final index = _appendMessage(
            VibeMessage(
              isUser: false,
              text: '',
              pending: true,
              tool: VibeToolCall(
                id: call.id,
                toolName: call.name,
                summary: _summarize(call.name, call.arguments),
              ),
            ),
          );
          _ToolOutcome outcome;
          final repeated = guard.rejectRepeat(call.name, call.arguments);
          if (repeated != null) {
            outcome = _error('repeated', repeated);
          } else {
            guard.recordCall(call.name, call.arguments);
            try {
              outcome = await _execute(call.name, call.arguments, index, guard);
            } on Object catch (error) {
              outcome = _error('error', '工具执行异常：$error');
            }
          }
          if (_cancelRequested || _disposed) {
            _finalizeCancelled(parsed, answered, index, outcome);
            return;
          }
          _tallyFacts(facts, outcome);
          _finalizeTool(index, outcome);
          answered.add(call.id);
          _history.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': _bounded(outcome.modelText, kVibeMaxToolResultChars),
          });
          _invalidateContextUsage();
        }
        _trimHistory();
        // 终端不可用时模型容易反复重试。已经写好文件、结构检查也通过时，
        // 把它当完成：缺的只是一次无处可跑的命令。
        if (_terminalUnavailable) {
          if (_wroteCleanThisSend) {
            _appendMessage(
              VibeMessage(isUser: false, text: '已写入文件，命令验证因终端不可用未执行。'),
            );
            _finalizeOpenPlan(failed: false);
            _finish(VibePhase.succeeded);
            return;
          }
          _finalizeOpenPlan(failed: true);
          _fail('终端不可用（未登录或登录已过期），无法运行命令验证');
          return;
        }
        final stalled = guard.endRound(
          facts,
          wroteEarlier: _wroteCleanThisSend,
        );
        if (stalled != null) {
          // 文件已经写好了，后面几轮只是回顾与核对。此时停下没意义，
          // 直接让模型收尾，并把整次 send 判成功。
          if (_wroteCleanThisSend) {
            _appendMessage(
              VibeMessage(isUser: false, text: '文件已写入，本次任务已收尾。请直接用中文总结完成的工作。'),
            );
            _finalizeOpenPlan(failed: false);
            _finish(VibePhase.succeeded);
            return;
          }
          _finalizeOpenPlan(failed: true);
          _fail(stalled);
          return;
        }
      }
      _finalizeOpenPlan(failed: true);
      _fail('已达到 $budget 轮工具调用上限，任务未完成');
    } on Object catch (error) {
      if (_cancelRequested || _disposed) {
        // cancel()/dispose 负责收尾。
      } else {
        _fail('任务执行失败：$error');
      }
    } finally {
      _closeLiveMessages();
      _abort = null;
      _terminalSubscription = null;
      _commandCompletion = null;
      if (_phase == VibePhase.running || _phase == VibePhase.cancelling) {
        if (_disposed) {
          _phase = VibePhase.cancelled;
        } else if (!_cancelRequested) {
          _finish(VibePhase.failed);
        }
        // 取消时保持 cancelling，等 cancel() 完成终端回收后再开放 send。
      }
    }
  }

  /// 汇总一轮工具结果，供进展守卫判定。
  void _tallyFacts(VibeRoundFacts facts, _ToolOutcome outcome) {
    if (outcome.writtenPath != null) {
      facts.writes++;
    } else if (outcome.readPath != null) {
      facts.reads++;
    }
    // 列目录与更新计划只在开工阶段算进展，由守卫按轮次判定。
    facts.listings += outcome.listedDirs;
    facts.newSources += outcome.newSources;
    if (outcome.plan != null) facts.planUpdates++;
    if (outcome.ranCommand) facts.exitCodes.add(outcome.exitCode);
    if (outcome.status == VibeToolStatus.error ||
        outcome.status == VibeToolStatus.conflict) {
      facts.errors.add('${outcome.code}: ${outcome.summary}');
      _roundHadFailures = true;
    }
  }

  /// 读技能列表；读取失败时退化为空列表，不打断本轮。
  Future<List<VibeSkill>> _readSkills() async {
    try {
      return await _agent.skills();
    } on Object {
      return const [];
    }
  }

  /// 读项目规则；读取失败时退化为空串，不打断本轮。
  Future<String> _readRules() async {
    try {
      return await _agent.rules();
    } on Object {
      return '';
    }
  }

  /// Trellis 上下文来源；代理上下文没实现时返回 null。
  VibeTrellisContextSource? get _trellisSource =>
      _agent is VibeTrellisContextSource
      ? _agent as VibeTrellisContextSource
      : null;

  /// 载入本次会话的 Trellis 上下文；一个会话只读一次。
  Future<void> _loadTrellis() async {
    if (_trellisLoaded) return;
    _trellisLoaded = true;
    final source = _trellisSource;
    if (source == null) return;
    try {
      _trellis = await source.trellisContext();
    } on Object {
      // 上下文读不到就不注入，不影响会话。
      _trellis = '';
    }
    if (_trellis.isNotEmpty) _invalidateContextUsage();
  }

  /// 把 `/trellis:continue` 这类命令换成真正的指令；不是命令时返回 null。
  ///
  /// 界面仍显示用户输入的那一行，模型收到的历史换成展开后的指令。
  Future<String?> _routeSlashCommand(String prompt) async {
    if (_trellisSource == null) return null;
    if (matchTrellisSlashCommand(prompt) == null) return null;
    String? routed;
    try {
      routed = await routeTrellisSlashCommand(
        prompt,
        projectRoot: _files.projectRoot,
        skills: _skills,
      );
    } on Object {
      routed = null;
    }
    if (routed == null || routed.isEmpty) return null;
    for (var index = _history.length - 1; index >= 0; index--) {
      final entry = _history[index];
      if (entry['role'] != 'user') continue;
      _history[index] = {...entry, 'content': routed};
      break;
    }
    _invalidateContextUsage();
    return routed;
  }

  /// 本轮工具列表。离线专属产品不暴露联网工具。
  ///
  /// `web_search` 已下线（整改任务书 §3-W3）：联网搜索的唯一上游是未披露的
  /// 第三方，而§1 允许的第三方只有华为、深度求索和云厂商。`web_fetch` 保留。
  List<Map<String, dynamic>> _toolSpecs() =>
      vibeWebToolsAvailable ? vibeToolSpecsWithWeb() : vibeToolSpecs();

  /// 载入本次 send 的技能、规则与 Trellis 上下文，并写入系统提示后可变的上下文块。
  void _prepareContext(String prompt) {
    final skills = _skills;
    final rules = _rules;
    final trellis = _trellis;
    if (skills.isEmpty && rules.isEmpty && trellis.isEmpty) return;
    final sections = <AgentContextCategory, String>{
      AgentContextCategory.systemPrompt: _systemPrompt(),
    };
    if (rules.isNotEmpty || trellis.isNotEmpty) {
      final buffer = StringBuffer();
      if (rules.isNotEmpty) {
        buffer.write('\n\n项目规则（来自仓库，必须遵守）：\n$rules');
      }
      if (trellis.isNotEmpty) buffer.write('\n\n$trellis');
      sections[AgentContextCategory.projectRules] = buffer.toString();
    }
    if (skills.isNotEmpty) {
      final buffer = StringBuffer(
        '\n\n可用技能（只列出名称与说明）：\n'
        '${buildVibeSkillIndex(skills)}',
      );
      if (vibePromptWantsWeb(prompt) &&
          skills.any((skill) => skill.name == 'web-app-scaffold')) {
        buffer.write('\n本次需求是网页类任务，建议先 use_skill web-app-scaffold。');
      }
      buffer.write('\n需要完整步骤时调用 use_skill；不要凭空重复技能内容。');
      sections[AgentContextCategory.skills] = buffer.toString();
    }
    _contextSystemSections = sections;
    _history[0] = {'role': 'system', 'content': sections.values.join()};
    _invalidateContextUsage();
    _plan = const [];
    _notify();
  }

  /// 项目快照（相对路径 → 字节数），用于先读后改判定。
  ///
  /// 与 run_command 用同一套排除规则，符号链接与构建目录不参与。
  Future<Map<String, int>> _projectSnapshot() async {
    final snapshot = <String, int>{};
    final root = Directory(_files.projectRoot);
    if (!root.existsSync()) return snapshot;
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = _files.relative(entity.path);
        final segments = relative.split('/');
        if (segments.first.startsWith('.') ||
            segments.any(VibeProjectSnapshot.excludedDirs.contains)) {
          continue;
        }
        snapshot[relative] = await entity.length();
      }
    } on FileSystemException {
      // 读不完整的路径直接跳过，不阻塞本轮任务。
    }
    return snapshot;
  }

  /// 结束时把未完成的计划项标为未完成，避免面板显示虚假进度。
  void _finalizeOpenPlan({required bool failed}) {
    if (!failed || _plan.isEmpty) return;
    if (vibePlanAllDone(_plan)) return;
    _plan = List.unmodifiable(
      _plan.map(
        (item) => item.status == VibePlanStatus.doing
            ? VibePlanItem(
                id: item.id,
                title: item.title,
                status: VibePlanStatus.pending,
              )
            : item,
      ),
    );
    _notify();
  }

  void _finalizeTool(int index, _ToolOutcome outcome) {
    if (index < 0 || index >= _messages.length) return;
    final current = _messages[index].tool;
    if (current == null) return;
    _replaceMessage(
      index,
      VibeMessage(
        isUser: false,
        text: '',
        pending: false,
        tool: current.copyWith(
          status: outcome.status,
          result: outcome.summary,
          commandOutput: outcome.output,
          exitCode: outcome.exitCode,
          plan: outcome.plan,
          changedPaths: outcome.writtenPath == null
              ? const []
              : [outcome.writtenPath!],
        ),
      ),
    );
  }

  /// 取消时补齐未完成的工具回复，避免历史里出现孤立 tool_calls。
  void _finalizeCancelled(
    List<_ParsedCall> calls,
    Set<String> answered,
    int? index,
    _ToolOutcome? outcome,
  ) {
    if (index != null) {
      final tool = _messages[index].tool;
      if (tool != null) {
        _replaceMessage(
          index,
          VibeMessage(
            isUser: false,
            text: '',
            pending: false,
            tool: tool.copyWith(
              status: VibeToolStatus.error,
              result: '已取消',
              commandOutput: outcome?.output,
            ),
          ),
        );
      }
    }
    for (final call in calls) {
      if (answered.contains(call.id)) continue;
      _history.add({
        'role': 'tool',
        'tool_call_id': call.id,
        'content': 'error(cancelled): 用户取消了执行',
      });
      _invalidateContextUsage();
    }
  }

  // ---- 工具执行 ----

  Future<_ToolOutcome> _execute(
    String name,
    String arguments,
    int index,
    VibeLoopGuard guard,
  ) async {
    Object? decoded;
    try {
      decoded = jsonDecode(arguments);
    } on FormatException {
      return _error('error', '工具参数不是有效 JSON');
    }
    if (decoded is! Map) return _error('error', '工具参数必须是对象');
    final args = Map<String, dynamic>.from(decoded);

    try {
      switch (name) {
        case 'list_files':
          final path = args['path'];
          if (path != null && path is! String) {
            return _error('error', 'path 必须是字符串');
          }
          final entries = await _files.list(
            path: path as String?,
            recursive: args['recursive'] == true,
          );
          final text = entries.isEmpty
              ? '目录为空'
              : entries
                    .map(
                      (entry) =>
                          '${entry['type'] == 'directory' ? 'd' : 'f'} '
                          '${entry['path']}'
                          '${entry['bytes'] == null ? '' : ' (${entry['bytes']} B)'}',
                    )
                    .join('\n');
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary: '${entries.length} 个条目',
            modelText: text,
            listedDirs: 1,
          );
        case 'read_file':
          final path = _requiredString(args, 'path');
          final content = await _files.read(path);
          // 项目内用相对路径，项目外附件用绝对路径；两者都不会命中写入。
          final display = _files.displayPathForRead(path);
          guard.markRead(display);
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary: '$display · ${utf8.encode(content).length} B',
            modelText: content.isEmpty ? '文件为空' : content,
            readPath: path,
          );
        case 'write_file':
          final path = _requiredString(args, 'path');
          final content = args['content'];
          if (content is! String) return _error('error', 'content 必须是字符串');
          final denied = await _approveWrite(
            path: path,
            summary:
                '${_isExisting(path) ? '覆盖' : '新建'} $path'
                '（${utf8.encode(content).length} B）',
            bytes: utf8.encode(content).length,
          );
          if (denied != null) {
            return _error('permission', denied, conflict: true);
          }
          final unread =
              guard.existedAtStart(_files.relative(_files.resolve(path)))
              ? guard.rejectUnreadWrite(_files.relative(_files.resolve(path)))
              : null;
          if (unread != null) return _error('unread', unread);
          // AI 写入的文件必须在开头留一行“本文件由 AI 生成”（§3-W3）。
          // 标识按目标语言的注释语法插入；没有注释语法的类型原样写入。
          final marked = addAiGeneratedHeader(path, content);
          final result = await _files.write(
            path,
            marked.content,
            createOnly: args['createOnly'] == true,
          );
          final sidecar = await _writeAiMark(result.relativePath, marked);
          guard.markWritten(result.relativePath);
          _onFileChanged?.call(result.relativePath);
          final verify = await _verificationHint(result.relativePath);
          // 内置检查报错时不能算干净写入，否则会把错页面当完成。
          _wroteCleanThisSend =
              _wroteCleanThisSend || (verify == null || verify.contains('已通过'));
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary:
                '${result.created ? '已创建' : '已写入'} '
                '${result.relativePath} · ${result.bytes} B$sidecar',
            modelText:
                '${result.created ? '已创建' : '已写入'} ${result.relativePath}'
                '（${result.bytes} B）'
                '${marked.inBody ? '，已加上 AI 生成标识' : ''}'
                '${result.backupPath == null ? '' : '，原文件已备份'}'
                '${verify == null ? '' : '\n$verify'}$sidecar',
            writtenPath: result.relativePath,
          );
        case 'edit_file':
          final path = _requiredString(args, 'path');
          final oldText = args['oldText'];
          final newText = args['newText'];
          if (oldText is! String || newText is! String) {
            return _error('error', 'oldText 与 newText 必须是字符串');
          }
          final denied = await _approveWrite(
            path: path,
            summary:
                '替换 $path 中的 ${utf8.encode(oldText).length} B '
                '为 ${utf8.encode(newText).length} B',
            bytes: utf8.encode(newText).length,
          );
          if (denied != null) {
            return _error('permission', denied, conflict: true);
          }
          final unread =
              guard.existedAtStart(_files.relative(_files.resolve(path)))
              ? guard.rejectUnreadWrite(_files.relative(_files.resolve(path)))
              : null;
          if (unread != null) return _error('unread', unread);
          final result = await _files.edit(
            path,
            oldText,
            newText,
            replaceAll: args['replaceAll'] == true,
          );
          guard.markWritten(result.relativePath);
          _onFileChanged?.call(result.relativePath);
          // edit_file 同样要留标识：改过的文件也是 AI 写的（§3-W3）。
          final editMark = addAiGeneratedHeader(
            result.relativePath,
            await _files.read(result.relativePath),
          );
          if (editMark.content != await _files.read(result.relativePath)) {
            await _files.write(result.relativePath, editMark.content);
            _onFileChanged?.call(result.relativePath);
          }
          final editSidecar = await _writeAiMark(result.relativePath, editMark);
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary:
                '已替换 ${result.relativePath} · ${result.bytes} B$editSidecar',
            modelText:
                '已替换 ${result.relativePath}（${result.bytes} B），原文件已备份'
                '$editSidecar',
            writtenPath: result.relativePath,
          );
        case 'search_text':
          return await _searchText(args);
        case 'run_command':
          return await _runCommand(args, index);
        case 'todo':
          return _updatePlan(args);
        case 'use_skill':
          return await _useSkill(args);
        case 'web_fetch':
          return await _runWebTool(name, args);
        default:
          return _error('error', '未知工具：$name');
      }
    } on VibeToolException catch (error) {
      return _error(
        error.isConflict ? 'conflict' : error.code,
        error.message,
        conflict: error.isConflict,
      );
    } on VibePlanException catch (error) {
      return _error('plan', error.message);
    } on FileSystemException catch (error) {
      return _error('error', '文件操作失败：${error.message}');
    }
  }

  /// 写盘前审批：返回 null 放行，返回字符串则为拒绝原因。
  ///
  /// 取消与 dispose 会同时结束等待，避免宿主忘了回复时整轮卡死。
  Future<String?> _approveWrite({
    required String path,
    required String summary,
    required int bytes,
  }) async {
    final hook = writeApprovalHook;
    if (hook == null) return null;
    final request = VibeWriteRequest(
      path: path,
      summary: summary,
      isCreate: !_isExisting(path),
      bytes: bytes,
    );
    final abort = _abort;
    if (abort == null) return hook(request);
    final decision = hook(request);
    final winner = await Future.any<Object?>([
      decision,
      abort.future.then<Object?>((_) => const _WriteCancelled()),
    ]);
    if (winner is _WriteCancelled) return '已取消写入';
    return winner as String?;
  }

  /// 目标是否已存在；路径不合法时当作不存在，后续会绕回路径校验。
  bool _isExisting(String path) {
    try {
      return File(_files.resolve(path)).existsSync();
    } on VibeToolException {
      return false;
    }
  }

  /// `search_text`：在项目内按行搜索，返回 路径:行号: 内容。
  Future<_ToolOutcome> _searchText(Map<String, dynamic> args) async {
    final pattern = _requiredString(args, 'pattern');
    final rawLimit = args['maxResults'];
    if (rawLimit != null && rawLimit is! int) {
      return _error('error', 'maxResults 必须是整数');
    }
    final rawPath = args['path'];
    if (rawPath != null && rawPath is! String) {
      return _error('error', 'path 必须是字符串');
    }
    final matches = await _files.searchText(
      pattern,
      path: rawPath as String?,
      maxResults: rawLimit as int? ?? VibeProjectFiles.defaultMaxSearchResults,
      regex: args['regex'] == true,
      caseSensitive: args['caseSensitive'] == true,
    );
    if (matches.isEmpty) {
      return const _ToolOutcome(
        status: VibeToolStatus.ok,
        summary: '没有匹配',
        modelText: '没有匹配的行',
      );
    }
    final text = matches
        .map((match) => '${match.path}:${match.line}: ${match.text}')
        .join('\n');
    return _ToolOutcome(
      status: VibeToolStatus.ok,
      summary: '${matches.length} 处匹配',
      modelText: text,
      // 搜到东西算一次进展，否则守卫会把纯检索的一轮当成停滞。
      listedDirs: 1,
    );
  }

  /// 写入结果的补充说明：标识是否落到说明文件。
  ///
  /// 带注释语法的类型标识已在正文，返回空串。
  /// 说明文件写失败时返回提示，不推翻已成功的正文写入。
  Future<String> _writeAiMark(
    String path,
    AiGeneratedHeaderResult marked,
  ) async {
    final sidecar = marked.sidecarContent;
    if (sidecar == null) return '';
    final written = await _files.writeAiMarkSidecar(
      path: aiGeneratedSidecarPath(path),
      content: sidecar,
    );
    if (written == null) {
      return '，但 AI 标识说明文件写入失败';
    }
    return '，已在 $written 标注 AI 生成';
  }

  /// 写入成功后的自检提示：网页类项目就地做真实结构检查。
  ///
  /// 不再让模型发一段 heredoc 脚本：那会撞上 run_command 的长度上限，
  /// 把已经正确的页面判成失败。检查在本地完成，结果直接写进工具结果。
  Future<String?> _verificationHint(String relativePath) async {
    if (!relativePath.toLowerCase().endsWith('.html')) return null;
    final report = await _checkHtml(relativePath);
    return report;
  }

  /// 内置 HTML 结构检查：标签闭合、引用的本地文件是否存在。
  ///
  /// 只读当前项目，不调用命令行，也不依赖外部工具。
  Future<String> _checkHtml(String relativePath) async {
    final tagPattern = RegExp(
      r'<(/?)([a-zA-Z][a-zA-Z0-9-]*)([^>]*?)(/?)>',
      dotAll: true,
    );
    const voidTags = {
      'meta',
      'link',
      'br',
      'img',
      'input',
      'hr',
      'source',
      'area',
      'base',
      'col',
      'embed',
      'param',
      'track',
      'wbr',
    };
    final source = await _files.read(relativePath);
    final stack = <String>[];
    final problems = <String>[];
    final refs = <String>[];
    var openTags = 0;
    for (final match in tagPattern.allMatches(source)) {
      final closing = match.group(1) == '/';
      final tag = match.group(2)!.toLowerCase();
      if (closing) {
        if (stack.isNotEmpty && stack.last == tag) {
          stack.removeLast();
        } else if (stack.contains(tag)) {
          problems.add('</$tag> 之前有未闭合标签');
          while (stack.isNotEmpty && stack.removeLast() != tag) {}
        } else {
          problems.add('多余的 </$tag>');
        }
        continue;
      }
      openTags++;
      if (!voidTags.contains(tag) && match.group(4) != '/') stack.add(tag);
      final attrs = match.group(3) ?? '';
      if (tag == 'link' || tag == 'script' || tag == 'img') {
        final attr = tag == 'link' ? 'href' : 'src';
        final value = RegExp(
          '$attr\\s*=\\s*["\']([^"\']+)["\']',
        ).firstMatch(attrs)?.group(1);
        if (value != null) refs.add(value.trim());
      }
    }
    final buffer = StringBuffer('本地结构检查（$relativePath）：');
    if (problems.isEmpty && stack.isEmpty) {
      buffer.write('标签闭合正常，$openTags 个开始标签');
    } else {
      buffer.write('标签有问题');
      if (problems.isNotEmpty) buffer.write('，${problems.join('；')}');
      if (stack.isNotEmpty) buffer.write('，未闭合：${stack.join(', ')}');
    }
    final missing = <String>[];
    final checked = <String>{};
    for (final ref in refs) {
      final lower = ref.toLowerCase();
      if (lower.startsWith('http://') ||
          lower.startsWith('https://') ||
          lower.startsWith('data:') ||
          lower.startsWith('//') ||
          lower.startsWith('#')) {
        continue;
      }
      if (!checked.add(ref)) continue;
      try {
        final absolute = _files.resolve(ref.split('?').first.split('#').first);
        if (!File(absolute).existsSync()) missing.add(ref);
      } on VibeToolException {
        missing.add(ref);
      }
    }
    if (refs.isNotEmpty) {
      buffer.write(
        missing.isEmpty
            ? '；引用的 ${checked.length} 个本地文件都存在'
            : '；缺少文件：${missing.join(', ')}',
      );
    }
    if (problems.isNotEmpty || stack.isNotEmpty || missing.isNotEmpty) {
      buffer.write('。先修好这些再用 run_command 验证。');
    } else {
      buffer.write('。结构自检已通过，无需再发检查脚本。');
    }
    return buffer.toString();
  }

  /// `web_fetch`：经服务端中转真实抓取，结果原样交给模型。
  Future<_ToolOutcome> _runWebTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    if (!vibeWebToolsAvailable) {
      return _error('OFFLINE_ONLY', '当前产品为离线模式，不能访问网络');
    }
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      return _error('auth', '需要登录后才能使用联网工具');
    }
    final result = await executeVibeWebTool(
      name: name,
      arguments: args,
      api: _api,
      token: token,
      onlineAllowed: _onlineAllowed,
    );
    if (result == null) return _error('error', '未知联网工具：$name');
    var fresh = 0;
    if (result.ok) {
      // 只有带回新网址才算进展，重复抓取不推任务向前。
      final query = '${args['url'] ?? ''}'.trim().toLowerCase();
      final dedupeKey = '$name|$query';
      final newQuery = query.isNotEmpty && _seenQueries.add(dedupeKey);
      final urls = RegExp(
        "[hH][tT][tT][pP][sS]?://[^\\s<>\"']+",
      ).allMatches(result.modelText).map((m) => m.group(0)!).toList();
      final newUrls = urls.where(_seenUrls.add).length;
      if (newQuery || newUrls > 0) fresh = 1;
      if (result.ok) _searchCount++;
    }
    var text = result.modelText;
    if (result.ok && _searchCount >= 3) {
      text = '$text\n\n信息已足够，请直接用中文总结并列出所用来源网址，不要继续抓取。';
    }
    return _ToolOutcome(
      status: result.ok ? VibeToolStatus.ok : VibeToolStatus.error,
      summary: result.summary,
      modelText: text,
      code: result.ok ? null : 'web',
      newSources: fresh,
    );
  }

  /// `todo`：整体替换计划，并把快照挂到该工具条目上。
  _ToolOutcome _updatePlan(Map<String, dynamic> args) {
    final next = parseVibePlan(args['items']);
    if (vibePlanAllDone(next) && _roundHadFailures) {
      return _error('plan', '本轮仍有工具失败，计划不能全部标记为 done');
    }
    _plan = next;
    _notify();
    final done = next
        .where((item) => item.status == VibePlanStatus.done)
        .length;
    return _ToolOutcome(
      status: VibeToolStatus.ok,
      summary: '$done/${next.length} 完成',
      modelText: describeVibePlan(next),
      plan: next,
    );
  }

  /// `use_skill`：按名称返回技能正文。
  Future<_ToolOutcome> _useSkill(Map<String, dynamic> args) async {
    final name = args['name'];
    if (name is! String || name.trim().isEmpty) {
      return _error('error', 'name 必须是非空字符串');
    }
    final wanted = name.trim();
    final available = _skills.where((skill) => skill.name == wanted);
    if (available.isEmpty) {
      final names = _skills.isEmpty
          ? '当前项目没有可用技能'
          : '可用技能：${_skills.map((skill) => skill.name).join('、')}';
      return _error('skill', '没有名为 $wanted 的技能。$names');
    }
    final match = available.first;
    final body = await match.resolveBody();
    if (body.trim().isEmpty) {
      return _error('skill', '技能 $wanted 的正文读取失败，请检查文件是否存在');
    }
    if (!_usedSkills.contains(match.name)) _usedSkills.add(match.name);
    _notify();
    return _ToolOutcome(
      status: VibeToolStatus.ok,
      summary: '${match.name}（${match.source}）',
      modelText: body,
    );
  }

  /// 走在线终端：快照上传、进度与退出码。
  Future<_ToolOutcome> _runCommand(Map<String, dynamic> args, int index) async {
    final command = args['command'];
    if (command is! String || command.trim().isEmpty) {
      return _error('error', 'command 不能为空');
    }
    if (command.length > 2000) {
      return _error(
        'error',
        '命令超过 2000 字符。把检查逻辑用 write_file 写成项目里的文件，'
            '再用一行短命令执行，例如 python3 check.py。',
      );
    }
    // 先尝试跨应用运行：OHOS 上由兄弟应用用本地工具链编译并执行。
    // 返回 null 表示不适用（无桥接、入口不匹配、命令不属于该语法），
    // 此时才回落到在线终端，两条路径不会重复执行。
    final interop = await _tryInteropRun(command, index);
    if (interop != null) return interop;
    if (_cancelRequested) return _cancelledOutcome();
    return _runCommandInTerminal(command, index);
  }

  /// 跨应用运行一次命令；不适用时返回 null。
  ///
  /// 只有结果里的内容都是对方应用真实输出时才当作成功，不编造退出码。
  Future<_ToolOutcome?> _tryInteropRun(String command, int index) async {
    final runner = _interop;
    if (runner == null || !runner.isSupported) return null;
    if (!InteropRunner.supports(_language)) return null;
    _updateTool(index, stage: '跨应用运行');
    final InteropRun? run;
    try {
      run = await runner.tryRunCommand(
        projectRoot: _files.projectRoot,
        language: _language,
        command: command,
      );
    } on Object catch (error) {
      // 桥接自身出错时回落到在线终端，并把原因交给模型。
      _updateTool(index, stage: '跨应用不可用，改用在线终端');
      _notice('跨应用运行失败，已改用在线终端：$error');
      return null;
    }
    if (run == null) return null;
    final stdout = _TailBuffer(kVibeMaxCommandTailChars);
    final stderr = _TailBuffer(kVibeMaxCommandTailChars);
    _updateTool(index, output: '');
    await for (final chunk in run.stdout) {
      stdout.add('$chunk\n');
      _updateTool(index, output: _combine(stdout.value, stderr.value));
    }
    await for (final chunk in run.stderr) {
      stderr.add('$chunk\n');
      _updateTool(index, output: _combine(stdout.value, stderr.value));
    }
    final exitCode = await run.exitCode;
    final output = _combine(stdout.value, stderr.value);
    final diagnostics = run.diagnostics.isEmpty
        ? ''
        : '\n${run.diagnostics.join('\n')}';
    return _ToolOutcome(
      status: exitCode == 0 ? VibeToolStatus.ok : VibeToolStatus.error,
      summary: '跨应用 · 退出码 $exitCode',
      modelText:
          '退出码：$exitCode（跨应用运行：${run.title}）$diagnostics\n'
          '${output.isEmpty ? '（无输出）' : output}',
      output: output.isEmpty ? null : output,
      exitCode: exitCode,
    );
  }

  Future<_ToolOutcome> _runCommandInTerminal(String command, int index) async {
    // 先置位再等待：快照收集期间终端会话已经算“用过”，
    // 否则取消落在这段窗口里就回收不到会话，下一任务会抢同一个终端。
    _usedTerminal = true;
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      _terminalUnavailable = true;
      _usedTerminal = false;
      return _error(
        'auth',
        '终端不可用（未登录）。不要重试 run_command，'
            '直接说明未能运行验证，并用 list_files 与内置检查说明交付物。',
      );
    }
    final List<Map<String, String>> snapshot;
    try {
      snapshot = await VibeProjectSnapshot.collect(_files.projectRoot);
    } on VibeToolException catch (error) {
      _usedTerminal = false;
      return _error(error.code, error.message);
    }
    if (_cancelRequested) {
      // 终端会话已经占过位（`_usedTerminal`），取消要走回收，否则下一任务会
      // 抢同一个会话；这里不能把占位清掉，交给 cancel() 统一处理。
      return _cancelledOutcome();
    }

    final stdout = _TailBuffer(kVibeMaxCommandTailChars);
    final stderr = _TailBuffer(kVibeMaxCommandTailChars);
    final result = Completer<_ToolOutcome>();
    _commandCompletion = result;
    var sawResult = false;
    var exitCode = 1;

    void publishProgress(String stage, {bool notify = true}) {
      if (notify) _updateTool(index, stage: stage);
    }

    void finish(_ToolOutcome outcome) {
      if (!result.isCompleted) result.complete(outcome);
    }

    publishProgress('上传项目并排队');
    final StreamSubscription<TerminalEvent> subscription;
    try {
      subscription = _api
          .terminalEvents(
            token,
            command,
            files: snapshot,
            abortTrigger: _abort?.future,
          )
          .listen(
            (event) {
              switch (event.type) {
                case TerminalEventType.progress:
                  publishProgress(_stageLabel(event.stage));
                case TerminalEventType.stdout:
                  stdout.add(event.text ?? '');
                  _updateTool(
                    index,
                    output: _combine(stdout.value, stderr.value),
                  );
                case TerminalEventType.stderr:
                  stderr.add(event.text ?? '');
                  _updateTool(
                    index,
                    output: _combine(stdout.value, stderr.value),
                  );
                case TerminalEventType.result:
                  sawResult = true;
                  exitCode = event.exitCode ?? 1;
              }
            },
            onError: (Object error) {
              // 取消后 abortTrigger 会先结束字节流，紧跟着的“请求已取消”
              // 不是终端故障，不能当作模型需要处理的错误。
              final cancelled =
                  _cancelRequested ||
                  (error is ApiException && error.message == '请求已取消');
              if (cancelled) {
                finish(_cancelledOutcome());
              } else {
                final message = error is ApiException
                    ? error.message
                    : '终端连接失败：$error';
                if (_isTerminalUnavailable(error)) {
                  _terminalUnavailable = true;
                  finish(
                    _ToolOutcome(
                      status: VibeToolStatus.error,
                      summary: message,
                      modelText:
                          'error(auth): 终端不可用（$message）。'
                          '不要重试 run_command，直接说明未能运行验证。',
                      output: _combine(stdout.value, stderr.value),
                      code: 'auth',
                    ),
                  );
                  return;
                }
                finish(
                  _ToolOutcome(
                    status: VibeToolStatus.error,
                    summary: message,
                    modelText: '终端执行失败：$message',
                    output: _combine(stdout.value, stderr.value),
                  ),
                );
              }
            },
            onDone: () {
              if (_cancelRequested) {
                finish(_cancelledOutcome());
                return;
              }
              if (!sawResult) {
                // 流正常结束却没给出退出码：同样属于终端不可用。
                _terminalUnavailable = true;
                finish(
                  _ToolOutcome(
                    status: VibeToolStatus.error,
                    summary: '终端未返回执行结果',
                    modelText:
                        'error(auth): 终端不可用（未返回执行结果）。'
                        '不要重试 run_command，直接说明未能运行验证。',
                    output: _combine(stdout.value, stderr.value),
                    code: 'auth',
                  ),
                );
                return;
              }
              final output = _combine(stdout.value, stderr.value);
              finish(
                _ToolOutcome(
                  status: exitCode == 0
                      ? VibeToolStatus.ok
                      : VibeToolStatus.error,
                  summary: '退出码 $exitCode',
                  modelText:
                      '退出码：$exitCode\n'
                      '${output.isEmpty ? '（无输出）' : output}',
                  output: output,
                  exitCode: exitCode,
                ),
              );
            },
            cancelOnError: true,
          );
    } on ApiException catch (error) {
      return _error('terminal', error.message);
    }
    _terminalSubscription = subscription;
    final outcome = await result.future;
    // 取消时 abortTrigger 已中断 HTTP；此处不阻塞等待流关闭。
    unawaited(subscription.cancel());
    if (identical(_terminalSubscription, subscription)) {
      _terminalSubscription = null;
    }
    if (identical(_commandCompletion, result)) _commandCompletion = null;
    return outcome;
  }

  // ---- 状态 ----

  String _systemPrompt() =>
      '''
你是 QFLI 编辑器里的编程助手，直接操作真实项目。
项目：$_projectName（$_language），所有路径都相对当前项目根目录。
工具规则：
1. 只能通过工具读写项目文件，不要输出绝对路径。
2. 多步骤任务先用 todo 列出计划，完成后立刻开始写文件，不要停下来反复列目录。
3. 修改已有文件前先 read_file；小改动用 edit_file，新建文件用 write_file。
4. 建站类任务：规划完成后立刻用 write_file 创建 index.html，不要反复 list_files。
   根目录用 `.` 或空串一次列完就够了，列完就动手。
5. 用 run_command 运行代码、构建或测试，命令在隔离在线终端执行。
6. 没有真实工具结果时不得声称运行成功或测试通过。
7. 工具失败时读取真实错误，修复后重新运行，直到验证通过或确认无法继续。
8. 网页类交付物的完成标准：list_files 能看到全部文件，且 run_command 的结构检查通过。
9. 同一个失败命令连续报错时，先 read_file 看当前内容，不要盲目重试。
10. 用过 web_fetch 时，最终回答必须列出所用来源：
    每条一行，写标题和完整网址，例如“- 标题 — https://example.com/a”。
    只引用工具实际返回过的网址，逐字照抄，不得编造或补全。
    工具没返回可用结果时，直接说明查不到，不要编造来源。
    联网搜索工具已下线，不要声称自己搜过网。
回答用中文，简洁说明改动内容和真实验证结果。''';

  // ---- 流式回合 ----

  /// 消费一次模型的回合事件流，返回权威结果。
  ///
  /// 增量只用于显示。写历史、执行工具只认 `AiTurnCompleted.result`
  /// （design §5.1）。
  Future<AiChatResult> _consumeTurn(
    _StreamTurn turn, {
    required String token,
  }) async {
    AiChatResult? completed;
    try {
      final events = _api.aiChatStream(
        token: token,
        messages: List.unmodifiable(_history),
        tools: _toolSpecs(),
        abortTrigger: _abort?.future,
        endpoint: _endpointProvider?.call(),
        model: _modelId,
        reasoningEffort: _reasoningEffort,
      );
      await for (final event in events) {
        switch (event) {
          case AiReasoningDelta(:final text):
            turn.emitted = true;
            _pushReasoning(turn, text);
          case AiContentDelta(:final text):
            turn.emitted = true;
            _pushContent(turn, text);
          case AiToolCallStarted():
            turn.emitted = true;
            _closeReasoning(turn);
          case AiTurnCompleted(:final result):
            completed = result;
        }
      }
    } finally {
      if (completed == null) _interruptStreaming(turn);
    }
    final result = completed;
    if (result == null) {
      // 取消或被中断。交给调用方按现有规则收尾。
      throw ApiException(
        'AI 回合没有返回结果',
        details: const {'code': 'AI_STREAM_INCOMPLETE'},
      );
    }
    _lastReportedInputTokens = _reportedInputTokens(result.usage);
    _invalidateContextUsage();
    return result;
  }

  static int? _reportedInputTokens(Map<String, dynamic>? usage) {
    if (usage == null) return null;
    for (final key in const ['prompt_tokens', 'input_tokens']) {
      final value = usage[key];
      if (value is int && value >= 0) return value;
    }
    return null;
  }

  /// 思考增量：第一条新建思考消息并开始计时。
  void _pushReasoning(_StreamTurn turn, String text) {
    final index = turn.reasoningIndex ??= _openReasoningMessage(turn);
    turn.reasoningText += text;
    _pushLive(index, turn.reasoningText);
  }

  /// 新建思考消息，并开始计时。
  int _openReasoningMessage(_StreamTurn turn) {
    turn.clock = Stopwatch()..start();
    return _openLiveMessage(
      const VibeMessage(
        isUser: false,
        text: '',
        pending: true,
        aiGenerated: true,
        kind: VibeMessageKind.reasoning,
      ),
    );
  }

  /// 正文增量：第一条新建助手文本消息并保持 pending。
  void _pushContent(_StreamTurn turn, String text) {
    _closeReasoning(turn);
    final index = turn.contentIndex ??= _openLiveMessage(
      const VibeMessage(
        isUser: false,
        text: '',
        pending: true,
        aiGenerated: true,
      ),
    );
    turn.contentText += text;
    _pushLive(index, turn.contentText);
  }

  /// 思考收尾：气泡不再 pending，写入用时。正文或工具开始时调用。
  void _closeReasoning(_StreamTurn turn) {
    final index = turn.reasoningIndex;
    if (index == null || turn.reasoningClosed) return;
    turn.reasoningClosed = true;
    turn.clock?.stop();
    _settleMessage(
      index,
      text: turn.reasoningText,
      durationMs: turn.clock?.elapsedMilliseconds ?? 0,
    );
    _retireLive(index);
  }

  /// 回合结束后用权威结果校准思考文本。
  ///
  /// 没有增量时（旧中转、上游返回 JSON）也补一条气泡，否则思考内容白丢。
  void _calibrateReasoning(_StreamTurn turn, AiChatResult result) {
    final index = turn.reasoningIndex;
    if (index == null) {
      if (result.reasoning.isEmpty) return;
      _appendMessage(
        VibeMessage(
          isUser: false,
          text: result.reasoning,
          aiGenerated: true,
          kind: VibeMessageKind.reasoning,
        ),
      );
      return;
    }
    turn.reasoningClosed = true;
    turn.clock?.stop();
    _settleMessage(
      index,
      text: result.reasoning.isNotEmpty ? result.reasoning : turn.reasoningText,
      durationMs: turn.clock?.elapsedMilliseconds ?? 0,
    );
    _retireLive(index);
  }

  /// 回合结束后用权威结果校准正文。
  /// 没有增量时补一条消息。
  void _calibrateContent(_StreamTurn turn, AiChatResult result) {
    final text = result.content.trim().isNotEmpty
        ? result.content.trim()
        : turn.contentText.trim();
    final index = turn.contentIndex;
    if (index == null) {
      if (text.isEmpty) return;
      _appendMessage(
        VibeMessage(isUser: false, text: text, aiGenerated: result.aiGenerated),
      );
      return;
    }
    _settleMessage(index, text: text);
    _retireLive(index);
  }

  /// 回合意外结束时，把还在流式中的消息收尾。
  ///
  /// 取消可能落在“结果已到、还没校准”的窗口里，这时不能留下一个转圈的气泡。
  void _closeLiveMessages() {
    if (_liveText.isEmpty) return;
    for (final index in List<int>.of(_liveText.keys)) {
      final text = _liveBuffer.remove(index);
      _settleMessage(index, text: text ?? _messages[index].text);
      _retireLive(index);
    }
  }

  /// 取消或中断：保留已经显示的内容，消息改为不 pending。
  void _interruptStreaming(_StreamTurn turn) {
    final reasoning = turn.reasoningIndex;
    if (reasoning != null) {
      turn.clock?.stop();
      _settleMessage(reasoning, text: turn.reasoningText);
      _retireLive(reasoning);
    }
    final content = turn.contentIndex;
    if (content != null) {
      _settleMessage(content, text: turn.contentText);
      _retireLive(content);
    }
  }

  /// 新增一条流式消息，并给它一个实时文本 notifier。
  int _openLiveMessage(VibeMessage message) {
    final index = _appendMessage(message);
    _liveText[index] = ValueNotifier<String>('');
    return index;
  }

  /// 把一条流式消息写成最终内容。
  void _settleMessage(int index, {required String text, int? durationMs}) {
    if (index < 0 || index >= _messages.length) return;
    final current = _messages[index];
    if (current.text == text &&
        !current.pending &&
        current.durationMs == durationMs) {
      return;
    }
    _messages[index] = current.copyWith(
      text: text,
      pending: false,
      durationMs: durationMs,
    );
    _notify();
  }

  /// 记下新的实时文本。下一帧合并写入，每帧最多一次。
  void _pushLive(int index, String text) {
    if (!_liveText.containsKey(index)) return;
    _liveBuffer[index] = text;
    _scheduleLiveFlush();
  }

  void _scheduleLiveFlush() {
    if (_liveFlushScheduled) return;
    final frames = _frames;
    if (frames == null) {
      _flushLive();
      return;
    }
    _liveFlushScheduled = true;
    frames.scheduleFrameCallback((_) {
      _liveFlushScheduled = false;
      _flushLive();
    });
    frames.ensureVisualUpdate();
  }

  void _flushLive() {
    if (_liveBuffer.isEmpty) return;
    final pending = Map<int, String>.of(_liveBuffer);
    _liveBuffer.clear();
    for (final entry in pending.entries) {
      final notifier = _liveText[entry.key];
      if (notifier != null) notifier.value = entry.value;
    }
  }

  /// 流式结束：补上最后一段文本，之后不再实时更新。
  void _retireLive(int index) {
    final text = _liveBuffer.remove(index);
    final notifier = _liveText.remove(index);
    if (notifier == null) return;
    if (text != null && notifier.value != text) notifier.value = text;
    _retiredLive.add(notifier);
  }

  /// 帧调度器。没有绑定（纯单元测试）时返回 null，直接写入。
  static SchedulerBinding? get _frames {
    try {
      return SchedulerBinding.instance;
    } on Object {
      return null;
    }
  }

  int _appendMessage(VibeMessage message) {
    _messages.add(message);
    _notify();
    return _messages.length - 1;
  }

  void _replaceMessage(int index, VibeMessage message) {
    if (index < 0 || index >= _messages.length) return;
    _messages[index] = message;
    _notify();
  }

  void _updateTool(
    int index, {
    String? stage,
    String? output,
    bool notify = true,
  }) {
    if (index < 0 || index >= _messages.length) return;
    final current = _messages[index];
    final tool = current.tool;
    if (tool == null) return;
    _messages[index] = current.copyWith(
      tool: tool.copyWith(
        result: stage ?? tool.result,
        commandOutput: output ?? tool.commandOutput,
      ),
    );
    if (notify) _notify();
  }

  void _fail(String message, {ApiException? apiError}) {
    _lastError = message;
    _lastApiError = apiError;
    _finish(VibePhase.failed);
  }

  void _finish(VibePhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _notice(String message) => _onNotice?.call(message);

  Future<void> _resetTerminal() async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) return;
    try {
      await _api.resetTerminal(token);
    } on ApiException {
      // 取消已生效，会话回收失败不影响结果。
    }
  }

  void _trimHistory() {
    const keep = 80;
    final extras = _history.length - 1;
    if (extras > keep) {
      var start = _history.length - keep;
      // 片段不能以 tool 结果开头，否则上游拒绝。
      while (start < _history.length && _history[start]['role'] == 'tool') {
        start++;
      }
      _rewriteHistory(start);
    }
    _trimHistoryBytes();
  }

  /// 序列化后超过 [_maxHistoryBytes] 时，从最旧的完整轮次开始丢。
  ///
  /// 思考内容会明显撑大历史，而中转的请求体上限是 512 KiB，
  /// 这里给中转留出余量（design §5.3）。
  void _trimHistoryBytes() {
    if (_history.length <= 1) return;
    var bytes = 0;
    for (final entry in _history) {
      bytes += _entryBytes(entry);
    }
    if (bytes <= _maxHistoryBytes) return;
    var start = 1;
    while (start < _history.length && bytes > _maxHistoryBytes) {
      bytes -= _entryBytes(_history[start]);
      start++;
    }
    // 只从完整轮次（user 条目）开始，起点一定不是 tool 条目。
    while (start < _history.length && _history[start]['role'] != 'user') {
      start++;
    }
    if (start <= 1 || start >= _history.length) return;
    _rewriteHistory(start);
  }

  /// 一条历史条目序列化后的字节数，含结尾换行。
  static int _entryBytes(Map<String, dynamic> entry) =>
      utf8.encode(jsonEncode(entry)).length + 1;

  /// 丢掉 [start] 之前的条目，系统提示永远保留。
  void _rewriteHistory(int start) {
    if (start <= 1 || start >= _history.length) return;
    final kept = _history.sublist(start);
    _history
      ..clear()
      ..add({'role': 'system', 'content': _systemPrompt()})
      ..addAll(kept);
    _invalidateContextUsage();
  }

  /// 历史的字节预算。给中转的 512 KiB 请求体留出余量。
  static const int _maxHistoryBytes = 448 * 1024;

  /// 把思考内容写进助手历史条目，下一轮原样回传。
  static void _carryReasoning(
    Map<String, dynamic> assistant,
    AiChatResult result,
  ) {
    final content = result.rawMessage['reasoning_content'];
    if (content is String && content.isNotEmpty) {
      assistant['reasoning_content'] = content;
    }
    final blocks = _cleanReasoningBlocks(result.rawMessage['reasoning_blocks']);
    if (blocks.isNotEmpty) {
      assistant['reasoning_blocks'] = blocks;
    }
  }

  /// 只保留已知键的思考块。
  ///
  /// 直连 Messages 协议要求原样回传这些块，所以签名和 `data` 不能丢。
  static List<Map<String, dynamic>> _cleanReasoningBlocks(Object? value) {
    if (value is! List) return const [];
    final blocks = <Map<String, dynamic>>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final type = entry['type'];
      if (type is! String || type.isEmpty) continue;
      final block = <String, dynamic>{'type': type};
      for (final key in const ['thinking', 'signature', 'data']) {
        final field = entry[key];
        if (field is String && field.isNotEmpty) block[key] = field;
      }
      blocks.add(block);
    }
    return blocks;
  }

  /// 恢复历史时只保留协议合法的完整轮次。
  ///
  /// 丢掉 system 行、孤立的 tool 回复，以及尾部没有答完的 tool_calls 组，
  /// 避免会话重启后第一轮就被上游拒绕。
  static List<Map<String, dynamic>> _sanitizeHistory(
    Iterable<Map<String, dynamic>> entries,
  ) {
    final kept = <Map<String, dynamic>>[];
    final pending = <String>{};
    for (final entry in entries) {
      final role = entry['role'];
      if (role == 'tool') {
        final id = entry['tool_call_id'];
        if (id is! String || !pending.remove(id)) continue;
        kept.add({
          'role': 'tool',
          'tool_call_id': id,
          'content': entry['content'] is String ? entry['content'] : '',
        });
        continue;
      }
      if (role == 'assistant') {
        final calls = entry['tool_calls'];
        final ids = <String>[];
        if (calls is List) {
          for (final call in calls) {
            final id = call is Map ? call['id'] : null;
            if (id is String && id.isNotEmpty) ids.add(id);
          }
        }
        final content = entry['content'];
        final sanitized = <String, dynamic>{
          'role': 'assistant',
          'content': content is String ? content : null,
        };
        if (ids.isNotEmpty && calls is List) {
          sanitized['tool_calls'] = calls;
        }
        final reasoning = entry['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) {
          sanitized['reasoning_content'] = reasoning;
        }
        final blocks = _cleanReasoningBlocks(entry['reasoning_blocks']);
        if (blocks.isNotEmpty) {
          sanitized['reasoning_blocks'] = blocks;
        }
        kept.add(sanitized);
        pending.addAll(ids);
        continue;
      }
      if (role == 'user') {
        final content = entry['content'];
        if (content is! String || content.trim().isEmpty) continue;
        kept.add({'role': 'user', 'content': content});
      }
    }
    // 从尾部裁掉没答完的一组，连同它的 assistant 消息。
    while (pending.isNotEmpty && kept.isNotEmpty) {
      final last = kept.removeLast();
      if (last['role'] == 'tool') {
        pending.remove(last['tool_call_id']);
        continue;
      }
      final calls = last['tool_calls'];
      if (calls is List) {
        for (final call in calls) {
          final id = call is Map ? call['id'] : null;
          if (id is String) pending.remove(id);
        }
      }
    }
    if (kept.length > 60) {
      var start = kept.length - 60;
      while (start < kept.length && kept[start]['role'] == 'tool') {
        start++;
      }
      return kept.sublist(start);
    }
    return kept;
  }

  static String _requiredString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw VibeToolException('$key 必须是非空字符串');
    }
    return value;
  }

  static String _summarize(String name, String arguments) {
    if (name == 'run_command') {
      try {
        final value = jsonDecode(arguments);
        if (value is Map && value['command'] is String) {
          return _short(value['command'] as String, 160);
        }
      } on FormatException {
        // 参数不是 JSON 时显示原始片段。
      }
    } else {
      try {
        final value = jsonDecode(arguments);
        if (value is Map && value['path'] is String) {
          return _short(value['path'] as String, 160);
        }
      } on FormatException {
        // 同上。
      }
    }
    return _short(arguments, 160);
  }

  static String _short(String value, int max) {
    final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max)}…';
  }

  static String _bounded(String value, int max) => value.length <= max
      ? value
      : '…（已截断）\n${value.substring(value.length - max)}';

  static String _combine(String stdout, String stderr) {
    if (stdout.isEmpty) return stderr;
    if (stderr.isEmpty) return stdout;
    return '$stdout\n$stderr';
  }

  static String _stageLabel(String? stage) => switch (stage) {
    'queued' => '排队中',
    'initializing' => '初始化终端',
    'ready' => '终端已就绪',
    'uploading' => '上传项目快照',
    'running' => '运行中',
    'cleaning' => '清理环境',
    _ => '准备执行',
  };

  /// 终端不可用：没拿到退出码，且失败出在终端链路本身。
  ///
  /// 分类先看类型：[ApiException] 说明请求没走到命令，属于传输或认证层，
  /// 重试也改变不了。状态码 401/403/408/5xx 同理。
  /// 文案只做兜底，覆盖不抛异常或抛非 [ApiException] 的情形。
  static bool _isTerminalUnavailable(Object error) {
    if (error is ApiException) {
      final status = error.statusCode;
      if (status == null) return true;
      return status == 401 || status == 403 || status == 408 || status >= 500;
    }
    final message = error is String ? error : '$error';
    const hints = [
      '未登录',
      '登录已过期',
      '登录过期',
      '需要登录',
      '重新登录',
      'unauthorized',
      '安全连接',
      '连接超时',
      '连接已中断',
      '无法连接终端',
      '网络错误',
      'socket',
      'handshake',
      'timeout',
    ];
    final lower = message.toLowerCase();
    return hints.any((hint) => lower.contains(hint.toLowerCase()));
  }

  static _ToolOutcome _error(
    String code,
    String message, {
    bool conflict = false,
  }) => _ToolOutcome(
    status: conflict ? VibeToolStatus.conflict : VibeToolStatus.error,
    summary: message,
    modelText: 'error($code): $message',
    code: code,
  );

  static _ToolOutcome _cancelledOutcome() => const _ToolOutcome(
    status: VibeToolStatus.error,
    summary: '已取消',
    modelText: 'error(cancelled): 用户取消了执行',
    code: 'cancelled',
  );
}

class _WriteCancelled {
  const _WriteCancelled();
}

/// 一轮流式回合的临时状态。
///
/// 每次请求前调用 [reset]，重试时不会把上一轮的下标串进来。
class _StreamTurn {
  int? reasoningIndex;
  int? contentIndex;
  Stopwatch? clock;
  String reasoningText = '';
  String contentText = '';
  bool reasoningClosed = false;

  /// 本轮是否已经发出过增量。
  /// 已发出增量的回合不重试。
  bool emitted = false;

  void reset() {
    reasoningIndex = null;
    contentIndex = null;
    clock = null;
    reasoningText = '';
    contentText = '';
    reasoningClosed = false;
    emitted = false;
  }
}

class _ParsedCall {
  const _ParsedCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;
}

class _ToolOutcome {
  const _ToolOutcome({
    required this.status,
    required this.summary,
    required this.modelText,
    this.output,
    this.exitCode,
    this.readPath,
    this.writtenPath,
    this.plan,
    this.code,
    this.listedDirs = 0,
    this.newSources = 0,
  });

  final VibeToolStatus status;
  final String summary;
  final String modelText;
  final String? output;
  final int? exitCode;

  /// 本次调用实际读取的相对路径，用于先读后改与进展判定。
  final String? readPath;

  /// 本次调用成功写入的相对路径。
  final String? writtenPath;

  /// todo 提交后的计划快照。
  final List<VibePlanItem>? plan;

  /// 本次调用成功列出的目录数（0 或 1）。
  final int listedDirs;

  /// 本次联网调用带回的新来源数（0 或 1）；重复查询与重复网址为 0。
  final int newSources;

  /// 失败分类（`conflict`、`unread`、`plan` 等）；成功时为 null。
  final String? code;

  bool get ranCommand => exitCode != null;
}

class _TailBuffer {
  _TailBuffer(this.max);

  final int max;
  String _value = '';

  void add(String chunk) {
    if (chunk.isEmpty) return;
    _value += chunk;
    if (_value.length > max) {
      _value = '…（输出已截断）\n${_value.substring(_value.length - max)}';
    }
  }

  String get value => _value;
}
