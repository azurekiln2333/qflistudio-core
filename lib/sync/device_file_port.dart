import 'package:qfli_studio_core/remote_control/models/protocol.dart';

/// Narrow port over the paired-computer channel used by the device sync paths.
///
/// The sync services ask this port for what they need and never touch the
/// socket themselves, so cloud tests inject a fake instead of opening a real
/// connection.
abstract interface class DeviceFilePort {
  /// Git metadata of [root] on the computer.
  ///
  /// Throws when the computer cannot answer, which makes the caller take the
  /// file transfer path.
  Future<GitProjectInfo> gitInfo(String root);

  /// Every file and directory under [root] that the ignore table keeps.
  Future<FsManifest> manifest(String root);

  /// Bytes of [path] starting at [offset], at most one chunk per call.
  Future<FsChunk> read(String path, {required int offset, int? length});
}
