import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../github/github_auth_controller.dart';
import '../../github/github_models.dart';
import '../../i18n/studio_localizations.dart';
import '../../services/runner_service.dart';

/// GitHub connection controls for Profile and the standalone picker.
/// The host restores and disposes [controller]. This panel only cancels a
/// device flow it started. Retained hosts must mark hidden panels inactive or
/// disable their TickerMode; Offstage alone does not signal visibility.
class GitHubConnectionPanel extends StatefulWidget {
  const GitHubConnectionPanel({
    super.key,
    required this.controller,
    this.isActive = true,
  });

  final GitHubAuthController controller;
  final bool isActive;

  @override
  State<GitHubConnectionPanel> createState() => _GitHubConnectionPanelState();
}

class _GitHubConnectionPanelState extends State<GitHubConnectionPanel>
    with AutomaticKeepAliveClientMixin {
  final _pat = TextEditingController();
  GitHubAuthMethod _method = GitHubAuthMethod.oauthDevice;
  _PanelDeviceFlow? _deviceFlow;
  bool _active = true;
  bool _reconnecting = false;
  String? _actionError;

  bool get _ownsPendingDeviceFlow => _deviceFlow?.finished == false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateVisibility();
  }

  @override
  void didUpdateWidget(GitHubConnectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _cancelOwnedDeviceFlow();
      _pat.clear();
      _reconnecting = false;
      _actionError = null;
    }
    _updateVisibility();
  }

  void _updateVisibility() {
    _active =
        widget.isActive &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (!_active) {
      _pat.clear();
      _cancelOwnedDeviceFlow();
    }
  }

  void _cancelOwnedDeviceFlow() {
    final flow = _deviceFlow;
    if (flow == null) return;
    _deviceFlow = null;
    // An inherited visibility change or disposal can occur during a parent
    // build. Defer notification until the current build has finished.
    unawaited(
      Future<void>.microtask(() async {
        try {
          await flow.cancel();
        } catch (_) {
          // Lifecycle cleanup must not expose transport/credential errors.
        }
      }),
    );
  }

  @override
  void dispose() {
    _cancelOwnedDeviceFlow();
    _pat.dispose();
    super.dispose();
  }

  Future<void> _invoke(Future<void> Function() action) async {
    final controller = widget.controller;
    setState(() => _actionError = null);
    try {
      await action();
    } catch (_) {
      if (mounted && controller == widget.controller) {
        setState(
          () => _actionError = StudioLocalizations.of(
            context,
          ).githubRequestFailed,
        );
      }
    }
  }

  Future<void> _beginDeviceOAuth() async {
    final controller = widget.controller;
    if (!_active || controller.isBusy || _ownsPendingDeviceFlow) return;
    final flow = _PanelDeviceFlow(controller);
    _deviceFlow = flow;
    await _invoke(() async {
      try {
        await controller.beginDeviceOAuth();
      } finally {
        flow.finish();
      }
    });
    if (!mounted || _deviceFlow != flow) return;
    setState(() {
      _deviceFlow = null;
      if (controller.status == GitHubAuthStatus.authenticated) {
        _reconnecting = false;
      }
    });
  }

  Future<void> _changeMethod(GitHubAuthMethod method) async {
    final controller = widget.controller;
    if (!_active || (controller.isBusy && !_ownsPendingDeviceFlow)) return;
    if (_ownsPendingDeviceFlow) {
      final flow = _deviceFlow!;
      _deviceFlow = null;
      await _invoke(flow.cancel);
    }
    if (!mounted || controller != widget.controller) return;
    _pat.clear();
    setState(() {
      _method = method;
      _actionError = null;
    });
  }

  Future<void> _signInPat() async {
    final controller = widget.controller;
    final value = _pat.text.trim();
    if (!_active || controller.isBusy || value.isEmpty) return;
    _pat.clear();
    FocusScope.of(context).unfocus();
    await _invoke(() => controller.signInWithPat(value));
    if (mounted &&
        controller == widget.controller &&
        controller.status == GitHubAuthStatus.authenticated) {
      setState(() => _reconnecting = false);
    }
  }

  Future<void> _disconnect() async {
    _deviceFlow = null;
    _pat.clear();
    setState(() => _reconnecting = false);
    await _invoke(widget.controller.disconnect);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final auth = widget.controller;
        final l10n = StudioLocalizations.of(context);
        final signedIn = auth.status == GitHubAuthStatus.authenticated;
        final device = auth.deviceAuthorization;
        final canChangeMethod =
            _active && (!auth.isBusy || _ownsPendingDeviceFlow);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_actionError ?? auth.errorMessage case final error?) ...[
                Text(
                  error,
                  key: const ValueKey('github-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              if (auth.hasConnection || signedIn) ...[
                Text(
                  auth.account?.login ?? 'GitHub',
                  key: const ValueKey('github-account'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('github-reconnect'),
                      onPressed: !_active || auth.isBusy
                          ? null
                          : () {
                              setState(() => _reconnecting = true);
                            },
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        l10n.isEnglish
                            ? 'Reconnect GitHub'
                            : l10n.isTraditionalChinese
                            ? '重新連接 GitHub'
                            : '重新连接 GitHub',
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('github-disconnect'),
                      onPressed: _active ? _disconnect : null,
                      icon: const Icon(Icons.link_off),
                      label: Text(l10n.githubDisconnect),
                    ),
                  ],
                ),
              ],
              if (!signedIn || _reconnecting) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.githubOAuth),
                      avatar: const Icon(Icons.open_in_browser, size: 18),
                      selected: _method == GitHubAuthMethod.oauthDevice,
                      onSelected: canChangeMethod
                          ? (_) => _changeMethod(GitHubAuthMethod.oauthDevice)
                          : null,
                    ),
                    ChoiceChip(
                      label: Text(l10n.githubPat),
                      avatar: const Icon(Icons.key, size: 18),
                      selected: _method == GitHubAuthMethod.personalAccessToken,
                      onSelected: canChangeMethod
                          ? (_) => _changeMethod(
                              GitHubAuthMethod.personalAccessToken,
                            )
                          : null,
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
                          onPressed: !_active
                              ? null
                              : () => _invoke(
                                  () => Clipboard.setData(
                                    ClipboardData(text: device.userCode),
                                  ),
                                ),
                          icon: const Icon(Icons.copy),
                          label: Text(l10n.githubCopyCode),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('github-open-browser'),
                          onPressed: !_active
                              ? null
                              : () => _invoke(
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
                  ] else
                    FilledButton.icon(
                      key: const ValueKey('github-oauth-connect'),
                      onPressed: !_active || auth.isBusy
                          ? null
                          : _beginDeviceOAuth,
                      icon: const Icon(Icons.login),
                      label: Text(l10n.githubConnect),
                    ),
                  if (_ownsPendingDeviceFlow)
                    TextButton(
                      key: const ValueKey('github-cancel-oauth'),
                      onPressed: !_active
                          ? null
                          : () => _changeMethod(GitHubAuthMethod.oauthDevice),
                      child: Text(l10n.cancel),
                    ),
                ] else ...[
                  TextField(
                    key: const ValueKey('github-pat'),
                    controller: _pat,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: _active && !auth.isBusy,
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
                    onPressed:
                        !_active || auth.isBusy || _pat.text.trim().isEmpty
                        ? null
                        : _signInPat,
                    icon: const Icon(Icons.login),
                    label: Text(l10n.githubConnect),
                  ),
                ],
              ],
              if (auth.isBusy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PanelDeviceFlow {
  _PanelDeviceFlow(this.controller) {
    controller.addListener(_authChanged);
  }

  final GitHubAuthController controller;
  bool finished = false;

  // A disconnected or completed flow may still be awaiting its polling sleep.
  // Observe terminal state synchronously so a later PAT/restore request cannot
  // be mistaken for this panel's still-pending device request.
  void _authChanged() {
    if (controller.status != GitHubAuthStatus.loading &&
        controller.status != GitHubAuthStatus.awaitingDeviceAuthorization) {
      finish();
    }
  }

  void finish() {
    if (finished) return;
    finished = true;
    controller.removeListener(_authChanged);
  }

  Future<void> cancel() async {
    if (finished) return;
    try {
      await controller.cancelDeviceOAuth();
    } finally {
      finish();
    }
  }
}
