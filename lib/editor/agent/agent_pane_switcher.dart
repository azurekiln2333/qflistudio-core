import 'package:flutter/material.dart';

import '../../shell/workbench_state.dart';

/// 中屏与窄屏：顶部分段条，下面用 Offstage 保活两块。
///
/// 编辑器列和 Agent 面板都常驻树上，只切换可见性，所以跨断点或来回切换都
/// 不会重建。见 design.md §11.2 第 3、7 点。
class AgentPaneSwitcher extends StatelessWidget {
  const AgentPaneSwitcher({
    super.key,
    required this.state,
    required this.editor,
    required this.agent,
    this.onPaneSelected,
    this.showBar = true,
  });

  final WorkbenchState state;

  /// 编辑器列（含标签栏、代码区、底部面板）。
  final Widget editor;

  /// Agent 面板。为 null 时该分段只显示等待占位。
  final Widget? agent;

  /// 分段被切换后的回调。打开 Agent 分段时由外层开始解析运行时。
  final ValueChanged<MainPane>? onPaneSelected;

  /// 专注模式下分段条也隐藏。
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final showAgent = state.mainPane == MainPane.agent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBar) _buildBar(context),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _hidden(
                    hidden: showAgent,
                    child: KeyedSubtree(
                      key: const ValueKey('editor-pane-editor'),
                      child: editor,
                    ),
                  ),
                  _hidden(
                    hidden: !showAgent,
                    child: KeyedSubtree(
                      key: const ValueKey('editor-pane-agent'),
                      child: agent ?? const _AgentPending(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          SegmentedButton<MainPane>(
            key: const ValueKey('editor-main-pane-switch'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: MainPane.editor,
                label: Text('编辑器'),
                icon: Icon(Icons.code, size: 18),
              ),
              ButtonSegment(
                value: MainPane.agent,
                label: Text('Agent'),
                icon: Icon(Icons.smart_toy_outlined, size: 18),
              ),
            ],
            selected: {state.mainPane},
            onSelectionChanged: (selection) {
              final pane = selection.first;
              state.showMainPane(pane);
              onPaneSelected?.call(pane);
            },
          ),
        ],
      ),
    );
  }

  /// 隐藏但保持存活。
  Widget _hidden({required bool hidden, required Widget child}) => Offstage(
    offstage: hidden,
    child: TickerMode(
      enabled: !hidden,
      child: ExcludeFocus(
        excluding: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: IgnorePointer(ignoring: hidden, child: child),
        ),
      ),
    ),
  );
}

/// Agent 面板还没准备好时的占位。
class _AgentPending extends StatelessWidget {
  const _AgentPending();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
