import 'package:flutter/material.dart';

import '../i18n/studio_localizations.dart';
import '../models/project.dart';
import 'shortcut_label.dart';
import 'workbench_theme.dart';
import 'large_screen_controller.dart';

/// Two retained pages in the shell's single Explorer sidebar slot.
class WorkbenchExplorer extends StatefulWidget {
  const WorkbenchExplorer({
    super.key,
    required this.controller,
    required this.projects,
    required this.files,
    required this.projectName,
  });

  final LargeScreenController controller;
  final Widget projects;
  final Widget files;
  final String? projectName;

  static const backKey = ValueKey('workbench-explorer-projects');
  static const duration = Duration(milliseconds: 200);

  @override
  State<WorkbenchExplorer> createState() => _WorkbenchExplorerState();
}

class _WorkbenchExplorerState extends State<WorkbenchExplorer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late double _destination;

  double get _target =>
      widget.projectName != null &&
          widget.controller.explorerPage == ExplorerPage.files
      ? 1
      : 0;

  @override
  void initState() {
    super.initState();
    _destination = _target;
    _motion = AnimationController(
      vsync: this,
      duration: WorkbenchExplorer.duration,
      value: _destination,
    );
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant WorkbenchExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _changed();
  }

  void _changed() {
    final target = _target;
    if (_destination == target) return;
    _destination = target;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _motion.value = target;
    } else {
      _motion.animateTo(
        target,
        duration: WorkbenchExplorer.duration,
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = StudioLocalizations.of(context);
    final projectsLabel = l.isEnglish
        ? 'Project list'
        : l.isTraditionalChinese
        ? '專案列表'
        : '项目列表';
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              _page(
                key: const ValueKey('workbench-explorer-project-page'),
                active: _target == 0,
                offset: -_motion.value * constraints.maxWidth,
                child: widget.projects,
              ),
              _page(
                key: const ValueKey('workbench-explorer-files-page'),
                active: _target == 1,
                offset: (1 - _motion.value) * constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: LargeScreenScope.isDesktop(context) ? 40 : 48,
                      child: Row(
                        children: [
                          IconButton(
                            key: WorkbenchExplorer.backKey,
                            tooltip: projectsLabel,
                            onPressed: widget.controller.showProjects,
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Text(
                              widget.projectName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: widget.files),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page({
    required Key key,
    required bool active,
    required double offset,
    required Widget child,
  }) => Offstage(
    key: key,
    offstage: !active && !_motion.isAnimating,
    child: Transform.translate(
      offset: Offset(offset, 0),
      child: TickerMode(
        enabled: active,
        child: ExcludeFocus(
          excluding: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: IgnorePointer(ignoring: !active, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Workbench-only project chrome. Phone Home continues to render its own UI.
class WorkbenchProjectsPanel extends StatelessWidget {
  const WorkbenchProjectsPanel({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onCreate,
    required this.body,
    required this.filterItems,
    required this.moreItems,
    required this.progress,
    this.onOpenFolder,
    this.onClone,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCreate;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onClone;
  final List<Widget> filterItems;
  final List<Widget> moreItems;
  final Widget body;
  final Widget progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = StudioLocalizations.of(context);
    final desktop = LargeScreenScope.isDesktop(context);
    final target = desktop ? 32.0 : 48.0;
    Widget button(
      IconData icon,
      String label,
      String keys,
      VoidCallback? action,
    ) => IconButton(
      tooltip: '$label (${shortcutLabel(keys)})',
      constraints: BoxConstraints.tightFor(width: target, height: target),
      padding: EdgeInsets.zero,
      iconSize: 18,
      onPressed: action,
      icon: Icon(icon),
    );
    Widget menu(IconData icon, String label, List<Widget> items) => MenuAnchor(
      menuChildren: items,
      builder: (context, controller, _) => IconButton(
        tooltip: label,
        constraints: BoxConstraints.tightFor(width: target, height: target),
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(icon),
      ),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('workbench-project-header'),
            height: desktop ? 40 : 48,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.isEnglish
                        ? 'Projects'
                        : l.isTraditionalChinese
                        ? '專案'
                        : '项目',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                button(
                  Icons.create_new_folder_outlined,
                  l.createProject,
                  'Ctrl+Shift+N',
                  onCreate,
                ),
                if (onOpenFolder != null)
                  button(
                    Icons.folder_open_outlined,
                    l.addExistingProject,
                    'Ctrl+O',
                    onOpenFolder,
                  ),
                if (onClone != null)
                  button(
                    Icons.cloud_download_outlined,
                    l.isEnglish ? 'Clone repository' : '克隆仓库',
                    'Ctrl+Shift+G',
                    onClone,
                  ),
                menu(Icons.more_vert, l.more, moreItems),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: desktop ? 36 : 48,
                    child: TextField(
                      key: const ValueKey('workbench-project-search'),
                      controller: searchController,
                      onChanged: onSearchChanged,
                      style: theme.textTheme.bodySmall,
                      decoration: InputDecoration(
                        hintText: l.searchProjectHint,
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHigh,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 32,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                menu(
                  Icons.filter_list,
                  l.isEnglish ? 'Filter projects' : '筛选项目',
                  filterItems,
                ),
              ],
            ),
          ),
          progress,
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// A flat, compact row with an independent menu for project operations.
class WorkbenchProjectRow extends StatelessWidget {
  const WorkbenchProjectRow({
    super.key,
    required this.project,
    required this.current,
    required this.opened,
    required this.onOpen,
    required this.menuItems,
  });

  final Project project;
  final bool current;
  final bool opened;
  final VoidCallback onOpen;
  final List<Widget> menuItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = LargeScreenScope.isDesktop(context);
    final foreground = current ? scheme.onSecondaryContainer : scheme.onSurface;
    return WorkbenchFocusOutline(
      child: Semantics(
        selected: current,
        child: SizedBox(
          key: ValueKey('workbench-project-${project.id}'),
          height: desktop ? 32 : 48,
          child: Material(
            color: current
                ? scheme.secondaryContainer
                : scheme.surfaceContainerLow,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Tooltip(
                    message: project.path,
                    child: InkWell(
                      onTap: onOpen,
                      mouseCursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Icon(
                              project.isCloud
                                  ? Icons.cloud_outlined
                                  : Icons.folder_outlined,
                              size: 18,
                              color: foreground,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: foreground,
                                ),
                              ),
                            ),
                            if (opened)
                              Icon(
                                current
                                    ? Icons.radio_button_checked
                                    : Icons.circle_outlined,
                                size: 12,
                                color: foreground,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                MenuAnchor(
                  menuChildren: menuItems,
                  builder: (context, controller, _) => IconButton(
                    tooltip: StudioLocalizations.of(context).more,
                    constraints: BoxConstraints.tightFor(
                      width: desktop ? 28 : 48,
                      height: desktop ? 32 : 48,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz, size: 16, color: foreground),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
