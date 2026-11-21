/// The current phase of one independent repository clone.
enum GitCloneStage {
  preparing,
  connecting,
  receiving,
  resolving,
  checkout,
  registering,
}

/// Structured, secret-free progress for a single clone operation.
class GitCloneProgress {
  const GitCloneProgress({
    required this.stage,
    this.completed = 0,
    this.total = 0,
    this.receivedBytes = 0,
  });

  final GitCloneStage stage;
  final int completed;
  final int total;
  final int receivedBytes;

  /// Returns a bounded fraction when Git reports a non-zero total.
  double? get fraction {
    if (total <= 0) return null;
    return (completed / total).clamp(0.0, 1.0).toDouble();
  }
}

typedef GitCloneProgressCallback = void Function(GitCloneProgress progress);

/// Invokes a UI progress listener without allowing it to change clone outcome.
void emitGitCloneProgress(
  GitCloneProgressCallback? callback,
  GitCloneProgress progress,
) {
  try {
    callback?.call(progress);
  } on Object {
    // Progress observers are best-effort and must not abort a clone.
  }
}
