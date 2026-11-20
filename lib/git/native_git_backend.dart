import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_git/qfli_git.dart' as plugin;

import '../services/studio_profile.dart';
import 'git_backend.dart';
import 'git_repository_queue.dart';

/// Data exchanged with the native plugin. Kept small so tests can describe a
/// repository without opening a native library.
class NativeStatusData {
  const NativeStatusData(this.path, this.bits);
  final String path;
  final int bits;
}

class NativeHeadData {
  const NativeHeadData({this.branch, this.oid, this.state = 'clean'});
  final String? branch;
  final String? oid;
  final String state;
}

class NativeBranchData {
  const NativeBranchData({
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

class NativeRemoteData {
  const NativeRemoteData({required this.name, required this.url});
  final String name;
  final String url;
}

class NativeCommitData {
  const NativeCommitData({
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

class NativeDiffData {
  const NativeDiffData({
    this.patch = '',
    this.binary = false,
    this.truncated = false,
  });
  final String patch;
  final bool binary;
  final bool truncated;
}

/// One network operation's native cancel flag.
abstract interface class NativeCancelHandle {
  void cancel();
  void dispose();
}

/// Native operations used by [NativeGitBackend].
///
/// Production uses the qfli_git plugin. Tests inject a fake so cloud-only tests
/// cover mapping, validation, cancellation and policy without a native binary.
abstract interface class NativeGitApi {
  Future<void> ensureInitialized();
  NativeRepository open(String root);
  Future<NativeRepository> init(String root);
  NativeCancelHandle createCancel();
  Future<void> clone({
    required String url,
    required String path,
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  });
}

/// One repository handle. The plugin opens and frees native handles per call;
/// this interface stays free of plugin types for testability.
abstract interface class NativeRepository {
  Future<void> addAll();
  Future<void> stagePaths(List<String> paths);
  Future<void> unstagePaths(List<String> paths);
  Future<String> commit(String message, String name, String email);
  Future<void> createBranch(String name);
  Future<void> checkout(String name);
  Future<int> merge(String ref, String name, String email);
  Future<String> commitMerge(String message, String name, String email);
  Future<List<NativeStatusData>> status();
  Future<NativeHeadData> head();
  Future<List<NativeBranchData>> branches();
  Future<List<NativeRemoteData>> remotes();
  Future<NativeDiffData> diff({String? path, bool staged = false});
  Future<List<NativeCommitData>> log({int limit = 20});
  Future<void> setRemote(String name, String url);
  Future<void> fetch({
    String remote = 'origin',
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  });
  Future<void> push({
    String remote = 'origin',
    required String refspec,
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  });
}

/// Native adapter for Android, iOS and OHOS.
///
/// Native work is lazy: constructing this object only normalizes [root]. The
/// plugin is initialized on the first operation and never on a non-repository
/// snapshot. Mutations are serialized by physical root through
/// [GitRepositoryQueue].
class NativeGitBackend implements GitBackend {
  NativeGitBackend(String root, {NativeGitApi? api, bool Function()? isOffline})
    : root = p.normalize(p.absolute(root)),
      _api = api ?? _PluginGitApi(),
      _isOffline = isOffline ?? _defaultOffline;

  @override
  final String root;

  @override
  GitBackendKind get kind => GitBackendKind.native;

  final NativeGitApi _api;
  final bool Function() _isOffline;
  final Set<Future<Object?>> _pending = {};

  NativeRepository? _repository;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _disposed = false;
  bool _cancelRequested = false;
  NativeCancelHandle? _networkCancel;

  static bool _defaultOffline() => StudioProfile.current?.offlineOnly == true;

  @override
  Future<GitSnapshot> snapshot() => _serial(() async {
    _rejectNested(root);
    if (!_looksLikeRepository(root)) {
      return const GitSnapshot(isRepository: false);
    }
    final repository = await _open();
    final head = await repository.head();
    final status = await repository.status();
    final changes = <GitChange>[for (final entry in status) _change(entry)];
    final branches = <GitBranchInfo>[];
    for (final branch in await repository.branches()) {
      if (branch.remote && branch.name.endsWith('/HEAD')) continue;
      branches.add(
        GitBranchInfo(
          name: branch.name,
          current: branch.current,
          remote: branch.remote,
          upstream: branch.upstream,
        ),
      );
    }
    final remotes = <GitRemoteInfo>[
      for (final remote in await repository.remotes())
        GitRemoteInfo(name: remote.name, url: _redact(remote.url)),
    ];
    return GitSnapshot(
      isRepository: true,
      branch: head.branch,
      oid: head.oid,
      state: head.state.isEmpty ? 'clean' : head.state,
      changes: changes,
      branches: branches,
      remotes: remotes,
      conflicts: <String>[
        for (final change in changes)
          if (change.conflict) change.path,
      ],
    );
  });

  @override
  Future<void> init() => _serial(() async {
    _rejectNested(root);
    await _ensureInitialized();
    _repository = await _api.init(root);
  });

  /// Native work is lazy, so nothing has inspected the disk at construction.
  ///
  /// A directory below another worktree cannot be addressed safely: the plugin
  /// exchanges paths relative to the enclosing repository root. Refuse it
  /// instead of opening a second, wrongly rooted repository.
  static void _rejectNested(String root) {
    if (_enclosingWorktree(root) == null) return;
    throw const GitOperationException(
      '请打开仓库根目录：当前目录位于另一个 Git 仓库内部',
      kind: 'invalid',
    );
  }

  /// Returns the nearest ancestor that holds its own Git directory.
  static String? _enclosingWorktree(String root) {
    var current = p.dirname(p.normalize(p.absolute(root)));
    while (true) {
      if (_looksLikeRepository(current)) return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  @override
  Future<void> stage(List<String> paths) async {
    if (paths.isEmpty) return;
    final checked = paths.map(_path).toList(growable: false);
    await _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      await repository.stagePaths(checked);
    });
  }

  @override
  Future<void> unstage(List<String> paths) async {
    if (paths.isEmpty) return;
    final checked = paths.map(_path).toList(growable: false);
    await _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      await repository.unstagePaths(checked);
    });
  }

  @override
  Future<void> stageAll() => _serial(() async {
    _rejectNested(root);
    final repository = await _open();
    await repository.addAll();
  });

  @override
  Future<GitDiffData> diff(String path, {required GitChangeArea area}) {
    final checked = _path(path);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      final data = await repository.diff(
        path: checked,
        staged: area == GitChangeArea.staged,
      );
      return GitDiffData(
        patch: data.patch,
        binary: data.binary,
        truncated: data.truncated,
      );
    });
  }

  @override
  Future<List<GitCommitInfo>> history({int limit = 20}) => _serial(() async {
    if (limit <= 0) return const <GitCommitInfo>[];
    _rejectNested(root);
    final repository = await _open();
    final head = await repository.head();
    if (head.oid == null) return const <GitCommitInfo>[];
    final bounded = limit > 200 ? 200 : limit;
    final commits = await repository.log(limit: bounded);
    return <GitCommitInfo>[
      for (final commit in commits)
        GitCommitInfo(
          oid: commit.oid,
          message: commit.message,
          authorName: commit.authorName,
          authorEmail: commit.authorEmail,
          time: commit.time,
        ),
    ];
  });

  @override
  Future<String> commit(String message, GitIdentity identity) {
    _identity(identity, message: message);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      final oid = await repository.commit(
        message,
        identity.name,
        identity.email,
      );
      if (oid.isEmpty) {
        throw const GitOperationException('提交后无法读取 HEAD');
      }
      return oid;
    });
  }

