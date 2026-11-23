import 'package:qfli_studio_core/git/git_backend.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/sync_limits.dart';

/// How a device project pull ended.
enum GitPullOutcome {
  /// The repository was cloned into the local project directory.
  cloned,

  /// An existing clone was fast-forwarded instead of transferred.
  pulled,

  /// The computer reports a clone large enough to ask the user first.
  needsConfirm,

  /// The project is not a usable repository; use the file sync path.
  fallbackToFiles,

  /// The device is not paired, or the agent does not support the request.
  blocked,
}

/// Result of one attempt to pull a device project through git.
class GitPullReport {
  const GitPullReport(this.outcome, {this.reason, this.gitBytes});

  const GitPullReport.blocked(String this.reason)
    : outcome = GitPullOutcome.blocked,
      gitBytes = null;

  final GitPullOutcome outcome;

  /// Set for [GitPullOutcome.blocked] and [GitPullOutcome.fallbackToFiles].
  final String? reason;

  /// Reported size of `.git` on the computer, when known.
  final int? gitBytes;

  bool get needsUserConfirm => outcome == GitPullOutcome.needsConfirm;
}

/// Decides whether a device project can be pulled through git, and pulls it.
///
/// The class owns only the decision and the clone call: the protocol request
/// that fetches [GitProjectInfo] lives in the remote port, and the local clone
/// goes through [GitBackendFactory] so the desktop and the phone share one
/// path. It never writes into the user's own project directory: the clone
/// target is supplied by the caller.
class DeviceGitPull {
  const DeviceGitPull();

  /// Decide what to do with [info] before any byte is transferred.
  ///
  /// A missing remote or an unsupported repository falls back to file sync
  /// instead of failing: the user asked to get the project onto the phone, and
  /// the transfer path can still do that.
  GitPullReport decide(
    GitProjectInfo info, {
    int confirmBytes = kGitConfirmBytes,
  }) {
    if (!info.supported) {
      return const GitPullReport(
        GitPullOutcome.fallbackToFiles,
        reason: '该目录不是可直接读取的 Git 仓库',
      );
    }
    if (!info.canClone) {
      return const GitPullReport(
        GitPullOutcome.fallbackToFiles,
        reason: '仓库没有 origin 远端',
      );
    }
    final bytes = info.gitBytes;
    if (bytes != null && bytes > confirmBytes) {
      return GitPullReport(GitPullOutcome.needsConfirm, gitBytes: bytes);
    }
    return GitPullReport(GitPullOutcome.cloned, gitBytes: bytes);
  }

  /// Clone [info] into [target] or fast-forward an existing clone there.
  ///
  /// Returns [GitPullOutcome.needsConfirm] without touching the filesystem when
  /// the size gate trips and [confirmed] is false, so a caller that shows the
  /// prompt first can call again with `confirmed: true`.
  Future<GitPullReport> pull(
    GitProjectInfo info, {
    required String target,
    required bool targetExists,
    bool confirmed = false,
    int confirmBytes = kGitConfirmBytes,
    GitCredentials? credentials,
    GitCloneCancellation? cancellation,
    GitCloneProgressCallback? onProgress,
  }) async {
    final decision = decide(info, confirmBytes: confirmBytes);
    if (decision.outcome == GitPullOutcome.needsConfirm && !confirmed) {
      return decision;
    }
    if (decision.outcome != GitPullOutcome.cloned &&
        decision.outcome != GitPullOutcome.needsConfirm) {
      return decision;
    }

    final url = info.remote!;
    if (targetExists) {
      final backend = GitBackendFactory.open(target);
      try {
        await backend.fetch(credentials: credentials);
        return GitPullReport(
          GitPullOutcome.pulled,
          gitBytes: decision.gitBytes,
        );
      } finally {
        await backend.dispose();
      }
    }
    await GitBackendFactory.clone(
      url: url,
      path: target,
      credentials: credentials,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    return GitPullReport(GitPullOutcome.cloned, gitBytes: decision.gitBytes);
  }
}
