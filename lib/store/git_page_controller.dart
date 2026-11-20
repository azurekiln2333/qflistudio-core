import 'dart:async';

import 'package:flutter/foundation.dart';

import '../git/git_backend.dart';

/// One line of the operation log shown below the repository controls.
@immutable
class GitLogLine {
  const GitLogLine(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// Result of a read-only Git query.
///
/// Keeps the error text next to the value so a dialog can show a real failure
/// instead of an empty success state.
class GitQueryResult<T> {
  const GitQueryResult.value(this.value) : error = null;
  const GitQueryResult.failure(this.error) : value = null;

  final T? value;
  final String? error;

  bool get ok => error == null;
}

/// In-memory commit author identity.
///
/// Non-secret, so it may be remembered for the app session. It is deliberately
/// not written to `auth.json`, project config or Git config in this task.
class GitIdentityStore {
  GitIdentityStore({GitIdentity? initial}) : identity = initial;

  static final GitIdentityStore shared = GitIdentityStore();

  GitIdentity? identity;
}

/// Owns one local repository page session.
///
/// Every awaited operation is guarded by a monotonically increasing token.
/// A stale completion never publishes state, never clears a newer operation's
/// busy label and never reports success after disposal.
class GitPageController extends ChangeNotifier {
  GitPageController({
    required this.backend,
    GitIdentityStore? identityStore,
    GitCredentials? credentials,
  }) : _identityStore = identityStore ?? GitIdentityStore.shared,
       _credentials = credentials;

  final GitBackend backend;
  final GitIdentityStore _identityStore;

  GitSnapshot? _snapshot;
  final List<GitLogLine> _log = [];
  String? _busyLabel;
  String? _error;
  bool _networkOperation = false;
  bool _disposed = false;
  bool _closed = false;
  bool _notifierDisposed = false;
  Future<void>? _closeFuture;
  int _opToken = 0;
  GitCredentials? _credentials;
  GitMergeResult? _lastMergeResult;

  GitSnapshot? get snapshot => _snapshot;
  List<GitLogLine> get log => List.unmodifiable(_log);
  String? get busyLabel => _busyLabel;
  bool get isBusy => _busyLabel != null;
  bool get isNetworkOperation => _networkOperation;
  String? get error => _error;
  GitMergeResult? get lastMergeResult => _lastMergeResult;

  String get root => backend.root;
  GitBackendKind get kind => backend.kind;
  bool get isRepository => _snapshot?.isRepository ?? false;
  String? get branch => _snapshot?.branch;
  String get state => _snapshot?.state ?? '';
  List<String> get conflicts => _snapshot?.conflicts ?? const [];

  GitIdentity? get identity => _identityStore.identity;
  GitCredentials? get credentials => _credentials;
  bool get canPullRebase => backend.kind == GitBackendKind.cli;

  String get backendLabel => switch (backend.kind) {
    GitBackendKind.cli => '本机 Git CLI',
    GitBackendKind.native => '原生 Git 插件',
  };

  /// Changes that are fully or partly staged.
  List<GitChange> get stagedChanges =>
      (_snapshot?.changes ?? const <GitChange>[])
          .where((change) => change.staged)
          .toList();

  /// Changes that still have worktree content, including conflicts.
  List<GitChange> get unstagedChanges =>
      (_snapshot?.changes ?? const <GitChange>[])
          .where(
            (change) => change.unstaged || change.untracked || change.conflict,
          )
          .toList();

  List<GitRemoteInfo> get remotes => _snapshot?.remotes ?? const [];
  List<GitBranchInfo> get branches => _snapshot?.branches ?? const [];

  void setIdentity(GitIdentity? value) {
    _identityStore.identity = value;
  }

  void rememberCredentials(GitCredentials? value) {
    _credentials = value;
  }

  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed || _closed) return;
    if (_busyLabel != null) return;
    final token = ++_opToken;
    _busyLabel = '读取仓库状态…';
    _error = null;
    _notify();
    final failure = await _reloadSnapshot(token);
    if (_disposed || token != _opToken) return;
    if (failure != null) {
      _error = failure;
      _appendLog(failure, isError: true);
    }
    _busyLabel = null;
    _notify();
  }

