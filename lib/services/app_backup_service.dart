import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_backup_codec.dart';
import 'app_paths.dart';
import 'app_private_roots.dart';
import 'studio_profile.dart';

/// 应用级全量私有数据备份。
///
/// 导出/导入的范围是**整个应用私有数据目录**（`AppPaths.storageDirectory()`）：
/// 设置、项目注册表、认证、教程示例缓存、本地统计/审计、任务活动，以及
/// `projects/`（含二进制资源）、`files_backup/`、`recyclebin/`、
/// `avatar_cache/`、`code_snippets/`、`cloud_projects/` 等全部子目录。
///
/// 归档是 ZIP（扩展名 `.qfliz`），根目录含 `app_info.json`，其余数据统一放在
/// `data/` 前缀下，保持与私有目录一致的相对路径。
///
/// ## 恢复边界（关键设计）
///
/// 线上存储（`SettingsStore` / `ProjectStore` / `ExampleCodeStore` 等）会保留
/// 内存状态、排队写盘，被最小化的编辑器还可能后台自动保存。**在应用运行中
/// 直接替换私有文件是不安全的**。因此导入拆成两步：
///
/// 1. [prepareImport]：校验整个归档（格式、身份、路径、符号链接），把数据写入
///    私有的暂存目录，并落下 pending 标记。此步**完全不改动线上数据**，可以在
///    设置页里立即执行并提示“重启后生效”。
/// 2. [applyPendingRestore]：在下一次 [AppBootstrap] 里、任何 Store 加载之前
///    执行。它把暂存数据整体交换进私有根，失败则回滚。此时没有活动会话。
///
/// [importAll] 是「立即 prepare + apply」的便捷入口，仅供测试或确认无活动存储的
/// 工具路径使用。
///
/// ## 安全校验
///
/// - 拒绝非 `data/` 前缀的根条目、绝对路径、`..` 越界、空路径、重复路径。
/// - 保留符号链接文本但不跟随目标；拒绝以链接为祖先的数据条目。
/// - 只在应用私有根上工作；`AppPaths` 回退到 HOME/当前目录时拒绝导出。
class AppBackupException implements Exception {
  const AppBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 归档元数据（根 `app_info.json`）。
@immutable
class AppBackupInfo {
  const AppBackupInfo({
    required this.formatVersion,
    required this.productKey,
    required this.appTitle,
    required this.profileId,
    required this.runtimeKind,
    required this.createdAt,
    required this.fileCount,
    this.appVersion = '1.0.0',
    this.recordedRoots = const {},
    this.recordedRootPath,
  });

  /// 归档格式版本，用于未来迁移。
  final int formatVersion;

  /// 导出产品的稳定 key，例如 `jvmx`。
  final String productKey;

  /// 导出产品显示名，例如 `QFLIJVMX`。
  final String appTitle;

  /// `StudioProfile.id`。
  final String profileId;

  /// `StudioProfile.runtimeKind`。
  final String runtimeKind;

  final String appVersion;
  final DateTime createdAt;
  final int fileCount;

  /// 导出时各私有根的绝对路径，键为稳定根名（`storage`、`documents`...）。
  ///
  /// 用于恢复时重定位 `projects.json` 里跨根记录的绝对路径：跨设备/跨沙箱后旧
  /// 前缀已不存在，需要把落在旧根下的路径重写到对应新根。
  final Map<String, String> recordedRoots;

  /// 旧版单根字段，兼容早期归档。
  final String? recordedRootPath;

  Map<String, dynamic> toJson() => {
    'format': 'qfli-app-backup',
    'formatVersion': formatVersion,
    'productKey': productKey,
    'appTitle': appTitle,
    'profileId': profileId,
    'runtimeKind': runtimeKind,
    'appVersion': appVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'fileCount': fileCount,
    if (recordedRoots.isNotEmpty) 'recordedRoots': recordedRoots,
    if (recordedRootPath != null) 'recordedRootPath': recordedRootPath,
  };

  /// 返回写入了新的已记录根集合的副本。
  AppBackupInfo copyWithRoots(
    Map<String, String> roots, {
    String? legacyRootPath,
  }) => AppBackupInfo(
    formatVersion: formatVersion,
    productKey: productKey,
    appTitle: appTitle,
    profileId: profileId,
    runtimeKind: runtimeKind,
    createdAt: createdAt,
    fileCount: fileCount,
    appVersion: appVersion,
    recordedRoots: roots,
    recordedRootPath: legacyRootPath,
  );

  static AppBackupInfo fromJson(Map<String, dynamic> json) {
    Object? raw(String key) => json[key];
    final format = raw('format');
    if (format != null && format != 'qfli-app-backup') {
      throw const AppBackupException('不是本应用生成的备份文件');
    }
    final formatVersion = (raw('formatVersion') as num?)?.toInt();
    if (formatVersion == null || formatVersion < 1) {
      throw const AppBackupException('备份缺少有效的格式版本');
    }
    final createdAt = DateTime.tryParse(raw('createdAt') as String? ?? '');
    return AppBackupInfo(
      formatVersion: formatVersion,
      productKey: raw('productKey') as String? ?? '',
      appTitle: raw('appTitle') as String? ?? '',
      profileId: raw('profileId') as String? ?? '',
      runtimeKind: raw('runtimeKind') as String? ?? '',
      appVersion: raw('appVersion') as String? ?? '1.0.0',
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      fileCount: (raw('fileCount') as num?)?.toInt() ?? 0,
      recordedRoots: {
        for (final entry in (raw('recordedRoots') as Map? ?? const {}).entries)
          entry.key.toString(): entry.value.toString(),
      },
      recordedRootPath: raw('recordedRootPath') as String?,
    );
  }
}

/// 一次导出的结果：归档字节与元数据。
@immutable
class AppBackupBundle {
  const AppBackupBundle({required this.bytes, required this.info});

  final Uint8List bytes;
  final AppBackupInfo info;

  int get byteLength => bytes.length;
}

/// 一次「已暂存、等待下次启动应用」的导入。
@immutable
class PreparedRestore {
  const PreparedRestore({
    required this.info,
    required this.fileCount,
    required this.stagingDirectory,
  });

  final AppBackupInfo info;
  final int fileCount;

  /// 暂存目录（位于私有根下），下次启动由 [AppBackupService.applyPendingRestore] 消费。
  final String stagingDirectory;
}

/// 一次应用（交换）后的结果。
@immutable
class AppRestoreResult {
  const AppRestoreResult({required this.info, required this.restoredFiles});

  final AppBackupInfo info;
  final int restoredFiles;
}

abstract final class AppBackupService {
  /// 当前归档格式版本。导入时兼容 `<= currentFormatVersion`。
  static const int currentFormatVersion = 1;

  /// 归档内元数据文件名。
  static const String infoFileName = 'app_info.json';

