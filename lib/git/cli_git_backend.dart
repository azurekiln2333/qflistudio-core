import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../services/process_supervisor.dart';
import '../services/studio_profile.dart';
import 'git_backend.dart';
import 'git_clone_progress_parser.dart';
import 'git_repository_queue.dart';

typedef _Result = ({String out, String err, int code, bool truncated});

/// Desktop Git keeps the user's installed Git, SSH and credential helper.
class CliGitBackend implements GitBackend {
  CliGitBackend(String root, {ProcessSupervisor? supervisor})
    : root = p.normalize(p.absolute(root)),
      _supervisor = supervisor ?? ProcessSupervisor();

  @override
  final String root;
  @override
  GitBackendKind get kind => GitBackendKind.cli;
  final ProcessSupervisor _supervisor;
  final Set<Future<Object?>> _pending = {};
  bool _disposed = false;
  bool _cancelRequested = false;
  ManagedProcess? _network;

  Future<T> _serial<T>(Future<T> Function() operation) {
    late final Future<T> result;
    result = GitRepositoryQueue.run(root, () {
      if (_disposed) {
        throw const GitOperationException('Git 页面已关闭', kind: 'cancelled');
      }
      return operation();
    });
    _pending.add(result);
    unawaited(
      result.then<void>(
        (_) => _pending.remove(result),
        onError: (Object _, StackTrace _) {
          _pending.remove(result);
        },
      ),
    );
    return result;
  }

  static void _online() {
    if (StudioProfile.current?.offlineOnly == true) {
      throw const GitOperationException('当前产品禁止网络操作', kind: 'offline');
    }
  }

  static String _argument(String value, String label) {
    if (value.isEmpty ||
        value.startsWith('-') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw GitOperationException('$label 无效', kind: 'invalid');
    }
    return value;
  }

  static void _identity(GitIdentity identity, [String? message]) {
    if (identity.name.trim().isEmpty ||
        !identity.email.contains('@') ||
        RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(identity.name + identity.email) ||
        (message != null &&
            (message.trim().isEmpty || message.contains('\x00')))) {
      throw const GitOperationException('请填写有效作者、邮箱和提交信息', kind: 'invalid');
    }
  }

  static Map<String, String> _author(GitIdentity identity) => {
    'GIT_AUTHOR_NAME': identity.name,
    'GIT_AUTHOR_EMAIL': identity.email,
    'GIT_COMMITTER_NAME': identity.name,
    'GIT_COMMITTER_EMAIL': identity.email,
  };

  static String _redact(String text) => text.replaceAllMapped(
    RegExp(r'(https?://)[^\s/@]+@', caseSensitive: false),
    (match) => '${match[1]}[redacted]@',
  );

