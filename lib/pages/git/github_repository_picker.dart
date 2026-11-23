// R1: repository selection owns presentation only. GitHub auth, pagination,
// credential persistence and request-generation fences belong to lib/github.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../github/github_auth_controller.dart';
import '../../github/github_models.dart';
import '../../github/github_scope.dart';
import '../../i18n/studio_localizations.dart';
import '../../services/git_clone_service.dart';
import '../../services/runner_service.dart';
import 'github_connection_panel.dart';
import 'github_repository_list.dart';

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
  late GitHubAuthController _auth;
  bool _initialized = false;
  bool _ownsController = false;
  String? _actionError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final shared = widget.controller ?? GitHubScope.maybeOf(context);
    _ownsController = shared == null;
    _auth =
        shared ??
        GitHubAuthController(
          openBrowser: (uri) => RunnerService.openUrl(uri.toString()),
        );
    if (_ownsController) unawaited(_auth.restore());
  }

  @override
  void dispose() {
    // The connection panel cancels only its own device flow. An injected or
    // app-owned controller may still be serving Home or Profile.
    if (_ownsController) {
      // Finish this private controller's flow before disposal so the child
      // panel cannot later invalidate a newer controller during cleanup.
      unawaited(_auth.cancelDeviceOAuth());
      _auth.dispose();
    }
    super.dispose();
  }

  Future<void> _disconnect() async {
    setState(() => _actionError = null);
    try {
      await _auth.disconnect();
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = StudioLocalizations.of(
            context,
          ).githubRequestFailed,
        );
      }
    }
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
            if (signedIn)
              IconButton(
                key: const ValueKey('github-disconnect'),
                tooltip: l10n.githubDisconnect,
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_actionError case final error?)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: signedIn
                        ? GitHubRepositoryList.selection(controller: _auth)
                        : SingleChildScrollView(
                            child: GitHubConnectionPanel(controller: _auth),
                          ),
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
}
