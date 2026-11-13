import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/project.dart';
import '../../services/studio_profile.dart';
import '../../shell/agent_runtime_factory.dart';
import '../../shell/workbench_state.dart';
import '../../store/auth_store.dart';
import '../../store/project_store.dart';
import '../../store/settings_store.dart';
import '../../vibe_coding/vibe_agent_facade.dart';

/// 编辑器页里的 agent 宿主。
///
/// 只持有界面状态 [WorkbenchState]，运行时按需解析：首帧不创建，第一次需要
/// agent 界面时才解析。见 design.md §11.2 第 6 点。
class EditorAgentHost extends ChangeNotifier {
  EditorAgentHost({
    required this.project,
    required this.auth,
    required this.store,
    required this.settings,
    AgentRuntime? runtime,
    WorkbenchState? state,
  }) : _runtime = runtime,
       _ownsState = state == null,
       state =
           state ??
           WorkbenchState(
             projectId: project.id,
             // 打开项目是为了写代码，默认停在编辑器分段与文件树。
             mainPane: MainPane.editor,
             sidebarSection: SidebarSection.files,
             // 宽屏默认收起对话流：首帧不解析运行时进行 agent 相关的工作。
             agentPaneCollapsed: true,
           ) {
    this.state.addListener(notifyListeners);
  }

  final Project project;
  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;

  /// 三种宽度共用的界面状态。
  final WorkbenchState state;

  final bool _ownsState;

  AgentRuntime? _runtime;
  Object? _error;
  bool _activated = false;
  bool _resolving = false;
  bool _disposed = false;

  /// 实际解析应用级运行时的次数。测试用它验证懒创建。
  @visibleForTesting
  static int runtimeResolutions = 0;

  /// 清零计数，测试之间互不影响。
  @visibleForTesting
  static void resetRuntimeResolutions() => runtimeResolutions = 0;

  /// 当前产品是否提供 agent 功能。离线产品没有。
  ///
  /// 门控条件与旧的 AI 菜单项相同。
  static bool get supported => StudioProfile.current?.offlineOnly != true;

  /// 已解析的运行时；未展开过 Agent 面板时为 null。
  AgentRuntime? get runtime => _runtime;

  /// 解析运行时时的错误，供界面提示与重试。
  Object? get error => _error;

  /// 用户是否要求过 agent 界面。为 true 后不再重复解析。
  bool get activated => _activated;

  /// 标记需要 agent 界面，并开始解析运行时。
  ///
  /// 只解析一次；之后重复调用没有副作用。
  void activate() {
    if (_disposed) return;
    if (!_activated) {
      _activated = true;
      notifyListeners();
    }
    if (_runtime != null || _resolving) return;
    unawaited(_resolve());
  }

  /// 选中的会话；同时清掉后台未读标记。
  void selectSession(String? id) {
    state.selectSession(id);
    final runtime = _runtime;
    if (runtime != null && id != null) runtime.markSeen(id);
  }

  Future<void> _resolve() async {
    _resolving = true;
    runtimeResolutions++;
    try {
      final resolved = await studioAgentRuntime(
        auth: auth,
        store: store,
        settings: settings,
      );
      if (_disposed) return;
      _runtime = resolved;
      _error = null;
    } on Object catch (error) {
      if (_disposed) return;
      _error = error;
    } finally {
      _resolving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(notifyListeners);
    if (_ownsState) state.dispose();
    super.dispose();
  }
}
