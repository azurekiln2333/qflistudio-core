import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/device_sync.dart';
import 'package:qfli_studio_core/sync/sync_cache.dart';

/// A project that exists only because a session does.
///
/// When the user opens a session on the paired computer and the phone has no
/// local copy of that project, the editor still needs a directory to show and
/// somewhere to keep the stream cache. This class creates that directory under
/// `deviceSessions/`, marks the project as a placeholder, and leaves the real
/// files on the computer until the user asks for them.
///
/// Nothing is written into the user's own project folders: a placeholder lives
/// in the app data directory and is deleted with its session when the user
/// never pulled files.
class PlaceholderProjects {
  const PlaceholderProjects();

  /// Stable directory segment for one computer, so two computers with the same
  /// project path never share a placeholders directory.
  static String hostKey(String hostId) {
    final digest = sha256.convert(utf8.encode(hostId.trim())).toString();
    return digest.substring(0, 16);
  }

  /// Create (or reuse) the placeholder for [sessionId].
  ///
  /// The directory holds `.qfli/project.json` for the existing project config
  /// reader and `.session/` for the transcript cache. Reuse matters: the phone
  /// records the project once, and later opens must keep the same project id.
  Future<Project?> ensure({
    required String hostId,
    required String sessionId,
    required String title,
    String? deviceRoot,
    String language = '',
    String type = '',
  }) async {
    final root = await AppPaths.deviceSessionsRoot(create: true);
    if (root == null) return null;
    final directory = Directory(
      p.join(root, hostKey(hostId), _safeSegment(sessionId)),
    );
    await directory.create(recursive: true);
    await Directory(p.join(directory.path, '.session')).create(recursive: true);

    final configPath = ProjectConfig.configPath(directory.path);
    if (!File(configPath).existsSync()) {
      await ProjectConfig.write(
        projectRoot: directory.path,
        name: title.trim().isEmpty ? '电脑会话' : title.trim(),
        language: language,
        type: type,
      );
    }

    final now = DateTime.now();
    return Project(
      id: 'device-${hostKey(hostId)}-${_safeSegment(sessionId)}',
      name: title.trim().isEmpty ? '电脑会话' : title.trim(),
      path: directory.path,
      createdAt: now,
      lastOpenedAt: now,
      language: language,
      type: type,
      deviceHostId: hostId,
      deviceSessionId: sessionId,
      deviceRoot: deviceRoot,
      placeholder: true,
    );
  }

  /// Directory of the transcript cache for [project].
  String streamDirectory(Project project) => p.join(project.path, '.session');

  /// Where the real files would live once the user pulls them.
  ///
  /// `deviceProjects/<hostKey>/<projectKey>/files`, matching the cache layout so
  /// eviction can delete one project directory at a time.
  Future<String?> filesRoot(Project project) async {
    final root = await AppPaths.deviceProjectsRoot(create: true);
    if (root == null) return null;
    final hostId = project.deviceHostId;
    if (hostId == null) return null;
    return p.join(root, hostKey(hostId), _safeSegment(project.id), 'files');
  }

  /// Pull the project files the user just approved.
  ///
  /// Returns the report from [DeviceSyncService]; on success the project stops
  /// being a placeholder and points at the copy. A failure leaves the
  /// placeholder in place, so the session stays usable and the next attempt
  /// continues from the files that already landed.
  Future<SyncReport?> pullFiles(
    Project project, {
    required DeviceFilePort port,
    SyncCache? cache,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final deviceRoot = project.deviceRoot;
    if (deviceRoot == null || deviceRoot.trim().isEmpty) {
      return const SyncReport.failed('这个会话没有记下项目路径，无法拉取文件');
    }
    final localFiles = await filesRoot(project);
    if (localFiles == null) return const SyncReport.failed('未找到可写的项目目录');

    final copyRoot = p.dirname(localFiles);
    final service = DeviceSyncService(port: port, cache: cache);
    final cacheKey = '${project.deviceHostId ?? ''}/${project.id}';
    final plan = await service.plan(
      remoteRoot: deviceRoot,
      localRoot: copyRoot,
      cacheKey: cacheKey,
    );
    final report = await service.apply(plan, onProgress: onProgress);
    if (report.completed) {
      project
        ..filesPulled = true
        ..placeholder = false;
    }
    return report;
  }

  /// Delete the placeholder when its session ends and no files were pulled.
  ///
  /// A project the user pulled files into keeps its directory: it is now a real
  /// project and the session ending must not delete the user's code.
  Future<bool> discardIfUnused(Project project) async {
    if (!project.placeholder || project.filesPulled) return false;
    final directory = Directory(project.path);
    if (!await directory.exists()) return true;
    // Only remove a directory this class created, never a user folder.
    if (!project.isDevice || project.deviceSessionId == null) return false;
    try {
      await directory.delete(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Session ids and project ids become path segments, so keep them plain.
  static String _safeSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'session' : cleaned;
  }
}
