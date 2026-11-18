import 'ported/batch1.dart';
import 'ported/batch2.dart';
import 'ported/batch3.dart';
import 'ported/catalog.dart';
import 'ported/models.dart';
import 'ported_tool.dart';
import 'tool_audience.dart';

/// 三个批次登记的全部移植工具，顺序为批次 1、2、3，批内保持清单顺序。
///
/// 批次之间没有依赖：每个批次只写自己的 `lib/tools/ported/batchN.dart`，
/// 总注册表在这里拼接。
List<PortedToolEntry> get allPortedTools => <PortedToolEntry>[
  ...portedBatch1,
  ...portedBatch2,
  ...portedBatch3,
];

/// 按可见范围过滤后的移植工具。子项目下为空。
List<PortedToolEntry> get visiblePortedTools =>
    portedToolsInScope(isMainApp: ToolAudienceScope.isMainApp);

/// 按给定范围过滤后的移植工具。
///
/// 工具页把它读到的 `isMainApp` 传进来（测试可以覆盖），这样页面的判定与
/// [visiblePortedTools] 用的是同一套规则。
List<PortedToolEntry> portedToolsInScope({required bool isMainApp}) =>
    ToolAudienceScope.filter(
      allPortedTools,
      (entry) => entry.audience,
      isMainApp: isMainApp,
    );

/// 移植工具当前的分类顺序，取自 netrix 的分类枚举顺序。
List<ToolCategory> get portedCategoriesOrder => ToolCategory.values;

/// 某个分类下、当前可见的移植工具。
List<PortedToolEntry> visiblePortedToolsInCategory(ToolCategory category) => [
  for (final entry in visiblePortedTools)
    if (entry.tool.category == category) entry,
];

/// 清单里已经被某个批次登记的标识。
///
/// 被合并进现有工具的重复项不计入（见 `research/tools-duplicates.md`）。
Set<String> get claimedNetrixIds => <String>{
  for (final e in allPortedTools) e.tool.id,
};

/// 清单里还没被任何批次认领、也没有合并进现有工具的标识。
///
/// 框架完成后按契约分配：Pi C 拿 `batch1`，Pi D 拿 `batch2`，
/// Pi B 拿 `batch3`。这个集合为空时表示 52 个工具全部有归属。
List<String> get unclaimedNetrixIds => <String>[
  for (final id in netrixToolIds)
    if (!claimedNetrixIds.contains(id) && !mergedNetrixIds.contains(id)) id,
];

/// 已经被合并进现有工具的 netrix 标识。
///
/// 这些工具不再单独出现在工具页：功能并入同名或同用途的现有工具，
/// 并沿用现有工具的可见范围。明细见 `research/tools-duplicates.md`。
///
/// 第 1 批的 4 个 TEXT 重复项与处理结果：
///
/// | netrix 标识 | 并入的现有工具 | 并集里的 netrix 能力 |
/// |---|---|---|
/// | `json` | JSON 格式化（`JsonToolPage`） | 缩进文本输出，由「格式化 JSON」提供 |
/// | `base64` | Base64（`Base64ToolPage`） | `encode` / `decode` 两个方向，由「编码 / 解码」按钮提供 |
/// | `url-codec` | URL 编解码（`UrlToolPage`） | 组件风格百分号编码（空格转 `%20`），新增两行结果 |
/// | `digest` | 哈希摘要（`HashToolPage`） | SHA-512，新增一行结果 |
const Set<String> mergedNetrixIds = <String>{
  'json',
  'base64',
  'url-codec',
  'digest',
};
