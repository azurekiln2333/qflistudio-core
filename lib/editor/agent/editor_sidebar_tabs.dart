import 'package:flutter/material.dart';

import '../../shell/workbench_state.dart';

/// 侧边栏分段：「文件 | 会话」。
///
/// 分段固定在侧边栏顶部、文件树卡片之上，抽屉里用的是同一个组件，两处读
/// 同一个 [WorkbenchState]。见 design.md §11.1。
class EditorSidebarTabs extends StatelessWidget {
  const EditorSidebarTabs({
    super.key,
    required this.state,
    required this.files,
    this.sessions,
    this.sessionsLoading = false,
    this.showStrip = true,
    this.onSectionChanged,
  });

  final WorkbenchState state;

  /// 「文件」分段的内容，即原有的文件树。
  final Widget files;

  /// 「会话」分段的内容；为 null 时没有 agent，只显示文件树。
  final Widget? sessions;

  /// 会话列表还在准备中。
  final bool sessionsLoading;

  /// 是否在列表上方画分段条。
  final bool showStrip;

  /// 切分段时的回调。默认只改状态；编辑器页用它顺带激活运行时。
  final ValueChanged<SidebarSection>? onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final hasSessions = sessions != null || sessionsLoading;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final showSessions =
            hasSessions && state.sidebarSection == SidebarSection.sessions;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showStrip && hasSessions)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: SidebarSectionSwitch(
                  section: state.sidebarSection,
                  showLabels: true,
                  onChanged: onSectionChanged ?? state.showSidebarSection,
                ),
              ),
            Expanded(
              child: showSessions
                  ? (sessions ??
                        const Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ))
                  : files,
            ),
          ],
        );
      },
    );
  }
}

/// 「文件 | 会话」分段控件。
///
/// 每个分段至少 44×44，颜色只用主题 token。见 design.md §4 第 10 条。
class SidebarSectionSwitch extends StatelessWidget {
  const SidebarSectionSwitch({
    super.key,
    required this.section,
    required this.onChanged,
    this.showLabels = false,
  });

  final SidebarSection section;
  final ValueChanged<SidebarSection> onChanged;

  /// 是否显示文字。顶栏空间紧张时只显示图标，靠 tooltip 说明。
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<SidebarSection>(
      key: const ValueKey('editor-sidebar-section-switch'),
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(44, 44)),
      ),
      segments: [
        ButtonSegment(
          value: SidebarSection.files,
          label: showLabels ? const Text('文件') : null,
          tooltip: '文件',
          icon: const Icon(
            Icons.folder_outlined,
            key: ValueKey('editor-sidebar-section-files'),
            size: 18,
          ),
        ),
        ButtonSegment(
          value: SidebarSection.sessions,
          label: showLabels ? const Text('会话') : null,
          tooltip: '会话',
          icon: const Icon(
            Icons.forum_outlined,
            key: ValueKey('editor-sidebar-section-sessions'),
            size: 18,
          ),
        ),
      ],
      selected: {section},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
