/// 网页验收：解析生成的项目，检查引用是否真实存在。
///
/// 不用外部依赖：只做验收需要的三件事——标签能否闭合、`link`/`script`
/// 指向的文件是否存在、页面是否至少有可运行的脚本。检查的是磁盘上的
/// 真实文件，不看模型的自述。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 一次 HTML 检查的结论。`problems` 为空表示通过。
class VibeHtmlCheck {
  const VibeHtmlCheck({
    required this.file,
    required this.parsed,
    required this.stylesheets,
    required this.scripts,
    required this.problems,
  });

  final String file;

  /// 标签是否成对闭合（忽略 void 元素与自闭合）。
  final bool parsed;
  final List<String> stylesheets;
  final List<String> scripts;
  final List<String> problems;

  bool get ok => problems.isEmpty;

  Map<String, Object?> toJson() => {
    'file': file,
    'parsed': parsed,
    'stylesheets': stylesheets,
    'scripts': scripts,
    'problems': problems,
  };
}

const Set<String> _voidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

const Set<String> _rawTextTags = {'script', 'style'};

final RegExp _tagPattern = RegExp(
  r'<!--[\s\S]*?-->|<(/?)([a-zA-Z][a-zA-Z0-9-]*)((?:[^>"' "'" r']|"[^"]*"|' "'" r"[^']*')*)>",
);

final RegExp _attrPattern = RegExp(
  r'([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|' "'" r"'([^']*)'" r')',
);

/// 检查 [relative] 指向的 HTML 及其引用。
///
/// [projectRoot] 是项目根目录；引用按 HTML 所在目录解析，并用项目根目录做
/// 越界检查，防止 `../..` 指向项目外。
VibeHtmlCheck checkVibeHtml(String projectRoot, String relative) {
  final root = p.normalize(p.absolute(projectRoot));
  final file = File(p.join(root, relative));
  final problems = <String>[];
  if (!file.existsSync()) {
    return VibeHtmlCheck(
      file: relative,
      parsed: false,
      stylesheets: const [],
      scripts: const [],
      problems: ['缺少 $relative'],
    );
  }
  final html = file.readAsStringSync();
  if (html.trim().isEmpty) {
    return VibeHtmlCheck(
      file: relative,
      parsed: false,
      stylesheets: const [],
      scripts: const [],
      problems: ['$relative 是空文件'],
    );
  }

  final stack = <String>[];
  final stylesheets = <String>[];
  final scripts = <String>[];
  var sawClosingHtml = false;
  for (final match in _tagPattern.allMatches(html)) {
    if (match.group(0)!.startsWith('<!--')) continue;
    final closing = match.group(1) == '/';
    final name = match.group(2)!.toLowerCase();
    final attrs = match.group(3) ?? '';
    final selfClosing = attrs.trimRight().endsWith('/');

    if (closing) {
      if (name == 'html') sawClosingHtml = true;
      if (stack.isEmpty) {
        problems.add('额外的结束标签 </$name>');
        continue;
      }
      if (stack.last != name) {
        problems.add('标签未正确闭合：<$name> 遇到 </$name>（栈顶 <${stack.last}>）');
        // 尽量恢复：把同名标签之前的都弹掉。
        final index = stack.lastIndexOf(name);
        if (index >= 0) stack.removeRange(index, stack.length);
        continue;
      }
      stack.removeLast();
      continue;
    }

    if (name == 'link' || name == 'script') {
      final attrsMap = _attributes(attrs);
      final rel = attrsMap['rel']?.toLowerCase() ?? '';
      if (name == 'link' && rel.split(RegExp(r'\s+')).contains('stylesheet')) {
        final href = attrsMap['href'];
        if (href == null || href.trim().isEmpty) {
          problems.add('<link rel=stylesheet> 缺少 href');
        } else if (!_isExternal(href)) {
          stylesheets.add(href.trim());
        }
      }
      if (name == 'script') {
        final src = attrsMap['src'];
        if (src != null && src.trim().isNotEmpty && !_isExternal(src)) {
          scripts.add(src.trim());
        }
      }
    }

    if (_voidTags.contains(name) || selfClosing) continue;
    if (_rawTextTags.contains(name)) {
      // script/style 的内容不是标签，找下一个对应结束标签。
      stack.add(name);
      continue;
    }
    stack.add(name);
  }

  if (stack.isNotEmpty) {
    problems.add('未闭合的标签：${stack.map((tag) => '<$tag>').join(' ')}');
  }
  if (!sawClosingHtml) problems.add('缺少 </html>');
  if (stylesheets.isEmpty) problems.add('没有引用样式表');
  if (scripts.isEmpty) problems.add('没有引用脚本');

  for (final reference in [...stylesheets, ...scripts]) {
    final resolved = _resolve(root, p.dirname(relative), reference);
    if (resolved == null) {
      problems.add('引用越出项目目录：$reference');
      continue;
    }
    final target = File(resolved);
    if (!target.existsSync()) {
      problems.add('引用文件不存在：$reference');
    } else if (target.lengthSync() == 0) {
      problems.add('引用文件为空：$reference');
    }
  }

  return VibeHtmlCheck(
    file: relative,
    parsed: stack.isEmpty && sawClosingHtml,
    stylesheets: stylesheets,
    scripts: scripts,
    problems: problems,
  );
}

bool _isExternal(String reference) {
  final value = reference.trim().toLowerCase();
  return value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('//') ||
      value.startsWith('data:');
}

String? _resolve(String root, String baseDir, String reference) {
  final cleaned = reference.split('?').first.split('#').first;
  final joined = p.normalize(p.join(root, baseDir, cleaned));
  if (!p.isWithin(root, joined)) return null;
  return joined;
}

Map<String, String> _attributes(String raw) {
  final result = <String, String>{};
  for (final match in _attrPattern.allMatches(raw)) {
    final value = match.group(2) ?? match.group(3) ?? '';
    result[match.group(1)!.toLowerCase()] = value;
  }
  return result;
}

/// 页面里是否含可交互的脚本逻辑（新增/删除之类）。
bool vibeHtmlHasScriptLogic(String html) {
  final lower = html.toLowerCase();
  return lower.contains('addeventlistener') ||
      lower.contains('onclick') ||
      lower.contains('function') ||
      lower.contains('=>') ||
      lower.contains('const ') ||
      lower.contains('let ');
}
