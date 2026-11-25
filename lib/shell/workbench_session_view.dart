import 'dart:async';

import 'package:flutter/material.dart';

import '../harness/harness_host.dart';
import '../harness/hub/agents_index.dart';
import '../harness/hub/harness_hub.dart';
import '../harness/ui/hub_chat_view.dart';
import 'large_screen_controller.dart';

/// Center-area chat for an Agent session that has no usable editor project.
///
/// The workbench owns the overlay. This view owns only the session view when it
/// closes; it never stops the underlying Agent session.
class WorkbenchSessionView extends StatefulWidget {
  const WorkbenchSessionView({
    super.key,
    required this.row,
    required this.hub,
    required this.onClose,
  });

  final AgentsIndexRow row;
  final HarnessHub hub;
  final VoidCallback onClose;

  @override
  State<WorkbenchSessionView> createState() => _WorkbenchSessionViewState();
}

class _WorkbenchSessionViewState extends State<WorkbenchSessionView> {
  HarnessSessionHandle? _handle;
  Object? _error;
  int _openGeneration = 0;
  Future<HarnessSessionHandle>? _opening;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(WorkbenchSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hub == widget.hub &&
        oldWidget.row.rowKey == widget.row.rowKey) {
      return;
    }
    final oldHandle = _handle;
    _handle = null;
    _error = null;
    if (oldHandle != null) {
      final oldHub = oldWidget.hub;
      scheduleMicrotask(() => _releaseHandle(oldHub, oldHandle));
    }
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_openGeneration;
    if (mounted) {
      setState(() {
        _handle = null;
        _error = null;
      });
    }
    final hub = widget.hub;
    final session = widget.row.session;
    // Serialize replacement views within this widget. HarnessHub deliberately
    // rejects concurrent opens; switching during an open should not strand the
    // new selection on that temporary busy error.
    final previous = _opening;
    if (previous != null) {
      try {
        await previous;
      } on Object {
        // A failed previous selection does not prevent opening the new one.
      }
    }
    if (!mounted || _closed || generation != _openGeneration) return;
    try {
      final pending = hub.openSession(session);
      _opening = pending;
      final handle = await pending;
      if (!mounted || _closed || generation != _openGeneration) {
        await _releaseHandle(hub, handle);
        return;
      }
      setState(() => _handle = handle);
    } on Object catch (error) {
      if (!mounted || generation != _openGeneration) return;
      setState(() => _error = error);
    } finally {
      if (generation == _openGeneration) _opening = null;
    }
  }

  Future<void> _releaseHandle(
    HarnessHub hub,
    HarnessSessionHandle handle,
  ) async {
    if (identical(hub.activeHandle, handle)) await hub.closeActiveSession();
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _openGeneration++;
    final handle = _handle;
    _handle = null;
    if (handle != null) unawaited(_releaseHandle(widget.hub, handle));
    widget.onClose();
  }

  @override
  void dispose() {
    _openGeneration++;
    final hub = widget.hub;
    final handle = _handle;
    if (handle != null) {
      // Recheck identity after the frame: the editor may have opened another
      // session through this shared hub while the overlay was being removed.
      scheduleMicrotask(() => _releaseHandle(hub, handle));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = _handle;
    return Column(
      key: const ValueKey('workbench-session-view'),
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: SizedBox(
            key: const ValueKey('workbench-session-header'),
            height: LargeScreenScope.isDesktop(context) ? 40 : 48,
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.forum_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.row.session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    widget.row.hostLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('workbench-session-close'),
                  tooltip: '关闭会话',
                  constraints: BoxConstraints.tightFor(
                    width: LargeScreenScope.isDesktop(context) ? 40 : 48,
                    height: LargeScreenScope.isDesktop(context) ? 40 : 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: _close,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: handle != null
              ? HubChatView(handle: handle)
              : _error == null
              ? const Center(
                  key: ValueKey('workbench-session-loading'),
                  child: CircularProgressIndicator(),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      key: const ValueKey('workbench-session-open-error'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline),
                        const SizedBox(height: 8),
                        Text('无法打开此会话：$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const ValueKey('workbench-session-retry'),
                          onPressed: _open,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
