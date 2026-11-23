import 'package:flutter/material.dart';

import '../i18n/studio_localizations.dart';

/// 大屏工作台左侧图标导航的七个去处。
///
/// 一个枚举值对应侧栏的一种内容，切换时只替换侧栏与欢迎区，
/// 中间的编辑器与各列表状态由宿主保留。
enum WorkbenchActivity {
  projects,
  files,
  agents,
  tools,
  tutorial,
  settings,
  profile,
}

/// VS Code 式图标导航条。
///
/// 固定 52px 宽：不随文字缩放变宽，也不显示展开的文字标签，
/// 否则侧栏宽度会被导航条挤走。每个按钮是 44px 触控目标，
/// 语义标签与 tooltip 都来自本地化层，选中项用主题色高亮。
///
/// 高度不足时上半部分可滚动：底部设置与头像始终留在左下角。
class WorkbenchActivityRail extends StatelessWidget {
  const WorkbenchActivityRail({
    super.key,
    required this.selected,
    required this.onSelected,
    this.avatarImage,
    this.accountLabel,
  });

  /// 当前选中的去处。决定高亮项，也决定侧栏显示哪一块内容。
  final WorkbenchActivity selected;

  /// 用户点了某个图标。同一个值也会在重复点击时回调。
  final ValueChanged<WorkbenchActivity> onSelected;

  /// 头像图片；为空或加载失败时退回首字母或图标占位。
  final ImageProvider? avatarImage;

  /// 账号名，用于头像的语义标签与首字母回退。
  final String? accountLabel;

  /// 导航条宽度。导出给宿主排版与测试断言。
  static const double width = 52;

  /// 单个图标的触控目标边长。
  static const double touchTarget = 44;

  /// 顶部的三块主要去处。
  static const List<WorkbenchActivity> primary = <WorkbenchActivity>[
    WorkbenchActivity.projects,
    WorkbenchActivity.files,
    WorkbenchActivity.agents,
  ];

  /// 主去处下方的辅助入口。
  static const List<WorkbenchActivity> secondary = <WorkbenchActivity>[
    WorkbenchActivity.tools,
    WorkbenchActivity.tutorial,
  ];

  /// 单个图标的稳定标识。侧栏宿主与测试用它定位具体入口。
  static ValueKey<String> activityKey(WorkbenchActivity activity) =>
      ValueKey<String>('workbench-rail-${activity.name}');

  /// 底部头像的稳定标识。
  static const ValueKey<String> avatarKey = ValueKey<String>(
    'workbench-rail-avatar',
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = StudioLocalizations.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: <Widget>[
            Expanded(
              // 窗口很矮时可滚动，图标不会被裁掉一半。
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (final activity in primary)
                      _RailButton(
                        key: activityKey(activity),
                        activity: activity,
                        selected: activity == selected,
                        onPressed: onSelected,
                        label: _labelFor(activity, l),
                        icon: _iconFor(activity),
                      ),
                    const SizedBox(height: 8),
                    for (final activity in secondary)
                      _RailButton(
                        key: activityKey(activity),
                        activity: activity,
                        selected: activity == selected,
                        onPressed: onSelected,
                        label: _labelFor(activity, l),
                        icon: _iconFor(activity),
                      ),
                  ],
                ),
              ),
            ),
            // 底部固定在左下角：设置与账号。
            _RailButton(
              key: activityKey(WorkbenchActivity.settings),
              activity: WorkbenchActivity.settings,
              selected: selected == WorkbenchActivity.settings,
              onPressed: onSelected,
              label: _labelFor(WorkbenchActivity.settings, l),
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

  static IconData _iconFor(WorkbenchActivity activity) {
    switch (activity) {
      case WorkbenchActivity.projects:
        return Icons.folder_copy_outlined;
      case WorkbenchActivity.files:
        return Icons.description_outlined;
      case WorkbenchActivity.agents:
        return Icons.smart_toy_outlined;
      case WorkbenchActivity.tools:
        return Icons.handyman_outlined;
      case WorkbenchActivity.tutorial:
        return Icons.menu_book_outlined;
      case WorkbenchActivity.settings:
        return Icons.settings_outlined;
      case WorkbenchActivity.profile:
        return Icons.account_circle_outlined;
    }
  }

  /// 导航条的语义标签。
  ///
  /// 复用 [StudioLocalizations] 已有的条目；只有「文件」与「设置」在
  /// 内核里还没有对应 getter，此处就地按同一套三语文案取值。
  static String _labelFor(WorkbenchActivity activity, StudioLocalizations l) {
    switch (activity) {
      case WorkbenchActivity.projects:
        return l.allProjects;
      case WorkbenchActivity.files:
        return _filesLabel(l);
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

  static String _filesLabel(StudioLocalizations l) => l.isEnglish
      ? 'Files'
      : l.isTraditionalChinese
      ? '檔案'
      : '文件';

  static String _settingsLabel(StudioLocalizations l) => l.isEnglish
      ? 'Settings'
      : l.isTraditionalChinese
      ? '設定'
      : '设置';
}

/// 一个 44px 触控目标的图标按钮。
///
/// 用 [InkWell] 而不是 NavigationRailDestination：后者在展开时会加宽，
/// 与固定 52px 的宽度约束冲突。焦点圈交给主题的 `focusColor`。
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
    return Semantics(
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
              onTap: () => onPressed(activity),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // 选中指示：左侧一条主题色竖条，与 VS Code 一致。
                  if (selected)
                    Positioned(
                      left: 0,
                      top: 6,
                      bottom: 6,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    return Semantics(
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
              onTap: onPressed,
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
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

/// 空工作台的欢迎区。
///
/// 只说明当前没有打开的项目，并给一个打开项目的动作。
/// 不放统计数字或仪表盘：那些内容会与项目侧栏重复。
class WorkbenchWelcome extends StatelessWidget {
  const WorkbenchWelcome({super.key, required this.onOpenProject});

  /// 用户点了「打开项目」。由宿主决定弹选择器还是登记目录。
  final VoidCallback onOpenProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = StudioLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.space_dashboard_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l.noProjects,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l.isEnglish
                    ? 'Choose a folder or create a project to start editing.'
                    : l.isTraditionalChinese
                    ? '選擇資料夾或建立專案後即可開始編輯。'
                    : '选择文件夹或新建项目后即可开始编辑。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpenProject,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text(l.addExistingProject),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
