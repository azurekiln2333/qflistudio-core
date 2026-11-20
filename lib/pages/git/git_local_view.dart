import 'dart:async';

import 'package:flutter/material.dart';

import '../../git/git_backend.dart';
import '../../models/project.dart';
import '../../services/studio_profile.dart';
import '../../store/git_page_controller.dart';
import 'git_dialogs.dart';
import 'git_worktree_guard.dart';

/// Real local-repository view for desktop CLI and mobile native backends.
///
/// Read-only queries and mutations run through [GitPageController]; the view
/// only formats state. Worktree-changing actions are gated by
/// [beforeWorktreeChange] so unsaved editor buffers are resolved first.
class GitLocalRepositoryView extends StatefulWidget {
  const GitLocalRepositoryView({
    super.key,
    required this.project,
    required this.backend,
    this.beforeWorktreeChange,
    this.onWorktreeChanged,
  });

  final Project project;
  final GitBackend backend;
  final GitWorktreeGuard? beforeWorktreeChange;
  final GitWorktreeChanged? onWorktreeChanged;

  @override
  State<GitLocalRepositoryView> createState() => _GitLocalRepositoryViewState();
}

class _GitLocalRepositoryViewState extends State<GitLocalRepositoryView> {
  late final GitPageController _controller;
  bool _anonymousNetwork = false;

  @override
  void initState() {
    super.initState();
    _controller = GitPageController(backend: widget.backend);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }

  /// True only for a real merge in progress.
  ///
  /// Conflicts alone are not enough: a conflicted `pull --rebase` also leaves
  /// markers behind, and `completeMerge` cannot finish a rebase.
  bool get _mergeInProgress {
    final snapshot = _controller.snapshot;
    if (snapshot == null || !snapshot.isRepository) return false;
    return snapshot.state.toLowerCase() == 'merge' ||
        snapshot.state.toLowerCase().startsWith('merge:');
  }

  /// Rebase, cherry-pick or revert stop in the middle of another operation.
  ///
  /// The page cannot finish those, so it explains the supported recovery path
  /// instead of offering a merge completion that would fail.
  String? get _unsupportedOperation {
    final snapshot = _controller.snapshot;
    if (snapshot == null || !snapshot.isRepository) return null;
    final state = snapshot.state.toLowerCase();
    if (state.startsWith('rebase')) return '变基';
    if (state.startsWith('cherry')) return '拣选';
    if (state.startsWith('revert')) return '回滚';
    return null;
  }

