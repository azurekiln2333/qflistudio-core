// Private JSON store for the remote-control module.
//
// Migrated from CloudTerminal's `lib/state/app_store.dart` (AppStore). The
// document is `qfli_remote_control.json` in the host app's private support
// directory — a new namespace, so a CloudTerminal installation's
// `cloudterminal.json` is never read automatically and no Studio login token is
// reused.
//
// The pairing secret grants control of the paired computer, so it lives only in
// app-private storage (not shared preferences that some platforms export in
// backups, and not external storage). This is app-private plaintext, not
// encryption: that limitation is deliberate and documented rather than implied.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'remote_store_backend.dart';
import 'remote_store_backend_stub.dart'
    if (dart.library.io) 'remote_store_backend_io.dart'
    as platform;

/// Credentials for one paired computer.
class Pairing {
  const Pairing({
    required this.relayUrl,
    required this.agentId,
    required this.secret,
    this.name = '',
  });

  factory Pairing.fromJson(Map<String, dynamic> json) => Pairing(
    relayUrl: json['relayUrl'] as String,
    agentId: json['agentId'] as String,
    secret: json['secret'] as String,
    name: json['name'] as String? ?? '',
  );

  final String relayUrl;
  final String agentId;
  final String secret;
  final String name;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'relayUrl': relayUrl,
    'agentId': agentId,
    'secret': secret,
    'name': name,
  };

  Pairing copyWith({String? name}) => Pairing(
    relayUrl: relayUrl,
    agentId: agentId,
    secret: secret,
    name: name ?? this.name,
  );

  /// Never renders the secret; used if a pairing ever reaches a log line.
  @override
  String toString() => 'Pairing(relayUrl: $relayUrl, agentId: $agentId)';
}

/// Tiny JSON key/value store in the app's private support directory.
class RemoteStore {
  RemoteStore._(this._backend, this._data);

  /// In-memory store for tests and platforms without a writable directory.
  RemoteStore.memory([Map<String, dynamic>? data])
    : _backend = null,
      _data = data ?? <String, dynamic>{};

  /// Opens the private document, falling back to memory.
  ///
  /// A missing plugin channel (host without `path_provider`) or a filesystem
  /// error must not stop the app from launching: the module keeps working for
  /// this run and simply cannot restore the pairing. Corrupt JSON is handled by
  /// the backend, which starts from an empty document.
  static Future<RemoteStore> open({RemoteStoreBackend? backend}) async {
    try {
      final resolved =
          backend ?? await platform.openDefaultRemoteStoreBackend();
      return RemoteStore._(resolved, await resolved.read());
    } on MissingPluginException catch (e) {
      debugPrint('RemoteStore: no storage plugin, using memory: $e');
      return RemoteStore.memory();
    } catch (e) {
      debugPrint('RemoteStore: falling back to memory: $e');
      return RemoteStore.memory();
    }
  }

  /// File name of the private document, for diagnostics and docs.
  static const String fileName = remoteStoreFileName;

  final RemoteStoreBackend? _backend;
  final Map<String, dynamic> _data;

  /// Serialises writes; see [_put].
  Future<void>? _writes;

  Pairing? get pairing {
    final raw = _data['pairing'];
    if (raw is! Map<String, dynamic>) return null;
    try {
      return Pairing.fromJson(raw);
    } on TypeError {
      return null;
    }
  }

  Future<void> setPairing(Pairing? value) => _put('pairing', value?.toJson());

  String? getString(String key) => _data[key] as String?;

  Future<void> setString(String key, String? value) => _put(key, value);

  /// Last server address typed on the pair screen (kept after unpairing).
  String? get lastRelayUrl => getString('lastRelayUrl');

  /// Current document, for tests and diagnostics.
  ///
  /// Contains the pairing secret when one is stored; callers must not log it.
  @visibleForTesting
  Map<String, dynamic> get document => Map<String, dynamic>.unmodifiable(_data);

  /// Applies one key and persists.
  ///
  /// Writes are **ordered**: each flush waits for the previous one, so two rapid
  /// updates cannot interleave their temporary files, and the last snapshot
  /// flushed is the one that stays on disk. A failed write is still reported to
  /// this caller but does not poison the chain, so a later pairing can be saved.
  Future<void> _put(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    final backend = _backend;
    if (backend == null) return Future<void>.value();
    final previous = _writes ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => backend.write(_data));
    _writes = next.catchError((Object _) {});
    return next;
  }
}
