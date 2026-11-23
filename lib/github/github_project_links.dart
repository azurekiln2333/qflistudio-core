import 'dart:convert';
import 'dart:io';

import '../git/git_backend.dart';
import '../models/project.dart';
import '../services/local_store_backend.dart';
import 'github_models.dart';

/// Credential-free links to the existing project registry. Disconnecting an
/// account never edits this file or removes a local checkout.
class GitHubProjectLinks {
  GitHubProjectLinks({LocalStoreBackend? backend})
    : _backend = backend ?? const LocalFileBackend('github_project_links.json');

  final LocalStoreBackend _backend;
  final _links = <String, String>{};
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  String _key(GitHubRepository repository) =>
      '${Uri.parse(repository.cloneUrl).host.toLowerCase()}:${repository.id}';

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final payload = await _backend.read();
      if (payload == null) return;
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['version'] != 1) return;
      final links = decoded['links'];
      if (links is! Map) return;
      for (final entry in links.entries) {
        if (entry.key is String && entry.value is String) {
          _links[entry.key as String] = entry.value as String;
        }
      }
    } on Object {
      // Invalid optional metadata does not hide registered projects.
    }
  }

  Project? projectFor(GitHubRepository repository, Iterable<Project> projects) {
    final id = _links[_key(repository)];
    for (final project in projects) {
      if (project.id == id && !project.isCloud) return project;
    }
    return null;
  }

  Future<void> link(GitHubRepository repository, Project project) async {
    await load();
    _links[_key(repository)] = project.id;
    final payload = jsonEncode({'version': 1, 'links': _links});
    final write = _writes
        .catchError((Object _) {})
        .then((_) => _backend.write(payload));
    _writes = write;
    await write;
  }

  /// Older clones have no link file. Match their Git remote identity once,
  /// using the same backend as the existing Git UI, without any network call.
  Future<Project?> findExisting(
    GitHubRepository repository,
    Iterable<Project> projects,
  ) async {
    await load();
    final candidates = projects.where((project) => !project.isCloud).toList();
    final linked = projectFor(repository, candidates);
    if (linked != null && await Directory(linked.path).exists()) return linked;
    final identity = repositoryIdentity(repository.cloneUrl);
    if (identity == null) return null;
    for (final project in candidates) {
      if (!await Directory(project.path).exists()) continue;
      GitBackend? git;
      try {
        git = GitBackendFactory.open(project.path);
        final snapshot = await git.snapshot();
        if (!snapshot.isRepository ||
            !snapshot.remotes.any(
              (remote) => repositoryIdentity(remote.url) == identity,
            )) {
          continue;
        }
        try {
          await link(repository, project);
        } on Object {
          // A metadata write failure must never trigger a duplicate clone.
        }
        return project;
      } on Object {
        // An unavailable Git backend does not alter the local checkout.
      } finally {
        await git?.dispose();
      }
    }
    return null;
  }

  /// Compare HTTPS and SSH remotes without retaining user info or credentials.
  static String? repositoryIdentity(String remote) {
    final value = remote.trim();
    final scp = RegExp(r'^(?:[^@/]+@)?([^:/]+):([^/].+)$').firstMatch(value);
    final Uri? uri;
    if (!value.contains('://') && scp != null) {
      uri = Uri.tryParse('ssh://${scp[1]}/${scp[2]}');
    } else {
      uri = Uri.tryParse(value);
    }
    if (uri == null || !['https', 'ssh', 'git', 'http'].contains(uri.scheme)) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (host != 'github.com') return null;
    var path = uri.path.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    if (path.split('/').length != 2 ||
        path.split('/').any((part) => part.isEmpty)) {
      return null;
    }
    return '$host/$path';
  }
}
