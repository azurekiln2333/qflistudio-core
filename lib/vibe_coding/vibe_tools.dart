/// 真实项目文件工具：路径约束、读取、创建、覆盖、替换、备份和并发冲突检测。
///
/// 所有路径都相对项目根目录，结果只在本机文件系统上产生。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/file_service.dart';
import '../services/project_file_access.dart';

/// 工具失败原因；[code] 供控制器映射为工具错误或冲突。
class VibeToolException implements Exception {
  const VibeToolException(this.message, {this.code = 'error'});

  final String message;
  final String code;

  bool get isConflict => code == 'conflict';

  @override
  String toString() => message;
}

class VibeWriteResult {
  const VibeWriteResult({
    required this.relativePath,
    required this.bytes,
    required this.created,
    this.backupPath,
  });

  final String relativePath;
  final int bytes;
  final bool created;

  /// 覆盖前的备份绝对路径；新建文件为 null。
  final String? backupPath;
}

/// 一条文本搜索结果。
class VibeSearchMatch {
  const VibeSearchMatch({
    required this.path,
    required this.line,
    required this.text,
  });

  /// 相对项目根的路径，分隔符统一为 `/`。
  final String path;

  /// 行号，从 1 起。
  final int line;

  /// 命中的整行内容，已去除首尾空白并截断。
  final String text;
}

/// 覆盖前的应用级版本历史备份。返回空串或 null 表示成功，返回文本表示原因；
/// 失败不阻塞写入，与用户手动保存的行为一致。
typedef VibeHistoryBackup = Future<String?> Function(File file);

/// 项目内文件访问。一个会话共用一个实例，以便记录已读内容。
class VibeProjectFiles {
  VibeProjectFiles({
    required String projectRoot,
    this.maxReadBytes = 256 * 1024,
    this.maxWriteBytes = 256 * 1024,
    this.maxListEntries = 400,
    bool Function(String absolutePath)? shouldWrite,
  }) : projectRoot = p.normalize(p.absolute(projectRoot)),
       _shouldWrite = shouldWrite;

  /// 落入最终提交点的编辑器保护：返回 false 时拒绝覆盖。
  ///
  /// 在路径锁内、冲突复查和备份之后、真正写盘之前调用。
  /// 会话层用 [addWriteGuard] 再叠一层路径租约。
  bool Function(String absolutePath)? _shouldWrite;

  bool Function(String absolutePath)? get shouldWrite => _shouldWrite;

  /// 覆盖前的版本历史备份；为 null 时只留项目内 `.qfli/vibe-backups`。
  ///
  /// 编辑器集成把它接到用户手动保存同一条路径（[VibeHistoryBackup] 的实现
  /// 是 `FileBackup.backupBeforeOverwrite`），这样 agent 的写入也会出现在
  /// 文件历史里，和用户自己的保存一样能回滚。
  VibeHistoryBackup? historyBackup;

  /// 叠加一条写盘保护；多条按「全部通过才放行」组合。
  ///
  /// 会话层用它把路径租约接到既有的 `shouldWrite` 钩子上，
  /// 不改变编辑器原有的脏缓冲保护。
  void addWriteGuard(bool Function(String absolutePath) guard) {
    final previous = _shouldWrite;
    _shouldWrite = previous == null
        ? guard
        : (path) => previous(path) && guard(path);
  }

  final String projectRoot;
  final int maxReadBytes;
  final int maxWriteBytes;
  final int maxListEntries;

  /// 单次搜索最多返回的条数，模型可用参数调小。
  static const int maxSearchResults = 200;
  static const int defaultMaxSearchResults = 50;

  /// 单次搜索最多扫描的文件数，避免大仓库卡住一轮。
  static const int maxSearchFiles = 400;

  /// 搜索词长度上限与单行展示上限。
  static const int maxSearchPatternChars = 200;
  static const int maxSearchLineChars = 240;

  static const String backupDirName = 'vibe-backups';
  static const Set<String> _protectedSegments = {'.qfli', '.git'};
  static const Set<String> _excludedDirs = {
    'node_modules',
    'build',
    'target',
    'vendor',
    '__pycache__',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.qfli',
    '.git',
  };

