/// Collects a project directory into an [InteropRequest] payload.
///
/// The receiver cannot read the Studio sandbox and there is no shared writable
/// directory on OHOS, so the only way files reach a sibling app is this text
/// payload. It is bounded on purpose: a project that exceeds the cap is
/// refused with `payload_too_large` instead of arriving half-copied and being
/// compiled into a misleading result.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'interop_protocol.dart';

/// Build directories that never help a compile and can dwarf the payload.
const Set<String> _excludedDirectories = <String>{
  '.git',
  '.gradle',
  '.idea',
  '.qfli',
  '.dart_tool',
  '__pycache__',
  'build',
  'node_modules',
  'oh_modules',
  'out',
  'target',
  'vendor',
};

/// One directory tree turned into payload files.
abstract final class InteropProjectPayload {
  /// Reads every regular file under [projectRoot], skipping symlinks, hidden
  /// entries and [_excludedDirectories].
  ///
  /// Throws [InteropException] with `payload_too_large` as soon as a limit is
  /// hit. Symlinks are skipped rather than followed: a link can point outside
  /// the project, and copying its target would send bytes the user did not
  /// choose.
  static Future<List<InteropPayloadFile>> collect(
    String projectRoot, {
    int maxFiles = InteropLimits.maxFiles,
    int maxBytes = InteropLimits.maxPayloadBytes,
  }) async {
    final root = p.normalize(p.absolute(projectRoot));
    final rootDirectory = Directory(root);
    if (!await rootDirectory.exists()) {
      throw InteropException(
        InteropErrorCode.badRequest,
        '项目目录不存在：$projectRoot',
      );
    }
    final files = <InteropPayloadFile>[];
    var bytes = 0;

    Future<void> walk(Directory directory) async {
      final List<FileSystemEntity> children;
      try {
        children = await directory.list(followLinks: false).toList();
      } on FileSystemException catch (error) {
        throw InteropException(
          InteropErrorCode.internal,
          '无法读取 ${p.basename(directory.path)}：${error.message}',
        );
      }
      // A stable order keeps the request payload and its digest reproducible.
      children.sort((a, b) => a.path.compareTo(b.path));
      for (final entity in children) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Link) continue;
        if (entity is Directory) {
          if (_excludedDirectories.contains(name)) continue;
          await walk(entity);
          continue;
        }
        if (entity is! File) continue;
        final relative = p
            .relative(entity.path, from: root)
            .replaceAll('\\', '/');
        if (!InteropPath.isValid(relative)) continue;
        final int length;
        try {
          length = await entity.length();
        } on FileSystemException {
          continue;
        }
        if (files.length >= maxFiles) {
          throw InteropException(
            InteropErrorCode.payloadTooLarge,
            '项目超过 $maxFiles 个文件，跨应用运行只支持小型项目',
          );
        }
        if (bytes + length > maxBytes) {
          throw InteropException(
            InteropErrorCode.payloadTooLarge,
            '项目超过 ${maxBytes ~/ 1024} KiB，跨应用运行只支持小型项目',
          );
        }
        final List<int> content;
        try {
          content = await entity.readAsBytes();
        } on FileSystemException catch (error) {
          throw InteropException(
            InteropErrorCode.internal,
            '无法读取 $relative：${error.message}',
          );
        }
        bytes += content.length;
        files.add(InteropPayloadFile(path: relative, content: content));
      }
    }

    await walk(rootDirectory);
    return files;
  }

  /// Chooses the entry file for [language]: the project config first, then the
  /// first payload file whose extension matches.
  ///
  /// Returns null when the payload has no matching source, which the caller
  /// must report as a real failure rather than starting a run that cannot work.
  static String? findEntry(
    List<InteropPayloadFile> files, {
    required String language,
    String? configuredEntry,
  }) {
    final extensions = interopSourceExtensions(language);
    if (extensions.isEmpty) return null;
    if (configuredEntry != null &&
        configuredEntry.isNotEmpty &&
        files.any((file) => file.path == configuredEntry)) {
      return configuredEntry;
    }
    for (final file in files) {
      final extension = p.extension(file.path).toLowerCase();
      if (extensions.contains(extension)) return file.path;
    }
    return null;
  }
}

/// Source extensions that a language receiver can compile.
Set<String> interopSourceExtensions(String language) {
  switch (language) {
    case 'java':
      return const <String>{'.java'};
    case 'c':
      return const <String>{'.c'};
    case 'cpp':
      return const <String>{'.c', '.cc', '.cpp', '.cxx', '.h', '.hpp'};
    case 'python':
      return const <String>{'.py'};
    default:
      return const <String>{};
  }
}
