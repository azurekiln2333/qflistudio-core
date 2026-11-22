// 一个 hub 会话的详情：标题、状态、对话与终端两个标签。
//
// 关闭视图只调用 detach()，会话继续在主机上跑；结束会话要在这里先让用户
// 确认（AC5）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../harness_host.dart';
import '../hub/harness_hub.dart';
import 'hub_chat_view.dart';
import 'hub_status.dart';
import 'hub_terminal_view.dart';

/// 会话详情视图。
class HubSessionView extends StatefulWidget {
  const HubSessionView({
    super.key,
    required this.hub,
    required this.session,
    this.compact = false,
    this.onClose,
  });

  final HarnessHub hub;
  final HarnessSessionInfo session;

  /// 手机端：顶部显示返回、终端底部显示按键栏。
  final bool compact;

  /// 关闭视图后通知外层（例如把面板切回列表）。
  final VoidCallback? onClose;

  @override
  State<HubSessionView> createState() => _HubSessionViewState();
}

class _HubSessionViewState extends State<HubSessionView> {
  HarnessSessionHandle? _handle;
  Object? _error;
  int _openToken = 0;
  int _tab = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // hub 已经打开过这个会话时直接接上：第一帧就画出页头与内容，不再闪一次
    // 转圈，也不再跟异步打开抢帧。
    if (_adoptActiveHandle()) return;
    unawaited(_open());
  }

  /// 这个会话已经是 hub 的当前视图时，同步拿它的句柄。
  bool _adoptActiveHandle() {
    final active = widget.hub.activeHandle;
    if (active == null ||
        active.info.id != widget.session.id ||
        active.info.hostId != widget.session.hostId) {
      return false;
    }
    _handle = active;
    return true;
  }

  @override
  void didUpdateWidget(HubSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.hostId != widget.session.hostId) {
      _tab = 0;
      if (_adoptActiveHandle()) {
        setState(() {});
        return;
      }
      unawaited(_open());
    }
  }

  Future<void> _open() async {
    final token = ++_openToken;
    // 第一帧不需要 setState：两个字段本来就是空的，重建也是同一棵树。
    // 重新打开（重试、换会话）时才要把旧状态清掉。
    if (_error != null || _handle != null) {
      setState(() {
        _error = null;
        _handle = null;
      });
    }
    try {
      final handle = await widget.hub.openSession(widget.session);
      if (!mounted || token != _openToken) return;
      setState(() => _handle = handle);
    } on Object catch (error) {
      if (!mounted || token != _openToken) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    // 只释放视图。会话本身留在主机上，重新打开能接上。
    //
    // 放到微任务里：dispose 期间不能触发上层重建。
    final active = widget.hub.activeSession;
    if (active != null &&
        active.id == widget.session.id &&
        active.hostId == widget.session.hostId) {
      scheduleMicrotask(() => widget.hub.closeActiveSession());
    }
    super.dispose();
  }

  Future<void> _close() async {
    await widget.hub.closeActiveSession();
    widget.onClose?.call();
  }

  /// 结束会话前必须确认。按钮文案说明后果，默认动作是取消。
  Future<void> _confirmStop() async {
    final handle = _handle;
    if (handle == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('hub-stop-dialog'),
        title: const Text('结束会话'),
        content: Text('「${handle.info.title}」会在这台电脑上结束，正在运行的任务会被终止。'),
        actions: [
          TextButton(
            key: const ValueKey('hub-stop-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('hub-stop-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('结束会话'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await handle.stop();
      await widget.hub.closeActiveSession();
      widget.onClose?.call();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    final error = _error;
    if (handle == null) {
      return Center(
        child: error == null
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '打不开这个会话：$error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      key: const ValueKey('hub-session-retry'),
                      onPressed: _open,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
      );
    }
    final hasTranscript = handle.transcript != null;
    final hasTerminal = handle.terminal != null;
    // 标签和内容是同一份列表，索引不会错位。
    final pages = <({String label, Widget body})>[
      if (hasTranscript)
        (
          label: '对话',
          // 结束会话的确认在 _confirmStop 里做，输入卡片只把点击转过来。
          body: HubChatView(
            handle: handle,
            onStop: _busy ? null : () => unawaited(_confirmStop()),
          ),
        ),
      if (hasTerminal)
        (
          label: '终端',
          body: HubTerminalView(
            channel: handle.terminal!,
            compact: widget.compact,
          ),
        ),
    ];
    final index = pages.isEmpty ? 0 : _tab.clamp(0, pages.length - 1);
    return ValueListenableBuilder<HarnessSessionStatus>(
      valueListenable: handle.status,
      builder: (context, status, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, handle, status),
            if (pages.length > 1)
              _tabBar([
                for (var i = 0; i < pages.length; i++)
                  _tabButton(pages[i].label, i),
              ]),
            Expanded(
              child: pages.isEmpty
                  ? Center(
                      child: Text(
                        '这个会话没有可显示的对话或终端。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : IndexedStack(
                      index: index,
                      children: [for (final page in pages) page.body],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    HarnessSessionHandle handle,
    HarnessSessionStatus status,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cwd = handle.info.cwd?.trim();
    final canStop = handle.info.capabilities.contains(HarnessCapability.stop);
    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(
          children: [
            if (widget.compact)
              IconButton(
                key: const ValueKey('hub-session-back'),
                tooltip: '返回会话列表',
                onPressed: _close,
                icon: const Icon(Icons.arrow_back),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          handle.info.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      HarnessStatusChip(status: status),
                    ],
                  ),
                  if (cwd != null && cwd.isNotEmpty)
                    Text(
                      cwd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (canStop)
              IconButton(
                key: const ValueKey('hub-session-stop'),
                tooltip: '结束会话',
                onPressed: _busy ? null : _confirmStop,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            IconButton(
              key: const ValueKey('hub-session-close'),
              tooltip: '关闭视图（会话继续运行）',
              onPressed: _close,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        key: ValueKey('hub-tab-$index'),
        onPressed: () => setState(() => _tab = index),
        style: TextButton.styleFrom(
          foregroundColor: _tab == index
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          minimumSize: const Size(64, 36),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _tabBar(List<Widget> tabs) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(children: tabs),
    );
  }
}