  /// 归档内主私有根的数据目录前缀。
  static const String dataPrefix = 'data';

  /// 主私有根（`storage`）的稳定根名。
  static const String storageRootKey = 'storage';

  /// 额外私有根在归档中的目录前缀，键为根名。
  static String extraRootPrefix(String rootKey) => 'private_$rootKey';

  /// 暂存根目录名（私有根下）。整个目录都是暂存，导入前后都不会被导出。
  static const String stagingDirName = '.qfli-app-restore';

  /// pending 标记文件名。
  static const String pendingFileName = 'pending.json';

  /// 恢复副本目录名（固定名，便于中断后被发现接管）。
  static const String oldDirName = '.qfli-app-old';

  /// 恢复副本内部布局：`originals/` 存原数据，`control/` 存 journal。
  ///
  /// 与用户数据隔离，避免用户同名 `journal.json` 被移入后覆盖控制文件。
  static const String backupOriginalsDir = 'originals';
  static const String backupControlDir = 'control';

  /// 还原事务 journal 文件名。
  static const String journalFileName = 'journal.json';

  /// 测试注入私有根；为 null 时走 [AppPaths.storageDirectory]。
  ///
  /// 设置后跳过「必须为应用私有目录」的检查（测试用临时目录）。
  @visibleForTesting
  static String? rootOverride;

  /// 测试注入的根解析器；为 null 时走 [AppPrivateRoots.resolve]。
  ///
  /// 返回稳定的根名 → 绝对路径。`storage` 必须存在。
  @visibleForTesting
  static Future<Map<String, String>> Function(String storagePath)?
  rootsResolverOverride;

  /// 测试注入的移动钩子；抛出异常模拟中断/失败。
  @visibleForTesting
  static Future<void> Function(String from, String to)? moveOverride;

  static bool _preparing = false;

  /// 需要重定位的项目注册表文件名。
  static const String projectRegistryFileName = 'projects.json';

  /// 当前产品的身份信息，用于写入/校验归档。
  static AppBackupInfo currentInfo({int fileCount = 0}) {
    final profile = StudioProfile.current;
    return AppBackupInfo(
      formatVersion: currentFormatVersion,
      productKey: profile?.productKey ?? StudioProductCatalog.qfliStudioKey,
      appTitle: profile?.appTitle ?? StudioProductCatalog.qfliStudio,
      profileId: profile?.id ?? '',
      runtimeKind: profile?.runtimeKind ?? 'unavailable',
      createdAt: DateTime.now().toUtc(),
      fileCount: fileCount,
    );
  }

  /// 只解析**主根**路径，不做严格私有根校验。
  ///
  /// 用于启动时将“无待处理恢复”的常见路径快速短路，避免 AppPaths 回退目录的
  /// 普通启动被误判为需要恢复。
  static Future<String?> _primaryStoragePath() async {
    if (rootOverride case final override?) {
      return p.normalize(p.absolute(override));
    }
    final base = await AppPaths.storageDirectory();
    return (base == null || base.isEmpty)
        ? null
        : p.normalize(p.absolute(base));
  }

  /// 主根下是否存在被中断事务的 journal 痕迹。
  static Future<bool> _hasJournalTrace(Directory primaryRoot) async {
    final backup = Directory(p.join(primaryRoot.path, oldDirName));
    if (await _journalFile(backup).exists()) return true;
    final staging = Directory(p.join(primaryRoot.path, stagingDirName));
    return File(p.join(staging.path, journalFileName)).exists();
  }

  /// 解析所有已确认的应用私有根（稳定的根名 → 绝对路径）。
  ///
  /// `storage` 始终存在。额外根（如 Android `documents`）由
  /// [AppPrivateRoots.resolve] 提供；只有 provider 确认的私有目录才会出现，
  /// 桌面共享目录永远不会被当作私有根。
  static Future<Map<String, String>> _resolveRoots() async {
    final resolver = rootsResolverOverride;
    if (rootOverride case final override?) {
      final storage = p.normalize(p.absolute(override));
      if (resolver == null) return {storageRootKey: storage};
      return resolver(storage);
    }
    final base = await AppPaths.storageDirectory();
    if (base == null || base.isEmpty) {
      throw const AppBackupException('未找到应用私有数据目录');
    }
    final roots = resolver != null
        ? await resolver(base)
        : await AppPrivateRoots.resolve(base);
    if (!roots.containsKey(storageRootKey)) {
      throw const AppBackupException('无法确认应用私有数据目录');
    }
    return roots;
  }

  /// 某一根备份目录下的原数据目录。
  static Directory _originalsDir(Directory backup) =>
      Directory(p.join(backup.path, backupOriginalsDir));

  /// 某一根备份目录下的控制文件（journal）。
  ///
  /// 与控制文件隔离于 `control/`，避免用户同名 `journal.json` 被移入后覆盖。
  static File _journalFile(Directory backup) =>
      File(p.join(backup.path, backupControlDir, journalFileName));

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// 导出整应用私有数据到指定文件（推荐路径，流式、在 isolate 中运行）。
  ///
  /// 主根（`storage`）写入 `data/`，其余私有根（如 Android `documents`）
  /// 写入 `private_<rootKey>/`。返回归档元数据。
  static Future<AppBackupInfo> exportToFile(String destination) async {
    final roots = await _resolveRoots();
    final info = currentInfo().copyWithRoots(
      roots,
      legacyRootPath: roots[storageRootKey],
    );
    final metadata = await AppBackupCodec.exportFile(
      roots: roots,
      info: info.toJson(),
      destination: destination,
    );
    return AppBackupInfo.fromJson(Map<String, dynamic>.from(metadata));
  }

