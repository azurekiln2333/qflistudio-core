import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vibe_coding/vibe_agent_facade.dart';
import '../vibe_coding/vibe_coding_widgets.dart';
import 'write_approval_card.dart';

/// 对话流：一个会话的消息列表。
///
/// 只渲染 facade 给出的消息，不推断工具结果。见 design.md §4 第 6、7、8 条。
class ChatTranscript extends StatefulWidget {
  const ChatTranscript({
    super.key,
    required this.messages,
    required this.state,
    this.lastError,
    this.errorInfo,
    this.activity,
    this.queued = false,
    this.waitingSeconds,
    this.hasEarlier = false,
    this.loadingEarlier = false,
    this.onLoadEarlier,
    this.pendingApproval,
    this.onApproval,
    this.onRetry,
    this.onDiagnose,
    this.onResend,
    this.onEdit,
    this.onOpenFile,
    this.fileExists,
    this.busy = false,
    this.sessionKey,
    this.emptyTitle = '开始一个新的会话',
    this.emptyHint = '描述你想改什么。Agent 会读写项目文件，并在在线终端里运行命令。',
    this.emptyAction,
    this.padding = const EdgeInsets.all(12),
  });

  final List<AgentMessageView> messages;
  final AgentRunState state;

  /// 最近一次失败的原因，直接来自 facade。
  final String? lastError;

  /// 最近一次失败的分类。有分类时按 design.md §11.6 的文案表选文案。
  final AgentErrorInfo? errorInfo;

  /// 一句话说明正在做什么，来自 `facade.activity`。为空时写「思考中…」。
  final String? activity;

  /// 会话在排队。为真时状态行写「排队中」。
  final bool queued;

  /// 已等待秒数；不足 3 秒时为 null。
  final int? waitingSeconds;

  /// 还有更早的消息可以载入。
  final bool hasEarlier;

  /// 正在载入更早的一页。
  final bool loadingEarlier;

  final VoidCallback? onLoadEarlier;

  /// 等待确认的写入。
  final AgentWriteApproval? pendingApproval;

  final ValueChanged<bool>? onApproval;

  /// 重试上一条用户消息。
  final VoidCallback? onRetry;

  /// 诊断到 API 服务器的连接。只在用户点「诊断连接」时调用，不自动发起。
  /// 为空时不显示该按钮。
  final Future<String> Function()? onDiagnose;

  /// 把一条用户消息原样再发一次。为空时不显示「重发」。
  ///
  /// 重发走现有的发送管线，不碰输入卡片里未发出的草稿。第二个参数是消息 id，
  /// 调用方用它做「同一条消息不会被连点两次」的守卫。
  final void Function(AgentUserMessage message, String id)? onResend;

  /// 把一条用户消息放进输入卡片等用户确认发送。为空时不显示「编辑后重发」。
  final void Function(AgentUserMessage message, String id)? onEdit;

  /// 点开工具写入的文件。参数是相对项目根的路径。
  ///
  /// 为空时文件卡片只显示路径，不可点。
  final void Function(String path)? onOpenFile;

  /// 文件现在是否还在磁盘上。已删除的文件显示为禁用的卡片。
  /// 为空时按存在处理。
  final bool Function(String path)? fileExists;

  /// 会话正在跑：消息动作只能复制，编辑与重发要等这一轮结束。
  final bool busy;

  /// 当前会话的标识。换值时丢掉条目缓存并回到最新一条，
  /// 避免把上一个会话的条目和滚动位置带过来。
  final Object? sessionKey;

  final String emptyTitle;
  final String emptyHint;
  final Widget? emptyAction;
  final EdgeInsets padding;

  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
}

class _ChatTranscriptState extends State<ChatTranscript> {
  final ScrollController _scroll = ScrollController();
  String _lastTail = '';
  double _lastPixels = 0;

  /// 列表是否跟随底部。只有用户本来就贴着底部时新消息才自动滚到底：
  /// 用户往上翻看历史时不被抢走位置。
  bool _followBottom = true;
  bool _bottomJumpScheduled = false;
  bool _programmaticScroll = false;

