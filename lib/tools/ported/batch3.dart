import '../ported_tool.dart';
import '../tool_audience.dart';
import 'catalog.dart';

/// 第 3 批：剩余的 netrix 工具（Pi B 负责，教程合并之后开始）。
///
/// 移植规则见 `research/tools-port-contract.md`：只列标识，
/// 定义来自 netrix 原清单，新增条目加在末尾。
const List<String> portedBatch3Ids = <String>[];

/// 第 3 批的工具条目。
List<PortedToolEntry> get portedBatch3 => [
  for (final id in portedBatch3Ids)
    PortedToolEntry(
      tool: netrixTool(id),
      audience: ToolAudience.qfliStudioMainApp,
      batch: 3,
    ),
];
