import 'package:flutter/material.dart';

import '../../shell/workbench_state.dart';

/// 中屏与窄屏的内容区。顶栏负责切换面板。
///
/// 编辑器列和 Agent 面板都常驻树上，只切换可见性，所以跨断点或来回切换都
/// 不会重建。见 design.md §11.2 第 3、7 点。
class AgentPaneSwitcher extends StatelessWidget {
  const AgentPaneSwitcher({
    super.key,
    required this.state,
    required this.editor,
    required this.agent,
  });

  final WorkbenchState state;

  /// 编辑器列（含标签栏、代码区、底部面板）。
  final Widget editor;

  /// Agent 面板。为 null 时该分段只显示等待占位。
  final Widget? agent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final showAgent = state.mainPane == MainPane.agent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
