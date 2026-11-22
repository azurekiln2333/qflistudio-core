/// Trellis 任务面板的数据模型。
///
/// 面板只读：显示当前任务、阶段、产物链接与活跃任务。界面直接渲染本模型，
/// 打开产物走宿主提供的回调，模型自身不碰文件系统。
library;

import 'trellis_project.dart';

/// 面板里的一行任务。
class TrellisPanelTask {
  const TrellisPanelTask({required this.task, this.indent = 0});

  final TrellisTask task;

  /// 子任务的缩进层级。
  final int indent;
}

/// 任务面板快照。
class TrellisTaskPanel {
  const TrellisTaskPanel({
    required this.developer,
    required this.currentTask,
    required this.activeTasks,
    required this.myTasks,
    required this.specIndexes,
    required this.workflowPath,
  });

  /// `.trellis/.developer` 里的名字；没有时为空串。
  final String developer;

  /// 当前任务；未确定时为 null。
  final TrellisTask? currentTask;

  /// 活跃任务，父任务在前，子任务缩进跟随。
  final List<TrellisPanelTask> activeTasks;

  /// 分给当前开发者的活跃任务。
  final List<TrellisTask> myTasks;

  /// 有 `index.md` 的规范层。
  final List<TrellisSpecIndex> specIndexes;

  /// 工作流文件路径（相对项目根）。
  final String workflowPath;

  /// 没有任何可显示内容。
  bool get isEmpty =>
      currentTask == null && activeTasks.isEmpty && specIndexes.isEmpty;
}

/// 由项目状态生成面板。
///
/// 不是 Trellis 项目时 `TrellisProject.load` 已经返回 null，所以这里不返回
/// null：调用方拿到空面板即可渲染“没有任务”。
TrellisTaskPanel buildTrellisTaskPanel(TrellisProject project) {
  final active = project.activeTasks;
  final byName = {for (final task in active) task.dirName: task};
  final children = <String>{};
  for (final task in active) {
    for (final child in task.children) {
      if (byName.containsKey(child)) children.add(child);
    }
  }
  final rows = <TrellisPanelTask>[];
  // 任务文件的 `children` 是手写 JSON，可能互指；用 visited 集合挡住环。
  final seen = <String>{};
  void append(String name, int indent) {
    final task = byName[name];
    if (task == null) return;
    if (!seen.add(name)) return;
    rows.add(TrellisPanelTask(task: task, indent: indent));
    for (final child in task.children) {
      append(child, indent + 1);
    }
  }

  for (final task in active) {
    if (children.contains(task.dirName)) continue;
    append(task.dirName, 0);
  }
  // 父任务不在活跃集合里时，孤儿子任务照样显示。
  for (final task in active) {
    if (rows.any((row) => row.task.dirName == task.dirName)) continue;
    rows.add(TrellisPanelTask(task: task));
  }
  return TrellisTaskPanel(
    developer: project.developer,
    currentTask: project.currentTask,
    activeTasks: rows,
    myTasks: project.developer.isEmpty
        ? const []
        : project.activeTasksOf(project.developer),
    specIndexes: project.specIndexes,
    workflowPath: TrellisProject.workflowPath,
  );
}
