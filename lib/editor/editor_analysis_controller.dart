import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../services/code_analysis.dart';
import 'editor_controller.dart';
import 'open_file.dart';

/// One bounded lane per editor. Timed out providers keep their lane until they
/// actually complete, preventing unlimited work from a slow native checker.
class EditorAnalysisController extends ChangeNotifier {
  EditorAnalysisController({
    required this.editor,
    required this.analyzer,
    this.debounce = const Duration(milliseconds: 300),
    this.timeout = const Duration(seconds: 12),
  }) {
    editor.addListener(_synchronize);
    _synchronize();
  }

  static const maxDocuments = 64;
  static const maxSourceUnits = 4 * 1024 * 1024;
  static const maxDiagnostics = 1000;
  final EditorController editor;
  final CodeAnalyzer? analyzer;
  final Duration debounce;
  final Duration timeout;
  final _observed = <OpenFile, ({CodeLines lines, String text})>{};
  final _listeners = <OpenFile, VoidCallback>{};
  OpenFile? _active;
  Timer? _timer;
  Timer? _watchdog;
  int _generation = 0;
  bool _disposed = false;
  bool _busy = false;
  bool _ready = false;
  bool pending = false;
  bool checked = false;
  String? unavailableReason;
  List<CodeDiagnostic> problems = const [];
  Map<String, CodeDocumentSnapshot> _accepted = const {};

  String location(CodeDiagnostic problem) {
    final path = _path(problem.filePath);
    final active = editor.current;
    final label = active == null
        ? p.basename(path)
        : p.relative(path, from: active.projectRootPath);
    final text = _accepted[_identity(path)]?.text;
    if (text == null) return '$label · 打开后重新检查';
    final prefix = text.substring(0, problem.startOffset);
    final breaks = RegExp(r'\r\n|\r|\n').allMatches(prefix).toList();
    return '$label:${breaks.length + 1}:${problem.startOffset - (breaks.isEmpty ? 0 : breaks.last.end) + 1}';
  }

  void _synchronize() {
    if (_disposed) return;
    var changed = !identical(_active, editor.current);
    _active = editor.current;
    for (final file in _observed.keys.toList()) {
      if (editor.files.contains(file)) continue;
      file.controller.removeListener(_listeners.remove(file)!);
      _observed.remove(file);
      changed = true;
    }
    for (final file in editor.files) {
      final previous = _observed[file];
      if (previous == null) {
        void listener() => _synchronize();
        file.controller.addListener(listener);
        _listeners[file] = listener;
      }
      if (previous == null ||
          !identical(previous.lines, file.controller.codeLines)) {
        final text = file.controller.text;
        if (previous == null || previous.text != text) changed = true;
        _observed[file] = (lines: file.controller.codeLines, text: text);
      }
    }
    if (changed) requestAnalysis();
  }

  void requestAnalysis({bool immediate = false}) {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _watchdog?.cancel();
    _ready = false;
    checked = false;
    problems = const [];
    _accepted = const {};
    for (final file in editor.files) {
      file.diagnostics?.update(null, const []);
    }
    final active = editor.current;
    pending = analyzer != null && active != null && !active.readOnly;
    unavailableReason = analyzer == null
        ? '当前产品未安装本地代码检查器'
        : active == null || active.readOnly
        ? '打开可编辑的源文件后检查'
        : null;
    if (pending) {
      _timer = Timer(immediate ? Duration.zero : debounce, () {
        if (_disposed || generation != _generation) return;
        _ready = true;
        _armWatchdog(generation);
        _pump();
      });
    }
    notifyListeners();
  }

