import 'package:flutter/material.dart';

import '../../shell/workbench_state.dart';

/// 「文件 ↔ 会话」切换按钮，落在侧边栏卡片的标题行右端。
///
/// 只画一个普通图标按钮。按钮指向「另一个」分段：当前在文件段就切到会话段，
/// 当前在会话段就切到文件段。视觉与相邻的标题行动作完全一致：20 图标、
/// 44×44 触摸目标、零内边距、标准视觉密度、收缩触摸目标。这里不画边框、
/// 不加选中底色、不显示文字。
class SidebarSectionSwitch extends StatelessWidget {
  const SidebarSectionSwitch({
    super.key,
    required this.section,
    required this.onChanged,
  });

  /// 当前所在的分段。
  final SidebarSection section;

  final ValueChanged<SidebarSection> onChanged;

  @override
  Widget build(BuildContext context) {
    // 按钮的目标是另一个分段。
    final target = section == SidebarSection.files
        ? SidebarSection.sessions
        : SidebarSection.files;
    final toSessions = target == SidebarSection.sessions;
    return IconButton(
      key: const ValueKey('editor-sidebar-section-switch'),
      tooltip: toSessions ? '切换到会话' : '切换到文件',
      icon: Icon(
        toSessions ? Icons.forum_outlined : Icons.folder_outlined,
        // 子键标记目标分段，测试按目标找按钮。
        key: ValueKey(
          toSessions
              ? 'editor-sidebar-section-sessions'
              : 'editor-sidebar-section-files',
        ),
      ),
      iconSize: 20,
      onPressed: () => onChanged(target),
      // 与相邻标题行动作同一套几何参数：明确的 44×44、零内边距、
      // 标准视觉密度，并把触摸目标收缩，避免被撑成 48。
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
