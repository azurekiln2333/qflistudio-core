import 'package:flutter/foundation.dart';

/// GitHub authentication state exposed to the UI.
enum GitHubAuthStatus {
  signedOut,
  loading,
  awaitingDeviceAuthorization,
  authenticated,
  error,
}

/// How the current account authenticated.
enum GitHubAuthMethod { oauthDevice, personalAccessToken }

/// Public profile returned by GitHub `GET /user`.
@immutable
class GitHubAccount {
  const GitHubAccount({
    required this.id,
    required this.login,
    this.name,
    this.avatarUrl,
  });

  final int id;
  final String login;
  final String? name;
  final String? avatarUrl;
}

/// Repository visible to the authenticated GitHub credential.
@immutable
class GitHubRepository {
  const GitHubRepository({
    required this.id,
    required this.name,
    required this.fullName,
    required this.ownerLogin,
    required this.isPrivate,
    required this.htmlUrl,
    required this.cloneUrl,
    this.description,
    this.defaultBranch,
    this.archived = false,
  });

  final int id;
  final String name;
  final String fullName;
  final String ownerLogin;
  final bool isPrivate;
  final String htmlUrl;

  /// Clean HTTPS URL; never includes an OAuth/PAT credential.
  final String cloneUrl;

  final String? description;
  final String? defaultBranch;
  final bool archived;
}

/// Safe device authorization information shown to the user.
///
/// The OAuth `device_code` is deliberately not a field of this model.
@immutable
class GitHubDeviceAuthorization {
  const GitHubDeviceAuthorization({
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.pollingInterval,
  });

  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration pollingInterval;
}

/// Clone-only credential shape. Callers must keep it operation-scoped.
@immutable
class GitHubCloneCredential {
  const GitHubCloneCredential({required this.username, required this.token});

  final String username;
  final String token;

  @override
  String toString() => 'GitHubCloneCredential(redacted)';
}