  /// 首次载入的消息固定在中心，后续历史向上生长。
  final _centerKey = GlobalKey();
  int _earlierCount = 0;

  /// 上一次的条目 id 序列。判前插只看它，不看条数差。
  List<String> _lastIds = const <String>[];

  /// 每个缓存条目建出来时的动作指纹。
  final Map<String, String> _actionStamps = <String, String>{};

  /// 整个列表最近一次的动作指纹。
  String _lastActionStamp = '';

  /// 距离底部多少像素以内算「贴着底部」。
  static const double _followSlack = 32;

  /// 诊断结果和它对应的那次失败。失败变了就丢掉旧结果，避免张冠李戴。
  String? _diagnosis;
  String? _diagnosisFor;
  bool _diagnosing = false;

  /// 刚复制过详情，按钮上给一句回执。
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _lastIds = [for (final message in widget.messages) message.id];
    if (widget.messages.isNotEmpty) {
      _lastTail = _tailOf(widget.messages.last);
    }
    _scroll.addListener(_onScroll);
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant ChatTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signatureOf(widget.errorInfo) != _signatureOf(oldWidget.errorInfo)) {
      _diagnosis = null;
      _diagnosisFor = null;
      _diagnosing = false;
      _copied = false;
    }
    // 换了会话：条目缓存、底部跟随和诊断结果都不属于新会话。
    if (widget.sessionKey != oldWidget.sessionKey) {
      _resetTiles();
      _diagnosis = null;
      _diagnosisFor = null;
      _diagnosing = false;
      _copied = false;
      _scheduleJumpToBottom();
      return;
    }
    _refreshActionsIfNeeded();
    final messages = widget.messages;
    final tail = messages.isEmpty ? '' : _tailOf(messages.last);
    final ids = [for (final message in messages) message.id];
    if (_sameIds(ids, _lastIds) && tail == _lastTail) {
      if (_followBottom && widget.hasEarlier != oldWidget.hasEarlier) {
        _scheduleScrollToBottom();
      }
      return;
    }
    final prepended = _isPrepend(_lastIds, ids);
    if (prepended) _earlierCount += ids.length - _lastIds.length;
    _lastIds = ids;
    _lastTail = tail;
    if (prepended) return;
    if (_earlierCount > ids.length) _earlierCount = 0;
    if (_followBottom) _scheduleScrollToBottom();
  }

  /// 新列表就是把旧列表原样接在后面：只在前面多了条目。
  ///
  /// 用稳定 id 做命中比较，不看条数差：一次载入可能一条，也可能十几条。
  static bool _isPrepend(List<String> before, List<String> after) {
    if (before.isEmpty || after.length <= before.length) return false;
    final shift = after.length - before.length;
    for (var index = 0; index < before.length; index++) {
      if (after[index + shift] != before[index]) return false;
    }
    return true;
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static String _tailOf(AgentMessageView message) =>
      '${message.id}|${message.text.length}|${message.pending}';

  /// 已渲染过的条目。流式更新时只有末尾那条的内容会变，其余直接复用同一个
  /// widget 实例，Flutter 会跳过它们的 build（brief 任务 9）。
  final Map<String, Widget> _tiles = <String, Widget>{};
  final Map<String, AgentMessageView> _rendered = <String, AgentMessageView>{};

  /// 条目缓存的上限。超过就整体丢掉，避免长会话把旧条目一直留在内存里。
  static const int _tileCacheLimit = 4000;

  Widget _tileFor(AgentMessageView message) {
    final cached = _tiles[message.id];
    final previous = _rendered[message.id];
    if (cached != null &&
        previous != null &&
        _sameView(previous, message) &&
        _actionStamps[message.id] == _actionStamp()) {
      return cached;
    }
    if (_tiles.length >= _tileCacheLimit) {
      _tiles.clear();
      _rendered.clear();
    }
    // 只有用户的提问能编辑或重发；助手与工具条目不是提示词。
    // 回声消息（这一条还在发送中）也还不是可编辑的历史。
    final isUser = message.role == 'user';
    final settled = isUser && !message.pending;
    final offerEdit = settled && widget.onEdit != null;
    final offerResend = settled && widget.onResend != null;
    final canEdit = offerEdit && !widget.busy;
    final canResend = offerResend && !widget.busy;
    final sessionKey = widget.sessionKey;
    final tile = ChatMessageTile(
      key: ValueKey('chat-message-${message.id}'),
      message: message,
      onOpenFile: widget.onOpenFile,
      fileExists: widget.fileExists,
      actions: ChatMessageActions(
        canEdit: canEdit,
        canResend: canResend,
        busy: widget.busy,
        onCopy: () => _copyMessage(context, message),
        onEdit: offerEdit
            ? () {
                if (widget.sessionKey != sessionKey || widget.busy) return;
                widget.onEdit?.call(AgentUserMessage.of(message), message.id);
              }
            : null,
        onResend: offerResend
            ? () {
                if (widget.sessionKey != sessionKey || widget.busy) return;
                widget.onResend?.call(AgentUserMessage.of(message), message.id);
              }
            : null,
      ),
    );
    _tiles[message.id] = tile;
    _rendered[message.id] = message;
    _actionStamps[message.id] = _actionStamp();
    return tile;
  }

  /// 动作可用性是否变了的指纹。
  ///
  /// 运行中/空闲切换会改变菜单项的可点状态，缓存条目必须跟着重建，
  /// 否则会继续用旧的回调与旧的 enabled 状态。
  String _actionStamp() =>
      '${widget.busy}|${widget.onEdit != null}|${widget.onResend != null}';

  /// 动作指纹变过就丢掉条目缓存。
  void _refreshActionsIfNeeded() {
    final stamp = _actionStamp();
    if (stamp == _lastActionStamp) return;
    _lastActionStamp = stamp;
    _tiles.clear();
    _rendered.clear();
    _actionStamps.clear();
  }

  /// 复制一条消息的正文。附件段的路径也复制，用户拿到的就是当时发的原文。
  Future<void> _copyMessage(
    BuildContext context,
    AgentMessageView message,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = message.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: message.text));
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 2)),
      );
  }

  /// 内容没变就不重建。逐字段比较，不依赖 facade 复用同一个视图对象。
  static bool _sameView(AgentMessageView a, AgentMessageView b) =>
      a.role == b.role &&
      a.text == b.text &&
      a.toolName == b.toolName &&
      a.isError == b.isError &&
      a.pending == b.pending &&
      a.sourceText == b.sourceText &&
      a.aiGenerated == b.aiGenerated &&
      listEquals(a.changedPaths, b.changedPaths) &&
      listEquals(a.attachedPaths, b.attachedPaths);

  /// 条目缓存按会话隔离：换会话后旧条目不能活下来。
  void _resetTiles() {
    _tiles.clear();
    _rendered.clear();
    _actionStamps.clear();
    _earlierCount = 0;
    _lastPixels = 0;
    _lastIds = [for (final message in widget.messages) message.id];
    _lastTail = widget.messages.isEmpty ? '' : _tailOf(widget.messages.last);
    _followBottom = true;
  }

  void _scheduleScrollToBottom() {
    if (_bottomJumpScheduled) return;
    _bottomJumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomJumpScheduled = false;
      if (!mounted || !_scroll.hasClients || !_followBottom) return;
      final position = _scroll.position;
      final target = position.maxScrollExtent <= 0
          ? position.minScrollExtent
          : position.maxScrollExtent;
      if ((position.pixels - target).abs() <= 0.5) return;
      _programmaticScroll = true;
      try {
        _scroll.jumpTo(target);
      } finally {
        _programmaticScroll = false;
      }
      _followBottom = true;
      // 懒列表会更新滚动范围，下一帧继续贴近真实底部。
      _scheduleScrollToBottom();
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// 换会话后无条件跳到底：新会话的第一屏就是最新一条。
  void _scheduleJumpToBottom() {
    _followBottom = true;
    _scheduleScrollToBottom();
  }

  /// 用户往上滚到顶时载入更早的一页。
  ///
  /// 只在向上移动时触发，首次布局时 pixels 也等于 0，不能因此反复拉取。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final pixels = position.pixels;
    final movingUp = pixels < _lastPixels;
    _lastPixels = pixels;
    if (_programmaticScroll) return;
    // 只有贴着底部时才跟随新消息；离得远就当作在阅读历史。
    final atBottom = position.maxScrollExtent - pixels <= _followSlack;
    if (atBottom != _followBottom) _followBottom = atBottom;
    if (!movingUp) return;
    if (!widget.hasEarlier || widget.loadingEarlier) return;
    if (pixels > position.minScrollExtent) return;
    widget.onLoadEarlier?.call();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  bool get _running =>
      widget.state == AgentRunState.running ||
      widget.state == AgentRunState.cancelling ||
      widget.state == AgentRunState.awaitingApproval;

  /// 有进展要显示：运行、排队或等待确认。
  bool get _busy => _running || widget.queued;

  /// 状态行文案：排队优先，其次等确认，再用 facade 的 activity，最后是「思考中…」。
  ///
  /// 等确认时不能写「思考中…」：会话已经停下来等用户，这时再提示思考会
  /// 让用户以为还要等（C3）。
  String get _statusText {
    if (widget.queued) return '排队中';
    if (widget.state == AgentRunState.awaitingApproval) return '等待你确认写入';
    final activity = widget.activity?.trim() ?? '';
    if (activity.isNotEmpty) return activity;
    return '思考中…';
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final approval = widget.pendingApproval;
    final failed = widget.state == AgentRunState.failed;
    final busy = _busy;
    if (messages.isEmpty && approval == null && !failed && !busy) {
      return _buildEmpty(context);
    }
    final showEarlier = widget.hasEarlier;
    final extras = (approval == null ? 0 : 1) + (failed ? 1 : 0);
    final list = CustomScrollView(
      controller: _scroll,
      center: _centerKey,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            widget.padding.left,
            widget.padding.top,
            widget.padding.right,
            0,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => index < _earlierCount
                  ? _tileFor(messages[_earlierCount - 1 - index])
                  : _buildEarlierButton(context),
              childCount: _earlierCount + (showEarlier ? 1 : 0),
            ),
          ),
        ),
        SliverPadding(
          key: _centerKey,
          padding: EdgeInsets.fromLTRB(
            widget.padding.left,
            0,
            widget.padding.right,
            widget.padding.bottom,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final position = _earlierCount + index;
              if (position < messages.length) {
                return _tileFor(messages[position]);
              }
              if (approval != null && position == messages.length) {
                return WriteApprovalCard(
                  approval: approval,
                  onResolve: (allow) => widget.onApproval?.call(allow),
                );
              }
              return _buildErrorBar(context);
            }, childCount: messages.length - _earlierCount + extras),
          ),
        ),
      ],
    );
    if (!busy) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusHeader(context),
        Expanded(child: list),
      ],
    );
  }

  /// 对话流顶部的进度条和状态行（design.md §11.6）。
  Widget _buildStatusHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final waiting = widget.waitingSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(
          key: ValueKey('chat-progress'),
          minHeight: 3,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _statusText,
                  key: const ValueKey('chat-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (waiting != null)
                Text(
                  '已等待 $waiting 秒',
                  key: const ValueKey('chat-waiting'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEarlierButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: TextButton.icon(
          key: const ValueKey('chat-load-earlier'),
          onPressed: widget.loadingEarlier ? null : widget.onLoadEarlier,
          icon: widget.loadingEarlier
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.history, size: 18),
          label: const Text('载入更早的消息'),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 30,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              widget.emptyTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              widget.emptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            if (widget.emptyAction != null) ...[
              const SizedBox(height: 16),
              widget.emptyAction!,
            ],
          ],
        ),
      ),
    );
  }

  /// 一次失败的身份，用于判断诊断结果和「已复制」是否还适用。
  static String _signatureOf(AgentErrorInfo? info) {
    if (info == null) return '';
    return '${info.host}|${info.phase.name}|${info.statusCode}|${info.detail}';
  }

  /// 详情区的文本：状态码单独一行，后面跟多行说明。
  static String _detailTextOf(AgentErrorInfo info) {
    final detail = info.detail.trim();
    return <String>[
      if (info.statusCode != null) '状态码：${info.statusCode}',
      if (detail.isNotEmpty) detail,
    ].join('\n');
  }

  /// 复制用的文本：详情加一行设备时间，方便和日志对上。
  static String _copyTextOf(AgentErrorInfo info) {
    final stamp = '复制于 ${_formatDeviceTime(DateTime.now())}';
    final body = _detailTextOf(info);
    return body.isEmpty ? stamp : '$body\n$stamp';
  }

  static String _formatDeviceTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final offset = time.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final zone =
        '$sign${two(absolute.inHours)}:'
        '${two(absolute.inMinutes.remainder(60))}';
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)} $zone';
  }

  /// 连接类失败才建议诊断：服务器返回了 HTTP 错误时诊断没有意义。
  bool _canDiagnose(AgentErrorInfo info) {
    if (widget.onDiagnose == null) return false;
    return switch (info.phase) {
      AgentErrorPhase.dns ||
      AgentErrorPhase.connect ||
      AgentErrorPhase.tls ||
      AgentErrorPhase.timeout => true,
      _ => false,
    };
  }

  Future<void> _copyDetails(AgentErrorInfo info) async {
    await Clipboard.setData(ClipboardData(text: _copyTextOf(info)));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  /// 用户点了才发起，失败也只写一句本地提示。
  Future<void> _diagnose(AgentErrorInfo info) async {
    final callback = widget.onDiagnose;
    if (callback == null || _diagnosing) return;
    final signature = _signatureOf(info);
    setState(() {
      _diagnosing = true;
      _diagnosisFor = signature;
      _diagnosis = null;
    });
    String text;
    try {
      final result = (await callback()).trim();
      text = result.isEmpty ? '诊断没有返回结果。' : result;
    } catch (_) {
      text = '诊断没有完成，请稍后再试。';
    }
    if (!mounted) return;
    setState(() {
      _diagnosing = false;
      _diagnosis = text;
    });
  }

  /// design.md §11.6 的错误文案表。未知分类返回 null，由调用方回退到原文。
  static String? _errorTextOf(AgentErrorInfo? info) {
    if (info == null) return null;
    return switch (info.kind) {
      AgentErrorKind.loginExpired => '登录已过期，请重新登录',
      AgentErrorKind.rateLimited => '请求太频繁，已自动重试仍失败，请稍后再试',
      AgentErrorKind.notConfigured => 'AI 服务暂未开通（服务端未配置），请联系管理员',
      AgentErrorKind.offline => '网络不可用，检查网络后重试',
      AgentErrorKind.timeout => '上游响应超时，重试一次',
      AgentErrorKind.unknown => null,
    };
  }

  /// 失败条：原因来自 facade，下一步由这里补一句可执行的动作。
  Widget _buildErrorBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = widget.errorInfo;
    final raw = widget.lastError?.trim() ?? '';
    // 有主机时用门面的友好文案：它已经写清是哪台服务器、哪一步失败。
    final host = info?.host.trim() ?? '';
    final text = host.isNotEmpty && raw.isNotEmpty
        ? raw
        : (_errorTextOf(info) ?? (raw.isEmpty ? '这一轮没有完成。' : raw));
    final hasDetails =
        info != null &&
        (info.statusCode != null ||
            info.detail.trim().isNotEmpty ||
            _canDiagnose(info));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  key: const ValueKey('chat-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (hasDetails) _buildErrorDetails(context, info),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                key: const ValueKey('chat-retry'),
                onPressed: _running ? null : widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 折叠的「详情」：状态码、多行说明、复制与诊断。不把堆栈放到主文案里。
  Widget _buildErrorDetails(BuildContext context, AgentErrorInfo info) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = info.detail.trim();
    final signature = _signatureOf(info);
    final diagnosis = _diagnosisFor == signature ? _diagnosis : null;
    final monospace = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: scheme.onErrorContainer,
    );
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('chat-error-details'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: scheme.onErrorContainer,
        collapsedIconColor: scheme.onErrorContainer,
        title: Text(
          '详情',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onErrorContainer,
          ),
        ),
        children: [
          if (info.statusCode != null)
            Text(
              '状态码：${info.statusCode}',
              key: const ValueKey('chat-error-status'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onErrorContainer,
              ),
            ),
          if (detail.isNotEmpty)
            SelectableText(
              detail,
              key: const ValueKey('chat-error-detail'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onErrorContainer,
              ),
            ),
          // 窄屏和放大字体下两个按钮换行，不横向溢出。
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey('chat-error-copy'),
                onPressed: () => _copyDetails(info),
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? '已复制' : '复制'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (_canDiagnose(info))
                TextButton.icon(
                  key: const ValueKey('chat-error-diagnose'),
                  onPressed: _diagnosing ? null : () => _diagnose(info),
                  icon: _diagnosing
                      ? const SizedBox.square(
                          key: ValueKey('chat-error-diagnose-progress'),
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(_diagnosing ? '正在诊断…' : '诊断连接'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (diagnosis != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              diagnosis,
              key: const ValueKey('chat-error-diagnosis'),
              style: monospace,
            ),
          ],
        ],
      ),
    );
  }
}

