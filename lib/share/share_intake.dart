import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import 'share_inbox.dart';
import 'share_inbox_store.dart';

/// 复制进项目的默认子目录。
const String kShareInboxProjectFolder = 'inbox';

/// 复制结果。
class ShareIntakeResult {
  const ShareIntakeResult({
    required this.project,
    required this.relativePaths,
    this.skipped = const [],
  });

  final Project project;

  /// 相对项目根的路径，`/` 分隔。可直接作为 agent 附件。
  final List<String> relativePaths;

  /// 跳过的文件名与原因。
  final List<String> skipped;

  bool get isEmpty => relativePaths.isEmpty;
}

/// 收件箱落盘失败。
class ShareIntakeException implements Exception {
  const ShareIntakeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把一批收件箱文件复制进项目。
///
/// 规则见 design 4.7：先建 `.part`，写完再改名；重名依次试 `name (1).ext`；
/// 超过上限的文件跳过并记在 [ShareIntakeResult.skipped]。
Future<ShareIntakeResult> copyBatchIntoProject({
  required ShareInboxBatch batch,
  required Project project,
  String subdirectory = kShareInboxProjectFolder,
  int maxFiles = ShareInboxStore.defaultMaxFilesPerBatch,
  int maxFileBytes = ShareInboxStore.defaultMaxFileBytes,
}) async {
  final root = project.path;
  if (root.trim().isEmpty) {
    throw const ShareIntakeException('项目目录不存在，无法放入文件');
  }
  final target = Directory(p.join(root, _cleanSubdirectory(subdirectory)));
  // 本次调用是否建过目录。只在确实要写文件那一刻建，整批跳过时不留空壳。
  var createdTarget = false;
  final copied = <String>[];
  final skipped = <String>[];
  var count = 0;
  for (final file in batch.files) {
    if (count >= maxFiles) {
      skipped.add('${file.name}：超过单批 $maxFiles 个文件');
      continue;
    }
    if (file.bytes > maxFileBytes) {
      skipped.add('${file.name}：超过单文件上限');
      continue;
    }
    final source = File(file.path);
    if (!await source.exists()) {
      skipped.add('${file.name}：收件箱文件已不存在');
      continue;
    }
    final name = sanitizeSharedFileName(file.name);
    try {
      if (!createdTarget && !await target.exists()) {
        await target.create(recursive: true);
        createdTarget = true;
      }
      final destination = await _uniqueTarget(target, name);
      await _copyStreaming(source, destination);
      copied.add(
        p.relative(destination.path, from: root).replaceAll('\\', '/'),
      );
      count++;
    } on FileSystemException catch (error) {
      skipped.add('${file.name}：${error.message}');
      continue;
    }
  }
  if (copied.isEmpty && createdTarget) {
    // 非递归：只能删空目录，不会波及这个期间别人写进去的文件。
    try {
      await target.delete();
    } on FileSystemException {
      // 目录已不空或被占用：留着，下一批还能用。
    }
  }
  return ShareIntakeResult(
    project: project,
    relativePaths: List.unmodifiable(copied),
    skipped: List.unmodifiable(skipped),
  );
}

/// 把收件箱显示名换成安全文件名。
///
/// 先按 POSIX 取末段：`/` 是真实目录分隔，原生可能给 `../../etc/passwd`。
/// 反斜杠不先转 `/`：它是名字里的普通字符，换成 `_` 而不是整段丢弃。
String sanitizeSharedFileName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'shared-file';
  var name = p.posix.basename(trimmed);
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_').trim();
  if (name.isEmpty || name == '.' || name == '..') return 'shared-file';
  if (name.length > 120) {
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 && name.length - dot <= 16
        ? name.substring(dot)
        : '';
    name = '${name.substring(0, 120 - extension.length)}$extension';
  }
  return name;
}

/// 子目录只接受相对路径，且不允许跳出项目根。
///
/// 空串表示项目根，包含 `..` 时回落到默认的 `inbox`。
String _cleanSubdirectory(String raw) {
  final normalized = raw.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return '';
  final parts = <String>[];
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return kShareInboxProjectFolder;
    parts.add(part);
  }
  if (parts.isEmpty) return '';
  return p.joinAll(parts);
}

/// 人类可读的文件大小，如 `1.2 MiB`。
String formatSharedBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// 重名时依次试 `name (1).ext`，到 99 次放弃。
Future<File> _uniqueTarget(Directory directory, String name) async {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  var candidate = File(p.join(directory.path, name));
  if (!await candidate.exists()) return candidate;
  for (var index = 1; index <= 99; index++) {
    candidate = File(p.join(directory.path, '$stem ($index)$extension'));
    if (!await candidate.exists()) return candidate;
  }
  throw ShareIntakeException('同名文件太多：$name');
}

/// 分块复制：先写 `.part`，写完再改名。
Future<void> _copyStreaming(File source, File target) async {
  final part = File('${target.path}.part');
  try {
    await part.parent.create(recursive: true);
    if (await part.exists()) await part.delete();
    final sink = part.openWrite();
    try {
      await source.openRead().pipe(sink);
    } finally {
      // pipe 正常结束会自己关闭；异常时补一次，重复关闭是安全的。
      await sink.close().catchError((Object _) {});
    }
    if (await target.exists()) {
      throw const ShareIntakeException('目标文件已被占用');
    }
    await part.rename(target.path);
  } on FileSystemException {
    try {
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      // 清理失败不掩盖原始错误。
    }
    rethrow;
  }
}
