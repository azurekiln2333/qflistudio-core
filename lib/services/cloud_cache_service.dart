import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/cloud_project.dart';
import '../models/project.dart';
import 'api_client.dart';
import 'app_paths.dart';
import 'cloud_cache_paths.dart';

/// Owns immutable complete remote snapshots, never the editor's working files.
class CloudCacheService extends ChangeNotifier {
  CloudCacheService({ApiClient? api, this.projectsRootOverride})
    : api = api ?? ApiClient.instance;
  static final instance = CloudCacheService();
  final ApiClient api;
  final String? projectsRootOverride;
  final _statuses = <String, CloudCacheStatus>{};
  static final _busy = <String>{};
  static final _leases = <String, int>{};
  static final _versions = <String, int>{};

  String key(CloudProjectScope scope, String id) =>
      CloudWorkspaceActivity.key(scope, CloudProjectScope.validateCloudId(id));
  CloudCacheStatus status(CloudProjectScope scope, String id) =>
      _statuses[key(scope, id)] ?? const CloudCacheStatus();
  bool isBusy(CloudProjectScope scope, String id) =>
      _busy.contains(key(scope, id));

  Future<String> projectRoot(CloudProjectScope scope, String id) =>
      AppPaths.cloudProjectRoot(
        scope: scope,
        cloudId: id,
        projectsRootOverride: projectsRootOverride,
      );

  void _set(String key, CloudCacheStatus status) {
    _statuses[key] = status;
    notifyListeners();
  }

  void _checkProject(Project project, CloudSession session) {
    session.ensureCurrent();
    if (!project.belongsToCloudScope(session.scope)) {
      throw const CloudOperationException('scope', '云端项目账号不匹配');
    }
    CloudProjectScope.validateCloudId(project.cloudId!);
  }

