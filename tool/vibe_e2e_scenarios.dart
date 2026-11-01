/// Vibe Coding 验收场景：提示词、断言与结果采集。
///
/// 场景只读取 [VibeCodingController] 的公开状态，不重新实现工具循环。
/// 断言直接对比真实工具结果；没有真实结果时场景判失败，不判通过。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

import 'vibe_e2e_report.dart';
import 'vibe_e2e_web_check.dart';

/// 单个场景定义。`prepare` 在临时项目里写好夹具文件。
class VibeE2eScenario {
  const VibeE2eScenario({
    required this.key,
    required this.title,
    required this.prompt,
    required this.language,
    required this.timeout,
    this.execution = VibeE2eExecution.terminal,
    this.requiresSearchTools = false,
    this.prepare,
    this.assertions,
  });

  final String key;
  final String title;
  final String prompt;
  final String language;
  final Duration timeout;

  /// `terminal` 依赖在线终端中继；`files` 只断言文件写入。
  final VibeE2eExecution execution;

  /// 需要 `web_search` / `web_fetch` 工具时置真；B 未发布前场景判跳过。
  final bool requiresSearchTools;

  final Future<void> Function(String projectRoot)? prepare;
  final List<VibeE2eAssertion> Function(VibeE2eScenarioOutcome outcome)?
  assertions;
}

enum VibeE2eExecution {
  /// 需要 `/api/terminal/exec/stream`。
  terminal,

  /// 只需要模型与文件工具。
  files,
}

/// 场景执行后可用于断言的事实集合。
class VibeE2eScenarioOutcome {
  const VibeE2eScenarioOutcome({
    required this.projectRoot,
    required this.phase,
    required this.toolCalls,
    required this.messages,
    required this.changedFiles,
  });

  final String projectRoot;
  final VibePhase phase;
  final List<VibeToolCall> toolCalls;
  final List<VibeMessage> messages;

  /// `onFileChanged` 报告的相对路径，按发生顺序。
  final List<String> changedFiles;

  List<VibeToolCall> callsOf(String name) =>
      toolCalls.where((call) => call.toolName == name).toList();

  List<VibeToolCall> get runs => callsOf('run_command');

  String? get assistantReply {
    for (final message in messages.reversed) {
      if (message.isUser || message.tool != null) continue;
      if (message.text.trim().isNotEmpty) return message.text.trim();
    }
    return null;
  }

  /// 本轮全部助手文本，按出现顺序拼接。
  ///
  /// [assistantReply] 只看最后一条，而检索类场景常常先说一句就收尾；
  /// 判断是否引用网址要看整段回答，不能只看末句。
  String get assistantTranscript => messages
      .where((message) => !message.isUser && message.tool == null)
      .map((message) => message.text.trim())
      .where((text) => text.isNotEmpty)
      .join('\n\n');

  Future<bool> hasFile(String relative) =>
      File(p.join(projectRoot, relative)).exists();
}

/// 断言集合的可复用片段。
abstract final class VibeE2eAssertions {
  static VibeE2eAssertion file(String name, bool ok, {String? detail}) =>
      VibeE2eAssertion(
        name: name,
        ok: ok,
        detail: detail ?? (ok ? 'present' : 'missing'),
      );

  /// 首个 run_command 必须真实失败，末个必须真实成功。
  static List<VibeE2eAssertion> firstFailLastPass(
    VibeE2eScenarioOutcome outcome,
  ) {
    final runs = outcome.runs;
    // 只算拿到真实退出码的运行。云终端漏令牌的 401 不是命令的结果，
    // 拿它当「第一次运行」会把日志读成另一种事实。
    final decided = runs.where((run) => run.exitCode != null).toList();
    if (decided.length < 2) {
      return [
        VibeE2eAssertion(
          name: 'runs_at_least_two',
          ok: false,
          detail: '带退出码的运行 ${decided.length} 次 / 共 ${runs.length} 次',
        ),
      ];
    }
    final first = decided.first.exitCode;
    final last = decided.last.exitCode;
    return [
      VibeE2eAssertion(
        name: 'first_run_failed',
        ok: first != null && first != 0,
        detail: 'exit $first',
      ),
      VibeE2eAssertion(
        name: 'last_run_passed',
        ok: last == 0,
        detail: 'exit $last',
      ),
    ];
  }
}

