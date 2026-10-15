import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves only provider-owned durable directories, never a shared fallback.
abstract final class AppPrivateRoots {
  static Future<Map<String, String>> resolve(String storagePath) async {
    Future<String?> read(Future<Directory> Function() getter) async {
      try {
        final directory = await getter().timeout(const Duration(seconds: 2));
        return p.normalize(p.absolute(directory.path));
      } catch (_) {
        return null;
      }
    }

    final mobile = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.ohos ||
      TargetPlatform.iOS => true,
      _ => false,
    };
    final support = await read(getApplicationSupportDirectory);
    // Desktop Documents belongs to the user, not the application.
    final documents = mobile
        ? await read(getApplicationDocumentsDirectory)
        : null;
    if (mobile && (support == null || documents == null)) {
      throw const FileSystemException('无法完整读取应用私有数据目录，请稍后重试');
    }
    final storage = p.normalize(p.absolute(storagePath));
    if (!p.equals(storage, support ?? '') &&
        !p.equals(storage, documents ?? '')) {
      throw const FileSystemException('无法确认应用私有数据目录');
    }
    final roots = <String, String>{'storage': storage};
    for (final entry in {'support': support, 'documents': documents}.entries) {
      final path = entry.value;
      if (path == null ||
          roots.values.any(
            (root) => p.equals(root, path) || p.isWithin(root, path),
          )) {
        continue;
      }
      if (roots.values.any((root) => p.isWithin(path, root))) {
        throw const FileSystemException('应用私有目录布局不受支持');
      }
      roots[entry.key] = path;
    }
    return roots;
  }
}
