import 'package:flutter/material.dart';

import '../services/studio_profile.dart';
import 'editor_debug_controller.dart';

/// Retains actual stream text, without retaining an unbounded run history.
/// Appenders own line separators; chunks are otherwise preserved exactly.
class EditorOutputBuffer extends ChangeNotifier {
  static const maxUnits = 128 * 1024;

  String _text = '';
  bool _truncated = false;
  bool _disposed = false;

  String get text => _text;
  bool get truncated => _truncated;

  void append(String value) {
    if (_disposed || value.isEmpty) return;
    if (value.length >= maxUnits) {
      var start = value.length - maxUnits;
      if (_low(value.codeUnitAt(start)) &&
          (start > 0
              ? _high(value.codeUnitAt(start - 1))
              : _text.isNotEmpty &&
                    _high(_text.codeUnitAt(_text.length - 1)))) {
        start++;
      }
      _truncated = _truncated || _text.isNotEmpty || start > 0;
      _text = value.substring(start);
    } else {
      final retained = _tail(_text + value);
      _text = retained.text;
      _truncated = _truncated || retained.truncated;
    }
    notifyListeners();
  }

  void clear() {
    if (_disposed || (_text.isEmpty && !_truncated)) return;
    _text = '';
    _truncated = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

bool _high(int unit) => unit >= 0xd800 && unit <= 0xdbff;
bool _low(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

({String text, bool truncated}) _tail(String text) {
  if (text.length <= EditorOutputBuffer.maxUnits) {
    return (text: text, truncated: false);
  }
  var start = text.length - EditorOutputBuffer.maxUnits;
  if (_low(text.codeUnitAt(start)) && _high(text.codeUnitAt(start - 1))) {
    start++;
  }
  return (text: text.substring(start), truncated: true);
}

class EditorOutputPanel extends StatelessWidget {
  const EditorOutputPanel({
    super.key,
    required this.output,
    required this.debug,
    required this.onClose,
  });

  final EditorOutputBuffer output;
  final EditorDebugController debug;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([output, debug]),
    builder: (context, _) {
      final snapshot = debug.snapshot;
      return _Panel(
        title: '输出',
        onClose: onClose,
        closeKey: 'close-editor-output',
        clearTooltip: '清空运行与工具输出',
        onClear: output.text.isEmpty && !output.truncated ? null : output.clear,
        children: [
          if (output.text.isNotEmpty || output.truncated)
            _TextSection(
              label: '运行与工具',
              text: output.text,
              textKey: 'editor-run-output',
              retainedTruncated: output.truncated,
            ),
          if (snapshot != null) ...[
            Text(
              '调试状态：${_phase(snapshot.phase)} · '
              '退出码：${snapshot.exitCode?.toString() ?? '未提供'}',
            ),
            if (snapshot.stdout.isNotEmpty || snapshot.stdoutTruncated)
              _TextSection(
                label: '调试 stdout',
                text: snapshot.stdout,
                textKey: 'editor-debug-stdout',
                backendTruncated: snapshot.stdoutTruncated,
              ),
            if (snapshot.stderr.isNotEmpty || snapshot.stderrTruncated)
              _TextSection(
                label: '调试 stderr',
                text: snapshot.stderr,
                textKey: 'editor-debug-stderr',
                backendTruncated: snapshot.stderrTruncated,
              ),
          ],
          if (output.text.isEmpty &&
              (snapshot?.stdout.isEmpty ?? true) &&
              (snapshot?.stderr.isEmpty ?? true))
            const Text('尚无运行、工具或调试输出'),
        ],
      );
    },
  );
}

class EditorDebugConsolePanel extends StatelessWidget {
  const EditorDebugConsolePanel({
    super.key,
    required this.previewConsole,
    required this.debug,
    required this.onClose,
  });

  final EditorOutputBuffer previewConsole;
  final EditorDebugController debug;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([previewConsole, debug]),
    builder: (context, _) {
      final snapshot = debug.snapshot;
      final console = snapshot?.console ?? '';
      final message = snapshot?.message ?? '';
      final error = debug.error ?? '';
      return _Panel(
        title: '调试控制台',
        onClose: onClose,
        closeKey: 'close-editor-debug-console',
        clearTooltip: '清空预览日志',
        onClear: previewConsole.text.isEmpty && !previewConsole.truncated
            ? null
            : previewConsole.clear,
        children: [
          const Text('只读日志；当前后端不提供表达式求值。'),
          if (previewConsole.text.isNotEmpty || previewConsole.truncated)
            _TextSection(
              label: '预览日志',
              text: previewConsole.text,
              textKey: 'editor-preview-console',
              retainedTruncated: previewConsole.truncated,
            ),
          if (console.isNotEmpty || (snapshot?.consoleTruncated ?? false))
            _TextSection(
              label: '调试器日志',
              text: console,
              textKey: 'editor-debug-console',
              backendTruncated: snapshot?.consoleTruncated ?? false,
            ),
          if (message.isNotEmpty)
            _TextSection(
              label: '调试器消息',
              text: message,
              textKey: 'editor-debug-message',
            ),
          if (error.isNotEmpty && error != message)
            _TextSection(
              label: '调试操作反馈',
              text: error,
              textKey: 'editor-debug-error',
            ),
          if (previewConsole.text.isEmpty &&
              console.isEmpty &&
              message.isEmpty &&
              error.isEmpty)
            const Text('尚无预览日志或调试器消息'),
        ],
      );
    },
  );
}

/// Lists only the preview session supplied by the editor. This widget performs
/// no port discovery, socket operations, URL launches or network requests.
class EditorPortsPanel extends StatefulWidget {
  const EditorPortsPanel({
    super.key,
    required this.preview,
    required this.onStop,
    required this.onClose,
  });

