import 'dart:io';

import 'package:path/path.dart' as p;

/// 收件箱目录的配额与清理。
///
/// 目录布局：`<root>/<batchId>/<index>-<name>`。批次 id 由原生端生成，
/// 只允许 `[A-Za-z0-9_-]`，因此这里可以把 id 直接拼进路径。
class ShareInboxStore {
  ShareInboxStore({
    required this.root,
    this.maxBytes = defaultMaxBytes,
    this.maxAge = defaultMaxAge,
    this.maxFilesPerBatch = defaultMaxFilesPerBatch,
    this.maxFileBytes = defaultMaxFileBytes,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 收件箱常驻上限：512 MiB。
  static const int defaultMaxBytes = 512 * 1024 * 1024;

  /// 单文件上限：2 GiB。
  static const int defaultMaxFileBytes = 2 * 1024 * 1024 * 1024;

  /// 保留期：7 天。
  static const Duration defaultMaxAge = Duration(days: 7);

  /// 单批最多 16 个文件。
  static const int defaultMaxFilesPerBatch = 16;

  static final RegExp _batchId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final Directory root;
  final int maxBytes;
  final Duration maxAge;
  final int maxFilesPerBatch;
  final int maxFileBytes;
  final DateTime Function() _clock;

  /// 批次 id 是否可用。不可用的 id 一律不拼进路径。
  static bool isValidBatchId(String id) => _batchId.hasMatch(id);

  Directory batchDirectory(String batchId) =>
      Directory(p.join(root.path, batchId));

  /// 删除一个批次。目录不在时视为成功。
  Future<void> discard(String batchId) async {
    if (!isValidBatchId(batchId)) return;
    try {
      final dir = batchDirectory(batchId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // 盘忙或被占用：下次启动再清。
    }
  }

  /// 先删超期批次，再按最旧优先删到总量不超上限。
  ///
  /// 清理失败只跳过，不抛给调用方。
  Future<void> sweep() async {
    final batches = await _scan();
    if (batches.isEmpty) return;
    final now = _clock();
    for (final batch in batches) {
      if (now.difference(batch.modified) <= maxAge) continue;
      await discard(batch.id);
    }
    var remaining = await _scan();
    var total = remaining.fold<int>(0, (sum, batch) => sum + batch.bytes);
    for (final batch in remaining) {
      if (total <= maxBytes) break;
      await discard(batch.id);
      total -= batch.bytes;
    }
  }

  /// 按修改时间从旧到新列出批次。
  Future<List<({String id, DateTime modified, int bytes})>> _scan() async {
    final found = <({String id, DateTime modified, int bytes})>[];
    try {
      if (!await root.exists()) return found;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final id = p.basename(entity.path);
        if (!isValidBatchId(id)) continue;
        try {
          final modified = (await entity.stat()).modified;
          var bytes = 0;
          await for (final child in entity.list(
            recursive: true,
            followLinks: false,
          )) {
            if (child is File) bytes += (await child.stat()).size;
          }
          found.add((id: id, modified: modified, bytes: bytes));
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return found;
    }
    found.sort((a, b) => a.modified.compareTo(b.modified));
    return found;
  }
}
