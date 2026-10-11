import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_service.dart';
import 'project_templates.dart';

/// 应用可写目录与配置文件的路径解析。
///
/// 在鸿蒙/Android 等移动平台上，插件缺失或沙箱限制都可能让
/// path_provider 失败，这里按候选顺序逐个探测真实可写性。
abstract final class AppPaths {
  static const String _probeMarker = '.qfli_write_probe';
  static Future<String?>? _storageFuture;
  static Future<String?>? _writableFuture;
  static int _probeId = 0;
  static String? _storagePathCache;

  /// Last resolved storage directory, or null when not resolved yet.
  ///
  /// Synchronous so callers that must not await (e.g. a terminal building its
  /// sandbox root inside initState) can use it without scheduling a probe timer.
  static String? get storageDirectoryIfResolved => _storagePathCache;

  /// 首个可写的候选目录；全部失败返回 null。
  static Future<String?> writableDirectory() =>
      _writableFuture ??= _findWritableDirectory();

  static Future<String?> _findWritableDirectory() async {
    final candidates = <String>[];

    Future<void> tryAdd(Future<Directory?> Function() getter) async {
      try {
        final dir = await getter().timeout(const Duration(seconds: 2));
        if (dir != null) candidates.add(dir.path);
      } catch (_) {
        // 平台实现缺失（如 ohos 未注册插件）时忽略。
      }
    }

    await tryAdd(() => getApplicationDocumentsDirectory());
    await tryAdd(() => getApplicationSupportDirectory());
    await tryAdd(() => getExternalStorageDirectory());

    for (final key in const ['HOME', 'USERPROFILE', 'TMPDIR', 'TEMP', 'TMP']) {
      final value = Platform.environment[key];
      if (value != null && value.isNotEmpty) candidates.add(value);
    }
    try {
      if (Directory.current.path.isNotEmpty) {
        candidates.add(Directory.current.path);
      }
    } catch (_) {}

    for (final path in candidates) {
      if (await _isWritable(path)) return path;
    }
    return null;
  }

  /// 配置文件所在目录：优先应用支持目录，其次文档目录，最后任意可写目录。
  static Future<String?> storageDirectory() =>
      _storageFuture ??= _findStorageDirectory();

  static Future<String?> _findStorageDirectory() async {
    // 三个 Store 共享一次探测；第一个候选成功后立即返回。
    for (final getter in [
      getApplicationSupportDirectory,
      getApplicationDocumentsDirectory,
    ]) {
      try {
        final dir = await getter().timeout(const Duration(seconds: 2));
        if (await _isWritable(dir.path)) return _storagePathCache = dir.path;
      } catch (_) {}
    }
    return _storagePathCache = await writableDirectory();
  }

  /// 新建项目的默认根目录：`<应用数据>/projects`。
  ///
  /// [create] 为 true 时确保目录存在（用于创建项目前）。
  static Future<String?> projectsRoot({bool create = false}) async {
    final base = await storageDirectory();
    if (base == null) return null;
    final dir = Directory(p.join(base, 'projects'));
    if (create) {
      try {
        await dir.create(recursive: true);
      } on FileSystemException {
        return null;
      }
    }
    return dir.path;
  }

  static String languageProjectsRoot(
    String location, {
    String type = '',
    String language = '',
  }) {
    final template =
        ProjectTemplate.fromType(type) ??
        ProjectTemplate.fromLanguage(language) ??
        ProjectTemplate.empty;
    final root = p.normalize(p.absolute(location.trim()));
    return p.equals(p.basename(root), template.directoryName)
        ? root
        : p.join(root, template.directoryName);
  }

  static String availableProjectPath({
    required String directory,
    required String name,
  }) {
    final trimmed = name.trim();
    if (!FileService.isValidEntryName(trimmed) || trimmed.contains('\u0000')) {
      throw const FileSystemException('项目名称无效');
    }
    bool occupied(String path) =>
        FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
    final original = p.join(directory, trimmed);
    if (!occupied(original)) return original;
    final stamped = '${trimmed}_${DateTime.now().millisecondsSinceEpoch}';
    var candidate = p.join(directory, stamped);
    var counter = 1;
    while (occupied(candidate)) {
      candidate = p.join(directory, '${stamped}_${counter++}');
    }
    return candidate;
  }

  static Directory createProjectDirectory({
    required String location,
    required String name,
    String type = '',
    String language = '',
  }) {
    final root = languageProjectsRoot(location, type: type, language: language);
    final directory = Directory(
      availableProjectPath(directory: root, name: name),
    );
    // Reserve the directory before template/archive writes yield to another creator.
    directory.createSync(recursive: true);
    return directory;
  }

  /// Creates a directory for an imported example whose **display name** may be a
  /// Chinese title. The on-disk basename is always unique ASCII of the form
  /// `demo_<timestamp>_<random>` so a non-ASCII title never becomes a directory
  /// name and repeated imports never collide.
  static Directory createAsciiDemoProjectDirectory({
    required String location,
    String type = '',
    String language = '',
  }) {
    final root = languageProjectsRoot(location, type: type, language: language);
    final directory = Directory(_uniqueAsciiDemoPath(root));
    directory.createSync(recursive: true);
    return directory;
  }

  static String _uniqueAsciiDemoPath(String root) {
    bool occupied(String path) =>
        FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
    for (var attempt = 0; attempt < 1000; attempt++) {
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final rand = Random().nextInt(46656).toRadixString(36).padLeft(3, '0');
      final candidate = p.join(root, 'demo_${stamp}_$rand');
      if (!occupied(candidate)) return candidate;
    }
    throw const FileSystemException('无法生成唯一的示例目录名');
  }

  /// 通过写入并删除探针文件验证目录可写。
  static Future<bool> _isWritable(String dirPath) async {
    try {
      if (!await Directory(dirPath).exists()) return false;
      final probe = File(
        p.join(
          dirPath,
          '$_probeMarker${DateTime.now().microsecondsSinceEpoch}_${_probeId++}',
        ),
      );
      await probe.writeAsString('ok', flush: false);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 是否为桌面平台（可访问任意磁盘路径）。
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}
