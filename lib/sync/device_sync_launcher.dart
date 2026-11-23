import 'package:flutter/material.dart';

import '../models/project.dart';
import '../remote_control/remote_computer_page.dart';
import '../remote_control/state/remote_controller.dart';
import '../remote_control/state/remote_store.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import 'device_file_port.dart';
import 'device_sync_dialog.dart';
import 'placeholder_project.dart';
import 'remote_device_file_port.dart';

/// 编辑器页「从电脑同步」动作的接线处。
///
/// 编辑器页自己不持有配对连接：一个页面对多个会话，而配对只有一份。所以
/// 这里在按下按钮时才打开配对存储与控制器，用完立刻关掉，不把长连接留在
/// 页面上。这样即使页面一直开着，也不会多出一条常驻的 WebSocket。
class DeviceSyncLauncher {
  const DeviceSyncLauncher();

  /// 项目能否从配对电脑同步。
  ///
  /// 两个条件必须同时成立：项目来自配对电脑，并且产品开了这个入口。
  /// 产品开关保证离线语言产品看不到它；[Project.isDevice] 保证普通本地项目
  /// 与云端项目不会拿到一个指向电脑的按钮。
  static bool canSync(Project project) =>
      project.isDevice && project.deviceHostId != null;

  /// 跑一次同步。
  ///
  /// 失败只弹一次说明，不抛给界面：同步是用户主动的附加动作，失败不该让
  /// 编辑器出现未处理异常。成功时把项目从占位项目改成已拉取。
  Future<void> run(
    BuildContext context, {
    required Project project,
    required ProjectStore store,
    required SettingsStore settings,
    required AuthStore auth,
    DeviceFilePort? portOverride,
  }) async {
    final deviceRoot = project.deviceRoot;
    if (deviceRoot == null || deviceRoot.trim().isEmpty) {
      _explain(context, '这个项目没有记下电脑上的路径，无法同步。');
      return;
    }
    final localFiles = await const PlaceholderProjects().filesRoot(project);
    if (!context.mounted) return;
    if (localFiles == null) {
      _explain(context, '未找到可写的项目目录，无法同步。');
      return;
    }

    final opened = portOverride == null ? await _openPort() : null;
    final port = portOverride ?? opened?.port;
    if (!context.mounted) {
      await opened?.close();
      return;
    }
    if (port == null) {
      _explain(context, '未连接配对电脑，或电脑不在线。');
      await opened?.close();
      return;
    }

    try {
      if (!context.mounted) return;
      final completed = await runDeviceSync(
        context,
        port: port,
        remoteRoot: deviceRoot,
        localRoot: _copyRoot(localFiles),
        cacheKey: '${project.deviceHostId}/${project.id}',
      );
      if (completed) {
        project
          ..filesPulled = true
          ..placeholder = false;
        store.touch(project);
      }
    } finally {
      await opened?.close();
    }
  }

  /// `files` 的上一级，也就是同步服务眼里的项目根。
  static String _copyRoot(String filesRoot) =>
      filesRoot.substring(0, filesRoot.length - '/files'.length);

  Future<_OpenedPort?> _openPort() async {
    if (!RemoteComputerPage.isSupported) return null;
    final RemoteStore store;
    try {
      store = await RemoteStore.open();
    } on Object {
      return null;
    }
    final controller = RemoteController(store: store);
    if (controller.pairing == null) {
      controller.dispose();
      return null;
    }
    controller.connect();
    return _OpenedPort(
      port: RemoteDeviceFilePort(controller),
      controller: controller,
    );
  }

  void _explain(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 借用的连接：同步结束就还回去，不留在页面上。
class _OpenedPort {
  _OpenedPort({required this.port, required this.controller});

  final DeviceFilePort port;
  final RemoteController controller;

  Future<void> close() async {
    controller.dispose();
  }
}
