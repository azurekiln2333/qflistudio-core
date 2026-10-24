import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../services/debug_session.dart';
import 'editor_debug_controller.dart';
import 'open_file.dart';

class EditorDebugPanel extends StatefulWidget {
  const EditorDebugPanel({
    super.key,
    required this.debug,
    required this.runBusy,
    required this.onStart,
    required this.onClose,
  });

  final EditorDebugController debug;
  final bool runBusy;
  final Future<void> Function(bool stopOnEntry) onStart;
  final VoidCallback onClose;

  @override
  State<EditorDebugPanel> createState() => _EditorDebugPanelState();
}

class _EditorDebugPanelState extends State<EditorDebugPanel> {
  bool _stopOnEntry = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.debug,
    builder: (context, _) {
      final debug = widget.debug;
      final snapshot = debug.snapshot;
      final capabilities = debug.capabilities;
      final file = debug.editor.current;
      final paused = debug.paused;
      final frame = paused ? debug.selectedFrame : null;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 12),
                const Expanded(child: Text('调试')),
                IconButton(
                  tooltip: '关闭调试面板',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Text(debug.debugger?.displayName ?? '本产品未提供离线调试器'),
                  if (debug.error case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (debug.busy || snapshot != null)
                    Text(
                      debug.stopping
                          ? '正在停止并等待资源释放…'
                          : debug.starting
                          ? '正在启动…'
                          : snapshot?.isTerminal == true && debug.busy
                          ? '正在等待调试器清理…'
                          : switch (snapshot?.phase) {
                              DebugPhase.paused =>
                                paused ? '已暂停' : '暂停状态已失效，等待调试器更新…',
                              DebugPhase.running => '运行中',
                              DebugPhase.terminated =>
                                '已结束${snapshot?.exitCode == null ? '' : ' · 退出码 ${snapshot!.exitCode}'}',
                              DebugPhase.failed => '调试失败',
                              _ => '准备调试',
                            },
                    ),
                  if (snapshot?.message case final message?) Text(message),
                  if (debug.projectPath case final root?) Text(root),
                  Wrap(
                    spacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('editor-debug-start'),
                        onPressed:
                            !debug.busy &&
                                !widget.runBusy &&
                                debug.debugger != null &&
                                file != null
                            ? () => unawaited(widget.onStart(_stopOnEntry))
                            : null,
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('开始调试'),
                      ),
                      _command(
                        debug,
                        DebugCommand.resume,
                        '继续',
                        Icons.play_arrow,
                      ),
                      if (capabilities?.supportsPause == true)
                        _command(debug, DebugCommand.pause, '暂停', Icons.pause),
                      if (capabilities?.supportsStepOver == true)
                        _command(
                          debug,
                          DebugCommand.stepOver,
                          '单步跳过',
                          Icons.redo,
                        ),
                      if (capabilities?.supportsStepInto == true)
                        _command(
                          debug,
                          DebugCommand.stepInto,
                          '单步进入',
                          Icons.arrow_downward,
                        ),
                      if (capabilities?.supportsStepOut == true)
                        _command(
                          debug,
                          DebugCommand.stepOut,
                          '单步跳出',
                          Icons.arrow_upward,
                        ),
                      IconButton(
                        key: const ValueKey('editor-debug-stop'),
                        tooltip: '停止调试',
                        onPressed:
                            debug.busy &&
                                (!debug.stopping || debug.error != null)
                            ? () => unawaited(debug.stop())
                            : null,
                        icon: const Icon(Icons.stop),
                      ),
                      TextButton.icon(
                        key: const ValueKey('editor-debug-toggle-breakpoint'),
                        onPressed:
                            file != null && debug.canToggleBreakpoint(file)
                            ? () {
                                final lines = file.controller.codeLines;
                                final index =
                                    file.controller.selection.extentIndex;
                                if (index < 0 || index >= lines.length) return;
                                unawaited(
                                  debug.toggleBreakpoint(
                                    file,
                                    lines.index2lineIndex(index) + 1,
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.circle, size: 12),
                        label: const Text('切换当前行断点'),
                      ),
                    ],
                  ),
                  if (capabilities?.supportsStopOnEntry == true)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('入口暂停'),
                      value: _stopOnEntry,
                      onChanged: debug.busy
                          ? null
                          : (value) =>
                                setState(() => _stopOnEntry = value ?? false),
                    ),
                  if (capabilities != null)
                    Text(switch (capabilities.outputDelivery) {
                      DebugOutputDelivery.live => '程序输出显示在 Output',
                      DebugOutputDelivery.pauseOrExit =>
                        '程序输出在暂停或结束时更新到 Output',
                      DebugOutputDelivery.exitOnly => '程序输出在执行结束后显示在 Output',
                    }),
                  if (capabilities?.breakpointUpdate ==
                      DebugBreakpointUpdate.launchOnly)
                    const Text('断点在启动时生效；结束后可修改下一次调试的断点'),
                  if (debug.breakpoints.isNotEmpty) ...[
                    const Divider(),
                    const Text('断点'),
                    for (final point in debug.breakpoints)
                      _breakpoint(debug, point),
                  ],
                  if (paused &&
                      snapshot != null &&
                      capabilities?.supportsStackFrames == true) ...[
                    const Divider(),
                    const Text('调用栈'),
                    if (snapshot.threadsTruncated) const Text('线程列表已截断'),
                    if (snapshot.framesTruncated) const Text('调用栈已截断'),
                    if (snapshot.frames.isEmpty) const Text('当前暂停没有可用的调用栈'),
                    for (final candidate in snapshot.frames)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        selected: identical(candidate, frame),
                        title: Text(candidate.name),
                        subtitle: Text(
                          '${candidate.threadId}${candidate.location == null ? '' : ' · ${candidate.location!.filePath}:${candidate.location!.line}'}',
                        ),
                        onTap: () {
                          debug.selectFrame(candidate);
                          if (candidate.location != null) {
                            unawaited(debug.navigate(candidate));
                          }
                        },
                      ),
                  ],
                  if (paused &&
                      capabilities?.supportsVariables == true &&
                      frame != null) ...[
                    const Divider(),
                    const Text('局部变量（只读）'),
                    if (frame.localsUnavailableReason case final reason?)
                      Text(reason),
                    if (frame.localsTruncated) const Text('局部变量已截断'),
                    if (frame.locals.isEmpty &&
                        frame.localsUnavailableReason == null)
                      const Text('无局部变量'),
                    for (final value in frame.locals) _DebugValue(value: value),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _command(
    EditorDebugController debug,
    DebugCommand command,
    String label,
    IconData icon,
  ) => IconButton(
    key: ValueKey('editor-debug-${command.name}'),
    tooltip: label,
    onPressed: debug.canCommand(command)
        ? () => unawaited(debug.command(command))
        : null,
    icon: Icon(icon),
  );

  Widget _breakpoint(EditorDebugController debug, DebugBreakpoint point) {
    final result = debug.breakpointFor(point.filePath, point.line);
    final status = switch (result?.status) {
      DebugBreakpointStatus.verified => '已验证',
      DebugBreakpointStatus.rejected => '已拒绝',
      _ => '待验证',
    };
    return Text(
      '${point.filePath}:${point.line} · $status${result?.reason == null ? '' : ' · ${result!.reason}'}',
    );
  }
}

class _DebugValue extends StatelessWidget {
  const _DebugValue({required this.value});
  final DebugVariable value;
  @override
  Widget build(BuildContext context) {
    final label =
        '${value.name} (${value.type}) = ${value.value}${value.truncated ? ' [已截断]' : ''}';
    if (value.children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SelectableText(
          '$label${value.unavailableReason == null ? '' : '\n${value.unavailableReason}'}',
        ),
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: value.unavailableReason == null
          ? null
          : Text(value.unavailableReason!),
      children: [for (final child in value.children) _DebugValue(value: child)],
    );
  }
}

/// The hit target and marks use physical source lines, including folded chunks.
class EditorDebugGutter extends StatelessWidget {
  const EditorDebugGutter({
    super.key,
    required this.debug,
    required this.file,
    required this.notifier,
  });
  final EditorDebugController debug;
  final OpenFile file;
  final CodeIndicatorValueNotifier notifier;

