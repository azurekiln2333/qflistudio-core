import 'package:flutter/foundation.dart';

/// 侧边栏顶部分段。
enum SidebarSection { sessions, files }

/// 窄屏与中屏单区显示的内容。
enum MainPane { editor, agent }

/// 工作台界面状态。
///
/// 三种宽度共用这一个实例：布局只读它，不持有自己的副本。见 design.md §3。
class WorkbenchState extends ChangeNotifier {
  WorkbenchState({
    required this.projectId,
    this.sessionId,
    this.sidebarSection = SidebarSection.sessions,
    this.mainPane = MainPane.agent,
    this.agentPaneCollapsed = false,
  });

  /// 所属项目 id。
  String projectId;

  /// 当前打开的会话 id；未选会话时为 null。
  String? sessionId;

  /// 侧边栏分段。
  SidebarSection sidebarSection;

  /// 窄屏与中屏的单区内容。
  MainPane mainPane;

  /// 宽屏下对话流是否收起。
  bool agentPaneCollapsed;

  void selectSession(String? id) {
    if (sessionId == id) return;
    sessionId = id;
    notifyListeners();
  }

  void showSidebarSection(SidebarSection section) {
    if (sidebarSection == section) return;
    sidebarSection = section;
    notifyListeners();
  }

  void showMainPane(MainPane pane) {
    if (mainPane == pane) return;
    mainPane = pane;
    notifyListeners();
  }

  void setAgentPaneCollapsed(bool collapsed) {
    if (agentPaneCollapsed == collapsed) return;
    agentPaneCollapsed = collapsed;
    notifyListeners();
  }

  void toggleAgentPane() => setAgentPaneCollapsed(!agentPaneCollapsed);
}