  static bool _isProtected(String segment) =>
      _protectedSegments.contains(segment.toLowerCase());

  /// 归一化后的路径是否指项目根目录（`.` 或空串）。
  static bool isProjectRootPath(String rawPath) {
    final normalized = rawPath.replaceAll('\\', '/').trim();
    return normalized.isEmpty || normalized == '.' || normalized == './';
  }

  static bool _isExcluded(String name) =>
      _excludedDirs.contains(name.toLowerCase());

  /// 读取白名单里的项目外附件上限，避免一次附加几百个路径。
  static const int maxReadOnlyFiles = 64;

  final Map<String, String> _knownContent = {};

  /// 本会话可读的项目外附件（规范化绝对路径）。
  ///
  /// 只影响 [read]：写入、编辑、列目录、搜索仍然只能落在项目根内。
  final Set<String> _readOnlyFiles = {};

  /// 已登记的可读附件。
  Set<String> get readOnlyFiles => Set.unmodifiable(_readOnlyFiles);

  /// 登记一批只读附件（工作区里其他项目的文件）。
  ///
  /// 路径必须能规范化为绝对路径；项目内路径不需要登记。无效条目直接跳过，
  /// 不报错——选择器给出的路径里混一个不可用的，不该拦住整次发送。
  void allowReadOnlyFiles(Iterable<String> paths) {
    for (final raw in paths) {
      if (_readOnlyFiles.length >= maxReadOnlyFiles) return;
      final normalized = _normalizeReadOnlyPath(raw);
      if (normalized != null) _readOnlyFiles.add(normalized);
    }
  }

