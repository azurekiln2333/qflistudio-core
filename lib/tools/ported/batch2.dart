import '../ported_tool.dart';
import '../tool_audience.dart';
import 'catalog.dart';

/// 第 2 批：地址与网络诊断类工具（Pi D 负责）。
///
/// 移植规则见 `research/tools-port-contract.md`：只列标识，
/// 定义来自 netrix 原清单，新增条目加在末尾。
///
/// 本批共 27 个标识，取自 `research/netrix-tools-inventory.md` 第 7.2 节：
/// 地址与子网 13 个（`subnet-calculator` … `ipv4-scope`）在前，
/// 网络诊断 14 个（`reachability` … `tls-inspector`）在后，顺序与 netrix
/// 的 `kTools` 一致。服务层的 `address_service` / `network_service`
/// 已经 1:1 在 `lib/tools/ported/services/` 下，这里不复制任何逻辑。
const List<String> portedBatch2Ids = <String>[
  // 地址与子网
  'subnet-calculator',
  'subnet-splitter',
  'range-to-cidr',
  'cidr-aggregate',
  'ip-converter',
  'wildcard-mask',
  'ip-inspector',
  'ip-membership',
  'ip-range',
  'prefix-mask',
  'mask-prefix',
  'ipv4-classifier',
  'ipv4-scope',
  // 网络诊断
  'reachability',
  'port-check',
  'port-scan',
  'host-scan',
  'hostname-lookup',
  'dns-record',
  'public-ip',
  'local-interfaces',
  'http-request',
  'websocket',
  'mac-normalizer',
  'dns-propagation',
  'rdap',
  'tls-inspector',
];

/// 第 2 批的工具条目。
List<PortedToolEntry> get portedBatch2 => [
  for (final id in portedBatch2Ids)
    PortedToolEntry(
      tool: netrixTool(id),
      audience: ToolAudience.qfliStudioMainApp,
      batch: 2,
    ),
];
