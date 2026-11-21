import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/cloud_project.dart';

/// One portable path policy shared by remote downloads and editor pushes.
abstract final class CloudCachePaths {
  static String relative(String value) {
    if (value.isEmpty ||
        value.length > 4096 ||
        value.contains(r'\') ||
        value.startsWith('/') ||
        RegExp(r'[\x00-\x1f\x7f:]').hasMatch(value)) {
      throw const CloudOperationException('path', '云端文件路径无效');
    }
    for (final segment in value.split('/')) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.endsWith('.') ||
          segment.endsWith(' ') ||
          RegExp(r'[<>"|?*]').hasMatch(segment) ||
          RegExp(
            r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
            caseSensitive: false,
          ).hasMatch(segment)) {
        throw const CloudOperationException('path', '云端文件路径无效');
      }
    }
    return value;
  }

  static String resolve(String root, String relativePath) {
    final path = p.normalize(p.join(root, relative(relativePath)));
    if (!p.isWithin(p.absolute(root), p.absolute(path))) {
      throw const CloudOperationException('path', '文件越出云端缓存目录');
    }
    return path;
  }

  /// Reject links in every existing ancestor, including the configured root.
  static void noLinks(String path) {
    var current = p.absolute(path);
    while (true) {
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const CloudOperationException('link', '云端缓存路径包含链接');
      }
      final parent = p.dirname(current);
      if (p.equals(parent, current)) break;
      current = parent;
    }
  }

  static void directory(String path) {
    noLinks(path);
    Directory(path).createSync(recursive: true);
    noLinks(path);
  }

  static void regularFile(String path) {
    noLinks(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const CloudOperationException('manifest', '缓存文件缺失或不是普通文件');
    }
  }
}