  String? _normalizeReadOnlyPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains('\u0000')) return null;
    if (!p.isAbsolute(trimmed)) return null;
    final normalized = p.normalize(trimmed);
    // 项目内的文件走原有相对路径约束即可，不进白名单。
    if (p.equals(normalized, projectRoot) ||
        p.isWithin(projectRoot, normalized)) {
      return null;
    }
    return normalized;
  }

  /// 白名单命中时返回可读的绝对路径；未命中返回 null。
  ///
  /// 命中后仍要重新校验：必须是普通文件、不能是符号链接，也不能经由链接
  /// 逃到别处。登记到读取之间文件可能被换掉，所以校验放在读取时。
  String? _readOnlyTarget(String rawPath) {
    if (_readOnlyFiles.isEmpty) return null;
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed.contains('\u0000')) return null;
    if (!p.isAbsolute(trimmed)) return null;
    final candidate = p.normalize(trimmed);
    if (!_readOnlyFiles.contains(candidate)) return null;
    final type = FileSystemEntity.typeSync(candidate, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const VibeToolException('文件不存在', code: 'not_found');
    }
    if (type != FileSystemEntityType.file) {
      throw const VibeToolException('附件必须是普通文件，不允许目录或链接', code: 'escape');
    }
    final String real;
    try {
      real = File(candidate).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw const VibeToolException('无法解析附件路径', code: 'escape');
    }
    if (!p.equals(real, candidate)) {
      throw const VibeToolException('附件路径包含符号链接，已拒绝', code: 'escape');
    }
    return candidate;
  }

  /// 读取时的实际路径：项目内走原有约束，项目外只接受白名单附件。
  String _readablePath(String rawPath) =>
      _readOnlyTarget(rawPath) ?? resolve(rawPath);

  /// 读取路径的展示名：项目内用相对路径，白名单附件用绝对路径。
  ///
  /// 先读成功再调，避免未验证的路径被当成可读。
  String displayPathForRead(String rawPath) {
    final raw = rawPath.trim();
    if (p.isAbsolute(raw) && _readOnlyFiles.contains(p.normalize(raw))) {
      return p.normalize(raw).replaceAll('\\', '/');
    }
    return relative(resolve(rawPath));
  }

  /// 跨实例的写入队列，按物理路径串行化。
  static final Map<String, Future<void>> _pathQueues = {};

  String? _realRoot;

  /// 已登记的外部根（文件夹授权打开的项目）。
  ///
  /// 外部根的目录确实不在 [projectRoot] 之下，但它就是这次会话的工作根：
  /// 列表、读取、写入都应落在它里面。没有这一条时，外部项目下的
  /// `src/main.dart` 会被拼成项目内的路径，读取走到普通文件分支，
  /// 协调读取永远不触发（iCloud 占位文件因此读不到）。
  ///
  /// 只有字符串相等或是它的子路径才放行，`..` 段在前面已经拒掉。
  String? _externalRoot(String normalized) {
    if (!ProjectFileAccess.isExternal(projectRoot)) return null;
    final root = projectRoot.replaceAll('\\', '/');
    if (normalized == root) return projectRoot;
    if (!normalized.startsWith('$root/')) return null;
    return p.normalize(
      p.join(projectRoot, normalized.substring(root.length + 1)),
    );
  }

  String get realRoot =>
      _realRoot ??= Directory(projectRoot).resolveSymbolicLinksSync();

  /// 把工具参数里的相对路径转换成受约束的绝对路径。
  ///
  /// 拒绝绝对路径、盘符、`..`、NUL、受保护目录和符号链接逃逸。
  /// 项目根之外还有两个允许的落点：已登记的外部根（文件夹授权打开的项目）
  /// 与只读附件。两个都按绝对路径拼，后续的 `isExternal` 与写入拦截
  /// 才能在同一个口径上认出它们。
  String resolve(String rawPath) {
    if (rawPath.contains('\u0000')) {
      throw const VibeToolException('路径包含非法字符', code: 'escape');
    }
    final normalized = rawPath.replaceAll('\\', '/').trim();
    // 约定：`.` 与空串都表示项目根目录，列表工具靠它们就地看根。
    if (isProjectRootPath(normalized)) return projectRoot;
    if (normalized.isEmpty) {
      throw const VibeToolException('路径不能为空');
    }
    final external = _externalRoot(normalized);
    if (external != null) return external;
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw const VibeToolException('只允许项目内的相对路径', code: 'escape');
    }
    final segments = normalized.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw const VibeToolException('路径不能包含 . 或 ..', code: 'escape');
      }
      if (segment.contains('\u0000')) {
        throw const VibeToolException('路径包含非法字符', code: 'escape');
      }
    }
    if (_isProtected(segments.first)) {
      throw const VibeToolException('不能读写项目元数据目录', code: 'protected');
    }
    final absolute = p.normalize(p.joinAll([projectRoot, ...segments]));
    if (!p.equals(absolute, projectRoot) &&
        !p.isWithin(projectRoot, absolute)) {
      throw const VibeToolException('路径超出项目目录', code: 'escape');
    }
    _requireNoLinkEscape(absolute);
    return absolute;
  }

  String relative(String absolutePath) =>
      p.relative(absolutePath, from: projectRoot).replaceAll('\\', '/');

  /// 逐级检查已存在的路径段，拒绝符号链接和穿越。
  void _requireNoLinkEscape(String absolute) {
    final root = p.normalize(projectRoot);
    final relativeParts = p.split(p.relative(absolute, from: root));
    var cursor = root;
    for (final part in relativeParts) {
      if (part == '.' || part.isEmpty) continue;
      cursor = p.join(cursor, part);
      final type = FileSystemEntity.typeSync(cursor, followLinks: false);
      if (type == FileSystemEntityType.notFound) break;
      if (type == FileSystemEntityType.link) {
        throw const VibeToolException('路径包含符号链接，已拒绝', code: 'escape');
      }
    }
    // 已存在的最近祖先还要落在根目录的真实路径内。
    var ancestor = absolute;
    while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(ancestor);
      if (p.equals(parent, ancestor)) break;
      ancestor = parent;
    }
    if (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw const VibeToolException('项目目录不存在', code: 'not_found');
    }
    final ancestorType = FileSystemEntity.typeSync(
      ancestor,
      followLinks: false,
    );
    final real = ancestorType == FileSystemEntityType.directory
        ? Directory(ancestor).resolveSymbolicLinksSync()
        : File(ancestor).resolveSymbolicLinksSync();
    if (!p.equals(real, realRoot) && !p.isWithin(realRoot, real)) {
      throw const VibeToolException('路径超出项目目录', code: 'escape');
    }
  }

  /// 文件字节数。占位文件尚未下载，`length` 不可用，按 0 计。
  static Future<int> _fileLength(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  /// 列目录；默认只列一层，跳过隐藏项和依赖/构建目录。
  Future<List<Map<String, Object?>>> list({
    String? path,
    bool recursive = false,
  }) async {
    final start = path == null || isProjectRootPath(path)
        ? projectRoot
        : resolve(path);
    final type = FileSystemEntity.typeSync(start);
    if (type == FileSystemEntityType.notFound) {
      throw const VibeToolException('目录不存在', code: 'not_found');
    }
    if (type != FileSystemEntityType.directory) {
      throw const VibeToolException('目标不是目录');
    }
    final entries = <Map<String, Object?>>[];
    Future<void> walk(Directory directory) async {
      // 外部根走协调列目录：iCloud 占位文件在盘上是 `.名字.icloud`，
      // 直接 `list` 会把它当成隐藏项跳过，用户看到的是空目录。
      final children = ProjectFileAccess.isExternal(directory.path)
          ? await FileService.listSorted(directory.path)
          : await directory.list(followLinks: false).toList();
      children.sort((a, b) {
        final rank = (a is Directory ? 0 : 1) - (b is Directory ? 0 : 1);
        return rank != 0
            ? rank
            : p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase());
      });
      for (final entity in children) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Link) continue;
        if (entity is Directory) {
          if (_isExcluded(name)) continue;
          entries.add({'path': relative(entity.path), 'type': 'directory'});
          if (entries.length > maxListEntries) {
            throw const VibeToolException('目录条目过多，请缩小路径范围', code: 'too_large');
          }
          if (recursive) await walk(entity);
        } else if (entity is File) {
          entries.add({
            'path': relative(entity.path),
            'type': 'file',
            'bytes': await _fileLength(entity.path),
          });
          if (entries.length > maxListEntries) {
            throw const VibeToolException('目录条目过多，请缩小路径范围', code: 'too_large');
          }
        }
      }
    }

    await walk(Directory(start));
    return entries;
  }

  /// 在项目内搜索文本，按行返回命中的位置。
  ///
  /// 只搜目录内真实文件：跳过隐藏项、符号链接、依赖与构建目录，
  /// 不跟随链接，单个文件超过读取上限时跳过。二进制或非 UTF-8 文件
  /// 直接跳过，不让一个不可读文件拖垮整次搜索。
  Future<List<VibeSearchMatch>> searchText(
    String pattern, {
    String? path,
    int maxResults = defaultMaxSearchResults,
    bool regex = false,
    bool caseSensitive = false,
  }) async {
    final needle = pattern.trim();
    if (needle.isEmpty) {
      throw const VibeToolException('搜索内容不能为空');
    }
    if (needle.length > maxSearchPatternChars) {
      throw const VibeToolException('搜索内容过长，最多 200 字符');
    }
    final limit = maxResults <= 0
        ? defaultMaxSearchResults
        : (maxResults > maxSearchResults ? maxSearchResults : maxResults);
    final RegExp matcher;
    if (regex) {
      try {
        matcher = RegExp(needle, caseSensitive: caseSensitive);
      } on FormatException {
        throw const VibeToolException('正则表达式无效');
      }
    } else {
      matcher = RegExp(RegExp.escape(needle), caseSensitive: caseSensitive);
    }

    final start = path == null || isProjectRootPath(path)
        ? projectRoot
        : resolve(path);
    final type = FileSystemEntity.typeSync(start);
    if (type == FileSystemEntityType.notFound) {
      throw const VibeToolException('路径不存在', code: 'not_found');
    }
    final files = <File>[];
    if (type == FileSystemEntityType.file) {
      files.add(File(start));
    } else if (type == FileSystemEntityType.directory) {
      Future<void> walk(Directory directory) async {
        final children = await directory.list(followLinks: false).toList();
        children.sort((a, b) => a.path.compareTo(b.path));
        for (final entity in children) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (entity is Link) continue;
          if (entity is Directory) {
            if (_isExcluded(name)) continue;
            await walk(entity);
          } else if (entity is File) {
            if (files.length >= maxSearchFiles) return;
            files.add(entity);
          }
        }
      }

      await walk(Directory(start));
    } else {
      throw const VibeToolException('目标不是文件或目录');
    }

    final matches = <VibeSearchMatch>[];
    for (final file in files) {
      if (matches.length >= limit) break;
      final int length;
      try {
        length = await file.length();
      } on FileSystemException {
        continue;
      }
      if (length > maxReadBytes) continue;
      final String text;
      try {
        text = _decodeText(await file.readAsBytes());
      } on VibeToolException {
        continue;
      } on FileSystemException {
        continue;
      }
      final lines = text.split('\n');
      for (var index = 0; index < lines.length; index++) {
        if (matches.length >= limit) break;
        final line = lines[index];
        if (!matcher.hasMatch(line)) continue;
        matches.add(
          VibeSearchMatch(
            path: relative(file.path),
            line: index + 1,
            text: _shortLine(line),
          ),
        );
      }
    }
    return matches;
  }

  static String _shortLine(String line) {
    final flat = line.replaceAll('\r', '').trimRight();
    return flat.length <= maxSearchLineChars
        ? flat
        : '${flat.substring(0, maxSearchLineChars)}…';
  }

  /// 读取文本文件并记录内容，后续写入据此检测并发变化。
  Future<String> read(String path) async {
    final absolute = _readablePath(path);
    final file = File(absolute);
    final external = ProjectFileAccess.isExternal(absolute);
    if (!external) {
      if (!await file.exists()) {
        throw const VibeToolException('文件不存在', code: 'not_found');
      }
      final length = await file.length();
      if (length > maxReadBytes) {
        throw VibeToolException(
          '文件超过 ${maxReadBytes ~/ 1024} KiB，无法读取',
          code: 'too_large',
        );
      }
    }
    // 外部根走协调读取：iCloud 占位先下载，`exists` 在下载前会报假。
    final bytes = await ProjectFileAccess.readBytes(absolute);
    if (bytes.length > maxReadBytes) {
      throw VibeToolException(
        '文件超过 ${maxReadBytes ~/ 1024} KiB，无法读取',
        code: 'too_large',
      );
    }
    final text = _decodeText(bytes);
    _knownContent[absolute] = text;
    return text;
  }

  /// 严格 UTF-8 文本策略：二进制或非 UTF-8 文件不允许读取或覆盖。
  /// 宽松解码后回写会破坏原字节，因此这里直接拒绝。
  static String _decodeText(List<int> bytes) {
    if (bytes.contains(0)) {
      throw const VibeToolException('文件包含 NUL 字节，按二进制文件拒绝', code: 'binary');
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const VibeToolException('文件不是 UTF-8 文本，工具拒绝读取或覆盖', code: 'binary');
    }
  }

  /// 创建或覆盖文件。已存在的文件必须先读取，且磁盘内容不能变化。
  ///
  /// 同一物理路径的写入跨实例串行化；真正写盘前在锁内复查磁盘内容和
  /// [shouldWrite]。
  Future<VibeWriteResult> write(
    String path,
    String content, {
    bool createOnly = false,
  }) async {
    if (utf8.encode(content).length > maxWriteBytes) {
      throw VibeToolException(
        '写入内容超过 ${maxWriteBytes ~/ 1024} KiB',
        code: 'too_large',
      );
    }
    if (content.contains('\u0000')) {
      throw const VibeToolException('写入内容不能包含 NUL 字节', code: 'binary');
    }
    final absolute = resolve(path);
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      throw const VibeToolException('目标是目录，不能写入文件');
    }
    if (type == FileSystemEntityType.file && createOnly) {
      throw const VibeToolException('文件已存在，未覆盖', code: 'exists');
    }
    return _withPathQueue(
      _physical(absolute),
      () => _commitWrite(path, content, createOnly: createOnly),
    );
  }

  /// 物理队列键：真实根 + 相对路径，别名根不会落到不同队列。
  String _physical(String absolute) {
    final relativePath = p.relative(absolute, from: projectRoot);
    return p.normalize(p.join(realRoot, relativePath));
  }

  Future<VibeWriteResult> _commitWrite(
    String path,
    String content, {
    required bool createOnly,
  }) async {
    // 出队后重新校验路径：排队期间父目录可能被换成链接。
    final absolute = resolve(path);
    final file = File(absolute);
    final relativePath = relative(absolute);
    await file.parent.create(recursive: true);
    final exists =
        FileSystemEntity.typeSync(absolute, followLinks: false) ==
        FileSystemEntityType.file;

    if (createOnly) {
      if (exists) {
        throw const VibeToolException('文件已存在，未覆盖', code: 'exists');
      }
      // 创建前保护：拒绝时不会留下空文件。
      if (shouldWrite?.call(absolute) == false) {
        throw const VibeToolException('编辑器中有未保存的修改，已拒绝覆盖', code: 'conflict');
      }
      try {
        // 原子独占创建：并发创建只有一个赢家。
        await file.create(exclusive: true);
      } on FileSystemException {
        throw const VibeToolException('文件已存在，未覆盖', code: 'exists');
      }
      await ProjectFileAccess.writeBytes(absolute, utf8.encode(content));
      _knownContent[absolute] = content;
      return VibeWriteResult(
        relativePath: relativePath,
        bytes: utf8.encode(content).length,
        created: true,
      );
    }

    String? backup;
    if (exists) {
      final known = _knownContent[absolute];
      if (known == null) {
        throw const VibeToolException('写入已有文件前请先 read_file', code: 'not_read');
      }
      // 锁内、真正写盘前复查磁盘内容。
      final current = _decodeText(await ProjectFileAccess.readBytes(absolute));
      if (current != known) {
        throw const VibeToolException('文件已在会话外被修改，已拒绝覆盖', code: 'conflict');
      }
      // 外部根不建 `.qfli` 备份；应用级历史备份仍然跑。
      if (!ProjectFileAccess.isExternal(absolute)) {
        backup = await _backup(absolute);
        if (backup == null) {
          throw const VibeToolException('备份失败，已取消写入', code: 'backup');
        }
      }
      // 应用级版本历史与用户手动保存同一条路径。备份的是覆盖前的磁盘内容，
      // 所以必须在真正写盘之前调用；失败不阻塞写入。
      try {
        await historyBackup?.call(file);
      } on Object {
        // 历史备份失败不影响本次写入。
      }
      // 备份也是 await：写盘前再对一次磁盘版本。
      final latest = _decodeText(await ProjectFileAccess.readBytes(absolute));
      if (latest != known) {
        throw const VibeToolException('文件在备份期间被修改，已拒绝覆盖', code: 'conflict');
      }
    }
    // 最终提交点再问一次编辑器，覆盖备份读取期间的脏缓冲变化。
    if (shouldWrite?.call(absolute) == false) {
      throw const VibeToolException('编辑器中有未保存的修改，已拒绝覆盖', code: 'conflict');
    }
    await ProjectFileAccess.writeBytes(absolute, utf8.encode(content));
    _knownContent[absolute] = content;
    return VibeWriteResult(
      relativePath: relativePath,
      bytes: utf8.encode(content).length,
      created: !exists,
      backupPath: backup,
    );
  }

  /// 写入 AI 生成标识的说明文件（无注释语法的类型）。
  ///
  /// 说明文件与正文同目录、同名加 `.ai-generated`。
  /// 路径仍走同样的越界检查，写失败不推翻已成功的正文写入。
  Future<String?> writeAiMarkSidecar({
    required String path,
    required String content,
  }) async {
    final absolute = resolve(path);
    final file = File(absolute);
    try {
      await file.parent.create(recursive: true);
      await ProjectFileAccess.writeBytes(absolute, utf8.encode(content));
    } on FileSystemException {
      return null;
    }
    return relative(absolute);
  }

  /// 同一物理路径串行执行；键在 Windows 上不区分大小写。
  static Future<T> _withPathQueue<T>(
    String absolute,
    Future<T> Function() action,
  ) async {
    final key = Platform.isWindows ? absolute.toLowerCase() : absolute;
    final previous = _pathQueues[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _pathQueues[key] = gate.future;
    try {
      await previous;
      return await action();
    } finally {
      gate.complete();
      if (identical(_pathQueues[key], gate.future)) {
        _pathQueues.remove(key);
      }
    }
  }

  /// 精确替换一处文本；[replaceAll] 为 false 时多处匹配会失败。
  Future<VibeWriteResult> edit(
    String path,
    String oldText,
    String newText, {
    bool replaceAll = false,
  }) async {
    if (oldText.isEmpty) {
      throw const VibeToolException('oldText 不能为空');
    }
    final absolute = resolve(path);
    final known = _knownContent[absolute];
    if (known == null) {
      throw const VibeToolException('修改已有文件前请先 read_file', code: 'not_read');
    }
    final file = File(absolute);
    if (!await file.exists()) {
      throw const VibeToolException('文件不存在', code: 'not_found');
    }
    final current = _decodeText(await file.readAsBytes());
    if (current != known) {
      throw const VibeToolException('文件已在会话外被修改，已拒绝编辑', code: 'conflict');
    }
    final first = current.indexOf(oldText);
    if (first < 0) {
      throw const VibeToolException('未找到 oldText', code: 'no_match');
    }
    if (!replaceAll && current.indexOf(oldText, first + oldText.length) >= 0) {
      throw const VibeToolException(
        'oldText 匹配多处，请提供更长的唯一片段',
        code: 'ambiguous',
      );
    }
    final updated = replaceAll
        ? current.replaceAll(oldText, newText)
        : current.replaceRange(first, first + oldText.length, newText);
    return write(path, updated);
  }

  /// 覆盖前把当前磁盘内容复制到项目内备份目录。
  ///
  /// 外部根不写 `.qfli`，所以不在这里建备份；调用方已跳过该分支。
  Future<String?> _backup(String absolute) async {
    if (ProjectFileAccess.isExternal(absolute)) return null;
    try {
      final stamp = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final label =
          '${stamp.year}${two(stamp.month)}${two(stamp.day)}'
          '-${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}'
          '-${stamp.millisecond.toString().padLeft(3, '0')}';
      final flat = relative(absolute).replaceAll('/', '__');
      final dir = Directory(p.join(projectRoot, '.qfli', backupDirName));
      // 备份目录本身也不能通过链接逃出项目。
      _requireNoLinkEscape(dir.path);
      await dir.create(recursive: true);
      final realDir = dir.resolveSymbolicLinksSync();
      if (!p.equals(realDir, realRoot) && !p.isWithin(realRoot, realDir)) {
        return null;
      }
      var target = p.join(dir.path, '$label-$flat');
      var index = 1;
      while (FileSystemEntity.typeSync(target, followLinks: false) !=
              FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync('$target.json', followLinks: false) !=
              FileSystemEntityType.notFound) {
        if (++index > 1000) return null;
        target = p.join(dir.path, '$label-$flat-$index');
      }
      // 创建后被替换成链接时，父目录真实路径会变化。
      final realParent = Directory(
        p.dirname(target),
      ).resolveSymbolicLinksSync();
      if (!p.equals(realParent, realDir)) return null;
      await File(absolute).copy(target);
      await File('$target.json').writeAsString(
        jsonEncode({
          'path': relative(absolute),
          'time': stamp.toIso8601String(),
        }),
        flush: true,
      );
      return target;
    } catch (_) {
      return null;
    }
  }
}

