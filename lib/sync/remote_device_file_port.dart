import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';

/// [DeviceFilePort] backed by the paired-computer channel.
///
/// Thin by design: every call becomes one `project_git_info` request on the
/// existing controller, so request ids, timeouts and the offline error message
/// stay in one place.
class RemoteDeviceFilePort implements DeviceFilePort {
  RemoteDeviceFilePort(this.controller);

  final RemoteController controller;

  @override
  Future<GitProjectInfo> gitInfo(String root) =>
      controller.projectGitInfo(root);
}
