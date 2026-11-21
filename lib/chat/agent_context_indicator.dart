import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vibe_coding/agent_context_usage.dart';

/// Context estimates for loaded history, with explicit capacity provenance.
class AgentContextIndicator extends StatefulWidget {
  const AgentContextIndicator({
    super.key,
    required this.usage,
    this.modelLabel,
    this.reportedCapacity,
    this.manualCapacity,
    this.onCapacityChanged,
  });

  final AgentContextUsage usage;
  final String? modelLabel;
  final int? reportedCapacity;
  final int? manualCapacity;
  final ValueChanged<int?>? onCapacityChanged;

  @override
  State<AgentContextIndicator> createState() => _AgentContextIndicatorState();
}

class _AgentContextIndicatorState extends State<AgentContextIndicator> {
  final MenuController _menu = MenuController();
  final FocusNode _focus = FocusNode();
  Timer? _hoverTimer;
  Timer? _closeTimer;
  bool _pinned = false;

  int? get _capacity {
    final value = widget.manualCapacity ?? widget.reportedCapacity;
    return value != null && value > 0 ? value : null;
  }

  double? get _ratio {
    final capacity = _capacity;
    if (capacity == null || !widget.usage.historyLoaded) return null;
    return widget.usage.estimatedInputTokens / capacity;
  }

  void _enter({bool anchor = false}) {
    _closeTimer?.cancel();
    _hoverTimer?.cancel();
    if (_menu.isOpen) return;
    _hoverTimer = Timer(
      anchor ? const Duration(milliseconds: 300) : Duration.zero,
      () {
        if (mounted) _menu.open();
      },
    );
  }

  void _leave() {
    _hoverTimer?.cancel();
    _closeTimer?.cancel();
    if (_pinned) return;
    _closeTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && !_pinned) _menu.close();
    });
  }

  void _toggle() {
    _hoverTimer?.cancel();
    _closeTimer?.cancel();
    if (_menu.isOpen && _pinned) {
      _pinned = false;
      _menu.close();
    } else {
      _pinned = true;
      _menu.open();
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _closeTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _editCapacity() async {
    final original = widget;
    final input = TextEditingController(
      text:
          original.manualCapacity?.toString() ??
          original.reportedCapacity?.toString() ??
          '',
    );
    _menu.close();
    int? result;
    try {
      result = await showDialog<int>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) {
            final value = int.tryParse(input.text.trim());
            final valid = value != null && value > 0;
            return AlertDialog(
              title: const Text('上下文容量'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('填入模型的上下文上限，单位为 token。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: input,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '容量（token）'),
                    onChanged: (_) => refresh(() {}),
                    onSubmitted: (_) {
                      if (valid) Navigator.of(context).pop(value);
                    },
                  ),
                ],
              ),
              scrollable: true,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(0),
                  child: const Text('使用接口值'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: valid
                      ? () => Navigator.of(context).pop(value)
                      : null,
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      input.dispose();
    }
    if (!mounted || result == null) return;
    original.onCapacityChanged?.call(result == 0 ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final width = math.max(1.0, math.min(360.0, size.width - 32));
    final height = math.max(1.0, math.min(560.0, size.height - 48));
    final ratio = _ratio;
    final fill = ratio != null && ratio >= .9 ? scheme.error : scheme.primary;
    final center = !widget.usage.historyLoaded
        ? '…'
        : ratio == null
        ? '?'
        : '${(ratio * 100).round()}%';
    final label = widget.usage.historyLoaded
        ? '上下文容量：估算 ${_number(widget.usage.estimatedInputTokens)} token'
        : '上下文容量：完整历史将在发送时读取';
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      ),
      onClose: () {
        _pinned = false;
        _hoverTimer?.cancel();
        _closeTimer?.cancel();
      },
      menuChildren: [
        MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _leave(),
          child: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _details(context),
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => _enter(anchor: true),
        onExit: (_) => _leave(),
        child: Semantics(
          label: label,
          child: SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: const ValueKey('agent-context-capacity'),
              focusNode: _focus,
              padding: const EdgeInsets.all(6),
              onPressed: _toggle,
              icon: SizedBox.square(
                dimension: 30,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: ratio?.clamp(0.0, 1.0) ?? 0,
                      strokeWidth: 2.5,
                      backgroundColor: scheme.outlineVariant,
                      color: fill,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontSize: 9,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final theme = Theme.of(context);
    final usage = widget.usage;
    final capacity = _capacity;
    final ratio = _ratio;
    final denominator = capacity ?? math.max(1, usage.estimatedInputTokens);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('上下文容量', style: theme.textTheme.titleMedium),
        if (widget.modelLabel case final label?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 10),
        Text(
          usage.historyLoaded
              ? '估算 ${_number(usage.estimatedInputTokens)} token'
              : '完整历史将在发送时读取',
          style: theme.textTheme.titleSmall,
        ),
        Text(
          capacity == null
              ? '模型上限未提供'
              : '上限 ${_number(capacity)} token · '
                    '${widget.manualCapacity == null ? '接口值' : '手动设置'}',
          style: theme.textTheme.bodySmall,
        ),
        if (ratio != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            color: ratio >= .9 ? theme.colorScheme.error : null,
          ),
          if (ratio > 1) const Text('估算用量已超过设置的容量。'),
        ],
        const SizedBox(height: 12),
        for (final category in AgentContextCategory.values) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              Text(_categoryLabel(category), style: theme.textTheme.bodySmall),
              Text(
                usage.historyLoaded
                    ? '≈ ${_number(usage.estimatedBreakdown[category] ?? 0)} token'
                    : '待读取',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.historyLoaded
                ? ((usage.estimatedBreakdown[category] ?? 0) / denominator)
                      .clamp(0.0, 1.0)
                : 0,
            minHeight: 4,
          ),
          const SizedBox(height: 8),
        ],
        if (usage.lastReportedInputTokens case final input?)
          Text(
            '上轮接口输入：${_number(input)} token',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 6),
        Text(
          '分项按已装载内容估算，不含输入草稿和未读取附件。'
          '系统提示词含应用指令。项目规则含 Trellis 入口。'
          'MCP 当前未接入。'
          '${capacity == null ? '分项进度条表示当前占比。' : '分项进度条相对于容量上限。'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (widget.onCapacityChanged != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _editCapacity,
              child: const Text('设置模型容量'),
            ),
          ),
      ],
    );
  }

  static String _categoryLabel(AgentContextCategory category) =>
      switch (category) {
        AgentContextCategory.systemPrompt => '系统提示词',
        AgentContextCategory.projectRules => '项目规则',
        AgentContextCategory.skills => '技能',
        AgentContextCategory.messages => '消息',
        AgentContextCategory.tools => '工具定义与结果',
        AgentContextCategory.mcp => 'MCP',
        AgentContextCategory.other => '其他',
      };

  static String _number(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}
