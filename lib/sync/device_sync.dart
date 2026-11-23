import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/sync_cache.dart';
import 'package:qfli_studio_core/sync/sync_ignore.dart';
import 'package:qfli_studio_core/sync/sync_limits.dart';

/// A sync request that cannot go ahead as asked.
class DeviceSyncException implements Exception {
  const DeviceSyncException(this.message, {this.kind = 'failed'});

  final String message;

  /// `truncated`, `mismatch`, `hash` or `failed`.
  final String kind;

  @override
  String toString() => message;
}

/// What one sync would change locally.
class SyncPlan {
  const SyncPlan({
    required this.remoteRoot,
    required this.localRoot,
    required this.manifest,
    required this.downloads,
    required this.deletes,
    required this.bytes,
    this.cacheKey = '',
  });

  final String remoteRoot;

  /// Directory of this copy on the phone.
  final String localRoot;

  /// The manifest the plan was built from, kept so [DeviceSyncService.apply]
  /// can store it after every file is in place.
  final FsManifest manifest;

  /// Files to add or replace, in manifest order.
  final List<FsEntry> downloads;

  /// Relative paths present locally but absent from the manifest.
  final List<String> deletes;

  /// Total bytes the downloads carry.
  final int bytes;

  /// Cache index key, `hostId/projectKey`; '' when the caller keeps no index.
  final String cacheKey;

  bool get isEmpty => downloads.isEmpty && deletes.isEmpty;
}

/// How far one apply has come.
class SyncProgress {
  const SyncProgress({
    required this.doneFiles,
    required this.totalFiles,
    required this.doneBytes,
    required this.totalBytes,
    this.path = '',
  });

  final int doneFiles;
  final int totalFiles;
  final int doneBytes;
  final int totalBytes;
  final String path;
}

/// What one apply actually did.
class SyncReport {
  const SyncReport({
    required this.writtenFiles,
    required this.deletedEntries,
    required this.bytes,
    required this.completed,
    this.failure,
  });

  const SyncReport.failed(String this.failure)
    : writtenFiles = 0,
      deletedEntries = 0,
      bytes = 0,
      completed = false;

  final int writtenFiles;
  final int deletedEntries;
  final int bytes;

  /// False when a step failed; the files that landed are complete copies and
  /// the deletions that did not run left the old files alone.
  final bool completed;
  final String? failure;
}

/// Copies a device project onto this phone, one file at a time.
///
/// The service never asks the computer for a whole directory: it compares
/// manifests first, transfers only the files whose hash changed, writes each
/// file to a temporary name and renames it only after the hash matches, and
/// touches deletions last. A failure therefore leaves complete files and the old
/// manifest, and the next sync converges from there.
class DeviceSyncService {
  DeviceSyncService({required DeviceFilePort port, SyncCache? cache})
    : _port = port,
      _cache = cache;

  final DeviceFilePort _port;
  final SyncCache? _cache;

  /// Compare the computer with the local copy.
  ///
  /// Throws [DeviceSyncException] when the manifest is cut short or was built
  /// with another ignore table: a partial list would make every file that is
  /// missing from it look deleted.
  Future<SyncPlan> plan({
    required String remoteRoot,
    required String localRoot,
    String cacheKey = '',
  }) async {
    final manifest = await _port.manifest(remoteRoot);
    if (manifest.truncated) {
      throw const DeviceSyncException(
        '项目文件太多，同步清单被截断。请改用更小的目录。',
        kind: 'truncated',
      );
    }
    if (manifest.ignoreVersion != kSyncIgnoreVersion) {
      throw DeviceSyncException(
        '电脑与本机的忽略表版本不一致（${manifest.ignoreVersion} / $kSyncIgnoreVersion），请先升级。',
        kind: 'mismatch',
      );
    }

    final local = await _listLocal(localRoot);
    final remote = manifest.byPath;
    final downloads = <FsEntry>[];
    var bytes = 0;
    for (final entry in manifest.entries) {
      if (!entry.isFile) continue;
      final existing = local.files[entry.path];
      if (existing != null &&
          existing.size == entry.size &&
          existing.hash == entry.hash) {
        continue;
      }
      downloads.add(entry);
      bytes += entry.size;
    }

    final deletes = <String>[
      for (final path in local.files.keys)
        if (!remote.containsKey(path)) path,
    ]..sort();

    return SyncPlan(
      remoteRoot: remoteRoot,
      localRoot: localRoot,
      manifest: manifest,
      downloads: downloads,
      deletes: deletes,
      bytes: bytes,
      cacheKey: cacheKey,
    );
  }

