/// 项目规则加载：把仓库里的约定文本并入系统提示。
///
/// 来源按优先级读取：`AGENTS.md`、`CLAUDE.md`、`.qfli/rules.md`。每个文件
/// 与整体都有字符上限，超出时按行截断并标注。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 单个规则文件的上限（字符）。
const int kVibeMaxRuleFileChars = 4 * 1024;

/// 全部规则的上限（字符）。
const int kVibeMaxRulesChars = 8 * 1024;

/// 规则来源顺序。
const List<String> kVibeRuleFiles = [
  'AGENTS.md',
  'CLAUDE.md',
  '.qfli/rules.md',
];

/// 读取项目规则；没有规则时返回空串。
///
/// 只读项目根目录下的普通文件。符号链接整份跳过，避免读出项目外内容。
String loadVibeRules(String projectRoot) {
  final sections = <String>[];
  var used = 0;
  for (final relative in kVibeRuleFiles) {
    final file = File(p.joinAll([projectRoot, ...relative.split('/')]));
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) continue;
    final String text;
    try {
      text = _readHead(file);
    } on FileSystemException {
      continue;
    }
    final trimmed = clampVibeText(text, kVibeMaxRuleFileChars);
    if (trimmed.trim().isEmpty) continue;
    final header = '### $relative';
    final budget = kVibeMaxRulesChars - used;
    if (budget <= header.length + 32) {
      sections.add('（其余规则文件已达上限，未加载）');
      break;
    }
    final room = budget - header.length - '（规则已截断）'.length - 2;
    final body = trimmed.length <= room
        ? trimmed
        : '${clampVibeText(trimmed, room)}\n（规则已截断）';
    sections.add('$header\n${body.trimRight()}');
    used += body.length + header.length + 2;
  }
  return sections.join('\n\n');
}

/// 只读取文件开头，避免加载超大规则文件。
String _readHead(File file) {
  final limit = kVibeMaxRuleFileChars * 2;
  if (file.lengthSync() <= limit) return file.readAsStringSync();
  final handle = file.openSync();
  try {
    final bytes = handle.readSync(limit);
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    handle.closeSync();
  }
}

/// 按字符截断，尽量在换行处结束，避免切断句子。
String clampVibeText(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  final cut = text.substring(0, maxChars < 0 ? 0 : maxChars);
  final newline = cut.lastIndexOf('\n');
  return newline > maxChars ~/ 2 ? cut.substring(0, newline) : cut;
}
