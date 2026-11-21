// R1: repository selection owns presentation only. GitHub auth, pagination,
// credential persistence and request-generation fences belong to lib/github.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../github/github_auth_controller.dart';
import '../../github/github_models.dart';
import '../../i18n/studio_localizations.dart';
import '../../services/git_clone_service.dart';
import '../../services/runner_service.dart';

Future<List<GitCloneRequest>?> showGitHubRepositoryPicker(
  BuildContext context, {
  GitHubAuthController? controller,
}) => Navigator.of(context).push<List<GitCloneRequest>>(
  MaterialPageRoute(
    builder: (_) => GitHubRepositoryPicker(controller: controller),
  ),
);

/// Returns independent clone requests. It never clones, registers a project or
/// copies credentials into a URL, label, diagnostic or persisted widget model.
class GitHubRepositoryPicker extends StatefulWidget {
  const GitHubRepositoryPicker({super.key, this.controller});

  /// Tests may supply the existing controller with a fake API/secure store.
  /// The caller retains ownership of injected controllers.
  final GitHubAuthController? controller;

  @override
  State<GitHubRepositoryPicker> createState() => _GitHubRepositoryPickerState();
}

class _GitHubRepositoryPickerState extends State<GitHubRepositoryPicker> {
  late final GitHubAuthController _auth =
      widget.controller ??
      GitHubAuthController(
        openBrowser: (uri) => RunnerService.openUrl(uri.toString()),
      );
  final _pat = TextEditingController();
  final _search = TextEditingController();
  GitHubAuthMethod _method = GitHubAuthMethod.oauthDevice;
  String _query = '';
  String? _actionError;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) unawaited(_invoke(_auth.restore));
  }

  @override
  void dispose() {
    // Never leave OAuth polling after a route closes, including an injected
    // controller that its caller keeps alive.
    unawaited(_auth.cancelDeviceOAuth());
    if (widget.controller == null) _auth.dispose();
    _pat.clear();
    _pat.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _invoke(Future<void> Function() action) async {
    if (mounted) setState(() => _actionError = null);
    try {
      await action();
    } catch (_) {
      // The controller supplies safe domain messages. Never render a raw error
      // from a transport/credential plugin that might reflect credentials.
      if (mounted) {
        setState(
          () => _actionError = StudioLocalizations.of(
            context,
          ).githubRequestFailed,
        );
      }
    }
  }

  Future<void> _changeMethod(GitHubAuthMethod method) async {
    await _auth.cancelDeviceOAuth();
    if (!mounted) return;
    _pat.clear();
    setState(() {
      _method = method;
      _actionError = null;
    });
  }

  Future<void> _signInPat() async {
    final value = _pat.text.trim();
    if (value.isEmpty) return;
    _pat.clear();
    FocusScope.of(context).unfocus();
    await _invoke(() => _auth.signInWithPat(value));
  }

  void _cloneSelected() {
    if (_auth.status != GitHubAuthStatus.authenticated) return;
    // A's handoff validates the current authenticated selection. There is no
    // async gap between validating it and returning the operation-scoped values.
    final requests = <GitCloneRequest>[
      for (final repository in _auth.selectedRepositories)
        ?_auth.buildCloneRequest(repository),
    ];
    if (requests.isEmpty) return;
    _auth.clearSelection();
    Navigator.of(context).pop(List<GitCloneRequest>.unmodifiable(requests));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _auth,
    builder: (context, _) {
      final l10n = StudioLocalizations.of(context);
      final signedIn = _auth.status == GitHubAuthStatus.authenticated;
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.githubRepositories),
          actions: [
            if (signedIn) ...[
              IconButton(
                tooltip: l10n.refresh,
                onPressed: _auth.isLoadingRepositories
                    ? null
                    : () => _invoke(_auth.refreshRepositories),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                key: const ValueKey('github-disconnect'),
                tooltip: l10n.githubDisconnect,
                onPressed: () => _invoke(_auth.disconnect),
                icon: const Icon(Icons.link_off),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_actionError ?? _auth.errorMessage case final error?)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error,
                        key: const ValueKey('github-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: signedIn
                        ? _repositories(l10n)
                        : _authentication(l10n),
                  ),
                  if (signedIn)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.githubSelectedCount(
                              _auth.selectedRepositoryIds.length,
                            ),
                          ),
                          FilledButton.icon(
                            key: const ValueKey('github-clone-selected'),
                            onPressed: _auth.selectedRepositoryIds.isEmpty
                                ? null
                                : _cloneSelected,
                            icon: const Icon(Icons.download),
                            label: Text(l10n.githubCloneSelected),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _authentication(StudioLocalizations l10n) {
    final device = _auth.deviceAuthorization;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Chips wrap on narrow/large-text screens instead of forcing both
        // authentication labels into a fixed-width segmented control.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.githubOAuth),
              avatar: const Icon(Icons.open_in_browser, size: 18),
              selected: _method == GitHubAuthMethod.oauthDevice,
              onSelected: (_) => _changeMethod(GitHubAuthMethod.oauthDevice),
            ),
            ChoiceChip(
              label: Text(l10n.githubPat),
              avatar: const Icon(Icons.key, size: 18),
              selected: _method == GitHubAuthMethod.personalAccessToken,
              onSelected: (_) =>
                  _changeMethod(GitHubAuthMethod.personalAccessToken),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_method == GitHubAuthMethod.oauthDevice) ...[
          Text(l10n.githubOAuthHint),
          const SizedBox(height: 12),
          if (device != null) ...[
            Text(l10n.githubAuthorizationCode),
            SelectableText(
              device.userCode,
              key: const ValueKey('github-user-code'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SelectableText(device.verificationUri.toString()),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: device.userCode)),
                  icon: const Icon(Icons.copy),
                  label: Text(l10n.githubCopyCode),
                ),
                FilledButton.icon(
                  key: const ValueKey('github-open-browser'),
                  onPressed: () => _invoke(
                    () => RunnerService.openUrl(
                      device.verificationUri.toString(),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(l10n.githubOpenBrowser),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.githubWaiting),
            TextButton(
              onPressed: () => _invoke(_auth.cancelDeviceOAuth),
              child: Text(l10n.cancel),
            ),
          ] else
            FilledButton.icon(
              key: const ValueKey('github-oauth-connect'),
              onPressed: _auth.isBusy
                  ? null
                  : () => _invoke(_auth.beginDeviceOAuth),
              icon: const Icon(Icons.login),
              label: Text(l10n.githubConnect),
            ),
        ] else ...[
          TextField(
            key: const ValueKey('github-pat'),
            controller: _pat,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_auth.isBusy,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.githubPatHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _signInPat(),
          ),
          const SizedBox(height: 8),
          Text(l10n.githubPatPrivacy),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('github-pat-connect'),
            onPressed: _auth.isBusy || _pat.text.trim().isEmpty
                ? null
                : _signInPat,
            icon: const Icon(Icons.login),
            label: Text(l10n.githubConnect),
          ),
        ],
        if (_auth.isBusy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Widget _repositories(StudioLocalizations l10n) {
    final repositories = _auth.repositories
        .where(
          (repository) =>
              repository.fullName.toLowerCase().contains(_query) ||
              (repository.description ?? '').toLowerCase().contains(_query),
        )
        .toList();
    // Header and results share one scroll viewport. A keyboard or large text
    // must not strand the repository list below a non-scrollable tall header.
    return CustomScrollView(
      key: const ValueKey('github-repositories'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _auth.account?.login ?? '',
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
                    TextButton(
                      onPressed: _auth.selectVisibleRepositories,
                      child: Text(l10n.githubSelectLoaded),
                    ),
                    TextButton(
                      onPressed: _auth.clearSelection,
                      child: Text(l10n.githubClearSelection),
                    ),
                  ],
                ),
                Text(l10n.githubLoadedCount(_auth.repositories.length)),
                if (_auth.isLoadingRepositories)
                  const LinearProgressIndicator(),
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (repositories.isEmpty) Text(l10n.githubNoRepositories),
                if (_auth.hasMoreRepositories)
                  OutlinedButton(
                    key: const ValueKey('github-load-more'),
                    onPressed: _auth.isLoadingRepositories
                        ? null
                        : () => _invoke(_auth.loadNextRepositoryPage),
                    child: Text(l10n.githubLoadMore),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _repository(GitHubRepository repository, StudioLocalizations l10n) =>
      CheckboxListTile(
        key: ValueKey('github-repository-${repository.id}'),
        value: _auth.selectedRepositoryIds.contains(repository.id),
        onChanged: (value) =>
            _auth.setRepositorySelected(repository.id, value ?? false),
        title: Text(repository.fullName),
        subtitle: Text(
          [
            if (repository.isPrivate) l10n.githubPrivate,
            if (repository.archived) l10n.githubArchived,
            if (repository.description?.isNotEmpty == true)
              repository.description!,
          ].join(' · '),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      );
}