  @override
  Future<void> createBranch(String name) {
    final checked = _branchName(name);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      await repository.createBranch(checked);
    });
  }

  @override
  Future<void> checkout(String name) {
    final checked = _branchName(name);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      final local = (await repository.branches()).any(
        (branch) => !branch.remote && branch.name == checked,
      );
      if (!local) {
        throw GitOperationException(
          '本地没有分支 $checked，请先切换到本地分支',
          kind: 'invalid',
        );
      }
      await repository.checkout(checked);
    });
  }

  @override
  Future<GitMergeResult> merge(String ref, GitIdentity identity) {
    final checked = _mergeRef(ref);
    _identity(identity);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      final result = await repository.merge(
        checked,
        identity.name,
        identity.email,
      );
      return switch (result) {
        0 => GitMergeResult.upToDate,
        1 => GitMergeResult.fastForward,
        2 => GitMergeResult.merged,
        3 => GitMergeResult.conflicts,
        _ => throw const GitOperationException('原生合并返回未知结果'),
      };
    });
  }

  @override
  Future<String> completeMerge(String message, GitIdentity identity) {
    _identity(identity, message: message);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      final oid = await repository.commitMerge(
        message,
        identity.name,
        identity.email,
      );
      if (oid.isEmpty) {
        throw const GitOperationException('合并完成后无法读取 HEAD');
      }
      return oid;
    });
  }

  @override
  Future<void> setRemote(String name, String url) {
    final checkedName = _remoteName(name);
    final checkedUrl = _remoteUrl(url);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      await repository.setRemote(checkedName, checkedUrl);
    });
  }

  @override
  Future<void> fetch({String remote = 'origin', GitCredentials? credentials}) {
    final checkedRemote = _remoteName(remote);
    _online();
    final secrets = _credentials(credentials);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      // The product may switch to offline while this call waits in the queue.
      _online();
      final cancel = _beginNetwork();
      try {
        await repository.fetch(
          remote: checkedRemote,
          username: secrets.username,
          token: secrets.token,
          cancel: cancel,
        );
      } finally {
        _endNetwork(cancel);
      }
    });
  }

  @override
  Future<void> push({String remote = 'origin', GitCredentials? credentials}) {
    final checkedRemote = _remoteName(remote);
    _online();
    final secrets = _credentials(credentials);
    return _serial(() async {
      _rejectNested(root);
      final repository = await _open();
      final head = await repository.head();
      final branch = head.branch;
      if (branch == null || branch.isEmpty || head.oid == null) {
        throw const GitOperationException('请先提交并切换到本地分支');
      }
      // Network policy is enforced at the request boundary, not only on entry.
      _online();
      final cancel = _beginNetwork();
      try {
        await repository.push(
          remote: checkedRemote,
          refspec: 'refs/heads/$branch:refs/heads/$branch',
          username: secrets.username,
          token: secrets.token,
          cancel: cancel,
        );
      } finally {
        _endNetwork(cancel);
      }
    });
  }

  @override
  Future<void> pullRebase() async {
    throw const GitOperationException(
      '原生后端不支持 pull --rebase，请先 fetch 再 merge',
      kind: 'unsupported',
    );
  }

  @override
  void cancelNetwork() {
    _cancelRequested = true;
    _networkCancel?.cancel();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      await _waitPending();
      return;
    }
    _disposed = true;
    cancelNetwork();
    await _waitPending();
    final active = _networkCancel;
    _networkCancel = null;
    active?.dispose();
    _repository = null;
  }

  /// Clones [url] into [path]. The native CancelToken lives until the plugin
  /// call actually completes, even when the caller cancels earlier.
  static Future<void> cloneRepository({
    required String url,
    required String path,
    GitCredentials? credentials,
    GitCloneCancellation? cancellation,
    NativeGitApi? api,
    bool Function()? isOffline,
  }) async {
    final checkedUrl = _remoteUrl(url);
    if ((isOffline ?? _defaultOffline)()) {
      throw const GitOperationException('当前产品禁止网络操作', kind: 'offline');
    }
    final target = _clonePath(path);
    final secrets = _credentials(credentials);
    final client = api ?? _PluginGitApi();
    final cancel = client.createCancel();
    void onCancel() => cancel.cancel();
    cancellation?.addListener(onCancel);
    try {
      if (cancellation?.isCancelled == true) {
        throw const GitOperationException('克隆已取消', kind: 'cancelled');
      }
      await GitRepositoryQueue.run(target, () async {
        await client.ensureInitialized();
        if (cancellation?.isCancelled == true) {
          throw const GitOperationException('克隆已取消', kind: 'cancelled');
        }
        await client.clone(
          url: checkedUrl,
          path: target,
          username: secrets.username,
          token: secrets.token,
          cancel: cancel,
        );
        if (cancellation?.isCancelled == true) {
          throw const GitOperationException('克隆已取消', kind: 'cancelled');
        }
      });
    } on GitOperationException {
      rethrow;
    } on plugin.GitException catch (error) {
      if (error.isCanceled || cancellation?.isCancelled == true) {
        throw const GitOperationException('克隆已取消', kind: 'cancelled');
      }
      throw GitOperationException(_redact(error.message));
    } on Object catch (error) {
      if (cancellation?.isCancelled == true) {
        throw const GitOperationException('克隆已取消', kind: 'cancelled');
      }
      throw _unexpected(error);
    } finally {
      cancellation?.removeListener(onCancel);
      cancel.dispose();
    }
  }

  Future<NativeRepository> _open() async {
    await _ensureInitialized();
    return _repository ??= _api.open(root);
  }

  Future<void> _ensureInitialized() {
    if (_initialized) return Future<void>.value();
    final existing = _initializing;
    if (existing != null) return existing;
    late final Future<void> guarded;
    guarded = _api
        .ensureInitialized()
        .then((_) {
          _initialized = true;
        })
        .whenComplete(() {
          if (identical(_initializing, guarded)) _initializing = null;
        });
    _initializing = guarded;
    return guarded;
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    if (_disposed) {
      return Future<T>.error(
        const GitOperationException('Git 页面已关闭', kind: 'cancelled'),
      );
    }
    late final Future<T> result;
    result = GitRepositoryQueue.run(root, () async {
      if (_disposed) {
        throw const GitOperationException('Git 页面已关闭', kind: 'cancelled');
      }
      try {
        return await operation();
      } on GitOperationException {
        rethrow;
      } on plugin.GitException catch (error) {
        if (error.isCanceled) {
          throw const GitOperationException('Git 操作已取消', kind: 'cancelled');
        }
        throw GitOperationException(
          _redact(error.message),
          kind: error.isConflict ? 'conflict' : 'operation',
        );
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(_unexpected(error), stack);
      }
    });
    _pending.add(result);
    unawaited(
      result.then<void>(
        (_) => _pending.remove(result),
        onError: (Object _, StackTrace _) => _pending.remove(result),
      ),
    );
    return result;
  }

  Future<void> _waitPending() async {
    await Future.wait(
      _pending.toList().map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
  }

  NativeCancelHandle _beginNetwork() {
    final cancel = _api.createCancel();
    final pendingCancel = _cancelRequested;
    _cancelRequested = false;
    if (pendingCancel) cancel.cancel();
    _networkCancel = cancel;
    return cancel;
  }

  void _endNetwork(NativeCancelHandle cancel) {
    if (identical(_networkCancel, cancel)) {
      _networkCancel = null;
      // A cancellation belongs to the finished request; the next one starts clean.
      _cancelRequested = false;
    }
    cancel.dispose();
  }

  void _online() {
    if (_isOffline()) {
      throw const GitOperationException('当前产品禁止网络操作', kind: 'offline');
    }
  }

  static bool _looksLikeRepository(String root) {
    final dotGit = p.join(root, '.git');
    if (FileSystemEntity.typeSync(dotGit) != FileSystemEntityType.notFound) {
      return true;
    }
    // A bare repository has HEAD and objects, but no .git node.
    return File(p.join(root, 'HEAD')).existsSync() &&
        Directory(p.join(root, 'objects')).existsSync();
  }

  static GitChange _change(NativeStatusData entry) {
    const indexMask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4);
    const worktreeMask =
        (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 11) | (1 << 12);
    const untrackedBit = 1 << 7;
    const conflictBit = 1 << 15;
    final untracked = entry.bits & untrackedBit != 0;
    return GitChange(
      path: entry.path,
      staged: entry.bits & indexMask != 0,
      unstaged: !untracked && entry.bits & worktreeMask != 0,
      untracked: untracked,
      conflict: entry.bits & conflictBit != 0,
    );
  }

  static String _path(String value) {
    final normalized = p.posix.normalize(value);
    if (value.isEmpty ||
        value.contains('\x00') ||
        value.contains(r'\') ||
        p.posix.isAbsolute(value) ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw const GitOperationException('文件路径无效', kind: 'invalid');
    }
    return normalized;
  }

  static String _clonePath(String value) {
    if (value.trim().isEmpty || value.contains('\x00')) {
      throw const GitOperationException('克隆目标路径无效', kind: 'invalid');
    }
    return p.normalize(p.absolute(value));
  }

  static String _branchName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.startsWith('-') ||
        name.startsWith('/') ||
        name.endsWith('/') ||
        name.endsWith('.lock') ||
        name == '.' ||
        name == '..' ||
        name.contains('..') ||
        RegExp(r'[\x00-\x20\x7f~^:?*\[\\]').hasMatch(name)) {
      throw const GitOperationException('分支名无效', kind: 'invalid');
    }
    return name;
  }

  static String _mergeRef(String value) {
    final ref = value.trim();
    if (ref.isEmpty ||
        ref.startsWith('-') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(ref)) {
      throw const GitOperationException('合并目标无效', kind: 'invalid');
    }
    return ref;
  }

  static String _remoteName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.startsWith('-') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(name)) {
      throw const GitOperationException('远端名称无效', kind: 'invalid');
    }
    return name;
  }

  static String _remoteUrl(String value) {
    final url = value.trim();
    if (url.isEmpty ||
        url.length > 2048 ||
        RegExp(r'\s').hasMatch(url) ||
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s/@]*@').hasMatch(url)) {
      throw const GitOperationException('仓库地址无效或包含凭据', kind: 'invalid');
    }
    final uri = Uri.tryParse(url);
    final scpLike = RegExp(r'^[^@/\s]+@[^:/\s]+:.+$').hasMatch(url);
    final accepted =
        url.startsWith('https://') ||
        url.startsWith('http://') ||
        url.startsWith('ssh://') ||
        url.startsWith('git://') ||
        scpLike ||
        (uri != null && uri.scheme == 'file' && uri.path.isNotEmpty);
    if (!accepted) {
      throw const GitOperationException(
        '请使用 HTTPS、SSH 或 file 地址',
        kind: 'invalid',
      );
    }
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment)) {
      throw const GitOperationException('仓库地址不能包含凭据或查询参数', kind: 'invalid');
    }
    return url;
  }

  static void _identity(GitIdentity identity, {String? message}) {
    final name = identity.name.trim();
    final email = identity.email.trim();
    if (name.isEmpty ||
        email.isEmpty ||
        !email.contains('@') ||
        RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(identity.name + identity.email) ||
        (message != null &&
            (message.trim().isEmpty || message.contains('\x00')))) {
      throw const GitOperationException('请填写有效作者、邮箱和提交信息', kind: 'invalid');
    }
  }

  static ({String? username, String? token}) _credentials(
    GitCredentials? credentials,
  ) {
    if (credentials == null || credentials.token.isEmpty) {
      return (username: null, token: null);
    }
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(credentials.username) ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(credentials.token)) {
      throw const GitOperationException('Git 凭据无效', kind: 'invalid');
    }
    final username = credentials.username.trim();
    return (
      username: username.isEmpty ? null : username,
      token: credentials.token,
    );
  }

  static String _redact(String text) => text
      .replaceAllMapped(
        RegExp(r'((?:https?|ssh|git)://)[^\s/@]+@', caseSensitive: false),
        (match) => '${match[1]}[redacted]@',
      )
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();

  static GitOperationException _unexpected(Object error) {
    final text = error is StateError || error is FormatException
        ? error.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), '')
        : error.toString();
    return GitOperationException(_redact(text));
  }
}