/// 内置场景表。顺序即报告顺序。
final List<VibeE2eScenario> vibeE2eScenarios = [
  VibeE2eScenario(
    key: 'static_site',
    title: '做一个待办事项小网站',
    language: 'web',
    timeout: const Duration(minutes: 6),
    prompt:
        '在项目里做一个待办事项小网站。创建 index.html、style.css 和 app.js，'
        'index.html 引用另外两个文件，app.js 实现新增与删除待办。'
        '可删除的待办在前端内存里维护。完成后用 list_files 确认三个文件都在。',
    execution: VibeE2eExecution.files,
    prepare: (root) async {
      await File(
        p.join(root, 'README.md'),
      ).writeAsString('# 待办小网站\n\n由 QFLI Vibe Coding 验收驱动创建。\n');
    },
    assertions: (outcome) {
      final written = outcome
          .callsOf('write_file')
          .map((call) => call.summary)
          .toList();
      final changed = outcome.changedFiles;
      bool touched(String name) =>
          changed.any((path) => p.basename(path) == name) ||
          written.any((path) => path.contains(name));
      return [
        VibeE2eAssertion(
          name: 'phase_succeeded',
          ok: outcome.phase == VibePhase.succeeded,
          detail: outcome.phase.name,
        ),
        VibeE2eAssertion(
          name: 'index_written',
          ok: touched('index.html'),
          detail: written.join(', '),
        ),
        VibeE2eAssertion(
          name: 'style_written',
          ok: touched('style.css') || touched('styles.css'),
          detail: written.join(', '),
        ),
        VibeE2eAssertion(
          name: 'script_written',
          ok: touched('app.js') || touched('script.js') || touched('main.js'),
          detail: written.join(', '),
        ),
        VibeE2eAssertion(
          name: 'html_references_assets',
          ok: _htmlReferences(
            outcome.projectRoot,
            const ['style', 'styles'],
            const ['app.js', 'script.js'],
          ),
          detail: 'index.html 的 link 与 script 引用',
        ),
        // 解析真实 HTML：标签能否闭合、引用的 css/js 是否真实存在。
        ...() {
          final check = checkVibeHtml(outcome.projectRoot, 'index.html');
          return [
            VibeE2eAssertion(
              name: 'html_well_formed',
              ok: check.parsed,
              detail: check.parsed ? '标签成对闭合' : check.problems.join('; '),
            ),
            VibeE2eAssertion(
              name: 'html_assets_exist',
              ok:
                  check.ok &&
                  check.stylesheets.isNotEmpty &&
                  check.scripts.isNotEmpty,
              detail: check.problems.isEmpty
                  ? 'css ${check.stylesheets.length}、js ${check.scripts.length} 均存在'
                  : check.problems.join('; '),
            ),
          ];
        }(),
      ];
    },
  ),
  VibeE2eScenario(
    key: 'python_fix_loop',
    title: '先看真实失败，再修好',
    language: 'python',
    timeout: const Duration(minutes: 6),
    prompt:
        '完成一次真实调试。第一步用 run_command 执行 python3 verify.py，'
        '必须先看到这次真实失败。然后读取 math_ops.py，用 edit_file 修复 add。'
        '创建 result.txt，content 参数用 JSON 字符串 "42\\n"，文件必须恰好三个字节。'
        '最后再次执行 python3 verify.py，必须看到 QFLI_VIBE_VERIFIED_42。'
        '完成实际工具操作后再回复。',
    prepare: (root) async {
      await File(
        p.join(root, 'math_ops.py'),
      ).writeAsString('def add(a, b):\n    return a - b\n');
      await File(p.join(root, 'verify.py')).writeAsString(
        'from pathlib import Path\n'
        'from math_ops import add\n'
        'assert add(20, 22) == 42\n'
        'assert Path("result.txt").read_bytes() == b"42\\n"\n'
        'print("QFLI_VIBE_VERIFIED_42")\n',
      );
    },
    assertions: (outcome) {
      final runs = outcome.runs;
      return [
        ...VibeE2eAssertions.firstFailLastPass(outcome),
        VibeE2eAssertion(
          name: 'edit_applied',
          ok: outcome
              .callsOf('edit_file')
              .any((call) => call.status == VibeToolStatus.ok),
          detail: '${outcome.callsOf('edit_file').length} 次 edit_file',
        ),
        VibeE2eAssertion(
          name: 'verification_marker',
          ok:
              runs.isNotEmpty &&
              (runs.last.commandOutput ?? '').contains('QFLI_VIBE_VERIFIED_42'),
          detail: '最后一次 run_command 的输出',
        ),
      ];
    },
  ),
  VibeE2eScenario(
    key: 'web_search',
    title: '需要最新事实的问题',
    language: 'web',
    timeout: const Duration(minutes: 6),
    prompt:
        '查一下 HarmonyOS NEXT 当前最新的公开 SDK 版本，给出发布日期和出处链接。'
        '必须使用 web_search 检索，并在回答里引用真实链接。',
    execution: VibeE2eExecution.files,
    requiresSearchTools: true,
    assertions: (outcome) {
      const searchTools = {'web_search', 'web_fetch'};
      final searchCalls = outcome.toolCalls
          .where((call) => searchTools.contains(call.toolName))
          .toList();
      // 判断引用要看整段回答：检索场景常常先说一句就收尾。
      final reply = outcome.assistantTranscript;
      final cited = RegExp(r'https?://\S+').hasMatch(reply);
      return [
        VibeE2eAssertion(
          name: 'search_tool_called',
          ok: searchCalls.isNotEmpty,
          detail: '${searchCalls.length} 次检索调用',
        ),
        VibeE2eAssertion(
          name: 'reply_cites_url',
          ok: cited,
          detail: cited ? '回答含链接' : '回答里没有网址（回答共 ${reply.length} 字）',
        ),
      ];
    },
  ),
];

