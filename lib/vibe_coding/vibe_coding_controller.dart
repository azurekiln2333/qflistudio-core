/// AI 编程会话控制器：真实的模型/工具循环。
///
/// 每轮把完整助手消息（含 tool_calls）和工具结果写回对话，工具只能操作
/// 项目内文件或在隔离在线终端执行命令。控制器不编造执行结果。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../interop/interop_runner.dart';
import '../services/ai_file_header.dart';
import '../services/api_client.dart';
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
export 'vibe_rules.dart'
    show
        loadVibeRules,
        kVibeMaxRuleFileChars,
        kVibeMaxRulesChars,
        kVibeRuleFiles;
export 'vibe_tools.dart'
    show VibeProjectFiles, VibeToolException, VibeWriteResult;

/// 技能与计划的可替换来源；测试可注入固定实现。
abstract interface class VibeAgentContext {
  /// 当前可见技能（按名称排序）。
  Future<List<VibeSkill>> skills();

  /// 项目规则文本；没有规则时返回空串。
  Future<String> rules();
}

/// 默认实现：读项目目录、内置资产与仓库规则文件。
class VibeProjectAgentContext implements VibeAgentContext {
  VibeProjectAgentContext({required this.projectRoot, this.language = ''});

  final String projectRoot;
  final String language;

  @override
  Future<List<VibeSkill>> skills() =>
      VibeSkillLibrary(projectRoot: projectRoot, language: language).load();

  @override
  Future<String> rules() async => loadVibeRules(projectRoot);
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
       _interop = interopRunner {
    _history.add({'role': 'system', 'content': _systemPrompt()});
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

  late final VibeAgentContext _agent =
      _context ??
      VibeProjectAgentContext(
        projectRoot: _files.projectRoot,
        language: _language,
      );

  final List<Map<String, dynamic>> _history = [];
  final List<VibeMessage> _messages = [];
  List<VibePlanItem> _plan = const [];
  List<VibeSkill> _skills = const [];
  String _rules = '';
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
    _terminalUnavailable = false;
    _wroteCleanThisSend = false;
    _seenQueries.clear();
    _seenUrls.clear();
    _searchCount = 0;
    _appendMessage(VibeMessage(isUser: true, text: prompt));
    _history.add({'role': 'user', 'content': prompt});
    _trimHistory();
    _phase = VibePhase.running;
    _notify();
    _activeRun = _run(prompt);
  }

  /// 取消在途模型请求和终端执行；返回时本轮已停止并完成终端清理。
  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;    _phase = VibePhase.cancelling;
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
    super.dispose();
  }

  // ---- 循环 ----

  /// 一次 send 的主体：准备技能与规则，然后进入模型/工具循环。
  Future<void> _run(String prompt) async {
    _abort = Completer<void>();
    _usedTerminal = false;
    _usedSkills.clear();
    final guard = VibeLoopGuard();
    _finalizeOpenPlan(failed: true);
    final budget = _maxRounds ?? vibeRoundBudget(prompt);
    _skills = await _agent.skills();
    _rules = await _agent.rules();
    if (_cancelRequested || _disposed) return;
    guard.markSnapshot(await _projectSnapshot());
    _prepareContext(prompt);
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
        final AiChatResult reply;
        try {
          reply = await _api.aiChat(
            token: activeToken,
            messages: List.unmodifiable(_history),
            tools: _toolSpecs(),
            abortTrigger: _abort?.future,
            endpoint: _endpointProvider?.call(),
          );
        } on ApiException catch (error) {
          if (_cancelRequested || _disposed) {
            return;
          } else {
            _fail(error.message);
          }
          return;
        }
        if (_cancelRequested || _disposed) {
          return;
        }

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
        _history.add(assistant);
        if (reply.content.trim().isNotEmpty) {
          _appendMessage(
            VibeMessage(
              isUser: false,
              text: reply.content.trim(),
              aiGenerated: reply.aiGenerated,
            ),
          );
        }
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

  /// 本轮工具列表。离线专属产品不暴露联网工具。
  ///
  /// `web_search` 已下线（整改任务书 §3-W3）：联网搜索的唯一上游是未披露的
  /// 第三方，而§1 允许的第三方只有华为、深度求索和云厂商。`web_fetch` 保留。
  List<Map<String, dynamic>> _toolSpecs() =>
      vibeWebToolsAvailable ? vibeToolSpecsWithWeb() : vibeToolSpecs();

  /// 载入本次 send 的技能与规则，并写入系统提示后可变的上下文块。
  void _prepareContext(String prompt) {
    final skills = _skills;
    final rules = _rules;
    if (skills.isEmpty && rules.isEmpty) return;
    final buffer = StringBuffer(_systemPrompt());
    if (rules.isNotEmpty) {
      buffer.write('\n\n项目规则（来自仓库，必须遵守）：\n$rules');
    }
    if (skills.isNotEmpty) {
      buffer.write(
        '\n\n可用技能（只列出名称与说明）：\n'
        '${buildVibeSkillIndex(skills)}',
      );
      if (vibePromptWantsWeb(prompt) &&
          skills.any((skill) => skill.name == 'web-app-scaffold')) {
        buffer.write('\n本次需求是网页类任务，建议先 use_skill web-app-scaffold。');
      }
      buffer.write('\n需要完整步骤时调用 use_skill；不要凭空重复技能内容。');
    }
    _history[0] = {'role': 'system', 'content': buffer.toString()};
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
          guard.markRead(_files.relative(_files.resolve(path)));
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary:
                '${_files.relative(_files.resolve(path))} · '
                '${utf8.encode(content).length} B',
            modelText: content.isEmpty ? '文件为空' : content,
            readPath: path,
          );
        case 'write_file':
          final path = _requiredString(args, 'path');
          final content = args['content'];
          if (content is! String) return _error('error', 'content 必须是字符串');
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
          final editSidecar = await _writeAiMark(
            result.relativePath,
            editMark,
          );
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary: '已替换 ${result.relativePath} · ${result.bytes} B$editSidecar',
            modelText:
                '已替换 ${result.relativePath}（${result.bytes} B），原文件已备份'
                '$editSidecar',
            writtenPath: result.relativePath,
          );
        case 'run_command':
          return await _runCommand(args, index);
        case 'todo':
          return _updatePlan(args);
        case 'use_skill':
          return _useSkill(args);
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
  _ToolOutcome _useSkill(Map<String, dynamic> args) {
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
    if (!_usedSkills.contains(match.name)) _usedSkills.add(match.name);
    _notify();
    return _ToolOutcome(
      status: VibeToolStatus.ok,
      summary: '${match.name}（${match.source}）',
      modelText: match.body,
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
    }    if (_cancelRequested) {
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

  void _fail(String message) {
    _lastError = message;
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
    if (extras <= keep) return;
    var start = _history.length - keep;
    // 片段不能以 tool 结果开头，否则上游拒绝。
    while (start < _history.length && _history[start]['role'] == 'tool') {
      start++;
    }
    final kept = _history.sublist(start);
    _history
      ..clear()
      ..add({'role': 'system', 'content': _systemPrompt()})
      ..addAll(kept);
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