  Future<String?> initRepository() =>
      _mutate('初始化 Git 仓库…', () => backend.init(), successLabel: '已初始化 Git 仓库');

  Future<String?> stage(GitChange change) => _mutate(
    '暂存文件…',
    () => backend.stage([change.path]),
    successLabel: '已暂存 ${change.path}',
  );

  Future<String?> unstage(GitChange change) => _mutate(
    '取消暂存…',
    // A displayed rename has one path but two index entries. Resetting only
    // the new path would leave the old one staged as a deletion.
    () => backend.unstage(<String>[
      if (change.oldPath != null && change.oldPath != change.path)
        change.oldPath!,
      change.path,
    ]),
    successLabel: '已取消暂存 ${change.path}',
  );

  Future<String?> stageAll() =>
      _mutate('暂存全部改动…', () => backend.stageAll(), successLabel: '已暂存全部改动');

  Future<String?> createBranch(String name) => _mutate(
    '创建分支…',
    () => backend.createBranch(name),
    successLabel: '已创建分支 $name',
  );

  /// Switches to a local branch.
  ///
  /// Remote-tracking refs are merge targets, not checkouts: the adapters would
  /// either refuse them or detach HEAD, which the push path then rejects.
  Future<String?> checkout(String name) {
    final snapshot = _snapshot;
    final isRemoteOnly =
        snapshot != null &&
        snapshot.branches.any((b) => b.remote && b.name == name) &&
        !snapshot.branches.any((b) => !b.remote && b.name == name);
    if (isRemoteOnly) {
      return Future.value('远端分支不能直接切换，请先创建同名本地分支');
    }
    return _mutate(
      '切换分支…',
      () => backend.checkout(name),
      successLabel: '已切换到分支 $name',
    );
  }

  Future<String?> setRemote(String name, String url) => _mutate(
    '保存远程仓库…',
    () => backend.setRemote(name, url),
    successLabel: '已保存远程仓库 $name',
  );

  Future<String?> fetch({GitCredentials? credentials}) => _mutate(
    '获取远端…',
    () => backend.fetch(credentials: credentials),
    successLabel: '已完成获取',
    network: true,
  );

  Future<String?> push({GitCredentials? credentials}) => _mutate(
    '推送当前分支…',
    () => backend.push(credentials: credentials),
    successLabel: '已推送当前分支',
    network: true,
  );

  Future<String?> pullRebase() {
    if (!canPullRebase) {
      return Future.value('当前平台不支持拉取变基，请分别执行获取和合并');
    }
    return _mutate(
      '拉取并变基…',
      () => backend.pullRebase(),
      successLabel: '已完成拉取并变基',
      network: true,
    );
  }

  /// Commits the index only. Never stages or infers paths.
  Future<String?> commit(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return '提交信息不能为空';
    if (trimmed.contains('\u0000')) return '提交信息无效';
    final identity = _identityStore.identity;
    if (identity == null ||
        identity.name.trim().isEmpty ||
        identity.email.trim().isEmpty ||
        !identity.email.contains('@')) {
      return '请先填写提交作者和邮箱';
    }
    if (_disposed || _closed) return '页面已关闭';
    if (_busyLabel != null) return '有 Git 操作正在进行，请稍候';
    final token = _begin('提交已暂存的文件…', network: false);
    try {
      final oid = await backend.commit(trimmed, identity);
      if (_stale(token)) return null;
      _appendLog('已提交 ${_shortOid(oid)}');
    } on GitOperationException catch (error) {
      return _fail(token, _messageOf(error));
    } on Object catch (error) {
      return _fail(token, '提交失败：$error');
    }
    await _finish(token);
    return null;
  }

