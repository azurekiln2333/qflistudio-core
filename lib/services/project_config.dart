import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 项目级配置文件：`<项目根>/.qfli/project.json`。
///
/// Names and source-language metadata travel with the project; directory
/// suffixes never become its display name.
abstract final class ProjectConfig {
  static const String dirName = '.qfli';
  static const String fileName = 'project.json';

  static String configPath(String projectRoot) =>
      p.join(projectRoot, dirName, fileName);

  /// 读取完整配置；文件不存在或内容损坏返回 null。
  static Map<String, dynamic>? read(String projectRoot) {
    try {
      final file = File(configPath(projectRoot));
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync());
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  static ({String? name, String? language, String? type}) metadataFromJson(
    Map<String, dynamic>? data,
  ) {
    String? value(String key) {
      final raw = data?[key];
      return raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    }

    return (
      name: value('name'),
      language: value('language'),
      type: value('type'),
    );
  }

  static ({String? name, String? language, String? type}) readMetadata(
    String projectRoot,
  ) => metadataFromJson(read(projectRoot));

  static String? readName(String projectRoot) => readMetadata(projectRoot).name;

  /// 读取语言标注；缺失返回 null。
  static String? readLanguage(String projectRoot) =>
      readMetadata(projectRoot).language;

  static String? readType(String projectRoot) => readMetadata(projectRoot).type;

  /// Merge metadata; strict creation/import reports failures to the caller.
  static Future<void> write({
    required String projectRoot,
    required String name,
    required String language,
    String type = '',
    String? entryFile,
    bool strict = false,
  }) async {
    try {
      final existing = read(projectRoot) ?? <String, dynamic>{};
      existing['version'] = 1;
      existing['name'] = name;
      existing['language'] = language;
      if (type.isNotEmpty) existing['type'] = type;
      if (entryFile != null) existing['entryFile'] = entryFile;
      if (!existing.containsKey('createdAt')) {
        existing['createdAt'] = DateTime.now().toIso8601String();
      }
      final file = File(configPath(projectRoot));
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(existing),
        flush: true,
      );
    } catch (_) {
      if (strict) rethrow;
      // 配置写入失败不影响项目本身。
    }
  }
}
