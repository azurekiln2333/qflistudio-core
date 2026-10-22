import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../services/code_analysis.dart';

/// Decorations for one source snapshot validated by the editor scheduler.
class EditorFileDiagnostics extends ChangeNotifier {
  EditorFileDiagnostics(this.path);
  final String path;
  late CodeLineEditingController _controller;
  String? _source;
  List<int> _lineStarts = const [0];
  Map<int, CodeDiagnosticSeverity> _lineSeverities = const {};
  List<CodeDiagnostic> problems = const [];
  bool _disposed = false;
  bool _repaintScheduled = false;

  void attach(CodeLineEditingController controller) => _controller = controller;

  void update(String? source, List<CodeDiagnostic> diagnostics) {
    if (_disposed) return;
    if (_source == source && problems.isEmpty && diagnostics.isEmpty) return;
    _source = source;
    _lineStarts = [
      0,
      if (source != null)
        for (final match in RegExp(r'\r\n|\r|\n').allMatches(source)) match.end,
    ];
    problems = List.unmodifiable(diagnostics);
    final severities = <int, CodeDiagnosticSeverity>{};
    for (final problem in problems) {
      final line = _sourceLine(problem.startOffset);
      final previous = severities[line];
      if (previous == null || problem.severity.index < previous.index) {
        severities[line] = problem.severity;
      }
    }
    _lineSeverities = severities;
    // Content listeners run before re_editor reconciles its render object's
    // line list. Repainting here can read old indices from a shorter buffer.
    // Invalidate our state immediately, then repaint after that reconciliation.
    if (!_repaintScheduled) {
      _repaintScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _repaintScheduled = false;
        if (!_disposed) _controller.forceRepaint();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    notifyListeners();
  }

  TextSpan decorate({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    if (_source == null || problems.isEmpty || codeLine.text.isEmpty) {
      return textSpan;
    }
    final line = _controller.codeLines.index2lineIndex(index);
    if (line < 0 || line >= _lineStarts.length) return textSpan;
    final start = _lineStarts[line];
    final end = start + codeLine.text.length;
    final ranges = <({int start, int end, CodeDiagnosticSeverity severity})>[];
    for (final problem in problems) {
      var low = problem.startOffset;
      var high = problem.endOffset;
      if (low == high && low >= start && low <= end) {
        if (low == end) low = end - 1;
        high = low + 1;
      }
      if (high <= start || low >= end) continue;
      low = (low - start).clamp(0, codeLine.text.length);
      high = (high - start).clamp(0, codeLine.text.length);
      if (low > 0 &&
          low < codeLine.text.length &&
          _lowSurrogate(codeLine.text.codeUnitAt(low))) {
        low--;
      }
      if (high < codeLine.text.length &&
          _lowSurrogate(codeLine.text.codeUnitAt(high))) {
        high++;
      }
      ranges.add((start: low, end: high, severity: problem.severity));
    }
    if (ranges.isEmpty) return textSpan;
    final scheme = Theme.of(context).colorScheme;
    var offset = 0;
    TextSpan visit(TextSpan span) {
      final children = <InlineSpan>[];
      final text = span.text ?? '';
      final boundaries = <int>{0, text.length};
      for (final range in ranges) {
        boundaries.add((range.start - offset).clamp(0, text.length));
        boundaries.add((range.end - offset).clamp(0, text.length));
      }
      final cuts = boundaries.toList()..sort();
      for (var i = 0; i + 1 < cuts.length; i++) {
        final low = cuts[i];
        final high = cuts[i + 1];
        if (low == high) continue;
        CodeDiagnosticSeverity? severity;
        for (final range in ranges) {
          if (range.start < offset + high &&
              range.end > offset + low &&
              (severity == null || range.severity.index < severity.index)) {
            severity = range.severity;
          }
        }
        children.add(
          TextSpan(
            text: text.substring(low, high),
            style: severity == null
                ? null
                : TextStyle(
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.wavy,
                    decorationColor: switch (severity) {
                      CodeDiagnosticSeverity.error => scheme.error,
                      CodeDiagnosticSeverity.warning => Colors.orange,
                      CodeDiagnosticSeverity.information => scheme.primary,
                      CodeDiagnosticSeverity.hint => scheme.outline,
                    },
                    decorationThickness: 1.5,
                  ),
          ),
        );
      }
      offset += text.length;
      for (final child in span.children ?? const <InlineSpan>[]) {
        children.add(child is TextSpan ? visit(child) : child);
      }
      return TextSpan(
        style: span.style,
        children: children,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }

    return visit(textSpan);
  }

  static bool _lowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  int _sourceLine(int offset) {
    var low = 0;
    var high = _lineStarts.length;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (_lineStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Folded children share their visible parent's gutter marker.
  CodeDiagnosticSeverity? gutterSeverity(int visibleIndex) {
    CodeDiagnosticSeverity? severity;
    for (final entry in _lineSeverities.entries) {
      if (_controller.codeLines.lineIndex2Index(entry.key).index !=
          visibleIndex) {
        continue;
      }
      if (severity == null || entry.value.index < severity.index) {
        severity = entry.value;
      }
    }
    return severity;
  }

  bool navigate(CodeDiagnostic diagnostic) {
    if (_source == null ||
        _source != _controller.text ||
        !problems.contains(diagnostic)) {
      return false;
    }
    CodeLinePosition position(int offset) {
      var line = 0;
      while (line + 1 < _lineStarts.length && _lineStarts[line + 1] <= offset) {
        line++;
      }
      var mapped = _controller.codeLines.lineIndex2Index(line);
      while (mapped.index >= 0 && mapped.chunkIndex >= 0) {
        _controller.expandChunk(mapped.index);
        mapped = _controller.codeLines.lineIndex2Index(line);
      }
      return CodeLinePosition(
        index: mapped.index,
        offset: (offset - _lineStarts[line]).clamp(
          0,
          _controller.codeLines[mapped.index].text.length,
        ),
      );
    }

    final start = position(diagnostic.startOffset);
    final end = position(diagnostic.endOffset);
    _controller.selection = CodeLineSelection(
      baseIndex: start.index,
      baseOffset: start.offset,
      extentIndex: end.index,
      extentOffset: end.offset,
    );
    _controller.makePositionVisible(start);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A source-independent mark also makes empty-file/blank-line insertions visible.
class EditorDiagnosticGutter extends StatelessWidget {
  const EditorDiagnosticGutter({
    super.key,
    required this.diagnostics,
    required this.notifier,
  });

  final EditorFileDiagnostics diagnostics;
  final CodeIndicatorValueNotifier notifier;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: double.infinity,
    child: CustomPaint(
      painter: _DiagnosticGutterPainter(
        diagnostics,
        notifier,
        Theme.of(context).colorScheme,
      ),
    ),
  );
}

class _DiagnosticGutterPainter extends CustomPainter {
  _DiagnosticGutterPainter(this.diagnostics, this.notifier, this.scheme)
    : super(repaint: Listenable.merge([diagnostics, notifier]));

  final EditorFileDiagnostics diagnostics;
  final CodeIndicatorValueNotifier notifier;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final paragraph
        in notifier.value?.paragraphs ?? <CodeLineRenderParagraph>[]) {
      final severity = diagnostics.gutterSeverity(paragraph.index);
      if (severity == null) continue;
      canvas.drawCircle(
        Offset(
          size.width / 2,
          paragraph.top + paragraph.preferredLineHeight / 2,
        ),
        3,
        Paint()
          ..color = switch (severity) {
            CodeDiagnosticSeverity.error => scheme.error,
            CodeDiagnosticSeverity.warning => Colors.orange,
            CodeDiagnosticSeverity.information => scheme.primary,
            CodeDiagnosticSeverity.hint => scheme.outline,
          },
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiagnosticGutterPainter oldDelegate) =>
      oldDelegate.diagnostics != diagnostics ||
      oldDelegate.notifier != notifier ||
      oldDelegate.scheme != scheme;
}
