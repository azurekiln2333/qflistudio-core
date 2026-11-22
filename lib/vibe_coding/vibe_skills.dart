/// 技能目录与现有代理生态兼容：用户目录 `~/.qfli/skills`、`~/.claude/skills`、
/// `~/.agents/skills`、`~/.pi/skills`、`~/.codex/skills`，项目内的同名目录，
/// 外加随包发布的内置技能。提示词里只放名称与描述。
///
/// 来源优先级（低 → 高）：内置 < 用户级 < 项目级。同名技能后者覆盖前者；
/// 同一来源内部则先出现者胜出。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 一个已发现的技能。[body] 可以直接持有正文，也可以留空并在 [resolveBody]
/// 时按 [bodyPath] 读盘。发现阶段只读 frontmatter，正文按需加载。
class VibeSkill {
  const VibeSkill({
    required this.name,
    required this.description,
    required this.body,
    required this.source,
    this.truncated = false,
    this.bodyPath,
  });

  final String name;
  final String description;

  /// 去掉 frontmatter 的正文；超长时保留开头并标注截断。
  ///
  /// 懒加载得到的技能这里为空串，正文由 [resolveBody] 读取。
  final String body;

  /// 来源标签：[VibeSkillSource] 的 `label`。
  final String source;
  final bool truncated;

  /// `SKILL.md` 的绝对路径；只有懒加载的技能才有值。
  final String? bodyPath;

  bool get isBuiltIn => source == VibeSkillSource.builtIn.label;

  /// 正文是否已随技能一起读入。
  bool get hasInlineBody => body.isNotEmpty;

  /// 去掉正文，保留元数据；正文改成按需读取。
  VibeSkill withoutBody(String path) => VibeSkill(
    name: name,
    description: description,
    body: '',
    source: source,
    bodyPath: path,
  );

  /// 取正文：已读入的直接返回，否则按需读盘。
  ///
  /// 读不到时返回空串，调用方据此报告技能不可用，不编造内容。
  Future<String> resolveBody() async {
    if (body.isNotEmpty) return body;
    final path = bodyPath;
    if (path == null) return '';
    return readVibeSkillBody(path);
  }
}

/// 技能来源，决定去重顺序与是否受项目语言过滤。
enum VibeSkillSource {
  user('用户技能'),
  projectQfli('.qfli/skills'),
  claude('.claude/skills'),
  agents('.agents/skills'),
  pi('.pi/skills'),
  codex('.codex/skills'),
  builtIn('内置技能');

  const VibeSkillSource(this.label);

  final String label;
}

/// 单个技能正文上限；超出部分丢弃并标记。
const int kVibeSkillMaxBodyChars = 12 * 1024;

/// 索引条数上限，避免技能很多时挤占上下文。
const int kVibeMaxSkillEntries = 40;

/// 索引文本上限。
const int kVibeMaxSkillIndexChars = 4 * 1024;

/// 内置技能所属语言；`*` 表示所有语言可用。
const Map<String, Set<String>> kVibeBuiltInSkillLanguages = {
  'web-app-scaffold': {'*'},
  'bug-fix-loop': {'*'},
  'project-review': {'*'},
  'web-research': {'*'},
};

