import 'package:flutter/material.dart';

import '../../shell/workbench_state.dart';

/// 「文件 | 会话」切换控件，渲染在侧边栏卡片的标题行里。
///
/// 每个分段至少 44×44，颜色只用主题 token。标题栏要和项目名、新建、搜索、
/// 刷新共用一行，所以这里固定紧凑样式；文字只在确实放得下时显示，否则只留
/// 图标加 tooltip，避免把标签挤成两行。
class SidebarSectionSwitch extends StatelessWidget {
  const SidebarSectionSwitch({
    super.key,
    required this.section,
    required this.onChanged,
    this.showLabels = false,
  });

  final SidebarSection section;
  final ValueChanged<SidebarSection> onChanged;

  /// 是否显示文字。标题栏空间紧张时只显示图标。
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 自绘两段切换控件：Material 的 SegmentedButton 会强制留出 56 宽，
    // 280 宽的侧边栏放不下，所以直接画两个 44×44 的方框。
    return Container(
      key: const ValueKey('editor-sidebar-section-switch'),
      // 外框描边占 1px，容器 46 才能让里层触摸目标真的达到 44。
      height: 46,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context,
            section: SidebarSection.files,
            icon: Icons.folder_outlined,
            label: '文件',
            iconKey: const ValueKey('editor-sidebar-section-files'),
          ),
          _segment(
            context,
            section: SidebarSection.sessions,
            icon: Icons.forum_outlined,
            label: '会话',
            iconKey: const ValueKey('editor-sidebar-section-sessions'),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required SidebarSection section,
    required IconData icon,
    required String label,
    required Key iconKey,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = this.section == section;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: () => onChanged(section),
          child: Container(
            // 44×44 的触摸目标，不给标签留挤压空间。
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            color: selected ? scheme.secondaryContainer : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  key: iconKey,
                  size: 18,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                if (showLabels) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
