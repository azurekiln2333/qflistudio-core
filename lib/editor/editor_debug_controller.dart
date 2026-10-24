import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../services/runner_service.dart';
import '../services/studio_profile.dart';
import 'editor_controller.dart';
import 'open_file.dart';

/// Owns one real debugger session until both worker and provider cleanup finish.
/// Launch is explicit; analysis and ordinary Run are never debugger fallbacks.
class EditorDebugController extends ChangeNotifier {
  EditorDebugController({
    required this.editor,
    StudioDebugger? debugger,
    this.isFileAvailable,
    this.isProjectAvailable,
  }) : debugger = debugger ?? StudioProfile.current?.debugger {
    editor.addListener(_editorChanged);
  }

  static const maxDocuments = 64;
  static const maxSourceUnits = 4 * 1024 * 1024;
  static const maxBreakpoints = 1000;
  static const _maxCloseDisposalAttempts = 3;
  static const _closeDisposalRetryDelay = Duration(milliseconds: 50);

  final EditorController editor;
  final StudioDebugger? debugger;

  /// The host may retain recovery buffers whose project left its workspace.
  /// Recheck availability after asynchronous preparation, before source writes.
  final bool Function(OpenFile file)? isFileAvailable;

  /// Checks the original owning root even when its clean tabs were closed.
  /// Navigation rechecks this before an unopened source can enter the editor.
  final bool Function(String projectPath)? isProjectAvailable;
  final List<DebugBreakpoint> _breakpoints = [];
  _DebugRun? _run;
  DebugSnapshot? _snapshot;
  DebugFrame? _selectedFrame;
  String? _projectPath;
  String? _error;
  bool _closed = false;
  bool _disposed = false;
  int _navigationGeneration = 0;
  Future<void>? _closeFuture;

  DebugSnapshot? get snapshot => _snapshot;
  bool get busy => _run != null;
  bool get starting =>
      _run != null &&
      (_run!.starting || _snapshot?.phase == DebugPhase.starting);
  bool get stopping =>
      _run != null &&
      (_run!.stopRequested || _snapshot?.phase == DebugPhase.stopping);
  String? get error => _error;
  String? get projectPath => _projectPath;
  DebugCapabilities? get capabilities =>
      _run?.capabilities ?? debugger?.capabilities;
  List<DebugBreakpoint> get breakpoints => List.unmodifiable(_breakpoints);
  DebugFrame? get selectedFrame => _selectedFrame;
  bool get paused {
    final run = _run;
    return !_closed && run != null && _pause(run) != null;
  }