  /// Merges [ref] and keeps the typed outcome for the caller.
  ///
  /// Conflicts are a real merge result, not an exception: the snapshot refresh
  /// afterwards shows the conflicted files so the page can offer completion.
  Future<String?> merge(String ref, GitIdentity identity) async {
    final trimmedRef = ref.trim();
    if (!_isSafeRef(trimmedRef)) return '合并目标无效';
    if (identity.name.trim().isEmpty || !identity.email.contains('@')) {
      return '请先填写提交作者和邮箱';
    }
    if (_disposed || _closed) return '页面已关闭';
    if (_busyLabel != null) return '有 Git 操作正在进行，请稍候';
    _lastMergeResult = null;
    final token = _begin('合并 $trimmedRef…', network: false);
    try {
      final result = await backend.merge(trimmedRef, identity);
      if (_stale(token)) return null;
      _lastMergeResult = result;
      switch (result) {
        case GitMergeResult.upToDate:
          _appendLog('已是最新，无需合并');
        case GitMergeResult.fastForward:
          _appendLog('已完成快进合并');
        case GitMergeResult.merged:
          _appendLog('已生成合并提交');
        case GitMergeResult.conflicts:
          _appendLog('合并产生冲突，请解决后完成合并', isError: true);
      }
    } on GitOperationException catch (error) {
      return _fail(token, _messageOf(error));
    } on Object catch (error) {
      return _fail(token, '合并失败：$error');
    }
    await _finish(token);
    return null;
  }

  Future<String?> completeMerge(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return '提交信息不能为空';
    final identity = _identityStore.identity;
    if (identity == null ||
        identity.name.trim().isEmpty ||
        !identity.email.contains('@')) {
      return '请先填写提交作者和邮箱';
    }
    if (_disposed || _closed) return '页面已关闭';
    if (_busyLabel != null) return '有 Git 操作正在进行，请稍候';
    final token = _begin('完成合并提交…', network: false);
    try {
      final oid = await backend.completeMerge(trimmed, identity);
      if (_stale(token)) return null;
      _appendLog('已完成合并提交 ${_shortOid(oid)}');
    } on GitOperationException catch (error) {
      return _fail(token, _messageOf(error));
    } on Object catch (error) {
      return _fail(token, '完成合并失败：$error');
    }
    await _finish(token);
    return null;
  }

  Future<GitQueryResult<GitDiffData>> diff(
    GitChange change, {
    required GitChangeArea area,
  }) async {
    if (_disposed || _closed) {
      return const GitQueryResult.failure('页面已关闭');
    }
    if (_busyLabel != null) {
      return const GitQueryResult.failure('有 Git 操作正在进行，请稍候');
    }
    // A read owns the busy state too: two dialogs must not race the same
    // repository, and a mutation must not start while a diff is in flight.
    final token = _begin('读取差异…', network: false);
    try {
      final data = await backend.diff(change.path, area: area);
      if (_stale(token)) return const GitQueryResult.failure('页面已关闭');
      return GitQueryResult.value(data);
    } on GitOperationException catch (error) {
      if (_stale(token)) return const GitQueryResult.failure('页面已关闭');
      return _queryFailure(_messageOf(error));
    } on Object catch (error) {
      if (_stale(token)) return const GitQueryResult.failure('页面已关闭');
      return _queryFailure('读取差异失败：$error');
    } finally {
      _endQuery(token);
    }
  }

  Future<GitQueryResult<List<GitCommitInfo>>> history({int limit = 30}) async {
    if (_disposed || _closed) {
      return const GitQueryResult.failure('页面已关闭');
    }
    if (_busyLabel != null) {
      return const GitQueryResult.failure('有 Git 操作正在进行，请稍候');
    }
    final token = _begin('读取历史…', network: false);
    try {
      final commits = await backend.history(limit: limit);
      if (_stale(token)) return const GitQueryResult.failure('页面已关闭');
      return GitQueryResult.value(commits);
    } on GitOperationException catch (error) {
      if (_stale(token)) return const GitQueryResult.failure('页面已关闭');
      return _queryFailure(_messageOf(error));
    } on Object catch (error) {
      if (_stale(token)) return const GitQueryResult.failure('页面已关闭');
      return _queryFailure('读取历史失败：$error');
    } finally {
      _endQuery(token);
    }
  }

  /// Signals a running network operation to stop.
  ///
  /// The adapter still owns completion; this only requests cancellation so a
  /// transport cannot be abandoned with a live handle.
  void cancelNetwork() {
    if (_disposed || _closed || !_networkOperation) return;
    try {
      backend.cancelNetwork();
      _appendLog('已请求取消网络操作');
    } on Object catch (error) {
      _appendLog('取消请求失败：$error', isError: true);
    }
  }

  /// Idempotent close; every caller awaits the same teardown.
  Future<void> close() => _closeFuture ??= _shutdown();