  Future<T> exclusive<T>(
    Project project,
    CloudSession session,
    Future<T> Function() action,
  ) async {
    _checkProject(project, session);
    final id = key(session.scope, project.cloudId!);
    if (CloudWorkspaceActivity.pending(id)) {
      throw const CloudOperationException('busy', '有文件正在上传，请稍后重试');
    }
    if (!_busy.add(id)) {
      throw const CloudOperationException('busy', '云端项目正在处理，请稍后重试');
    }
    _versions[id] = (_versions[id] ?? 0) + 1;
    notifyListeners();
    try {
      session.ensureCurrent();
      return await action();
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }

  /// Reads a manifest and checks every listed payload byte. A directory alone
  /// is never proof of a complete cache, including after a process restart.
  Future<CloudCacheStatus> inspect(
    Project project,
    CloudSession session,
  ) async {
    _checkProject(project, session);
    final id = key(session.scope, project.cloudId!);
    if (_busy.contains(id)) return status(session.scope, project.cloudId!);
    final version = _versions[id] ?? 0;
    try {
      final root = await projectRoot(session.scope, project.cloudId!);
      session.ensureCurrent();
      final manifest = await _readManifest(root, project, session);
      session.ensureCurrent();
      final last = manifest?.status ?? const CloudCacheStatus();
      final operation = _readJson(p.join(root, 'status.json'));
      final interrupted = operation?['phase'] == 'caching';
      final failed = operation?['phase'] == 'failed';
      final result = interrupted || failed
          ? CloudCacheStatus(
              phase: CloudCachePhase.failed,
              fileCount: last.fileCount,
              bytes: last.bytes,
              cachedAt: last.cachedAt,
              completedFiles: _nonnegative(operation?['completedFiles']),
              totalFiles: _nonnegative(operation?['totalFiles']),
              downloadedBytes: _nonnegative(operation?['downloadedBytes']),
              error: interrupted ? '上次缓存未完成，请重试' : '上次缓存失败，请重试',
            )
          : last;
      if ((_versions[id] ?? 0) != version) {
        return status(session.scope, project.cloudId!);
      }
      _set(id, result);
      return result;
    } catch (_) {
      session.ensureCurrent();
      if ((_versions[id] ?? 0) != version) {
        return status(session.scope, project.cloudId!);
      }
      const result = CloudCacheStatus(
        phase: CloudCachePhase.failed,
        error: '缓存清单或文件无效，请更新缓存',
      );
      _set(id, result);
      return result;
    }
  }

  Future<CloudCacheStatus> update(Project project, CloudSession session) =>
      exclusive(project, session, () async {
        await _download(project, session);
        return status(session.scope, project.cloudId!);
      });

  /// Always fetches a fresh tree. No stale or partial fallback for sharing.
  Future<CloudSnapshot> prepareSnapshot({
    required Project project,
    required CloudSession session,
  }) => exclusive(project, session, () async {
    final manifest = await _download(project, session);
    session.ensureCurrent();
    final leaseKey = key(session.scope, project.cloudId!);
    _leases[leaseKey] = (_leases[leaseKey] ?? 0) + 1;
    return CloudSnapshot(
      path: manifest.payload,
      fileCount: manifest.files.length,
      bytes: manifest.bytes,
      cachedAt: manifest.cachedAt,
      ensureCurrent: session.ensureCurrent,
      release: () async {
        final count = (_leases[leaseKey] ?? 1) - 1;
        if (count <= 0) {
          _leases.remove(leaseKey);
        } else {
          _leases[leaseKey] = count;
        }
      },
    );
  });

  Future<_CacheManifest> _download(
    Project project,
    CloudSession session,
  ) async {
    final id = key(session.scope, project.cloudId!);
    final previous = status(session.scope, project.cloudId!);
    Directory? stage;
    String? ownedRoot;
    try {
      final root = await projectRoot(session.scope, project.cloudId!);
      session.ensureCurrent();
      _ownRoot(root, project, session);
      ownedRoot = root;
      _CacheManifest? old;
      try {
        old = await _readManifest(root, project, session);
      } on CloudOperationException catch (error) {
        session.ensureCurrent();
        if (error.code != 'manifest') rethrow;
      } on FormatException {
        session.ensureCurrent();
      }
      final prior = old?.status ?? previous;
      _set(
        id,
        CloudCacheStatus(
          phase: CloudCachePhase.caching,
          fileCount: prior.fileCount,
          bytes: prior.bytes,
          cachedAt: prior.cachedAt,
        ),
      );
      _recordStatus(root, session, status(session.scope, project.cloudId!));
      final remote = api.scopedCloud(session);
      final tree = _tree(await remote.fileTree(project.cloudId!));
      _set(
        id,
        CloudCacheStatus(
          phase: CloudCachePhase.caching,
          totalFiles: tree.length,
          fileCount: prior.fileCount,
          bytes: prior.bytes,
          cachedAt: prior.cachedAt,
        ),
      );
      session.ensureCurrent();
      final snapshots = p.join(root, 'snapshots');
      CloudCachePaths.directory(snapshots);
      stage = Directory(snapshots).createTempSync('.stage-');
      final payload = p.join(stage.path, 'files');
      CloudCachePaths.directory(payload);
      final files = <_CacheFile>[];
      var bytes = 0;
      for (final entry in tree) {
        session.ensureCurrent();
        final response = await remote.readFile(project.cloudId!, entry.path);
        final encoded = response['content'];
        if (encoded is! String) {
          throw const CloudOperationException('response', '云端文件内容无效');
        }
        final content = base64Decode(encoded);
        final target = CloudCachePaths.resolve(payload, entry.path);
        CloudCachePaths.directory(p.dirname(target));
        CloudCachePaths.noLinks(target);
        // The owned stage is never shared with an editor.
        File(target).createSync(exclusive: true);
        File(target).writeAsBytesSync(content, flush: true);
        files.add(
          _CacheFile(
            entry.path,
            content.length,
            sha256.convert(content).toString(),
          ),
        );
        bytes += content.length;
        _set(
          id,
          CloudCacheStatus(
            phase: CloudCachePhase.caching,
            completedFiles: files.length,
            totalFiles: tree.length,
            downloadedBytes: bytes,
            fileCount: prior.fileCount,
            bytes: prior.bytes,
            cachedAt: prior.cachedAt,
          ),
        );
      }
      // Do not publish a tree that changed during the file downloads.
      final after = _tree(await remote.fileTree(project.cloudId!));
      if (jsonEncode(tree.map((f) => f.json).toList()) !=
          jsonEncode(after.map((f) => f.json).toList())) {
        throw const CloudOperationException('remoteChanged', '云端文件已变化，请重试');
      }
      session.ensureCurrent();
      final generation = 'snapshot-${p.basename(stage.path).substring(7)}';
      final committed = p.join(snapshots, generation);
      CloudCachePaths.noLinks(committed);
      if (FileSystemEntity.typeSync(committed, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const CloudOperationException('collision', '缓存目录已被占用');
      }
      stage.renameSync(committed);
      stage = null;
      session.ensureCurrent();
      final expected = Directory(
        p.join(committed, 'files'),
      ).listSync(recursive: true, followLinks: false);
      for (final entity in expected) {
        CloudCachePaths.noLinks(entity.path);
      }
      final manifest = _CacheManifest(
        root: root,
        generation: generation,
        cachedAt: DateTime.now().toUtc(),
        files: files,
        bytes: bytes,
      );
      session.ensureCurrent();
      _writeJson(root, 'manifest.json', manifest.json(project, session.scope));
      _recordStatus(root, session, manifest.status);
      _set(id, manifest.status);
      return manifest;
    } catch (error) {
      // Keep the last successful metadata and all earlier immutable snapshots.
      // Never echo a server body, token, or a file's content into status.
      final prior = status(session.scope, project.cloudId!);
      _set(
        id,
        CloudCacheStatus(
          phase: CloudCachePhase.failed,
          completedFiles: prior.completedFiles,
          totalFiles: prior.totalFiles,
          downloadedBytes: prior.downloadedBytes,
          fileCount: prior.fileCount,
          bytes: prior.bytes,
          cachedAt: prior.cachedAt,
          error: error is CloudOperationException
              ? error.message
              : error is FileSystemException
              ? '缓存文件读写失败，请重试'
              : '下载云端缓存失败，请重试',
        ),
      );
      if (ownedRoot != null) {
        try {
          session.ensureCurrent();
          _recordStatus(
            ownedRoot,
            session,
            status(session.scope, project.cloudId!),
          );
        } catch (_) {
          // A scope change or metadata error cannot overwrite the original error.
        }
      }
      rethrow;
    } finally {
      if (stage != null) {
        // Only this operation's uncommitted directory may be discarded.
        try {
          CloudCachePaths.noLinks(stage.path);
          stage.deleteSync(recursive: true);
        } on FileSystemException {
          /* Keep the original failure. */
        }
      }
    }
  }

  /// Clear only a known owned cache. Dirty/active workspaces and export leases
  /// make clear a recoverable conflict, not a destructive best-effort cleanup.
  Future<void> clear(Project project, CloudSession session) =>
      exclusive(project, session, () async {
        final id = key(session.scope, project.cloudId!);
        if (CloudWorkspaceActivity.active(id) ||
            CloudWorkspaceActivity.pending(id) ||
            CloudWorkspaceActivity.dirty(id) ||
            (_leases[id] ?? 0) > 0) {
          throw const CloudOperationException('busy', '缓存正在使用或有未同步修改');
        }
        final root = await projectRoot(session.scope, project.cloudId!);
        session.ensureCurrent();
        if (!Directory(root).existsSync()) {
          _set(id, const CloudCacheStatus());
          return;
        }
        _verifyOwner(root, project, session.scope);
        final workspace = p.join(root, 'workspace');
        if (!workspaceIsClean(root, workspace)) {
          throw const CloudOperationException('dirty', '缓存有未同步修改，请先保存副本');
        }
        // Refuse unexpected entries instead of deleting user-managed files.
        for (final entity in Directory(
          root,
        ).listSync(recursive: true, followLinks: false)) {
          CloudCachePaths.noLinks(entity.path);
          final relative = p.relative(entity.path, from: root);
          final first = p.split(relative).first;
          if (!const [
            'owner.json',
            'manifest.json',
            'workspace.json',
            'status.json',
            'workspace',
            'snapshots',
          ].contains(first)) {
            throw const CloudOperationException('ownership', '缓存目录包含未知文件');
          }
        }
        session.ensureCurrent();
        if (CloudWorkspaceActivity.active(id) ||
            CloudWorkspaceActivity.pending(id) ||
            CloudWorkspaceActivity.dirty(id) ||
            (_leases[id] ?? 0) > 0) {
          throw const CloudOperationException('busy', '缓存正在使用或有未同步修改');
        }
        // No awaits between the final session/activity guard and deletion.
        Directory(root).deleteSync(recursive: true);
        _set(id, const CloudCacheStatus());
      });

  static int _nonnegative(Object? value) =>
      value is int && value >= 0 ? value : 0;

  static void _recordStatus(
    String root,
    CloudSession session,
    CloudCacheStatus status,
  ) {
    session.ensureCurrent();
    _writeJson(root, 'status.json', {
      'phase': status.phase.name,
      'completedFiles': status.completedFiles,
      'totalFiles': status.totalFiles,
      'downloadedBytes': status.downloadedBytes,
    });
  }

  static List<_RemoteFile> _tree(Map<String, dynamic> body) {
    final raw = body['files'];
    if (raw is! List) {
      throw const CloudOperationException('response', '云端文件列表无效');
    }
    final files = <_RemoteFile>[];
    for (final item in raw) {
      if (item is! Map ||
          item['path'] is! String ||
          item['mtime'] is! num ||
          !(item['mtime'] as num).isFinite) {
        throw const CloudOperationException('response', '云端文件列表无效');
      }
      final path = CloudCachePaths.relative(item['path'] as String);
      files.add(_RemoteFile(path, (item['mtime'] as num).toDouble()));
    }
    _validatePortablePaths(files.map((file) => file.path));
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Every shared prefix must keep one spelling and one node type, even on a
  /// case-sensitive host. Checking only complete file names misses A/x + a/y.
  static void _validatePortablePaths(
    Iterable<String> paths, {
    String errorCode = 'path',
  }) {
    final nodes = <String, ({String spelling, bool directory})>{};
    for (final path in paths) {
      final parts = path.split('/');
      for (var depth = 1; depth <= parts.length; depth++) {
        final spelling = parts.take(depth).join('/');
        final directory = depth < parts.length;
        final folded = spelling.toLowerCase();
        final previous = nodes[folded];
        if (previous != null) {
          if (previous.spelling != spelling) {
            throw CloudOperationException(errorCode, '云端路径大小写冲突');
          }
          if (previous.directory != directory) {
            throw CloudOperationException(errorCode, '云端文件与目录冲突');
          }
          if (!directory) {
            throw CloudOperationException(errorCode, '云端文件路径重复');
          }
        } else {
          nodes[folded] = (spelling: spelling, directory: directory);
        }
      }
    }
  }

  /// Creates or validates ownership without touching old workspace bytes.
  void ensureOwner(String root, Project project, CloudSession session) =>
      _ownRoot(root, project, session);

  void _ownRoot(String root, Project project, CloudSession session) {
    CloudCachePaths.noLinks(root);
    if (Directory(root).existsSync()) {
      final marker = File(p.join(root, 'owner.json'));
      if (marker.existsSync()) {
        _verifyOwner(root, project, session.scope);
        return;
      }
      if (Directory(root).listSync().isNotEmpty) {
        throw const CloudOperationException('ownership', '缓存目录不属于当前账号');
      }
    }
    CloudCachePaths.directory(root);
    _writeJson(root, 'owner.json', {
      'version': 1,
      'scope': session.scope.key,
      'cloudId': project.cloudId,
    });
  }

  static void _verifyOwner(
    String root,
    Project project,
    CloudProjectScope scope,
  ) {
    final owner = _readJson(p.join(root, 'owner.json'));
    if (owner?['version'] != 1 ||
        owner?['scope'] != scope.key ||
        owner?['cloudId'] != project.cloudId) {
      throw const CloudOperationException('ownership', '缓存目录不属于当前账号');
    }
  }

  Future<_CacheManifest?> _readManifest(
    String root,
    Project project,
    CloudSession session,
  ) async {
    CloudCachePaths.noLinks(root);
    final json = _readJson(p.join(root, 'manifest.json'));
    if (json == null) return null;
    _verifyOwner(root, project, session.scope);
    if (json['version'] != 1 ||
        json['complete'] != true ||
        json['scope'] != session.scope.key ||
        json['cloudId'] != project.cloudId ||
        json['files'] is! List ||
        json['generation'] is! String ||
        !RegExp(
          r'^snapshot-[A-Za-z0-9_-]+$',
        ).hasMatch(json['generation'] as String)) {
      throw const CloudOperationException('manifest', '缓存清单无效');
    }
    final time = DateTime.tryParse(json['cachedAt'] as String? ?? '');
    if (time == null) throw const CloudOperationException('manifest', '缓存时间无效');
    final files = <_CacheFile>[];
    for (final raw in json['files'] as List) {
      if (raw is! Map ||
          raw['path'] is! String ||
          raw['bytes'] is! int ||
          raw['hash'] is! String) {
        throw const CloudOperationException('manifest', '缓存清单无效');
      }
      files.add(
        _CacheFile(
          CloudCachePaths.relative(raw['path'] as String),
          raw['bytes'] as int,
          raw['hash'] as String,
        ),
      );
    }
    // Validate the entire namespace before touching any listed payload file.
    _validatePortablePaths(
      files.map((file) => file.path),
      errorCode: 'manifest',
    );
    final seen = files.map((file) => file.path).toSet();
    final payload = p.join(
      root,
      'snapshots',
      json['generation'] as String,
      'files',
    );
    CloudCachePaths.noLinks(payload);
    if (!Directory(payload).existsSync()) {
      throw const CloudOperationException('manifest', '缓存目录缺失');
    }
    var total = 0;
    for (final entry in files) {
      final file = File(CloudCachePaths.resolve(payload, entry.path));
      CloudCachePaths.regularFile(file.path);
      final hash = await sha256.bind(file.openRead()).first;
      session.ensureCurrent();
      if (file.lengthSync() != entry.bytes || hash.toString() != entry.hash) {
        throw const CloudOperationException('manifest', '缓存文件校验失败');
      }
      total += entry.bytes;
    }
    // An extra file would otherwise leak into ZIP even though not in manifest.
    for (final entity in Directory(
      payload,
    ).listSync(recursive: true, followLinks: false)) {
      CloudCachePaths.noLinks(entity.path);
      if (entity is! Directory &&
          !seen.contains(
            p.relative(entity.path, from: payload).replaceAll(r'\', '/'),
          )) {
        throw const CloudOperationException('manifest', '缓存含有清单外文件');
      }
    }
    if (json['bytes'] != total || json['fileCount'] != files.length) {
      throw const CloudOperationException('manifest', '缓存统计无效');
    }
    return _CacheManifest(
      root: root,
      generation: json['generation'] as String,
      cachedAt: time,
      files: files,
      bytes: total,
    );
  }

  static Map<String, dynamic>? _readJson(String path) {
    CloudCachePaths.noLinks(path);
    if (!File(path).existsSync()) return null;
    CloudCachePaths.regularFile(path);
    final raw = jsonDecode(File(path).readAsStringSync());
    if (raw is! Map) throw const CloudOperationException('manifest', '缓存清单无效');
    return Map<String, dynamic>.from(raw);
  }

  static void _writeJson(String root, String name, Map<String, dynamic> value) {
    CloudCachePaths.noLinks(root);
    final temporary = Directory(root).createTempSync('.metadata-');
    try {
      final file = File(p.join(temporary.path, name));
      file.writeAsStringSync(jsonEncode(value), flush: true);
      final destination = p.join(root, name);
      CloudCachePaths.noLinks(destination);
      file.renameSync(destination);
    } finally {
      temporary.deleteSync();
    }
  }

  /// Baseline is outside the workspace, never included in export payloads.
  static bool workspaceIsClean(String root, String workspace) {
    CloudCachePaths.noLinks(workspace);
    final baseline = _readJson(p.join(root, 'workspace.json'));
    if (!Directory(workspace).existsSync()) {
      return baseline == null || baseline.isEmpty;
    }
    final entries = Directory(
      workspace,
    ).listSync(recursive: true, followLinks: false);
    if (entries.isEmpty) return baseline == null || baseline.isEmpty;
    if (baseline == null) return false;
    final seen = <String>{};
    for (final entity in entries) {
      CloudCachePaths.noLinks(entity.path);
      if (entity is Directory) continue;
      CloudCachePaths.regularFile(entity.path);
      final relative = p
          .relative(entity.path, from: workspace)
          .replaceAll(r'\', '/');
      if (baseline[relative] !=
          sha256.convert(File(entity.path).readAsBytesSync()).toString()) {
        return false;
      }
      seen.add(relative);
    }
    return seen.length == baseline.length;
  }

  /// Restore a verified complete snapshot for offline opening. Dirty working
  /// bytes win. This does not download, move, or adopt a legacy mirror.
  Future<void> restoreWorkspace(
    Project project,
    CloudSession session,
    String workspace,
  ) => exclusive(project, session, () async {
    _checkProject(project, session);
    final id = key(session.scope, project.cloudId!);
    if (CloudWorkspaceActivity.pending(id) ||
        CloudWorkspaceActivity.dirty(id)) {
      return;
    }
    final root = await projectRoot(session.scope, project.cloudId!);
    session.ensureCurrent();
    final manifest = await _readManifest(root, project, session);
    if (manifest == null) return;
    session.ensureCurrent();
    final snapshot = CloudSnapshot(
      path: manifest.payload,
      fileCount: manifest.files.length,
      bytes: manifest.bytes,
      cachedAt: manifest.cachedAt,
      ensureCurrent: session.ensureCurrent,
      release: () async {},
    );
    try {
      await populateWorkspace(
        project: project,
        session: session,
        workspace: workspace,
        snapshot: snapshot,
        onlyIfMissing: CloudWorkspaceActivity.active(id),
      );
    } on CloudOperationException catch (error) {
      if (!const ['dirty', 'busy'].contains(error.code)) rethrow;
      // Existing local changes are opened in place, not overwritten.
    } finally {
      await snapshot.release();
    }
  });

  /// Seeds only absent workspace files. Existing bytes are never overwritten.
  /// Manual update refuses local differences rather than pruning them.
  Future<int> populateWorkspace({
    required Project project,
    required CloudSession session,
    required String workspace,
    required CloudSnapshot snapshot,
    required bool onlyIfMissing,
  }) async {
    _checkProject(project, session);
    final root = await projectRoot(session.scope, project.cloudId!);
    session.ensureCurrent();
    final expected = p.join(root, 'workspace');
    if (!p.equals(p.absolute(workspace), p.absolute(expected))) {
      throw const CloudOperationException('legacy', '旧镜像已保留，请从云端列表重新打开');
    }
    final id = key(session.scope, project.cloudId!);
    if (CloudWorkspaceActivity.pending(id) ||
        CloudWorkspaceActivity.dirty(id)) {
      throw const CloudOperationException('busy', '有未同步修改，已保留本地文件');
    }
    CloudCachePaths.directory(workspace);
    final baseline =
        _readJson(p.join(root, 'workspace.json')) ?? <String, dynamic>{};
    final sources = Directory(
      snapshot.path,
    ).listSync(recursive: true, followLinks: false).whereType<File>().toList();
    if (!onlyIfMissing) {
      // Preflight *all* existing paths before the first write.
      for (final source in sources) {
        final relative = p
            .relative(source.path, from: snapshot.path)
            .replaceAll(r'\', '/');
        final target = CloudCachePaths.resolve(workspace, relative);
        CloudCachePaths.noLinks(target);
        if (!File(target).existsSync()) {
          if (baseline.containsKey(relative)) {
            throw const CloudOperationException('dirty', '镜像有未同步删除，已保留本地文件');
          }
          continue;
        }
        final hash = sha256.convert(File(target).readAsBytesSync()).toString();
        final remoteHash = sha256.convert(source.readAsBytesSync()).toString();
        if (hash != remoteHash && CloudWorkspaceActivity.active(id)) {
          throw const CloudOperationException('busy', '编辑器正在使用镜像，缓存已更新但未覆盖文件');
        }
        if (hash != baseline[relative] && hash != remoteHash) {
          throw const CloudOperationException('dirty', '镜像有未同步修改，已保留本地文件');
        }
      }
    }
    var copied = 0;
    snapshot.ensureCurrent();
    for (final source in sources) {
      final relative = p
          .relative(source.path, from: snapshot.path)
          .replaceAll(r'\', '/');
      final target = CloudCachePaths.resolve(workspace, relative);
      CloudCachePaths.noLinks(target);
      if (onlyIfMissing &&
          (File(target).existsSync() || baseline.containsKey(relative))) {
        continue;
      }
      CloudCachePaths.regularFile(source.path);
      final bytes = source.readAsBytesSync();
      CloudCachePaths.directory(p.dirname(target));
      File(target).writeAsBytesSync(bytes, flush: true);
      baseline[relative] = sha256.convert(bytes).toString();
      copied++;
    }
    // Deliberately no prune: remote deletion cannot destroy unsent local files.
    _writeJson(root, 'workspace.json', baseline);
    return copied;
  }

  static void recordSyncedFile(String root, String relative, List<int>? bytes) {
    final baseline =
        _readJson(p.join(root, 'workspace.json')) ?? <String, dynamic>{};
    if (bytes == null) {
      baseline.remove(relative);
    } else {
      baseline[relative] = sha256.convert(bytes).toString();
    }
    _writeJson(root, 'workspace.json', baseline);
  }
}

class _RemoteFile {
  const _RemoteFile(this.path, this.mtime);
  final String path;
  final double mtime;
  Map<String, dynamic> get json => {'path': path, 'mtime': mtime};
}

class _CacheFile {
  const _CacheFile(this.path, this.bytes, this.hash);
  final String path;
  final int bytes;
  final String hash;
  Map<String, dynamic> get json => {'path': path, 'bytes': bytes, 'hash': hash};
}

class _CacheManifest {
  const _CacheManifest({
    required this.root,
    required this.generation,
    required this.cachedAt,
    required this.files,
    required this.bytes,
  });
  final String root;
  final String generation;
  final DateTime cachedAt;
  final List<_CacheFile> files;
  final int bytes;
  String get payload => p.join(root, 'snapshots', generation, 'files');
  CloudCacheStatus get status => CloudCacheStatus(
    phase: CloudCachePhase.cached,
    completedFiles: files.length,
    totalFiles: files.length,
    downloadedBytes: bytes,
    fileCount: files.length,
    bytes: bytes,
    cachedAt: cachedAt,
  );
  Map<String, dynamic> json(Project project, CloudProjectScope scope) => {
    'version': 1,
    'complete': true,
    'scope': scope.key,
    'cloudId': project.cloudId,
    'generation': generation,
    'cachedAt': cachedAt.toIso8601String(),
    'fileCount': files.length,
    'bytes': bytes,
    'files': files.map((f) => f.json).toList(),
  };
}
