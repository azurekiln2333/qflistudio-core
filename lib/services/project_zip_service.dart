import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import 'project_config.dart';

class ProjectZipException implements Exception {
  const ProjectZipException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A .qsz file is a normal ZIP of the project's relative files and directories.
/// Filesystem traversal, compression and extraction run outside the UI isolate.
abstract final class ProjectZipService {
  static Future<void> exportToFile(Project project, String destination) {
    final source = project.path;
    final metadata = _metadata(project);
    return Isolate.run(() => _export(source, destination, metadata));
  }

  /// Used by native document providers that accept bytes rather than a path.
  static Future<Uint8List> exportProject(Project project) {
    final source = project.path;
    final metadata = _metadata(project);
    return Isolate.run(() async {
      final temporary = await Directory.systemTemp.createTemp('qfli-qsz-');
      try {
        final file = File(p.join(temporary.path, 'project.qsz'));
        await _export(source, file.path, metadata);
        return await file.readAsBytes();
      } finally {
        await temporary.delete(recursive: true);
      }
    });
  }

  static Map<String, String> _metadata(Project project) => {
    'name': project.name,
    'language': project.language,
    'type': project.type,
  };

  /// Returns a newly created directory owned by this import only. The store
  /// registers it after metadata preparation and removes it if persistence fails.
  static Future<String> restoreProject(
    Uint8List bytes, {
    required String projectsRoot,
  }) => Isolate.run(() async {
    Directory? created;
    try {
      final members = _readMembers(bytes);
      final root = Directory(projectsRoot);
      await root.create(recursive: true);
      created = await root.createTemp('import_');
      for (final member in members) {
        final target = p.joinAll([created.path, ...member.path.split('/')]);
        if (member.isDirectory) {
          await Directory(target).create(recursive: true);
        } else {
          final file = File(target);
          await file.parent.create(recursive: true);
          final output = OutputFileStream(target);
          try {
            member.header.file!.decompress(output);
          } finally {
            await output.close();
          }
          var size = 0;
          var crc = 0;
          await for (final chunk in file.openRead()) {
            size += chunk.length;
            crc = getCrc32(chunk, crc);
          }
          if (size != member.header.uncompressedSize ||
              crc != member.header.crc32) {
            throw ProjectZipException('项目压缩包文件校验失败：${member.path}');
          }
          await _restoreMode(file, member.header.externalFileAttributes >> 16);
        }
      }
      await _sanitizeConfig(created.path);
      return created.path;
    } catch (error) {
      if (created != null) {
        try {
          await created.delete(recursive: true);
        } on FileSystemException {
          // Keep the original import failure.
        }
      }
      if (error is ProjectZipException || error is FileSystemException) rethrow;
      throw const ProjectZipException('不是有效的项目 ZIP 压缩包，或压缩包已损坏');
    }
  });

