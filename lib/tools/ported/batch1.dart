import '../ported_tool.dart';
import '../tool_audience.dart';
import 'catalog.dart';

/// 第 1 批：文本类工具（Pi C 负责）。
///
/// 移植规则：只列标识，定义来自 netrix 原清单。新增条目时把它加在末尾，
/// 不要重排别人的行。
///
/// 清单第 1 批共 6 个 TEXT 工具，其中 4 个与本项目现有工具功能重复
/// （`json`、`base64`、`url-codec`、`digest`）。按「重复就合并成一个」
/// 的规则，这 4 个不单独出现在工具页，能力并入现有工具，
/// 见 [mergedNetrixIds]。这里只列没有对应现有工具的两个：
///
/// - `hex`：Hex 编解码，现有工具里没有。
/// - `jwt`：JWT 查看器，现有工具里没有。
const List<String> portedBatch1Ids = <String>['hex', 'jwt'];

/// 第 1 批的工具条目。
///
/// 全部是移植来的工具，可见范围用 [ToolAudience.qfliStudioMainApp]：
/// 只在主程序显示。
List<PortedToolEntry> get portedBatch1 => [
  for (final id in portedBatch1Ids)
    PortedToolEntry(
      tool: netrixTool(id),
      audience: ToolAudience.qfliStudioMainApp,
      batch: 1,
    ),
];
