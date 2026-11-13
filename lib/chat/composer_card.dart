import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/app_paths.dart';
import '../vibe_coding/vibe_agent_facade.dart';
import 'attachment_picker.dart';
import 'composer_state.dart';

/// 输入卡片。
///
/// 项目页和工作台共用这一个实现，见 design.md §4 第 1 条。上方是输入区，
/// 下方是工具行；发送按钮在卡片内部，运行中同一位置变成停止按钮。
class ComposerCard extends StatefulWidget {
  const ComposerCard({
    super.key,
    required this.state,
    required this.onSend,
    this.onStop,
    this.running = false,
    this.models = const [],
    this.skills = const [],
    this.onPickAttachments,
    this.enabled = true,
    this.hintText,
    this.modelsLoading = false,
    this.modelsError,
    this.onRetryModels,
    this.desktopKeyboard,
  });

  final ComposerState state;

  /// 返回 false 表示没有发出去（例如登录被取消），输入内容保留。
  final Future<bool> Function(String text, List<String> attachments) onSend;

  final VoidCallback? onStop;

  /// 运行中：发送按钮变成停止按钮。
  final bool running;

  final List<AgentModelOption> models;
  final List<AgentSkillRef> skills;

  /// 模型列表还在加载：选择器显示「模型…」和一个小转圈。
  final bool modelsLoading;

  /// 模型列表取不到的原因；为空表示没有出错。
  final String? modelsError;

  /// 重新拉取模型列表。
  final VoidCallback? onRetryModels;

  /// 覆盖「是否桌面键盘」的判断，只用于测试移动端与桌面端的回车行为。
  final bool? desktopKeyboard;

  /// 打开附件选择器；为 null 时不显示加号。
  final Future<List<String>?> Function(AttachmentSource source)?
  onPickAttachments;

  final bool enabled;
  final String? hintText;

  @override
  State<ComposerCard> createState() => _ComposerCardState();
}

