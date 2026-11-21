import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/api_config.dart';
import '../models/cloud_project.dart';
import '../models/project.dart';
import 'api_client.dart';
import 'cloud_cache_paths.dart';
import 'cloud_cache_service.dart';
import 'project_templates.dart';

/// 云端项目条目（服务器返回）。
class CloudProjectInfo {
  const CloudProjectInfo({
    required this.id,
    required this.name,
    required this.fileCount,
  });
  final String id;
  final String name;
  final int fileCount;
  static CloudProjectInfo fromJson(Map<String, dynamic> j) => CloudProjectInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    fileCount: (j['files'] as num?)?.toInt() ?? 0,
  );
}

/// 云端文件条目。
class CloudFileInfo {
  const CloudFileInfo({required this.path, required this.mtime});
  final String path;
  final double mtime;
  static CloudFileInfo fromJson(Map<String, dynamic> j) => CloudFileInfo(
    path: CloudCachePaths.relative(j['path'] as String),
    mtime: (j['mtime'] as num).toDouble(),
  );
}

enum SyncState { idle, syncing, synced, offline }

/// Editor workspace sync. Complete remote snapshots live in a separate owner.
/// A pull may seed/update known clean files, but never prunes local edits.
class CloudSyncService {
  CloudSyncService._({
    required this.cloudId,
    required this.localPath,
    required this.scope,
    required this.session,
    required this.root,
    required this.name,
    required this.cache,
  }) {
    if (scope != null) CloudWorkspaceActivity.open(_activityKey);
  }

  static CloudSession? activeSession;
  final String cloudId;
  final String localPath;
  final String root;
  final String name;
  final CloudProjectScope? scope;
  final CloudSession? session;
  final CloudCacheService cache;
  bool _disposed = false;
  final _stateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;
  SyncState _state = SyncState.idle;
  final Map<String, Future<String?>> _pushes = {};
  SyncState get state => _state;
  String get _activityKey => CloudWorkspaceActivity.key(scope!, cloudId);