/// 从 `SKILL.md` 文本解析技能；缺少描述返回 null。
///
/// frontmatter 是文件开头的 `---` 块，只读取 `name` 与 `description`。
/// 传 [bodyPath] 时，技能保留文件位置，后续可用 [VibeSkill.resolveBody] 重读。
VibeSkill? parseVibeSkill(
  String text, {
  required String fallbackName,
  required VibeSkillSource source,
  String? bodyPath,
}) {
  final normalized = text.replaceAll('\r\n', '\n');
  String? name;
  String? description;
  var body = normalized;
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    var end = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
    }
    if (end > 0) {
      final block = <String, String>{};
      String? pendingKey;
      final pendingValue = <String>[];
      void flush() {
        final key = pendingKey;
        if (key != null) {
          block[key] = pendingValue.join(' ').trim();
        }
        pendingKey = null;
        pendingValue.clear();
      }

      for (final line in lines.sublist(1, end)) {
        final trimmed = line.trimLeft();
        if (trimmed.isEmpty) continue;
        if (line.startsWith(RegExp(r'\s')) && pendingKey != null) {
          pendingValue.add(trimmed);
          continue;
        }
        flush();
        final match = RegExp(
          r'^([A-Za-z0-9_-]+)\s*:\s*(.*)$',
        ).firstMatch(trimmed);
        if (match == null) continue;
        pendingKey = match.group(1)!.toLowerCase();
        final value = match.group(2)!.trim();
        // YAML 块标量（`>-`、`|`）只表示折叠或保留换行，不是内容。
        if (!RegExp(r'^[|>][-+]?$').hasMatch(value)) {
          pendingValue.add(_unquote(value));
        }
      }
      flush();
      name = block['name'];
      description = block['description'];
      body = _bodyOf(normalized);
    }
  }
  final resolvedName = (name == null || name.trim().isEmpty)
      ? fallbackName.trim()
      : name.trim();
  final resolvedDescription = description?.trim() ?? '';
  if (resolvedName.isEmpty || resolvedDescription.isEmpty) return null;
  final trimmedBody = body.trim();
  final truncated = trimmedBody.length > kVibeSkillMaxBodyChars;
  return VibeSkill(
    name: resolvedName,
    description: _oneLine(resolvedDescription),
    body: truncated
        ? '${trimmedBody.substring(0, kVibeSkillMaxBodyChars)}\n\n（技能正文已截断）'
        : trimmedBody,
    source: source.label,
    truncated: truncated,
    bodyPath: bodyPath,
  );
}

/// 去掉开头的 frontmatter 块，返回正文；没有 frontmatter 时返回原文。
String _bodyOf(String normalized) {
  final lines = normalized.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return normalized;
  for (var index = 1; index < lines.length; index++) {
    if (lines[index].trim() == '---') {
      return lines.sublist(index + 1).join('\n');
    }
  }
  return normalized;
}

/// 读一份技能的正文；文件不存在或不可读时返回空串。
///
/// 只读开头一段，正文超过 [kVibeSkillMaxBodyChars] 时保留开头并标注截断。
Future<String> readVibeSkillBody(String path) async {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    return '';
  }
  final String text;
  try {
    text = await _readHead(File(path));
  } on FileSystemException {
    return '';
  }
  final body = _bodyOf(text.replaceAll('\r\n', '\n')).trim();
  if (body.length <= kVibeSkillMaxBodyChars) return body;
  return '${body.substring(0, kVibeSkillMaxBodyChars)}\n\n（技能正文已截断）';
}

/// 只读技能文件的开头。
///
/// UTF-8 一个字符最多 4 字节，按 4 倍上限读才能保证按字符截断时不丢内容。
Future<String> _readHead(File file) async {
  const limit = kVibeSkillMaxBodyChars * 4 + 1024;
  if (await file.length() <= limit) return file.readAsString();
  final bytes = await file
      .openRead(0, limit)
      .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  return utf8.decode(bytes, allowMalformed: true);
}

