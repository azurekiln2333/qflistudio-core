/// Trellis 斜杠命令：把 `/trellis:continue`、`/trellis:finish-work`
/// 展开成同名技能或项目里的命令文件。
///
/// 解析顺序：可见技能 → 项目命令文件 → 内置说明。任何一步取到的内容都按
/// [kTrellisCommandMaxChars] 截断，命令本身不执行任何脚本。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../vibe_coding/vibe_skills.dart';
import 'trellis_project.dart';

/// 展开后的指令上限（字符）。
const int kTrellisCommandMaxChars = 8 * 1024;

/// 一条 Trellis 斜杠命令。
class TrellisSlashCommand {
  const TrellisSlashCommand({
    required this.name,
    required this.skillNames,
    required this.projectPaths,
    required this.instructions,
  });

  /// 用户输入的命令名，例如 `/trellis:continue`。
  final String name;

  /// 同义技能名；按顺序取第一个可见的。
  final List<String> skillNames;

  /// 项目内的命令文件，相对项目根；按顺序取第一个存在的。
  final List<String> projectPaths;

  /// 都找不到时使用的内置说明。
  final String instructions;
}

/// 支持的命令。
const List<TrellisSlashCommand> kTrellisSlashCommands = [
  TrellisSlashCommand(
    name: '/trellis:continue',
    skillNames: ['trellis-continue', 'trellis:continue'],
    projectPaths: [
      '.pi/prompts/trellis-continue.md',
      '.claude/commands/trellis/continue.md',
    ],
    instructions: _continueInstructions,
  ),
  TrellisSlashCommand(
    name: '/trellis:finish-work',
    skillNames: ['trellis-finish-work', 'trellis:finish-work'],
    projectPaths: [
      '.pi/prompts/trellis-finish-work.md',
      '.claude/commands/trellis/finish-work.md',
    ],
    instructions: _finishInstructions,
  ),
];

const String _continueInstructions = '''
继续当前 Trellis 任务，按阶段接着做：

1. 读 `.trellis/workflow.md` 的阶段索引。
2. 读当前任务的 `task.json`，按 `status` 与产物决定步骤：
   - `planning` 且没有 `prd.md`：回到 1.1 写需求。
   - `planning` 且复杂任务缺 `design.md` 或 `implement.md`：补齐设计。
   - `planning` 且产物齐全：请用户确认后再开始实现。
   - `in_progress` 且未开工：进入 2.1 实现。
   - `in_progress` 且已实现未检查：进入 2.2 质量检查。
   - `completed`：进入归档流程。
3. 只读当前步骤需要的规范与任务文件。
4. 不要代替用户批准实现，也不要跳过检查。''';

const String _finishInstructions = '''
收尾当前 Trellis 任务：

1. 先确认本轮代码已经提交；未提交时提示用户回到 3.4。
2. 归档当前任务：`python ./.trellis/scripts/task.py archive <任务名>`。
3. 记录会话日志：`python ./.trellis/scripts/add_session.py`。
4. 不要在这里提交代码，也不要改写别人的工作树。
5. 命令失败时如实报告，不编造执行结果。''';

/// 找出输入开头的 Trellis 命令；不是命令时返回 null。
TrellisSlashCommand? matchTrellisSlashCommand(String input) {
  final trimmed = input.trimLeft();
  for (final command in kTrellisSlashCommands) {
    if (!trimmed.startsWith(command.name)) continue;
    final rest = trimmed.substring(command.name.length);
    if (rest.isEmpty || rest.startsWith(RegExp(r'\s'))) return command;
  }
  return null;
}

/// 命令之后的附加说明；没有时返回空串。
String trellisCommandArguments(TrellisSlashCommand command, String input) {
  final trimmed = input.trimLeft();
  if (!trimmed.startsWith(command.name)) return '';
  return trimmed.substring(command.name.length).trim();
}

/// 展开 Trellis 斜杠命令；不是命令或不是 Trellis 项目时返回 null。
///
/// [skills] 是当前会话可见的技能；同名技能优先，正文按需读盘。
Future<String?> routeTrellisSlashCommand(
  String input, {
  required String projectRoot,
  required List<VibeSkill> skills,
  int maxChars = kTrellisCommandMaxChars,
}) async {
  final command = matchTrellisSlashCommand(input);
  if (command == null) return null;
  if (!TrellisProject.hasWorkflow(projectRoot)) return null;
  final extra = trellisCommandArguments(command, input);
  final body =
      await _skillBody(command, skills) ??
      _projectFile(command, projectRoot) ??
      command.instructions;
  final buffer = StringBuffer(command.name);
  if (extra.isNotEmpty) buffer.write('：$extra');
  buffer
    ..writeln()
    ..writeln()
    ..write(body.trim());
  return clampTrellisCommand(buffer.toString(), maxChars);
}

/// 按字符上限截断展开结果。
String clampTrellisCommand(
  String text, [
  int maxChars = kTrellisCommandMaxChars,
]) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}\n\n（命令内容已截断）';
}

Future<String?> _skillBody(
  TrellisSlashCommand command,
  List<VibeSkill> skills,
) async {
  for (final name in command.skillNames) {
    for (final skill in skills) {
      if (skill.name != name) continue;
      final body = await skill.resolveBody();
      if (body.trim().isNotEmpty) return body;
    }
  }
  return null;
}

String? _projectFile(TrellisSlashCommand command, String projectRoot) {
  for (final relative in command.projectPaths) {
    final file = File(p.joinAll([projectRoot, ...relative.split('/')]));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      continue;
    }
    try {
      final limit = kTrellisCommandMaxChars * 2;
      final text = file.lengthSync() <= limit
          ? file.readAsStringSync()
          : _readHead(file, limit);
      if (text.trim().isNotEmpty) return text;
    } on FileSystemException {
      continue;
    }
  }
  return null;
}

String _readHead(File file, int maxBytes) {
  final handle = file.openSync();
  try {
    return utf8.decode(handle.readSync(maxBytes), allowMalformed: true);
  } finally {
    handle.closeSync();
  }
}