  /// 导出整应用私有数据为 `.qfliz` 归档字节（兼容 / URI 上传路径）。
  ///
  /// 先流式写入临时文件，再一次性读回压缩字节并清理临时文件；内存只驻留压缩
  /// 结果，不保留未压缩的整棵私有树。需要控制内存的大导出请用 [exportToFile]。
  static Future<AppBackupBundle> exportAll() async {
    final tempRoot = await Directory.systemTemp.createTemp('qfli-export-');
    final destination = p.join(tempRoot.path, 'backup.qfliz');
    try {
      final info = await exportToFile(destination);
      final bytes = await File(destination).readAsBytes();
      return AppBackupBundle(bytes: bytes, info: info);
    } finally {
      try {
        await tempRoot.delete(recursive: true);
      } on FileSystemException {
        // 临时清理失败不影响导出结果。
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Metadata / validation
  // ---------------------------------------------------------------------------

  /// 仅读取归档元数据（导入前预览/校验）。
  static AppBackupInfo readInfo(Uint8List bytes) {
    final archive = _decodeArchive(bytes);
    final entry = _findEntry(archive, infoFileName);
    if (entry == null) {
      throw const AppBackupException('备份缺少 $infoFileName');
    }
    _verifyCrc(entry, infoFileName, entry.content);
    return AppBackupInfo.fromJson(_decodeJson(entry, infoFileName));
  }

  /// Parse large ZIP directories without blocking page animations.
  static Future<AppBackupInfo> readInfoAsync(Uint8List bytes) =>
      Isolate.run(() => readInfo(bytes));

  /// 校验归档身份与当前产品是否兼容。
  ///
  /// 同产品线（productKey 相同）始终允许，从而支持同一产品跨操作系统恢复。
  /// 跨产品时仅当任一侧 profileId 为空（多语言全能版）时允许。
  static void assertCompatible(
    AppBackupInfo info, {
    AppBackupInfo? current,
    bool allowCrossProduct = false,
  }) {
    if (info.formatVersion > currentFormatVersion) {
      throw AppBackupException(
        '备份来自更新版本（格式 ${info.formatVersion}），当前仅支持 $currentFormatVersion',
      );
    }
    if (allowCrossProduct) return;
    final target = current ?? currentInfo();
    if (info.productKey == target.productKey) return;
    if (info.profileId.isEmpty || target.profileId.isEmpty) return;
    throw AppBackupException(
      '该备份属于 ${info.appTitle.isEmpty ? info.productKey : info.appTitle}，'
      '与当前应用不兼容',
    );
  }

  /// 是否已有待应用的导入。
  static Future<bool> hasPendingRestore() async {
    final dir = await _pendingDirectory();
    return dir != null &&
        await File(p.join(dir.path, pendingFileName)).exists();
  }

  /// 读取待应用导入的元数据；没有则返回 null。
  static Future<AppBackupInfo?> pendingRestoreInfo() async {
    final dir = await _pendingDirectory();
    if (dir == null) return null;
    final marker = File(p.join(dir.path, pendingFileName));
    if (!await marker.exists()) return null;
    try {
      final data = jsonDecode(await marker.readAsString());
      if (data is! Map) return null;
      return AppBackupInfo.fromJson(Map<String, dynamic>.from(data));
    } on Object {
      return null;
    }
  }

  static Future<Directory?> _pendingDirectory() async {
    final base = rootOverride ?? AppPaths.storageDirectoryIfResolved;
    if (base == null || base.isEmpty) return null;
    return Directory(p.join(base, stagingDirName));
  }

  // ---------------------------------------------------------------------------
  // Prepare (no live mutation)
  // ---------------------------------------------------------------------------

  /// 校验归档并把数据写入暂存目录，等待下次启动应用。
  ///
  /// 全程**不改动线上数据**。已存在待应用的导入时抛出，避免二次覆盖。
  /// 暂存布局：`payload/<rootKey>/...`，每根一个子目录。
  static Future<PreparedRestore> prepareImport(
    Uint8List bytes, {
    AppBackupInfo? current,
    bool allowCrossProduct = false,
    bool replacePending = false,
  }) async {
    if (_preparing) throw const AppBackupException('已有导入正在进行');
    _preparing = true;
    try {
      final roots = await _resolveRoots();
      // Plugins and product globals belong to the main isolate. Pass their
      // resolved values explicitly; decompression, checksums and staging do not.
      final identity = current ?? currentInfo();
      return await Isolate.run(
        () => _prepareImportWorker(
          bytes,
          roots: roots,
          current: identity,
          allowCrossProduct: allowCrossProduct,
          replacePending: replacePending,
        ),
      );
    } finally {
      _preparing = false;
    }
  }

  static Future<PreparedRestore> _prepareImportWorker(
    Uint8List bytes, {
    required Map<String, String> roots,
    required AppBackupInfo current,
    required bool allowCrossProduct,
    required bool replacePending,
  }) async {
    final root = Directory(roots[storageRootKey]!);
    final archive = _decodeArchive(bytes);
    final info = readInfo(bytes);
    assertCompatible(
      info,
      current: current,
      allowCrossProduct: allowCrossProduct,
    );
    final entries = _validateEntries(archive);
    if (entries.isEmpty) {
      throw const AppBackupException('备份中没有可恢复的数据');
    }
    // 归档中的根名必须是当前真实存在的私有根。
    // 否则 `private_../x` 之类的根名会逃出 payload 目录。
    for (final key in entries.map((e) => e.rootKey).toSet()) {
      if (!roots.containsKey(key)) {
        throw AppBackupException('备份包含未知的根：$key');
      }
    }

    final stagingRoot = Directory(p.join(root.path, stagingDirName));
    if (await stagingRoot.exists()) {
      if (!replacePending &&
          await File(p.join(stagingRoot.path, pendingFileName)).exists()) {
        throw const AppBackupException('已有待应用的恢复，请先重启应用完成或取消');
      }
      await _safeDelete(stagingRoot);
    }
    final payload = Directory(p.join(stagingRoot.path, 'payload'));
    await payload.create(recursive: true);
    final payloadRoot = p.normalize(p.absolute(payload.path));
    String full(String rootKey, String relative) {
      final target = p.normalize(
        p.absolute(p.joinAll([payload.path, rootKey, ...relative.split('/')])),
      );
      // 防御性断言：所有暂存目标必须位于 payload 内。
      if (!p.isWithin(payloadRoot, target)) {
        throw AppBackupException('备份路径越界：$relative');
      }
      return target;
    }

    try {
      // 先落普通目录与文件，再最后建符号链接：链接不能有链接祖先，先建链接
      // 会让后续内容写入跟随链接到外部。
      for (final entry in entries.where((e) => e.kind != _EntryKind.symlink)) {
        final target = full(entry.rootKey, entry.path);
        switch (entry.kind) {
          case _EntryKind.directory:
            await Directory(target).create(recursive: true);
          case _EntryKind.file:
            final file = File(target);
            await file.parent.create(recursive: true);
            // Retain one decompressed member at a time, rather than a copy of
            // every runtime/project file alongside the compressed archive.
            final member = entry.member!;
            final content = member.content;
            _verifyCrc(member, entry.path, content);
            await file.writeAsBytes(content, flush: true);
            member.clear();
            if (entry.mode != null) {
              await _applyMode(file.path, entry.mode!);
            }
          case _EntryKind.symlink:
            // 已在上面过滤掉。
            break;
        }
      }
      for (final entry in entries.where((e) => e.kind == _EntryKind.symlink)) {
        final target = full(entry.rootKey, entry.path);
        await Directory(p.dirname(target)).create(recursive: true);
        // 只写链接文本，绝不读取/写入链接目标。
        await Link(target).create(entry.target!);
      }
      // 为每个出现过的根建好空目录，确保只有链接的根也能正确交换。
      for (final rootKey in entries.map((e) => e.rootKey).toSet()) {
        await Directory(p.join(payload.path, rootKey)).create(recursive: true);
      }
      // Apply directory permissions only after all children have been written.
      final directories =
          entries
              .where((e) => e.kind == _EntryKind.directory && e.mode != null)
              .toList()
            ..sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final entry in directories) {
        await _applyMode(full(entry.rootKey, entry.path), entry.mode!);
      }
      await File(
        p.join(stagingRoot.path, pendingFileName),
      ).writeAsString(jsonEncode(info.toJson()), flush: true);
    } catch (error) {
      await _safeDelete(stagingRoot);
      if (error is AppBackupException) rethrow;
      throw AppBackupException('写入暂存数据失败：$error');
    }
    return PreparedRestore(
      info: info,
      fileCount: entries.where((e) => e.kind != _EntryKind.directory).length,
      stagingDirectory: stagingRoot.path,
    );
  }

  /// 取消待应用的导入，清理暂存数据。
  static Future<void> cancelPendingRestore() async {
    if (_preparing) throw const AppBackupException('请等待当前导入完成');
    final dir = await _pendingDirectory();
    if (dir == null) return;
    await _safeDelete(dir);
  }

  // ---------------------------------------------------------------------------
  // Apply (bootstrap-time)
  // ---------------------------------------------------------------------------

  /// 在下一次启动、任何 Store 加载之前应用待处理的导入。
  ///
  /// 交换协议（可中断、可恢复）：
  /// 0. **先检查已存在的 journal**：若上次事务被中断，先恢复（回滚或确认已完成）
  ///    再继续；绝不无条件删除旧恢复副本。
  /// 1. **先写 journal**：在任何移动之前写入。
  /// 2. 把当前私有根的用户子项移入恢复副本 `backup/<rootKey>/`。
  /// 3. 把 payload 中的子项移入对应私有根。
  /// 4. 成功后删除 journal、恢复副本与 staging（提交）。
  ///
  /// 失败时回滚：删除已换入的新子项，再把恢复副本移回。若回滚不完整，
  /// **保留 staging、恢复副本与 journal**，下轮启动可继续恢复。
  static Future<AppRestoreResult?> applyPendingRestore() async {
    // 先只解析**主根**并检查是否有 pending 或中断事务的痕迹。
    // 没有待处理恢复时必须立即返回，绝不能因为无法严格确认私有根而让
    // 普通启动（例如 AppPaths 回退目录）进入恢复门控。
    final primary = await _primaryStoragePath();
    if (primary == null) return null;
    final primaryDir = Directory(primary);
    final probeStaging = Directory(p.join(primaryDir.path, stagingDirName));
    final hasMarker = await File(
      p.join(probeStaging.path, pendingFileName),
    ).exists();
    final hasJournal = await _hasJournalTrace(primaryDir);
    if (!hasMarker && !hasJournal) return null;

    // 确认确实存在待处理恢复/中断事务后，才严格解析全部私有根。
    final Map<String, String> roots;
    try {
      roots = await _resolveRoots();
    } catch (_) {
      // 无法确认私有根但确实存在待恢复数据：保守要求恢复（不能以部分状态启动）。
      if (hasJournal) {
        throw const AppBackupException('存在被中断的恢复，但无法确认应用私有目录');
      }
      return null;
    }
    final root = Directory(roots[storageRootKey]!);
    final stagingRoot = Directory(p.join(root.path, stagingDirName));
    // A transaction takes priority over a possibly missing/corrupt pending
    // marker or payload. Never load stores while originals are still moved out.
    final interrupted = await _recoverInterrupted(roots);
    if (interrupted != null) return interrupted;
    final marker = File(p.join(stagingRoot.path, pendingFileName));
    if (!await marker.exists()) {
      return null;
    }
    final payload = Directory(p.join(stagingRoot.path, 'payload'));
    if (!await payload.exists()) {
      await _safeDelete(stagingRoot);
      return null;
    }

    AppBackupInfo info;
    try {
      final data = jsonDecode(await marker.readAsString());
      info = AppBackupInfo.fromJson(Map<String, dynamic>.from(data as Map));
    } on Object {
      await _safeDelete(stagingRoot);
      throw const AppBackupException('待应用的恢复标记已损坏');
    }

    // 1) 先规划并写入 journal，再做任何移动。
    final backupRoots = <String, Directory>{};
    for (final entry in roots.entries) {
      final backup = Directory(p.join(entry.value, oldDirName));
      // 只有在确认无残留 journal 后才清空旧的恢复副本。
      await _safeDelete(backup);
      await _originalsDir(backup).create(recursive: true);
      await Directory(
        p.join(backup.path, backupControlDir),
      ).create(recursive: true);
      backupRoots[entry.key] = backup;
    }
    final primaryBackup = backupRoots[storageRootKey]!;
    final journal = <String, dynamic>{
      'state': 'planned',
      'version': 1,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'recordedRoots': {for (final e in roots.entries) e.key: e.value},
      'plannedOrigins': <String, List<String>>{},
      'plannedNew': <String, List<String>>{},
      'movedToBackup': <String, List<String>>{},
      'installedNew': <String, List<String>>{},
    };
    final plannedOrigins =
        journal['plannedOrigins'] as Map<String, List<String>>;
    final plannedNew = journal['plannedNew'] as Map<String, List<String>>;
    for (final entry in roots.entries) {
      final base = Directory(entry.value);
      if (await base.exists()) {
        plannedOrigins[entry.key] = [
          for (final entity in base.listSync(followLinks: false))
            if (!_isTransientTopLevel(p.basename(entity.path)))
              p.basename(entity.path),
        ];
      }
    }
    for (final rootDir in payload.listSync(followLinks: false)) {
      final key = p.basename(rootDir.path);
      if (rootDir is! Directory) {
        throw AppBackupException('暂存数据包含意外条目：$key');
      }
      plannedNew[key] = [
        for (final entity in rootDir.listSync(followLinks: false))
          p.basename(entity.path),
      ];
    }

    List<String> journalList(String key, String field) =>
        (journal[field] as Map<String, List<String>>).putIfAbsent(
          key,
          () => <String>[],
        );

    Future<void> writeJournal() async {
      final encoded = jsonEncode(journal);
      // 原子写入：先写临时文件再 rename，避免半截 journal 导致恢复误判。
      Future<void> atomic(File file) async {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(encoded, flush: true);
        await temp.rename(file.path);
      }

      await atomic(_journalFile(primaryBackup));
      await atomic(File(p.join(stagingRoot.path, journalFileName)));
    }

    await writeJournal();

    try {
      journal['state'] = 'moving-originals';
      await writeJournal();
      for (final entry in roots.entries) {
        final base = Directory(entry.value);
        final backup = backupRoots[entry.key]!;
        if (!await base.exists()) continue;
        for (final name in plannedOrigins[entry.key] ?? const <String>[]) {
          final source = p.join(base.path, name);
          if (FileSystemEntity.typeSync(source, followLinks: false) ==
              FileSystemEntityType.notFound) {
            continue;
          }
          await _move(
            _entityFor(source),
            p.join(_originalsDir(backup).path, name),
          );
          journalList(entry.key, 'movedToBackup').add(name);
          await writeJournal();
        }
      }
      journal['state'] = 'installing';
      await writeJournal();
      for (final entry in plannedNew.entries) {
        final key = entry.key;
        final base = roots[key];
        if (base == null) {
          throw AppBackupException('备份包含未知的根：$key');
        }
        final target = Directory(base);
        await target.create(recursive: true);
        for (final name in entry.value) {
          final source = p.join(payload.path, key, name);
          if (FileSystemEntity.typeSync(source, followLinks: false) ==
              FileSystemEntityType.notFound) {
            continue;
          }
          await _move(_entityFor(source), p.join(target.path, name));
          journalList(key, 'installedNew').add(name);
          await writeJournal();
        }
      }
      await _rebaseProjectRegistry(root, info, roots);
      journal['state'] = 'committed';
      await writeJournal();
    } on Object catch (error) {
      journal['state'] = 'rolling-back';
      try {
        await writeJournal();
      } on Object {
        // journal 写不进也不阻止回滚。
      }
      final failures = await _rollbackFromJournal(journal, roots, backupRoots);
      if (failures.isEmpty) {
        await _safeDelete(stagingRoot);
        for (final backup in backupRoots.values) {
          await _safeDelete(backup);
        }
        throw AppBackupException('恢复失败，已还原原有数据：$error');
      }
      // 回滚不完整：保留 staging、恢复副本与 journal。
      throw AppBackupException(
        '恢复失败且未能完全回滚（未还原：${failures.join('、')}）。'
        '已保留恢复副本目录 $oldDirName、$journalFileName 与暂存数据，请勿删除。'
        '原始错误：$error',
      );
    }
    await _safeDelete(stagingRoot);
    for (final backup in backupRoots.values) {
      await _safeDelete(backup);
    }
    return AppRestoreResult(info: info, restoredFiles: info.fileCount);
  }

  /// 检查并恢复一个被中断的事务。
  ///
  /// - `committed`：上次已完成（仅在删 journal 前崩溃），直接清理。
  /// - 否则：回滚，优先按 journal 记录，其次从磁盘实际内容推断。
  ///
  /// 返回非 null 表示接管了一个中断事务（本次不再继续应用）。
  static Future<AppRestoreResult?> _recoverInterrupted(
    Map<String, String> roots,
  ) async {
    // 读取 journal：优先各根的 control journal；若均缺失，尝试 staging 中的副本。
    Map<String, dynamic>? journal;
    var journalCorrupt = false;
    for (final entry in roots.entries) {
      final backup = Directory(p.join(entry.value, oldDirName));
      final file = _journalFile(backup);
      if (await file.exists()) {
        try {
          final data = jsonDecode(await file.readAsString());
          if (data is Map) {
            journal = Map<String, dynamic>.from(data);
          } else {
            journalCorrupt = true;
          }
        } on Object {
          journalCorrupt = true;
        }
        break;
      }
    }
    if (journal == null) {
      // 主 journal 缺失或损坏：尝试 staging 里的 journal 副本。
      final staging = Directory(p.join(roots[storageRootKey]!, stagingDirName));
      final stagingJournal = File(p.join(staging.path, journalFileName));
      if (await stagingJournal.exists()) {
        journalCorrupt = true;
        try {
          final data = jsonDecode(await stagingJournal.readAsString());
          if (data is Map) {
            journal = Map<String, dynamic>.from(data);
          }
        } on Object {
          // 两份都坏：保留现场并报错，绝不删除恢复目录。
        }
      }
    }
    if (journal == null) {
      if (!journalCorrupt) return null;
      throw const AppBackupException('检测到损坏的恢复事务记录；已保留恢复目录，请勿删除。');
    }

    // 任何清理/回滚之前，先验证 journal 记录的**全部**根在当前仍然齐全且路径
    // 一致。否则（例如 documents provider 暂时缺失）会在只处理主根后把主
    // journal 删掉，导致另一根的数据被孤立。
    final recordedRoots = <String, String>{
      for (final entry
          in ((journal['recordedRoots'] as Map?) ?? const {}).entries)
        entry.key.toString(): entry.value.toString(),
    };
    if (recordedRoots.isNotEmpty) {
      for (final entry in recordedRoots.entries) {
        final current = roots[entry.key];
        if (current == null) {
          throw AppBackupException(
            '恢复事务涉及的私有根 ${entry.key} 当前不可用；已保留恢复目录与 journal。',
          );
        }
        if (!p.equals(p.normalize(current), p.normalize(entry.value))) {
          throw AppBackupException(
            '恢复事务涉及的私有根 ${entry.key} 路径已变化；已保留恢复目录与 journal。',
          );
        }
      }
    }

    final state = journal['state'] as String? ?? 'unknown';
    final backupRoots = <String, Directory>{
      for (final entry in roots.entries)
        entry.key: Directory(p.join(entry.value, oldDirName)),
    };
    if (state == 'committed') {
      // 已经提交：清理暂存与恢复副本，并**返回非 null 让调用方停止本次启动**
      // （不能返回 null，否则 applyPendingRestore 会继续使用已删除的 payload）。
      for (final entry in roots.entries) {
        await _safeDelete(Directory(p.join(entry.value, stagingDirName)));
        await _safeDelete(backupRoots[entry.key]!);
      }
      return AppRestoreResult(info: currentInfo(), restoredFiles: 0);
    }
    final failures = await _rollbackFromJournal(
      journal,
      roots,
      backupRoots,
      inferFromDisk: true,
    );
    if (failures.isEmpty) {
      final staging = Directory(p.join(roots[storageRootKey]!, stagingDirName));
      await _safeDelete(staging);
      for (final backup in backupRoots.values) {
        await _safeDelete(backup);
      }
      return AppRestoreResult(info: currentInfo(), restoredFiles: 0);
    }
    throw AppBackupException(
      '检测到被中断的恢复且未能完全回滚（未还原：${failures.join('、')}）。'
      '已保留恢复副本与 journal，请勿删除。',
    );
  }

  /// 根据 journal（[inferFromDisk] 时结合磁盘实际内容）执行回滚。
  ///
  /// 核心原则（避免误删未动的原始文件）：
  /// - 只有在恢复副本中**确实存在对应原文件**时，才可删除目标位置（即目标确实
  ///   是被换入的新项）。若原文件未被移入副本（如 `planned` 阶段就中断），目标
  ///   就是原始文件，必须保留。
  /// - 对同名交叠（原项与新项同名）：仅当副本存在时才删目标，否则保留。
  ///
  /// 返回未能还原的 `rootKey/name` 列表；为空表示回滚完整。
  static Future<List<String>> _rollbackFromJournal(
    Map<String, dynamic> journal,
    Map<String, String> roots,
    Map<String, Directory> backupRoots, {
    bool inferFromDisk = false,
  }) async {
    final failures = <String>[];
    // 拷贝成可变列表，避免对 const [] 调用 add。
    List<String> list(String field, String key) => [
      ...(((journal[field] as Map?)?[key] as List?)?.cast<String>() ??
          const <String>[]),
    ];
    final installed = <String, List<String>>{
      for (final key in roots.keys) key: list('installedNew', key),
    };
    final moved = <String, List<String>>{
      for (final key in roots.keys) key: list('movedToBackup', key),
    };
    final plannedOrigins = <String, List<String>>{
      for (final key in roots.keys) key: list('plannedOrigins', key),
    };
    final plannedNew = <String, List<String>>{
      for (final key in roots.keys) key: list('plannedNew', key),
    };

    /// 某原项是否真的已被移入恢复副本。
    bool hasOriginalBackup(String key, String name) =>
        FileSystemEntity.typeSync(
          p.join(_originalsDir(backupRoots[key]!).path, name),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;

    if (inferFromDisk) {
      final stagingPayload = Directory(
        p.join(roots[storageRootKey]!, stagingDirName, 'payload'),
      );
      final state = journal['state'] as String? ?? 'unknown';
      for (final entry in roots.entries) {
        final originals = _originalsDir(backupRoots[entry.key]!);
        if (await originals.exists()) {
          for (final entity in originals.listSync(followLinks: false)) {
            final name = p.basename(entity.path);
            if (!moved[entry.key]!.contains(name)) {
              moved[entry.key]!.add(name);
            }
          }
        }
        // 只有当某新项的原文件已确实在副本里（目标确实被换入）时，才将其
        // 视为需要删除的已换入项。origin 仍在原位 / planned 阶段则保留。
        final base = Directory(entry.value);
        if (await base.exists()) {
          for (final name in plannedNew[entry.key]!) {
            final targetExists =
                FileSystemEntity.typeSync(
                  p.join(base.path, name),
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound;
            final originalTaken = hasOriginalBackup(entry.key, name);
            if (targetExists && originalTaken) {
              if (!installed[entry.key]!.contains(name)) {
                installed[entry.key]!.add(name);
              }
            }
          }
        }
        // 未记录在 moved 中、且尚未移回的原项：如果副本里有，按推断还原。
        for (final name in plannedOrigins[entry.key]!) {
          if (!moved[entry.key]!.contains(name) &&
              hasOriginalBackup(entry.key, name)) {
            moved[entry.key]!.add(name);
          }
        }
        // fresh-only “重命名后未及 journal”的推断：
        // 处于 installing（或之后）、目标存在、暂存 payload 中已无该名、且无
        // 同名原文件入库 → 该目标是刚换入的新项，必须删除（否则回滚会留下它）。
        if (state == 'installing' || state == 'rolling-back') {
          final payloadDir = Directory(p.join(stagingPayload.path, entry.key));
          final payloadNames = <String>{};
          if (await payloadDir.exists()) {
            for (final entity in payloadDir.listSync(followLinks: false)) {
              payloadNames.add(p.basename(entity.path));
            }
          }
          final base = Directory(entry.value);
          if (await base.exists()) {
            for (final entity in base.listSync(followLinks: false)) {
              final name = p.basename(entity.path);
              if (_isTransientTopLevel(name)) continue;
              if (payloadNames.contains(name)) continue;
              if (hasOriginalBackup(entry.key, name)) continue;
              if (!plannedNew[entry.key]!.contains(name)) continue;
              if (!installed[entry.key]!.contains(name)) {
                installed[entry.key]!.add(name);
              }
            }
          }
        }
      }
    }

    // 1) 先删掉已换入的新子项（仅当原文件确实已入库时）。
    for (final entry in installed.entries) {
      final base = Directory(roots[entry.key]!);
      for (final name in entry.value) {
        final isOriginal =
            plannedOrigins[entry.key]!.contains(name) &&
            !hasOriginalBackup(entry.key, name);
        if (isOriginal) continue;
        try {
          await _deleteEntity(p.join(base.path, name));
        } on Object {
          failures.add('${entry.key}/$name');
        }
      }
    }
    // 2) 把恢复副本移回原位（仅移动副本中确实存在的）。
    for (final entry in moved.entries) {
      final base = Directory(roots[entry.key]!);
      final originals = _originalsDir(backupRoots[entry.key]!);
      for (final name in entry.value) {
        final source = p.join(originals.path, name);
        if (FileSystemEntity.typeSync(source, followLinks: false) ==
            FileSystemEntityType.notFound) {
          continue;
        }
        try {
          await _deleteEntity(p.join(base.path, name));
          await _move(_entityFor(source), p.join(base.path, name));
        } on Object {
          failures.add('${entry.key}/$name');
        }
      }
    }
    return failures;
  }

  /// 立即 prepare 并 apply；仅供测试或无活动存储的工具路径使用。
  static Future<AppRestoreResult> importAll(
    Uint8List bytes, {
    AppBackupInfo? current,
    bool allowCrossProduct = false,
  }) async {
    await prepareImport(
      bytes,
      current: current,
      allowCrossProduct: allowCrossProduct,
      replacePending: true,
    );
    final result = await applyPendingRestore();
    if (result == null) {
      throw const AppBackupException('恢复暂存数据丢失，未能应用');
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Path rebasing
  // ---------------------------------------------------------------------------

  /// 重定位 `projects.json` 中位于**旧私有根**下的项目绝对路径。
  ///
  /// 项目注册表保存绝对路径；跨设备/跨沙箱恢复后旧前缀已不存在。这里只改
  /// 那些确实落在归档记录的某个私有根下的路径，改写为对应新根下的相对路径；
  /// 外部引用（例如用户自定义目录）保持原样。
  static Future<void> _rebaseProjectRegistry(
    Directory root,
    AppBackupInfo info,
    Map<String, String> currentRoots,
  ) async {
    final recorded = <String, String>{
      ...info.recordedRoots,
      if (info.recordedRootPath != null) storageRootKey: info.recordedRootPath!,
    };
    if (recorded.isEmpty) return;
    final registry = File(p.join(root.path, projectRegistryFileName));
    if (await registry.exists()) {
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(await registry.readAsString());
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // 损坏的注册表不阻止元数据重定位。
      }
      final projects = data?['projects'];
      if (projects is List &&
          await _rebaseProjectPaths(projects, recorded, currentRoots)) {
        // Write failures must escape to the transaction rollback. Swallowing
        // a truncated write here would commit and delete the original copy.
        await registry.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
          flush: true,
        );
      }
    }
    // FileBackup.listVersions 与回收站通过原路径过滤；不重定位这些元数据会让
    // 导入的历史版本/回收记录全部失效。即使 projects.json 缺失也要执行。
    await _rebaseMetadataJson(root, recorded, currentRoots);
  }

  /// 重定位 `files_backup/**.metadata.json` 与 `recyclebin/**.metadata.json` 里的
  /// `originalPath`。
  static Future<void> _rebaseMetadataJson(
    Directory root,
    Map<String, String> recorded,
    Map<String, String> currentRoots,
  ) async {
    final subDirs = <String>[
      'files_backup',
      p.join('recyclebin', 'projects_bin'),
      p.join('recyclebin', 'files_bin'),
    ];
    for (final sub in subDirs) {
      final dir = Directory(p.join(root.path, sub));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.metadata.json')) {
          continue;
        }
        Map<String, dynamic> data;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map) continue;
          data = Map<String, dynamic>.from(decoded);
        } on Object {
          continue;
        }
        final original = data['originalPath'];
        if (original is! String || original.isEmpty) continue;
        final rebased = _rebasePath(original, recorded, currentRoots);
        if (rebased == null) continue;
        data['originalPath'] = rebased;
        await entity.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
          flush: true,
        );
      }
    }
  }