  /// Run [plan]: download, verify, rename, then delete.
  ///
  /// [keep] holds the cache keys that must survive the eviction this run may
  /// need (the project being synced is added automatically). [evictBefore] asks
  /// for room for the incoming bytes before the first write, so a sync that
  /// needs space does not leave the cache over budget until the next run.
  Future<SyncReport> apply(
    SyncPlan plan, {
    void Function(SyncProgress)? onProgress,
    Set<String> keep = const <String>{},
    bool evictBefore = true,
  }) async {
    var written = 0;
    var writtenBytes = 0;
    try {
      if (evictBefore && plan.bytes > 0) {
        await evict(
          needBytes: plan.bytes,
          keep: <String>{...keep, if (plan.cacheKey.isNotEmpty) plan.cacheKey},
        );
      }
      await Directory(p.join(plan.localRoot, 'files')).create(recursive: true);
      final staging = Directory(p.join(plan.localRoot, '.incoming'));
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      for (final entry in plan.downloads) {
        final bytes = await _fetch(entry);
        _ensureSafe(entry.path);
        await _writeVerified(plan.localRoot, entry, bytes);
        written += 1;
        writtenBytes += bytes.length;
        onProgress?.call(
          SyncProgress(
            doneFiles: written,
            totalFiles: plan.downloads.length,
            doneBytes: writtenBytes,
            totalBytes: plan.bytes,
            path: entry.path,
          ),
        );
      }

      final deleted = await _deleteStale(plan);
      await _storeManifest(plan);
      await _cache?.touch(
        plan.cacheKey,
        directory: plan.localRoot,
        bytes: await _directoryBytes(p.join(plan.localRoot, 'files')),
      );
      await _cache?.save();
      // The copy just written is complete, so trimming the cache now cannot
      // lose anything this run produced.
      if (!evictBefore) {
        await evict(
          needBytes: 0,
          keep: <String>{...keep, if (plan.cacheKey.isNotEmpty) plan.cacheKey},
        );
      }
      return SyncReport(
        writtenFiles: written,
        deletedEntries: deleted,
        bytes: writtenBytes,
        completed: true,
      );
    } on DeviceSyncException catch (error) {
      return SyncReport.failed(error.message);
    } on FileSystemException catch (error) {
      return SyncReport.failed('写入失败：${error.message}');
    }
  }

  /// Delete the least recently used copies until [needBytes] more bytes fit.
  ///
  /// [keep] holds the keys of the projects the user has open; those are never
  /// removed.
  Future<int> evict({
    required int needBytes,
    Set<String> keep = const <String>{},
  }) async {
    final cache = _cache;
    if (cache == null) return 0;
    final candidates = cache.evictCandidates(needBytes: needBytes, keep: keep);
    var removed = 0;
    for (final key in candidates) {
      final entry = cache.entryFor(key);
      if (entry == null) continue;
      final dir = Directory(entry.directory);
      if (await dir.exists()) {
        await dir.delete(recursive: true).catchError((Object _) => dir);
      }
      await cache.forget(key);
      removed += 1;
    }
    if (removed > 0) await cache.save();
    return removed;
  }

