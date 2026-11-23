import 'package:flutter/material.dart';

import '../../github/github_auth_controller.dart';
import '../../github/github_models.dart';
import '../../i18n/studio_localizations.dart';

/// Inline repository browser. The host owns authentication, clone/open work,
/// and progress. This widget never pushes or pops a route or cancels shared I/O.
class GitHubRepositoryList extends StatefulWidget {
  const GitHubRepositoryList({
    super.key,
    required this.controller,
    required Future<void> Function(GitHubRepository) onOpenRepository,
    required VoidCallback onConnect,
    this.actionLabel,
    this.progress,
  }) : _onOpenRepository = onOpenRepository,
       _onConnect = onConnect,
       _selectionMode = false;

  /// Checkbox presentation used by the legacy multi-repository picker.
  const GitHubRepositoryList.selection({super.key, required this.controller})
    : _onOpenRepository = null,
      _onConnect = null,
      _selectionMode = true,
      actionLabel = null,
      progress = null;

  final GitHubAuthController controller;
  final Future<void> Function(GitHubRepository)? _onOpenRepository;
  final VoidCallback? _onConnect;
  final bool _selectionMode;

  /// Defaults to "Clone". Hosts can return "Open" for mapped local projects.
  final String? Function(GitHubRepository)? actionLabel;
  final Widget? progress;

  @override
  State<GitHubRepositoryList> createState() => _GitHubRepositoryListState();
}

class _GitHubRepositoryListState extends State<GitHubRepositoryList> {
  final _search = TextEditingController();
  String _query = '';
  String? _actionError;
  int? _openingId;
  int _revision = 0;

  @override
  void didUpdateWidget(GitHubRepositoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _revision++;
      _openingId = null;
      _actionError = null;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _invoke(Future<void> Function() action) async {
    final revision = _revision;
    final accountId = widget.controller.account?.id;
    setState(() => _actionError = null);
    try {
      await action();
    } catch (_) {
      if (mounted &&
          revision == _revision &&
          accountId == widget.controller.account?.id) {
        setState(
          () => _actionError = StudioLocalizations.of(
            context,
          ).githubRequestFailed,
        );
      }
    }
  }

  Future<void> _open(GitHubRepository repository) async {
    if (_openingId != null ||
        widget.controller.status != GitHubAuthStatus.authenticated) {
      return;
    }
    final revision = _revision;
    setState(() => _openingId = repository.id);
    await _invoke(() => widget._onOpenRepository!(repository));
    if (mounted && revision == _revision) {
      setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final auth = widget.controller;
      final l10n = StudioLocalizations.of(context);
      final signedIn = auth.status == GitHubAuthStatus.authenticated;
      final repositories = signedIn
          ? auth.repositories
                .where(
                  (repository) =>
                      repository.fullName.toLowerCase().contains(_query) ||
                      (repository.description ?? '').toLowerCase().contains(
                        _query,
                      ),
                )
                .toList()
          : <GitHubRepository>[];
      return RefreshIndicator(
        onRefresh: () => _invoke(auth.refreshRepositories),
        child: CustomScrollView(
          key: const ValueKey('github-repositories'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?widget.progress,
                    if (_actionError ?? auth.errorMessage case final error?)
                      Text(
                        error,
                        key: const ValueKey('github-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (signedIn) ...[
                      Text(
                        auth.account?.login ?? '',
                        key: const ValueKey('github-account'),
                      ),
                      Text(
                        l10n.githubRepositoryScope,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('github-search'),
                        controller: _search,
                        decoration: InputDecoration(
                          labelText: l10n.githubSearch,
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            key: const ValueKey('github-refresh'),
                            onPressed: auth.isLoadingRepositories
                                ? null
                                : () => _invoke(auth.refreshRepositories),
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.refresh),
                          ),
                          if (widget._selectionMode) ...[
                            TextButton(
                              onPressed: auth.selectVisibleRepositories,
                              child: Text(l10n.githubSelectLoaded),
                            ),
                            TextButton(
                              onPressed: auth.clearSelection,
                              child: Text(l10n.githubClearSelection),
                            ),
                          ],
                        ],
                      ),
                      Text(l10n.githubLoadedCount(auth.repositories.length)),
                      if (auth.isLoadingRepositories)
                        const LinearProgressIndicator(),
                    ] else ...[
                      if (auth.isBusy) const LinearProgressIndicator(),
                      if (widget._onConnect != null)
                        FilledButton.icon(
                          key: const ValueKey('github-connect'),
                          onPressed: widget._onConnect,
                          icon: const Icon(Icons.link),
                          label: Text(l10n.githubConnect),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _repository(repositories[index], l10n),
                childCount: repositories.length,
              ),
            ),
            if (signedIn)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (repositories.isEmpty && !auth.isLoadingRepositories)
                        Text(l10n.githubNoRepositories),
                      if (auth.hasMoreRepositories)
                        OutlinedButton(
                          key: const ValueKey('github-load-more'),
                          onPressed: auth.isLoadingRepositories
                              ? null
                              : () => _invoke(auth.loadNextRepositoryPage),
                          child: Text(l10n.githubLoadMore),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _repository(GitHubRepository repository, StudioLocalizations l10n) {
    final details = [
      if (repository.isPrivate) l10n.githubPrivate,
      if (repository.archived) l10n.githubArchived,
      if (repository.description?.isNotEmpty == true) repository.description!,
    ].join(' · ');
    if (widget._selectionMode) {
      return CheckboxListTile(
        key: ValueKey('github-repository-${repository.id}'),
        value: widget.controller.selectedRepositoryIds.contains(repository.id),
        onChanged: (value) => widget.controller.setRepositorySelected(
          repository.id,
          value ?? false,
        ),
        title: Text(repository.fullName),
        subtitle: Text(details),
        controlAffinity: ListTileControlAffinity.leading,
      );
    }
    return Padding(
      key: ValueKey('github-repository-${repository.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            repository.fullName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (details.isNotEmpty) Text(details),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              key: ValueKey('github-open-${repository.id}'),
              onPressed: _openingId != null ? null : () => _open(repository),
              child: Text(
                widget.actionLabel?.call(repository) ??
                    (l10n.isEnglish
                        ? 'Clone'
                        : l10n.isTraditionalChinese
                        ? '複製'
                        : '克隆'),
              ),
            ),
          ),
          if (_openingId == repository.id) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