  /// 把单个绝对路径从某旧根前缀重写到新根；无须重定位时返回 null。
  static String? _rebasePath(
    String path,
    Map<String, String> recorded,
    Map<String, String> currentRoots,
  ) {
    final normalized = p.normalize(path);
    for (final entry in recorded.entries) {
      final from = p.normalize(entry.value);
      if (!p.isWithin(from, normalized) && !p.equals(from, normalized)) {
        continue;
      }
      final to = currentRoots[entry.key];
      if (to == null) continue;
      if (p.equals(from, normalized)) return p.normalize(to);
      return p.normalize(
        p.join(p.normalize(to), p.relative(normalized, from: from)),
      );
    }
    return null;
  }

  /// 把重启后仍在磁盘上的项目路径重定位到新私有根，返回是否发生修改。
  static Future<bool> _rebaseProjectPaths(
    List<dynamic> projects,
    Map<String, String> recorded,
    Map<String, String> currentRoots,
  ) async {
    var changed = false;
    for (final item in projects) {
      if (item is! Map) continue;
      final path = item['path'];
      if (path is! String || path.isEmpty) continue;
      final rebased = _rebasePath(path, recorded, currentRoots);
      if (rebased == null) continue;
      item['path'] = rebased;
      changed = true;
    }
    return changed;
  }