class _PluginGitApi implements NativeGitApi {
  @override
  Future<void> ensureInitialized() => plugin.QfliGit.ensureInitialized();

  @override
  NativeRepository open(String root) =>
      _PluginRepository(plugin.GitRepository.open(root));

  @override
  Future<NativeRepository> init(String root) async =>
      _PluginRepository(await plugin.GitRepository.init(root));

  @override
  NativeCancelHandle createCancel() => _PluginCancel(plugin.CancelToken());

  @override
  Future<void> clone({
    required String url,
    required String path,
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  }) async {
    await plugin.GitRepository.clone(
      url: url,
      path: path,
      username: username,
      token: token,
      cancel: _pluginCancel(cancel),
    );
  }
}

class _PluginCancel implements NativeCancelHandle {
  _PluginCancel(this.token);
  final plugin.CancelToken token;

  @override
  void cancel() => token.cancel();

  @override
  void dispose() => token.dispose();
}

plugin.CancelToken? _pluginCancel(NativeCancelHandle? cancel) {
  if (cancel == null) return null;
  if (cancel is _PluginCancel) return cancel.token;
  throw StateError('native cancel handle belongs to another API');
}

class _PluginRepository implements NativeRepository {
  _PluginRepository(this.repository);
  final plugin.GitRepository repository;

