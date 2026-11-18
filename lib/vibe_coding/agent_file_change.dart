import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Agent 对项目文件做了什么。
enum AgentFileChangeKind {
  /// 写入或新建。
  written,

  /// 删除。
  removed,
}

/// Agent 写入或删除项目文件后的一条事件。
///
/// 编辑器页监听它来刷新打开的标签页和文件树。事件只带路径，不带内容：
/// 刷新的一方自己按需读盘，避免把大文件正文塞进事件流。
@immutable
class AgentFileChange {
  const AgentFileChange({
    required this.projectRoot,
    required this.path,
    required this.kind,
  });

  /// 项目根的绝对路径。
  final String projectRoot;

  /// 相对项目根的路径，分隔符统一为 `/`。
  final String path;

  /// 这条事件对应的动作。
  final AgentFileChangeKind kind;

  /// 事件的绝对路径（已归一化）。
  String get absolutePath => p.normalize(p.join(projectRoot, path));

  /// 绝对路径 [absolute] 是否就是这条事件的文件，或落在被删除的目录里。
  ///
  /// 删除目录时下游传入的是目录路径，所以用前缀判断；写入只看完全相等。
  bool matches(String absolute) {
    final target = p.normalize(absolute);
    if (p.equals(target, absolutePath)) return true;
    if (kind != AgentFileChangeKind.removed) return false;
    return p.isWithin(absolutePath, target);
  }

  @override
  String toString() => 'AgentFileChange(${kind.name}, $path)';
}