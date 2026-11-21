import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'github_platform_stub.dart'
    if (dart.library.io) 'github_platform_io.dart';

/// Operation-scoped GitHub credential storage.
///
/// Tokens are never written to files, project metadata, SharedPreferences or
/// QFLI's account store. Implementations may be injected by tests; production
/// uses [FlutterGitHubCredentialStore] and the platform secure vault.
abstract interface class GitHubCredentialStore {
  /// False only where this platform has no vetted secure vault.
  bool get isAvailable;

  Future<String?> readAccessToken();
  Future<void> writeAccessToken(String token);
  Future<void> deleteAccessToken();
}

/// Platform-vault implementation backed by flutter_secure_storage.
///
/// OHOS currently has no verified implementation in the selected plugin; this
/// class fails closed there rather than pretending persistence succeeded.
class FlutterGitHubCredentialStore implements GitHubCredentialStore {
  FlutterGitHubCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'github.access_token.v1';
  final FlutterSecureStorage _storage;

  @override
  bool get isAvailable => !kIsWeb && !isUnsupportedGithubCredentialPlatform;

  static const AndroidOptions _androidOptions = AndroidOptions(
    storageNamespace: 'com.azurekiln.qfli.github',
  );
  static final IOSOptions _iosOptions = const IOSOptions(
    accountName: 'com.azurekiln.qfli.github',
    accessibility: KeychainAccessibility.unlocked_this_device,
  );
  static final MacOsOptions _macosOptions = const MacOsOptions(
    accountName: 'com.azurekiln.qfli.github',
    accessibility: KeychainAccessibility.unlocked_this_device,
    // This app does not share Keychain records with other apps. The legacy
    // Keychain avoids the Keychain Sharing entitlement/provisioning requirement.
    usesDataProtectionKeychain: false,
  );

  void _requireSupported() {
    if (!isAvailable) {
      throw const GitHubSecureStorageException(
        '此平台没有可用的 GitHub 安全存储，无法安全保存或使用 GitHub 凭据。',
      );
    }
  }

  @override
  Future<String?> readAccessToken() async {
    _requireSupported();
    try {
      return await _storage.read(
        key: _key,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
        mOptions: _macosOptions,
      );
    } on Object {
      throw const GitHubSecureStorageException('系统安全存储不可用，无法读取 GitHub 凭据。');
    }
  }

  @override
  Future<void> writeAccessToken(String token) async {
    _requireSupported();
    if (token.trim().isEmpty) {
      throw const GitHubSecureStorageException('GitHub 凭据为空。');
    }
    try {
      await _storage.write(
        key: _key,
        value: token,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
        mOptions: _macosOptions,
      );
    } on Object {
      throw const GitHubSecureStorageException('系统安全存储不可用，GitHub 登录未完成。');
    }
  }

  @override
  Future<void> deleteAccessToken() async {
    _requireSupported();
    try {
      await _storage.delete(
        key: _key,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
        mOptions: _macosOptions,
      );
    } on Object {
      throw const GitHubSecureStorageException('系统安全存储不可用，无法安全清除 GitHub 凭据。');
    }
  }
}

/// Serializes secure-vault operations and fences intent across controllers.
///
/// Controllers share one vault namespace, so ordering is process-wide. An
/// obsolete read/write queued before a newer intent is skipped. A newer delete
/// stays in the queue after an already-running write and guarantees that
/// `disconnect()` returns only after the stale value was removed.
abstract final class GitHubCredentialOperations {
  static Future<void> _tail = Future<void>.value();
  static int _intentGeneration = 0;

  static int beginIntent() => ++_intentGeneration;

  static bool isCurrent(int generation) => generation == _intentGeneration;

  static Future<T?> serializedForIntent<T>(
    int generation,
    Future<T> Function() operation,
  ) => serialized<T?>(() async {
    if (!isCurrent(generation)) return null;
    return operation();
  });

  static Future<T> serialized<T>(Future<T> Function() operation) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return () async {
      try {
        await previous;
      } catch (_) {
        // A failed vault operation must not poison later reads/deletes.
      }
      try {
        return await operation();
      } finally {
        released.complete();
      }
    }();
  }
}

/// Safe, credential-free secure storage error.
class GitHubSecureStorageException implements Exception {
  const GitHubSecureStorageException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Process-local fake seam for tests. Production never selects this automatically.
class MemoryGitHubCredentialStore implements GitHubCredentialStore {
  String? _token;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> writeAccessToken(String token) async {
    _token = token;
  }

  @override
  Future<void> deleteAccessToken() async {
    _token = null;
  }

  @visibleForTesting
  bool get hasToken => _token != null;
}