  @override
  Future<void> addAll() => repository.addAll();

  @override
  Future<void> stagePaths(List<String> paths) => repository.stagePaths(paths);

  @override
  Future<void> unstagePaths(List<String> paths) =>
      repository.unstagePaths(paths);

  @override
  Future<String> commit(String message, String name, String email) =>
      repository.commit(message, plugin.GitAuthor(name, email));

  @override
  Future<void> createBranch(String name) => repository.createBranch(name);

  @override
  Future<void> checkout(String name) => repository.checkout(name);

  @override
  Future<int> merge(String ref, String name, String email) async {
    final result = await repository.merge(ref, plugin.GitAuthor(name, email));
    return switch (result) {
      plugin.MergeOutcome.upToDate => 0,
      plugin.MergeOutcome.fastForward => 1,
      plugin.MergeOutcome.merged => 2,
      plugin.MergeOutcome.conflicts => 3,
    };
  }

  @override
  Future<String> commitMerge(String message, String name, String email) =>
      repository.commitMerge(message, plugin.GitAuthor(name, email));

  @override
  Future<List<NativeStatusData>> status() async => <NativeStatusData>[
    for (final entry in await repository.status())
      NativeStatusData(entry.path, entry.statusBits),
  ];

  @override
  Future<NativeHeadData> head() async {
    final head = await repository.head();
    final branch = head.branch;
    return NativeHeadData(
      branch: branch == null || branch.isEmpty || branch == 'HEAD'
          ? null
          : branch,
      oid: head.oid.isEmpty ? null : head.oid,
      state: head.state.isEmpty ? 'clean' : head.state,
    );
  }

