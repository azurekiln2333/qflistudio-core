/// Writes the request payload as one zip inside the Studio cache.
///
/// zlib.compressFile hung on a real API 26 device with a folder input: the
/// promise never settled and no zip appeared, which left the bridge's channel
/// future dangling. The zip is therefore built here with the pure-Dart archive
/// package. Dart and ArkTS share one sandbox, so the bridge only has to turn
/// the returned path into a granted file URI.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'interop_protocol.dart';

/// Writes `<cacheDirectory>/qfli_interop/out/<sessionId>.zip` and removes
/// leftovers from earlier sessions so failed runs cannot accumulate caches.
/// Returns the zip path the bridge grants to the receiver.
///
/// Callers must have validated the payload already ([InteropRequest]
/// validation covers path grammar and size caps); this function writes
/// exactly the files it is given.
Future<String> writePayloadZip({
  required String cacheDirectory,
  required String sessionId,
  required List<InteropPayloadFile> files,
}) async {
  final outDirectory = Directory(p.join(cacheDirectory, 'qfli_interop', 'out'));
  if (outDirectory.existsSync()) {
    for (final entity in outDirectory.listSync()) {
      try {
        entity.deleteSync(recursive: true);
      } on FileSystemException {
        // A locked leftover must not fail the new run.
      }
    }
  }
  outDirectory.createSync(recursive: true);
  final archive = Archive();
  for (final file in files) {
    archive.addFile(ArchiveFile.bytes(file.path, file.content));
  }
  final zipPath = p.join(outDirectory.path, '$sessionId.zip');
  File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));
  return zipPath;
}
