// Migrated from CloudTerminal's `lib/state/session_view.dart` (source HEAD
// 49b2aac). Rendering state for one remote session: ordered events, sequence
// dedupe, tool results, permission resolutions, streaming text, and the xterm
// emulator used by the PTY viewport (ported in phase 2 as RemoteTerminalPane).

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/protocol.dart';

/// Everything the session screen renders for one session. Separate from
/// [RemoteController] so streaming deltas only rebuild the open session.
class SessionView extends ChangeNotifier {
  SessionView(this._info);

  SessionInfo _info;
  final List<SessionEvent> _events = <SessionEvent>[];
  final Map<String, ToolResultEvent> _results = <String, ToolResultEvent>{};
  final Map<String, PermissionResolvedEvent> _resolved =
      <String, PermissionResolvedEvent>{};
  String _streaming = '';
  bool _gone = false;
  bool _loaded = false;

  SessionInfo get info => _info;
  String get id => _info.id;

  /// Every event, in order (tool results and resolutions included).
  List<SessionEvent> get events => List<SessionEvent>.unmodifiable(_events);

  /// Assistant text still being streamed (not yet a stored event).
  String get streaming => _streaming;

  /// Session no longer exists on the agent (closed elsewhere / agent restart).
  bool get gone => _gone;

  /// First backlog has arrived.
  bool get loaded => _loaded;

  int _lastSeq = 0;
  int get lastSeq => _lastSeq;
  bool _replaying = false;
  Terminal? _terminal;
  void Function(String)? onTerminalInput;

  /// Bumped whenever the stored event list changes. A harness pump reads this
  /// first: streaming text and status changes notify without touching it.
  int _revision = 0;
  int get eventRevision => _revision;

  /// Raw terminal bytes kept so a host that renders its own emulator (the
  /// harness hub) can show the screen it missed. Bounded, never a full log.
  static const int _terminalLogLimit = 32 * 1024;
  final List<String> _terminalLog = <String>[];
  int _terminalLogChars = 0;
  final List<_TerminalOutputListener> _terminalOutputListeners =
      <_TerminalOutputListener>[];

  /// Recent raw output, oldest first, for a listener that attaches late.
  List<String> get terminalLog => List<String>.unmodifiable(_terminalLog);

  /// Calls [onData] with every raw chunk, live and replayed from backlog.
  ///
  /// [onReset] fires when the backlog restarts from scratch, so a second
  /// emulator clears before the replay instead of stacking two screens.
  /// [terminal] is still fed, so both kinds of view can coexist.
  void addTerminalOutputListener(
    void Function(String data) onData, {
    void Function()? onReset,
  }) {
    _terminalOutputListeners.add(_TerminalOutputListener(onData, onReset));
  }

  void removeTerminalOutputListener(void Function(String data) onData) {
    _terminalOutputListeners.removeWhere(
      (listener) => listener.onData == onData,
    );
  }

  /// Keep the parsed screen across navigation, never an unbounded raw log.
  Terminal get terminal => _terminal ??= _createTerminal();

  Terminal _createTerminal() {
    final terminal = Terminal(maxLines: 2000);
    terminal.resize(
      (_info.cols ?? 80).clamp(2, 500),
      (_info.rows ?? 24).clamp(1, 300),
    );
    terminal.onOutput = (data) {
      if (!_replaying) onTerminalInput?.call(data);
    };
    return terminal;
  }

  ToolResultEvent? resultFor(String toolUseId) => _results[toolUseId];

  PermissionResolvedEvent? resolutionFor(String requestId) =>
      _resolved[requestId];

  /// Permission requests nobody has answered yet, oldest first.
  List<PermissionRequestEvent>
  get pendingPermissions => <PermissionRequestEvent>[
    for (final e in _events)
      if (e is PermissionRequestEvent && !_resolved.containsKey(e.requestId)) e,
  ];

  void updateInfo(SessionInfo info) {
    final terminal = _terminal;
    if (terminal != null &&
        info.cols != null &&
        info.rows != null &&
        (info.cols != _info.cols || info.rows != _info.rows)) {
      // Desktop/other clients can resize the shared PTY. Apply its geometry
      // without echoing another resize request back to the agent.
      final onResize = terminal.onResize;
      terminal.onResize = null;
      terminal.resize(info.cols!.clamp(2, 500), info.rows!.clamp(1, 300));
      terminal.onResize = onResize;
    }
    _info = info;
    if (info.isClosed || info.status == SessionStatus.idle) _streaming = '';
    notifyListeners();
  }

  void markGone() {
    _gone = true;
    notifyListeners();
  }

  void applyBacklog(List<SessionEvent> events, {required bool reset}) {
    if (reset) {
      _lastSeq = 0;
      _terminal = null;
      _events.clear();
      _results.clear();
      _resolved.clear();
      _streaming = '';
      _revision += 1;
      if (_terminalLog.isNotEmpty) {
        _terminalLog.clear();
        _terminalLogChars = 0;
      }
      for (final listener in List<_TerminalOutputListener>.of(
        _terminalOutputListeners,
      )) {
        listener.onReset?.call();
      }
    }
    _replaying = true;
    try {
      for (final e in events) {
        _add(e);
      }
    } finally {
      _replaying = false;
    }
    _loaded = true;
    _gone = false;
    notifyListeners();
  }

  void applyEvent(SessionEvent event) {
    if (_add(event)) notifyListeners();
  }

  void applyDelta(String text) {
    _streaming += text;
    notifyListeners();
  }

  bool _add(SessionEvent e) {
    if (e.seq <= lastSeq) return false; // duplicate from a resubscribe race
    _lastSeq = e.seq;
    if (e is TerminalOutputEvent) {
      terminal.write(e.data);
      _recordTerminalOutput(e.data);
      return true;
    }
    _events.add(e);
    _revision += 1;
    if (_info.isTerminal && _events.length > 100) _events.removeAt(0);
    switch (e) {
      case ToolResultEvent():
        _results[e.toolUseId] = e;
      case PermissionResolvedEvent():
        _resolved[e.requestId] = e;
      case AssistantEvent() || ToolUseEvent() || ResultEvent() || ErrorEvent():
        // The stored message supersedes whatever was streamed for it.
        _streaming = '';
      default:
        break;
    }
    return true;
  }

  void _recordTerminalOutput(String data) {
    if (data.isEmpty) return;
    _terminalLog.add(data);
    _terminalLogChars += data.length;
    while (_terminalLogChars > _terminalLogLimit && _terminalLog.length > 1) {
      _terminalLogChars -= _terminalLog.removeAt(0).length;
    }
    for (final listener in List<_TerminalOutputListener>.of(
      _terminalOutputListeners,
    )) {
      listener.onData(data);
    }
  }
}

/// One harness view that renders raw terminal bytes itself.
class _TerminalOutputListener {
  const _TerminalOutputListener(this.onData, this.onReset);

  final void Function(String data) onData;
  final void Function()? onReset;
}