/// 一条用户消息的原始形态：正文加真实附件路径。
///
/// 数据来自 `AgentMessageView` 的类型化元数据（`sourceText`、`attachedPaths`），
/// 不从展示文本里反推路径。旧版持久化消息没有这些字段时，正文保持原文不变，
/// 附件视为空。
@immutable
class AgentUserMessage {
  const AgentUserMessage({required this.text, this.attachedPaths = const []});

  /// 用户真正输入的正文（`@路径` 展开之前）。
  final String text;

  /// 用户自己附加的文件路径，按当时的顺序。
  final List<String> attachedPaths;

  /// 从消息视图取编辑/重发需要的原文与附件。
  factory AgentUserMessage.of(AgentMessageView message) {
    final source = message.sourceText;
    return AgentUserMessage(
      // 没有元数据的旧消息：正文就是展示文本，原样保留。
      text: source ?? message.text,
      attachedPaths: message.attachedPaths,
    );
  }
}

/// 一条消息：用户气泡、助手正文或工具调用条目。
class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({
    super.key,
    required this.message,
    this.actions,
    this.onOpenFile,
    this.fileExists,
  });

  final AgentMessageView message;

  /// 消息动作；为空或全部不可用时只显示正文。
  final ChatMessageActions? actions;

  /// 点开工具写入的文件；为空表示卡片不可点。
  final void Function(String path)? onOpenFile;

  /// 文件现在是否还在磁盘上；为空时按存在处理。
  final bool Function(String path)? fileExists;

  /// 测试用：累计 build 次数，用来证明流式更新只重建末尾条目。
  static int debugBuildCount = 0;

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugBuildCount++;
      return true;
    }());
    final role = message.role;
    if (role == 'user') return _buildUser(context);
    if (role == 'tool') return _buildTool(context);
    return _buildAssistant(context);
  }

  Widget _buildUser(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            _MessageActionsButton(message: message, actions: actions),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 20),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: message.isError
              ? Border.all(color: scheme.error, width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.trim().isNotEmpty)
              SelectableText(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: message.isError ? scheme.error : null,
                ),
              ),
            if (message.aiGenerated && message.text.trim().isNotEmpty)
              const AiGeneratedBadge(),
            if (message.pending)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '处理中…',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            _MessageActionsButton(message: message, actions: actions),
          ],
        ),
      ),
    );
  }

  Widget _buildTool(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = message.toolName ?? '';
    final failed = message.isError;
    final pending = message.pending;
    final color = pending
        ? scheme.primary
        : (failed ? scheme.error : scheme.primary);
    final label = pending ? '执行中' : (failed ? '失败' : '完成');
    final detail = message.text.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 运行中转圈，完成后对勾或叉（design.md §11.6 第 4 条）。
              if (pending)
                SizedBox(
                  key: ValueKey('tool-spinner-${message.id}'),
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(
                  key: ValueKey('tool-done-${message.id}'),
                  failed ? Icons.cancel_outlined : Icons.check_circle_outline,
                  size: 16,
                  color: color,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vibeToolLabel(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
          if (message.changedPaths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final path in message.changedPaths)
                    _ChangedFileCard(
                      path: path,
                      available: fileExists?.call(path) ?? true,
                      onTap: onOpenFile == null
                          ? null
                          : () => onOpenFile!(path),
                    ),
                ],
              ),
            ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                detail,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: failed ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一条工具条目里被写入的一个文件。
///
/// 可点时打开编辑器里的那个文件；文件已被删除时只显示禁用状态，
/// 不确定剩下一个能点的死路径。
class _ChangedFileCard extends StatelessWidget {
  const _ChangedFileCard({
    required this.path,
    required this.available,
    this.onTap,
  });

  final String path;

  /// 文件现在是否还在磁盘上。
  final bool available;

  final VoidCallback? onTap;

  bool get _enabled => available && onTap != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = _enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('chat-file-card-$path'),
          onTap: _enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: _enabled ? 1 : 0.5,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available
                      ? Icons.description_outlined
                      : Icons.delete_outline,
                  size: 16,
                  color: _enabled ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: foreground,
                    ),
                  ),
                ),
                if (!available)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '已删除',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (_enabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: scheme.onSurfaceVariant,
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

/// 一条消息可以做的动作。菜单项按可用性显示。
@immutable
class ChatMessageActions {
  const ChatMessageActions({
    this.canEdit = false,
    this.canResend = false,
    this.busy = false,
    this.onCopy,
    this.onEdit,
    this.onResend,
  });

  /// 运行中不允许编辑与重发，避免和正在跑的一轮抢执行槽。
  final bool canEdit;
  final bool canResend;
  final bool busy;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onResend;

  bool get isEmpty => onCopy == null && onEdit == null && onResend == null;
}

/// 消息右上角的紧凑动作菜单。触屏和鼠标都能用。
///
/// 菜单只用图标按钮，不占正文宽度；动作不可用时菜单项变灰并说明原因。
class _MessageActionsButton extends StatelessWidget {
  const _MessageActionsButton({required this.message, this.actions});

  final AgentMessageView message;
  final ChatMessageActions? actions;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    if (actions == null || actions.isEmpty) return const SizedBox.shrink();
    final blocked =
        actions.busy && (actions.onEdit != null || actions.onResend != null);
    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<String>(
        key: ValueKey('chat-actions-${message.id}'),
        tooltip: '消息操作',
        icon: Icon(
          Icons.more_horiz,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        iconSize: 18,
        padding: EdgeInsets.zero,
        // 触屏与鼠标都需要 44 像素的点击区。
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onSelected: (value) {
          switch (value) {
            case 'copy':
              actions.onCopy?.call();
            case 'edit':
              actions.onEdit?.call();
            case 'resend':
              actions.onResend?.call();
          }
        },
        itemBuilder: (context) => [
          if (actions.onCopy != null)
            const PopupMenuItem<String>(value: 'copy', child: Text('复制')),
          if (actions.onEdit != null)
            PopupMenuItem<String>(
              value: 'edit',
              enabled: actions.canEdit,
              child: const Text('编辑后重发'),
            ),
          if (actions.onResend != null)
            PopupMenuItem<String>(
              value: 'resend',
              enabled: actions.canResend,
              child: const Text('重发'),
            ),
          if (blocked)
            const PopupMenuItem<String>(
              value: 'busy',
              enabled: false,
              child: Text('等这一轮结束后可用'),
            ),
        ],
      ),
    );
  }
}
