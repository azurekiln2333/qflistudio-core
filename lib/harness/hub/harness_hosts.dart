// hub 的主机装配点。
//
// 本任务把界面和 hub 建在同一分支上，四类主机由并行任务提供：
//   * StudioAgentHost（内置 Agent，studio）
//   * LocalHarnessHost（本机 PTY 与日志，local）
//   * HerdrHost（Herdr 窗格，local）
//   * RemoteHarnessHost（已绑定电脑，remote）
// 它们分别位于 lib/harness/{local,herdr,remote,studio}/，本文件不直接引用，
// 这样 Pi-C 分支可以先合并而不带上别人的实现。集成时用
// [HarnessHosts.registerDefault] 注册一个工厂即可，编辑器页无需再改。

import 'package:flutter/foundation.dart';

import '../harness_host.dart';
import '../../services/app_paths.dart';
import 'harness_hub.dart';

/// 装配主机时能从编辑器页拿到的依赖。
///
/// 只放各家主机真正需要的东西：登录态、项目仓库、设置、当前项目根。
class HubHostContext {
  const HubHostContext({
    required this.auth,
    required this.projectStore,
    required this.settings,
    required this.projectRoot,
  });

  final Object auth;
  final Object projectStore;
  final Object settings;

  /// 当前打开项目的绝对路径，可作为新会话的默认工作目录。
  final String projectRoot;
}

/// 返回主机列表的工厂。返回顺序就是界面上的顺序。
///
/// 工厂每次调用都应当返回**新的**主机实例：主机由 hub 持有，编辑页销毁时
/// 会调用它们的 `dispose()`。要全应用共用的主机请由工厂自己缓存，并让它
/// 的 `dispose()` 幂等、不杀掉共享资源。
typedef HarnessHostsFactory =
    List<HarnessHost> Function(HubHostContext context);

/// 主机工厂注册表。
///
/// 没有注册时 hub 是空的：Agents 面板仍可打开，只显示「暂无可用主机」，
/// 内置 Agent 的原生会话列表照常工作。
abstract final class HarnessHosts {
  static HarnessHostsFactory? _default;
  static HarnessHostsFactory? _override;

  /// 最近一次 [build] 的异常；成功后清空。
  ///
  /// 主机装不上时界面上不能只留一个空白面板：编辑器页把它交给
  /// [HarnessHub.hostBuildError]，Agents 面板据此显示原因。
  static Object? lastBuildError;

  /// 集成方注册真实主机。后注册的覆盖先注册的。
  static void registerDefault(HarnessHostsFactory factory) {
    _default = factory;
    lastBuildError = null;
  }

  /// 测试和预览注入假主机，优先于 [registerDefault]。
  static void overrideForTesting(HarnessHostsFactory? factory) {
    _override = factory;
    lastBuildError = null;
  }

  /// 是否有任何工厂可用；界面据此决定要不要显示主机选择器。
  static bool get hasFactory => _override != null || _default != null;

  static List<HarnessHost> build(HubHostContext context) {
    final factory = _override ?? _default;
    if (factory == null) {
      lastBuildError = null;
      return const <HarnessHost>[];
    }
    try {
      final hosts = factory(context);
      lastBuildError = null;
      return hosts;
    } on Object catch (error, stack) {
      // 某台主机的构造失败不应该连带让整个 Agents 面板打不开，
      // 但原因要留下来，否则界面只能显示“什么都没有”。
      lastBuildError = error;
      assert(() {
        debugPrint('HarnessHosts.build failed: $error\n$stack');
        return true;
      }());
      return const <HarnessHost>[];
    }
  }
}

/// 编辑器页用的便捷构造：装配主机并交给 hub。
///
/// 手机端只保留已绑定电脑和内置 Agent，与 [HarnessHub.hostVisibleOnPlatform]
/// 一致；[desktop] 只在测试里覆盖平台判定。
HarnessHub harnessHubFor({
  required Object auth,
  required Object store,
  required Object settings,
  required String projectRoot,
  bool? desktop,
}) {
  final hosts = HarnessHosts.build(
    HubHostContext(
      auth: auth,
      projectStore: store,
      settings: settings,
      projectRoot: projectRoot,
    ),
  );
  return HarnessHub(
    hosts: hosts,
    desktop: desktop ?? AppPaths.isDesktop,
    hostBuildError: HarnessHosts.lastBuildError,
  );
}
