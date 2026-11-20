import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../vibe_coding/vibe_agent_facade.dart';
import '../vibe_coding/vibe_coding_widgets.dart';

/// 一条思考消息的气泡：标题行加可折叠的思考正文。
///
/// 标题行显示状态和用时。流式中每秒刷新一次，结束时换成最终用时
/// （任务 11-19-agent-thinking-stream design §6）。
class ThinkingBubble extends StatefulWidget {
  const ThinkingBubble({
    super.key,
    required this.message,
    this.liveText,
    this.expanded,
    this.onToggle,
  });

  /// `role == 'reasoning'` 的消息。
  final AgentMessageView message;

  /// 流式中的实时文本。取不到值时用 [message] 自己的 `text`。
  final ValueListenable<String>? liveText;

  /// 用户手动设置的展开状态。null 表示用户没设置过。
  final bool? expanded;

  /// 用户点了标题行。为 null 时气泡自己记住这次切换。
  final ValueChanged<bool>? onToggle;

  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble> {
  /// 流式中展开的气泡最高多少像素。高度固定，对话列表不会每帧跳动。
  static const double _streamingMaxHeight = 240;

  /// 离末尾多少像素以内算贴着末尾。
  static const double _tailSlack = 8;

  final ScrollController _body = ScrollController();

  /// 流式计时器。只在流式中运行。
  Timer? _ticker;

  /// 流式开始后的秒数。
  int _seconds = 0;

  /// 正文是否跟随末尾。
  bool _followTail = true;
  bool _tailJumpScheduled = false;

  /// 调用方没接管展开状态时，气泡自己记用户的选择。
  bool? _localExpanded;

  @override
  void initState() {
    super.initState();
    _body.addListener(_onBodyScroll);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ThinkingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _body.removeListener(_onBodyScroll);
    _body.dispose();
    super.dispose();
  }

  /// 流式中启动计时器，结束时停掉。销毁时由 [dispose] 停掉。
  void _syncTicker() {
    if (widget.message.pending) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
      });
      return;
    }
    _ticker?.cancel();
    _ticker = null;
  }

  /// 用户手动设置过就用用户的值，没设置过时流式中展开、结束后收起。
  bool get _expanded =>
      widget.expanded ?? _localExpanded ?? widget.message.pending;

  void _toggle() {
    final next = !_expanded;
    final onToggle = widget.onToggle;
    if (onToggle != null) {
      onToggle(next);
      return;
    }
    setState(() => _localExpanded = next);
  }

  /// 标题文案：流式写「思考中… N 秒」，结束写最终用时，取消时不写秒数。
  String get _title {
    final message = widget.message;
    if (message.pending) return '思考中… $_seconds 秒';
    final duration = message.durationMs;
    if (duration == null) return '已思考';
    return '已思考 ${(duration / 1000).round()} 秒';
  }

  /// 用户往上滚离开末尾时停止自动跟随，滚回底部后恢复。
  void _onBodyScroll() {
    if (!_body.hasClients) return;
    final position = _body.position;
    final atBottom = position.maxScrollExtent - position.pixels <= _tailSlack;
    if (atBottom != _followTail) _followTail = atBottom;
  }

  /// 下一帧把正文带到底部。只在流式且跟随末尾时跳。
  void _scheduleTailJump() {
    if (_tailJumpScheduled) return;
    _tailJumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tailJumpScheduled = false;
      if (!mounted || !_followTail) return;
      if (!_body.hasClients) return;
      final position = _body.position;
      if (position.maxScrollExtent <= 0) return;
      if ((position.pixels - position.maxScrollExtent).abs() <= 0.5) return;
      _body.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 思考内容比正文更弱：底色更淡，文字用次要色。两种主题都用配色方案。
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.5,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: ValueKey('thinking-bubble-${widget.message.id}'),
        margin: const EdgeInsets.only(bottom: 6, right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  // 收起时只建标题行，正文不进树。
                  if (_expanded) _buildBody(context, bodyStyle),
                ],
              ),
            ),
            // AI 标记始终在气泡下方，收起时也显示（prd AC8）。
            const AiGeneratedBadge(),
          ],
        ),
      ),
    );
  }

  /// 标题行：思考图标、文案、展开箭头。整行都能点，高度不少于 44。
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = _expanded;
    return Semantics(
      button: true,
      label: '思考内容',
      child: InkWell(
        key: ValueKey('thinking-header-${widget.message.id}'),
        onTap: _toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _title,
                    key: ValueKey('thinking-title-${widget.message.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TextStyle? style) {
    final key = ValueKey('thinking-body-${widget.message.id}');
    const padding = EdgeInsets.fromLTRB(10, 0, 10, 10);
    final body = _buildStreamText(style);
    if (!widget.message.pending) {
      // 结束后显示完整内容，不再限高。
      return Padding(key: key, padding: padding, child: body);
    }
    // 流式时固定高度，内部滚动并跟随末尾。
    return ConstrainedBox(
      key: key,
      constraints: const BoxConstraints(maxHeight: _streamingMaxHeight),
      child: SingleChildScrollView(
        controller: _body,
        padding: padding,
        child: body,
      ),
    );
  }

  /// 正文。有实时文本时只重绘这个气泡，不重建整个对话列表。
  Widget _buildStreamText(TextStyle? style) {
    final live = widget.liveText;
    if (live == null) return _chunked(style, widget.message.text);
    return ValueListenableBuilder<String>(
      valueListenable: live,
      builder: (context, value, _) {
        if (widget.message.pending) _scheduleTailJump();
        return _chunked(style, value.isEmpty ? widget.message.text : value);
      },
    );
  }

  Widget _chunked(TextStyle? style, String text) => ChunkedText(
    text: text,
    style: style,
    // 流式用普通 Text，结束后才能选中复制（design §6.1）。
    selectable: !widget.message.pending,
    keyPrefix: 'thinking-${widget.message.id}',
  );
}

/// 分块渲染长文本。
///
/// 已完成的块缓存成固定 widget，只有最后一块随增量重新布局
/// （design §6.1）。思考正文和 AI 正文共用这个组件。
class ChunkedText extends StatefulWidget {
  const ChunkedText({
    super.key,
    required this.text,
    this.style,
    this.selectable = false,
    this.keyPrefix = 'chunk',
    this.chunkSize = defaultChunkSize,
  });

  /// 一块的目标字符数。块边界落在换行之后，实际长度略大于它。
  static const int defaultChunkSize = 2048;

  /// 测试用：从 [start] 开始的一块到哪里结束。
  @visibleForTesting
  static int debugBoundaryOf(String text, int start, int target) =>
      _chunkBoundaryOf(text, start, target);

  final String text;
  final TextStyle? style;

  /// 结束时用可选中的文本，流式中用普通文本。
  final bool selectable;

  /// 块 widget 的 key 前缀。测试按它断言只重排最后一块。
  final String keyPrefix;

  final int chunkSize;

  @override
  State<ChunkedText> createState() => _ChunkedTextState();
}

class _ChunkedTextState extends State<ChunkedText> {
  /// 已经定型的块文本。
  final List<String> _settled = <String>[];

  /// 定型块的 widget。文本追加时原样复用，Flutter 跳过它们的重建。
  final List<Widget> _settledWidgets = <Widget>[];

  /// 已经切进 [_settled] 的字符数。
  int _consumed = 0;

  /// 仍在增长的最后一块。
  String _tail = '';

  /// 上一次处理的完整文本。
  String _seen = '';

  @override
  void initState() {
    super.initState();
    _consume(widget.text);
  }

  @override
  void didUpdateWidget(covariant ChunkedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 样式、可选状态或块长度变了，缓存块要按新样式重建。
    if (oldWidget.selectable != widget.selectable ||
        oldWidget.style != widget.style ||
        oldWidget.chunkSize != widget.chunkSize) {
      _reset();
    }
    if (widget.text != _seen) _consume(widget.text);
  }

  void _reset() {
    _settled.clear();
    _settledWidgets.clear();
    _consumed = 0;
    _tail = '';
    _seen = '';
  }

  /// 把新增的文本切块。只有追加才能复用已定型的块，整体替换就从头切。
  void _consume(String text) {
    if (!text.startsWith(_seen)) {
      _settled.clear();
      _settledWidgets.clear();
      _consumed = 0;
    }
    var start = _consumed;
    while (true) {
      final end = _chunkBoundaryOf(text, start, widget.chunkSize);
      if (end >= text.length) break;
      final chunk = text.substring(start, end);
      _settled.add(chunk);
      _settledWidgets.add(_buildChunk(_settledWidgets.length, chunk));
      start = end;
    }
    _consumed = start;
    _tail = text.substring(start);
    _seen = text;
  }

  Widget _buildChunk(int index, String text) {
    final key = ValueKey('${widget.keyPrefix}-chunk-$index');
    if (widget.selectable) {
      return SelectableText(text, key: key, style: widget.style);
    }
    return Text(text, key: key, style: widget.style);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[..._settledWidgets];
    if (_tail.isNotEmpty || _settled.isEmpty) {
      children.add(_buildChunk(_settled.length, _tail));
    }
    if (children.length == 1) return children.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// 找一个块边界：目标长度之后的第一个换行。
///
/// 一整行超过两个目标长度时按目标长度硬切，避免一个块无限变大。
/// 边界只由前缀决定，所以追加文本不会改动已经切好的块。
int _chunkBoundaryOf(String text, int start, int target) {
  final limit = start + target;
  if (text.length <= limit) return text.length;
  final newline = text.indexOf('\n', limit - 1);
  if (newline >= 0 && newline < limit + target) return newline + 1;
  var cut = limit;
  // 不要把落单的代理对切开。
  if (cut > start + 1) {
    final unit = text.codeUnitAt(cut);
    if (unit >= 0xDC00 && unit <= 0xDFFF) cut -= 1;
  }
  return cut;
}
