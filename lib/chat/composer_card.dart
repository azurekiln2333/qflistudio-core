import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/app_paths.dart';
import '../vibe_coding/vibe_agent_facade.dart';
import 'agent_context_indicator.dart';
import 'attachment_picker.dart';
import 'composer_state.dart';

/// 输入卡片。
///
/// 项目页和工作台共用这一定义。上方是输入区，
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
    this.contextUsage,
  });

  final ComposerState state;

  /// 返回 false 表示没有发出去（例如登录被取消），输入内容保留。
  final Future<bool> Function(String text, List<String> attachments) onSend;

  final VoidCallback? onStop;

  /// 运行中：发送按钮变成停止按钮。
  final bool running;

  final List<AgentModelOption> models;
  final List<AgentSkillRef> skills;
  final AgentContextUsage? contextUsage;

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
      // 换会话后新的状态可能还没轮到模型列表：按当前列表补一次，否则卡片退回
      //「默认模型」并丢掉推理强度（D1、D2）。
      _syncDefaultSelection();
    }
    if (!identical(oldWidget.models, widget.models)) _syncDefaultSelection();
  }

  /// 模型列表到达或换会话后，保证选中一个具体模型。
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

  /// 模型支持的推理强度；不支持时返回空，选择器整块隐藏。
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
    // 记下发起这次发送的状态：await 期间可能已经换了会话。
    final composer = _state;
    final text = composer.text.trim();
    final attachments = composer.attachments;
    setState(() => _sending = true);
    final sent = await widget.onSend(text, attachments);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!sent) return;
    // 已经换了会话：新会话的草稿不能动。
    if (!identical(composer, _state)) return;
    // 只有输入仍是刚发出去那一份时才清空，不覆盖用户新打的字。
    if (composer.text.trim() != text) return;
    if (!listEquals(composer.attachments, attachments)) return;
    composer.clearInput();
  }

  Future<void> _pick(AttachmentSource source) async {
    final picker = widget.onPickAttachments;
    if (picker == null) return;
    // 选择器关闭前可能换了会话，回到时只能加到原来那个。
    final composer = _state;
    final paths = await picker(source);
    if (paths == null || paths.isEmpty) return;
    if (!mounted) return;
    if (!identical(composer, _state)) return;
    composer.attachAll(paths);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matches = _skillMatches;
    return SafeArea(
      top: false,
      child: Padding(
        // 左右同宽的内边距：输入区和工具行都对齐到这条线，右侧不再比左侧窄。
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
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
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildInput(context)),
                      if (widget.contextUsage case final usage?) ...[
                        const SizedBox(width: 6),
                        _buildContextIndicator(usage),
                      ],
                    ],
                  ),
                  if (_state.attachments.isNotEmpty) _buildAttachments(context),
                  const SizedBox(height: 4),
                  _buildToolRow(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextIndicator(AgentContextUsage usage) {
    final composer = _state;
    final modelId = composer.modelId;
    AgentModelOption? selected;
    for (final model in widget.models) {
      if (model.id == modelId) {
        selected = model;
        break;
      }
    }
    return AgentContextIndicator(
      key: ObjectKey(composer),
      usage: usage,
      modelLabel: selected?.label ?? modelId,
      reportedCapacity: selected?.contextWindowTokens,
      manualCapacity: composer.contextWindowFor(modelId),
      onCapacityChanged: (value) =>
          composer.setContextWindowFor(modelId, value),
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
    // Restored sessions may contain paths created on another platform.
    if (!p.posix.isAbsolute(path) && !p.windows.isAbsolute(path)) {
      return slashed;
    }
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

  /// 工具行：左侧附件，中间选择器成组，右侧紧凑的发送键。
  ///
  /// 不按屏幕宽度分档，只看实际可用宽度。
  Widget _buildToolRow(BuildContext context) {
    final efforts = _efforts;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _fitFor(
          context,
          constraints.maxWidth,
          efforts: efforts,
          hasPicker: widget.onPickAttachments != null,
          desktop: widget.desktopKeyboard ?? AppPaths.isDesktop,
        );
        return Row(
          children: [
            // 第一组：附件；没有选择器时不占位。
            if (widget.onPickAttachments != null)
              _buildAddButton(context, hasLabel: fit.addLabel),
            // 组间最小间距要先占住：窄屏下 Spacer 会缩成 0，
            // 两个 chip 就会贴在一起。
            if (widget.onPickAttachments != null) SizedBox(width: fit.outerGap),
            // 第二组：权限、模型、推理强度，组内间距一致。
            _buildSelectorGroup(context, fit: fit, efforts: efforts),
            const Spacer(),
            SizedBox(width: fit.rightGap),
            // 第三组：发送。可见的圆 36，可点范围 44。
            _buildSendButton(context),
          ],
        );
      },
    );
  }

  /// 选择器组：放不下就收文字，不会撑出边界。
  Widget _buildSelectorGroup(
    BuildContext context, {
    required _ToolRowFit fit,
    required List<String> efforts,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPermissionButton(context, showLabel: fit.permissionLabel),
        const SizedBox(width: _selectorGap),
        // 宽度由档位算好，这里不再伸缩。
        SizedBox(width: fit.modelWidth, child: _buildModelButton(context)),
        if (efforts.isNotEmpty) ...[
          const SizedBox(width: _selectorGap),
          _buildEffortButton(context, efforts, showLabel: fit.effortLabel),
        ],
      ],
    );
  }

  /// 发送与停止占同一块区域。
  ///
  /// 用标准 `IconButton` 保留按钮语义与键盘激活；背景透明，
  /// 可见的圆由 36 的容器画，可点范围仍为 44。
  Widget _buildSendButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = widget.running;
    // 能点需要同时满足：有内容、界面可用、当前没在发。
    final canSendNow = _state.canSend && widget.enabled && !_sending;

    // 底色与前景色成对给出，保证对比度：
    // 运行/禁用用容器色，可用时用主色。
    final Color fill;
    final Color foreground;
    if (running) {
      fill = scheme.surfaceContainerHighest;
      // 深色主题下 onSurfaceVariant 与容器色对比不够，用 onSurface。
      foreground = scheme.onSurface;
    } else if (canSendNow) {
      fill = scheme.primary;
      foreground = scheme.onPrimary;
    } else {
      fill = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    }

    return SizedBox(
      width: _sendTarget,
      height: _sendTarget,
      child: IconButton(
        key: ValueKey(running ? 'composer-stop' : 'composer-send'),
        tooltip: running ? '停止' : '发送',
        onPressed: running ? widget.onStop : (canSendNow ? _submit : null),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(_sendTarget),
          minimumSize: const Size.square(_sendTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: EdgeInsets.zero,
          // 不画底色：否则会把 44 的可点区整个填满，看起来又变大了。
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          splashFactory: InkSparkle.splashFactory,
          shape: const CircleBorder(),
        ),
        icon: Container(
          width: _sendDiameter,
          height: _sendDiameter,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Center(
            child: running
                ? Icon(Icons.stop, size: 18, color: foreground)
                : (_sending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foreground,
                          ),
                        )
                      : Icon(Icons.arrow_upward, size: 18, color: foreground)),
          ),
        ),
      ),
    );
  }

  /// 附件加号：贴在最左侧。
  ///
  /// 图标左对齐，避免默认居中摆放造成的视觉偏移。
  Widget _buildAddButton(BuildContext context, {required bool hasLabel}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<AttachmentSource>(
      key: const ValueKey('composer-plus'),
      tooltip: '添加文件',
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
      child: Container(
        height: 44,
        constraints: BoxConstraints(minWidth: hasLabel ? 64 : _addWidth),
        // 不加底色：它只是图标入口，不像选择器那样需要 chip。
        // 左边不留白，图标与输入框文字对齐。
        padding: EdgeInsets.only(
          left: hasLabel ? 8 : 0,
          right: hasLabel ? 8 : 0,
        ),
        alignment: Alignment.centerLeft,
        // 图标靠左不居中，否则看起来又离左边远了一截。
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
            if (hasLabel) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '附件',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _permissionLabel => switch (_state.permission) {
    AgentPermissionMode.readOnly => '只读',
    AgentPermissionMode.askEveryWrite => '每次询问',
    AgentPermissionMode.autoAcceptEdits => '自动接受',
  };

  Widget _buildPermissionButton(
    BuildContext context, {
    required bool showLabel,
  }) {
    return PopupMenuButton<AgentPermissionMode>(
      key: const ValueKey('composer-permission'),
      // 提示由下面的 chip 提供，这里不再重复，否则同一个提示会出现两次。
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
        // 不用问号：问号看不出这是权限，也容易被当成帮助按钮。
        icon: switch (_state.permission) {
          AgentPermissionMode.readOnly => Icons.visibility_outlined,
          AgentPermissionMode.askEveryWrite => Icons.shield_outlined,
          AgentPermissionMode.autoAcceptEdits => Icons.bolt_outlined,
        },
        label: _permissionLabel,
        tooltip: '权限模式：$_permissionLabel',
        compact: !showLabel,
      ),
    );
  }

  /// 模型选择始终显示，并且始终带模型名。
  ///
  /// 加载中显示「模型…」；列表为空或失败显示「默认模型」，点开说明原因并提供
  /// 「重试」。名字过长时省略，但按钮至少留出六个字的宽度。
  Widget _buildModelButton(BuildContext context) {
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
        compact: false,
        // 六个字左右的宽度：名字再长也先保证看得见开头。
        minWidth: _modelChipMinWidth,
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
    required bool showLabel,
  }) {
    final selected = _state.reasoningEffort;
    final label = selected ?? efforts.first;
    return PopupMenuButton<String>(
      key: const ValueKey('composer-reasoning'),
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
        compact: !showLabel,
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
      // 内边距 8 而不是 10：窄卡片下模型名能多看见两个字。
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
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
          if (trailing != null) ...[const SizedBox(width: 5), trailing],
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

/// 工具行保留哪些文字，以及各段空隙的宽度。
@immutable
class _ToolRowFit {
  const _ToolRowFit({
    required this.addLabel,
    required this.permissionLabel,
    required this.effortLabel,
    required this.modelWidth,
    required this.outerGap,
    required this.rightGap,
  });

  /// 加号是否带「附件」文字。只有很宽且宽松的卡片才带。
  final bool addLabel;
  final bool permissionLabel;
  final bool effortLabel;

  /// 模型按钮的宽度。
  final double modelWidth;

  /// 附件与选择器组之间的空隙。永远不小于 _minOuterGap。
  final double outerGap;

  /// 选择器组与发送键之间留出的空隙。
  final double rightGap;
}

/// 模型按钮至少留出的宽度：图标加约五个字。
const double _modelChipMinWidth = 84;

/// 选择器组内部的按钮间距：比组间的空隙小，看起来是一组。
const double _selectorGap = 6;

/// 加号按钮的尺寸（无文字）与带文字时的宽度。
const double _addWidth = 44;
const double _addLabelWidth = 64;

/// 选择器只剩图标时的宽度。
const double _toolIconChipWidth = 44;

/// 发送键：可点范围 44，视觉圆 36。
const double _sendDiameter = 36;
const double _sendTarget = 44;

/// 选择器组与发送键之间：发送是主操作，留得比组内间距大。
const double _toolSendGap = 12;

/// 附件与选择器组之间的最小空隙。必须在宽度预算里先扣出来，
/// 否则窄屏下会被挤成 0。
const double _minOuterGap = 8;

/// 刚好塞满时字体会压线，留一点余量再换下一档。空隙已经算在 required()
/// 里，这里的余量只需覆盖四舍五入误差，不用再放大。
const double _toolFitSlack = 0;

/// 模型名吃剩余宽度时额外扣掉的像素。
///
/// 文字度量与真正排版之间可能差 1px（真字体下尤其明显），刚好塞满时
/// 工具行会画出溢出条。宁可让模型名少 1px。
const double _toolRowRoundingSlack = 1;

/// 生成一套按钮宽度：文字用真实的字体度量，已含字体缩放。
class _ToolRowMetrics {
  _ToolRowMetrics(BuildContext context)
    : permissionLabel = _chipWidth(context, _permissionLabels),
      effortLabel = _chipWidth(context, _effortLabels);

  /// 权限按钮带文字时的宽度：三种模式里取最宽的，切换模式不抖动。
  final double permissionLabel;

  /// 推理强度带文字时的宽度：常见的几档里取最宽。
  final double effortLabel;

  static const List<String> _permissionLabels = ['只读', '每次询问', '自动接受'];

  /// 推理强度的可选值由模型决定，这里用几个常见的短词估宽；真实值更短也不会溢出。
  static const List<String> _effortLabels = ['low', 'medium', 'high', '最小'];

  static double _chipWidth(BuildContext context, List<String> labels) {
    var widest = 0.0;
    for (final label in labels) {
      widest = math.max(widest, _textWidth(context, label));
    }
    // 图标 15 + 图标与文字的间距 5 + 左右内边距 16。
    return 36 + widest;
  }

  static double _textWidth(BuildContext context, String text) {
    final theme = Theme.of(context);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: theme.textTheme.labelMedium ?? const TextStyle(),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// 选最齐的档：先试全部带文字，再依次收附件、推理强度、权限的文字。
///
/// 收缩顺序：推理强度，权限，模型名最后；附件标签最先收。
_ToolRowFit _fitFor(
  BuildContext context,
  double available, {
  required List<String> efforts,
  required bool hasPicker,
  required bool desktop,
}) {
  final metrics = _ToolRowMetrics(context);
  final hasEfforts = efforts.isNotEmpty;
  final sendWidth = _sendTarget;
  // 组间空隙在预算里先留出来：窄屏下 Spacer 会缩成 0，
  // 预留这一段才能保证两个 chip 不贴着。
  final filterGap = hasPicker ? _minOuterGap : 0.0;
  final gaps = filterGap + _toolSendGap;

  double required({
    required bool addLabel,
    required bool permission,
    required bool effort,
  }) {
    final addWidthNow = !hasPicker
        ? 0.0
        : (addLabel ? math.max(_addWidth, _addLabelWidth) : _addWidth);
    final permissionWidth = permission
        ? metrics.permissionLabel
        : _toolIconChipWidth;
    final effortWidth = !hasEfforts
        ? 0.0
        : (effort ? metrics.effortLabel : _toolIconChipWidth);
    // 模型的宽度下界也算进去：放不下就继续收文字，而不是让它撑出边界。
    final selectorGaps = _selectorGap + (hasEfforts ? _selectorGap : 0.0);
    return addWidthNow +
        gaps +
        permissionWidth +
        selectorGaps +
        effortWidth +
        _modelChipMinWidth +
        sendWidth;
  }

  bool fits({
    required bool addLabel,
    required bool permission,
    required bool effort,
  }) =>
      required(addLabel: addLabel, permission: permission, effort: effort) +
          _toolFitSlack <=
      available;

  // 桌面端选择器标签是主要识别信息，只要放得下就一直带；移动端按宽度收。
  var addLabel = false;
  var permission = false;
  var effort = false;

  if (fits(addLabel: hasPicker, permission: true, effort: hasEfforts)) {
    addLabel = hasPicker;
    permission = true;
    effort = hasEfforts;
  } else if (fits(addLabel: false, permission: true, effort: hasEfforts)) {
    permission = true;
    effort = hasEfforts;
  } else if (fits(addLabel: false, permission: true, effort: false)) {
    permission = true;
  }

  // 桌面窗口再窄也优先保留选择器文字，放不下时宁可让模型名窄一点。
  if (desktop && !permission) {
    final withoutLabels = required(
      addLabel: false,
      permission: true,
      effort: false,
    );
    if (withoutLabels + _toolFitSlack <= available) permission = true;
  }

  // 模型名拿剩下的宽度。
  //
  // 三种情况：放得下就按下界与封顶值取一个；原本就挤时把剩下的宽度
  // 全部给模型名。宁可模型名短一点，也不让两个 chip 贴在一起。
  final used =
      required(addLabel: addLabel, permission: permission, effort: effort) -
      _modelChipMinWidth;
  final room = available - used - _toolRowRoundingSlack;
  final double modelWidth;
  if (room >= _modelChipMinWidth) {
    final modelCap = math.max(_modelChipMinWidth, available * 0.36);
    modelWidth = math.min(modelCap, room);
  } else {
    // 放不下完整下界：图标优先，剩下的宽度全给模型名，但绝不撑过可用宽度。
    // 393 宽的手机上这里原来会多出 1px，工具行画出溢出条。
    modelWidth = math.max(0, room);
  }
  return _ToolRowFit(
    addLabel: addLabel,
    permissionLabel: permission,
    effortLabel: effort,
    modelWidth: modelWidth,
    outerGap: hasPicker ? _minOuterGap : 0,
    rightGap: _toolSendGap,
  );
}

/// 模型菜单里的「重试」条目。用独立类型，避免和模型 id 的字符串撞上。
class _RetryModels {
  const _RetryModels();
}