String _unquote(String value) {
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' || first == "'") && first == last) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

String _oneLine(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 技能加载器；一个会话用一个实例，内置资产只读一次。
class VibeSkillLibrary {
  VibeSkillLibrary({
    required this.projectRoot,
    this.language = '',
    AssetBundle? bundle,
    this.maxEntries = kVibeMaxSkillEntries,
    this.maxIndexChars = kVibeMaxSkillIndexChars,
    String? userSkillsDir,
    List<String>? userSkillsDirs,
    this.includeUserSkills = true,
    this.lazyBodies = false,
  }) : _bundle = bundle ?? rootBundle,
       _userSkillsDir = userSkillsDir,
       _userSkillsDirs = userSkillsDirs;

  final String projectRoot;
  final String language;
  final AssetBundle _bundle;
  final int maxEntries;
  final int maxIndexChars;

  /// 只读 frontmatter，正文留给 [VibeSkill.resolveBody]。
  ///
  /// 列表、索引这类只要名称与描述的路径传 true，避免为每个技能读全文。
  final bool lazyBodies;

  /// 显式指定的用户级技能目录；为 null 时按 [defaultUserSkillsDirs] 推算。
  final String? _userSkillsDir;

  /// 显式指定的多个用户级技能目录；优先于 [_userSkillsDir]。
  final List<String>? _userSkillsDirs;

  /// 是否读用户级目录；嵌入式或测试可关掉。
  final bool includeUserSkills;

  /// 用户级技能目录：`$HOME/.qfli/skills`。
  ///
  /// 没有 HOME（部分移动端）时返回 null，不报错也不猜路径。
  static String? defaultUserSkillsDir() {
    final home = _homeDir();
    if (home == null) return null;
    return p.join(home, '.qfli', 'skills');
  }

  /// 用户级技能目录，按优先级排列。
  ///
  /// 同一个技能名多份定义时先用 `~/.qfli/skills`，依次到 `~/.codex/skills`。
  static List<String> defaultUserSkillsDirs() {
    final home = _homeDir();
    if (home == null) return const [];
    return [
      for (final dir in userSkillDirNames) p.joinAll([home, ...dir.split('/')]),
    ];
  }

  /// 用户级技能子目录，顺序即优先级。
  static const List<String> userSkillDirNames = [
    '.qfli/skills',
    '.claude/skills',
    '.agents/skills',
    '.pi/skills',
    '.codex/skills',
  ];

  /// 项目内技能子目录，顺序即优先级。
  static const List<String> projectSkillDirNames = [
    '.qfli/skills',
    '.claude/skills',
    '.agents/skills',
    '.pi/skills',
    '.codex/skills',
  ];

  static String? _homeDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.trim().isEmpty) return null;
    return home.trim();
  }

  static const List<String> builtInAssetDirs = [
    'assets/skills/web-app-scaffold/SKILL.md',
    'assets/skills/bug-fix-loop/SKILL.md',
    'assets/skills/project-review/SKILL.md',
    'assets/skills/web-research/SKILL.md',
  ];

  static List<VibeSkill>? _builtInCache;

  /// 测试用：清空内置技能缓存。
  static void resetBuiltInCache() => _builtInCache = null;

  /// 按来源优先级发现技能。内置最低，项目级最高。
  Future<List<VibeSkill>> load() async {
    final builtIn = <String, VibeSkill>{};
    for (final skill in await _builtIns()) {
      if (!_languageAccepts(skill.name)) continue;
      builtIn.putIfAbsent(skill.name, () => skill);
    }
    final user = await _collect(_userDirs(), VibeSkillSource.user);
    final project = <String, VibeSkill>{};
    for (final dir in _projectDirs()) {
      final source = _sourceFor(dir);
      if (source == null) continue;
      for (final skill in await _readDirectory(dir, source)) {
        project.putIfAbsent(skill.name, () => skill);
      }
    }
    final merged = <String, VibeSkill>{};
    merged.addAll(builtIn);
    merged.addAll(user);
    merged.addAll(project);
    final list = merged.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list.length <= maxEntries ? list : list.sublist(0, maxEntries);
  }

  Future<Map<String, VibeSkill>> _collect(
    List<String> dirs,
    VibeSkillSource source,
  ) async {
    final found = <String, VibeSkill>{};
    for (final dir in dirs) {
      for (final skill in await _readDirectory(dir, source)) {
        found.putIfAbsent(skill.name, () => skill);
      }
    }
    return found;
  }

  List<String> _userDirs() {
    if (!includeUserSkills) return const [];
    final explicit = _userSkillsDirs;
    if (explicit != null) return explicit;
    final single = _userSkillsDir;
    if (single != null) return [single];
    return defaultUserSkillsDirs();
  }

  List<String> _projectDirs() => [
    for (final dir in projectSkillDirNames)
      p.joinAll([projectRoot, ...dir.split('/')]),
  ];

  VibeSkillSource? _sourceFor(String dir) {
    // 只认最后两段，避免项目路径里恰好出现同名目录时误判。
    final parts = p.split(p.normalize(dir));
    if (parts.length < 2 || parts.last != 'skills') return null;
    return switch (parts[parts.length - 2]) {
      '.qfli' => VibeSkillSource.projectQfli,
      '.claude' => VibeSkillSource.claude,
      '.agents' => VibeSkillSource.agents,
      '.pi' => VibeSkillSource.pi,
      '.codex' => VibeSkillSource.codex,
      _ => null,
    };
  }

  bool _languageAccepts(String name) {
    final languages = kVibeBuiltInSkillLanguages[name];
    if (languages == null || languages.contains('*')) return true;
    return languages.contains(language.toLowerCase());
  }

  Future<List<VibeSkill>> _readDirectory(
    String dir,
    VibeSkillSource source,
  ) async {
    // 技能目录是符号链接时整目录拒绝，和文件工具的策略一致。
    final type = FileSystemEntity.typeSync(dir, followLinks: false);
    if (type != FileSystemEntityType.directory) return const [];
    final skills = <VibeSkill>[];
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list(followLinks: false).toList();
    } on FileSystemException {
      // 目录存在但列不出来（权限、占用、路径过长）时只跳过这一份，
      // 不让整次技能加载失败。
      return const [];
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final file = File(p.join(entry.path, 'SKILL.md'));
      final fileType = FileSystemEntity.typeSync(file.path, followLinks: false);
      if (fileType != FileSystemEntityType.file) continue;
      try {
        final text = await _readCapped(file);
        final skill = parseVibeSkill(
          text,
          fallbackName: p.basename(entry.path),
          source: source,
          bodyPath: file.path,
        );
        if (skill == null) continue;
        skills.add(lazyBodies ? skill.withoutBody(file.path) : skill);
      } on FileSystemException {
        // 不可读的技能目录跳过，不影响其余技能。
      }
    }
    return skills;
  }

  /// 读技能文件；按 UTF-8 最坏情况预留 4 倍字节，避免多字节正文被静默截断。
  Future<String> _readCapped(File file) async {
    const limit = kVibeSkillMaxBodyChars * 4 + 1024;
    if (!lazyBodies) {
      final length = await file.length();
      if (length <= limit) return file.readAsString();
    }
    final bytes = await file
        .openRead(0, lazyBodies ? _metadataHeadBytes : limit)
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 只读 frontmatter 时读多少字节。
  static const int _metadataHeadBytes = 16 * 1024;

  Future<List<VibeSkill>> _builtIns() async {
    final cached = _builtInCache;
    if (cached != null) return cached;
    final skills = <VibeSkill>[];
    for (final asset in builtInAssetDirs) {
      try {
        final text = await _bundle.loadString(asset);
        final dirName = p.basename(p.dirname(asset));
        final skill = parseVibeSkill(
          text,
          fallbackName: dirName,
          source: VibeSkillSource.builtIn,
        );
        if (skill != null) skills.add(skill);
      } on Object {
        // 宿主 App 未声明该资产时不提供内置技能。
      }
    }
    _builtInCache = List.unmodifiable(skills);
    return _builtInCache!;
  }
}

/// 技能索引：一行一个技能，供提示词使用；超出上限时截断并标注。
String buildVibeSkillIndex(
  List<VibeSkill> skills, {
  int maxChars = kVibeMaxSkillIndexChars,
}) {
  if (skills.isEmpty) return '';
  final buffer = StringBuffer();
  for (final skill in skills) {
    final line =
        '- ${skill.name}（${skill.source}）：${_short(skill.description, 200)}';
    if (buffer.length + line.length + 1 > maxChars) {
      buffer.writeln('- …（技能索引已截断）');
      break;
    }
    buffer.writeln(line);
  }
  return buffer.toString().trimRight();
}

String _short(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max)}…';

/// 网页类交付物的关键词；用于推荐脚手架技能，不强制调用。
const Set<String> kVibeWebIntentKeywords = {
  '网站',
  '网页',
  '页面',
  '静态站点',
  'html',
  'css',
  '网站首页',
  'site',
  'website',
  'webpage',
  'landing page',
};

/// 提示词是否像网页类任务。
bool vibePromptWantsWeb(String prompt) {
  final lower = prompt.toLowerCase();
  return kVibeWebIntentKeywords.any(lower.contains);
}