  void _armWatchdog(int generation) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, () {
      if (_disposed || generation != _generation || !pending) return;
      pending = false;
      unavailableReason = '本地检查器响应超时，等待当前请求结束后重试';
      notifyListeners();
    });
  }

  static String _path(String value) => p.normalize(p.absolute(value));
  static String _identity(String value) {
    final normalized = _path(value);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static bool _owned(String root, String file) {
    if (!p.isWithin(root, file)) return false;
    try {
      return !File(file).existsSync() ||
          p.isWithin(
            Directory(root).resolveSymbolicLinksSync(),
            File(file).resolveSymbolicLinksSync(),
          );
    } on FileSystemException {
      return false;
    }
  }

  void _pump() {
    if (_disposed || _busy || !_ready || analyzer == null) return;
    _ready = false;
    final active = editor.current;
    if (active == null || active.readOnly) return;
    final root = _path(active.projectRootPath);
    final activePath = _path(active.path);
    final files = editor.files
        .where(
          (file) =>
              !file.readOnly &&
              p.equals(_path(file.projectRootPath), root) &&
              _owned(root, _path(file.path)),
        )
        .toList();
    final units = files.fold<int>(
      0,
      (total, file) => total + _observed[file]!.text.length,
    );
    if (!_owned(root, activePath) ||
        files.length > maxDocuments ||
        units > maxSourceUnits) {
      pending = false;
      unavailableReason = '项目快照超出本地检查范围（最多 64 个文件、4 Mi UTF-16 单元）';
      _watchdog?.cancel();
      notifyListeners();
      return;
    }
    final request = CodeAnalysisRequest(
      projectPath: root,
      activeFilePath: activePath,
      language: _language(active.path, active.projectType),
      revision: active.revision,
      documents: [
        for (final file in files)
          CodeDocumentSnapshot(
            path: _path(file.path),
            text: _observed[file]!.text,
            revision: file.revision,
          ),
      ],
    );
    _busy = true;
    pending = true;
    unavailableReason = null;
    // Queue waiting time must not consume this dispatch's response timeout.
    _armWatchdog(_generation);
    unawaited(_run(request, _generation));
  }

  Future<void> _run(CodeAnalysisRequest request, int generation) async {
    try {
      final result = await analyzer!.analyze(request);
      if (!_current(request, generation)) return;
      final snapshots = {
        for (final document in request.documents)
          _identity(document.path): document,
      };
      final accepted = <CodeDiagnostic>[];
      for (final problem in result.diagnostics) {
        if (accepted.length >= maxDiagnostics) break;
        if (!p.isAbsolute(problem.filePath)) continue;
        final path = _path(problem.filePath);
        if (!_owned(request.projectPath, path) ||
            problem.message.trim().isEmpty ||
            problem.startOffset < 0 ||
            problem.endOffset < problem.startOffset) {
          continue;
        }
        final snapshot = snapshots[_identity(path)];
        if (snapshot != null && problem.endOffset > snapshot.text.length) {
          continue;
        }
        accepted.add(problem);
      }
      _accepted = snapshots;
      problems = List.unmodifiable(accepted);
      unavailableReason = result.unavailableReason;
      checked = result.unavailableReason == null;
      pending = false;
      for (final file in editor.files) {
        final snapshot = snapshots[_identity(file.path)];
        if (snapshot == null) continue;
        file.diagnostics?.update(snapshot.text, [
          for (final problem in problems)
            if (p.equals(_path(problem.filePath), snapshot.path)) problem,
        ]);
      }
      _watchdog?.cancel();
      notifyListeners();
    } on Object catch (error) {
      if (!_current(request, generation)) return;
      pending = false;
      unavailableReason = '本地检查暂时不可用：$error';
      _watchdog?.cancel();
      notifyListeners();
    } finally {
      _busy = false;
      if (!_disposed && _ready) _pump();
    }
  }

  bool _current(CodeAnalysisRequest request, int generation) {
    if (_disposed || generation != _generation) return false;
    final active = editor.current;
    if (active == null ||
        !p.equals(_path(active.path), request.activeFilePath) ||
        !p.equals(_path(active.projectRootPath), request.projectPath)) {
      return false;
    }
    for (final snapshot in request.documents) {
      final matching = editor.files.where(
        (file) => p.equals(_path(file.path), snapshot.path),
      );
      if (matching.length != 1) return false;
      final file = matching.single;
      if (file.revision != snapshot.revision ||
          file.controller.text != snapshot.text ||
          !p.equals(_path(file.projectRootPath), request.projectPath)) {
        return false;
      }
    }
    return true;
  }

  /// Unopened disk files become fresh snapshots before any precise selection.
  Future<void> navigate(CodeDiagnostic problem) async {
    if (!problems.contains(problem)) return;
    final active = editor.current;
    if (active == null) return;
    final path = _path(problem.filePath);
    final snapshot = _accepted[_identity(path)];
    final opened = editor.files.where(
      (file) => p.equals(_path(file.path), path),
    );
    if (snapshot != null &&
        opened.length == 1 &&
        opened.single.controller.text == snapshot.text) {
      final file = opened.single;
      // Apply before switching tabs, which deliberately invalidates old results.
      file.diagnostics?.navigate(problem);
      editor.select(editor.files.indexOf(file));
      file.focusNode.requestFocus();
      return;
    }
    await editor.openPath(
      path,
      ownerProjectName: active.ownerProjectName,
      ownerProjectPath: active.projectRootPath,
      ownerProjectType: active.projectType,
    );
    if (!_disposed) requestAnalysis(immediate: true);
  }

  static String _language(String file, String fallback) =>
      {
        '.c': 'c',
        '.h': fallback == 'cpp' || fallback == 'c++' ? 'cpp' : 'c',
        '.cpp': 'cpp',
        '.cc': 'cpp',
        '.cxx': 'cpp',
        '.hpp': 'cpp',
        '.hh': 'cpp',
        '.hxx': 'cpp',
        '.inl': 'cpp',
        '.dart': 'dart',
        '.java': 'java',
        '.py': 'python',
        '.lua': 'lua',
        '.js': 'javascript',
        '.mjs': 'javascript',
        '.ts': 'typescript',
        '.tsx': 'typescript',
        '.jsx': 'javascript',
        '.go': 'go',
        '.rs': 'rust',
        '.sh': 'shell',
        '.bash': 'shell',
        '.kt': 'kotlin',
        '.kts': 'kotlin',
        '.sql': 'sql',
        '.json': 'json',
        '.md': 'markdown',
        '.html': 'html',
        '.css': 'css',
      }[p.extension(file).toLowerCase()] ??
      fallback;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _watchdog?.cancel();
    editor.removeListener(_synchronize);
    for (final entry in _listeners.entries) {
      entry.key.controller.removeListener(entry.value);
    }
    _listeners.clear();
    _observed.clear();
    super.dispose();
  }
}