  Future<List<int>> _fetch(FsEntry entry) async {
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final chunk = await _port.read(
        entry.path,
        offset: offset,
        length: kSyncChunkBytes,
      );
      if (chunk.bytes.isEmpty && !chunk.eof) {
        throw DeviceSyncException('电脑返回了空分片：${entry.path}');
      }
      builder.add(chunk.bytes);
      offset += chunk.bytes.length;
      if (chunk.eof) break;
      if (offset > entry.size + kSyncChunkBytes) {
        throw DeviceSyncException('传输长度超出清单记录：${entry.path}');
      }
    }
    return builder.takeBytes();
  }

  Future<void> _writeVerified(
    String localRoot,
    FsEntry entry,
    List<int> bytes,
  ) async {
    final digest = sha256.convert(bytes).toString();
    if (digest != entry.hash) {
      throw DeviceSyncException('文件校验不通过：${entry.path}', kind: 'hash');
    }
    final target = p.join(localRoot, 'files', p.joinAll(entry.path.split('/')));
    final temp = File(
      p.join(
        localRoot,
        '.incoming',
        '${entry.path.replaceAll('/', '__')}.part',
      ),
    );
    await temp.parent.create(recursive: true);
    await temp.writeAsBytes(bytes, flush: true);
    await File(target).parent.create(recursive: true);
    if (await File(target).exists()) await File(target).delete();
    await temp.rename(target);
  }

  Future<int> _deleteStale(SyncPlan plan) async {
    var removed = 0;
    for (final relative in plan.deletes) {
      _ensureSafe(relative);
      final path = p.join(
        plan.localRoot,
        'files',
        p.joinAll(relative.split('/')),
      );
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        removed += 1;
      }
    }
    // Directories go deepest first so a parent never blocks its children.
    final dirs = <String>[];
    final root = Directory(p.join(plan.localRoot, 'files'));
    if (await root.exists()) {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) dirs.add(entity.path);
      }
    }
    dirs.sort((a, b) => b.length.compareTo(a.length));
    for (final path in dirs) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      if (await dir.list(followLinks: false).isEmpty) {
        await dir.delete();
        removed += 1;
      }
    }
    return removed;
  }

  Future<void> _storeManifest(SyncPlan plan) async {
    final file = File(p.join(plan.localRoot, 'manifest.json'));
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(_manifestJson(plan.manifest)),
      flush: true,
    );
    await temp.rename(file.path);
    final state = File(p.join(plan.localRoot, 'sync.json'));
    await state.writeAsString(
      jsonEncode(<String, dynamic>{
        'root': plan.remoteRoot,
        'usedAt': DateTime.now().toIso8601String(),
        'bytes': plan.bytes,
        'files': plan.downloads.length,
      }),
      flush: true,
    );
  }

  void _ensureSafe(String relative) {
    if (!isSafeRelativePath(relative)) {
      throw DeviceSyncException('清单里有不安全路径：$relative', kind: 'failed');
    }
  }

  Future<_LocalListing> _listLocal(String localRoot) async {
    final files = <String, _LocalFile>{};
    final root = Directory(p.join(localRoot, 'files'));
    if (!await root.exists()) return _LocalListing(files);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .split(p.separator)
          .join('/');
      if (!isSafeRelativePath(relative)) continue;
      if (isIgnoredRelativePath(relative)) continue;
      final info = await entity.stat();
      files[relative] = _LocalFile(
        size: info.size,
        hash: sha256.convert(await entity.readAsBytes()).toString(),
      );
    }
    return _LocalListing(files);
  }

  Future<int> _directoryBytes(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}

class _LocalFile {
  const _LocalFile({required this.size, required this.hash});

  final int size;
  final String hash;
}

class _LocalListing {
  const _LocalListing(this.files);

  final Map<String, _LocalFile> files;
}

Map<String, dynamic> _manifestJson(FsManifest manifest) => <String, dynamic>{
  'root': manifest.root,
  'ignoreVersion': manifest.ignoreVersion,
  'truncated': manifest.truncated,
  'entries': <Map<String, dynamic>>[
    for (final entry in manifest.entries)
      <String, dynamic>{
        'path': entry.path,
        'kind': entry.kind,
        'size': entry.size,
        'hash': entry.hash,
      },
  ],
};