  // ---------------------------------------------------------------------------
  // Entry validation helpers
  // ---------------------------------------------------------------------------

  /// 校验归档内全部数据条目。
  ///
  /// 返回 `(rootKey, relative, kind, bytes, target, mode)`。校验在任何写入之前完成：
  /// - 条目必须属于已知根前缀（`data/` 或 `private_<key>/`）；`data/` 与
  ///   `private_<key>/` 裸标记视为空根标记，安全忽略。
  /// - 拒绝绝对路径、`..` 越界、空路径、重复路径。
  /// - **拒绝符号链接祖先**：任何条目的父路径不能是符号链接。
  /// - 符号链接识别不依赖 `isSymbolicLink`（归档包在 DOS creator 下不识别）：
  ///   直接用 `mode & 0xf000 == 0xa000`（UNIX 链接位）或包已解析的 symbolicLink。
  /// - CRC 校验每个普通成员（包的 `verify` 被注释掉）。
  static List<_ValidatedEntry> _validateEntries(Archive archive) {
    final result = <_ValidatedEntry>[];
    final seen = <String>{};
    final symlinkPaths = <String>{};
    // 第一遍：先收集所有符号链接路径，用于拒绝“链接祖先”。
    for (final member in archive.files) {
      final rawName = member.name.replaceAll('\\', '/');
      if (_isSymlinkEntry(member)) {
        final parsed = _parseEntryName(rawName);
        if (parsed != null) {
          symlinkPaths.add('${parsed.rootKey}/${parsed.relative}');
        }
      }
    }
    for (final member in archive.files) {
      final rawName = member.name.replaceAll('\\', '/');
      if (rawName == infoFileName || rawName == '$infoFileName/') continue;
      // 目录条目名常带尾部 `/`，去掉后再校验（不去空白，保留用户文件名）。
      final stripped = rawName.replaceFirst(RegExp(r'/+$'), '');
      final parsed = _parseEntryName(stripped);
      if (parsed == null) {
        // 裸 `private_<key>/` 空根标记。
        throw AppBackupException('备份包含未知的根条目：$rawName');
      }
      // 裸根目录标记（`data/` 或 `private_<key>/`）：允许，表示该根为空。
      // 空根会在应用时由 payload 目录本身自然保留，不产生条目。
      if (parsed.relative.isEmpty) {
        if (!member.isDirectory &&
            !(rawName.endsWith('/') && member.size == 0)) {
          throw AppBackupException('备份根必须是目录：$rawName');
        }
        if (rawName == dataPrefix ||
            rawName == '$dataPrefix/' ||
            RegExp(r'^private_[^/]+/?$').hasMatch(rawName)) {
          if (!seen.add('${parsed.rootKey}/')) {
            throw AppBackupException('备份包含重复根：${parsed.rootKey}');
          }
          result.add(
            _ValidatedEntry(
              rootKey: parsed.rootKey,
              path: '',
              kind: _EntryKind.directory,
            ),
          );
          continue;
        }
        throw AppBackupException('备份包含非法路径：$rawName');
      }
      final validated = _validateRelative(parsed.relative);
      if (_isTransientTopLevel(validated.split('/').first)) {
        throw AppBackupException('备份包含保留的控制路径：$rawName');
      }
      final key = '${parsed.rootKey}/$validated';
      if (!seen.add(key)) {
        throw AppBackupException('备份包含重复路径：$validated');
      }
      // 拒绝符号链接祖先：父目录不得是链接。
      final segments = validated.split('/');
      for (var i = 1; i < segments.length; i++) {
        final ancestor =
            '${parsed.rootKey}/${segments.sublist(0, i).join('/')}';
        if (symlinkPaths.contains(ancestor)) {
          throw AppBackupException('备份条目位于符号链接之下：$validated');
        }
      }

      final isDirectory =
          member.isDirectory || rawName.endsWith('/') || stripped.isEmpty;
      if (_isSymlinkEntry(member)) {
        _verifyCrc(member, validated, member.content);
        final rawTarget = member.isSymbolicLink
            ? (member.symbolicLink ?? '')
            : utf8.decode(member.content, allowMalformed: true);
        if (rawTarget.isEmpty || rawTarget.contains('\u0000')) {
          throw AppBackupException('备份包含非法符号链接：$validated');
        }
        // Link targets are data, never extraction destinations. Runtime trees
        // commonly contain ../ links; preserve their exact text as on export.
        final target = rawTarget;
        result.add(
          _ValidatedEntry(
            rootKey: parsed.rootKey,
            path: validated,
            kind: _EntryKind.symlink,
            target: target,
          ),
        );
        continue;
      }
      if (isDirectory) {
        result.add(
          _ValidatedEntry(
            rootKey: parsed.rootKey,
            path: validated,
            kind: _EntryKind.directory,
            mode: member.mode,
          ),
        );
        continue;
      }
      result.add(
        _ValidatedEntry(
          rootKey: parsed.rootKey,
          path: validated,
          kind: _EntryKind.file,
          member: member,
          mode: member.mode,
        ),
      );
    }
    return result;
  }

