// 外部文件夹：iOS 与 Mac 的系统授权目录。
//
// 原生持有安全作用域书签。Dart 只拿到不透明 id 与解析后的路径。
// 这里管三条边界：选择、恢复、释放。协调读写与列目录走同一个通道。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 一个已授权的外部文件夹。
class ExternalFolder {
  const ExternalFolder({
    required this.id,
    required this.name,
    required this.path,
  });

  /// 原生书签表的键。与 Android SAF 的 `uri` 同位。
  final String id;
  final String name;

  /// 当前解析出的绝对路径。重启后可能变化。
  final String path;

  @override
  String toString() => 'ExternalFolder($id, $name, $path)';
}

/// 外部文件夹里的一条目录记录。
class ExternalFolderEntry {
  const ExternalFolderEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.downloaded,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;

  /// iCloud 占位文件为 false。读取会先触发下载。
  final bool downloaded;
}

abstract final class ExternalFolderService {
  static const MethodChannel _channel = MethodChannel('qflistudio/platform');

  /// 已授权的根：文件夹 id → 规范化路径。
  static final Map<String, String> _rootByFolder = <String, String>{};

  static bool? _available;

  /// 测试钩子：绕过平台判定。
  static bool debugAssumeSupported = false;

  /// iOS 与 Mac 为 true。其它平台为 false。
  static bool get supported =>
      debugAssumeSupported || (!kIsWeb && (Platform.isIOS || Platform.isMacOS));

  /// 握手一次并缓存。通道缺失时返回 false。
  ///
  /// macOS 上的单元测试宿主也叫 Mac。没有原生处理器时这里必须安静返回，
  /// 否则现有测试会多出一条未实现的通道错误。
  static Future<bool> ensureAvailable() async {
    if (!supported) return false;
    final cached = _available;
    if (cached != null) return cached;
    try {
      await _channel.invokeListMethod<Object?>('resolveFolders');
      _available = true;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // 方法存在，运行期失败不算不可用。
      _available = true;
    }
    return _available ?? false;
  }

  /// 弹系统文件夹选择器。用户取消或平台不支持时返回 null。
  static Future<ExternalFolder?> pick() async {
    if (!await ensureAvailable()) return null;
    final raw = await _channel.invokeMethod<Object?>('pickFolder');
    final folder = folderFrom(raw);
    if (folder != null) adopt(folder);
    return folder;
  }

  /// 解析全部已存书签。过期书签由原生续期。
  static Future<List<ExternalFolder>> restore() async {
    if (!await ensureAvailable()) return const <ExternalFolder>[];
    final raw = await _channel.invokeListMethod<Object?>('resolveFolders');
    final folders = <ExternalFolder>[];
    for (final item in raw ?? const <Object?>[]) {
      final folder = folderFrom(item);
      if (folder != null) folders.add(folder);
    }
    _rootByFolder.clear();
    for (final folder in folders) {
      adopt(folder);
    }
    return folders;
  }

  /// 释放一个根：原生停掉安全作用域，Dart 忘了它。
  static Future<void> release(String id) async {
    if (id.isEmpty) return;
    _rootByFolder.remove(id);
    if (!await ensureAvailable()) return;
    await _channel.invokeMethod<Object?>('releaseFolder', {'id': id});
  }

  /// 列出目录。占位文件也在结果里，`downloaded` 为 false。
  static Future<List<ExternalFolderEntry>> list(String directoryPath) async {
    if (!await ensureAvailable()) {
      throw StateError('当前平台不支持外部文件夹');
    }
    final raw = await _channel.invokeListMethod<Object?>('folderList', {
      'path': directoryPath,
    });
    final entries = <ExternalFolderEntry>[];
    for (final item in raw ?? const <Object?>[]) {
      final entry = entryFrom(item);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// 协调读取。iCloud 占位文件先下载再读。
  static Future<Uint8List> read(String path) async {
    final raw = await _channel.invokeMethod<Object?>('coordinatedRead', {
      'path': path,
    });
    if (raw is Uint8List) return raw;
    if (raw is List) return Uint8List.fromList(raw.cast<int>());
    throw StateError('外部文件夹未返回文件内容');
  }

  /// 协调写入。原子替换，与其它应用互斥。
  static Future<void> write(String path, Uint8List bytes) async {
    await _channel.invokeMethod<void>('coordinatedWrite', {
      'path': path,
      'bytes': bytes,
    });
  }

  /// 登记本进程内的外部根。选择与恢复后调用。
  static void adopt(ExternalFolder folder) {
    final root = normalize(folder.path);
    if (root.isEmpty) return;
    _rootByFolder[folder.id] = root;
  }

  static bool isExternal(String path) => _ownerOf(path) != null;

  /// 路径所属的文件夹 id；不在任何根内时为 null。
  static String? folderIdOf(String path) => _ownerOf(path);

  static String? _ownerOf(String path) {
    if (_rootByFolder.isEmpty) return null;
    final target = normalize(path);
    for (final entry in _rootByFolder.entries) {
      final root = entry.value;
      if (target == root || p.isWithin(root, target)) return entry.key;
    }
    return null;
  }

  static String normalize(String path) {
    if (path.isEmpty) return path;
    final absolute = p.isAbsolute(path) ? path : p.absolute(path);
    return p.normalize(absolute);
  }

  /// 解析通道返回值。缺 id 或缺路径的记录按无效丢弃。
  static ExternalFolder? folderFrom(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String? ?? '';
    final path = raw['path'] as String? ?? '';
    if (id.isEmpty || path.isEmpty) return null;
    return ExternalFolder(
      id: id,
      name: raw['name'] as String? ?? p.basename(path),
      path: path,
    );
  }

  static ExternalFolderEntry? entryFrom(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'] as String? ?? '';
    if (path.isEmpty) return null;
    return ExternalFolderEntry(
      name: raw['name'] as String? ?? p.basename(path),
      path: path,
      isDirectory: raw['isDirectory'] as bool? ?? false,
      size: (raw['size'] as num?)?.toInt() ?? 0,
      downloaded: raw['downloaded'] as bool? ?? true,
    );
  }

  /// 测试钩子：清空登记与握手缓存。
  @visibleForTesting
  static void resetForTesting() {
    _rootByFolder.clear();
    _available = null;
    debugAssumeSupported = false;
  }
}
