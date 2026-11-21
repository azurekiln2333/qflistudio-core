import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/git_clone_service.dart';
import 'github_api.dart';
import 'github_credential_store.dart';
import 'github_models.dart';

/// Compile-time public GitHub OAuth App client ID.
///
/// A release may omit this define. The controller then reports OAuth as
/// unavailable and leaves PAT as an explicit alternative; no client secret is
/// required or accepted.
const String qfliGitHubClientId = String.fromEnvironment(
  'QFLI_GITHUB_CLIENT_ID',
);

/// Observable auth, repository listing and clone handoff for GitHub.
///
/// Constructing this controller starts no I/O. The host explicitly calls
/// [restore] and disposes it with its page/scope. This makes a fake subclass
/// safe for picker widget tests and keeps auth from surprising app startup.
class GitHubAuthController extends ChangeNotifier {
  GitHubAuthController({
    String? clientId,
    GitHubCredentialStore? credentialStore,
    GitHubApi? api,
    Future<void> Function(Uri uri)? openBrowser,
    Future<void> Function(Duration duration)? sleep,
    DateTime Function()? clock,
  }) : clientId = clientId ?? qfliGitHubClientId,
       _credentialStore = credentialStore ?? FlutterGitHubCredentialStore(),
       _api = api ?? GitHubApi(),
       _ownsApi = api == null,
       _openBrowser = openBrowser,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final String clientId;
  final GitHubCredentialStore _credentialStore;
  final GitHubApi _api;
  final bool _ownsApi;
  final Future<void> Function(Uri uri)? _openBrowser;
  final Future<void> Function(Duration duration) _sleep;
  final DateTime Function() _clock;

  GitHubAuthStatus _status = GitHubAuthStatus.signedOut;
  GitHubAuthMethod? _authMethod;
  GitHubAccount? _account;
  GitHubDeviceAuthorization? _deviceAuthorization;
  String? _errorMessage;
  String? _accessToken;
  String? _credentialUsername;
  bool _isBusy = false;
  bool _isLoadingRepositories = false;
  bool _hasMoreRepositories = false;
  int _repositoryPage = 0;
  Uri? _nextPageUri;
  final List<GitHubRepository> _repositories = <GitHubRepository>[];
  final Set<int> _selectedIds = <int>{};
  int _generation = 0;
  int _repositoryGeneration = 0;
  bool _disposed = false;
  Future<void>? _restoreFuture;

  GitHubAuthStatus get status => _status;
  GitHubAuthMethod? get authMethod => _authMethod;
  GitHubAccount? get account => _account;
  GitHubDeviceAuthorization? get deviceAuthorization => _deviceAuthorization;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _isBusy;
  bool get isLoadingRepositories => _isLoadingRepositories;
  bool get hasMoreRepositories => _hasMoreRepositories;
  int get repositoryPage => _repositoryPage;
  List<GitHubRepository> get repositories =>
      List<GitHubRepository>.unmodifiable(_repositories);
  Set<int> get selectedRepositoryIds => Set<int>.unmodifiable(_selectedIds);

  List<GitHubRepository> get selectedRepositories =>
      List<GitHubRepository>.unmodifiable(
        _repositories.where(
          (repository) => _selectedIds.contains(repository.id),
        ),
      );

  GitHubCloneCredential? get cloneCredential {
    final token = _accessToken;
    final username = _credentialUsername;
    if (_status != GitHubAuthStatus.authenticated ||
        token == null ||
        username == null ||
        !_isCurrent(_generation)) {
      return null;
    }
    return GitHubCloneCredential(username: username, token: token);
  }

  /// Reads the vault once. The default constructor itself performs no I/O.
  Future<void> restore() => _restoreFuture ??= _restore();

  Future<void> _restore() async {
    if (_status == GitHubAuthStatus.authenticated || _disposed) return;
    final generation = _beginIntent();
    _setBusy(true, status: GitHubAuthStatus.loading);
    try {
      final token = await GitHubCredentialOperations.serializedForIntent(
        generation,
        _credentialStore.readAccessToken,
      );
      if (!_isCurrent(generation)) return;
      if (token == null || token.isEmpty) {
        _clearIdentity(keepStatus: true);
        _status = GitHubAuthStatus.signedOut;
        _errorMessage = null;
        _notify();
        return;
      }
      await _finishAuthentication(
        token: token,
        method: GitHubAuthMethod.personalAccessToken,
        persist: false,
        generation: generation,
      );
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      _clearIdentity(keepStatus: true);
      _status = GitHubAuthStatus.error;
      _errorMessage = _safeError(error);
      _notify();
    } finally {
      if (_isCurrent(generation)) _setBusy(false);
    }
  }

