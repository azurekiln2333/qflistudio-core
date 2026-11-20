import 'dart:io';

import 'package:path/path.dart' as p;

import '../git/git_backend.dart';
import '../models/project.dart';
import '../store/project_store.dart';
import 'app_paths.dart';
import 'project_config.dart';

/// One clone request entered on Home.
///
/// Credentials are optional and live only for this operation. The token is never
/// rendered, persisted or put into the repository URL.
class GitCloneRequest {
  const GitCloneRequest({
    required this.url,
    this.name = '',
    this.username = '',
    this.token = '',
  });

  final String url;
  final String name;
  final String username;
  final String token;

  bool get hasCredentials => token.isNotEmpty;

  GitCredentials? get credentials => hasCredentials
      ? GitCredentials(username: username.trim(), token: token)
      : null;

  @override
  String toString() =>
      'GitCloneRequest($url, name=$name, '
      'credentials=${hasCredentials ? 'provided' : 'none'})';
}

/// Runs an actual clone into an already reserved, empty [path].
typedef GitCloneRunner =
    Future<void> Function({
      required String url,
      required String path,
      GitCredentials? credentials,
      GitCloneCancellation? cancellation,
    });

/// Reserves a fresh, exclusively owned destination directory for a clone.
///
typedef GitDestinationAllocator =
    Future<GitCloneDestination?> Function({required String name});

/// A destination directory this operation alone created.
///
/// [path] comes from a create-exclusive call, so no other actor can own it.
/// [displayName] is the name the user asked for; the directory itself may carry
/// a random suffix.
class GitCloneDestination {
  const GitCloneDestination({required this.path, required this.displayName});

  final String path;
  final String displayName;
}

/// A completed clone request outcome.
class GitCloneOutcome {
  const GitCloneOutcome({
    this.project,
    this.error,
    this.path,
    this.preservedPath,
    this.cancelled = false,
  });

  final Project? project;
  final String? error;
  final String? path;

  /// Set when clone data was deliberately kept after registration failed.
  final String? preservedPath;
  final bool cancelled;

  bool get ok => error == null && !cancelled && project != null;
}

/// Clone coordinator: reserve a new AppPaths destination, run real Git, then
/// register the project with [ProjectStore].
///
/// Cleanup only ever deletes the directory this operation created. Registration
/// writes `.qfli/project.json`; that metadata is never staged or auto-ignored.
class GitCloneService {
  GitCloneService({
    required this.store,
    GitCloneRunner? cloneRunner,
    GitDestinationAllocator? allocateDestination,
    bool? desktop,
  }) : _clone = cloneRunner ?? _factoryClone,
       _allocate = allocateDestination ?? _defaultAllocate,
       _desktop = desktop ?? AppPaths.isDesktop;

  final ProjectStore store;
  final GitCloneRunner _clone;
  final GitDestinationAllocator _allocate;
  final bool _desktop;

  Future<GitCloneOutcome> clone(
    GitCloneRequest request, {
    GitCloneCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      return const GitCloneOutcome(cancelled: true);
    }
    final url = request.url.trim();
    final urlError = gitCloneUrlError(url, desktop: _desktop);
    if (urlError != null) return GitCloneOutcome(error: urlError);

    final name = cloneProjectName(url, request.name);
    GitCloneDestination? destination;
    try {
      destination = await _allocate(name: name);
    } on Object catch (error) {
      return GitCloneOutcome(error: '无法准备项目目录：$error');
    }
    if (destination == null || destination.path.trim().isEmpty) {
      return const GitCloneOutcome(error: '未找到可写的项目目录');
    }
    // The allocator created this directory exclusively, so it is ours alone.
    final path = p.normalize(p.absolute(destination.path));
    final displayName = destination.displayName.trim().isEmpty
        ? p.basename(path)
        : destination.displayName.trim();
    // Cancellation can arrive while the destination is being allocated. The
    // directory is already ours, so drop it now and never start the clone.
    if (cancellation?.isCancelled == true) {
      await _removeOwnedPath(path);
      return const GitCloneOutcome(cancelled: true);
    }

    try {
      await _clone(
        url: url,
        path: path,
        credentials: request.credentials,
        cancellation: cancellation,
      );
    } on GitOperationException catch (error) {
      await _removeOwnedPath(path);
      if (error.kind == 'cancelled' || cancellation?.isCancelled == true) {
        return GitCloneOutcome(cancelled: true);
      }
      return GitCloneOutcome(error: error.message, path: path);
    } on Object catch (error) {
      await _removeOwnedPath(path);
      if (cancellation?.isCancelled == true) {
        return GitCloneOutcome(cancelled: true);
      }
      return GitCloneOutcome(error: '克隆失败：$error', path: path);
    }

    try {
      // The directory carries a random suffix, so record the wanted name in
      // project metadata first; registration reads it back from there. A
      // cloned repository may ship its own `.qfli/project.json`, so keep its
      // language and type instead of blanking real metadata.
      final metadata = ProjectConfig.readMetadata(path);
      await ProjectConfig.write(
        projectRoot: path,
        name: displayName,
        language: metadata.language ?? '',
        type: metadata.type ?? '',
        // A silent failure here would register the project under the random
        // directory name while reporting the requested name.
        strict: true,
      );
      final result = await store.addExisting(path);
      if (result.error != null || result.project == null) {
        return GitCloneOutcome(
          error: result.error ?? '项目注册失败',
          path: path,
          preservedPath: path,
        );
      }
      return GitCloneOutcome(project: result.project, path: path);
    } on Object catch (error) {
      return GitCloneOutcome(
        error: '项目注册失败：$error',
        path: path,
        preservedPath: path,
      );
    }
  }