/// 新建项目快照：最多 64 个文件、合计 256 KiB 解码数据，不跟随符号链接。
abstract final class VibeProjectSnapshot {
  static const int maxFiles = 64;
  static const int maxBytes = 256 * 1024;
  static const Set<String> excludedDirs = {
    'node_modules',
    'build',
    'target',
    'vendor',
    '__pycache__',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.qfli',
    '.git',
  };

  static bool _isExcluded(String name) =>
      excludedDirs.contains(name.toLowerCase());

  static Future<List<Map<String, String>>> collect(String projectRoot) async {
    final files = <Map<String, String>>[];
    var bytes = 0;
    Future<void> walk(Directory directory) async {
      final children = await directory.list(followLinks: false).toList();
      for (final entity in children) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Link) continue;
        if (entity is Directory) {
          if (_isExcluded(name)) continue;
          await walk(entity);
        } else if (entity is File) {
          if (files.length >= maxFiles) {
            throw const VibeToolException(
              '项目超过 64 个文件，在线运行只支持小型项目',
              code: 'too_large',
            );
          }
          final content = <int>[];
          await for (final chunk in entity.openRead()) {
            bytes += chunk.length;
            if (bytes > maxBytes) {
              throw const VibeToolException(
                '项目副本超过 256 KiB，无法上传终端',
                code: 'too_large',
              );
            }
            content.addAll(chunk);
          }
          files.add({
            'path': p
                .relative(entity.path, from: projectRoot)
                .replaceAll('\\', '/'),
            'content': base64Encode(content),
          });
        }
      }
    }

    await walk(Directory(projectRoot));
    return files;
  }
}

