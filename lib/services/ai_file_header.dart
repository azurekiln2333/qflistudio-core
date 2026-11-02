/// AI 生成文件的标识行（整改任务书 §3-W3、§4 第 9 条）。
///
/// 规则：文件开头按语言注释语法加一行“本文件由 AI 生成”。
///
/// 几种必须特殊处理的形状：
/// - **shebang**（`#!`）必须是文件第一个字符，否则脚本不能直接执行；
///   标识行因此插在 shebang 之后，而不是第 1 行。
/// - **XML 声明**（`<?xml`）与 **编码声明**（`-*- coding:`、`# coding:`）
///   同样受“必须是第一行”或“必须在前两行”的约束，标识行也插在它们之后。
/// - **没有注释语法的类型**（`.json`、`.csv`、`.txt`、`.md` 之外的纯数据）
///   不插入任何内容：往 JSON 里塞一行注释会让文件直接解析失败，
///   改了内容却报错比不加标识更糟。调用方据此在界面提示原因。
library;

/// 标识文案。
const String kAiGeneratedFileNote = '本文件由 AI 生成';

/// 一种语言的注释写法。
class AiCommentSyntax {
  const AiCommentSyntax.line(this.prefix) : suffix = null;
  const AiCommentSyntax.block(this.prefix, this.suffix);

  /// 行注释前缀（`#`、`//`、`--` 等），或块注释起始符。
  final String prefix;

  /// 块注释结束符；行注释为 null。
  final String? suffix;

  bool get isBlock => suffix != null;

  /// 生成完整的标识行（行注释带一个空格，块注释单行闭合）。
  String get line => isBlock
      ? '$prefix $kAiGeneratedFileNote $suffix'
      : '$prefix $kAiGeneratedFileNote';
}

/// 扩展名 → 注释写法。未列出的扩展名不插入标识。
///
/// 只收录确实支持注释的类型；数据格式（json/csv/tsv/xml 除外）故意缺席。
const Map<String, AiCommentSyntax> aiCommentSyntaxByExtension = {
  // 行注释 #
  'py': AiCommentSyntax.line('#'),
  'pyw': AiCommentSyntax.line('#'),
  'sh': AiCommentSyntax.line('#'),
  'bash': AiCommentSyntax.line('#'),
  'zsh': AiCommentSyntax.line('#'),
  'rb': AiCommentSyntax.line('#'),
  'pl': AiCommentSyntax.line('#'),
  'r': AiCommentSyntax.line('#'),
  'yaml': AiCommentSyntax.line('#'),
  'yml': AiCommentSyntax.line('#'),
  'toml': AiCommentSyntax.line('#'),
  'ini': AiCommentSyntax.line('#'),
  'conf': AiCommentSyntax.line('#'),
  'properties': AiCommentSyntax.line('#'),
  'cmake': AiCommentSyntax.line('#'),
  'dockerfile': AiCommentSyntax.line('#'),
  'makefile': AiCommentSyntax.line('#'),
  'awk': AiCommentSyntax.line('#'),
  'tcl': AiCommentSyntax.line('#'),
  'nim': AiCommentSyntax.line('#'),
  'jl': AiCommentSyntax.line('#'),
  // 行注释 //
  'c': AiCommentSyntax.line('//'),
  'h': AiCommentSyntax.line('//'),
  'cc': AiCommentSyntax.line('//'),
  'cpp': AiCommentSyntax.line('//'),
  'cxx': AiCommentSyntax.line('//'),
  'hpp': AiCommentSyntax.line('//'),
  'cs': AiCommentSyntax.line('//'),
  'java': AiCommentSyntax.line('//'),
  'kt': AiCommentSyntax.line('//'),
  'kts': AiCommentSyntax.line('//'),
  'scala': AiCommentSyntax.line('//'),
  'groovy': AiCommentSyntax.line('//'),
  'dart': AiCommentSyntax.line('//'),
  'js': AiCommentSyntax.line('//'),
  'mjs': AiCommentSyntax.line('//'),
  'cjs': AiCommentSyntax.line('//'),
  'ts': AiCommentSyntax.line('//'),
  'tsx': AiCommentSyntax.line('//'),
  'jsx': AiCommentSyntax.line('//'),
  'go': AiCommentSyntax.line('//'),
  'rs': AiCommentSyntax.line('//'),
  'swift': AiCommentSyntax.line('//'),
  'm': AiCommentSyntax.line('//'),
  'mm': AiCommentSyntax.line('//'),
  'php': AiCommentSyntax.line('//'),
  'v': AiCommentSyntax.line('//'),
  'zig': AiCommentSyntax.line('//'),
  'ets': AiCommentSyntax.line('//'),
  // 行注释 --
  'sql': AiCommentSyntax.line('--'),
  'lua': AiCommentSyntax.line('--'),
  'hs': AiCommentSyntax.line('--'),
  'elm': AiCommentSyntax.line('--'),
  'ada': AiCommentSyntax.line('--'),
  // 行注释 ;（Lisp 系）与 %（TeX / Erlang / Prolog）
  'lisp': AiCommentSyntax.line(';'),
  'clj': AiCommentSyntax.line(';'),
  'scm': AiCommentSyntax.line(';'),
  'rkt': AiCommentSyntax.line(';'),
  'asm': AiCommentSyntax.line(';'),
  'tex': AiCommentSyntax.line('%'),
  'erl': AiCommentSyntax.line('%'),
  'pro': AiCommentSyntax.line('%'),
  // 行注释 "（Vim 脚本 / BASIC）
  'vim': AiCommentSyntax.line('"'),
  'bas': AiCommentSyntax.line("'"),
  // 块注释
  'css': AiCommentSyntax.block('/*', '*/'),
  'scss': AiCommentSyntax.line('//'),
  'less': AiCommentSyntax.line('//'),
  'html': AiCommentSyntax.block('<!--', '-->'),
  'htm': AiCommentSyntax.block('<!--', '-->'),
  'xml': AiCommentSyntax.block('<!--', '-->'),
  'svg': AiCommentSyntax.block('<!--', '-->'),
  'vue': AiCommentSyntax.block('<!--', '-->'),
  'svelte': AiCommentSyntax.block('<!--', '-->'),
  'md': AiCommentSyntax.block('<!--', '-->'),
  'markdown': AiCommentSyntax.block('<!--', '-->'),
};