  /// 是否为符号链接条目。
  ///
  /// 归档包只在 UNIX creator 下设置 `symbolicLink`；对 DOS creator 的链接，
  /// 按 `mode & 0xf000 == 0xa000` 自行判断。
  static bool _isSymlinkEntry(ArchiveFile member) =>
      member.isSymbolicLink || (member.mode & 0xf000) == 0xa000;

  /// 从归档条目名解析根名与相对路径。
  static ({String rootKey, String relative})? _parseEntryName(String name) {
    if (name == dataPrefix || name.startsWith('$dataPrefix/')) {
      return (
        rootKey: storageRootKey,
        relative: name.length <= dataPrefix.length
            ? ''
            : name.substring(dataPrefix.length + 1),
      );
    }
    const extra = 'private_';
    if (name.startsWith(extra)) {
      final rest = name.substring(extra.length);
      final slash = rest.indexOf('/');
      if (slash == -1 && rest.isNotEmpty) {
        return (rootKey: rest, relative: '');
      }
      if (slash <= 0) return null;
      final rootKey = rest.substring(0, slash);
      if (rootKey.isEmpty) return null;
      return (rootKey: rootKey, relative: rest.substring(slash + 1));
    }
    return null;
  }

  /// 校验单个成员的 CRC（包内置校验已注释）。
  static void _verifyCrc(
    ArchiveFile member,
    String validated,
    Uint8List bytes,
  ) {
    final expected = member.crc32;
    if (expected == null) return;
    if (getCrc32(bytes) != expected) {
      throw AppBackupException('备份文件校验失败（CRC）：$validated');
    }
  }