  bool get _networkAllowed => StudioProfile.current?.offlineOnly != true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final busy = _controller.isBusy;
        if (snapshot == null && busy) {
          return const Center(
            key: ValueKey('git-local-loading'),
            child: CircularProgressIndicator(),
          );
        }
        return ListView(
          key: const ValueKey('git-local-scroll'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _buildHeader(context, snapshot),
            if (_controller.error != null) ...[
              const SizedBox(height: 8),
              _buildErrorBanner(context),
            ],
            const SizedBox(height: 12),
            _buildActions(context, snapshot, busy),
            if (busy) ...[const SizedBox(height: 10), _buildProgress(context)],
            if (_mergeInProgress) ...[
              const SizedBox(height: 12),
              _buildConflictCard(context),
            ],
            if (_unsupportedOperation != null) ...[
              const SizedBox(height: 12),
              _buildInterruptedOperationCard(context, _unsupportedOperation!),
            ],
            if (snapshot != null && !snapshot.isRepository) ...[
              const SizedBox(height: 12),
              _buildNotRepository(context),
            ] else if (_controller.isRepository) ...[
              const SizedBox(height: 12),
              _buildChangeSection(
                context,
                title: '已暂存',
                changes: _controller.stagedChanges,
                staged: true,
                emptyLabel: '暂无已暂存文件',
              ),
              const SizedBox(height: 12),
              _buildChangeSection(
                context,
                title: '未暂存',
                changes: _controller.unstagedChanges,
                staged: false,
                emptyLabel: '工作区没有改动',
              ),
            ],
            const SizedBox(height: 12),
            _buildLog(context),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, GitSnapshot? snapshot) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final branch = snapshot?.branch;
    final oid = snapshot?.oid;
    final state = snapshot == null
        ? '正在读取…'
        : snapshot.isRepository
        ? _stateLabel(snapshot.state)
        : '还不是 Git 仓库';
    return Card(
      key: const ValueKey('git-repo-header'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.project.name,
                    key: const ValueKey('git-project-name'),
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(label: _controller.backendLabel),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              widget.project.path,
              key: const ValueKey('git-project-path'),
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(
                  icon: Icons.call_split_outlined,
                  label: branch == null
                      ? (snapshot?.isRepository == true ? '尚无提交' : '无分支')
                      : (oid == null || oid.isEmpty
                            ? branch
                            : '$branch · ${_shortOid(oid)}'),
                ),
                _StatusChip(
                  icon: _mergeInProgress
                      ? Icons.warning_amber_outlined
                      : Icons.check_circle_outline,
                  label: state,
                  highlight: _mergeInProgress,
                ),
                if (snapshot != null && snapshot.isRepository)
                  _StatusChip(
                    icon: Icons.difference_outlined,
                    label: '${snapshot.changes.length} 个改动',
                  ),
                if (snapshot != null && snapshot.remotes.isNotEmpty)
                  _StatusChip(
                    icon: Icons.cloud_outlined,
                    label: '远端 ${snapshot.remotes.length}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('git-repo-error'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              _controller.error!,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            key: const ValueKey('git-dismiss-error'),
            tooltip: '关闭提示',
            icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
            onPressed: _controller.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, GitSnapshot? snapshot, bool busy) {
    final isRepo = snapshot?.isRepository == true;
    final hasRemote = snapshot != null && snapshot.remotes.isNotEmpty;
    final hasRemoteBranch =
        snapshot != null && snapshot.branches.any((branch) => branch.remote);
    final canSync = hasRemote || hasRemoteBranch;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('git-refresh'),
          onPressed: busy ? null : _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('刷新'),
        ),
        if (snapshot != null && !isRepo)
          FilledButton.tonalIcon(
            key: const ValueKey('git-init'),
            onPressed: busy ? null : _initRepository,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('初始化'),
          ),
        if (isRepo) ...[
          OutlinedButton(
            key: const ValueKey('git-stage-all'),
            onPressed: busy ? null : _stageAll,
            child: const Text('暂存全部'),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('git-commit'),
            onPressed: busy ? null : _commit,
            icon: const Icon(Icons.commit_outlined, size: 18),
            label: const Text('提交'),
          ),
          OutlinedButton(
            key: const ValueKey('git-history'),
            onPressed: busy ? null : _showHistory,
            child: const Text('历史'),
          ),
          OutlinedButton(
            key: const ValueKey('git-branches'),
            onPressed: busy ? null : _showBranches,
            child: const Text('分支'),
          ),
          OutlinedButton(
            key: const ValueKey('git-remotes'),
            onPressed: busy ? null : _editRemote,
            child: const Text('远程'),
          ),
          if (hasRemote)
            OutlinedButton(
              key: const ValueKey('git-fetch'),
              onPressed: busy ? null : _fetch,
              child: const Text('获取'),
            ),
          if (canSync)
            OutlinedButton(
              key: const ValueKey('git-merge'),
              onPressed: busy ? null : _merge,
              child: const Text('合并'),
            ),
          if (_controller.canPullRebase)
            OutlinedButton(
              key: const ValueKey('git-pull'),
              onPressed: busy ? null : _pullRebase,
              child: const Text('拉取（变基）'),
            ),
          if (hasRemote)
            OutlinedButton(
              key: const ValueKey('git-push'),
              onPressed: busy ? null : _push,
              child: const Text('推送'),
            ),
        ],
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _controller.busyLabel ?? '处理中…',
                key: const ValueKey('git-busy-label'),
              ),
            ),
            if (_controller.isNetworkOperation)
              TextButton(
                key: const ValueKey('git-cancel-network'),
                onPressed: _controller.cancelNetwork,
                child: const Text('取消'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conflicts = _controller.conflicts;
    return Card(
      key: const ValueKey('git-conflict-card'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.report_outlined,
                  size: 20,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conflicts.isEmpty ? '合并进行中' : '合并冲突',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              conflicts.isEmpty ? '没有未解决的冲突，可以完成合并。' : '解决冲突并暂存后完成合并。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final path in conflicts)
                Padding(
                  key: ValueKey('git-conflict-$path'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    path,
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('git-complete-merge'),
                onPressed: conflicts.isNotEmpty || _controller.isBusy
                    ? null
                    : _completeMerge,
                child: const Text('完成合并'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterruptedOperationCard(BuildContext context, String label) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const ValueKey('git-interrupted-operation'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 20,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$label进行中',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '本页不能完成$label。请解决冲突后，在终端执行 git $label --continue，'
              '或执行 git $label --abort 回到操作前。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotRepository(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const ValueKey('git-not-repository'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此文件夹还不是 Git 仓库', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '初始化后可以暂存、提交和配置远程仓库。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeSection(
    BuildContext context, {
    required String title,
    required List<GitChange> changes,
    required bool staged,
    required String emptyLabel,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey(staged ? 'git-staged-section' : 'git-unstaged-section'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  '${changes.length} 个文件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (changes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  emptyLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final change in changes)
              _buildChangeRow(context, change, staged: staged),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeRow(
    BuildContext context,
    GitChange change, {
    required bool staged,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final area = staged ? 'staged' : 'worktree';
    final flags = <String>[
      if (change.conflict) '冲突',
      if (change.untracked) '未跟踪',
      if (change.oldPath != null) '由 ${change.oldPath} 重命名',
      if (change.staged && change.unstaged) '暂存后又有改动',
    ];
    return Padding(
      key: ValueKey('git-change-$area-${change.path}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            change.conflict
                ? Icons.error_outline
                : change.untracked
                ? Icons.fiber_new_outlined
                : Icons.insert_drive_file_outlined,
            size: 18,
            color: change.conflict ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (flags.isNotEmpty)
                  Text(
                    flags.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: change.conflict
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('git-diff-$area-${change.path}'),
            tooltip: '查看差异',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.code, size: 18),
            onPressed: _controller.isBusy
                ? null
                : () => _showDiff(change, staged: staged),
          ),
          TextButton(
            key: ValueKey(
              staged
                  ? 'git-unstage-${change.path}'
                  : 'git-stage-${change.path}',
            ),
            onPressed: _controller.isBusy
                ? null
                : staged
                ? () => _unstage(change)
                : () => _stage(change),
            child: Text(staged ? '取消暂存' : '暂存'),
          ),
        ],
      ),
    );
  }

  Widget _buildLog(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = _controller.log.length > 40
        ? _controller.log.sublist(_controller.log.length - 40)
        : _controller.log;
    return Card(
      key: const ValueKey('git-log'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('操作记录', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (lines.isEmpty)
              Text(
                '还没有操作',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: SelectableText(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                    color: line.isError ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() => _controller.load();

  Future<void> _initRepository() async {
    final error = await _controller.initRepository();
    if (!mounted) return;
    if (error != null) {
      _showSnack('初始化失败：$error');
      return;
    }
    _showSnack('已初始化 Git 仓库');
  }

  Future<void> _stageAll() async {
    if (_controller.unstagedChanges.isEmpty) {
      _showSnack('没有可暂存的改动');
      return;
    }
    final error = await _controller.stageAll();
    if (!mounted) return;
    if (error != null) _showSnack('暂存失败：$error');
  }

  Future<void> _stage(GitChange change) async {
    final error = await _controller.stage(change);
    if (!mounted) return;
    if (error != null) _showSnack('暂存失败：$error');
  }

  Future<void> _unstage(GitChange change) async {
    final error = await _controller.unstage(change);
    if (!mounted) return;
    if (error != null) _showSnack('取消暂存失败：$error');
  }

  Future<void> _showDiff(GitChange change, {required bool staged}) async {
    final result = await _controller.diff(
      change,
      area: staged ? GitChangeArea.staged : GitChangeArea.worktree,
    );
    if (!mounted) return;
    if (!result.ok || result.value == null) {
      _showSnack(result.error ?? '读取差异失败');
      return;
    }
    await showGitDialog<void>(
      context: context,
      builder: (_) => GitDiffDialog(path: change.path, data: result.value!),
    );
  }

  Future<void> _showHistory() async {
    final result = await _controller.history();
    if (!mounted) return;
    await showGitDialog<void>(
      context: context,
      builder: (_) => GitHistoryDialog(
        commits: result.value ?? const <GitCommitInfo>[],
        error: result.error,
      ),
    );
  }

  Future<void> _commit() async {
    if (_controller.stagedChanges.isEmpty) {
      _showSnack('请先暂存要提交的文件');
      return;
    }
    if (_controller.conflicts.isNotEmpty) {
      _showSnack('请先解决冲突并完成合并');
      return;
    }
    final input = await showGitCommitDialog(
      context,
      title: '提交已暂存的文件',
      confirmLabel: '提交',
      note: '只提交已暂存的文件；未暂存的改动会保留。',
      initialIdentity: _controller.identity,
    );
    if (input == null || !mounted) return;
    _controller.setIdentity(input.identity);
    final error = await _controller.commit(input.message);
    if (!mounted) return;
    if (error != null) {
      _showSnack('提交失败：$error');
      return;
    }
    _showSnack('已提交已暂存的文件');
  }

  Future<void> _showBranches() async {
    final choice = await showGitBranchesDialog(
      context,
      branches: _controller.branches,
      current: _controller.branch,
    );
    if (choice == null || !mounted) return;
    if (choice.create) {
      final name = await showGitBranchNameDialog(context);
      if (name == null || !mounted) return;
      final error = await _controller.createBranch(name);
      if (!mounted) return;
      if (error != null) {
        _showSnack('创建分支失败：$error');
        return;
      }
      await _checkout(name);
      return;
    }
    final name = choice.name;
    if (name == null) return;
    await _checkout(name);
  }

  Future<void> _checkout(String name) async {
    if (!await _guard('切换到 $name')) return;
    if (!mounted) return;
    final error = await _controller.checkout(name);
    if (!mounted) return;
    if (error != null) {
      // A refused or half-finished checkout can still have touched files.
      await _worktreeChanged(diskMayHaveChanged: true);
      if (!mounted) return;
      _showSnack('切换分支失败：$error');
      return;
    }
    await _worktreeChanged();
    if (mounted) _showSnack('已切换到 $name');
  }

  Future<void> _merge() async {
    final ref = await showGitMergeDialog(
      context,
      branches: _controller.branches,
      currentBranch: _controller.branch,
    );
    if (ref == null || !mounted) return;
    final identity = await _ensureIdentity();
    if (identity == null || !mounted) return;
    if (!await _guard('合并 $ref')) return;
    if (!mounted) return;
    final error = await _controller.merge(ref, identity);
    if (!mounted) return;
    if (error != null) {
      await _worktreeChanged(diskMayHaveChanged: true);
      if (!mounted) return;
      _showSnack('合并失败：$error');
      return;
    }
    final result = _controller.lastMergeResult;
    switch (result) {
      case null:
        return;
      case GitMergeResult.upToDate:
        _showSnack('已是最新，无需合并');
        return;
      case GitMergeResult.fastForward:
        await _worktreeChanged();
        if (mounted) _showSnack('已完成快进合并');
        return;
      case GitMergeResult.merged:
        await _worktreeChanged();
        if (mounted) _showSnack('已生成合并提交');
        return;
      case GitMergeResult.conflicts:
        await _worktreeChanged();
        if (mounted) _showSnack('合并产生冲突，请解决后完成合并');
        return;
    }
  }

  Future<void> _editRemote() async {
    final input = await showGitRemoteDialog(
      context,
      existing: _controller.remotes,
    );
    if (input == null || !mounted) return;
    final error = await _controller.setRemote(input.name, input.url);
    if (!mounted) return;
    if (error != null) {
      _showSnack('保存远程仓库失败：$error');
      return;
    }
    _showSnack('已保存远程仓库 ${input.name}');
  }

  Future<void> _fetch() async {
    if (!_networkAllowed) {
      _showSnack('离线产品不启用网络 Git 操作');
      return;
    }
    final credentials = await _networkCredentials();
    if (credentials == null || !credentials.proceed || !mounted) return;
    final error = await _controller.fetch(credentials: credentials.credentials);
    if (!mounted) return;
    if (error != null) {
      _showSnack('获取失败：$error');
      return;
    }
    _showSnack('已完成获取');
  }

  Future<void> _push() async {
    if (!_networkAllowed) {
      _showSnack('离线产品不启用网络 Git 操作');
      return;
    }
    final credentials = await _networkCredentials();
    if (credentials == null || !credentials.proceed || !mounted) return;
    final error = await _controller.push(credentials: credentials.credentials);
    if (!mounted) return;
    if (error != null) {
      _showSnack('推送失败：$error');
      return;
    }
    _showSnack('已推送当前分支');
  }

  Future<void> _pullRebase() async {
    if (!_networkAllowed) {
      _showSnack('离线产品不启用网络 Git 操作');
      return;
    }
    if (!await _guard('拉取并变基')) return;
    if (!mounted) return;
    final error = await _controller.pullRebase();
    if (!mounted) return;
    if (error != null) {
      // A stopped rebase leaves the worktree rewritten; clean buffers must be
      // reloaded even though the operation reported failure.
      await _worktreeChanged(diskMayHaveChanged: true);
      if (!mounted) return;
      _showSnack('拉取失败：$error');
      return;
    }
    await _worktreeChanged();
    if (mounted) _showSnack('已完成拉取并变基');
  }

  Future<void> _completeMerge() async {
    final identity = await _ensureIdentity();
    if (identity == null || !mounted) return;
    final input = await showGitCommitDialog(
      context,
      title: '完成合并提交',
      confirmLabel: '完成',
      note: '只提交已暂存的冲突解决结果。',
      initialIdentity: identity,
    );
    if (input == null || !mounted) return;
    _controller.setIdentity(input.identity);
    final error = await _controller.completeMerge(input.message);
    if (!mounted) return;
    if (error != null) {
      _showSnack('完成合并失败：$error');
      return;
    }
    await _worktreeChanged();
    if (mounted) _showSnack('已完成合并提交');
  }

  Future<GitIdentity?> _ensureIdentity() async {
    final existing = _controller.identity;
    if (existing != null &&
        existing.name.trim().isNotEmpty &&
        existing.email.contains('@')) {
      return existing;
    }
    final identity = await showGitIdentityDialog(
      context,
      initialIdentity: existing,
    );
    if (identity == null || !mounted) return null;
    _controller.setIdentity(identity);
    return identity;
  }

  /// Native backends get an explicit, masked HTTPS credential prompt.
  ///
  /// Desktop CLI keeps the installed credential helper and SSH behavior, so it
  /// is never handed a token from this dialog.
  Future<GitCredentialPrompt?> _networkCredentials() async {
    if (_controller.kind != GitBackendKind.native) {
      return const GitCredentialPrompt.anonymous();
    }
    final existing = _controller.credentials;
    if (existing != null) {
      return GitCredentialPrompt.credentials(existing);
    }
    if (_anonymousNetwork) return const GitCredentialPrompt.anonymous();
    final prompt = await showGitCredentialsDialog(context, initialUsername: '');
    if (prompt == null) return const GitCredentialPrompt.cancelled();
    if (prompt.proceed) {
      final credentials = prompt.credentials;
      if (credentials == null) {
        _anonymousNetwork = true;
      } else {
        _anonymousNetwork = false;
        _controller.rememberCredentials(credentials);
      }
    }
    return prompt;
  }

  Future<bool> _guard(String operation) async {
    final guard = widget.beforeWorktreeChange;
    if (guard == null) return true;
    try {
      return await guard(
        GitWorktreeChangeRequest(root: _controller.root, operation: operation),
      );
    } on Object {
      if (mounted) _showSnack('未保存改动检查失败，已取消操作');
      return false;
    }
  }

  Future<void> _worktreeChanged({bool diskMayHaveChanged = false}) async {
    final callback = widget.onWorktreeChanged;
    if (callback == null) return;
    try {
      // A failed operation still reports the disk as changed, so the editor
      // reloads clean buffers instead of keeping text that no longer matches
      // the file.
      await callback(_controller.root, diskMayHaveChanged: diskMayHaveChanged);
    } on Object {
      // The Git operation already succeeded; tree refresh is best effort.
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _stateLabel(String state) {
    final value = state.trim();
    final lower = value.toLowerCase();
    if (lower.isEmpty || lower == 'clean') return '工作区干净';
    if (lower.contains('conflict')) return '存在冲突';
    // Rebase states embed `merge` (`rebase_merge`), so they must be checked
    // first or the header would label a rebase as a merge.
    if (lower.contains('rebase')) return '变基进行中';
    if (lower.contains('merge')) return '合并进行中';
    if (lower.contains('cherry')) return '拣选进行中';
    if (lower.contains('detached')) return '游离 HEAD';
    if (lower.contains('unborn') || lower.contains('empty')) return '尚无提交';
    if (lower.contains('dirty')) return '有未提交改动';
    return value;
  }

  String _shortOid(String oid) => oid.length <= 7 ? oid : oid.substring(0, 7);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.icon, this.highlight = false});

  final String label;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: highlight
                  ? scheme.onErrorContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: highlight
                    ? scheme.onErrorContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