/// 没有扩展名但按文件名识别的注释写法。
const Map<String, AiCommentSyntax> aiCommentSyntaxByFileName = {
  'dockerfile': AiCommentSyntax.line('#'),
  'makefile': AiCommentSyntax.line('#'),
  'cmakelists.txt': AiCommentSyntax.line('#'),
  '.gitignore': AiCommentSyntax.line('#'),
  '.env': AiCommentSyntax.line('#'),
  '.bashrc': AiCommentSyntax.line('#'),
  '.zshrc': AiCommentSyntax.line('#'),
};

/// 结果：[content] 是插入标识后的全文；[inserted] 为 false 时原样返回并给出 [reason]。
class AiGeneratedHeaderResult {
  const AiGeneratedHeaderResult.inserted(this.content)
    : inserted = true,
      reason = null;
  const AiGeneratedHeaderResult.skipped(this.content, this.reason)
    : inserted = false;

  final String content;
  final bool inserted;

  /// 未插入的原因，供界面提示（例如“JSON 没有注释语法”）。
  final String? reason;
}

/// 需要保持在前面的首行特征。
bool _mustStayFirst(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return false;
  return trimmed.startsWith('#!') ||
      trimmed.startsWith('<?xml') ||
      RegExp(r'^(-#-|\*-\s*coding)').hasMatch(trimmed) ||
      RegExp(r'^#.*coding[:=]').hasMatch(trimmed);
}

/// 判断某个路径是否有注释语法；返回 null 表示没有。
AiCommentSyntax? aiCommentSyntaxFor(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last.toLowerCase();
  final byName = aiCommentSyntaxByFileName[name];
  if (byName != null) return byName;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  return aiCommentSyntaxByExtension[name.substring(dot + 1)];
}

/// 给 [content] 插入 AI 标识行；已标识过的文件保持不变。
///
/// 幂等：文件里已经出现 [kAiGeneratedFileNote] 时原样返回（[inserted] 仍为 true，
/// 因为标识确实存在）。
AiGeneratedHeaderResult addAiGeneratedHeader(String path, String content) {
  final syntax = aiCommentSyntaxFor(path);
  if (syntax == null) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final extension = name.contains('.') ? name.split('.').last : name;
    return AiGeneratedHeaderResult.skipped(
      content,
      '$extension 文件没有注释语法，已按原样保存（未加 AI 标识）',
    );
  }
  if (content.contains(kAiGeneratedFileNote)) {
    return AiGeneratedHeaderResult.inserted(content);
  }
  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  final lines = content.split(RegExp(r'\r?\n'));

  // 找到第一条不该被压后的行之后的位置。
  var insertAt = 0;
  while (insertAt < lines.length && _mustStayFirst(lines[insertAt])) {
    insertAt++;
  }
  // 紧随其后的空行保留在声明之后，避免把 shebang 和代码粘在一起。
  final marker = syntax.line;
  final head = lines.sublist(0, insertAt);
  final rest = lines.sublist(insertAt);
  final buffer = StringBuffer();
  if (head.isEmpty || head.first.trim().isEmpty) {
    // 空文件或文件以空行开头：标识直接放在最前。
    buffer.write(marker);
    if (rest.isNotEmpty) buffer.write(newline);
    buffer.write(rest.join(newline));
  } else {
    buffer.write(head.join(newline));
    buffer.write(newline);
    buffer.write(marker);
    if (rest.isNotEmpty) buffer.write(newline);
    buffer.write(rest.join(newline));
  }
  return AiGeneratedHeaderResult.inserted(buffer.toString());
}

/// 完整路径版本的便捷方法，供保存前调用。
String addAiGeneratedHeaderOrOriginal(String path, String content) =>
    addAiGeneratedHeader(path, content).content;
