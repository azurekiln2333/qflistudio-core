import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:qfli_studio_core/editor/editor_page_diag.dart';
import '../services/local_audit_service.dart';
import '../services/local_stats_service.dart';

import 'package:flutter/material.dart';
import 'editor_fonts.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../i18n/studio_localizations.dart';
import '../services/process_supervisor.dart';
import '../services/api_client.dart';
import '../services/cloud_sql.dart';
import '../services/online_program.dart';
import '../store/auth_store.dart';
import '../services/app_paths.dart';
import '../services/studio_profile.dart';
import '../terminal/shell/shell_backend.dart' as shell;
import '../terminal/shell/local_shell.dart' as shell_io;
import '../terminal/widgets/terminal_input.dart';

/// Shared terminal panel height constants, used by both the pane and the editor
/// so they cannot drift apart.
abstract final class TerminalPanelMetrics {
  /// Height of the collapsed header row.
  static const double collapsedHeight = 40;

  /// Vertical breathing room above and below the session tab pills inside the
  /// header, so the tabs are not flush against the header's edges.
  static const double tabBarVerticalPadding = 4;

  /// Height of a session tab pill. Sized so `2 * tabBarVerticalPadding +
  /// tabHeight` together with the action buttons still fits [collapsedHeight].
  static const double tabHeight = 30;

  /// Widest a session tab pill may grow. Longer labels are ellipsised so a
  /// handful of tabs stay reachable without scrolling the bar.
  static const double maxTabWidth = 96;

  /// Horizontal padding inside a tab pill, around its label.
  static const double tabHorizontalPadding = 8;

  /// Height of the enlarged drag region above the panel content.
  static const double dragHandleHeight = 22;

  /// Total allocation when the panel is collapsed: the drag region plus the
  /// header, so the handle stays reachable and there is no overflow.
  static const double collapsedTotalHeight = dragHandleHeight + collapsedHeight;

  /// Smallest useful expanded height.
  static const double minExpandedHeight = 120;

  /// Default/preferred expanded height.
  static const double defaultExpandedHeight = 240;

  /// Dragging below this (measured from the viewport floor) collapses instead of
  /// clamping, with a small hysteresis band so a hover at the boundary does not
  /// flicker between states.
  static const double collapseThreshold = 72;
}

