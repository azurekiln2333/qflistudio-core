enum GitBackendKind { cli, native }

enum GitChangeArea { worktree, staged }

enum GitMergeResult { upToDate, fastForward, merged, conflicts }

class GitOperationException implements Exception {
  const GitOperationException(this.message, {this.kind = 'operation'});
  final String message;
  final String kind;

  @override
  String toString() => message;
}

class GitIdentity {
  const GitIdentity({required this.name, required this.email});
  final String name;
  final String email;
}

class GitCredentials {
  const GitCredentials({required this.username, required this.token});
  final String username;
  final String token;

  @override
  String toString() => 'GitCredentials(redacted)';
}

class GitChange {
  const GitChange({
    required this.path,
    this.staged = false,
    this.unstaged = false,
    this.untracked = false,
    this.conflict = false,
    this.oldPath,
  });
  final String path;
  final bool staged;
  final bool unstaged;
  final bool untracked;
  final bool conflict;
  final String? oldPath;
}

class GitBranchInfo {
  const GitBranchInfo({
    required this.name,
    this.current = false,
    this.remote = false,
    this.upstream,
  });
  final String name;
  final bool current;
  final bool remote;
  final String? upstream;
}

class GitRemoteInfo {
  const GitRemoteInfo({required this.name, required this.url});
  final String name;
  final String url;
}

class GitCommitInfo {
  const GitCommitInfo({
    required this.oid,
    required this.message,
    required this.authorName,
    required this.authorEmail,
    required this.time,
  });
  final String oid;
  final String message;
  final String authorName;
  final String authorEmail;
  final DateTime time;
}

class GitDiffData {
  const GitDiffData({
    this.patch = '',
    this.binary = false,
    this.truncated = false,
  });
  final String patch;
  final bool binary;
  final bool truncated;
}

class GitSnapshot {
  const GitSnapshot({
    required this.isRepository,
    this.branch,
    this.oid,
    this.state = 'clean',
    this.changes = const [],
    this.branches = const [],
    this.remotes = const [],
    this.conflicts = const [],
  });
  final bool isRepository;
  final String? branch;
  final String? oid;
  final String state;
  final List<GitChange> changes;
  final List<GitBranchInfo> branches;
  final List<GitRemoteInfo> remotes;
  final List<String> conflicts;
}
