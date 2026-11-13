/// 工作台断点。
///
/// 新代码只能从这里取断点数值，不得在别处另写。见 design.md §3。
abstract final class Breakpoints {
  /// 侧边栏由抽屉改为常驻的最小宽度。
  static const double sidebarPersistent = 720;

  /// 主体由单区改为「编辑器 + 对话流」并排的最小宽度。
  static const double threePane = 1100;

  /// 侧边栏常驻时的宽度。
  static const double sidebarWidth = 280;

  /// 宽屏下对话流栏的宽度。
  static const double agentPaneWidth = 360;
}

/// 工作台的三种宽度形态。
enum WorkbenchLayout { narrow, medium, wide }

/// 按可用宽度判定形态。布局只读此结果，不另外判断宽度。
WorkbenchLayout layoutOf(double width) {
  if (width < Breakpoints.sidebarPersistent) return WorkbenchLayout.narrow;
  if (width < Breakpoints.threePane) return WorkbenchLayout.medium;
  return WorkbenchLayout.wide;
}