  /// 相对路径校验；**不做 trim**，保留用户文件名原样。
  ///
  /// 拒绝：绝对路径、盘符/UNC/冒号路径（任意宿主）、空路径、空组件、`.`、
  /// `..` 与任意形式的越界。每个组件都校验，因此 `data/link/./child` 不会
  /// 绕过符号链接祖先检查（`.` 也被拒）。
  static String _validateRelative(String value) {
    final relative = _normalize(value);
    if (relative.isEmpty || relative == '.') {
      throw AppBackupException('备份包含非法路径：$value');
    }
    // 绝对路径 / 盘符 / UNC / 冒号（Windows 与 POSIX 均拒）。
    if (relative.startsWith('/') ||
        p.isAbsolute(relative) ||
        relative.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relative) ||
        relative.contains(':') ||
        relative.contains('\u0000')) {
      throw AppBackupException('备份包含非法路径：$value');
    }
    final parts = relative.split('/');
    for (final part in parts) {
      if (part.isEmpty || part == '.' || part == '..') {
        throw AppBackupException('备份包含非法路径：$value');
      }
    }
    return relative;
  }

  /// 解码归档，并在合并前拒绝**原始**重复名（包会合并同名条目）。
  static Archive _decodeArchive(Uint8List bytes) {
    if (bytes.isEmpty) throw const AppBackupException('备份文件为空');
    final decoder = ZipDecoder();
    Archive archive;
    try {
      archive = decoder.decodeBytes(bytes);
    } on Object {
      throw const AppBackupException('备份不是有效的 ZIP 归档');
    }
    final rawSeen = <String>{};
    for (final header in decoder.directory.fileHeaders) {
      final normalized = header.filename.replaceAll('\\', '/');
      if (!rawSeen.add(normalized)) {
        throw AppBackupException('备份包含重复路径：$normalized');
      }
    }
    return archive;
  }

  static ArchiveFile? _findEntry(Archive archive, String name) {
    for (final entry in archive.files) {
      if (entry.name.replaceAll('\\', '/') == name) return entry;
    }
    return null;
  }

  static Map<String, dynamic> _decodeJson(ArchiveFile entry, String name) {
    final text = utf8.decode(entry.content, allowMalformed: true);
    try {
      final value = jsonDecode(text);
      if (value is! Map) throw const FormatException();
      return Map<String, dynamic>.from(value);
    } on Object {
      throw AppBackupException('$name 不是合法 JSON');
    }
  }

  static bool _isTransientTopLevel(String name) =>
      name == stagingDirName ||
      name == oldDirName ||
      name.startsWith('.qfli-app-old-') ||
      name.startsWith('.qfli-restore-') ||
      name.startsWith('.qfli-project-registry-') ||
      name.startsWith('.qfli_write_probe');

  static FileSystemEntity _entityFor(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    return switch (type) {
      FileSystemEntityType.directory => Directory(path),
      FileSystemEntityType.link => Link(path),
      _ => File(path),
    };
  }

  static Future<void> _deleteEntity(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.notFound:
        return;
      default:
        await File(path).delete();
    }
  }

  static Future<void> _move(FileSystemEntity entity, String target) async {
    final override = moveOverride;
    if (override != null) {
      await override(entity.path, target);
    }
    await _moveEntity(entity, target);
  }

  static Future<void> _moveEntity(
    FileSystemEntity entity,
    String target,
  ) async {
    await Directory(p.dirname(target)).create(recursive: true);
    await entity.rename(target);
  }

  static Future<void> _safeDelete(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // 清理失败不应覆盖真实的导入结果。
    }
  }

  static Future<void> _applyMode(String path, int mode) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', [
      (mode & 0x1ff).toRadixString(8),
      path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('无法恢复文件权限：${result.stderr}', path);
    }
  }

  static String _normalize(String value) => value.replaceAll(r'\', '/');
}

/// 备份条目类型。
///
/// 导出时保真：空目录、普通文件与符号链接各有专属类型，不静默丢弃。
enum _EntryKind { file, directory, symlink }

/// 校验后的归档条目。
@immutable
class _ValidatedEntry {
  const _ValidatedEntry({
    required this.rootKey,
    required this.path,
    required this.kind,
    this.member,
    this.target,
    this.mode,
  });

  final String rootKey;
  final String path;
  final _EntryKind kind;
  final ArchiveFile? member;
  final String? target;
  final int? mode;
}
