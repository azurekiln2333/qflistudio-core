import 'package:flutter/material.dart';

import '../i18n/studio_localizations.dart';
import '../models/project.dart';
import 'large_screen_controller.dart';
import 'shortcut_label.dart';
import 'workbench_theme.dart';

/// 大屏工作台左侧图标导航的六个去处。
///
/// 一个枚举值对应侧栏的一种内容，切换时只替换侧栏与欢迎区，
/// 中间的编辑器与各列表状态由宿主保留。
enum WorkbenchActivity {
  explorer,
  agents,
  tools,
  tutorial,
  settings,
  profile;

  // Source compatibility for callers migrating to the single Explorer entry.
  // These aliases are not extra destinations in values or the rail.
  // Use explorer and LargeScreenController.showProjects()/showFiles().
  static const projects = explorer;
  static const files = explorer;
}

/// MD3 navigation rail for the six workbench destinations.
///
/// The four primary destinations use NavigationRail. Settings and the account
/// avatar stay anchored at the bottom of the same 80dp rail.
class WorkbenchActivityRail extends StatelessWidget {
  const WorkbenchActivityRail({
    super.key,
    required this.selected,
    required this.onSelected,
    this.avatarImage,
    this.accountLabel,
  });

  final WorkbenchActivity selected;
  final ValueChanged<WorkbenchActivity> onSelected;
  final ImageProvider? avatarImage;
  final String? accountLabel;

  static const double width = 80;
  static const double touchTarget = 48;
  static const List<WorkbenchActivity> primary = <WorkbenchActivity>[
    WorkbenchActivity.explorer,
    WorkbenchActivity.agents,
  ];
  static const List<WorkbenchActivity> secondary = <WorkbenchActivity>[
    WorkbenchActivity.tools,
    WorkbenchActivity.tutorial,
  ];
  static const List<WorkbenchActivity> _railActivities = [
    WorkbenchActivity.explorer,
    WorkbenchActivity.agents,
    WorkbenchActivity.tools,
    WorkbenchActivity.tutorial,
  ];

  static ValueKey<String> activityKey(WorkbenchActivity activity) =>
      ValueKey<String>('workbench-rail-${activity.name}');