  @override
  Future<List<NativeBranchData>> branches() async => <NativeBranchData>[
    for (final branch in await repository.branches())
      NativeBranchData(
        name: branch.name,
        current: branch.current,
        remote: branch.remote,
        upstream: branch.upstream,
      ),
  ];

  @override
  Future<List<NativeRemoteData>> remotes() async => <NativeRemoteData>[
    for (final remote in await repository.remotes())
      NativeRemoteData(name: remote.name, url: remote.url),
  ];

  @override
  Future<NativeDiffData> diff({String? path, bool staged = false}) async {
    final diff = await repository.diff(
      path: path,
      staged: staged,
      maxBytes: 262144,
    );
    return NativeDiffData(
      patch: diff.patch,
      binary: diff.binary,
      truncated: diff.truncated,
    );
  }

  @override
  Future<List<NativeCommitData>> log({int limit = 20}) async =>
      <NativeCommitData>[
        for (final commit in await repository.log(limit: limit))
          NativeCommitData(
            oid: commit.oid,
            message: commit.message,
            authorName: commit.authorName,
            authorEmail: commit.authorEmail,
            time: commit.time,
          ),
      ];

  @override
  Future<void> setRemote(String name, String url) =>
      repository.setRemote(name, url);

  @override
  Future<void> fetch({
    String remote = 'origin',
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  }) => repository.fetch(
    remote: remote,
    username: username,
    token: token,
    cancel: _pluginCancel(cancel),
  );

  @override
  Future<void> push({
    String remote = 'origin',
    required String refspec,
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  }) => repository.push(
    remote: remote,
    refspec: refspec,
    username: username,
    token: token,
    cancel: _pluginCancel(cancel),
  );
}