  /// Starts GitHub OAuth device flow and polls until a terminal result.
  Future<void> beginDeviceOAuth() async {
    if (_disposed || _isBusy) return;
    if (clientId.trim().isEmpty) {
      _status = GitHubAuthStatus.error;
      _errorMessage =
          'GitHub OAuth 尚未配置客户端 ID；请联系发布方配置 QFLI_GITHUB_CLIENT_ID，或使用 PAT。';
      _notify();
      return;
    }
    if (!_credentialStore.isAvailable) {
      _status = GitHubAuthStatus.error;
      _errorMessage = '此平台没有可用的 GitHub 安全存储，无法安全登录。';
      _notify();
      return;
    }
    final generation = _beginIntent();
    _clearIdentity(keepStatus: true);
    _setBusy(true, status: GitHubAuthStatus.loading);
    try {
      final privateDevice = await _api.requestDeviceCode(clientId.trim());
      if (!_isCurrent(generation)) return;
      _deviceAuthorization = GitHubDeviceAuthorization(
        userCode: privateDevice.userCode,
        verificationUri: privateDevice.verificationUri,
        expiresAt: privateDevice.expiresAt,
        pollingInterval: privateDevice.pollingInterval,
      );
      _status = GitHubAuthStatus.awaitingDeviceAuthorization;
      _errorMessage = null;
      _notify();

      // Browser failure does not invalidate the device grant. The picker keeps
      // the verification URL and user code available for copy/manual entry.
      try {
        await _openBrowser?.call(privateDevice.verificationUri);
      } on Object {
        // Deliberately do not expose platform/browser exception details.
      }

      var interval = privateDevice.pollingInterval;
      while (_isCurrent(generation) &&
          _clock().isBefore(privateDevice.expiresAt)) {
        await _sleep(interval);
        if (!_isCurrent(generation)) return;
        if (!_clock().isBefore(privateDevice.expiresAt)) break;
        final poll = await _api.pollDeviceToken(
          clientId: clientId.trim(),
          deviceCode: privateDevice.deviceCode,
        );
        if (!_isCurrent(generation)) return;
        switch (poll.status) {
          case GitHubTokenPollStatus.pending:
            continue;
          case GitHubTokenPollStatus.slowDown:
            interval += const Duration(seconds: 5);
            continue;
          case GitHubTokenPollStatus.authorized:
            final token = poll.token;
            if (token == null || token.isEmpty) {
              throw const GitHubApiException('GitHub OAuth 未返回访问凭据。');
            }
            await _finishAuthentication(
              token: token,
              method: GitHubAuthMethod.oauthDevice,
              persist: true,
              generation: generation,
            );
            return;
          case GitHubTokenPollStatus.denied:
            _setAuthFailure(generation, '用户拒绝了 GitHub OAuth 授权。');
            return;
          case GitHubTokenPollStatus.expired:
            _setAuthFailure(generation, 'GitHub OAuth 授权码已过期，请重新开始。');
            return;
          case GitHubTokenPollStatus.failed:
            _setAuthFailure(
              generation,
              poll.message ?? 'GitHub OAuth 授权失败，请重试。',
            );
            return;
        }
      }
      if (_isCurrent(generation)) {
        _setAuthFailure(generation, 'GitHub OAuth 授权超时，请重新开始。');
      }
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _setAuthFailure(generation, _safeError(error));
      }
    } finally {
      if (_isCurrent(generation)) _setBusy(false);
    }
  }

  Future<void> cancelDeviceOAuth() async {
    if (_status != GitHubAuthStatus.awaitingDeviceAuthorization &&
        _status != GitHubAuthStatus.loading) {
      return;
    }
    _invalidateIntent();
    _accessToken = null;
    _credentialUsername = null;
    _account = null;
    _authMethod = null;
    _deviceAuthorization = null;
    _status = GitHubAuthStatus.signedOut;
    _errorMessage = null;
    _isBusy = false;
    _clearRepositories();
    _notify();
  }

  /// Validates a PAT against `/user`; only persists after validation and only
  /// while the platform vault is usable.
  Future<void> signInWithPat(String pat) async {
    if (_disposed || _isBusy) return;
    final token = pat.trim();
    if (token.isEmpty) {
      _status = GitHubAuthStatus.error;
      _errorMessage = '请输入 GitHub Personal Access Token。';
      _notify();
      return;
    }
    if (!_credentialStore.isAvailable) {
      _status = GitHubAuthStatus.error;
      _errorMessage = '此平台没有可用的 GitHub 安全存储，无法安全登录。';
      _notify();
      return;
    }
    final generation = _beginIntent();
    _clearIdentity(keepStatus: true);
    _setBusy(true, status: GitHubAuthStatus.loading);
    try {
      await _finishAuthentication(
        token: token,
        method: GitHubAuthMethod.personalAccessToken,
        persist: true,
        generation: generation,
      );
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _clearIdentity(keepStatus: true);
        _setAuthFailure(generation, _safeError(error));
      }
    } finally {
      if (_isCurrent(generation)) _setBusy(false);
    }
  }

  Future<void> _finishAuthentication({
    required String token,
    required GitHubAuthMethod method,
    required bool persist,
    required int generation,
  }) async {
    final user = await _api.getAuthenticatedUser(token);
    if (!_isCurrent(generation)) return;
    // Serialize across controller instances. A newer intent skips this write if
    // it has not started. If it was already in progress, disconnect's queued
    // delete waits behind it, so returning from disconnect guarantees removal.
    if (persist) {
      final stored = await GitHubCredentialOperations.serializedForIntent(
        generation,
        () async {
          await _credentialStore.writeAccessToken(token);
          // Cancel/dispose can happen while native storage is awaiting. Remove
          // only this just-written value before releasing the queue slot; any
          // newer account write waits behind this cleanup and therefore wins.
          if (!GitHubCredentialOperations.isCurrent(generation) ||
              !_isCurrent(generation)) {
            await _credentialStore.deleteAccessToken();
            return false;
          }
          return true;
        },
      );
      if (stored != true || !_isCurrent(generation)) return;
    }
    if (!_isCurrent(generation)) return;
    _accessToken = token;
    _credentialUsername = method == GitHubAuthMethod.oauthDevice
        ? user.login
        : 'x-access-token';
    _account = user;
    _authMethod = method;
    _status = GitHubAuthStatus.authenticated;
    _errorMessage = null;
    _deviceAuthorization = null;
    _clearRepositories();
    _notify();
    // The picker can render the account immediately. Listing failure is kept as
    // a safe repository error and does not discard a valid authenticated user.
    unawaited(refreshRepositories());
  }

  /// Disconnects and invalidates all pending identity-bound requests.
  Future<void> disconnect() async {
    final generation = _invalidateIntent();
    _isBusy = false;
    _isLoadingRepositories = false;
    _accessToken = null;
    _credentialUsername = null;
    _account = null;
    _authMethod = null;
    _deviceAuthorization = null;
    _errorMessage = null;
    _status = GitHubAuthStatus.signedOut;
    _clearRepositories();
    _notify();
    try {
      await GitHubCredentialOperations.serialized(
        _credentialStore.deleteAccessToken,
      );
    } on Object catch (error) {
      if (_disposed || !_isCurrent(generation)) return;
      _status = GitHubAuthStatus.error;
      _errorMessage = _safeError(error);
      _notify();
    }
  }

  Future<void> refreshRepositories() async {
    final token = _accessToken;
    if (_status != GitHubAuthStatus.authenticated || token == null) return;
    final authGeneration = _generation;
    final repoGeneration = ++_repositoryGeneration;
    _isLoadingRepositories = true;
    _errorMessage = null;
    _hasMoreRepositories = false;
    _nextPageUri = null;
    _repositoryPage = 0;
    _repositories.clear();
    _selectedIds.clear();
    _notify();
    try {
      final page = await _api.listRepositories(token: token, page: 1);
      if (!_isRepositoryRequestCurrent(authGeneration, repoGeneration)) return;
      _appendUnique(page.repositories);
      _nextPageUri = page.nextPageUri;
      _hasMoreRepositories = _nextPageUri != null;
      _repositoryPage = 1;
    } on Object catch (error) {
      if (!_isRepositoryRequestCurrent(authGeneration, repoGeneration)) return;
      _errorMessage = _safeError(error);
    } finally {
      if (_isRepositoryRequestCurrent(authGeneration, repoGeneration)) {
        _isLoadingRepositories = false;
        _notify();
      }
    }
  }

  Future<void> loadNextRepositoryPage() async {
    final token = _accessToken;
    final next = _nextPageUri;
    if (_status != GitHubAuthStatus.authenticated ||
        token == null ||
        next == null ||
        _isLoadingRepositories) {
      return;
    }
    final authGeneration = _generation;
    final repoGeneration = _repositoryGeneration;
    _isLoadingRepositories = true;
    _notify();
    try {
      final page = await _api.listRepositories(
        token: token,
        pageUri: next,
        page: _repositoryPage + 1,
      );
      if (!_isRepositoryRequestCurrent(authGeneration, repoGeneration)) return;
      _appendUnique(page.repositories);
      _nextPageUri = page.nextPageUri;
      _hasMoreRepositories = _nextPageUri != null;
      _repositoryPage++;
    } on Object catch (error) {
      if (!_isRepositoryRequestCurrent(authGeneration, repoGeneration)) return;
      _errorMessage = _safeError(error);
    } finally {
      if (_isRepositoryRequestCurrent(authGeneration, repoGeneration)) {
        _isLoadingRepositories = false;
        _notify();
      }
    }
  }

  void setRepositorySelected(int repositoryId, bool selected) {
    if (_status != GitHubAuthStatus.authenticated ||
        !_repositories.any((repository) => repository.id == repositoryId)) {
      return;
    }
    if (selected) {
      _selectedIds.add(repositoryId);
    } else {
      _selectedIds.remove(repositoryId);
    }
    _notify();
  }

  void selectVisibleRepositories() {
    if (_status != GitHubAuthStatus.authenticated) return;
    _selectedIds.addAll(_repositories.map((repository) => repository.id));
    _notify();
  }

  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _notify();
  }

  /// Converts one selected repository to the existing clone request without
  /// putting credentials in its URL. Null means not authenticated/not selected.
  GitCloneRequest? buildCloneRequest(GitHubRepository repository) {
    final credential = cloneCredential;
    if (credential == null || !_selectedIds.contains(repository.id)) {
      return null;
    }
    final loaded = _repositories.where((item) => item.id == repository.id);
    if (loaded.isEmpty) return null;
    final confirmed = loaded.first;
    if (confirmed.cloneUrl != repository.cloneUrl ||
        confirmed.fullName != repository.fullName ||
        !_isCleanCloneUrl(confirmed.cloneUrl)) {
      return null;
    }
    return GitCloneRequest(
      url: confirmed.cloneUrl,
      name: confirmed.fullName,
      username: credential.username,
      token: credential.token,
    );
  }

  void _appendUnique(List<GitHubRepository> page) {
    final existing = _repositories.map((repo) => repo.id).toSet();
    for (final repository in page) {
      if (existing.add(repository.id)) _repositories.add(repository);
    }
  }

  bool _isRepositoryRequestCurrent(int authGeneration, int repoGeneration) =>
      !_disposed &&
      _generation == authGeneration &&
      GitHubCredentialOperations.isCurrent(authGeneration) &&
      _repositoryGeneration == repoGeneration &&
      _status == GitHubAuthStatus.authenticated;

  int _beginIntent() {
    final generation = GitHubCredentialOperations.beginIntent();
    _generation = generation;
    return generation;
  }

  int _invalidateIntent() => _beginIntent();

  bool _isCurrent(int generation) =>
      !_disposed &&
      _generation == generation &&
      GitHubCredentialOperations.isCurrent(generation);

  void _clearIdentity({required bool keepStatus}) {
    _accessToken = null;
    _credentialUsername = null;
    _account = null;
    _authMethod = null;
    _deviceAuthorization = null;
    _errorMessage = null;
    if (!keepStatus) _status = GitHubAuthStatus.signedOut;
    _clearRepositories();
  }

  void _clearRepositories() {
    ++_repositoryGeneration;
    _repositories.clear();
    _selectedIds.clear();
    _repositoryPage = 0;
    _nextPageUri = null;
    _hasMoreRepositories = false;
    _isLoadingRepositories = false;
  }

  void _setBusy(bool value, {GitHubAuthStatus? status}) {
    if (_disposed) return;
    _isBusy = value;
    if (status != null) _status = status;
    _notify();
  }

  void _setAuthFailure(int generation, String message) {
    if (!_isCurrent(generation)) return;
    _clearIdentity(keepStatus: true);
    _isBusy = false;
    _status = GitHubAuthStatus.error;
    _errorMessage = message;
    _notify();
  }

  String _safeError(Object error) {
    if (error is GitHubSecureStorageException || error is GitHubApiException) {
      return error.toString();
    }
    return 'GitHub 操作失败，请重试。';
  }

  bool _isCleanCloneUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'github.com' &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (GitHubCredentialOperations.isCurrent(_generation)) {
      GitHubCredentialOperations.beginIntent();
    }
    ++_generation;
    ++_repositoryGeneration;
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