  static const ValueKey<String> avatarKey = ValueKey<String>(
    'workbench-rail-avatar',
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = StudioLocalizations.of(context);
    final index = _railActivities.indexOf(selected);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Expanded(
              child: NavigationRail(
                minWidth: width,
                minExtendedWidth: width,
                selectedIndex: index < 0 ? null : index,
                onDestinationSelected: (value) =>
                    onSelected(_railActivities[value]),
                labelType: NavigationRailLabelType.all,
                scrollable: true,
                useIndicator: true,
                indicatorColor: scheme.secondaryContainer,
                indicatorShape: const StadiumBorder(),
                selectedLabelTextStyle: Theme.of(context).textTheme.labelMedium,
                unselectedLabelTextStyle: Theme.of(
                  context,
                ).textTheme.labelMedium,
                groupAlignment: -0.85,
                destinations: [
                  for (final activity in _railActivities)
                    NavigationRailDestination(
                      icon: MouseRegion(
                        key: activityKey(activity),
                        cursor: SystemMouseCursors.click,
                        child: Tooltip(
                          message: _tooltipFor(activity, l),
                          child: Icon(_iconFor(activity), size: 24),
                        ),
                      ),
                      selectedIcon: MouseRegion(
                        key: activityKey(activity),
                        cursor: SystemMouseCursors.click,
                        child: Tooltip(
                          message: _tooltipFor(activity, l),
                          child: Icon(_iconFor(activity), size: 24),
                        ),
                      ),
                      label: SizedBox(
                        width: 72,
                        child: Text(
                          _labelFor(activity, l),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _RailButton(
              key: activityKey(WorkbenchActivity.settings),
              activity: WorkbenchActivity.settings,
              selected: selected == WorkbenchActivity.settings,
              onPressed: onSelected,
              label: _tooltipFor(WorkbenchActivity.settings, l),
              icon: _iconFor(WorkbenchActivity.settings),
            ),
            _AvatarButton(
              key: avatarKey,
              selected: selected == WorkbenchActivity.profile,
              onPressed: () => onSelected(WorkbenchActivity.profile),
              label: _labelFor(WorkbenchActivity.profile, l),
              accountLabel: accountLabel,
              avatarImage: avatarImage,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(WorkbenchActivity activity) => switch (activity) {
    WorkbenchActivity.explorer => Icons.folder_copy_outlined,
    WorkbenchActivity.agents => Icons.smart_toy_outlined,
    WorkbenchActivity.tools => Icons.handyman_outlined,
    WorkbenchActivity.tutorial => Icons.menu_book_outlined,
    WorkbenchActivity.settings => Icons.settings_outlined,
    WorkbenchActivity.profile => Icons.account_circle_outlined,
  };

  static String _labelFor(WorkbenchActivity activity, StudioLocalizations l) {
    switch (activity) {
      case WorkbenchActivity.explorer:
        return l.isEnglish
            ? 'Explorer'
            : l.isTraditionalChinese
            ? '資源管理器'
            : '资源管理器';
      case WorkbenchActivity.agents:
        return l.agentsTab;
      case WorkbenchActivity.tools:
        return l.tools;
      case WorkbenchActivity.tutorial:
        return l.tutorial;
      case WorkbenchActivity.settings:
        return _settingsLabel(l);
      case WorkbenchActivity.profile:
        return l.profile;
    }
  }

  static String _tooltipFor(WorkbenchActivity activity, StudioLocalizations l) {
    final keys = switch (activity) {
      WorkbenchActivity.explorer => 'Ctrl+Shift+E',
      WorkbenchActivity.agents => 'Ctrl+Shift+A',
      WorkbenchActivity.settings => 'Ctrl+,',
      _ => null,
    };
    final label = _labelFor(activity, l);
    return keys == null ? label : '$label (${shortcutLabel(keys)})';
  }

  static String _settingsLabel(StudioLocalizations l) => l.isEnglish
      ? 'Settings'
      : l.isTraditionalChinese
      ? '設定'
      : '设置';
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.activity,
    required this.selected,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final WorkbenchActivity activity;
  final bool selected;
  final ValueChanged<WorkbenchActivity> onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WorkbenchFocusOutline(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: label,
            child: SizedBox(
              width: WorkbenchActivityRail.width,
              height: WorkbenchActivityRail.touchTarget,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onPressed(activity),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? scheme.secondaryContainer : null,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        icon,
                        size: 24,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resizable IDE-style sidebar edge. Double-click restores the default width.
class WorkbenchSidebarDivider extends StatelessWidget {
  const WorkbenchSidebarDivider({
    super.key,
    required this.controller,
    this.touchLayout = false,
  });

  final LargeScreenController controller;
  final bool touchLayout;
  static const double desktopHitWidth = 6;
  static const double touchHitWidth = 48;

  static const ValueKey<String> dividerKey = ValueKey<String>(
    'workbench-sidebar-divider',
  );

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: dividerKey,
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => controller.setSidebarWidth(
        controller.sidebarWidth + details.delta.dx,
      ),
      onDoubleTap: controller.resetSidebarWidth,
      child: SizedBox(
        width: touchLayout ? touchHitWidth : desktopHitWidth,
        child: Center(
          child: Container(
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}

/// 底部头像按钮：选中即打开账号面板。
///
/// 图片缺失或解码失败时退回账号名首字；账号名也没有时退回图标。
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    super.key,
    required this.selected,
    required this.onPressed,
    required this.label,
    required this.accountLabel,
    required this.avatarImage,
  });

  final bool selected;
  final VoidCallback onPressed;
  final String label;
  final String? accountLabel;
  final ImageProvider? avatarImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = _initialOf(accountLabel);
    return WorkbenchFocusOutline(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Tooltip(
          message: label,
          child: SizedBox(
            width: WorkbenchActivityRail.width,
            height: WorkbenchActivityRail.touchTarget,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: onPressed,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                      color: scheme.surfaceContainerHigh,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _avatarChild(scheme, initial),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarChild(ColorScheme scheme, String? initial) {
    final image = avatarImage;
    if (image != null) {
      return Image(
        image: image,
        fit: BoxFit.cover,
        // 图片解码失败时不能让整条导航条报错。
        errorBuilder: (context, error, stack) => _fallback(scheme, initial),
      );
    }
    return _fallback(scheme, initial);
  }

  Widget _fallback(ColorScheme scheme, String? initial) {
    if (initial == null) {
      return Icon(
        Icons.person_outline,
        size: 16,
        color: scheme.onSurfaceVariant,
      );
    }
    return Center(
      child: Text(
        initial,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }

  static String? _initialOf(String? label) {
    final trimmed = label?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed.characters.first.toUpperCase();
  }
}

/// The empty workbench offers existing project commands and recent projects.
class WorkbenchWelcome extends StatelessWidget {
  const WorkbenchWelcome({
    super.key,
    required this.onOpenProject,
    this.onCreateProject,
    this.onCloneRepository,
    this.projects = const [],
    this.onOpenRecent,
  });

  final VoidCallback onOpenProject;
  final VoidCallback? onCreateProject;
  final VoidCallback? onCloneRepository;
  final List<Project> projects;
  final ValueChanged<Project>? onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = StudioLocalizations.of(context);
    final recent = [...projects]
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget action(
      String label,
      IconData icon,
      String keys,
      VoidCallback? onPressed,
    ) => Tooltip(
      message: '$label (${shortcutLabel(keys)})',
      child: TextButton(
        style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        onPressed: onPressed,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (MediaQuery.sizeOf(context).width >= 600) ...[
              const SizedBox(width: 8),
              Text(shortcutLabel(keys), style: theme.textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
    final start = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          l.isEnglish
              ? 'Start'
              : l.isTraditionalChinese
              ? '開始'
              : '开始',
        ),
        action(
          l.createProject,
          Icons.create_new_folder_outlined,
          'Ctrl+Shift+N',
          onCreateProject,
        ),
        action(
          l.addExistingProject,
          Icons.folder_open_outlined,
          'Ctrl+O',
          onOpenProject,
        ),
        if (onCloneRepository != null)
          action(
            l.isEnglish ? 'Clone repository' : '克隆仓库',
            Icons.cloud_download_outlined,
            'Ctrl+Shift+G',
            onCloneRepository,
          ),
      ],
    );
    final history = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          l.isEnglish
              ? 'Recent projects'
              : l.isTraditionalChinese
              ? '最近專案'
              : '最近项目',
        ),
        if (recent.isEmpty)
          Text(l.noProjects, style: theme.textTheme.bodySmall)
        else
          for (final project in recent.take(8))
            TextButton(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: onOpenRecent == null
                  ? null
                  : () => onOpenRecent!(project),
              child: Tooltip(
                message: project.path,
                child: Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: constraints.maxWidth >= 600
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: start),
                      const SizedBox(width: 48),
                      Expanded(child: history),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [start, const SizedBox(height: 32), history],
                  ),
          ),
        ),
      ),
    );
  }
}
