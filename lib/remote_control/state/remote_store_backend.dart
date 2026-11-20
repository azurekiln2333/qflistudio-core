// Storage boundary for the remote-control module.
//
// The pairing document lives in the host app's private support directory. This
// file owns the platform-neutral contract; `remote_store_backend_io.dart` is the
// native implementation and `remote_store_backend_stub.dart` is the browser-safe
// fallback. Keeping the boundary here means `remote_store.dart` (and every
// controller above it) stays free of `dart:io`.

/// File name of the module's private document.
///
/// Deliberately not `cloudterminal.json`: the source application's credentials
/// must never be picked up automatically, and this feature keeps its own
/// namespace inside the host app's support directory.
const String remoteStoreFileName = 'qfli_remote_control.json';

/// One persisted JSON document.
abstract class RemoteStoreBackend {
  /// Loads the document. Missing or corrupt storage yields an empty map; the
  /// caller never has to handle "no file yet".
  Future<Map<String, dynamic>> read();

  /// Replaces the document. Implementations must be atomic (write a temporary
  /// file, then rename) so a crash cannot leave a half-written pairing.
  Future<void> write(Map<String, dynamic> data);
}

/// In-memory backend used by the unsupported-platform fallback and by tests.
class MemoryRemoteStoreBackend implements RemoteStoreBackend {
  MemoryRemoteStoreBackend([Map<String, dynamic>? data])
    : _data = data ?? <String, dynamic>{};

  Map<String, dynamic> _data;

  /// Last document written, for assertions in tests.
  Map<String, dynamic> get data => Map<String, dynamic>.unmodifiable(_data);

  @override
  Future<Map<String, dynamic>> read() async => Map<String, dynamic>.of(_data);

  @override
  Future<void> write(Map<String, dynamic> data) async {
    _data = Map<String, dynamic>.of(data);
  }
}
