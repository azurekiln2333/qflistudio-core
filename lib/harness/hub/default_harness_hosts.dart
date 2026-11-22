// 集成装配：把四类主机接到 hub 上。
//
// Pi-C 的 `harness_hosts.dart` 只定义注册点和 `HubHostContext`，不引用任何具体
// 主机；四个实现分别由 Pi-A（本机）、Pi-B（Herdr、远程）、Pi-D（内置 Agent）
// 提供。本文件是唯一的接线处，编辑器页仍然只调 `harnessHubFor(...)`。
//
// 装配顺序就是界面顺序：内置 Agent → 本机 → Herdr → 已绑定电脑。

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../remote_control/remote_computer_page.dart';
import '../../remote_control/state/herdr_controller.dart';
import '../../remote_control/state/remote_controller.dart';
import '../../remote_control/state/remote_store.dart';
import '../harness_host.dart';
import '../herdr/herdr_host.dart';
import '../local/local_harness_host.dart';
import '../local/studio_mux_pty.dart';
import '../remote/remote_harness_host.dart';
import '../remote/remote_ports.dart';
import '../studio/studio_agent_host.dart';
import 'harness_hosts.dart';

/// 注册真实主机。应用启动时调用一次即可（后注册覆盖先注册）。
void registerDefaultHarnessHosts() {
  HarnessHosts.registerDefault(buildDefaultHarnessHosts);
}

/// 工厂本体：桌面端装配本机与 Herdr，所有平台装配内置 Agent。
///
/// 远程主机不在这里：它要先异步打开 [RemoteStore] 才能拿到已绑定的电脑，
/// 见 [openRemoteHarnessHost]。
List<HarnessHost> buildDefaultHarnessHosts(HubHostContext context) {
  final hosts = <HarnessHost>[];

  final runtime = context.runtime;
  final projectId = context.projectId;
  if (runtime != null && projectId != null) {
    // 一个主机只属于一个项目，一个 hub 一个实例：编辑器页销毁时随 hub 释放。
    hosts.add(
      StudioAgentHost(
        runtime: runtime,
        projectId: projectId,
        projectRoot: context.projectRoot,
        signedIn: context.signedIn,
      ),
    );
  }

  if (context.desktop) {
    hosts.add(LocalHarnessHost());
    // Herdr 只有在拿到真实 PTY 时才能 attach 窗格；拿不到时它自己退回快照
    // 终端（刷新 1.5 s 级），功能完整，所以工厂不需要按平台再分一次。
    // 工厂的启动器是惰性创建的，谁创建谁释放：交给主机在 dispose 时收尾。
    final pty = StudioMuxPtyFactory();
    hosts.add(HerdrHost(ptyFactory: pty, disposePtyFactory: pty.dispose));
  }

  return hosts;
}

/// 打开已绑定电脑的远程主机；没有配对、平台不支持或打不开存储时返回 null。
///
/// 返回的主机自己持有 [RemoteController] 与 [HerdrController]，`dispose()` 时
/// 一并释放。所以调用方把它交给 hub 之后不要再碰控制器：一个 hub 一个控制器，
/// 与“一个编辑器页一个 hub”一致。
Future<HarnessHost?> openRemoteHarnessHost() async {
  if (!RemoteComputerPage.isSupported) return null;
  final RemoteStore store;
  try {
    store = await RemoteStore.open();
  } on Object catch (error, stack) {
    // 只在调试构建里打：发布版留一条带堆栈的日志没有用处，反而泄路径。
    assert(() {
      debugPrint('openRemoteHarnessHost: 打不开远程存储 $error\n$stack');
      return true;
    }());
    return null;
  }
  final controller = RemoteController(store: store);
  if (controller.pairing == null) {
    // 没配对就不必连：一个空的主机会在界面上留下“未连接”的噪声。
    controller.dispose();
    return null;
  }
  controller.connect();
  return OwnedRemoteHarnessHost(controller: controller);
}

/// 自己管控制器的 [RemoteHarnessHost]。
///
/// hub 会在页面销毁时调用 `dispose()`，而 `RemoteHarnessHost` 只摘自己的监听
/// （端口由调用方提供）。控制器里的 WebSocket 必须有人关，否则每开一次编辑器
/// 页就多一条连接。
class OwnedRemoteHarnessHost implements HarnessHost {
  OwnedRemoteHarnessHost({required RemoteController controller})
    : _controller = controller {
    _herdr = HerdrController(controller);
    _host = RemoteHarnessHost(
      remote: RemoteControllerSessionAdapter(controller),
      herdr: HerdrControllerAdapter(controller: _herdr, remote: controller),
      codex: RemoteControllerCodexAdapter(controller),
    );
  }

  final RemoteController _controller;
  late final HerdrController _herdr;
  late final RemoteHarnessHost _host;
  bool _disposed = false;

  @override
  String get id => _host.id;

  @override
  String get label => _host.label;

  @override
  HarnessHostKind get kind => _host.kind;

  @override
  ValueListenable<HarnessHostState> get state => _host.state;

  @override
  Stream<List<HarnessSessionInfo>> watchSessions() => _host.watchSessions();

  @override
  Future<List<HarnessProviderInfo>> providers() => _host.providers();

  @override
  Future<HarnessSessionHandle> open(String sessionId) => _host.open(sessionId);

  @override
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request) =>
      _host.launch(request);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _host.dispose();
    _herdr.dispose();
    _controller.dispose();
  }
}
