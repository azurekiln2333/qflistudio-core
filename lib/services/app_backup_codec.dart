import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// File streams keep a large private tree out of the UI isolate and avoid
/// retaining every uncompressed project/runtime file in memory at once.
abstract final class AppBackupCodec {
  static Future<Map<String, dynamic>> exportFile({
    required Map<String, String> roots,
    required Map<String, dynamic> info,
    required String destination,
  }) => Isolate.run(() async {
    for (final root in roots.values) {
      if (p.equals(root, destination) || p.isWithin(root, destination)) {
        throw const FileSystemException('备份输出不能位于被备份的数据目录内');
      }
    }
    final entries = <({FileSystemEntity entity, String name})>[];
    Future<void> collect(
      Directory directory,
      String prefix, {
      bool top = false,
    }) async {
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (top && _transient(name)) continue;
        final archiveName = '$prefix/$name';
        entries.add((entity: entity, name: archiveName));
        if (entity is Directory) await collect(entity, archiveName);
      }
    }

    for (final entry in roots.entries) {
      final prefix = entry.key == 'storage' ? 'data' : 'private_${entry.key}';
      entries.add((entity: Directory(entry.value), name: prefix));
      await collect(Directory(entry.value), prefix, top: true);
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    final metadata = <String, dynamic>{
      ...info,
      'recordedRoots': roots,
      'recordedRootPath': roots['storage'],
      'fileCount': entries.where((entry) => entry.entity is! Directory).length,
    };
    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      encoder.create(destination, level: DeflateLevel.defaultCompression);
      opened = true;
      encoder.addArchiveFile(
        ArchiveFile.string(
          'app_info.json',
          const JsonEncoder.withIndent('  ').convert(metadata),
        ),
      );
      for (final entry in entries) {
        final entity = entry.entity;
        if (entity is File) {
          await encoder.addFile(entity, entry.name);
        } else if (entity is Directory) {
          final member = ArchiveFile.directory('${entry.name}/');
          if (await entity.exists()) {
            final stat = await entity.stat();
            member.mode = stat.mode;
            member.lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000;
          }
          encoder.addArchiveFile(member);
        } else if (entity is Link) {
          // archive's ZIP encoder does not serialize ArchiveFile.symlink's
          // target. Store the standard Unix link payload and type bits.
          encoder.addArchiveFile(
            ArchiveFile.string(entry.name, await entity.target())
              ..mode = 0xa1ff,
          );
        } else {
          throw FileSystemException('不支持备份此文件类型', entity.path);
        }
      }
      await encoder.close();
      opened = false;
      return metadata;
    } catch (_) {
      if (opened) {
        try {
          await encoder.close();
        } catch (_) {
          // Preserve the original archive/write error.
        }
      }
      try {
        await File(destination).delete();
      } catch (_) {
        // The output may not have been created.
      }
      rethrow;
    }
  });

  static bool _transient(String name) =>
      name == '.qfli-app-restore' ||
      name == '.qfli-app-old' ||
      name.startsWith('.qfli-app-old-') ||
      name.startsWith('.qfli-restore-') ||
      name.startsWith('.qfli_write_probe') ||
      name.startsWith('.qfli-project-registry-');
}
