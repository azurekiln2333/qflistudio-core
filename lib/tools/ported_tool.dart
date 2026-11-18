import 'package:flutter/material.dart';

import 'ported/models.dart';
import 'ported/netrix_localizations.dart';
import 'ported/netrix_tool_page.dart';
import 'tool_audience.dart';
import 'tool_state_store.dart';

/// 从 netrix 移植来的一个工具。
///
/// 与 netrix 的 `ToolDefinition` 字段一一对应：标识、中英文名、说明、分类、
/// 图标、输入字段和执行函数。字段的判空、端口的范围检查等全部复用 netrix
/// 的原实现（`models.dart`），移植过来的工具与 netrix 行为一致。
///
/// 批次注册文件（[portedBatch1] 等）负责产出条目。总注册表见
/// `ported_tools.dart`，页面的可见范围由 [audience] 决定。
@immutable
class PortedToolEntry {
  const PortedToolEntry({
    required this.tool,
    required this.audience,
    this.batch = 1,
  }) : assert(batch >= 1 && batch <= 3);

  /// netrix 原样搬来的定义，包含显示文字和执行函数。
  final ToolDefinition tool;

  /// 可见范围。移植来的工具默认用 [ToolAudience.qfliStudioMainApp]。
  final ToolAudience audience;

  /// 归属批次：1 = Pi C，2 = Pi D，3 = Pi B。只用于测试和排查。
  final int batch;
}

/// 工具页调用子条目时需要的运行环境。
///
/// 页面负责创建并释放一次，批次注册文件只处理自己的状态，不碰页面。
class PortedToolHost {
  const PortedToolHost({required this.state, required this.isMainApp});

  /// 显示密度、收藏和使用记录。
  final ToolStateStore state;

  /// 当前产品是否为主程序，决定移植工具是否显示。
  final bool isMainApp;
}

/// 让每个条目自己决定按键时做什么。
///
/// 批次文件只返回 [PortedToolEntry]，路由规则集中在这里，
/// 三批共用同一个工具详情页（[NetrixToolPage]）。
typedef PortedToolLauncher =
    Future<void> Function(BuildContext context, PortedToolEntry entry);

/// 默认的打开方式：压入 netrix 原样的详情页。
Future<void> openPortedTool(
  BuildContext context,
  PortedToolEntry entry,
  ToolStateStore state,
) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NetrixToolPage(tool: entry.tool, store: state)));
}

/// 分类和标题的多语言取值。
///
/// 分类键来自 netrix 的 `ToolCategory.key`；本项目的多语言层是
/// [StudioLocalizations]，netrix 的分类只在它自己的目录里，所以这里用
/// netrix 目录兜底，缺失时回落到宿主语言。
String portedCategoryLabel(BuildContext context, ToolCategory category) {
  final netrix = NetrixLocalizations.of(context);
  final localized = netrix.category(category.key);
  if (localized != category.key) return localized;
  return category.key;
}
