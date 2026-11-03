/// AI 生成文件的标识行（整改任务书 §3-W3、§4 第 9 条）。
///
/// 规则：文件开头按语言注释语法加一行“本文件由 AI 生成”。
///
/// 几种必须特殊处理的形状：
/// - **shebang**（`#!`）必须是文件第一个字符，否则脚本不能直接执行；
///   标识行因此插在 shebang 之后，而不是第 1 行。
/// - **XML 声明**（`<?xml`）与 **编码声明**（`-*- coding:`、`# coding:`）
///   同样受“必须是第一行”或“必须在前两行”的约束，标识行也插在它们之后。
/// - **没有注释语法的类型**（`.json`、`.csv`、`.txt` 等纯数据）
///   标识写进同目录的说明文件 `<文件名>.ai-generated`。
///   正文保持原样，JSON 解析器看不到注释；
///   删掉说明文件就删掉了标识，不碰数据。
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
      reason = null,
      _sidecar = null;

  const AiGeneratedHeaderResult.skipped(this.content, this.reason)
    : inserted = false,
      _sidecar = null;

  /// 标识写不进正文，改写到说明文件。
  ///
  /// [content] 是正文原文，[_sidecar] 是说明文件的内容。
  /// 调用方先写正文，再写 [sidecarContent] 到 [sidecarName]。
  const AiGeneratedHeaderResult.sidecar(this.content, String this._sidecar)
    : inserted = true,
      reason = null;

  final String content;
  final bool inserted;

  /// 未插入的原因，供界面提示。
  final String? reason;

  final String? _sidecar;

  /// 说明文件的内容；标识已写进正文时为 null。
  String? get sidecarContent => _sidecar;

  /// 标识写在正文内，还是写进说明文件。
  bool get inBody => _sidecar == null;
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

/// 说明文件的后缀：`data.json` → `data.json.ai-generated`。
const String kAiGeneratedSidecarSuffix = '.ai-generated';

/// [path] 对应的说明文件路径。
String aiGeneratedSidecarPath(String path) =>
    path.replaceAll('\\', '/') + kAiGeneratedSidecarSuffix;

/// 说明文件的内容：一行标识，一项原始路径。
String aiGeneratedSidecarContent(String path) =>
    '# $kAiGeneratedFileNote\n原始文件：${path.replaceAll('\\', '/')}\n';

/// 给 [content] 插入 AI 标识行；已标识过的文件保持不变。
///
/// 幂等：文件里已经出现 [kAiGeneratedFileNote] 时原样返回（[inserted] 仍为 true，
/// 因为标识确实存在）。
///
/// 没有注释语法的类型返回 [AiGeneratedHeaderResult.sidecar]。
/// 此时 [content] 未改，标识要写到 [aiGeneratedSidecarPath] 指定的说明文件。
AiGeneratedHeaderResult addAiGeneratedHeader(String path, String content) {
  final syntax = aiCommentSyntaxFor(path);
  if (syntax == null) {
    if (content.contains(kAiGeneratedFileNote)) {
      return AiGeneratedHeaderResult.inserted(content);
    }
    return AiGeneratedHeaderResult.sidecar(
      content,
      aiGeneratedSidecarContent(path),
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
///
/// 验证：正文总是带标识，或旁边总有说明文件。
String addAiGeneratedHeaderOrOriginal(String path, String content) =>
    addAiGeneratedHeader(path, content).content;

/// 写入标识：正文能带就写正文，否则写说明文件。
///
/// [write] 负责落盘。说明文件写失败会抛出异常，调用方要把失败告诉用户。
Future<void> applyAiGeneratedMark(
  String path,
  AiGeneratedHeaderResult marked, {
  required Future<void> Function(String target, String body) write,
}) async {
  final sidecar = marked.sidecarContent;
  if (sidecar == null) return;
  await write(aiGeneratedSidecarPath(path), sidecar);
}