class _ComposerCardState extends State<ComposerCard> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  int _selection = 0;

  ComposerState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _input.text = _state.text;
    _state.addListener(_onStateChanged);
    _syncDefaultSelection();
  }

  @override
  void didUpdateWidget(covariant ComposerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _input.text = widget.state.text;
    }
    if (!identical(oldWidget.models, widget.models)) _syncDefaultSelection();
  }

  /// 模型列表到达后选定一个具体模型。
  ///
  /// 没有选中模型时无从判断它支不支持推理强度，选择器就只能是猜的。因此这里
  /// 定下第一项（列表由服务端排序），推理强度跟着取该模型的第一档。
  void _syncDefaultSelection() {
    if (widget.models.isEmpty) return;
    final current = _state.modelId;
    if (current != null && widget.models.any((model) => model.id == current)) {
      return;
    }
    final first = widget.models.first;
    _state.modelId = first.id;
    _state.reasoningEffort = first.reasoningEfforts.isEmpty
        ? null
        : first.reasoningEfforts.first;
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_input.text != _state.text) {
      _input.text = _state.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    setState(() {});
  }

  void _onChanged(String value) {
    _state.text = value;
    _selection = 0;
  }

  /// 模型支持的推理强度；不支持时返回空，选择器整块隐藏（design.md §4 第 11 条）。
  List<String> get _efforts {
    final modelId = _state.modelId;
    if (modelId == null) return const [];
    for (final model in widget.models) {
      if (model.id == modelId) return model.reasoningEfforts;
    }
    return const [];
  }

  /// 输入 `/` 开头的片段时，列出匹配的 skill。
  List<AgentSkillRef> get _skillMatches {
    final text = _state.text;
    if (!text.startsWith('/')) return const [];
    if (text.contains(' ') || text.contains('\n')) return const [];
    final query = text.substring(1).toLowerCase();
    final matches = widget.skills
        .where((skill) => skill.name.toLowerCase().contains(query))
        .toList();
    if (matches.isEmpty) return const [];
    final index = _selection.clamp(0, matches.length - 1);
    _selection = index;
    return matches;
  }

  void _applySkill(AgentSkillRef skill) {
    _state.text = '/${skill.name} ';
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    if (!_state.canSend || _sending || widget.running || !widget.enabled) {
      return;
    }
    setState(() => _sending = true);
    final text = _state.text.trim();
    final attachments = _state.attachments;
    final sent = await widget.onSend(text, attachments);
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) _state.clearInput();
  }

  Future<void> _pick(AttachmentSource source) async {
    final picker = widget.onPickAttachments;
    if (picker == null) return;
    final paths = await picker(source);
    if (paths == null || paths.isEmpty) return;
    _state.attachAll(paths);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matches = _skillMatches;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (matches.isNotEmpty) _buildSkillMenu(context, matches),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInput(context),
                  if (_state.attachments.isNotEmpty) _buildAttachments(context),
                  const SizedBox(height: 8),
                  _buildToolRow(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: _sendShortcuts,
      child: Actions(
        actions: {
          _ComposerSendIntent: CallbackAction<_ComposerSendIntent>(
            onInvoke: (_) {
              final matches = _skillMatches;
              if (matches.isNotEmpty) {
                _applySkill(matches[_selection.clamp(0, matches.length - 1)]);
                return null;
              }
              _submit();
              return null;
            },
          ),
          _ComposerSkillNextIntent: CallbackAction<_ComposerSkillNextIntent>(
            onInvoke: (_) {
              final matches = _skillMatches;
              if (matches.isEmpty) return null;
              setState(() {
                _selection = (_selection + 1) % matches.length;
              });
              return null;
            },
          ),
        },
        child: TextField(
          key: const ValueKey('composer-input'),
          controller: _input,
          focusNode: _focus,
          minLines: 1,
          maxLines: 6,
          enabled: widget.enabled,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: theme.textTheme.bodyMedium,
          onChanged: _onChanged,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText:
                widget.hintText ?? (widget.running ? '正在执行，可点停止…' : '描述要改什么…'),
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  /// 桌面端 Enter 发送、Shift+Enter 换行；移动端回车换行，点按钮发送。
  Map<ShortcutActivator, Intent> get _sendShortcuts {
    if (!(widget.desktopKeyboard ?? AppPaths.isDesktop)) return const {};
    return const {
      SingleActivator(LogicalKeyboardKey.enter): _ComposerSendIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): _ComposerSendIntent(),
      SingleActivator(LogicalKeyboardKey.arrowDown): _ComposerSkillNextIntent(),
    };
  }

  /// 附件标签：项目内相对路径原样显示，项目外绝对路径只留最后两段。
  ///
  /// 绝对路径动辄三四十字，完整显示会把 chip 拉得很长，尾巴又被省略号吃掉，
  /// 反而看不见文件名。完整路径放进 tooltip。
  static String _attachmentLabel(String path) {
    final slashed = path.replaceAll('\\', '/');
    if (!p.isAbsolute(path)) return slashed;
    final parts = slashed.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 2) return slashed;
    return parts.sublist(parts.length - 2).join('/');
  }

  Widget _buildAttachments(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final path in _state.attachments)
            Tooltip(
              key: ValueKey('composer-attachment-$path'),
              message: path,
              child: InputChip(
                label: Text(
                  _attachmentLabel(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                onDeleted: () => _state.detach(path),
                deleteButtonTooltipMessage: '移除',
                deleteIcon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkillMenu(BuildContext context, List<AgentSkillRef> matches) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final skill = matches[index];
          return ListTile(
            key: ValueKey('composer-skill-${skill.name}'),
            dense: true,
            selected: index == _selection.clamp(0, matches.length - 1),
            leading: Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
            title: Text('/${skill.name}', style: theme.textTheme.labelMedium),
            subtitle: skill.description.isEmpty
                ? null
                : Text(
                    skill.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
            onTap: () => _applySkill(skill),
          );
        },
      ),
    );
  }

  Widget _buildToolRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final efforts = _efforts;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 窄卡片里只留图标，文字进 tooltip，避免工具行横向溢出。
        // 阈值来自 briefs/rework-pi-C.md 第 10 条，不是布局断点。
        final compact = width < _compactToolRowWidth;
        // 模型是用户最需要看到的那一项，比其余按钮多撑一段才收成图标。
        final compactModel = width < _compactModelWidth;
        return Row(
          children: [
            if (widget.onPickAttachments != null)
              _buildAddButton(context)
            else
              const SizedBox.shrink(),
            const SizedBox(width: 2),
            _buildPermissionButton(context, compact: compact),
            const SizedBox(width: 2),
            // 只有模型标签可以缩短：权限和推理强度是固定短语，模型名可能很长。
            Flexible(child: _buildModelButton(context, compact: compactModel)),
            if (efforts.isNotEmpty) ...[
              const SizedBox(width: 2),
              _buildEffortButton(context, efforts, compact: compact),
            ],
            const Spacer(),
            SizedBox(
              width: 48,
              height: 48,
              child: widget.running
                  ? IconButton.filledTonal(
                      key: const ValueKey('composer-stop'),
                      tooltip: '停止',
                      onPressed: widget.onStop,
                      icon: const Icon(Icons.stop, size: 20),
                    )
                  : IconButton.filled(
                      key: const ValueKey('composer-send'),
                      tooltip: '发送',
                      onPressed: _state.canSend && widget.enabled
                          ? _submit
                          : null,
                      icon: _sending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.arrow_upward, size: 20),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return PopupMenuButton<AttachmentSource>(
      key: const ValueKey('composer-plus'),
      tooltip: '添加文件',
      icon: const Icon(Icons.add, size: 20),
      constraints: const BoxConstraints(minWidth: 180),
      onSelected: _pick,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: AttachmentSource.project,
          height: 44,
          child: Text('项目文件'),
        ),
        PopupMenuItem(
          value: AttachmentSource.workspace,
          height: 44,
          child: Text('工作区文件'),
        ),
      ],
    );
  }

  String get _permissionLabel => switch (_state.permission) {
    AgentPermissionMode.readOnly => '只读',
    AgentPermissionMode.askEveryWrite => '每次询问',
    AgentPermissionMode.autoAcceptEdits => '自动接受',
  };

  Widget _buildPermissionButton(
    BuildContext context, {
    required bool compact,
  }) {
    return PopupMenuButton<AgentPermissionMode>(
      key: const ValueKey('composer-permission'),
      tooltip: '权限模式',
      onSelected: (mode) => _state.permission = mode,
      itemBuilder: (context) => [
        for (final mode in AgentPermissionMode.values)
          PopupMenuItem(
            value: mode,
            height: 56,
            child: _menuLine(
              context,
              title: switch (mode) {
                AgentPermissionMode.readOnly => '只读',
                AgentPermissionMode.askEveryWrite => '每次询问',
                AgentPermissionMode.autoAcceptEdits => '自动接受',
              },
              subtitle: switch (mode) {
                AgentPermissionMode.readOnly => '只读文件，不写入',
                AgentPermissionMode.askEveryWrite => '每次写入前确认',
                AgentPermissionMode.autoAcceptEdits => '直接写入，不再确认',
              },
            ),
          ),
      ],
      child: _chip(
        context,
        icon: switch (_state.permission) {
          AgentPermissionMode.readOnly => Icons.visibility_outlined,
          AgentPermissionMode.askEveryWrite => Icons.help_outline,
          AgentPermissionMode.autoAcceptEdits => Icons.bolt_outlined,
        },
        label: _permissionLabel,
        tooltip: '权限模式：$_permissionLabel',
        compact: compact,
      ),
    );
  }

  /// 模型选择始终显示（design.md §11.6）。
  ///
  /// 加载中显示「模型…」；列表为空或失败显示「默认模型」，点开说明原因并提供
  /// 「重试」。推理强度只在当前模型支持时出现。
  Widget _buildModelButton(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final models = widget.models;
    final selected = _state.modelId;
    final String label;
    if (widget.modelsLoading && models.isEmpty) {
      label = '模型…';
    } else if (selected == null ||
        !models.any((model) => model.id == selected)) {
      label = '默认模型';
    } else {
      label = _labelOf(selected);
    }
    return PopupMenuButton<Object>(
      key: const ValueKey('composer-model'),
      tooltip: '模型：$label',
      onSelected: (value) {
        if (value is _RetryModels) {
          widget.onRetryModels?.call();
          return;
        }
        if (value is String) _onModelSelected(value);
      },
      itemBuilder: (context) => _modelMenuItems(context),
      child: _chip(
        context,
        icon: Icons.memory,
        label: label,
        tooltip: '模型：$label',
        compact: compact,
        minWidth: 72,
        trailing: widget.modelsLoading && models.isEmpty
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : null,
      ),
    );
  }

  void _onModelSelected(String id) {
    _state.modelId = id;
    final efforts = _efforts;
    _state.reasoningEffort = efforts.isEmpty ? null : efforts.first;
    if (mounted) setState(() {});
  }

  List<PopupMenuEntry<Object>> _modelMenuItems(BuildContext context) {
    final models = widget.models;
    if (models.isEmpty) {
      final theme = Theme.of(context);
      final reason = widget.modelsLoading
          ? '模型列表还在加载，暂时使用默认模型。'
          : (widget.modelsError?.trim().isNotEmpty == true
                ? widget.modelsError!.trim()
                : '没有取到可选的模型列表，暂时使用默认模型。');
      return [
        PopupMenuItem<Object>(
          key: const ValueKey('composer-model-empty'),
          enabled: false,
          height: 56,
          child: _menuLine(context, title: '默认模型', subtitle: reason),
        ),
        if (widget.onRetryModels != null)
          PopupMenuItem<Object>(
            key: const ValueKey('composer-model-retry'),
            value: const _RetryModels(),
            height: 44,
            child: Text('重试', style: theme.textTheme.bodyMedium),
          ),
      ];
    }
    return [
      for (final model in models)
        PopupMenuItem<Object>(
          value: model.id,
          height: 44,
          child: Text(
            model.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }

  String _labelOf(String modelId) {
    for (final model in widget.models) {
      if (model.id == modelId) return model.label;
    }
    return modelId;
  }

  Widget _buildEffortButton(
    BuildContext context,
    List<String> efforts, {
    required bool compact,
  }) {
    final selected = _state.reasoningEffort;
    final label = selected ?? efforts.first;
    return PopupMenuButton<String>(
      key: const ValueKey('composer-reasoning'),
      tooltip: '推理强度',
      onSelected: (value) => _state.reasoningEffort = value,
      itemBuilder: (context) => [
        for (final effort in efforts)
          PopupMenuItem(
            value: effort,
            height: 44,
            child: Text(effort, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      child: _chip(
        context,
        icon: Icons.tune,
        label: label,
        tooltip: '推理强度：$label',
        compact: compact,
      ),
    );
  }

  /// 工具行的紧凑按钮：整块可点，高度守住 44；窄卡片下只留图标。
  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool compact,
    String? tooltip,
    Widget? trailing,
    double minWidth = 0,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Container(
      height: 44,
      constraints: BoxConstraints(minWidth: compact ? 44 : minWidth),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          if (!compact) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 5),
            trailing,
          ],
        ],
      ),
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip, child: content);
  }

  Widget _menuLine(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        Text(
          subtitle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ComposerSendIntent extends Intent {
  const _ComposerSendIntent();
}

class _ComposerSkillNextIntent extends Intent {
  const _ComposerSkillNextIntent();
}

/// 工具行只留图标的宽度。来自 briefs/rework-pi-C.md 第 10 条的「小于 360」。
///
/// 这不是布局断点（布局断点只在 `lib/layout/breakpoints.dart`），只是工具行自身
/// 在窄卡片里的收缩阈值。
const double _compactToolRowWidth = 360;

/// 模型选择收起成图标的宽度。比 [_compactToolRowWidth] 窄，因为「默认模型」
/// 这类文案必须让用户看见（briefs/rework-pi-C.md 第 7 条）。
const double _compactModelWidth = 320;

/// 模型菜单里的「重试」条目。用独立类型，避免和模型 id 的字符串撞上。
class _RetryModels {
  const _RetryModels();
}
