import 'package:flutter/material.dart';

import '../i18n/studio_localizations.dart';
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
                    Row(
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
