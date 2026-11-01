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
            VibeMessage(isUser: false, text: reply.content.trim()),
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
        final stalled = guard.endRound(facts);
        if (stalled != null) {
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
    if (outcome.ranCommand) facts.exitCodes.add(outcome.exitCode);
    if (outcome.status == VibeToolStatus.error ||
        outcome.status == VibeToolStatus.conflict) {
      facts.errors.add('${outcome.code}: ${outcome.summary}');
      _roundHadFailures = true;
    }
  }

  /// 本轮工具列表。离线专属产品不暴露联网工具。
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
          final result = await _files.write(
            path,
            content,
            createOnly: args['createOnly'] == true,
          );
          guard.markWritten(result.relativePath);
          _onFileChanged?.call(result.relativePath);
          final verify = _verificationHint(result.relativePath);
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary:
                '${result.created ? '已创建' : '已写入'} '
                '${result.relativePath} · ${result.bytes} B',
            modelText:
                '${result.created ? '已创建' : '已写入'} ${result.relativePath}'
                '（${result.bytes} B）'
                '${result.backupPath == null ? '' : '，原文件已备份'}'
                '${verify == null ? '' : '\n$verify'}',
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
          return _ToolOutcome(
            status: VibeToolStatus.ok,
            summary: '已替换 ${result.relativePath} · ${result.bytes} B',
            modelText: '已替换 ${result.relativePath}（${result.bytes} B），原文件已备份',
            writtenPath: result.relativePath,
          );
        case 'run_command':
          return await _runCommand(args, index);
        case 'todo':
          return _updatePlan(args);
        case 'use_skill':
          return _useSkill(args);
        case 'web_search':
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

  /// 连接内自检脚本：解析本地 HTML 的真实结构。
  ///
  /// 只读快照内的文件，没有任何外部依赖。
  static const String _htmlCheckScript = r'''
from html.parser import HTMLParser
from pathlib import Path
import sys

VOID = {'meta', 'link', 'br', 'img', 'input', 'hr', 'source'}


class Checker(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.errors = []
        self.count = 0

    def handle_starttag(self, tag, attrs):
        self.count += 1
        if tag not in VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()
        elif tag in self.stack:
            self.errors.append('</%s> 之前有未闭合标签' % tag)
            while self.stack and self.stack.pop() != tag:
                pass
        else:
            self.errors.append('多余的 </%s>' % tag)


files = [Path('index.html')]
files += sorted(p for p in Path('.').glob('*.css'))
failed = False
for path in files:
    if not path.is_file() or path.stat().st_size == 0:
        print('缺失或为空:', path)
        failed = True
        continue
    print('文件:', path, path.stat().st_size, 'B')

checker = Checker()
if Path('index.html').is_file():
    checker.feed(Path('index.html').read_text(encoding='utf-8'))
if checker.errors or checker.stack:
    print('标签问题:', checker.errors, '未闭合:', checker.stack)
    failed = True
else:
    print('结构检查: OK，%d 个开始标签' % checker.count)
sys.exit(1 if failed else 0)
''';

  /// 写入成功后的自检提示：网页类项目要跑真实结构检查。
  String? _verificationHint(String relativePath) {
    if (relativePath != 'index.html') return null;
    return '接下来运行 run_command 验证页面结构：\n'
        'python3 - <<\'PY\'\n$_htmlCheckScript${'PY'}';
  }

  /// `web_search` / `web_fetch`：经服务端中转真实检索，结果原样交给模型。
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
    return _ToolOutcome(
      status: result.ok ? VibeToolStatus.ok : VibeToolStatus.error,
      summary: result.summary,
      modelText: result.modelText,
      code: result.ok ? null : 'web',
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
      return _error('error', '命令超过 2000 字符');
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
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      return _error('auth', '需要登录后才能使用在线终端');
    }
    final List<Map<String, String>> snapshot;
    try {
      snapshot = await VibeProjectSnapshot.collect(_files.projectRoot);
    } on VibeToolException catch (error) {
      return _error(error.code, error.message);
    }
    if (_cancelRequested) return _cancelledOutcome();

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
                finish(
                  _ToolOutcome(
                    status: VibeToolStatus.error,
                    summary: '终端未返回执行结果',
                    modelText: '终端连接中断，未收到真实执行结果',
                    output: _combine(stdout.value, stderr.value),
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
    _usedTerminal = true;
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
2. 多步骤任务先用 todo 列出计划，每完成一步就把该项改为 done。
3. 修改已有文件前先 read_file；小改动用 edit_file，新建文件用 write_file。
4. 用 run_command 运行代码、构建或测试，命令在隔离在线终端执行。
5. 没有真实工具结果时不得声称运行成功或测试通过。
6. 工具失败时读取真实错误，修复后重新运行，直到验证通过或确认无法继续。
7. 网页类交付物的完成标准：list_files 能看到全部文件，且 run_command 的结构检查通过。
8. 同一个失败命令连续报错时，先 read_file 看当前内容，不要盲目重试。
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