  static void _url(String url) {
    _argument(url, '仓库地址');
    final uri = Uri.tryParse(url);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.userInfo.isNotEmpty ||
            uri.query.isNotEmpty ||
            uri.fragment.isNotEmpty)) {
      throw const GitOperationException('仓库地址不能包含凭据或查询参数', kind: 'invalid');
    }
    if (url.startsWith('ext::')) {
      throw const GitOperationException('不支持外部命令传输', kind: 'invalid');
    }
  }

  String _path(String value) {
    if (value.isEmpty ||
        value.contains('\x00') ||
        p.isAbsolute(value) ||
        p.split(value).contains('..') ||
        p.normalize(value) == '.') {
      throw const GitOperationException('文件路径无效', kind: 'invalid');
    }
    final target = p.normalize(p.join(root, value));
    if (!p.isWithin(root, target)) {
      throw const GitOperationException('文件不属于当前仓库', kind: 'invalid');
    }
    return value;
  }

  Future<_Result> _exec(
    List<String> args, {
    String? cwd,
    bool network = false,
    Set<int> allowed = const {0},
    int maxBytes = 4 * 1024 * 1024,
    bool allowTruncation = false,
    Map<String, String>? environment,
    GitCloneProgressParser? progressParser,
  }) async {
    if (_disposed) {
      throw const GitOperationException('Git 页面已关闭', kind: 'cancelled');
    }
    if (network) {
      _online();
      _cancelRequested = false;
    }
    final output = BytesBuilder(copy: false);
    final errors = BytesBuilder(copy: false);
    var truncated = false;
    void collect(BytesBuilder buffer, List<int> bytes) {
      final remaining = maxBytes - buffer.length;
      if (bytes.length > remaining) truncated = true;
      if (remaining > 0) {
        buffer.add(
          bytes.length > remaining ? bytes.sublist(0, remaining) : bytes,
        );
      }
    }

    ManagedProcess? process;
    Future<void>? outDone;
    Future<void>? errDone;
    var progressCompleted = false;
    try {
      process = await _supervisor.start(
        'git',
        ['--literal-pathspecs', ...args],
        workingDirectory: cwd ?? root,
        runInShell: false,
        environment: {
          'GIT_TERMINAL_PROMPT': '0',
          'LC_ALL': 'C',
          ...?environment,
        },
      );
      if (network) _network = process;
      outDone = process.stdout.forEach((data) => collect(output, data));
      errDone = process.stderr.forEach((data) {
        collect(errors, data);
        progressParser?.add(data);
      });
      if (_disposed || (network && _cancelRequested)) await process.cancel();
      final code = await _waitForExit(
        process,
        network: network,
        outDone: outDone,
        errDone: errDone,
      );
      if (_disposed || (network && _cancelRequested)) {
        throw const GitOperationException('Git 操作已取消', kind: 'cancelled');
      }
      final result = (
        out: utf8.decode(output.takeBytes(), allowMalformed: true),
        err: _redact(utf8.decode(errors.takeBytes(), allowMalformed: true)),
        code: code,
        truncated: truncated,
      );
      if (!allowed.contains(code)) {
        throw GitOperationException(
          result.err.trim().isEmpty ? 'Git 操作失败：$code' : result.err.trim(),
        );
      }
      if (truncated && !allowTruncation) {
        throw const GitOperationException('Git 输出超过读取上限', kind: 'limit');
      }
      progressCompleted = true;
      return result;
    } on ProcessException {
      throw const GitOperationException(
        '无法启动 Git，请确认已安装并加入 PATH',
        kind: 'unavailable',
      );
    } on GitOperationException {
      rethrow;
    } on Object catch (error) {
      throw GitOperationException(_redact(error.toString()));
    } finally {
      progressParser?.close(flush: progressCompleted);
      if (network && identical(_network, process)) _network = null;
    }
  }

  /// Waits for the owned child and both output streams.
  ///
  /// A timeout or a broken output stream must not leave a Git process running
  /// after the page reported failure, so every failure path cancels the child
  /// this backend started. Cancellation is idempotent and never reaches an
  /// unrelated process.
  Future<int> _waitForExit(
    ManagedProcess process, {
    required bool network,
    required Future<void> outDone,
    required Future<void> errDone,
  }) async {
    try {
      final code = await process.exitCode.timeout(
        Duration(minutes: network ? 5 : 2),
        onTimeout: () async {
          await process.cancel();
          throw const GitOperationException('Git 操作超时', kind: 'timeout');
        },
      );
      await Future.wait([outDone, errDone]);
      return code;
    } on Object {
      await process.cancel();
      await Future.wait<void>([
        outDone.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        errDone.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]);
      rethrow;
    }
  }

  Future<String?> _head() async {
    final result = await _exec(
      ['rev-parse', '--verify', '--quiet', 'HEAD'],
      allowed: {0, 1},
    );
    return result.code == 0 ? result.out.trim() : null;
  }

  @override
  Future<GitSnapshot> snapshot() => _serial(() async {
    final probe = await _exec(
      ['rev-parse', '--is-inside-work-tree'],
      allowed: {0, 128},
    );
    if (probe.code != 0) {
      if (probe.err.contains('not a git repository')) {
        // A project inside another worktree is not a repository of its own;
        // accepting it would report paths belonging to the outer repository.
        final enclosing = _enclosingWorktree(root);
        if (enclosing != null) {
          throw GitOperationException(
            '请打开仓库根目录：当前目录位于另一个 Git 仓库内部（$enclosing）',
            kind: 'invalid',
          );
        }
        return const GitSnapshot(isRepository: false);
      }
      throw GitOperationException(probe.err.trim());
    }
    if (probe.out.trim() != 'true') {
      throw const GitOperationException('此仓库没有可编辑的工作区');
    }
    await _requireWorktreeRoot();
    // --no-renames reports a move as an independent deletion and addition, so
    // both sides stay addressable by stage and unstage instead of a single
    // rename entry whose old path the index arithmetic would miss.
    final status = await _exec([
      'status',
      '--porcelain=v1',
      '-z',
      '--no-renames',
      '--untracked-files=all',
    ]);
    final changes = parseStatus(status.out);
    final branch = await _exec(
      ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      allowed: {0, 1},
    );
    final refs = await _exec([
      'for-each-ref',
      '--format=%(refname)%00%(HEAD)%00%(upstream:short)',
      'refs/heads/',
      'refs/remotes/',
    ]);
    final branches = <GitBranchInfo>[];
    for (final line in const LineSplitter().convert(refs.out)) {
      final fields = line.split('\x00');
      if (fields.length != 3 || fields[0].endsWith('/HEAD')) continue;
      final remote = fields[0].startsWith('refs/remotes/');
      branches.add(
        GitBranchInfo(
          name: fields[0].replaceFirst(
            remote ? 'refs/remotes/' : 'refs/heads/',
            '',
          ),
          remote: remote,
          current: fields[1] == '*',
          upstream: fields[2].isEmpty ? null : fields[2],
        ),
      );
    }
    final names = await _exec(['remote']);
    final remotes = <GitRemoteInfo>[];
    for (final name in const LineSplitter().convert(names.out)) {
      final remote = await _exec(['remote', 'get-url', '--', name]);
      remotes.add(GitRemoteInfo(name: name, url: _redact(remote.out.trim())));
    }
    final mergeHead = await _exec(['rev-parse', '--git-path', 'MERGE_HEAD']);
    final mergePath = p.isAbsolute(mergeHead.out.trim())
        ? mergeHead.out.trim()
        : p.join(root, mergeHead.out.trim());
    return GitSnapshot(
      isRepository: true,
      branch: branch.code == 0 ? branch.out.trim() : null,
      oid: await _head(),
      state: await _operationState(mergeHead: File(mergePath).existsSync()),
      changes: changes,
      branches: branches,
      remotes: remotes,
      conflicts: changes
          .where((entry) => entry.conflict)
          .map((entry) => entry.path)
          .toList(),
    );
  });

  /// Reports the operation a user must finish before the next mutation.
  ///
  /// A rebase leaves neither MERGE_HEAD nor a merge commit, so reporting only
  /// the merge state would present a rebase conflict as a clean repository and
  /// offer a merge completion that cannot apply.
  Future<String> _operationState({required bool mergeHead}) async {
    if (mergeHead) return 'merge';
    if (await _gitPathExists('rebase-merge') ||
        await _gitPathExists('rebase-apply')) {
      return 'rebase';
    }
    return 'clean';
  }

  Future<bool> _gitPathExists(String name) async {
    final result = await _exec(['rev-parse', '--git-path', name]);
    final value = result.out.trim();
    if (value.isEmpty) return false;
    final path = p.isAbsolute(value) ? value : p.join(root, value);
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  /// Rejects a project directory that is not the worktree root.
  ///
  /// Status, stage, unstage and diff exchange paths relative to the worktree
  /// root, so accepting a nested directory would silently address the wrong
  /// files (a file `sub/a.dart` would become `sub/sub/a.dart`).
  Future<void> _requireWorktreeRoot() async {
    final top = await _exec(
      ['rev-parse', '--show-toplevel'],
      allowed: {0, 128},
    );
    final reported = top.out.trim();
    if (top.code != 0 || reported.isEmpty) {
      throw GitOperationException(
        top.err.trim().isEmpty ? '当前目录不是 Git 工作区' : top.err.trim(),
      );
    }
    if (!_samePath(root, reported)) {
      throw const GitOperationException(
        '请打开仓库根目录：当前目录不是该 Git 仓库的根目录',
        kind: 'invalid',
      );
    }
  }

  static bool _samePath(String left, String right) {
    String canonical(String value) {
      var path = p.normalize(p.absolute(value));
      try {
        path = Directory(path).resolveSymbolicLinksSync();
      } on FileSystemException {
        // A path that cannot be resolved is compared as written.
      }
      return Platform.isWindows ? path.toLowerCase() : path;
    }

    return canonical(left) == canonical(right);
  }

  /// Porcelain -z preserves whitespace and Unicode without quoted-path parsing.
  static List<GitChange> parseStatus(String output) {
    final fields = output.split('\x00');
    final changes = <GitChange>[];
    for (var i = 0; i < fields.length; i++) {
      final entry = fields[i];
      if (entry.isEmpty) continue;
      if (entry.length < 4 || entry[2] != ' ') {
        throw const GitOperationException('Git 状态格式无效');
      }
      final x = entry[0], y = entry[1];
      final untracked = x == '?' && y == '?';
      final conflict =
          x == 'U' ||
          y == 'U' ||
          (x == 'A' && y == 'A') ||
          (x == 'D' && y == 'D');
      String? oldPath;
      if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
        if (++i >= fields.length || fields[i].isEmpty) {
          throw const GitOperationException('Git 重命名状态格式无效');
        }
        oldPath = fields[i];
      }
      changes.add(
        GitChange(
          path: entry.substring(3),
          oldPath: oldPath,
          staged: !untracked && x != ' ' && x != '!',
          unstaged: !untracked && y != ' ' && y != '!',
          untracked: untracked,
          conflict: conflict,
        ),
      );
    }
    return changes;
  }

  @override
  Future<void> init() => _serial(() async {
    final enclosing = _enclosingWorktree(root);
    if (enclosing != null) {
      throw GitOperationException(
        '请新建独立目录：当前目录位于另一个 Git 仓库内部（$enclosing）',
        kind: 'invalid',
      );
    }
    await _exec(['init']);
  });

  /// The nearest ancestor that already holds a Git directory, if any.
  static String? _enclosingWorktree(String root) {
    var current = p.dirname(p.normalize(p.absolute(root)));
    while (true) {
      if (FileSystemEntity.typeSync(p.join(current, '.git')) !=
          FileSystemEntityType.notFound) {
        return current;
      }
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  @override
  Future<void> stage(List<String> paths) => _serial(() async {
    if (paths.isEmpty) return;
    await _requireWorktreeRoot();
    await _exec(['add', '-A', '--', ...paths.map(_path)]);
  });
  @override
  Future<void> unstage(List<String> paths) => _serial(() async {
    if (paths.isEmpty) return;
    await _requireWorktreeRoot();
    final checked = paths.map(_path).toList();
    if (await _head() == null) {
      await _exec([
        'rm',
        '--cached',
        '-f',
        '--ignore-unmatch',
        '--',
        ...checked,
      ]);
    } else {
      await _exec(['reset', '-q', 'HEAD', '--', ...checked]);
    }
  });
  @override
  Future<void> stageAll() => _serial(() async {
    await _requireWorktreeRoot();
    await _exec(['add', '-A', '--', '.']);
  });

  @override
  Future<GitDiffData> diff(String path, {required GitChangeArea area}) =>
      _serial(() async {
        await _requireWorktreeRoot();
        final file = _path(path);
        final staged = area == GitChangeArea.staged;
        final tracked = await _exec(
          ['ls-files', '--error-unmatch', '--', file],
          allowed: {0, 1},
        );
        final args = <String>['diff', '--no-ext-diff', '--no-textconv'];
        Set<int> allowed = {0};
        if (!staged && tracked.code == 1) {
          final absolute = p.join(root, file);
          if (FileSystemEntity.isLinkSync(absolute)) {
            return const GitDiffData(patch: '新符号链接', binary: true);
          }
          args.addAll([
            '--no-index',
            '--',
            Platform.isWindows ? 'NUL' : '/dev/null',
            file,
          ]);
          allowed = {0, 1};
        } else {
          if (staged) args.add('--cached');
          args.addAll(['--', file]);
        }
        final result = await _exec(
          args,
          allowed: allowed,
          maxBytes: 262144,
          allowTruncation: true,
        );
        return GitDiffData(
          patch: result.out,
          binary: result.out.contains('Binary files '),
          truncated: result.truncated,
        );
      });

  @override
  Future<List<GitCommitInfo>> history({int limit = 20}) => _serial(() async {
    await _requireWorktreeRoot();
    if (await _head() == null) return [];
    final result = await _exec([
      'log',
      '-z',
      '-n',
      limit.clamp(1, 200).toString(),
      '--format=%H%x00%an%x00%ae%x00%at%x00%s',
    ]);
    final fields = result.out.split('\x00');
    final commits = <GitCommitInfo>[];
    for (var i = 0; i + 4 < fields.length; i += 5) {
      final seconds = int.tryParse(fields[i + 3]);
      if (seconds == null) throw const GitOperationException('Git 历史格式无效');
      commits.add(
        GitCommitInfo(
          oid: fields[i],
          authorName: fields[i + 1],
          authorEmail: fields[i + 2],
          time: DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ),
          message: fields[i + 4],
        ),
      );
    }
    return commits;
  });

  @override
  Future<String> commit(String message, GitIdentity identity) =>
      _serial(() async {
        await _requireWorktreeRoot();
        return _commit(message, identity);
      });
  Future<String> _commit(String message, GitIdentity identity) async {
    _identity(identity, message);
    await _exec(['commit', '-m', message], environment: _author(identity));
    final oid = await _head();
    if (oid == null) throw const GitOperationException('提交后无法读取 HEAD');
    return oid;
  }

  @override
  Future<void> createBranch(String name) => _serial(() async {
    _argument(name, '分支名');
    await _requireWorktreeRoot();
    await _exec(['check-ref-format', '--branch', name]);
    await _exec(['branch', '--', name]);
  });
  @override
  Future<void> checkout(String name) => _serial(() async {
    _argument(name, '分支名');
    await _requireWorktreeRoot();
    await _exec(['check-ref-format', '--branch', name]);
    // `git checkout origin/main` would detach HEAD without a local branch and
    // leave push unable to name a branch, so a non-local ref is refused before
    // the index changes.
    final local = await _exec(
      ['show-ref', '--verify', '--quiet', 'refs/heads/$name'],
      allowed: {0, 1},
    );
    if (local.code != 0) {
      throw GitOperationException('本地没有分支 $name，请先切换到本地分支', kind: 'invalid');
    }
    await _exec(['checkout', name, '--']);
  });

  @override
  Future<GitMergeResult> merge(String ref, GitIdentity identity) =>
      _serial(() async {
        _argument(ref, '合并目标');
        _identity(identity);
        await _requireWorktreeRoot();
        final before = await _head();
        final target = await _exec(['rev-parse', '--verify', '$ref^{commit}']);
        final result = await _exec(
          ['merge', '--no-edit', '--', ref],
          environment: _author(identity),
          allowed: {0, 1},
        );
        if (result.code != 0) {
          final conflicts = await _exec([
            'diff',
            '--name-only',
            '--diff-filter=U',
            '-z',
          ]);
          if (conflicts.out.isNotEmpty) return GitMergeResult.conflicts;
          throw GitOperationException(
            result.err.trim().isEmpty ? '合并失败' : result.err.trim(),
          );
        }
        final after = await _head();
        if (before == after) return GitMergeResult.upToDate;
        return after == target.out.trim()
            ? GitMergeResult.fastForward
            : GitMergeResult.merged;
      });

  @override
  Future<String> completeMerge(String message, GitIdentity identity) =>
      _serial(() async {
        await _requireWorktreeRoot();
        final state = await _exec(
          ['rev-parse', '--verify', '--quiet', 'MERGE_HEAD'],
          allowed: {0, 1},
        );
        if (state.code != 0) {
          if (await _gitPathExists('rebase-merge') ||
              await _gitPathExists('rebase-apply')) {
            throw const GitOperationException('当前仓库正在变基，请先完成或中止变基');
          }
          throw const GitOperationException('当前仓库没有待完成的合并');
        }
        return _commit(message, identity);
      });
  @override
  Future<void> setRemote(String name, String url) => _serial(() async {
    _argument(name, '远端名称');
    _url(url);
    await _requireWorktreeRoot();
    final names = await _exec(['remote']);
    if (const LineSplitter().convert(names.out).contains(name)) {
      await _exec(['remote', 'set-url', '--', name, url]);
    } else {
      await _exec(['remote', 'add', '--', name, url]);
    }
  });

  @override
  Future<void> fetch({String remote = 'origin', GitCredentials? credentials}) =>
      _serial(() async {
        final checked = _argument(remote, '远端名称');
        await _requireWorktreeRoot();
        await _exec(['fetch', '--', checked], network: true);
      });
  @override
  Future<void> push({String remote = 'origin', GitCredentials? credentials}) =>
      _serial(() async {
        await _requireWorktreeRoot();
        final branch = await _exec(
          ['symbolic-ref', '--quiet', '--short', 'HEAD'],
          allowed: {0, 1},
        );
        if (branch.code != 0 || await _head() == null) {
          throw const GitOperationException('请先提交并切换到本地分支');
        }
        await _exec([
          'push',
          '-u',
          '--',
          _argument(remote, '远端名称'),
          'HEAD:refs/heads/${branch.out.trim()}',
        ], network: true);
      });
  @override
  Future<void> pullRebase() => _serial(() async {
    await _requireWorktreeRoot();
    await _exec(['pull', '--rebase'], network: true);
  });

  @override
  void cancelNetwork() {
    _cancelRequested = true;
    final process = _network;
    if (process != null) unawaited(process.cancel().catchError((Object _) {}));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    cancelNetwork();
    await _supervisor.dispose();
    await Future.wait(
      _pending.toList().map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
  }

  static Future<void> cloneRepository({
    required String url,
    required String path,
    GitCredentials? credentials,
    GitCloneCancellation? cancellation,
    GitCloneProgressCallback? onProgress,
  }) async {
    _online();
    _url(url);
    if (cancellation?.isCancelled == true) {
      throw const GitOperationException('克隆已取消', kind: 'cancelled');
    }
    final backend = CliGitBackend(path);
    void cancel() => backend.cancelNetwork();
    cancellation?.addListener(cancel);
    try {
      await backend._serial(() async {
        if (cancellation?.isCancelled == true) {
          throw const GitOperationException('克隆已取消', kind: 'cancelled');
        }
        await backend._exec(
          ['clone', '--progress', '--', url, backend.root],
          cwd: p.dirname(backend.root),
          network: true,
          allowTruncation: true,
          progressParser: GitCloneProgressParser(onProgress),
        );
        if (cancellation?.isCancelled == true) {
          throw const GitOperationException('克隆已取消', kind: 'cancelled');
        }
      });
    } finally {
      cancellation?.removeListener(cancel);
      await backend.dispose();
    }
  }
}
