import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'file_backup.dart';
import 'recycle_bin.dart';

enum RecoveryKind { projects, files, backups, history }

class RecoveryEntry {
  const RecoveryEntry({
    required this.file,
    required this.name,
    required this.time,
    required this.size,
    required this.archive,
    this.originalPath,
    this.projectName,
    this.language = '',
    this.type = '',
  });

  final File file;
  final String name;
  final DateTime time;
  final int size;
  final bool archive;
  final String? originalPath;
  final String? projectName;
  final String language;
  final String type;

  String get groupKey => originalPath ?? '${projectName ?? ''}/$name';
}

abstract final class RecoveryService {
  static Future<List<RecoveryEntry>> list(RecoveryKind kind) async {
    final recycle = kind == RecoveryKind.projects || kind == RecoveryKind.files;
    final directory = recycle
        ? await RecycleBin.directory(
            kind == RecoveryKind.projects
                ? RecycleBin.projectsBin
                : RecycleBin.filesBin,
          )
        : await FileBackup.directory();
    if (!await directory.exists()) return [];
    final entries = <RecoveryEntry>[];
    await for (final entity in directory.list(
      recursive: !recycle,
      followLinks: false,
    )) {
      if (entity is! File || entity.path.endsWith('.metadata.json')) continue;
      if (recycle && p.extension(entity.path).toLowerCase() != '.zip') continue;
      Map<String, dynamic> metadata = {};
      final metadataFile = File('${entity.path}.metadata.json');
      if (await metadataFile.exists()) {
        try {
          metadata =
              jsonDecode(await metadataFile.readAsString())
                  as Map<String, dynamic>;
        } catch (_) {}
      }
      final stat = await entity.stat();
      final basename = p.basename(entity.path);
      final inferredName = recycle
          ? basename.replaceFirst(RegExp(r'-\d{8}-\d{6}(?:-\d+)?\.zip$'), '')
          : basename.replaceFirst(
              RegExp(r'-\d{8}-\d{6}-\d{3}(?:-\d+)?(?=\.[^.]+$|$)'),
              '',
            );
      entries.add(
        RecoveryEntry(
          file: entity,
          name: metadata['name'] as String? ?? inferredName,
          language: metadata['language'] is String
              ? metadata['language'] as String
              : '',
          type: metadata['type'] is String ? metadata['type'] as String : '',
          originalPath: metadata['originalPath'] as String?,
          projectName:
              metadata['projectName'] as String? ??
              (recycle ? null : p.basename(p.dirname(entity.path))),
          time:
              DateTime.tryParse(metadata['time'] as String? ?? '') ??
              stat.modified,
          size: stat.size,
          archive: recycle,
        ),
      );
    }
    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }

  static Future<String> preview(RecoveryEntry entry) async {
    if (entry.archive) {
      final archive = ZipDecoder().decodeBytes(await entry.file.readAsBytes());
      return archive.files.map((file) => file.name).join('\n');
    }
    final handle = await entry.file.open();
    try {
      return utf8.decode(await handle.read(256 * 1024), allowMalformed: true);
    } finally {
      await handle.close();
    }
  }

  static Future<void> restore(RecoveryEntry entry, String destination) async {
    if (!p.isAbsolute(destination)) {
      throw const FileSystemException('恢复位置必须是绝对路径');
    }
    final target = p.normalize(destination);
    if (entry.archive) {
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('恢复位置已存在，请选择其他位置');
      }
      final archive = ZipDecoder().decodeBytes(await entry.file.readAsBytes());
      if (archive.files.isEmpty) throw const FormatException('回收记录为空');
      final rootNames = archive.files
          .map((file) => file.name.replaceAll('\\', '/').split('/').first)
          .toSet();
      if (rootNames.length != 1 || rootNames.single.isEmpty) {
        throw const FormatException('回收记录目录结构无效');
      }
      final base = await AppPaths.storageDirectory();
      if (base == null) throw const FileSystemException('未找到应用数据目录');
      final staging = await Directory(base).createTemp('.qfli-restore-');
      try {
        for (final member in archive.files) {
          final normalized = member.name.replaceAll('\\', '/');
          final full = p.normalize(p.join(staging.path, normalized));
          if (p.isAbsolute(normalized) ||
              !p.isWithin(staging.path, full) ||
              member.isSymbolicLink) {
            throw const FormatException('回收记录包含非法路径');
          }
          if (member.isFile) {
            await Directory(p.dirname(full)).create(recursive: true);
            await File(full).writeAsBytes(member.content);
          } else {
            await Directory(full).create(recursive: true);
          }
        }
        final source = p.join(staging.path, rootNames.single);
        await Directory(p.dirname(target)).create(recursive: true);
        final entity = await FileSystemEntity.type(source);
        if (entity == FileSystemEntityType.directory) {
          await _copyDirectory(Directory(source), Directory(target));
        } else {
          await File(source).copy(target);
        }
      } finally {
        await staging.delete(recursive: true);
      }
    } else {
      if (p.equals(target, entry.file.absolute.path)) {
        throw const FileSystemException('不能覆盖备份本身');
      }
      final original = File(target);
      if (await original.exists()) {
        final error = await FileBackup.backupBeforeOverwrite(
          original,
          projectName: entry.projectName ?? '恢复文件',
        );
        if (error != null) throw FileSystemException(error);
      }
      await Directory(p.dirname(target)).create(recursive: true);
      await entry.file.copy(target);
    }
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final output = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(output));
      } else if (entity is File) {
        await entity.copy(output);
      }
    }
  }

  static Future<void> delete(RecoveryEntry entry) async {
    await entry.file.delete();
    final metadata = File('${entry.file.path}.metadata.json');
    if (await metadata.exists()) await metadata.delete();
  }
}
