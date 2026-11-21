import 'dart:io';

import 'cli_git_backend.dart';
import 'git_cancellation.dart';
import 'git_clone_progress.dart';
import 'git_models.dart';
import 'native_git_backend.dart';

export 'git_cancellation.dart';
export 'git_clone_progress.dart';
export 'git_models.dart';

abstract class GitBackend {
  String get root;
  GitBackendKind get kind;
  Future<GitSnapshot> snapshot();
  Future<void> init();
  Future<void> stage(List<String> paths);
  Future<void> unstage(List<String> paths);
  Future<void> stageAll();
  Future<GitDiffData> diff(String path, {required GitChangeArea area});
  Future<List<GitCommitInfo>> history({int limit = 20});
  Future<String> commit(String message, GitIdentity identity);
  Future<void> createBranch(String name);
  Future<void> checkout(String name);
  Future<GitMergeResult> merge(String ref, GitIdentity identity);
  Future<String> completeMerge(String message, GitIdentity identity);
  Future<void> setRemote(String name, String url);
  Future<void> fetch({String remote = 'origin', GitCredentials? credentials});
  Future<void> push({String remote = 'origin', GitCredentials? credentials});
  Future<void> pullRebase();
  void cancelNetwork();
  Future<void> dispose();
}

abstract final class GitBackendFactory {
  static bool get _desktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static GitBackend open(String root) {
    if (_desktop) return CliGitBackend(root);
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.operatingSystem == 'ohos') {
      return NativeGitBackend(root);
    }
    throw const GitOperationException('当前平台不支持本地 Git', kind: 'unsupported');
  }

  static Future<void> clone({
    required String url,
    required String path,
    GitCredentials? credentials,
    GitCloneCancellation? cancellation,
    GitCloneProgressCallback? onProgress,
  }) async {
    if (_desktop) {
      await CliGitBackend.cloneRepository(
        url: url,
        path: path,
        credentials: credentials,
        cancellation: cancellation,
        onProgress: onProgress,
      );
    } else if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.operatingSystem == 'ohos') {
      await NativeGitBackend.cloneRepository(
        url: url,
        path: path,
        credentials: credentials,
        cancellation: cancellation,
        onProgress: onProgress,
      );
    } else {
      throw const GitOperationException('当前平台不支持本地 Git', kind: 'unsupported');
    }
  }
}
