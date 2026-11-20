// Native persistence for the remote-control module.
//
// Selected by `remote_store.dart` on every platform with `dart:io`. The document
// is app-private plaintext JSON: it is not encrypted, and the pairing secret in
// it grants control of the paired computer, so it must never be logged, exported
// or copied into shared storage.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'remote_store_backend.dart';

/// Opens the app-private document in the support directory.
///
/// Throws when the directory is unavailable (missing plugin channel on a host
/// without `path_provider`, or a filesystem error); [RemoteStore.open] turns that
/// into an in-memory store rather than refusing to start.
Future<RemoteStoreBackend> openDefaultRemoteStoreBackend() async {
  final dir = await getApplicationSupportDirectory();
  return FileRemoteStoreBackend(
    File('${dir.path}${Platform.pathSeparator}$remoteStoreFileName'),
  );
}

/// JSON document on disk, written atomically.
class FileRemoteStoreBackend implements RemoteStoreBackend {
  FileRemoteStoreBackend(this.file);

  final File file;

  @override
  Future<Map<String, dynamic>> read() async {
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Corrupt file: start fresh rather than refusing to launch.
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    // Temporary file + rename: a crash mid-write must not leave a truncated
    // document that loses the pairing.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}