/// 本地终端面板：命令响应式 shell，沙箱权限内执行。
/// 移动端系统无编译器，复杂工具（gcc/python 等）需走在线终端。
class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.workingDirectory,
    required this.auth,
    this.onlineEnabled = true,
    this.executionBlocked = false,
    this.isExecutionBlocked,
    this.initialOnline = false,
    this.onClose,
    this.onCollapseChanged,
    this.onResizeDelta,
    this.onResizeStart,
    this.onResizeEnd,
    this.onActivated,
    this.onInputFocusChanged,
    this.onRunningWorkChanged,
    this.collapsed = false,
    this.compact = false,
  });

  final String workingDirectory;
  final AuthStore auth;
  final bool onlineEnabled;

  /// Blocks new commands while the editor's debugger owns execution.
  /// Existing work can still be interrupted and terminal tabs remain usable.
  final bool executionBlocked;

  /// Reads the owner's execution lane synchronously, before its next rebuild.
  final bool Function()? isExecutionBlocked;
  final bool initialOnline;
  final ValueChanged<bool>? onRunningWorkChanged;

  /// 用户点击面板上的关闭按钮时回调（编辑器隐藏整个面板）。
  final VoidCallback? onClose;

  /// 折叠状态变化回调（编辑器据此调整外层高度）。
  final ValueChanged<bool>? onCollapseChanged;

  /// Raw upward drag distance in logical pixels. Positive means the user is
  /// dragging the handle up (grow the panel).
  final ValueChanged<double>? onResizeDelta;

  /// Fired once when a resize drag starts/ends so the editor can suspend height
  /// animation and track the live displayed height.
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeEnd;

  /// Called when the user touches the terminal (its header or body).
  ///
  /// The editor uses it to expand a collapsed panel and to restore the user's
  /// preferred height; focus is handled by [TerminalPaneState.requestInputFocus]
  /// so the input is not focused before it is on screen.
  final VoidCallback? onActivated;

  /// Reports changes to the prompt input's focus state.
  ///
  /// The editor listens so it can avoid collapsing the panel to its header-only
  /// layout while the user is typing into a raised keyboard.
  final ValueChanged<bool>? onInputFocusChanged;

  /// Controlled collapsed state. The editor owns it; this pane only renders it
  /// and reports user intent.
  final bool collapsed;

  /// Shows only the panel header while the editor viewport is too short.
  final bool compact;

  @override
  State<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends State<TerminalPane> {
  final _sessions = <_TerminalSession>[];
  var _selectedSessionIndex = 0;
  var _nextSessionId = 1;
  bool _localCollapsed = false;
  final ProcessSupervisor _processSupervisor = ProcessSupervisor();
  ApiClient _api = ApiClient();
  String? _onlineToken;
  int _onlineGeneration = 0;
  bool _preparing = false;
  final _pendingCleanup = <Object>{};
  final _retiredSessions = <_TerminalSession>{};
  bool _reportedRunningWork = false;
  bool _runningWorkNotificationPending = false;

  /// A discarded focus node for the per-tab close buttons.
  ///
  /// The buttons must not become the primary focus (a tap would otherwise leave
  /// a detached node focused, and focus would then fall to the editor on
  /// mobile). Giving them a node that is never focused keeps the button usable
  /// without it joining the traversal order.
  final FocusNode _tabCloseFocusNode = FocusNode(
    debugLabel: 'terminal tab close',
    skipTraversal: true,
    canRequestFocus: false,
  );

  /// Sandbox root for local sessions.
  ///
  /// Defaults to the project directory and is upgraded to the app private data
  /// directory when that has already been resolved by the app (so the editor
  /// terminal can reach every project while starting in this project).
  /// Deliberately does not schedule an app-data probe from initState: that
  /// would create a pending timer under the test binding.
  String _sandboxRoot = '';

  /// Effective collapsed state: the parent's controlled value wins when it is
  /// wired, otherwise the pane keeps its own for standalone use.
  bool get _collapsed =>
      widget.onCollapseChanged != null ? widget.collapsed : _localCollapsed;

  void _setCollapsed(bool value) {
    if (_collapsed == value) return;
    if (widget.onCollapseChanged != null) {
      widget.onCollapseChanged?.call(value);
    } else {
      setState(() => _localCollapsed = value);
    }
  }

  bool get onlineSelected => _session.online;
  bool get busy => _session.running || _preparing;
  bool get _executionBlocked =>
      widget.executionBlocked || widget.isExecutionBlocked?.call() == true;

  /// Includes inactive tabs, dispatch preparation and pending tab cleanup.
  bool get hasRunningWork =>
      _preparing ||
      _pendingCleanup.isNotEmpty ||
      _retiredSessions.isNotEmpty ||
      _sessions.any(
        (session) =>
            session.running ||
            session.cancelAction != null ||
            session.hasUnfinishedCancellation ||
            session.backend?.busy == true,
      );

  void _notifyRunningWorkChanged() {
    if (!mounted || _runningWorkNotificationPending) return;
    _runningWorkNotificationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runningWorkNotificationPending = false;
      if (!mounted) return;
      final running = hasRunningWork;
      if (running == _reportedRunningWork) return;
      _reportedRunningWork = running;
      widget.onRunningWorkChanged?.call(running);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _trackCleanup(Future<void> Function() cleanup) async {
    final pending = Object();
    _pendingCleanup.add(pending);
    _notifyRunningWorkChanged();
    try {
      await cleanup();
    } finally {
      _pendingCleanup.remove(pending);
      if (mounted) setState(() {});
      _notifyRunningWorkChanged();
    }
  }

  void _retireSession(_TerminalSession session) {
    _retiredSessions.add(session);
    _notifyRunningWorkChanged();
    unawaited(
      _cleanupRetiredSession(session).catchError((Object error) {
        if (mounted) appendSystem('终端清理失败：$error');
      }),
    );
  }

  Future<void> _cleanupRetiredSession(
    _TerminalSession session, {
    bool retry = false,
  }) async {
    await (retry ? session.retryDispose() : session.dispose());
    if (!_retiredSessions.remove(session)) return;
    if (mounted) setState(() {});
    _notifyRunningWorkChanged();
  }

  /// Whether the terminal's prompt input currently holds focus.
  ///
  /// The editor needs this to decide whether it may collapse the panel to its
  /// compact (header-only) layout: doing so would hide a focused input behind a
  /// raised keyboard. See `EditorPage`'s `compactPanel` computation.
  bool get inputHasFocus => _session.focusNode.hasFocus;

  /// The prompt `FocusNode` currently being watched for focus changes.
  FocusNode? _watchedFocusNode;

  void _notifyInputFocusChanged() {
    final focused = _watchedFocusNode?.hasFocus ?? false;
    if (focused == _lastReportedInputFocus) return;
    _lastReportedInputFocus = focused;
    widget.onInputFocusChanged?.call(focused);
  }

  bool _lastReportedInputFocus = false;

  static const _maxLines = 500;

  _TerminalSession get _session => _sessions[_selectedSessionIndex];
  TextEditingController get _inputController => _session.inputController;
  List<String> get _history => _session.history;
  int get _historyIndex => _session.historyIndex;
  set _historyIndex(int value) => _session.historyIndex = value;
  bool get _running => _session.running;
  set _running(bool value) => _session.running = value;
  set _currentProcess(Process? value) => _session.currentProcess = value;

  @override
  void initState() {
    super.initState();
    // Use the already-resolved app data directory when the app has one; the
    // project directory otherwise. No probe is started here.
    _sandboxRoot =
        AppPaths.storageDirectoryIfResolved ?? widget.workingDirectory;
    _sessions.add(_createSession(_nextSessionId++));
    if (widget.initialOnline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(showOnline());
      });
    }
  }

  @override
  void dispose() {
    _tabCloseFocusNode.dispose();
    _watchedFocusNode?.removeListener(_notifyInputFocusChanged);
    _watchedFocusNode = null;
    unawaited(_processSupervisor.dispose());
    _onlineGeneration++;
    _api.close();
    final token = _onlineToken;
    if (token != null) unawaited(_releaseOnlineSession(token));
    for (final session in _sessions) {
      _retireSession(session);
    }
    super.dispose();
  }

  Future<void> _releaseOnlineSession(String token) async {
    final api = ApiClient();
    try {
      await api.resetTerminal(token);
    } on ApiException {
      // The server idle lease still bounds storage if the device is offline.
    } finally {
      api.close();
    }
  }

  void _newSession() {
    if (_preparing) return;
    _keepPromptFocusAfterSwap();
    setState(() {
      _sessions.add(_createSession(_nextSessionId++));
      _selectedSessionIndex = _sessions.length - 1;
    });
  }

  /// Creates a session and wires a direct scroll listener so follow tracking
  /// does not depend on scroll notifications surviving widget rebuilds.
  _TerminalSession _createSession(int id, {bool online = false}) {
    final session = _TerminalSession(id: id, online: online);
    session.listController.addListener(() => _trackFollow(session));
    return session;
  }

  /// Set by the expanded header's Listener so the pane-wide Listener can tell
  /// a header touch from a body touch.
  bool _pointerInExpandedHeader = false;

  /// Call before a tab swap that disposes or unmounts the focused prompt.
  ///
  /// When the focused node goes away, FocusManager falls back through the
  /// route scope's history, which lands on the editor (and raises its IME on
  /// OHOS). Re-focus the prompt of the session now on screen instead. Only
  /// when the prompt was focused, so header actions never change IME state;
  /// the "more" menu keeps focus in place (`requestFocus: false`).
  void _keepPromptFocusAfterSwap() {
    if (!_sessions.any((s) => s.focusNode.hasFocus)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => requestInputFocus());
  }

  void _selectSession(int index) {
    if (_preparing) return;
    if (index == _selectedSessionIndex ||
        index < 0 ||
        index >= _sessions.length) {
      return;
    }
    setState(() => _selectedSessionIndex = index);
    // Remember whether the caret was already in the transcript before the tab
    // tap took the pointer. `TapRegion`/`InkWell` focus changes have not run
    // yet at this point, so this reads the pre-tap state.
    final promptHadFocus = _sessions.any((s) => s.focusNode.hasFocus);
    // Restore the newly active session's own scroll offset after the list has
    // laid out with its controller.
    final session = _session;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || session.disposed) return;
      final controller = session.listController;
      if (controller.hasClients) {
        final target = session.follow
            ? controller.position.maxScrollExtent
            : session.scrollOffset;
        controller.jumpTo(
          target.clamp(0.0, controller.position.maxScrollExtent).toDouble(),
        );
      }
      // The tab is terminal chrome, so selecting one must leave the caret in the
      // prompt of the session now on screen. This runs *after* the scroll
      // restore on purpose: focusing the prompt scrolls the transcript to the
      // bottom, which would otherwise overwrite the offset just restored.
      //
      // Focus is only moved when it already belonged to the terminal: a keyboard
      // user tabbing through the pills owns the focus themselves and must keep
      // it so Enter can select a tab. What this prevents is the earlier
      // behaviour where a *pointer* tap on a pill left the terminal with no
      // focused input, so the next touch fell through to the editor.
      if (promptHadFocus) requestInputFocus();
    });
  }

  void _closeSession(int index) {
    if (_preparing) return;
    if (index < 0 || index >= _sessions.length) {
      return;
    }
    _keepPromptFocusAfterSwap();
    // Closing the last local tab must not leave the pane with nothing to show.
    // Rather than refusing (which made a single tab unclosable) or leaving an
    // empty pane, the closed session is replaced by a fresh one, so the visible
    // result is a cleared terminal. This mirrors what the user expects from
    // "close" when there is no other tab to fall back to.
    if (_sessions.length == 1) {
      final only = _sessions.first;
      if (only.online) return;
      final replacement = _TerminalSession(id: only.id);
      _sessions[0] = replacement;
      _retireSession(only);
      setState(() {
        _selectedSessionIndex = 0;
      });
      return;
    }
    final session = _sessions.removeAt(index);
    if (session.online) {
      _onlineGeneration++;
      _api.close();
      _api = ApiClient();
    }
    _retireSession(session);
    setState(() {
      if (_selectedSessionIndex > index) {
        _selectedSessionIndex--;
      } else if (_selectedSessionIndex >= _sessions.length) {
        _selectedSessionIndex = _sessions.length - 1;
      }
    });
  }

  Future<void> _run(String command) async {
    if (!mounted ||
        _executionBlocked ||
        _preparing ||
        _session.hasUnfinishedCancellation) {
      return;
    }
    if (_session.online) {
      await _runOnline(command);
      return;
    }
    final trimmed = command.trim();
    final session = _session;
    if (trimmed.isEmpty || session.running) return;
    // Reserve the session before backend preparation yields to Debug or a tab
    // switch. Recheck the editor's execution fence immediately before dispatch.
    setState(() => session.running = true);
    _notifyRunningWorkChanged();
    shell.ShellBackend? backend;
    final execution = () async {
      try {
        backend = await _backendFor(session);
        if (!mounted || session.disposed || _executionBlocked) return;
        unawaited(LocalStatsService.instance.recordTerminalCommand());
        unawaited(
          LocalAuditService.instance.record(
            kind: LocalAuditKind.terminal,
            action: '执行 $trimmed',
            project: p.basename(widget.workingDirectory),
            detail: '本地会话',
          ),
        );
        session.history.add(trimmed);
        session.historyIndex = session.history.length;
        setState(() {
          _append(
            _TermLine(
              text: '${_promptFor(session)} $trimmed',
              kind: _LineKind.command,
            ),
            session,
          );
          session.pendingStdout = null;
          session.pendingStderr = null;
          session.cancelAction = () => backend!.interrupt();
        });
        if (!session.follow) session.follow = true;
        _scrollToBottom(session, true);
        await backend!.execute(trimmed);
      } finally {
        if (mounted && !session.disposed) {
          setState(() {
            session.running = false;
            session.cancelAction = null;
            session.pendingStdout = null;
            session.pendingStderr = null;
          });
          _notifyRunningWorkChanged();
        }
      }
    }();
    session.commandDone = execution;
    try {
      await execution;
    } finally {
      if (identical(session.commandDone, execution)) session.commandDone = null;
    }
    if (!mounted || session.disposed) return;
    final code = backend?.lastExitCode;
    if (code != null && code != 0) {
      setState(() {
        // Keep the real numeric status visible, matching attached runs.
        _append(
          _TermLine(text: 'exit code $code', kind: _LineKind.stderr),
          session,
        );
      });
      _scrollToBottom(session);
    }
  }

  /// Lazily creates the single [shell.ShellBackend] that owns this local
  /// session's cwd, execution state, output, and cancellation.
  ///
  /// Uses the unified sandbox backend rooted at the app private data directory
  /// (so cross-project paths are reachable) and starts in the current project
  /// directory. Language toolchains (`javac`/`java`, `python`, ...) are supplied
  /// by the host profile's [StudioProfile.terminalCommandDelegate].
  Future<shell.ShellBackend> _backendFor(_TerminalSession session) async {
    final existing = session.backend;
    if (existing != null) return existing;
    final root = _sandboxRoot.isEmpty ? widget.workingDirectory : _sandboxRoot;
    final backend = shell_io.createSandboxShell(
      sandboxRoot: root,
      startDirectory: widget.workingDirectory,
      label: StudioProfile.current?.appTitle ?? 'Sandbox',
      delegate: StudioProfile.current?.terminalCommandDelegate,
    );
    session.backend = backend;
    session.backendSub = backend.output.listen(
      (chunk) => _onBackendChunk(session, chunk),
    );
    backend.addListener(() => _onBackendState(session, backend));
    return backend;
  }

  void _onBackendChunk(_TerminalSession session, shell.ShellChunk chunk) {
    if (!mounted || session.disposed) return;
    switch (chunk.kind) {
      case shell.OutputKind.control:
        // `clear`/`cls`: reset only this session's transcript and any partial
        // line. cwd, history, and session identity are untouched.
        setState(() => _clearTranscript(session));
      case shell.OutputKind.stderr:
        setState(() => _appendManaged(session, chunk.text, _LineKind.stderr));
      case shell.OutputKind.system:
        setState(() => _appendManaged(session, chunk.text, _LineKind.info));
      case shell.OutputKind.stdout:
        setState(() => _appendManaged(session, chunk.text, _LineKind.stdout));
    }
    _scrollToBottom(session);
  }

  /// Mirrors the backend's busy flag onto the session, while leaving the pane's
  /// own preparation/online ownership untouched.
  void _onBackendState(_TerminalSession session, shell.ShellBackend backend) {
    if (!mounted || session.disposed) return;
    final busy = backend.busy;
    if (session.running == busy) return;
    setState(() => session.running = busy);
    _notifyRunningWorkChanged();
  }

  /// Appends a backend chunk, splitting embedded newlines the way streaming
  /// output does so partial lines stay on the same row.
  void _appendManaged(_TerminalSession session, String text, _LineKind kind) {
    if (text.isEmpty) return;
    final pending = kind == _LineKind.stderr
        ? session.pendingStderr
        : session.pendingStdout;
    var combined = '${pending?.text ?? ''}$text';
    if (pending != null) session.outputLines.remove(pending);
    combined = combined.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = combined.split('\n');
    for (final line in parts.take(parts.length - 1)) {
      _append(_TermLine(text: line, kind: kind), session);
    }
    final last = parts.last.isEmpty
        ? null
        : _TermLine(text: parts.last, kind: kind);
    if (last != null) _append(last, session);
    if (kind == _LineKind.stderr) {
      session.pendingStderr = last;
    } else {
      session.pendingStdout = last;
    }
  }

  /// Clears the visible transcript and any partial line without touching cwd,
  /// history, running work, or the session's identity.
  void _clearTranscript(_TerminalSession session) {
    session.outputLines.clear();
    session.pendingStdout = null;
    session.pendingStderr = null;
  }

  void expand() {
    if (!mounted) return;
    _setCollapsed(false);
  }

  /// Dismisses the soft keyboard/focus without changing session state. Used
  /// while a resize gesture owns the pointer.
  void unfocusInput() {
    final session = _session;
    if (session.focusNode.hasFocus) {
      session.focusNode.unfocus();
    }
  }

  /// Interrupts the active session's running work: the attached-run cancel
  /// callback when present, otherwise the local shell backend. Also retries
  /// unfinished cleanup belonging to closed tabs.
  Future<void> interruptActive() async {
    final session = _session;
    final retired = _retiredSessions.toList();
    await _trackCleanup(() async {
      await Future.wait<void>([
        session.interrupt(),
        for (final closed in retired)
          _cleanupRetiredSession(closed, retry: true),
      ], eagerError: false);
    });
  }

  Future<void> _interruptFromUi() async {
    final session = _session;
    try {
      await interruptActive();
    } catch (error) {
      if (!mounted || session.disposed) return;
      setState(() {
        _append(
          _TermLine(text: '终端停止失败：$error', kind: _LineKind.info),
          session,
        );
      });
      _scrollToBottom(session);
    }
  }

  /// Marks the pane busy while the caller prepares a run. An empty [title] only
  /// flips the busy state; a non-empty one is appended as a system line.
  void beginPreparation([String? title]) {
    expand();
    final text = title?.trim() ?? '';
    setState(() {
      _preparing = true;
      _running = true;
      if (text.isNotEmpty) {
        _append(_TermLine(text: text, kind: _LineKind.info));
      }
    });
    _notifyRunningWorkChanged();
    _scrollToBottom();
  }

  void finishPreparation() {
    if (!mounted || !_preparing) return;
    setState(() {
      _preparing = false;
      _running = false;
    });
    _notifyRunningWorkChanged();
  }

  Future<void> showOnline({bool initialize = true}) async {
    if (!mounted || _preparing) return;
    if (!widget.onlineEnabled) return;
    var index = _sessions.indexWhere((session) => session.online);
    setState(() {
      if (index < 0) {
        _sessions.add(_createSession(0, online: true));
        index = _sessions.length - 1;
      }
      _selectedSessionIndex = index;
    });
    expand();
    if (initialize &&
        !_executionBlocked &&
        !_session.initialized &&
        !_session.running) {
      await _runOnline(':', initializing: true);
    }
  }

  Future<void> runOnlineProject(String projectPath, String entryFile) async {
    if (!mounted || !widget.onlineEnabled || _executionBlocked) return;
    await showOnline(initialize: false);
    if (!mounted ||
        _executionBlocked ||
        busy ||
        _session.hasUnfinishedCancellation) {
      return;
    }
    beginPreparation();
    try {
      final program = await OnlineProgram.prepare(projectPath, entryFile);
      if (!mounted || _executionBlocked) return;
      finishPreparation();
      await _runOnline(program.command, files: program.files);
    } catch (error) {
      if (!mounted) return;
      finishPreparation();
      appendSystem('$error');
    } finally {
      finishPreparation();
    }
  }

  /// Runs a `.sql` entry in the user's cloud MySQL practice space, a separate
  /// server from the business database. Output lands in the current session.
  Future<void> runCloudSql(String entryFile) async {
    if (!mounted ||
        !widget.onlineEnabled ||
        _executionBlocked ||
        busy ||
        _session.hasUnfinishedCancellation) {
      return;
    }
    final token = widget.auth.token;
    if (token == null) {
      appendSystem('请先登录后使用云 MySQL');
      return;
    }
    beginPreparation();
    try {
      final source = await File(entryFile).readAsString();
      if (!mounted || _executionBlocked) return;
      final raw = await _api.sqlScript(token, source: source);
      if (!mounted) return;
      final output = CloudSqlOutput.fromScript(raw);
      finishPreparation();
      await attachOutput(
        title: '云 MySQL · ${p.basename(entryFile)}',
        stdout: Stream<String>.fromIterable(output.stdout),
        stderr: Stream<String>.fromIterable(output.stderr),
        exitCode: Future<int>.value(output.exitCode),
      );
    } on FileSystemException catch (error) {
      if (mounted) appendSystem('无法读取 SQL 文件：${error.message}');
    } on ApiException catch (error) {
      if (mounted) appendSystem(error.message);
    } finally {
      finishPreparation();
    }
  }

  Future<void> _runOnline(
    String command, {
    bool initializing = false,
    List<Map<String, String>>? files,
  }) async {
    final session = _session;
    final trimmed = command.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 2000 ||
        _executionBlocked ||
        session.running ||
        session.hasUnfinishedCancellation ||
        _preparing) {
      return;
    }
    final token = widget.auth.token;
    if (token == null) {
      appendSystem('请先登录后使用在线终端');
      return;
    }
    _onlineToken = token;
    final generation = _onlineGeneration;
    session.history.add(trimmed);
    if (session.history.length > 100) session.history.removeAt(0);
    session.historyIndex = session.history.length;
    session.inputController.clear();
    setState(() {
      session.running = true;
      session.cancelAction = _cancelOnline;
      session.pendingStdout = null;
      session.pendingStderr = null;
      _append(
        _TermLine(
          text: initializing ? '连接在线终端...' : '/workspace\$ $trimmed',
          kind: _LineKind.command,
        ),
        session,
      );
    });
    _notifyRunningWorkChanged();
    _scrollToBottom(session);
    try {
      await for (final event in _api.terminalEvents(
        token,
        trimmed,
        files: files,
      )) {
        if (!mounted || session.disposed || generation != _onlineGeneration) {
          return;
        }
        setState(() {
          switch (event.type) {
            case TerminalEventType.progress:
              final text = switch (event.stage) {
                'queued' => '排队中：前方 ${(event.position ?? 1) - 1} 个请求',
                'initializing' => '初始化隔离环境...',
                'ready' => '在线终端已就绪',
                'uploading' => '传送项目副本...',
                'running' => initializing ? '检查会话...' : '执行中...',
                'cleaning' => '清理执行进程...',
                _ => '连接中...',
              };
              _append(_TermLine(text: text, kind: _LineKind.info), session);
              if (event.stage == 'ready') session.initialized = true;
            case TerminalEventType.stdout:
              _appendChunk(event.text!, _LineKind.stdout, session);
            case TerminalEventType.stderr:
              _appendChunk(event.text!, _LineKind.stderr, session);
            case TerminalEventType.result:
              session.initialized = true;
              if (!initializing && event.exitCode != 0) {
                _append(
                  _TermLine(
                    text: 'exit code ${event.exitCode}',
                    kind: _LineKind.stderr,
                  ),
                  session,
                );
              }
          }
        });
        _scrollToBottom(session);
      }
    } catch (error) {
      if (!mounted || session.disposed || generation != _onlineGeneration) {
        return;
      }
      _api.close();
      _api = ApiClient();
      setState(() {
        session.initialized = false;
        _append(_TermLine(text: '$error', kind: _LineKind.stderr), session);
      });
      _scrollToBottom(session);
    } finally {
      if (mounted && !session.disposed && generation == _onlineGeneration) {
        setState(() {
          session.running = false;
          session.cancelAction = null;
          session.pendingStdout = null;
          session.pendingStderr = null;
        });
      }
      _notifyRunningWorkChanged();
    }
  }

  void _appendChunk(String text, _LineKind kind, _TerminalSession session) {
    final pending = kind == _LineKind.stdout
        ? session.pendingStdout
        : session.pendingStderr;
    final combined = '${pending?.text ?? ''}$text';
    if (pending != null) session.outputLines.remove(pending);
    final lines = combined.split('\n');
    for (final line in lines.take(lines.length - 1)) {
      _append(_TermLine(text: line.replaceAll('\r', ''), kind: kind), session);
    }
    final last = lines.last.isEmpty
        ? null
        : _TermLine(text: lines.last, kind: kind);
    if (last != null) _append(last, session);
    if (kind == _LineKind.stdout) {
      session.pendingStdout = last;
    } else {
      session.pendingStderr = last;
    }
  }

  Future<void> _cancelOnline() async {
    _onlineGeneration++;
    _api.close();
    _api = ApiClient();
    final index = _sessions.indexWhere((session) => session.online);
    if (index < 0 || !mounted) return;
    final session = _sessions[index];
    setState(() {
      session.initialized = false;
      session.cancelAction = null;
      session.running = true;
      session.pendingStdout = null;
      session.pendingStderr = null;
      _append(_TermLine(text: '回收在线会话...', kind: _LineKind.info), session);
    });
    _notifyRunningWorkChanged();
    try {
      final token = _onlineToken ?? widget.auth.token;
      if (token != null) await _api.resetTerminal(token);
      if (mounted && !session.disposed) {
        setState(
          () => _append(
            _TermLine(text: '在线会话已回收', kind: _LineKind.info),
            session,
          ),
        );
      }
    } catch (error) {
      if (mounted && !session.disposed) {
        setState(
          () => _append(
            _TermLine(text: '$error', kind: _LineKind.stderr),
            session,
          ),
        );
      }
    } finally {
      if (mounted && !session.disposed) setState(() => session.running = false);
      _notifyRunningWorkChanged();
      _scrollToBottom(session);
    }
  }

  Future<void> _resetOnline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置终端会话？'),
        content: const Text('终端临时文件将被清除，云项目不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _cancelOnline();
  }

  void _append(_TermLine line, [_TerminalSession? target]) {
    final session = target ?? _session;
    session.outputLines.add(line);
    if (session.outputLines.length > _maxLines) {
      session.outputLines.removeRange(
        0,
        session.outputLines.length - _maxLines,
      );
    }
  }

  /// Scrolls the given session to the bottom only when it is following output.
  ///
  /// `force` is for explicit actions (command submission, focus-to-input) where
  /// the user clearly wants to see the latest prompt.
  void _scrollToBottom([_TerminalSession? target, bool force = false]) {
    final session = target ?? _session;
    if (!force && !session.follow) return;
    final controller = session.listController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || session.disposed) return;
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
  }

  /// Recomputes whether [session] should keep following the bottom.
  void _trackFollow(_TerminalSession session) {
    final controller = session.listController;
    if (!controller.hasClients) return;
    final position = controller.position;
    session.scrollOffset = position.pixels;
    const slack = 32.0;
    final atBottom = position.pixels >= position.maxScrollExtent - slack;
    if (atBottom != session.follow) {
      session.follow = atBottom;
    }
  }

  /// Brings the active session's prompt into view and focuses its input, even
  /// when the lazy list has not mounted the field yet.
  ///
  /// Uses [TerminalInputBehavior.restoreKeyboard] so that the soft keyboard is
  /// raised even when the field is already focused on the Flutter side but the
  /// platform IME connection was severed (e.g. the code editor temporarily took
  /// focus on OHOS and the keyboard was dismissed).
  void _focusInput(_TerminalSession session) {
    if (!mounted || session.disposed) return;
    if (session.running || _preparing) return;
    session.follow = true;
    _scrollToBottom(session, true);
    // restoreKeyboard, not focusAndShowKeyboard: after the editor has ever taken
    // focus the prompt's Flutter focusNode can still report hasFocus while the
    // platform IME is detached. focusAndShowKeyboard returns early on hasFocus
    // and would leave the keyboard down with a Return key that does nothing.
    TerminalInputBehavior.restoreKeyboard(session.focusNode);
  }

  /// Focuses the active session's prompt exactly as a user tap on the terminal
  /// does, without going through the pointer/deferred-tap machinery.
  ///
  /// Used by the editor after it expands a collapsed panel (focusing while the
  /// input is off screen would be lost), and by widget tests that need to
  /// establish "the user has focused the input".
  void focusInput() {
    final session = _session;
    if (session.disposed) return;
    _focusInput(session);
  }

  void _submit() {
    if (_executionBlocked || _preparing || _session.hasUnfinishedCancellation) {
      return;
    }
    final session = _session;
    final text = session.inputController.text;
    session.inputController.clear();
    _run(text);
    // Return must not drop focus on mobile: the keyboard stays up.
    if (mounted && session.focusNode.canRequestFocus) {
      session.focusNode.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Hardware Return submits, so a physical keyboard behaves like the soft one.
    //
    // This handler is for physical keys only. The OHOS soft keyboard's Return
    // does not come through here: the engine turns `EnterKeyType.UNSPECIFIED`
    // into `TextInputClient.performAction("TextInputAction.unspecified")`, a
    // platform message that `EditableText` routes to `onSubmitted` (see
    // [TerminalInputBehavior]). Do not add soft-keyboard detection here; there
    // is nothing for it to detect.
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _history.isNotEmpty &&
        _historyIndex > 0) {
      _historyIndex--;
      _inputController.text = _history[_historyIndex];
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _historyIndex < _history.length) {
      _historyIndex++;
      _inputController.text = _historyIndex == _history.length
          ? ''
          : _history[_historyIndex];
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Attaches a legacy process and observes attachment failures.
  void attachProcess(
    String title,
    Process process, {
    void Function(String text, bool isError)? onOutput,
    ValueChanged<int>? onExit,
  }) {
    final session = _session;
    _currentProcess = process;
    _observeAttachedOutput(
      session,
      attachOutput(
        title: title,
        stdout: process.stdout
            .transform(systemEncoding.decoder)
            .transform(const LineSplitter()),
        stderr: process.stderr
            .transform(systemEncoding.decoder)
            .transform(const LineSplitter()),
        exitCode: process.exitCode,
        cancel: () async {
          process.kill();
          await process.exitCode;
        },
        onOutput: onOutput,
        onExit: onExit,
      ),
    );
  }

  /// Attaches a process already owned by a [ProcessSupervisor].
  void attachManagedProcess(
    String title,
    ManagedProcess process, {
    void Function(String text, bool isError)? onOutput,
    ValueChanged<int>? onExit,
  }) {
    final session = _session;
    session.currentManagedProcess = process;
    _observeAttachedOutput(
      session,
      attachOutput(
        title: title,
        stdout: process.stdout
            .transform(systemEncoding.decoder)
            .transform(const LineSplitter()),
        stderr: process.stderr
            .transform(systemEncoding.decoder)
            .transform(const LineSplitter()),
        exitCode: process.exitCode,
        cancel: process.cancel,
        onOutput: onOutput,
        onExit: onExit,
      ),
    );
  }

  void _observeAttachedOutput(_TerminalSession session, Future<int> result) {
    unawaited(
      result.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted || session.disposed) return;
          setState(() {
            _append(
              _TermLine(text: 'Output failed: $error', kind: _LineKind.info),
              session,
            );
          });
          _scrollToBottom(session);
        },
      ),
    );
  }

  /// Owns line streams until both drain and the actual worker exit is observed.
  /// A stream/observer failure is reported to the caller after safe completion.
  /// An exceptional exit future leaves ownership blocked: it proves no exit.
  Future<int> attachOutput({
    required String title,
    required Stream<String> stdout,
    required Stream<String> stderr,
    required Future<int> exitCode,
    Future<void> Function()? cancel,
    void Function(String text, bool isError)? onOutput,
    ValueChanged<int>? onExit,
  }) {
    final session = _session;
    final attachment = Object();
    session.attachedRun = attachment;
    session.cancelAction = cancel;
    session.attachedExitCode = exitCode;
    session.follow = true;
    setState(() {
      final command = title.trim();
      if (command.isNotEmpty) {
        _append(
          _TermLine(text: _promptLine(command), kind: _LineKind.command),
          session,
        );
      }
      session.pendingStdout = null;
      session.pendingStderr = null;
      session.running = true;
    });
    _notifyRunningWorkChanged();
    _scrollToBottom(session, true);

    Object? firstError;
    StackTrace? firstStack;
    int? terminalCode;
    var cancellationRequested = false;
    bool current() => identical(session.attachedRun, attachment);

    void fail(Object error, StackTrace stackTrace, {bool stopWorker = true}) {
      firstError ??= error;
      firstStack ??= stackTrace;
      if (!stopWorker ||
          terminalCode != null ||
          cancellationRequested ||
          !current()) {
        return;
      }
      cancellationRequested = true;
      // Share Stop's in-flight cancellation and retained failure/retry action.
      unawaited(
        session.interrupt().then<void>(
          (_) => _notifyRunningWorkChanged(),
          onError: (Object cleanupError, StackTrace cleanupStack) {
            if (mounted && !session.disposed && current()) {
              setState(() {
                _append(
                  _TermLine(
                    text: 'Output cleanup failed: $cleanupError',
                    kind: _LineKind.info,
                  ),
                  session,
                );
              });
              _scrollToBottom(session);
            }
            _notifyRunningWorkChanged();
          },
        ),
      );
    }

    // Register immediately, before waiting for either stream. A failed exit
    // future must be handled even while output remains open indefinitely.
    final observedExit = exitCode.then<void>(
      (code) {
        terminalCode = code;
      },
      onError: (Object error, StackTrace stackTrace) => fail(error, stackTrace),
    );

    Future<void> consume(Stream<String> stream, bool isError) {
      try {
        return stream
            .listen((line) {
              if (!mounted || session.disposed || !current()) return;
              try {
                onOutput?.call(line, isError);
              } on Object catch (error, stackTrace) {
                fail(error, stackTrace, stopWorker: false);
              }
              if (!mounted || session.disposed || !current()) return;
              setState(() {
                _append(
                  _TermLine(
                    text: line,
                    kind: isError ? _LineKind.stderr : _LineKind.stdout,
                  ),
                  session,
                );
              });
              _scrollToBottom(session);
            })
            .asFuture<void>()
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {
                // asFuture cancels the bad subscription. A transport that never
                // closes after its error must not hide an observed worker exit.
                fail(error, stackTrace);
              },
            );
      } on Object catch (error, stackTrace) {
        fail(error, stackTrace);
        return Future<void>.value();
      }
    }

    final outDone = consume(stdout, false);
    final errDone = consume(stderr, true);
    return () async {
      await Future.wait<void>([outDone, errDone, observedExit]);
      final code = terminalCode;
      if (code != null && current()) {
        // An older attachment must never clear a replacement worker's state.
        session.attachedRun = null;
        session.currentProcess = null;
        session.currentManagedProcess = null;
        session.cancelAction = null;
        if (identical(session.attachedExitCode, exitCode)) {
          session.attachedExitCode = null;
        }
        session.running = false;
        if (mounted && !session.disposed) {
          try {
            onExit?.call(code);
          } on Object catch (error, stackTrace) {
            fail(error, stackTrace, stopWorker: false);
          }
          setState(() {
            if (code != 0) {
              _append(
                _TermLine(text: 'exit code $code', kind: _LineKind.stderr),
                session,
              );
            }
          });
          _scrollToBottom(session);
        }
        _notifyRunningWorkChanged();
      }
      final error = firstError;
      if (error != null) Error.throwWithStackTrace(error, firstStack!);
      // A non-error exit observer always supplies a real integer exit code.
      return code!;
    }();
  }

  /// 追加调试输出行（Web 预览 console 转发）。
  void appendDebug(String text) {
    setState(() {
      _append(_TermLine(text: text, kind: _LineKind.debug));
    });
    _scrollToBottom();
  }

  /// 追加系统提示行。
  void appendSystem(String text) {
    setState(() {
      _append(_TermLine(text: text, kind: _LineKind.info));
    });
    _scrollToBottom();
  }

  /// Enlarged, always-present drag region for resizing the panel. Uses a
  /// vertical-drag gesture with start/update/end so the editor can suspend
  /// animation and track the live displayed height.
  Widget _buildResizeHandle(ColorScheme scheme) {
    final onDelta = widget.onResizeDelta;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onDelta == null
          ? null
          : (_) => widget.onResizeStart?.call(),
      onVerticalDragUpdate: onDelta == null
          ? null
          : (details) => onDelta(-details.delta.dy),
      onVerticalDragEnd: onDelta == null
          ? null
          : (_) => widget.onResizeEnd?.call(),
      onVerticalDragCancel: onDelta == null
          ? null
          : () => widget.onResizeEnd?.call(),
      child: MouseRegion(
        cursor: onDelta == null
            ? MouseCursor.defer
            : SystemMouseCursors.resizeRow,
        child: Container(
          height: TerminalPanelMetrics.dragHandleHeight,
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Container(
            width: 48,
            height: 3,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = StudioLocalizations.of(context);
    // `collapsed` and `compact` must not unmount the prompt's TextField.
    //
    // A keyboard-driven body shrink flips `compact` (EditorPage's
    // `compactPanel`). If that swapped in a different subtree, the input's
    // element would be destroyed, its FocusNode detached, and the platform IME
    // closed — the "keyboard pops then immediately closes" bug.
    //
    // The Column therefore has the same two slots in every mode: a header and a
    // body. Only the body's *height* changes; it collapses to zero rather than
    // being removed, so the transcript's element path — and the prompt's
    // FocusNode inside it — is preserved.
    final headerOnly = _collapsed || widget.compact;
    // A raw `Listener` observes a touch anywhere on the pane (header or body)
    // without competing for gestures, so the transcript's own taps, selection
    // and scrolling are untouched. It only reports "the user touched the
    // terminal"; the editor decides what that means for the layout.
    return Listener(
      // Header chrome (tabs, "more", collapse) must not focus the prompt: that
      // raised the soft keyboard on every button tap, and the popup menu then
      // took focus and dismissed it again. The expanded header's own Listener
      // runs first (deepest hit wins) and flags the touch.
      onPointerDown: (_) {
        final fromHeader = _pointerInExpandedHeader;
        _pointerInExpandedHeader = false;
        if (!fromHeader) widget.onActivated?.call();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact && widget.onResizeDelta != null)
            _buildResizeHandle(scheme),
          if (headerOnly)
            if (widget.compact)
              Expanded(child: _buildCollapsedHeader(context, l10n, scheme))
            else
              _buildCollapsedHeader(context, l10n, scheme)
          else
            _buildExpandedHeader(context, l10n, scheme),
          // Exactly one body slot with an identical widget chain in both modes,
          // so the transcript's element path — and the prompt's FocusNode inside
          // it — is preserved across the switch. `Flexible` plus a zero-height
          // box collapses the slot without removing it: zero is still a bounded
          // height, which the transcript's ListView requires, whereas an offstage
          // or unbounded slot would assert.
          Flexible(
            fit: FlexFit.loose,
            child: SizedBox(
              width: double.infinity,
              height: headerOnly ? 0 : null,
              child: _buildBody(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Focuses the terminal input as if the user had tapped it.
  ///
  /// Public so the editor can move focus to the input after it expands a
  /// collapsed panel; focusing before the input is on screen would be lost.
  void requestInputFocus() {
    if (!mounted) return;
    focusInput();
  }

  /// Number of open sessions.
  ///
  /// Exposed for tests that assert tab open/close behaviour, which is otherwise
  /// only observable through the rendered tab pills.
  @visibleForTesting
  int get sessionCount => _sessions.length;

  /// Adds a local session, as the header's "new terminal" action does.
  @visibleForTesting
  void addSession() => _newSession();

  /// The header row shown when the pane is collapsed or compact.
  Widget _buildCollapsedHeader(
    BuildContext context,
    StudioLocalizations l10n,
    ColorScheme scheme,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.compact
          ? null
          : () {
              _setCollapsed(false);
              widget.onResizeEnd?.call();
            },
      child: Container(
        height: widget.compact ? null : TerminalPanelMetrics.collapsedHeight,
        color: scheme.surfaceContainerHigh,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.terminal, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.compact ? l10n.terminal : l10n.terminalCollapsed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!widget.compact)
              IconButton(
                tooltip: '展开终端',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  _setCollapsed(false);
                  widget.onResizeEnd?.call();
                },
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              ),
            IconButton(
              tooltip: l10n.close,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  /// The header row shown when the pane is expanded: session tabs and actions.
  Widget _buildExpandedHeader(
    BuildContext context,
    StudioLocalizations l10n,
    ColorScheme scheme,
  ) {
    return GestureDetector(
      // The header paints an opaque colour, but a coloured `Container` does not
      // absorb pointer events on its empty areas: a tap in the gap beside the
      // tabs would fall through to whatever is beneath the pane (on mobile, the
      // editor), moving focus there. An opaque detector consumes the event and
      // keeps the touch inside the terminal.
      behavior: HitTestBehavior.opaque,
      // Tapping the header chrome is a statement of intent about the terminal,
      // not the editor, so it must never collapse the panel.
      onTap: () {},
      // TEMP-DIAG (remove after device verification): report every pointer that
      // reaches the header, and what the global focus is at that moment.
      onTapDown: (details) => EditorPageDiag.diag(
        'pane header onTapDown local=${details.localPosition} '
        'focus=${FocusManager.instance.primaryFocus?.debugLabel}',
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          _pointerInExpandedHeader = true;
          EditorPageDiag.diag(
            'pane header Listener.onPointerDown '
            'focus=${FocusManager.instance.primaryFocus?.debugLabel}',
          );
        },
        child: Container(
          height: TerminalPanelMetrics.collapsedHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.surfaceContainerHigh,
          child: Row(
            // The tab pills bring their own vertical padding; the action buttons
            // are shorter than the header, so centre rather than stretch the row.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _buildSessionTabs(context)),
              if (_running)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (widget.onlineEnabled && !_session.online)
                IconButton(
                  tooltip: '在线终端',
                  // A header button must never become the focused control: on
                  // mobile that closes the terminal's IME and, worse, lets the
                  // next touch land on the editor. Focus stays with the prompt.
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: _preparing ? null : () => unawaited(showOnline()),
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                ),
              if (_session.cancelAction != null ||
                  _session.hasUnfinishedCancellation ||
                  _retiredSessions.isNotEmpty)
                IconButton(
                  tooltip: '停止',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => unawaited(_interruptFromUi()),
                  icon: const Icon(Icons.stop, size: 18),
                ),
              SizedBox(
                width: 36,
                height: 36,
                child: PopupMenuButton<String>(
                  tooltip: '终端操作',
                  // Keep focus (and the IME) where it is while the menu shows.
                  requestFocus: false,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (action) {
                    switch (action) {
                      case 'clear':
                        setState(() {
                          _session.outputLines.clear();
                          _session.pendingStdout = null;
                          _session.pendingStderr = null;
                        });
                      case 'new':
                        _newSession();
                      case 'reset':
                        unawaited(_resetOnline());
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.clear_all, size: 18),
                          SizedBox(width: 8),
                          Text('清屏'),
                        ],
                      ),
                    ),
                    if (!_session.online)
                      PopupMenuItem(
                        value: 'new',
                        enabled: !_preparing,
                        child: Row(
                          children: [
                            const Icon(Icons.add, size: 18),
                            const SizedBox(width: 8),
                            Text(l10n.newTerminal),
                          ],
                        ),
                      ),
                    if (_session.online)
                      PopupMenuItem(
                        value: 'reset',
                        enabled: !_running && !_preparing,
                        child: const Row(
                          children: [
                            Icon(Icons.restart_alt, size: 18),
                            SizedBox(width: 8),
                            Text('重置在线会话'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '收起终端',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => _setCollapsed(true),
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              ),
              IconButton(
                tooltip: l10n.close,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The body: the transcript list plus the interactive prompt.
  ///
  /// Always built from the same place in the widget tree so the prompt's
  /// element (and its FocusNode) survives a switch between the expanded and
  /// header-only layouts. See [build] for why that matters on OHOS.
  Widget _buildBody(BuildContext context) => _buildTranscript(context);

  /// Output + prompt share one scrollable document, wrapped in an explicit
  /// right-side scrollbar. A tap on empty canvas focuses the input, but only
  /// when it is a genuine tap (short, within slop) so text selection, long
  /// press, scrollbar dragging, and resize gestures keep their behaviour.
  Widget _buildTranscript(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = _session;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: (event) =>
              _handlePointerDown(session, event, constraints),
          onPointerMove: (event) => _handlePointerMove(session, event),
          onPointerUp: (event) => _handlePointerUp(session, event),
          onPointerCancel: (event) => _handlePointerCancel(session, event),
          child: ColoredBox(
            color: scheme.surface,
            // Disable the automatic desktop scrollbar around this list; the
            // explicit Scrollbar below is the single, visible, draggable bar.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Scrollbar(
                controller: session.listController,
                // Always show a draggable thumb on the right so long output can
                // be navigated.
                thumbVisibility: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.axis == Axis.vertical) {
                      _trackFollow(session);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: session.listController,
                    // A right gutter keeps text/caret clear of the scrollbar.
                    padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
                    itemCount:
                        session.outputLines.length + (_showPrompt ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= session.outputLines.length) {
                        return _buildPromptRow(context);
                      }
                      final line = session.outputLines[i];
                      return SelectableText(
                        line.text,
                        style: TextStyle(
                          fontFamily: EditorFonts.bundledFamily,
                          fontFamilyFallback: EditorFonts.fallbacks,
                          fontSize: 12.5,
                          height: 1.45,
                          color: switch (line.kind) {
                            _LineKind.command => scheme.primary,
                            _LineKind.stderr => scheme.error,
                            _LineKind.info => scheme.onSurfaceVariant,
                            _LineKind.debug => scheme.tertiary,
                            _LineKind.stdout => scheme.onSurface,
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const double _tapSlop = 12;
  static const double _scrollbarGutter = 20;
  static const Duration _tapTimeout = Duration(milliseconds: 300);
  static const Duration _doubleTapWindow = Duration(milliseconds: 250);

  void _handlePointerDown(
    _TerminalSession session,
    PointerDownEvent event,
    BoxConstraints constraints,
  ) {
    // A second pointer (multi-touch) cancels tap handling for this gesture.
    if (session.pointerId != null && session.pointerId != event.pointer) {
      session.pointerId = null;
      session.pointerOrigin = null;
      session.pointerMulti = true;
      return;
    }
    session.pointerId = event.pointer;
    session.pointerOrigin = event.position;
    session.pointerMaxTravel = 0;
    session.pointerDownAt = DateTime.now();
    session.pointerMulti = false;
    session.pointerOnScrollbar =
        constraints.maxWidth > 0 &&
        event.localPosition.dx > constraints.maxWidth - _scrollbarGutter;
  }

  void _handlePointerMove(_TerminalSession session, PointerMoveEvent event) {
    if (session.pointerId != event.pointer) return;
    final origin = session.pointerOrigin;
    if (origin == null) return;
    final travel = (event.position - origin).distance;
    if (travel > session.pointerMaxTravel) session.pointerMaxTravel = travel;
  }

  void _handlePointerUp(_TerminalSession session, PointerUpEvent event) {
    if (session.pointerId != event.pointer) {
      return; // not our tracked pointer (or cancelled by multi-touch)
    }
    final origin = session.pointerOrigin;
    final onScrollbar = session.pointerOnScrollbar;
    final multi = session.pointerMulti;
    final maxTravel = session.pointerMaxTravel;
    session.pointerId = null;
    session.pointerOrigin = null;
    session.pointerOnScrollbar = false;
    session.pointerMulti = false;
    if (origin == null || onScrollbar || multi) return;
    // A drag (even out and back) has real travel beyond the slop.
    if (maxTravel > _tapSlop) return;
    final held = DateTime.now().difference(session.pointerDownAt);
    if (held > _tapTimeout) return; // long press / selection hold

    // Defer the single-tap action briefly. A second tap in the window is a
    // double click (word selection) and cancels the deferred focus so the
    // viewport and selection are not disturbed.
    final now = DateTime.now();
    final lastTap = session.lastTapAt;
    session.lastTapAt = now;
    session.deferredTap?.cancel();
    if (lastTap != null && now.difference(lastTap) <= _doubleTapWindow) {
      session.deferredTap = null;
      return;
    }
    session.deferredTap = Timer(_doubleTapWindow, () {
      session.deferredTap = null;
      if (mounted && !session.disposed) _focusInput(session);
    });
  }

  void _handlePointerCancel(
    _TerminalSession session,
    PointerCancelEvent event,
  ) {
    if (session.pointerId != event.pointer) return;
    session.pointerId = null;
    session.pointerOrigin = null;
    session.pointerOnScrollbar = false;
    session.pointerMulti = false;
  }

  /// The interactive prompt is the final row of the transcript, so output and
  /// input share one scrollable document and one background. Hidden while a
  /// run or preparation owns the pane.
  bool get _showPrompt => !_running && !_preparing;

  Widget _buildPromptRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Report focus changes so the host can keep the panel expanded while the
    // user is typing (see TerminalPane.onInputFocusChanged).
    final focusNode = _session.focusNode;
    if (focusNode != _watchedFocusNode) {
      _watchedFocusNode?.removeListener(_notifyInputFocusChanged);
      focusNode.addListener(_notifyInputFocusChanged);
      _watchedFocusNode = focusNode;
    }
    return Focus(
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The prompt takes its natural width up to this cap; the input
          // receives every remaining pixel of the terminal line.
          final promptMaxWidth = constraints.maxWidth * 0.45;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: promptMaxWidth),
                child: Text(
                  _prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: EditorFonts.bundledFamily,
                    fontFamilyFallback: EditorFonts.fallbacks,
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _session.focusNode,
                  enabled: !_running && !_preparing,
                  maxLength: _session.online ? 2000 : null,
                  cursorColor: scheme.primary,
                  style: TextStyle(
                    fontFamily: EditorFonts.bundledFamily,
                    fontFamilyFallback: EditorFonts.fallbacks,
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                  // `unspecified` submits Return via `onSubmitted` while
                  // keeping the soft keyboard up; see [TerminalInputBehavior]
                  // for why `send` and `none` both fail.
                  textInputAction: TerminalInputBehavior.action,
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Renders [command] as a shell-style line using the short prompt, so the
  /// Run header reads like a terminal command rather than a card/paragraph.
  String _promptLine(String command) => '$_prompt $command';

  /// Short command-line prompt. Prefer the session's current folder name so a
  /// `cd` is visible and mobile sandbox paths
  /// (`/data/.../app_flutter/<project>`) do not crowd out the transcript.
  String get _prompt {
    return _promptFor(_session);
  }

  String _promptFor(_TerminalSession session) {
    if (session.online) return '/workspace\$';
    final backend = session.backend;
    final base = backend?.cwd ?? widget.workingDirectory;
    final name = p.basename(p.normalize(base));
    final shortName = name.isEmpty ? 'workspace' : name;
    return Platform.isWindows ? '$shortName>' : '$shortName\$';
  }

  Widget _buildSessionTabs(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Symmetric vertical padding so the pills sit clear of the header's top
      // and bottom edges instead of filling it edge to edge.
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: TerminalPanelMetrics.tabBarVerticalPadding,
      ),
      child: Row(
        children: [
          for (var index = 0; index < _sessions.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _buildSessionTab(
                context,
                Theme.of(context).colorScheme,
                index,
              ),
            ),
        ],
      ),
    );
  }

  /// Short tab label.
  ///
  /// A full `Terminal 1` occupies ~148 px per pill, so two or three tabs push
  /// the bar into horizontal scrolling on a phone. The id is the only part that
  /// distinguishes tabs, so it is the only part kept: `1` locally, `R1` for a
  /// remote session (the online tab is otherwise indistinguishable).
  String _sessionLabel(_TerminalSession session) =>
      session.online ? 'R${session.id}' : '${session.id}';

  /// Session label with a visible outline and clear selection so multiple tabs
  /// stay distinguishable at narrow widths.
  Widget _buildSessionTab(BuildContext context, ColorScheme scheme, int index) {
    final session = _sessions[index];
    final selected = index == _selectedSessionIndex;
    final label = _sessionLabel(session);
    // A single local terminal can be closed too. Closing the last tab keeps the
    // session list non-empty by replacing it with a fresh terminal, so the pane
    // never ends up with nothing selected (see `_closeSession`).
    final closable = !session.online && !_preparing;
    return Material(
      color: selected
          ? scheme.secondaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Cap the pill so long labels cannot push the action buttons off screen.
        constraints: const BoxConstraints(
          maxWidth: TerminalPanelMetrics.maxTabWidth,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Semantics(
                button: true,
                selected: selected,
                enabled: !_preparing,
                label: label,
                child: InkWell(
                  onTap: _preparing ? null : () => _selectSession(index),
                  canRequestFocus: !_preparing,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: TerminalPanelMetrics.tabHorizontalPadding,
                      right: closable
                          ? 2
                          : TerminalPanelMetrics.tabHorizontalPadding,
                    ),
                    child: SizedBox(
                      height: TerminalPanelMetrics.tabHeight,
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontFamily: EditorFonts.bundledFamily,
                            fontFamilyFallback: EditorFonts.fallbacks,
                            fontSize: 12.5,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (closable)
              SizedBox(
                width: 28,
                height: TerminalPanelMetrics.tabHeight,
                child: IconButton(
                  tooltip: 'Close terminal $label',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: TerminalPanelMetrics.tabHeight,
                  ),
                  iconSize: 14,
                  // Closing a tab must not leave focus on the removed button.
                  focusNode: _tabCloseFocusNode,
                  onPressed: () => _closeSession(index),
                  icon: Icon(
                    Icons.close,
                    size: 14,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TerminalSession {
  _TerminalSession({required this.id, this.online = false});

  final int id;
  final bool online;
  bool initialized = false;
  bool disposed = false;
  _TermLine? pendingStdout;
  _TermLine? pendingStderr;
  final outputLines = <_TermLine>[];
  final inputController = TextEditingController();
  final listController = ScrollController();
  final focusNode = FocusNode(debugLabel: 'terminal input');
  final history = <String>[];
  var historyIndex = -1;
  var running = false;

  /// True while the transcript should follow new output. Cleared when the user
  /// scrolls away from the bottom, restored when they return.
  var follow = true;

  /// Last observed scroll offset, restored explicitly when the session becomes
  /// active again so each session keeps its own place.
  var scrollOffset = 0.0;

  /// Pointer bookkeeping used to distinguish a focus tap from a drag, a long
  /// press, a scrollbar interaction, a double click, or a multi-touch gesture.
  int? pointerId;
  Offset? pointerOrigin;
  double pointerMaxTravel = 0;
  DateTime pointerDownAt = DateTime.now();
  bool pointerOnScrollbar = false;
  bool pointerMulti = false;

  /// Last completed single tap, used to detect a double click.
  DateTime? lastTapAt;

  /// Pending deferred focus for a single tap; cancelled by a double click or
  /// session disposal.
  Timer? deferredTap;

  /// The single shell backend owning this local session's cwd/execution.
  shell.ShellBackend? backend;
  StreamSubscription<shell.ShellChunk>? backendSub;

  Process? currentProcess;
  ManagedProcess? currentManagedProcess;
  Future<void> Function()? cancelAction;
  Future<void>? commandDone;
  Future<int>? attachedExitCode;
  Object? attachedRun;
  Future<void>? _pendingCancellation;
  Future<void> Function()? _unprovenCancellation;
  Future<void> Function()? _cleanupCancelAction;
  bool _cancellationCleaned = false;
  Future<void>? _disposeFuture;

  bool get hasUnfinishedCancellation => _unprovenCancellation != null;

  /// Stop and tab disposal share a cancellation while it is in flight. Failed
  /// attempts leave the action available so the next explicit Stop can retry.
  Future<void> interrupt() {
    final existing = _pendingCancellation;
    if (existing != null) return existing;
    final cancel =
        (disposed ? _cleanupCancelAction : null) ??
        _unprovenCancellation ??
        cancelAction ??
        backend?.interrupt;
    if (cancel == null) {
      if (disposed) _cancellationCleaned = true;
      return Future<void>.value();
    }
    _unprovenCancellation = cancel;
    late final Future<void> pending;
    pending = Future<void>.sync(cancel)
        .then<void>((_) {
          if (identical(_unprovenCancellation, cancel)) {
            _unprovenCancellation = null;
          }
          if (disposed) _cancellationCleaned = true;
        })
        .whenComplete(() {
          if (identical(_pendingCancellation, pending)) {
            _pendingCancellation = null;
          }
        });
    return _pendingCancellation = pending;
  }

  Future<void> retryDispose() async {
    final previous = _disposeFuture;
    // The previous pass may still be waiting for worker exit after cancellation
    // failed. Retry cancellation before waiting for that pass to finish.
    if (disposed && !_cancellationCleaned && !online) await interrupt();
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // This explicit retry continues with only the unfinished resources.
      }
    }
    await dispose();
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    final firstDisposal = !disposed;
    if (firstDisposal) {
      _cleanupCancelAction = _unprovenCancellation ?? cancelAction;
    }
    disposed = true;
    final cleanup = <Future<void>>[];
    final cancellation = _pendingCancellation;
    if (!_cancellationCleaned) {
      if (cancellation != null) {
        cleanup.add(cancellation);
      } else if (!online) {
        cleanup.add(interrupt());
      }
    }
    final managed = currentManagedProcess;
    if (managed != null) {
      cleanup.add(
        Future<void>.sync(() async {
          await managed.cancel();
          if (identical(currentManagedProcess, managed)) {
            currentManagedProcess = null;
          }
        }),
      );
    }
    final process = currentProcess;
    if (process != null) {
      cleanup.add(
        Future<void>.sync(() async {
          process.kill();
          await process.exitCode;
          if (identical(currentProcess, process)) currentProcess = null;
        }),
      );
    }
    final attached = attachedExitCode;
    if (attached != null) {
      cleanup.add(
        attached.then<void>((_) {
          if (identical(attachedExitCode, attached)) attachedExitCode = null;
        }),
      );
    }
    final command = commandDone;
    if (command != null) {
      cleanup.add(
        command.then<void>((_) {
          if (identical(commandDone, command)) commandDone = null;
        }),
      );
    }
    final output = backendSub;
    if (output != null) {
      cleanup.add(
        Future<void>.sync(() async {
          await output.cancel();
          if (identical(backendSub, output)) backendSub = null;
        }),
      );
    }
    final localBackend = backend;
    if (localBackend != null) {
      cleanup.add(
        Future<void>.sync(() async {
          await localBackend.shutdown();
          if (identical(backend, localBackend)) backend = null;
        }),
      );
    }
    if (firstDisposal) {
      deferredTap?.cancel();
      inputController.dispose();
      listController.dispose();
      focusNode.dispose();
    }
    late final Future<void> pending;
    pending = Future.wait<void>(cleanup, eagerError: false).then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_disposeFuture, pending)) _disposeFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    return _disposeFuture = pending;
  }
}

enum _LineKind { command, stdout, stderr, info, debug }

class _TermLine {
  const _TermLine({required this.text, required this.kind});

  final String text;
  final _LineKind kind;
}