  static Future<void> _export(
    String source,
    String destination,
    Map<String, String> metadata,
  ) async {
    final root = Directory(source);
    if (!await root.exists()) {
      throw const ProjectZipException('项目目录不存在');
    }
    final sourceRoot = await root.resolveSymbolicLinks();
    final output = File(p.absolute(destination));
    final outputType = await FileSystemEntity.type(
      output.path,
      followLinks: false,
    );
    if (outputType != FileSystemEntityType.notFound &&
        outputType != FileSystemEntityType.file) {
      throw const ProjectZipException('请选择普通文件作为项目导出位置');
    }
    await output.parent.create(recursive: true);
    final outputPath = p.join(
      await output.parent.resolveSymbolicLinks(),
      p.basename(output.path),
    );
    final entries = <({FileSystemEntity entity, String name})>[];
    await for (final entity in Directory(
      sourceRoot,
    ).list(recursive: true, followLinks: false)) {
      // The selected output is the only project payload excluded from export.
      if (p.equals(entity.path, outputPath)) continue;
      final relative = _relative(p.relative(entity.path, from: sourceRoot));
      if (entity is Link) {
        throw ProjectZipException('项目包含符号链接，请先处理后再导出：$relative');
      }
      if (entity is! File && entity is! Directory) {
        throw ProjectZipException('项目包含不支持的文件类型：$relative');
      }
      entries.add((entity: entity, name: relative));
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    final configName = '${ProjectConfig.dirName}/${ProjectConfig.fileName}';
    final hasConfig = entries.any((entry) => entry.name == configName);
    if (!hasConfig &&
        entries.any(
          (entry) =>
              entry.name == ProjectConfig.dirName && entry.entity is File,
        )) {
      throw const ProjectZipException('项目的 .qfli 配置目录被同名文件占用');
    }
    // Create this after traversal so a destination inside the project cannot
    // recursively include the archive currently being written.
    final temporary = await output.parent.createTemp('.qfli-qsz-export-');
    final staged = File(p.join(temporary.path, 'project.qsz'));
    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      encoder.create(staged.path, level: DeflateLevel.defaultCompression);
      opened = true;
      for (final entry in entries) {
        final entity = entry.entity;
        // Refuse a link substituted after the initial traversal, too.
        if (await FileSystemEntity.type(entity.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw ProjectZipException('项目包含符号链接：${entry.name}');
        }
        if (entity is File) {
          await encoder.addFile(entity, entry.name);
        } else {
          final stat = await entity.stat();
          encoder.addArchiveFile(
            ArchiveFile.directory('${entry.name}/')
              ..mode = stat.mode
              ..lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000,
          );
        }
      }
      if (!hasConfig) {
        encoder.addArchiveFile(
          ArchiveFile.string(
            configName,
            jsonEncode({'version': 1, ...metadata}),
          ),
        );
      }
      await encoder.close();
      opened = false;
      await staged.rename(output.path);
    } finally {
      if (opened) {
        try {
          await encoder.close();
        } catch (_) {
          // Preserve the source or destination error.
        }
      }
      await temporary.delete(recursive: true);
    }
  }

  static List<_ZipMember> _readMembers(Uint8List bytes) {
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.filePosition < 0 ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.totalCentralDirectoryEntriesOnThisDisk !=
            directory.totalCentralDirectoryEntries ||
        directory.fileHeaders.length !=
            directory.totalCentralDirectoryEntries ||
        directory.centralDirectoryOffset + directory.centralDirectorySize >
            directory.filePosition ||
        directory.filePosition +
                22 +
                ByteData.sublistView(
                  bytes,
                ).getUint16(directory.filePosition + 20, Endian.little) !=
            bytes.length) {
      throw const ProjectZipException('不是完整的项目 ZIP 压缩包');
    }
    final members = <_ZipMember>[];
    final explicit = <String>{};
    final nodes = <String, ({String path, bool directory})>{};
    final data = ByteData.sublistView(bytes);
    for (final header in directory.fileHeaders) {
      final file = header.file;
      final offset = header.localHeaderOffset;
      if (file == null ||
          offset < 0 ||
          offset + 30 > directory.centralDirectoryOffset ||
          data.getUint32(offset, Endian.little) != ZipFile.zipSignature ||
          file.filename != header.filename ||
          data.getUint16(offset + 8, Endian.little) !=
              header.compressionMethod ||
          offset +
                  30 +
                  data.getUint16(offset + 26, Endian.little) +
                  data.getUint16(offset + 28, Endian.little) +
                  header.compressedSize >
              directory.centralDirectoryOffset) {
        throw const ProjectZipException('项目压缩包文件头不一致');
      }
      if ((header.generalPurposeBitFlag & 1) != 0 || (file.flags & 1) != 0) {
        throw const ProjectZipException('暂不支持加密的项目压缩包');
      }
      if (header.compressionMethod != 0 &&
          header.compressionMethod != 8 &&
          header.compressionMethod != 12) {
        throw const ProjectZipException('项目压缩包使用了不支持的压缩方式');
      }
      final mode = (header.externalFileAttributes >> 16) & 0xf000;
      if (mode != 0 && mode != 0x8000 && mode != 0x4000) {
        throw ProjectZipException('项目压缩包包含链接或特殊文件：${header.filename}');
      }
      final normalized = header.filename.replaceAll(r'\', '/');
      final isDirectory = normalized.endsWith('/') || mode == 0x4000;
      final path = _relative(
        normalized.endsWith('/')
            ? normalized.substring(0, normalized.length - 1)
            : normalized,
      );
      if (isDirectory && (header.uncompressedSize != 0 || header.crc32 != 0)) {
        throw ProjectZipException('项目压缩包目录内容无效：$path');
      }
      final key = path.toLowerCase();
      if (!explicit.add(key)) {
        throw ProjectZipException('项目压缩包包含重复或大小写冲突的路径：$path');
      }
      final parts = path.split('/');
      for (var index = 1; index <= parts.length; index++) {
        final prefix = parts.take(index).join('/');
        final prefixKey = prefix.toLowerCase();
        final prefixIsDirectory = index < parts.length || isDirectory;
        final existing = nodes[prefixKey];
        if (existing != null &&
            (existing.path != prefix ||
                existing.directory != prefixIsDirectory)) {
          throw ProjectZipException('项目压缩包路径或文件目录冲突：$path');
        }
        nodes[prefixKey] = (path: prefix, directory: prefixIsDirectory);
      }
      members.add(_ZipMember(header, path, isDirectory));
    }
    return members;
  }

  static String _relative(String value) {
    final path = value.replaceAll(r'\', '/');
    final parts = path.split('/');
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains(':') ||
        path.contains('\u0000') ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.endsWith(' ') ||
              part.endsWith('.') ||
              RegExp(r'[<>"|?*\x00-\x1f]').hasMatch(part) ||
              RegExp(
                r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                caseSensitive: false,
              ).hasMatch(part),
        )) {
      throw ProjectZipException('项目压缩包包含不安全的路径：$value');
    }
    return path;
  }

  static Future<void> _sanitizeConfig(String root) async {
    final config = ProjectConfig.read(root);
    if (config == null) return;
    for (final key in ['id', 'path', 'cloudId', 'cloudOrigin']) {
      config.remove(key);
    }
    final entryFile = config['entryFile'];
    if (entryFile != null) {
      if (entryFile is! String) {
        throw const ProjectZipException('项目入口文件配置无效');
      }
      config['entryFile'] = _relative(entryFile);
    }
    await File(ProjectConfig.configPath(root)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
      flush: true,
    );
  }

  static Future<void> _restoreMode(File file, int mode) async {
    if (Platform.isWindows || mode & 0x49 == 0) return;
    // Keep executable scripts usable on Android/OHOS; never restore setuid bits.
    final result = await Process.run('chmod', [
      (mode & 0x1ff).toRadixString(8),
      file.path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('无法恢复项目文件权限', file.path);
    }
  }
}

class _ZipMember {
  const _ZipMember(this.header, this.path, this.isDirectory);

  final ZipFileHeader header;
  final String path;
  final bool isDirectory;
}
