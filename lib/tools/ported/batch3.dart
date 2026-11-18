import '../ported_tool.dart';
import '../tool_audience.dart';
import 'catalog.dart';

/// 第 3 批：剩余的 netrix 工具（Pi B 负责，教程合并之后开始）。
///
/// 移植规则见 `research/tools-port-contract.md`：只列标识，
/// 定义来自 netrix 原清单，新增条目加在末尾。
///
/// 本批共 18 个标识，取自 `research/netrix-tools-inventory.md` 第 7.3 节。
/// 该节列出 19 个，其中 `timestamp-converter` 与本项目已有的「时间戳」
/// 工具重复，按「重复就合并」的规则并入现有工具，不再单独出现，
/// 见 [mergedNetrixIds]。其余 18 个按 netrix `kTools` 顺序登记。
const List<String> portedBatch3Ids = <String>[
  'url-parser',
  'http-status',
  'port-reference',
  'headers-parser',
  'curl-builder',
  'reverse-dns',
  'dns-name',
  'query-parser',
  'query-builder',
  'http-content-type',
  'http-cache-control',
  'http-date',
  'basic-auth',
  'port-range',
  'cookie-parser',
  'url-join',
  'http-method',
  'dns-label',
];

/// 第 3 批的工具条目。
List<PortedToolEntry> get portedBatch3 => [
  for (final id in portedBatch3Ids)
    PortedToolEntry(
      tool: netrixTool(id),
      audience: ToolAudience.qfliStudioMainApp,
      batch: 3,
    ),
];
