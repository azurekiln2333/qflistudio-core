import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vibe_coding_controller.dart';
import 'vibe_coding_widgets.dart';

/// Editor bottom panel for Vibe Coding: one conversation that can inspect,
/// create and edit real project files and run real commands.
///
/// The panel renders controller state only. It never invents tool output and
/// never reports an action that the controller did not perform.
class VibeCodingPanel extends StatefulWidget {
  const VibeCodingPanel({
    super.key,
    required this.controller,
    required this.onSend,
    required this.loggedIn,
    this.projectName = '',
    this.onClose,
    this.onCollapseChanged,
    this.onRequestLogin,
    this.compact = false,
    this.onInputFocusChanged,
  });

  final VibeCodingController controller;

  /// Saves protected buffers first, then hands the prompt to the controller.
  /// Returns false when the prompt must stay in the input (save failed).
  final Future<bool> Function(String text) onSend;

  final bool loggedIn;
  final String projectName;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onCollapseChanged;
  final VoidCallback? onRequestLogin;

  /// Height-constrained mode: header only, no transcript.
  final bool compact;

  /// Reports prompt focus so the editor can keep the input mounted while the
  /// soft keyboard shrinks the panel, instead of collapsing it away mid-typing.
  final ValueChanged<bool>? onInputFocusChanged;

  @override
  State<VibeCodingPanel> createState() => _VibeCodingPanelState();
}

class _VibeCodingPanelState extends State<VibeCodingPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  bool _collapsed = false;
  bool _planExpanded = true;
  bool _sending = false;
  int _lastMessageCount = 0;
  String _lastTail = '';
  List<VibePlanItem> _lastPlan = const [];

  VibeCodingController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _lastMessageCount = _controller.messages.length;
    _inputFocus.addListener(_notifyInputFocus);
  }

  void _notifyInputFocus() =>
      widget.onInputFocusChanged?.call(_inputFocus.hasFocus);

  @override
  void didUpdateWidget(covariant VibeCodingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastMessageCount = widget.controller.messages.length;
      _lastTail = '';
    }
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_notifyInputFocus);
    _controller.removeListener(_onControllerChanged);
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final messages = _controller.messages;
    final tail = messages.isEmpty
        ? ''
        : '${messages.last.text}|${messages.last.tool?.status}|'
              '${messages.last.tool?.result}';
    final changed =
        messages.length != _lastMessageCount ||
        tail != _lastTail ||
        !_samePlan(_lastPlan, _controller.plan);
    _lastMessageCount = messages.length;
    _lastTail = tail;
    _lastPlan = _controller.plan;
    if (changed) _scrollToBottom();
    setState(() {});
  }

  static bool _samePlan(List<VibePlanItem> a, List<VibePlanItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].title != b[i].title ||
          a[i].status != b[i].status) {
        return false;
      }
    }
    return true;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || !_controller.canSend) return;
    setState(() => _sending = true);
    final sent = await widget.onSend(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) {
      _input.clear();
    }
  }

  bool get _running =>
      _controller.phase == VibePhase.running ||
      _controller.phase == VibePhase.cancelling;

  String get _headerLabel {
    return widget.projectName.isEmpty
        ? 'Vibe Coding'
        : 'Vibe Coding · ${widget.projectName}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Collapsed and compact both shrink the parent to the header height, so the
    // panel must not build the transcript in either case.
    if (widget.compact || _collapsed) {
      return _buildHeader(context, scheme, collapsedOnly: widget.compact);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, scheme),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        if (!widget.loggedIn)
          _buildGateCard(
            context,
            icon: Icons.lock_outline,
            message: 'Vibe Coding 需要登录后使用。登录后模型与工具由服务端转发。',
            actionLabel: '登录',
            onPressed: widget.onRequestLogin,
          )
        else ...[
          _buildAgentStrip(context),
          Expanded(child: _buildTranscript(context)),
          if (_controller.lastError != null && !_running)
            _buildErrorBar(context, _controller.lastError!),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          _buildInput(context, scheme),
        ],
      ],
    );
  }

  /// 计划进度与已用技能；展开时列出全部条目，窄屏不溢出。
  Widget _buildAgentStrip(BuildContext context) {
    final plan = _controller.plan;
    final skills = _controller.usedSkills;
    if (plan.isEmpty && skills.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VibeAgentChips(
            plan: plan,
            usedSkills: skills,
            planExpanded: _planExpanded,
            onTogglePlan: () => setState(() => _planExpanded = !_planExpanded),
          ),
          if (_planExpanded && plan.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: VibePlanList(plan: plan, dense: true),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme scheme, {
    bool collapsedOnly = false,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Icon(Icons.travel_explore, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _running
                  ? '$_headerLabel · ${_phaseLabel(_controller.phase)}'
                  : _headerLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (_running)
            IconButton(
              tooltip: '取消',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: () => _controller.cancel(),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
            ),
          if (!collapsedOnly)
            IconButton(
              tooltip: _collapsed ? '展开' : '收起',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() => _collapsed = !_collapsed);
                widget.onCollapseChanged?.call(_collapsed);
              },
              icon: Icon(
                _collapsed
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
              ),
            ),
          IconButton(
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(VibePhase phase) => switch (phase) {
    VibePhase.idle => '空闲',
    VibePhase.running => '执行中',
    VibePhase.cancelling => '正在取消',
    VibePhase.succeeded => '已完成',
    VibePhase.failed => '失败',
    VibePhase.cancelled => '已取消',
  };

  Widget _buildGateCard(
    BuildContext context, {
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onPressed, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBar(BuildContext context, String error) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: scheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscript(BuildContext context) {
    final messages = _controller.messages;
    if (messages.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '描述你想实现的功能。AI 会读取真实项目文件、创建或修改文件，'
            '并通过在线终端运行与调试。\n\n'
            '发送前会自动保存当前项目的未保存文件。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, i) => VibeMessageTile(message: messages[i]),
    );
  }

  Widget _buildInput(BuildContext context, ColorScheme scheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter, control: true):
                      _VibeSendIntent(),
                  SingleActivator(LogicalKeyboardKey.enter, meta: true):
                      _VibeSendIntent(),
                },
                child: Actions(
                  actions: {
                    _VibeSendIntent: CallbackAction<_VibeSendIntent>(
                      onInvoke: (_) {
                        _submit();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    enabled: !_running,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _running
                          ? '等待 AI 或点击取消…'
                          : '描述要实现的改动…（Ctrl+Enter 发送）',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_running)
              IconButton.filledTonal(
                tooltip: '取消',
                onPressed: _controller.canCancel
                    ? () => _controller.cancel()
                    : null,
                icon: const Icon(Icons.stop, size: 18),
              )
            else
              IconButton.filled(
                tooltip: '发送',
                onPressed: _sending || !_controller.canSend ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _VibeSendIntent extends Intent {
  const _VibeSendIntent();
}