  /// Execution arrows describe the exact captured source of a valid pause.
  /// Dirty text is valid when it was included in the launch snapshot.
  DebugSourceLocation? executionLocationFor(OpenFile file) {
    final run = _run;
    final frame = _selectedFrame;
    if (run == null ||
        !paused ||
        !_editable(file) ||
        !run.capabilities.supportsStackFrames ||
        frame?.location == null ||
        !(_snapshot?.frames.contains(frame) ?? false)) {
      return null;
    }
    try {
      if (!p.equals(_root(file.projectRootPath), run.root)) return null;
      final path = _source(run.root, file.path);
      if (_key(_source(run.root, frame!.location!.filePath)) != _key(path)) {
        return null;
      }
      for (final buffer in run.buffers) {
        if (_key(buffer.path) == _key(path) &&
            buffer.text == file.controller.text) {
          final location = frame.location!;
          if (location.line > 0 &&
              location.line <= file.controller.codeLines.lineCount) {
            return location;
          }
        }
      }
    } on FileSystemException {
      return null;
    } on StateError {
      return null;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _editorChanged() => _notify();

  static String _path(String path) => p.normalize(p.absolute(path));
  static String _key(String path) {
    final normalized = _path(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String _root(String path) =>
      _path(Directory(path).resolveSymbolicLinksSync());

  static String _fileKey(String path) {
    try {
      return _key(File(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      return _key(path);
    }
  }

  static String _source(String root, String path) {
    if (!p.isAbsolute(path)) throw StateError('调试源文件路径必须为绝对路径');
    final canonical = _path(File(path).resolveSymbolicLinksSync());
    if (!p.isWithin(root, canonical)) {
      throw StateError('调试源文件不能越出所属项目，包括文件链接');
    }
    return canonical;
  }

  static String _language(String file, String fallback) {
    final extension = p.extension(file).toLowerCase();
    final owner = fallback.trim().toLowerCase();
    if (extension == '.h' && (owner == 'cpp' || owner == 'c++')) return 'cpp';
    return const {
          '.py': 'python',
          '.pyw': 'python',
          '.lua': 'lua',
          '.go': 'go',
          '.dart': 'dart',
          '.java': 'java',
          '.c': 'c',
          '.h': 'c',
          '.cpp': 'cpp',
          '.cc': 'cpp',
          '.cxx': 'cpp',
          '.hpp': 'cpp',
          '.js': 'javascript',
          '.mjs': 'javascript',
          '.ts': 'typescript',
          '.rs': 'rust',
          '.json': 'json',
          '.sql': 'sql',
        }[extension] ??
        (extension.isEmpty ? owner : '');
  }

  bool _editable(OpenFile file) =>
      !_closed &&
      editor.files.contains(file) &&
      !file.readOnly &&
      isProjectAvailable?.call(file.projectRootPath) != false &&
      isFileAvailable?.call(file) != false;

  bool canToggleBreakpoint(OpenFile file) {
    if (!_editable(file) || debugger == null) {
      return false;
    }
    try {
      if (!debugger!.supportsLanguage(_language(file.path, file.projectType))) {
        return false;
      }
      final root = _root(file.projectRootPath);
      _source(root, file.path);
      final run = _run;
      if (run == null) return true;
      if (run.starting ||
          run.stopRequested ||
          run.breakpointsPending ||
          !p.equals(root, run.root)) {
        return false;
      }
      return switch (run.capabilities.breakpointUpdate) {
        DebugBreakpointUpdate.launchOnly => false,
        DebugBreakpointUpdate.paused => _pause(run) != null,
        DebugBreakpointUpdate.live =>
          _snapshot?.phase == DebugPhase.running || _pause(run) != null,
      };
    } on Object {
      return false;
    }
  }

  DebugBreakpointResult? breakpointFor(String filePath, int line) {
    String path;
    try {
      path = _path(File(filePath).resolveSymbolicLinksSync());
    } on FileSystemException {
      path = _path(filePath);
    }
    bool matches(DebugBreakpoint point) =>
        point.line == line && _key(point.filePath) == _key(path);
    for (final result in _snapshot?.breakpoints ?? <DebugBreakpointResult>[]) {
      if (matches(result.requested)) return result;
    }
    for (final point in _breakpoints) {
      if (matches(point)) {
        return DebugBreakpointResult(
          requested: point,
          status: DebugBreakpointStatus.pending,
        );
      }
    }
    return null;
  }

  Future<void> toggleBreakpoint(OpenFile file, int oneBasedPhysicalLine) async {
    if (!canToggleBreakpoint(file)) {
      _error = '当前文件或调试器状态不支持修改断点';
      _notify();
      return;
    }
    if (oneBasedPhysicalLine < 1 ||
        oneBasedPhysicalLine > file.controller.codeLines.lineCount) {
      _error = '断点行不在当前源文件内';
      _notify();
      return;
    }
    final run = _run;
    final root = _root(file.projectRootPath);
    final path = _source(root, file.path);
    final next = [..._breakpoints];
    final index = next.indexWhere(
      (point) =>
          _key(point.filePath) == _key(path) &&
          point.line == oneBasedPhysicalLine,
    );
    if (index >= 0) {
      next.removeAt(index);
    } else {
      if (next.length >= maxBreakpoints) {
        _error = '最多保留 $maxBreakpoints 个断点';
        _notify();
        return;
      }
      next.add(DebugBreakpoint(filePath: path, line: oneBasedPhysicalLine));
    }
    if (run == null) {
      _breakpoints
        ..clear()
        ..addAll(next);
      _snapshot = null; // Previous-session results cannot verify a new request.
      _error = null;
      _notify();
      return;
    }
    run.breakpointsPending = true;
    _error = null;
    _notify();
    try {
      await run.session!.setBreakpoints(
        List<DebugBreakpoint>.unmodifiable([
          for (final point in next)
            if (p.isWithin(run.root, point.filePath)) point,
        ]),
      );
      if (identical(_run, run) && !run.stopRequested) {
        _breakpoints
          ..clear()
          ..addAll(next);
        _receive(run, run.session!.snapshot);
      }
    } on Object catch (error) {
      if (identical(_run, run)) _error = '断点更新失败：$error';
    } finally {
      run.breakpointsPending = false;
      _notify();
    }
  }

  Future<void> start({bool stopOnEntry = false}) async {
    if (_closed || busy) {
      _error = _closed ? '调试控制器已关闭' : '等待当前调试器完成清理后再启动';
      _notify();
      return;
    }
    _DebugRun? run;
    try {
      final provider = debugger;
      final active = editor.current;
      if (provider == null) throw StateError('当前产品未安装离线调试器');
      if (active == null || !_editable(active)) {
        throw StateError('请先打开可编辑的项目源文件');
      }
      final originalRoot = _path(active.projectRootPath);
      final root = _root(originalRoot);
      _source(root, active.path);
      if (!provider.supportsLanguage(
        _language(active.path, active.projectType),
      )) {
        throw StateError('调试器不支持当前源文件语言');
      }
      final entry = RunnerService.findEntry(originalRoot);
      if (entry == null) throw StateError('所属项目没有可用的配置入口文件');
      final entryPath = _source(root, _path(entry));
      final language = _language(entryPath, active.projectType);
      if (!provider.supportsLanguage(language)) {
        throw StateError('调试器不支持项目入口文件语言');
      }
      final capabilities = provider.capabilities;
      if (stopOnEntry && !capabilities.supportsStopOnEntry) {
        throw StateError('当前调试器不支持在入口暂停');
      }
      final captured = <_DebugBuffer>[];
      final paths = <String>{};
      var units = 0;
      for (final file in editor.files) {
        if (!_editable(file) || !_belongsToRoot(file, originalRoot, root)) {
          continue;
        }
        final path = _source(root, file.path);
        if (!paths.add(_key(path))) throw StateError('项目存在重复的源文件别名');
        final text = file.controller.text;
        units += text.length;
        captured.add(_DebugBuffer(file, path, text, file.revision));
      }
      if (captured.length > maxDocuments || units > maxSourceUnits) {
        throw StateError('调试快照超出范围（最多 64 个文件、4 Mi UTF-16 单元）');
      }
      final points = <DebugBreakpoint>[];
      for (final point in _breakpoints) {
        if (!p.isWithin(root, point.filePath)) continue;
        points.add(
          DebugBreakpoint(
            filePath: _source(root, point.filePath),
            line: point.line,
          ),
        );
      }
      run = _DebugRun(
        root: root,
        originalRoot: originalRoot,
        ownerName: active.ownerProjectName,
        ownerType: active.projectType,
        capabilities: capabilities,
        buffers: captured,
      );
      _run = run;
      _projectPath = root;
      _snapshot = null;
      _selectedFrame = null;
      _error = null;
      _notify();
      if (!capabilities.supportsDocumentSnapshots) {
        for (final buffer in captured) {
          if (run.stopRequested || _closed) {
            _releaseUnlaunched(run);
            return;
          }
          _checkBuffers(run);
          final savingRun = run;
          final failure = await editor.saveFile(
            buffer.file,
            shouldSave: () {
              if (_closed ||
                  savingRun.stopRequested ||
                  !identical(_run, savingRun)) {
                return false;
              }
              _checkBuffers(savingRun);
              return true;
            },
          );
          if (run.stopRequested || _closed) {
            _releaseUnlaunched(run);
            return;
          }
          if (failure != null) throw StateError(failure);
          _checkBuffers(run);
        }
      }
      _checkBuffers(run);
      if (run.stopRequested || _closed) {
        _releaseUnlaunched(run);
        return;
      }
      final session = await provider.launch(
        DebugLaunchRequest(
          projectPath: root,
          entryFilePath: entryPath,
          language: language,
          documents: capabilities.supportsDocumentSnapshots
              ? [
                  for (final b in captured)
                    CodeDocumentSnapshot(
                      path: b.path,
                      text: b.text,
                      revision: b.revision,
                    ),
                ]
              : const [],
          breakpoints: points,
          stopOnEntry: stopOnEntry,
        ),
      );
      run.session = session;
      run.starting = false;
      // Subscribe first: a pause reached during launch remains observable.
      run.subscription = session.updates.listen(
        (snapshot) => _receive(run!, snapshot),
        onError: (Object error) {
          if (identical(_run, run)) {
            _error = '调试器状态流失败：$error';
            _notify();
          }
        },
      );
      _receive(run, session.snapshot);
      unawaited(_watch(run));
      if (run.stopRequested || _closed) unawaited(_requestStop(run));
      _notify();
    } on Object catch (error) {
      _error = '无法启动离线调试：$error';
      if (run != null && run.session == null) _releaseUnlaunched(run);
      if (run?.session != null) {
        run!.stopRequested = true;
        unawaited(_requestStop(run));
        unawaited(_watch(run));
      }
      _notify();
    }
  }

  void _checkBuffers(_DebugRun run) {
    final currentFiles = editor.files.where(
      (file) =>
          _editable(file) && _belongsToRoot(file, run.originalRoot, run.root),
    );
    if (currentFiles.length != run.buffers.length ||
        currentFiles.any(
          (file) => !run.buffers.any((b) => identical(b.file, file)),
        )) {
      throw StateError('准备调试时打开的项目文件发生变化，请重新启动调试');
    }
    for (final buffer in run.buffers) {
      final file = buffer.file;
      if (!_editable(file) ||
          file.revision != buffer.revision ||
          file.controller.text != buffer.text ||
          !p.equals(_root(file.projectRootPath), run.root) ||
          _key(_source(run.root, file.path)) != _key(buffer.path)) {
        throw StateError('准备调试时源文件发生变化，请重新启动调试');
      }
    }
    if (_key(_root(run.originalRoot)) != _key(run.root)) {
      throw StateError('准备调试时项目路径发生变化');
    }
  }

  static bool _belongsToRoot(OpenFile file, String originalRoot, String root) {
    try {
      return p.equals(_root(file.projectRootPath), root);
    } on FileSystemException {
      // An unrelated stale workspace tab must not block this project's launch.
      if (p.equals(_path(file.projectRootPath), originalRoot)) rethrow;
      return false;
    }
  }

  void _releaseUnlaunched(_DebugRun run) {
    if (identical(_run, run)) _run = null;
    run.starting = false;
    if (!run.finished.isCompleted) run.finished.complete();
    _notify();
  }

  void _receive(_DebugRun run, DebugSnapshot snapshot) {
    if (!identical(_run, run) ||
        snapshot.sessionId != run.session?.id ||
        (_snapshot != null && snapshot.revision <= _snapshot!.revision) ||
        (_snapshot?.isTerminal == true && !snapshot.isTerminal)) {
      return;
    }
    final token = snapshot.pauseToken;
    if (token != null && token.generation < run.pauseGeneration) return;
    if (token != null) run.pauseGeneration = token.generation;
    final oldToken = _snapshot?.pauseToken;
    final oldFrame = _selectedFrame;
    _snapshot = snapshot;
    _selectedFrame = null;
    if (token != null && token != run.invalidPause && !run.stopRequested) {
      if (oldToken == token && oldFrame != null) {
        for (final frame in snapshot.frames) {
          if (frame.id == oldFrame.id && frame.threadId == oldFrame.threadId) {
            _selectedFrame = frame;
            break;
          }
        }
      }
      if (_selectedFrame == null && snapshot.frames.isNotEmpty) {
        _selectedFrame = snapshot.frames.first;
      }
    }
    if (oldFrame?.id != _selectedFrame?.id ||
        oldFrame?.threadId != _selectedFrame?.threadId) {
      _navigationGeneration++;
    }
    if (snapshot.phase == DebugPhase.failed) _error = snapshot.message;
    _notify();
  }

  DebugPauseToken? _pause(_DebugRun run) {
    final snapshot = _snapshot;
    if (!identical(_run, run) ||
        run.stopRequested ||
        snapshot?.phase != DebugPhase.paused ||
        snapshot!.pauseToken == run.invalidPause) {
      return null;
    }
    return snapshot.pauseToken;
  }

  bool canCommand(DebugCommand command) {
    final run = _run;
    final state = _snapshot;
    if (_closed ||
        run == null ||
        run.starting ||
        run.stopRequested ||
        state == null ||
        state.isTerminal) {
      return false;
    }
    if (command == DebugCommand.pause) {
      return run.capabilities.supportsPause &&
          state.phase == DebugPhase.running &&
          !run.commands.contains(DebugCommand.pause);
    }
    if (_pause(run) == null ||
        run.breakpointsPending ||
        run.commands.isNotEmpty) {
      return false;
    }
    return switch (command) {
      DebugCommand.resume => true,
      DebugCommand.stepInto => run.capabilities.supportsStepInto,
      DebugCommand.stepOver => run.capabilities.supportsStepOver,
      DebugCommand.stepOut => run.capabilities.supportsStepOut,
      DebugCommand.pause => false,
    };
  }

  Future<void> command(DebugCommand command) async {
    if (!canCommand(command)) {
      _error = '当前暂停状态或调试器能力不支持此操作';
      _notify();
      return;
    }
    final run = _run!;
    final token = command == DebugCommand.pause ? null : _pause(run);
    final frame = _selectedFrame;
    String? threadId = frame?.threadId;
    if (threadId == null && token != null) {
      for (final thread in _snapshot!.threads) {
        if (thread.isPaused) {
          threadId = thread.id;
          break;
        }
      }
    }
    run.commands.add(command);
    if (token != null) {
      run.invalidPause = token;
      _selectedFrame = null;
    }
    _error = null;
    _notify();
    try {
      await run.session!.command(
        command,
        pauseToken: token,
        threadId: threadId,
      );
      if (identical(_run, run)) _receive(run, run.session!.snapshot);
    } on Object catch (error) {
      if (identical(_run, run)) _error = '调试命令失败：$error';
    } finally {
      run.commands.remove(command);
      _notify();
    }
  }

  void selectFrame(DebugFrame frame) {
    final run = _run;
    if (run == null ||
        _pause(run) == null ||
        !run.capabilities.supportsStackFrames ||
        !(_snapshot?.frames.contains(frame) ?? false)) {
      return;
    }
    _navigationGeneration++;
    _selectedFrame = frame;
    _notify();
  }

  Future<void> navigate(DebugFrame frame) async {
    final run = _run;
    final token = run == null ? null : _pause(run);
    if (_closed ||
        run == null ||
        token == null ||
        !run.capabilities.supportsStackFrames ||
        !(_snapshot?.frames.contains(frame) ?? false) ||
        frame.location == null) {
      return;
    }
    final navigation = ++_navigationGeneration;
    bool currentNavigation() =>
        !_closed &&
        navigation == _navigationGeneration &&
        identical(_run, run) &&
        _pause(run) == token &&
        isProjectAvailable?.call(run.originalRoot) != false;

    try {
      if (!currentNavigation()) return;
      final location = frame.location!;
      final path = _source(run.root, location.filePath);
      OpenFile? open;
      for (final file in editor.files) {
        if (_key(_path(file.path)) == _key(path) ||
            _fileKey(file.path) == _key(path)) {
          if (!_editable(file) ||
              !p.equals(_root(file.projectRootPath), run.root)) {
            throw StateError('调用栈源文件属于其他项目或只读快照');
          }
          open = file;
          break;
        }
      }
      if (open == null) {
        bool shouldOpen() {
          if (!currentNavigation()) return false;
          if (_key(_source(run.root, path)) != _key(path)) {
            throw StateError('调用栈源文件路径发生变化');
          }
          return true;
        }

        final failure = await editor.openPath(
          path,
          ownerProjectName: run.ownerName,
          ownerProjectPath: run.originalRoot,
          ownerProjectType: run.ownerType,
          shouldOpen: shouldOpen,
        );
        if (!currentNavigation()) return;
        if (failure != null) throw StateError(failure);
        for (final file in editor.files) {
          if (_key(file.path) == _key(path)) {
            open = file;
            break;
          }
        }
      }
      if (open == null || !currentNavigation()) return;
      if (!_editable(open) ||
          !p.equals(_root(open.projectRootPath), run.root)) {
        throw StateError('调用栈源文件属于其他项目或只读快照');
      }
      for (final buffer in run.buffers) {
        if (_key(buffer.path) == _key(path) &&
            buffer.text != open.controller.text) {
          throw StateError('源文件已改变，无法定位旧暂停位置');
        }
      }
      final controller = open.controller;
      final line = location.line - 1;
      if (line < 0 || line >= controller.codeLines.lineCount) {
        throw StateError('调试器返回的源代码行不在文件内');
      }
      var mapped = controller.codeLines.lineIndex2Index(line);
      while (mapped.index >= 0 && mapped.chunkIndex >= 0) {
        controller.expandChunk(mapped.index);
        mapped = controller.codeLines.lineIndex2Index(line);
      }
      final offset = ((location.column ?? 1) - 1).clamp(
        0,
        controller.codeLines[mapped.index].text.length,
      );
      editor.select(editor.files.indexOf(open));
      controller.selection = CodeLineSelection.collapsed(
        index: mapped.index,
        offset: offset,
      );
      controller.makePositionVisible(
        CodeLinePosition(index: mapped.index, offset: offset),
      );
      open.focusNode.requestFocus();
    } on Object catch (error) {
      if (currentNavigation()) {
        _error = '无法定位调试源文件：$error';
        _notify();
      }
    }
  }

  Future<void> _watch(_DebugRun run) async {
    if (run.watching) return;
    run.watching = true;
    try {
      await run.session!.done;
    } on Object catch (error) {
      if (identical(_run, run)) _error = '调试器结束失败：$error';
    } finally {
      run.doneObserved = true;
      try {
        if (identical(_run, run)) _receive(run, run.session!.snapshot);
      } on Object catch (error) {
        if (identical(_run, run)) _error = '无法读取调试器最终状态：$error';
      }
      await _disposeSession(run);
    }
  }

  Future<void> _disposeSession(_DebugRun run) async {
    if (run.disposing || run.finished.isCompleted) return;
    run.cleanupRetry?.cancel();
    run.cleanupRetry = null;
    run.disposing = true;
    if (_closed) run.closeDisposalAttempts++;
    var retryClosedCleanup = false;
    try {
      await run.session!.dispose();
      await run.subscription?.cancel();
      if (identical(_run, run)) {
        _run = null;
        _selectedFrame = null;
      }
      run.finished.complete();
    } on Object catch (error) {
      // A cleanup error cannot release the lane. A later Stop retries disposal.
      run.stopRequested = true;
      retryClosedCleanup =
          _closed && run.closeDisposalAttempts < _maxCloseDisposalAttempts;
      if (identical(_run, run)) {
        _error =
            '调试器清理尚未完成：$error'
            '${_closed && !retryClosedCleanup ? '；自动重试已用尽，请再次停止或关闭以重试' : ''}';
      }
    } finally {
      run.disposing = false;
      if (retryClosedCleanup && !run.finished.isCompleted) {
        run.cleanupRetry = Timer(_closeDisposalRetryDelay, () {
          run.cleanupRetry = null;
          unawaited(_disposeSession(run));
        });
      }
      _notify();
    }
  }

  Future<void> _requestStop(_DebugRun run) async {
    final session = run.session;
    if (session == null || run.finished.isCompleted) return;
    if (run.doneObserved) {
      await _disposeSession(run);
      return;
    }
    if (run.stopInFlight) return;
    run.stopInFlight = true;
    try {
      await session.stop();
    } on Object catch (error) {
      if (identical(_run, run)) _error = '停止调试失败，仍在等待实际清理：$error';
    } finally {
      run.stopInFlight = false;
      _notify();
    }
  }

  Future<void> stop() async {
    final run = _run;
    if (run == null) return;
    if (_closed) run.closeDisposalAttempts = 0;
    run.stopRequested = true;
    _selectedFrame = null;
    _notify();
    unawaited(_requestStop(run));
    await run.finished.future;
  }

  Future<void> close() {
    if (_closeFuture != null) {
      unawaited(stop());
      return _closeFuture!;
    }
    _closed = true;
    editor.removeListener(_editorChanged);
    return _closeFuture = stop();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}

class _DebugBuffer {
  const _DebugBuffer(this.file, this.path, this.text, this.revision);
  final OpenFile file;
  final String path;
  final String text;
  final int revision;
}

class _DebugRun {
  _DebugRun({
    required this.root,
    required this.originalRoot,
    required this.ownerName,
    required this.ownerType,
    required this.capabilities,
    required this.buffers,
  });
  final String root;
  final String originalRoot;
  final String ownerName;
  final String ownerType;
  final DebugCapabilities capabilities;
  final List<_DebugBuffer> buffers;
  final finished = Completer<void>();
  final commands = <DebugCommand>{};
  DebugSession? session;
  StreamSubscription<DebugSnapshot>? subscription;
  bool starting = true;
  bool stopRequested = false;
  bool stopInFlight = false;
  bool watching = false;
  bool doneObserved = false;
  bool disposing = false;
  bool breakpointsPending = false;
  int closeDisposalAttempts = 0;
  Timer? cleanupRetry;
  int pauseGeneration = 0;
  DebugPauseToken? invalidPause;
}
