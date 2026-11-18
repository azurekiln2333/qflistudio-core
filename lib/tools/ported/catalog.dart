import 'models.dart';
import 'netrix_registry.dart';

/// netrix 全部工具，按标识索引。
///
/// [kTools] 是从 netrix 原样搬来的完整清单（52 个工具，含执行函数）。
/// 批次注册文件只按标识挑选自己负责的那部分，不复制定义，
/// 这样三批之间不会有重复代码，也不会互相改文件。
final Map<String, ToolDefinition> netrixToolsById = <String, ToolDefinition>{
  for (final tool in kTools) tool.id: tool,
};

/// netrix 清单里的全部工具标识，顺序与 [kTools] 一致。
List<String> get netrixToolIds => <String>[for (final tool in kTools) tool.id];

/// 按标识取一个工具。标识不存在时抛错，因为那只可能是拼写错误。
ToolDefinition netrixTool(String id) {
  final tool = netrixToolsById[id];
  if (tool == null) {
    throw ArgumentError.value(id, 'id', 'netrix 清单里没有这个工具');
  }
  return tool;
}
