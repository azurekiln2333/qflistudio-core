import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';

/// [DeviceFilePort] backed by the paired-computer channel.
///
/// Thin by design: every call becomes one request on the existing controller,
/// so request ids, timeouts and the offline error message stay in one place.
///
/// The only thing it translates is the path in `fs_read`. A manifest is relative
/// to the project root, but the computer resolves the path it is given against
/// its own working directory, so the root the agent reported is prefixed again.
class RemoteDeviceFilePort implements DeviceFilePort {
  RemoteDeviceFilePort(this.controller);

  final RemoteController controller;

  /// Root of the last manifest, as the computer reported it.
  String? _root;

  @override
  Future<GitProjectInfo> gitInfo(String root) =>
      controller.projectGitInfo(root);

  @override
  Future<FsManifest> manifest(String root) async {
    final manifest = FsManifest.fromJson(
      await controller.projectFsManifest(root),
    );
    _root = manifest.root.isEmpty ? root : manifest.root;
    return manifest;
  }

  @override
  Future<FsChunk> read(String path, {required int offset, int? length}) async =>
      FsChunk.fromJson(
        await controller.projectFsRead(
          resolveDevicePath(_root, path),
          offset: offset,
          length: length,
        ),
      );
}