  static Future<void> _factoryClone({
    required String url,
    required String path,
    GitCredentials? credentials,
    GitCloneCancellation? cancellation,
  }) {
    return GitBackendFactory.clone(
      url: url,
      path: path,
      credentials: credentials,
      cancellation: cancellation,
    );
  }

  /// Creates the destination exclusively.
  ///
  /// `createTemp` asks the filesystem for a name that did not exist a moment
  /// ago, so two concurrent clones never share a path and cleanup can never
  /// delete a directory another actor created.
  static Future<GitCloneDestination?> _defaultAllocate({
    required String name,
  }) async {
    final root = await AppPaths.projectsRoot(create: true);
    if (root == null) return null;
    final parent = Directory(root);
    final prefix = '${_sanitizeSegment(name).isEmpty ? 'clone' : name}_';
    final created = await parent.createTemp(prefix);
    return GitCloneDestination(path: created.path, displayName: name);
  }

  static Future<void> _removeOwnedPath(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // A cleanup failure must not turn a failed clone into a success report.
    }
  }
}

/// URL validation shared by clone, remote configuration and dialogs.
///
/// Embedded `user:token@` credentials are rejected: host credentials belong to
/// one operation and must never live in a repository URL or Git config.
String? validateGitRemoteUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return '请填写仓库地址';
  if (url.length > 2048) return '仓库地址过长';
  if (RegExp(r'\s').hasMatch(url)) return '仓库地址不能包含空格';
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://[^/@]*@').hasMatch(url)) {
    return '仓库地址不能包含用户名或令牌';
  }
  final scpLike = RegExp(r'^[^@/\s]+@[^:/\s]+:.+$');
  final uri = Uri.tryParse(url);
  final accepted =
      url.startsWith('https://') ||
      url.startsWith('http://') ||
      url.startsWith('ssh://') ||
      url.startsWith('git://') ||
      scpLike.hasMatch(url) ||
      (uri != null && uri.scheme == 'file' && uri.path.isNotEmpty);
  return accepted ? null : '请使用 HTTPS、SSH 或 file 地址';
}

/// Clone-specific validation: native adapters support HTTPS only.
String? gitCloneUrlError(String raw, {required bool desktop}) {
  final base = validateGitRemoteUrl(raw);
  if (base != null) return base;
  if (!desktop && !raw.trim().startsWith('https://')) {
    return '移动端 Git 克隆仅支持 HTTPS 地址';
  }
  return null;
}

/// Derives a display/project directory name from a repository URL.
///
/// [preferred] wins when non-empty. Otherwise the last path segment is used and
/// a trailing `.git` is removed. Invalid filesystem characters become `_`.
String cloneProjectName(String url, String preferred) {
  final cleanedPreferred = _sanitizeSegment(preferred);
  if (cleanedPreferred.isNotEmpty) return cleanedPreferred;

  var pathPart = url.trim();
  final uri = Uri.tryParse(pathPart);
  if (uri != null && uri.hasScheme && uri.path.isNotEmpty) {
    pathPart = uri.path;
  } else {
    final scp = RegExp(r'^[^@/\s]+@[^:/\s]+:(.+)$').firstMatch(pathPart);
    if (scp != null) pathPart = scp.group(1)!;
  }
  final segments = pathPart
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  var base = segments.isEmpty ? '' : segments.last;
  if (base.toLowerCase().endsWith('.git')) {
    base = base.substring(0, base.length - 4);
  }
  final sanitized = _sanitizeSegment(base);
  if (sanitized.isNotEmpty) return sanitized;
  return 'clone_${DateTime.now().millisecondsSinceEpoch}';
}

String _sanitizeSegment(String value) {
  var name = value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name == '.' || name == '..') return '';
  if (name.length > 80) name = name.substring(0, 80);
  return name.trim();
}
