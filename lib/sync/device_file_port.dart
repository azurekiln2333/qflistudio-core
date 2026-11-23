import 'package:qfli_studio_core/remote_control/models/protocol.dart';

/// Absolute path of [path] on the computer.
///
/// The sync service keeps every path relative to the project root, because that
/// is what a manifest is; the computer needs a path it can resolve on its own
/// side, since `path.resolve` there is relative to the agent's working
/// directory. [root] is the root the agent reported in its manifest (null when
/// no manifest has been asked for yet).
String resolveDevicePath(String? root, String path) {
  if (root == null || root.isEmpty) return path;
  if (path.isEmpty) return root;
  if (path.startsWith('/')) return path;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) return path;
  final separator = root.contains('\\') ? '\\' : '/';
  final base = root.endsWith('/') || root.endsWith('\\')
      ? root.substring(0, root.length - 1)
      : root;
  return '$base$separator${path.replaceAll('/', separator)}';
}

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