bool _htmlReferences(
  String projectRoot,
  List<String> styleNames,
  List<String> scriptNames,
) {
  final file = File(p.join(projectRoot, 'index.html'));
  if (!file.existsSync()) return false;
  final html = file.readAsStringSync().toLowerCase();
  final hasStyle = styleNames.any(
    (name) => html.contains('href="$name') || html.contains("href='$name"),
  );
  final hasScript = scriptNames.any(
    (name) => html.contains('src="$name') || html.contains("src='$name"),
  );
  return hasStyle && hasScript;
}

/// 把控制器状态转成脱敏的工具证据。
List<Map<String, Object?>> vibeE2eToolEvidence(
  List<VibeToolCall> calls, {
  int maxOutput = 4096,
}) => [
  for (final call in calls)
    {
      'name': call.toolName,
      'status': call.status.name,
      'summary': call.summary,
      if (call.exitCode != null) 'exitCode': call.exitCode,
      // 失败原因必须落盘，否则只能看到 status=error。
      if (call.result != null && call.result!.isNotEmpty)
        'result': _tail(call.result!, 1024),
      if (call.commandOutput != null)
        'output': _tail(call.commandOutput!, maxOutput),
    },
];

String _tail(String value, int max) => value.length <= max
    ? value
    : '…（已截断）\n${value.substring(value.length - max)}';

/// 场景夹具写完后统计的文件清单，写进报告便于人工核对。
Future<Map<String, Object?>> vibeE2eFileEvidence(String projectRoot) async {
  final entries = <String, Object>{};
  await for (final entity in Directory(projectRoot).list(followLinks: false)) {
    if (entity is! File) continue;
    entries[p.basename(entity.path)] = await entity.length();
  }
  return {'projectFiles': entries};
}

/// 判断上游是否声明了检索工具；B 的适配器就绪前恒为 false。
bool vibeE2eHasSearchTools(List<Map<String, dynamic>> specs) {
  const names = {'web_search', 'web_fetch'};
  return specs.any((spec) {
    final function = spec['function'];
    return function is Map && names.contains(function['name']);
  });
}

/// 供运维脚本打印的一句话摘要，不含任何提示词内容。
String vibeE2eLine(Map<String, Object?> scenario) {
  final key = scenario['key'];
  final status = scenario['status'];
  final duration = scenario['durationMs'];
  final phase = scenario['phase'];
  return '$key  $status  $phase  ${duration}ms';
}

/// 报告里出现过的断言快照；测试用它校验字段名不被悄悄改掉。
const Set<String> kVibeE2eAssertionNames = {
  'phase_succeeded',
  'index_written',
  'style_written',
  'script_written',
  'html_references_assets',
  'html_well_formed',
  'html_assets_exist',
  'runs_at_least_two',
  'first_run_failed',
  'last_run_passed',
  'edit_applied',
  'verification_marker',
  'search_tool_called',
  'reply_cites_url',
};

/// 校验报告结构；返回问题列表，空表示合格。
List<String> vibeE2eReportProblems(Map<String, Object?> report) {
  final problems = <String>[];
  if (report['schema'] != kVibeE2eSchema) {
    problems.add('schema 不是 $kVibeE2eSchema');
  }
  final environment = report['environment'];
  if (environment is! Map) {
    problems.add('缺少 environment');
  } else {
    if (environment.containsKey('apiKey') || environment.containsKey('key')) {
      problems.add('environment 泄露密钥字段');
    }
    final scenarios = report['scenarios'];
    if (scenarios is! List || scenarios.isEmpty) {
      problems.add('scenarios 为空');
    }
  }
  final text = jsonEncode(report);
  for (final leak in ['QFLI_DEBUG_API_KEY', 'sk-', 'Bearer ']) {
    if (text.contains(leak)) problems.add('报告出现敏感片段 $leak');
  }
  return problems;
}
