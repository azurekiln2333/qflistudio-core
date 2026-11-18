import 'dart:async';

import 'package:flutter/material.dart';

import '../tools/tool_state_store.dart';
import '../widgets/tool_widgets.dart';
import '../widgets/tools_browser.dart';
import 'content_tools_pages.dart';
import 'offline_tool_pages.dart';

/// Metadata and a single action for one tool card.
class ToolDefinition {
  const ToolDefinition({
    required this.icon,
    required this.title,
    required this.description,
    this.builder,
    this.onTap,
  }) : assert((builder == null) != (onTap == null));

  final IconData icon;
  final String title;
  final String description;
  final WidgetBuilder? builder;
  final VoidCallback? onTap;
}

/// A product-owned group of cards, followed by the shared offline group.
class ToolSection {
  const ToolSection({
    required this.title,
    required this.icon,
    required this.tools,
  });

  final String title;
  final IconData icon;
  final List<ToolDefinition> tools;
}

/// Tools available offline to every product, in their display order.
final List<ToolDefinition> commonTools = List.unmodifiable([
  ToolDefinition(
    icon: Icons.abc,
    title: UnicodeToolPage.title,
    description: '码点、\\uXXXX、UTF-8 / UTF-16 字节',
    builder: (_) => const UnicodeToolPage(),
  ),
  ToolDefinition(
    icon: Icons.password_outlined,
    title: Base64ToolPage.title,
    description: '标准与 URL-safe 字母表编解码',
    builder: (_) => const Base64ToolPage(),
  ),
  ToolDefinition(
    icon: Icons.link,
    title: UrlToolPage.title,
    description: '百分号编解码：表单风格与组件风格',
    builder: (_) => const UrlToolPage(),
  ),
  ToolDefinition(
    icon: Icons.find_replace_outlined,
    title: RegexToolPage.title,
    description: '正则匹配、捕获分组与匹配位置',
    builder: (_) => const RegexToolPage(),
  ),
  ToolDefinition(
    icon: Icons.data_object,
    title: 'JSON 格式化',
    description: '格式化、校验与查看 JSON 结构',
    builder: (_) => const JsonToolPage(),
  ),
  ToolDefinition(
    icon: Icons.tag,
    title: HashToolPage.title,
    description: 'MD5 / SHA-1 / SHA-256 / SHA-512 摘要',
    builder: (_) => const HashToolPage(),
  ),
  ToolDefinition(
    icon: Icons.schedule,
    title: TimestampToolPage.title,
    description: '秒/毫秒时间戳 <-> 本地日期时间',
    builder: (_) => const TimestampToolPage(),
  ),
  ToolDefinition(
    icon: Icons.fingerprint,
    title: UuidToolPage.title,
    description: '随机 v4 与确定性 v3 / v5',
    builder: (_) => const UuidToolPage(),
  ),
  ToolDefinition(
    icon: Icons.palette_outlined,
    title: ColorToolPage.title,
    description: '#AARRGGBB / RGB / HSL 互转',
    builder: (_) => const ColorToolPage(),
  ),
]);

/// A single scroll body suitable for embedding in the shell's tools tab.
///
/// The body is the netrix-style browser ([ToolsBrowser]): a search field, a
/// category filter, a display-density switch, the product's own tool groups and
/// the shared offline group. Ported netrix tools are appended when the current
/// product is the main app; see [ToolsBrowser].
class ToolsGrid extends StatefulWidget {
  const ToolsGrid({
    super.key,
    this.sections = const [],
    this.onOpenTerminal,
    this.state,
  });

  final List<ToolSection> sections;
  final VoidCallback? onOpenTerminal;

  /// 显示密度、收藏和使用记录。null 时用 [ToolStateStore.instance]。
  final ToolStateStore? state;

  @override
  State<ToolsGrid> createState() => _ToolsGridState();
}

class _ToolsGridState extends State<ToolsGrid> {
  ToolStateStore get _state => widget.state ?? ToolStateStore.instance;

  @override
  void initState() {
    super.initState();
    // 首次打开工具页时读取一次本地状态；重复调用是空操作。
    // ignore: discarded_futures
    unawaited(_state.load());
  }

  @override
  Widget build(BuildContext context) {
    return ToolsBrowser(
      state: _state,
      sections: <ToolsBrowserSection>[
        for (final section in [
          if (widget.onOpenTerminal != null)
            ToolSection(
              title: '快捷入口',
              icon: Icons.widgets_outlined,
              tools: [
                ToolDefinition(
                  icon: Icons.terminal,
                  title: '终端',
                  description: '在本机沙盒中运行命令',
                  onTap: widget.onOpenTerminal!,
                ),
              ],
            ),
          ...widget.sections,
          ToolSection(
            title: '通用',
            icon: Icons.build_outlined,
            tools: commonTools,
          ),
        ])
          if (section.tools.isNotEmpty)
            ToolsBrowserSection(
              title: section.title,
              icon: section.icon,
              entries: [
                for (final tool in section.tools)
                  ToolsBrowserEntry(
                    id: 'builtin:${tool.title}',
                    icon: tool.icon,
                    title: tool.title,
                    subtitle: tool.description,
                    description: tool.description,
                    builder: tool.builder,
                    onTap: tool.onTap,
                  ),
              ],
            ),
      ],
    );
  }
}

/// Shared tool-card geometry for product-owned inline tools scroll views.
class ToolsGridSliver extends StatelessWidget {
  const ToolsGridSliver({super.key, required this.tools});

  final List<ToolDefinition> tools;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double extraLineHeight(TextStyle? style, double fallbackSize) {
      final size = style?.fontSize ?? fallbackSize;
      return (scaler.scale(size) - size).clamp(0.0, double.infinity) *
          (style?.height ?? 1.5);
    }

    // Each card has one title line and up to two description lines. Preserve
    // normal geometry and reserve the extra line height requested by the user.
    final extraTextHeight =
        extraLineHeight(textTheme.titleSmall, 14) +
        2 * extraLineHeight(textTheme.bodySmall, 12);
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final tool = tools[index];
        return ToolCard(
          icon: tool.icon,
          title: tool.title,
          description: tool.description,
          onTap:
              tool.onTap ??
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: tool.builder!)),
        );
      }, childCount: tools.length),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: ToolsTheme.cardMaxWidth,
        mainAxisExtent: ToolsTheme.cardHeight + extraTextHeight,
        crossAxisSpacing: ToolsTheme.cardSpacing,
        mainAxisSpacing: ToolsTheme.cardSpacing,
      ),
    );
  }
}