  @override
  void dispose() {
    unawaited(close());
    // Listeners must be released synchronously with the widget tree even
    // though the native teardown still runs in the background. The flag keeps
    // a later [close] from releasing them twice.
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }

  /// Runs teardown at most once; repeat callers await the same disposal.
  Future<void> _shutdown() async {
    if (_closed) return;
    _closed = true;
    _disposed = true;
    _opToken++;
    try {
      backend.cancelNetwork();
    } on Object {
      // Cancellation of an already-finished operation is harmless.
    }
    try {
      // Await the real teardown: reporting closure early would let a live
      // native handle outlive the page.
      await backend.dispose();
    } on Object {
      // Disposal failures must not surface as a successful operation.
    }
    _disposeNotifier();
  }

  /// Releases [ChangeNotifier] exactly once, whichever path runs first.
  void _disposeNotifier() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    super.dispose();
  }

  int _begin(String label, {required bool network}) {
    final token = ++_opToken;
    _busyLabel = label;
    _networkOperation = network;
    _error = null;
    _notify();
    return token;
  }

  Future<String?> _mutate(
    String label,
    Future<void> Function() action, {
    String? successLabel,
    bool network = false,
  }) async {
    if (_disposed || _closed) return '页面已关闭';
    if (_busyLabel != null) return '有 Git 操作正在进行，请稍候';
    final token = _begin(label, network: network);
    try {
      await action();
      if (_stale(token)) return null;
    } on GitOperationException catch (error) {
      return _fail(token, _messageOf(error));
    } on Object catch (error) {
      return _fail(token, '操作失败：$error');
    }
    if (successLabel != null) _appendLog(successLabel);
    await _finish(token);
    return null;
  }

  Future<String?> _reloadSnapshot(int token) async {
    try {
      final snapshot = await backend.snapshot();
      if (_stale(token)) return null;
      _snapshot = snapshot;
      return null;
    } on GitOperationException catch (error) {
      if (_stale(token)) return null;
      return _messageOf(error);
    } on Object catch (error) {
      if (_stale(token)) return null;
      return '读取仓库状态失败：$error';
    }
  }

  Future<void> _finish(int token) async {
    if (!_stale(token)) {
      final failure = await _reloadSnapshot(token);
      if (failure != null && !_stale(token)) {
        _appendLog('操作已完成，但刷新状态失败：$failure', isError: true);
      }
    }
    if (_stale(token)) return;
    _busyLabel = null;
    _networkOperation = false;
    _notify();
  }

  Future<String?> _fail(int token, String message) async {
    if (_stale(token)) return null;
    _error = message;
    _appendLog(message, isError: true);
    // A failed mutation may already have touched the index or the worktree:
    // a conflicted merge/pull leaves markers behind, and a refused checkout can
    // still move files. Refresh so the page never shows stale state beside the
    // failure, and keep the original error on screen.
    final failure = await _reloadSnapshot(token);
    if (_stale(token)) return null;
    if (failure != null) {
      _appendLog('刷新状态失败：$failure', isError: true);
    }
    _busyLabel = null;
    _networkOperation = false;
    _notify();
    return message;
  }

  GitQueryResult<T> _queryFailure<T>(String message) {
    _error = message;
    _appendLog(message, isError: true);
    return GitQueryResult.failure(message);
  }

  /// Releases the busy state owned by a read-only query.
  void _endQuery(int token) {
    if (_stale(token)) return;
    _busyLabel = null;
    _networkOperation = false;
    _notify();
  }

  bool _stale(int token) => _disposed || _closed || token != _opToken;

  bool _isSafeRef(String ref) {
    if (ref.isEmpty || ref.length > 255) return false;
    if (ref.startsWith('-') || ref.contains('..')) return false;
    return !RegExp(r'[\x00-\x20\x7f~^:?*\[\\]').hasMatch(ref);
  }

  String _messageOf(GitOperationException error) =>
      error.kind == 'cancelled' ? '已取消' : error.message;

  String _shortOid(String oid) => oid.length <= 7 ? oid : oid.substring(0, 7);

  void _appendLog(String text, {bool isError = false}) {
    if (_disposed || _closed) return;
    _log.add(GitLogLine(text, isError: isError));
    if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    _notify();
  }

  void _notify() {
    if (_disposed || _closed) return;
    notifyListeners();
  }
}