  static const width = 26.0;

  Key get hitTargetKey => ValueKey('editor-debug-gutter-${file.path}');

  /// Maps current local geometry to a one-based physical source line. Wrapped
  /// visual lines and folded children share their visible parent's source line.
  /// A source edit may precede the next render layout, so stale indices are
  /// ignored rather than being used to index the shortened source.
  int? lineAt(Offset localPosition) {
    if (!localPosition.dx.isFinite ||
        !localPosition.dy.isFinite ||
        localPosition.dx < 0 ||
        localPosition.dx >= width ||
        localPosition.dy < 0) {
      return null;
    }
    final lines = file.controller.codeLines;
    for (final paragraph
        in notifier.value?.paragraphs ?? <CodeLineRenderParagraph>[]) {
      if (!paragraph.inVerticalRange(localPosition)) continue;
      return _physicalRange(paragraph, lines)?.first;
    }
    return null;
  }

  /// Bounds of the mark's first visual line, relative to [hitTargetKey]. A
  /// folded child returns its visible parent's bounds; offscreen or stale
  /// paragraphs return null. Consumers may clip these bounds to the gutter.
  Rect? lineBounds(int oneBasedPhysicalLine) {
    if (oneBasedPhysicalLine < 1) return null;
    final lines = file.controller.codeLines;
    for (final paragraph
        in notifier.value?.paragraphs ?? <CodeLineRenderParagraph>[]) {
      final range = _physicalRange(paragraph, lines);
      if (range != null &&
          oneBasedPhysicalLine >= range.first &&
          oneBasedPhysicalLine < range.end) {
        return Rect.fromLTWH(
          0,
          paragraph.top,
          width,
          paragraph.preferredLineHeight,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    String canonical;
    try {
      canonical = File(file.path).resolveSymbolicLinksSync();
    } on FileSystemException {
      canonical = file.path;
    }
    return SizedBox(
      width: width,
      height: double.infinity,
      child: GestureDetector(
        key: hitTargetKey,
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final line = lineAt(details.localPosition);
          if (line != null && debug.canToggleBreakpoint(file)) {
            unawaited(debug.toggleBreakpoint(file, line));
          }
        },
        child: CustomPaint(
          painter: _DebugGutterPainter(
            debug: debug,
            file: file,
            notifier: notifier,
            canonicalPath: canonical,
            scheme: Theme.of(context).colorScheme,
          ),
        ),
      ),
    );
  }
}

({int first, int end})? _physicalRange(
  CodeLineRenderParagraph paragraph,
  CodeLines lines,
) {
  final index = paragraph.index;
  if (index < 0 || index >= lines.length) return null;
  final first = lines.index2lineIndex(index) + 1;
  if (first < 1) return null;
  return (first: first, end: first + lines[index].lineCount);
}

class _DebugGutterPainter extends CustomPainter {
  _DebugGutterPainter({
    required this.debug,
    required this.file,
    required this.notifier,
    required this.canonicalPath,
    required this.scheme,
  }) : super(repaint: Listenable.merge([debug, notifier, file.controller]));

  final EditorDebugController debug;
  final OpenFile file;
  final CodeIndicatorValueNotifier notifier;
  final String canonicalPath;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <int, DebugBreakpointStatus>{
      for (final point in debug.breakpoints)
        if (p.equals(point.filePath, canonicalPath))
          point.line: DebugBreakpointStatus.pending,
      for (final point
          in debug.snapshot?.breakpoints ?? <DebugBreakpointResult>[])
        if (p.equals(point.requested.filePath, canonicalPath))
          point.requested.line: point.status,
    };
    // This also rejects invalidated pause tokens and text changed since launch.
    // Resolve once per repaint, never once for every displayed source line.
    final executionLine = debug.executionLocationFor(file)?.line;
    final lines = file.controller.codeLines;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final paragraph
        in notifier.value?.paragraphs ?? <CodeLineRenderParagraph>[]) {
      final range = _physicalRange(paragraph, lines);
      if (range == null) continue;
      DebugBreakpointStatus? mark;
      for (final entry in points.entries) {
        if (entry.key < range.first || entry.key >= range.end) continue;
        if (entry.value == DebugBreakpointStatus.rejected) {
          mark = entry.value;
          break;
        }
        if (mark == null || entry.value == DebugBreakpointStatus.verified) {
          mark = entry.value;
        }
      }
      final centerY = paragraph.top + paragraph.preferredLineHeight / 2;
      if (mark != null) {
        final center = Offset(size.width * 0.28, centerY);
        final paint = Paint()
          ..color = scheme.error
          ..strokeWidth = 1.5
          ..style = mark == DebugBreakpointStatus.verified
              ? PaintingStyle.fill
              : PaintingStyle.stroke;
        canvas.drawCircle(center, 4.5, paint);
        if (mark == DebugBreakpointStatus.rejected) {
          canvas.drawLine(
            center + const Offset(-3, 3),
            center + const Offset(3, -3),
            paint,
          );
        }
      }
      if (executionLine != null &&
          executionLine >= range.first &&
          executionLine < range.end) {
        final left = size.width * 0.5;
        final right = size.width - 2;
        final arrow = Path()
          ..moveTo(left, centerY - 1.5)
          ..lineTo(right - 5, centerY - 1.5)
          ..lineTo(right - 5, centerY - 5)
          ..lineTo(right, centerY)
          ..lineTo(right - 5, centerY + 5)
          ..lineTo(right - 5, centerY + 1.5)
          ..lineTo(left, centerY + 1.5)
          ..close();
        canvas.drawPath(arrow, Paint()..color = scheme.primary);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DebugGutterPainter oldDelegate) =>
      oldDelegate.debug != debug ||
      oldDelegate.file != file ||
      oldDelegate.notifier != notifier ||
      oldDelegate.canonicalPath != canonicalPath ||
      oldDelegate.scheme != scheme;
}
