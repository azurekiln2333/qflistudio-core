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

  final String emptyTitle;
  final String emptyHint;
  final Widget? emptyAction;
  final EdgeInsets padding;

  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
}

class _ChatTranscriptState extends State<ChatTranscript> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  String _lastTail = '';
  double _lastPixels = 0;

  /// 诊断结果和它对应的那次失败。失败变了就丢掉旧结果，避免张冠李戴。
  String? _diagnosis;
  String? _diagnosisFor;
  bool _diagnosing = false;

  /// 刚复制过详情，按钮上给一句回执。
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.messages.length;
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
    final messages = widget.messages;
    final tail = messages.isEmpty ? '' : _tailOf(messages.last);
    if (messages.length != _lastCount || tail != _lastTail) {
      _lastCount = messages.length;
      _lastTail = tail;
      _scheduleScrollToBottom();
    }
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
    if (cached != null && previous != null && _sameView(previous, message)) {
      return cached;
    }
    if (_tiles.length >= _tileCacheLimit) {
      _tiles.clear();
      _rendered.clear();
    }
    final tile = ChatMessageTile(
      key: ValueKey('chat-message-${message.id}'),
      message: message,
    );
    _tiles[message.id] = tile;
    _rendered[message.id] = message;
    return tile;
  }

  /// 内容没变就不重建。逐字段比较，不依赖 facade 复用同一个视图对象。
  static bool _sameView(AgentMessageView a, AgentMessageView b) =>
      a.role == b.role &&
      a.text == b.text &&
      a.toolName == b.toolName &&
      a.isError == b.isError &&
      a.pending == b.pending &&
      a.aiGenerated == b.aiGenerated &&
      listEquals(a.changedPaths, b.changedPaths);

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
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
    final leading = showEarlier ? 1 : 0;
    final extras = (approval == null ? 0 : 1) + (failed ? 1 : 0);
    final list = ListView.builder(
      controller: _scroll,
      padding: widget.padding,
      itemCount: leading + messages.length + extras,
      itemBuilder: (context, index) {
        if (showEarlier && index == 0) return _buildEarlierButton(context);
        final position = index - leading;
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
      },
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

/// 一条消息：用户气泡、助手正文或工具调用条目。
class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({super.key, required this.message});

  final AgentMessageView message;

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          message.text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
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
              child: Text(
                message.changedPaths.join('\n'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
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