  void _setState(SyncState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  static Future<CloudSyncService> open({
    required String cloudId,
    required String name,
    String? testHome,
    String? cachePath,
    CloudProjectScope? scope,
    CloudSession? session,
    CloudCacheService? cache,
  }) async {
    CloudProjectScope.validateCloudId(cloudId);
    final captured = session ?? activeSession;
    scope ??= captured?.scope;
    if (captured != null && captured.scope != scope) {
      throw const CloudOperationException('scope', '云端项目账号不匹配');
    }
    final owner =
        cache ??
        (testHome == null
            ? CloudCacheService.instance
            : CloudCacheService(
                projectsRootOverride: p.join(testHome, 'projects'),
              ));
    // No implicit account ownership for legacy callers. Preserve their old
    // files, but fail closed on every later network operation.
    final root = scope == null
        ? p.dirname(cachePath ?? '')
        : await owner.projectRoot(scope, cloudId);
    final path =
        cachePath ??
        (scope == null
            ? throw const CloudOperationException('scope', '请先登录云端账号')
            : p.join(root, 'workspace'));
    CloudCachePaths.noLinks(path);
    if (scope != null &&
        p.equals(p.absolute(path), p.join(p.absolute(root), 'workspace'))) {
      if (captured == null) {
        throw const CloudOperationException('scope', '请先登录云端账号');
      }
      captured.ensureCurrent();
      owner.ensureOwner(
        root,
        Project.create(
          name: name,
          path: path,
          cloudId: cloudId,
          cloudOrigin: scope.origin,
          cloudAccountId: scope.accountId,
        ),
        captured,
      );
      CloudCachePaths.directory(path);
      try {
        await owner.restoreWorkspace(
          Project.create(
            name: name,
            path: path,
            cloudId: cloudId,
            cloudOrigin: scope.origin,
            cloudAccountId: scope.accountId,
          ),
          captured,
          path,
        );
      } on CloudOperationException catch (error) {
        if (error.code != 'manifest') rethrow;
        // An invalid cache never replaces locally recoverable workspace bytes.
      } on FormatException {
        // Opening remains possible; pull reports the invalid cache separately.
      }
    }
    captured?.ensureCurrent();
    return CloudSyncService._(
      cloudId: cloudId,
      localPath: path,
      scope: scope,
      session: captured,
      root: root,
      name: name,
      cache: owner,
    );
  }

  CloudSession _capture(String token) {
    final captured = session;
    if (_disposed ||
        captured == null ||
        scope == null ||
        captured.scope != scope ||
        !captured.acceptsToken(token)) {
      throw const CloudOperationException('sessionChanged', '云端会话已变化，请重新打开项目');
    }
    captured.ensureCurrent();
    if (scope!.origin != ApiConfig.origin) {
      throw const CloudOperationException('origin', '云端服务来源不匹配');
    }
    if (!p.equals(
      p.absolute(localPath),
      p.join(p.absolute(root), 'workspace'),
    )) {
      throw const CloudOperationException('legacy', '旧镜像已保留，请从云端列表重新打开');
    }
    CloudCachePaths.noLinks(localPath);
    return captured;
  }

  Project get _project => Project.create(
    name: name,
    path: localPath,
    cloudId: cloudId,
    cloudOrigin: scope!.origin,
    cloudAccountId: scope!.accountId,
  );

  bool existsAnyFile() {
    final dir = Directory(localPath);
    if (!dir.existsSync()) return false;
    return dir
        .listSync(recursive: true, followLinks: false)
        .any((e) => e is File);
  }

  Future<({int pulled, String? error})> pullAll({
    required String token,
    bool onlyIfMissing = false,
  }) async {
    _setState(SyncState.syncing);
    CloudSnapshot? snapshot;
    try {
      final session = _capture(token);
      snapshot = await cache.prepareSnapshot(
        project: _project,
        session: session,
      );
      final pulled = await cache.populateWorkspace(
        project: _project,
        session: session,
        workspace: localPath,
        snapshot: snapshot,
        onlyIfMissing: onlyIfMissing,
      );
      _setState(SyncState.synced);
      return (pulled: pulled, error: null);
    } catch (error) {
      _setState(SyncState.offline);
      return (pulled: 0, error: _message(error));
    } finally {
      await snapshot?.release();
    }
  }

  Future<String?> pushFile(String token, String absolutePath) async {
    try {
      return await pushBytes(
        token,
        absolutePath,
        await File(absolutePath).readAsBytes(),
      );
    } catch (error) {
      return _message(error);
    }
  }

  Future<String?> pushBytes(
    String token,
    String absolutePath,
    List<int> bytes,
  ) {
    final previous = _pushes[absolutePath];
    // Count queued work as well as active uploads. Clearing cannot run in the
    // gap while an earlier upload is still finishing.
    if (scope != null) {
      CloudWorkspaceActivity.markDirty(_activityKey, absolutePath);
      CloudWorkspaceActivity.beginPush(_activityKey);
    }
    final ownedBytes = List<int>.of(bytes);
    final next = () async {
      if (previous != null) await previous;
      return _pushBytes(token, absolutePath, ownedBytes);
    }();
    _pushes[absolutePath] = next;
    return next.whenComplete(() {
      if (scope != null) CloudWorkspaceActivity.endPush(_activityKey);
      if (identical(_pushes[absolutePath], next)) _pushes.remove(absolutePath);
    });
  }

  String _relative(String absolutePath) {
    if (!p.isWithin(p.absolute(localPath), p.absolute(absolutePath))) {
      throw const CloudOperationException('path', '文件不在云端项目目录内');
    }
    CloudCachePaths.noLinks(absolutePath);
    return CloudCachePaths.relative(
      p.relative(absolutePath, from: localPath).replaceAll(r'\', '/'),
    );
  }

  Future<String?> _pushBytes(
    String token,
    String absolutePath,
    List<int> bytes,
  ) async {
    _setState(SyncState.syncing);
    try {
      final session = _capture(token);
      final relative = _relative(absolutePath);
      if (cache.isBusy(scope!, cloudId)) {
        throw const CloudOperationException('busy', '缓存正在处理，已保留本地修改');
      }
      await cache.api
          .scopedCloud(session)
          .writeFile(cloudId, relative, base64Encode(bytes));
      CloudCacheService.recordSyncedFile(root, relative, bytes);
      CloudWorkspaceActivity.markSynced(_activityKey, absolutePath);
      _setState(SyncState.synced);
      return null;
    } catch (error) {
      _setState(SyncState.offline);
      return _message(error);
    }
  }

  Future<String?> pushDelete(String token, String absolutePath) async {
    if (scope != null) {
      CloudWorkspaceActivity.markDirty(_activityKey, absolutePath);
      CloudWorkspaceActivity.beginPush(_activityKey);
    }
    _setState(SyncState.syncing);
    try {
      final session = _capture(token);
      final relative = _relative(absolutePath);
      if (cache.isBusy(scope!, cloudId)) {
        throw const CloudOperationException('busy', '缓存正在处理，已保留本地修改');
      }
      await cache.api.scopedCloud(session).deleteFile(cloudId, relative);
      CloudCacheService.recordSyncedFile(root, relative, null);
      CloudWorkspaceActivity.markSynced(_activityKey, absolutePath);
      _setState(SyncState.synced);
      return null;
    } catch (error) {
      _setState(SyncState.offline);
      return _message(error);
    } finally {
      if (scope != null) CloudWorkspaceActivity.endPush(_activityKey);
    }
  }

  static Future<({String? id, String? error})> createCloudProject({
    required String token,
    required String name,
    required ProjectTemplate template,
    CloudProjectScope? scope,
    CloudSession? session,
  }) async {
    CloudSyncService? service;
    try {
      final captured = session ?? activeSession;
      scope ??= captured?.scope;
      if (captured == null ||
          captured.scope != scope ||
          !captured.acceptsToken(token)) {
        throw const CloudOperationException('scope', '请先登录云端账号');
      }
      final created = await ApiClient.instance
          .scopedCloud(captured)
          .createProject(name);
      final id = CloudProjectScope.validateCloudId(created['id'] as String);
      service = await open(
        cloudId: id,
        name: name,
        scope: scope,
        session: captured,
      );
      final files = template.files.isEmpty
          ? [const TemplateFile('src/.gitkeep', '')]
          : template.files;
      for (final file in files) {
        captured.ensureCurrent();
        final path = CloudCachePaths.resolve(service.localPath, file.path);
        CloudCachePaths.directory(p.dirname(path));
        CloudCachePaths.noLinks(path);
        File(path).writeAsStringSync(file.content, flush: true);
        final error = await service.pushFile(token, path);
        if (error != null) return (id: id, error: error);
      }
      return (id: id, error: null);
    } catch (error) {
      return (id: null, error: _message(error));
    } finally {
      service?.dispose();
    }
  }

  Future<({String stdout, String stderr, int exitCode})> git(
    String token,
    String action, {
    String? message,
    String? url,
  }) async {
    final captured = _capture(token);
    final result = await cache.api.cloudGit(
      captured.token,
      cloudId,
      action: action,
      message: message,
      url: url,
    );
    captured.ensureCurrent();
    return result;
  }

  static String _message(Object error) => error is CloudOperationException
      ? error.message
      : error is FileSystemException
      ? '同步文件读写失败'
      : '云端同步失败，请重试';
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (scope != null) CloudWorkspaceActivity.close(_activityKey);
    unawaited(_stateController.close());
  }
}