  final WebPreviewSession? preview;
  final Future<void> Function() onStop;
  final VoidCallback onClose;

  @override
  State<EditorPortsPanel> createState() => _EditorPortsPanelState();
}

class _EditorPortsPanelState extends State<EditorPortsPanel> {
  bool _stopping = false;
  WebPreviewSession? _stopped;
  String? _error;

  @override
  void didUpdateWidget(EditorPortsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preview, widget.preview)) _error = null;
  }

  Future<void> _stop() async {
    final preview = widget.preview;
    if (_stopping || preview == null || identical(preview, _stopped)) return;
    final stop = widget.onStop;
    setState(() {
      _stopping = true;
      _error = null;
    });
    try {
      await stop();
      if (mounted && identical(widget.preview, preview)) {
        setState(() => _stopped = preview);
      }
    } on Object catch (error) {
      if (mounted && identical(widget.preview, preview)) {
        setState(() => _error = '停止预览失败：$error');
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = identical(widget.preview, _stopped) ? null : widget.preview;
    String? url;
    String? port;
    String? addressError;
    if (preview != null) {
      try {
        url = preview.url;
        final parsed = Uri.tryParse(url);
        port = parsed != null && parsed.hasPort
            ? parsed.port.toString()
            : 'URL 未显式提供';
      } on Object catch (error) {
        addressError = '无法读取预览监听地址：$error';
      }
    }
    return _Panel(
      title: '端口',
      onClose: widget.onClose,
      closeKey: 'close-editor-ports',
      children: [
        if (preview == null)
          const Text('当前没有由应用启动的预览监听器')
        else ...[
          const Text('应用预览监听器'),
          if (url != null)
            _TextSection(label: '地址', text: url, textKey: 'editor-preview-url'),
          if (port != null) Text('端口：$port'),
          if (addressError != null) SelectableText(addressError),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('editor-preview-stop'),
              onPressed: _stopping ? null : _stop,
              icon: _stopping
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop, size: 18),
              label: Text(_stopping ? '停止中…' : '停止'),
            ),
          ),
        ],
        if (_error != null) SelectableText(_error!),
      ],
    );
  }
}

String _phase(DebugPhase phase) => switch (phase) {
  DebugPhase.starting => '启动中',
  DebugPhase.running => '运行中',
  DebugPhase.paused => '已暂停',
  DebugPhase.stopping => '停止中',
  DebugPhase.terminated => '已结束',
  DebugPhase.failed => '失败',
};

class _TextSection extends StatelessWidget {
  const _TextSection({
    required this.label,
    required this.text,
    required this.textKey,
    this.retainedTruncated = false,
    this.backendTruncated = false,
  });

  final String label;
  final String text;
  final String textKey;
  final bool retainedTruncated;
  final bool backendTruncated;

  @override
  Widget build(BuildContext context) {
    final shown = _tail(text);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          if (backendTruncated) const Text('后端已截断，显示保留的输出'),
          if (retainedTruncated || shown.truncated)
            const Text('面板仅保留最近 128 Ki UTF-16 单元以内的文本'),
          SelectableText(
            shown.text,
            key: ValueKey(textKey),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.onClose,
    required this.closeKey,
    required this.children,
    this.onClear,
    this.clearTooltip,
  });

  final String title;
  final VoidCallback onClose;
  final String closeKey;
  final List<Widget> children;
  final VoidCallback? onClear;
  final String? clearTooltip;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 240.0;
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 600.0;
        final compact = height < 64;
        final headerHeight = height < 48 ? height : 48.0;
        return SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: Column(
              children: [
                SizedBox(
                  height: headerHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (!compact && width >= 128 && clearTooltip != null)
                        IconButton(
                          tooltip: clearTooltip,
                          onPressed: onClear,
                          icon: const Icon(Icons.clear_all),
                        ),
                      IconButton(
                        key: ValueKey(closeKey),
                        tooltip: '关闭$title面板',
                        constraints: BoxConstraints.tightFor(
                          width: headerHeight < 40 ? headerHeight : 40,
                          height: headerHeight,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: headerHeight < 24 ? headerHeight : 20,
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (!compact)
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      children: [
                        for (final child in children)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: child,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
