import '../ported_tool.dart';
import '../tool_audience.dart';
import 'catalog.dart';

/// 第 2 批：地址与网络诊断类工具（Pi D 负责）。
///
/// 移植规则见 `research/tools-port-contract.md`：只列标识，
/// 定义来自 netrix 原清单，新增条目加在末尾。
const List<String> portedBatch2Ids = <String>[];

/// 第 2 批的工具条目。
List<PortedToolEntry> get portedBatch2 => [
  for (final id in portedBatch2Ids)
    PortedToolEntry(
      tool: netrixTool(id),
      audience: ToolAudience.qfliStudioMainApp,
      batch: 2,
    ),
];
