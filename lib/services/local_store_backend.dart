import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// Where a local store persists itself.
///
/// An interface rather than a bare `File` so tests can inject an in-memory
/// backend and never touch the disk: real file IO inside a widget test leaves
/// pending Futures that can stop the test process from exiting.
abstract interface class LocalStoreBackend {
  /// Returns the stored payload, or null when nothing has been written yet.
  Future<String?> read();

  /// Replaces the stored payload.
  Future<void> write(String payload);
}

/// The production backend: a JSON file in the app storage directory.
class LocalFileBackend implements LocalStoreBackend {
  const LocalFileBackend(this.fileName);

  /// File name under `AppPaths.storageDirectory()`.
  final String fileName;

  @override
  Future<String?> read() async {
    final file = await _resolve();
    if (file == null || !await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String payload) async {
    final file = await _resolve();
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(payload, flush: true);
  }

  Future<File?> _resolve() async {
    final directory = await AppPaths.storageDirectory();
    if (directory == null || directory.isEmpty) return null;
    return File(p.join(directory, fileName));
  }
}

/// An in-memory backend, for tests and for any platform without a writable
/// directory. Writes complete synchronously (as a completed Future), so no IO
/// Future can outlive the caller.
class LocalMemoryBackend implements LocalStoreBackend {
  LocalMemoryBackend([this._payload]);

  String? _payload;

  /// The last written payload, for assertions.
  String? get payload => _payload;

  bool get hasWrite => _payload != null;

  @override
  Future<String?> read() async => _payload;

  @override
  Future<void> write(String payload) async => _payload = payload;
}