/// OpenAI 兼容的工具定义；服务端只接受这些字段。
List<Map<String, dynamic>> vibeToolSpecs() => [
  {
    'type': 'function',
    'function': {
      'name': 'list_files',
      'description': '列出项目目录。路径相对项目根目录，默认只列一层。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '目录相对路径，省略表示根目录'},
          'recursive': {'type': 'boolean', 'description': '是否递归列出，默认 false'},
        },
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'read_file',
      'description': '读取项目内文本文件。覆盖已有文件前必须先读取。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '文件相对路径'},
        },
        'required': ['path'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'search_text',
      'description': '在项目文本文件里搜索内容，返回 路径:行号: 内容。不区分大小写，可用正则。',
      'parameters': {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string', 'description': '要查找的文本或正则'},
          'path': {'type': 'string', 'description': '搜索范围，相对目录或文件，省略表示项目根目录'},
          'maxResults': {
            'type': 'integer',
            'description': '返回条数上限，默认 50，最大 200',
          },
          'regex': {
            'type': 'boolean',
            'description': 'pattern 是否按正则解析，默认 false',
          },
          'caseSensitive': {
            'type': 'boolean',
            'description': '是否区分大小写，默认 false',
          },
        },
        'required': ['pattern'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'write_file',
      'description': '创建文件或整体覆盖已有文件。父目录不存在时自动创建。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '文件相对路径'},
          'content': {'type': 'string', 'description': '完整文件内容'},
          'createOnly': {
            'type': 'boolean',
            'description': '为 true 时只创建，已存在则失败',
          },
        },
        'required': ['path', 'content'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'edit_file',
      'description': '把文件中的一段文本替换为新文本。oldText 必须唯一匹配。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '文件相对路径'},
          'oldText': {'type': 'string', 'description': '要替换的原文本'},
          'newText': {'type': 'string', 'description': '替换后的文本'},
          'replaceAll': {'type': 'boolean', 'description': '是否替换全部匹配，默认 false'},
        },
        'required': ['path', 'oldText', 'newText'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'run_command',
      'description': '在隔离在线终端运行命令并返回真实退出码和输出。项目会作为快照上传，无法访问本机。',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': '要执行的 shell 命令'},
        },
        'required': ['command'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'todo',
      'description': '提交或更新任务计划。每次提交完整列表，面板会实时显示进度。多步骤任务在建文件前先列计划。',
      'parameters': {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'description': '完整计划，按执行顺序；最多 20 项，最多一项 doing',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string', 'description': '条目 id，省略时按顺序生成'},
                'title': {'type': 'string', 'description': '一步可验证的动作'},
                'status': {
                  'type': 'string',
                  'enum': ['pending', 'doing', 'done'],
                  'description': '条目状态，默认 pending',
                },
              },
              'required': ['title'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['items'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'use_skill',
      'description': '读取一个技能的完整步骤。系统提示里只有技能名称和描述，需要细节时调用本工具。',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '技能名称，必须来自技能索引'},
        },
        'required': ['name'],
        'additionalProperties': false,
      },
    },
  },
];
