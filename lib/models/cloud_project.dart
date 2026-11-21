import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable storage identity. Tokens and display names never form directory keys.
class CloudProjectScope {
  CloudProjectScope({required String origin, required this.accountId})
    : origin = _origin(origin) {
    if (accountId.isEmpty ||
        accountId.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(accountId)) {
      throw const CloudOperationException('scope', '云端账号标识无效');
    }
  }

  final String origin;
  final String accountId;
  String get originKey => sha256.convert(utf8.encode(origin)).toString();
  String get accountKey => sha256.convert(utf8.encode(accountId)).toString();
  String get key => '$originKey/$accountKey';

  static String _origin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const CloudOperationException('scope', '云端服务地址无效');
    }
    return uri.origin;
  }

  static String validateCloudId(String value) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value) ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const CloudOperationException('path', '云端项目 ID 无效');
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is CloudProjectScope &&
      other.origin == origin &&
      other.accountId == accountId;
  @override
  int get hashCode => Object.hash(origin, accountId);
  @override
  String toString() => 'CloudProjectScope($originKey/$accountKey)';
}

/// One captured login generation, rechecked before and after each async step.
class CloudSession {
  CloudSession({
    required this.scope,
    required String token,
    required bool Function() isCurrent,
  }) : _token = token,
       _isCurrent = isCurrent;

  final CloudProjectScope scope;
  final String _token;
  final bool Function() _isCurrent;

  void ensureCurrent() {
    if (_token.isEmpty || !_isCurrent()) {
      throw const CloudOperationException('sessionChanged', '账号已切换，请重试');
    }
  }

  /// Only the scoped API boundary uses this. Never serialize or log it.
  String get token {
    ensureCurrent();
    return _token;
  }

  bool acceptsToken(String value) => value == _token;
  @override
  String toString() => 'CloudSession(redacted)';
}

class CloudOperationException implements Exception {
  const CloudOperationException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

enum CloudCachePhase { notCached, caching, cached, failed }

class CloudCacheStatus {
  const CloudCacheStatus({
    this.phase = CloudCachePhase.notCached,
    this.completedFiles = 0,
    this.totalFiles = 0,
    this.downloadedBytes = 0,
    this.fileCount = 0,
    this.bytes = 0,
    this.cachedAt,
    this.error,
  });
  final CloudCachePhase phase;
  final int completedFiles;
  final int totalFiles;
  final int downloadedBytes;
  final int fileCount;
  final int bytes;
  final DateTime? cachedAt;
  final String? error;
}

class CloudDeleteResult {
  const CloudDeleteResult({
    required this.remoteDeleted,
    this.error,
    this.cleanupError,
  });
  final bool remoteDeleted;
  final String? error;
  final String? cleanupError;
}

/// Payload-only immutable remote snapshot, held until its consumer releases it.
class CloudSnapshot {
  CloudSnapshot({
    required this.path,
    required this.fileCount,
    required this.bytes,
    required this.cachedAt,
    required void Function() ensureCurrent,
    required Future<void> Function() release,
  }) : _ensureCurrent = ensureCurrent,
       _release = release;
  final String path;
  final int fileCount;
  final int bytes;
  final DateTime cachedAt;
  final void Function() _ensureCurrent;
  final Future<void> Function() _release;
  Future<void>? _released;
  void ensureCurrent() {
    if (_released != null) {
      throw const CloudOperationException('released', '缓存快照已释放');
    }
    _ensureCurrent();
  }

  Future<void> release() => _released ??= _release();
}

/// Cross-instance editor/push activity. Cache operations never mutate a workspace
/// held by an editor. Dirty marks also survive closing that editor in-process.
abstract final class CloudWorkspaceActivity {
  static final _editors = <String, int>{};
  static final _pending = <String, int>{};
  static final _dirty = <String, Set<String>>{};
  static String key(CloudProjectScope scope, String id) => '${scope.key}/$id';
  static void open(String key) => _editors[key] = (_editors[key] ?? 0) + 1;
  static void close(String key) => _decrement(_editors, key);
  static bool active(String key) => (_editors[key] ?? 0) > 0;
  static void beginPush(String key) => _pending[key] = (_pending[key] ?? 0) + 1;
  static void endPush(String key) => _decrement(_pending, key);
  static bool pending(String key) => (_pending[key] ?? 0) > 0;
  static bool dirty(String key) => _dirty[key]?.isNotEmpty ?? false;
  static void markDirty(String key, String path) =>
      (_dirty[key] ??= <String>{}).add(path);
  static void markSynced(String key, String path) => _dirty[key]?.remove(path);
  static void _decrement(Map<String, int> map, String key) {
    final count = (map[key] ?? 0) - 1;
    if (count <= 0) {
      map.remove(key);
    } else {
      map[key] = count;
    }
  }
}
