/// A Git operation that can rewrite files under one project root.
///
/// The Git page builds this before checkout, merge and pull. The editor answers
/// it with a real dirty-buffer check, so a worktree rewrite never discards
/// unsaved source text.
class GitWorktreeChangeRequest {
  const GitWorktreeChangeRequest({
    required this.root,
    required this.operation,
    this.paths = const [],
  });

  /// Absolute project root the operation targets.
  final String root;

  /// Short user-facing operation name, for example `切换到 dev`.
  final String operation;

  /// Repository-relative paths the operation may touch.
  ///
  /// Empty means every path under [root].
  final List<String> paths;

  bool get touchesWholeRoot => paths.isEmpty;
}

/// Asks the editor whether a worktree-changing Git operation may proceed.
///
/// Returning `false` cancels the operation. Implementations must resolve dirty
/// buffers by saving or by explicit user consent and must never force-reload a
/// dirty document.
typedef GitWorktreeGuard =
    Future<bool> Function(GitWorktreeChangeRequest request);

/// Called after a Git operation ran under [root].
///
/// The editor refreshes its tree and reloads only clean buffers. [
/// diskMayHaveChanged] is true when the operation reported failure but could
/// still have rewritten files (a stopped merge, rebase or checkout), so clean
/// buffers must be reloaded even though the action did not succeed. Dirty
/// buffers are never force-reloaded either way.
typedef GitWorktreeChanged =
    Future<void> Function(String root, {bool diskMayHaveChanged});
