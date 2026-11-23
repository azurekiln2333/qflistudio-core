import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../git/git_backend.dart';
import '../models/project.dart';
import '../remote_control/remote_computer_page.dart';
import '../remote_control/state/remote_controller.dart';
import '../remote_control/state/remote_store.dart';
import '../services/app_paths.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../sync/sync_cache.dart';
import '../sync/sync_limits.dart';
import 'device_file_port.dart';
import 'device_git_pull.dart';
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

  /// 连上电脑前等待的最长时间。
  ///
  /// 打开页面到 relay 确认在线要两次往返，第一次请求往往在 `online` 之前
  /// 就发出去了。不等就的请求会直接报「电脑未连接」，用户看到的是失败，
  /// 而不是「过一会儿就好了」。
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 跑一次同步。
  ///
  /// 顺序按需求 7 与需求 8：电脑上的项目是能读的 git 仓库时就按 origin 拉取，
  /// 否则按文件清单逐个传输。失败只弹一次说明，不抛给界面。成功时把项目指向
  /// 拉下来的副本，并从占位项目改成已拉取。
  Future<bool> run(
    BuildContext context, {
    required Project project,
    required ProjectStore store,
    required SettingsStore settings,
    required AuthStore auth,
    DeviceFilePort? portOverride,
    int confirmBytes = kGitConfirmBytes,
  }) async {
    final deviceRoot = project.deviceRoot;
    if (deviceRoot == null || deviceRoot.trim().isEmpty) {
      _explain(context, '这个项目没有记下电脑上的路径，无法同步。');
      return false;
    }
    final localFiles = await const PlaceholderProjects().filesRoot(project);
    if (!context.mounted) return false;
    if (localFiles == null) {
      _explain(context, '未找到可写的项目目录，无法同步。');
      return false;
    }

    final opened = portOverride == null ? await _openPort() : null;
    final port = portOverride ?? opened?.port;
    if (!context.mounted) {
      await opened?.close();
      return false;
    }
    if (port == null) {
      _explain(context, '未连接配对电脑，或电脑不在线。');
      await opened?.close();
      return false;
    }

    try {
      if (!(await opened?.waitUntilOnline() ?? true)) {
        if (context.mounted) _explain(context, '电脑不在线，同步没有开始。');
        return false;
      }
      if (!context.mounted) return false;
      final filesRoot = _copyRoot(localFiles);
      final bool completed;
      try {
        final pulled = await _pullGit(
          context,
          port: port,
          deviceRoot: deviceRoot,
          target: filesRoot,
          confirmBytes: confirmBytes,
        );
        if (pulled) {
          completed = true;
        } else {
          final cache = await _cache();
          if (!context.mounted) return false;
          completed = await runDeviceSync(
            context,
            port: port,
            remoteRoot: deviceRoot,
            localRoot: filesRoot,
            cacheKey: '${project.deviceHostId}/${project.id}',
            cache: cache,
          );
        }
      } on Object catch (error) {
        // 请求超时、连接断开或电脑端拒绝：都给用户一句能看到的话，
        // 不留一个静默失败的按钮。
        if (context.mounted) _explain(context, '同步失败：$error');
        return false;
      }
      if (completed) {
        project
          ..filesPulled = true
          ..placeholder = false
          // 副本就是项目本身：拉完之后编辑器、文件树、保存位置都指向它。
          // 不指过去的话，用户确认了半天，项目目录里仍然只有 `.qfli`。
          ..path = localFiles;
        store.touch(project);
      }
      return completed;
    } finally {
      await opened?.close();
    }
  }

  /// 走 git 拉取。返回 true 表示文件已经就位，不必再传文件。
  ///
  /// 三步判断与需求 7 一致：电脑上不是可读仓库、没有 origin、或者用户取消
  /// 超过 200 MB 的确认时返回 false，交给文件同步。
  Future<bool> _pullGit(
    BuildContext context, {
    required DeviceFilePort port,
    required String deviceRoot,
    required String target,
    required int confirmBytes,
  }) async {
    final DeviceFilePort adapter = port;
    final info = await adapter.gitInfo(deviceRoot);
    const pull = DeviceGitPull();
    final decision = pull.decide(info, confirmBytes: confirmBytes);
    if (decision.outcome == GitPullOutcome.fallbackToFiles) return false;
    if (decision.outcome == GitPullOutcome.blocked) return false;

    var confirmed = false;
    if (decision.needsUserConfirm) {
      if (!context.mounted) return false;
      final bytes = decision.gitBytes ?? 0;
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('这个仓库比较大'),
          content: Text(
            '电脑上这个仓库的 .git 目录约 ${_formatBytes(bytes)}。'
            '这是占用量，不是下载量。'
            '克隆会占用手机空间与流量，继续吗？',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('改传文件'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续克隆'),
            ),
          ],
        ),
      );
      if (answer != true) return false;
      confirmed = true;
    }

    await Directory(target).create(recursive: true);
    final exists =
        await Directory(p.join(target, '.git')).exists() &&
        await File(p.join(target, '.git', 'HEAD')).exists();
    final report = await pull.pull(
      info,
      target: target,
      targetExists: exists,
      confirmed: confirmed,
      confirmBytes: confirmBytes,
    );
    if (report.outcome == GitPullOutcome.pulled) {
      // 抓取只更新对象与引用，工作区还要快进一次才能看到文件。
      final backend = GitBackendFactory.open(target);
      try {
        await backend.merge(
          'origin/${info.branch ?? 'HEAD'}',
          const GitIdentity(name: 'QFLI Studio', email: 'studio@qfli.local'),
        );
      } finally {
        await backend.dispose();
      }
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          report.outcome == GitPullOutcome.cloned
              ? '已从 origin 克隆'
              : '已从 origin 更新',
        ),
      ),
    );
    return true;
  }

  /// 缓存索引；取不到应用数据目录时返回 null，同步照常进行。
  Future<SyncCache?> _cache() async {
    final root = await AppPaths.deviceProjectsRoot(create: true);
    if (root == null) return null;
    final cache = SyncCache(indexFile: p.join(root, 'sync_index.json'));
    await cache.load();
    return cache;
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

  /// 与同步报告用同一套单位。
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
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

  /// 等到 relay 确认电脑在线，最多 [DeviceSyncLauncher.connectTimeout]。
  ///
  /// 只等服务端那一声 `agent_online`，不轮询会话或设备信息：同步自己会取。
  Future<bool> waitUntilOnline() async {
    if (controller.isOnline) return true;
    final done = Completer<bool>();
    void check() {
      if (done.isCompleted) return;
      if (controller.isOnline) {
        done.complete(true);
        return;
      }
      // 鉴权失败与断线重试都不会再恢复，早点告诉用户。
      final phase = controller.phase;
      if (phase == ConnectionPhase.authFailed ||
          phase == ConnectionPhase.unpaired) {
        done.complete(false);
      }
    }

    controller.addListener(check);
    final timer = Timer(DeviceSyncLauncher.connectTimeout, () {
      if (!done.isCompleted) done.complete(false);
    });
    try {
      check();
      return await done.future;
    } finally {
      timer.cancel();
      controller.removeListener(check);
    }
  }
}
