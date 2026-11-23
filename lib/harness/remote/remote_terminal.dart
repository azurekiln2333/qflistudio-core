// Raw terminal and transcript feeds over an open remote session.
//
// Both are views: they subscribe to what the screen already receives and never
// start or stop desktop work. Releasing one (`close`/`detach`) cancels the local
// listener and releases the route's subscription owner; it sends no
// `session_close`, so the agent keeps running and reappears on reconnect.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../sync/remote_session_cache.dart';

import '../../remote_control/models/protocol.dart' as protocol;
import '../../remote_control/state/session_view.dart';
import '../harness_host.dart';
import 'remote_mapping.dart';
import 'remote_ports.dart';

/// Replays terminal bytes from a remote PTY session.
///
/// Bytes never live in [SessionView.events] (the view writes them straight into
/// its emulator), so this subscribes to the raw-output callback instead of
/// scanning the event list.
class RemoteTerminalChannel implements HarnessTerminalChannel {
  RemoteTerminalChannel({
    required SessionView view,
    required RemoteSessionPort port,
    required String sessionId,
  }) : _view = view,
       _port = port,
       _sessionId = sessionId;

  final SessionView _view;
  final RemoteSessionPort _port;
  final String _sessionId;

  /// Attaches on the first listener, not in the constructor: the controller is a
  /// broadcast stream, so a replay emitted before anyone listens is dropped —
  /// and that replay is the whole screen of an idle session.
  late final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast(onListen: _attach);
  bool _attached = false;
  bool _closed = false;

  void _attach() {
    if (_closed || _attached) return;
    _attached = true;
    for (final chunk in _view.terminalLog) {
      _emit(chunk);
    }
    _view.addTerminalOutputListener(_onOutput, onReset: _onReset);
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) {
    if (_closed || data.isEmpty) return;
    // The wire carries exact bytes as a string; malformed sequences are kept
    // rather than dropped, because a truncated key sequence is still input.
    unawaited(
      _port
          .terminalInput(_sessionId, utf8.decode(data, allowMalformed: true))
          .catchError((Object _) {}),
    );
  }

  @override
  void resize(int columns, int rows) {
    if (_closed) return;
    unawaited(
      _port.terminalResize(_sessionId, columns, rows).catchError((Object _) {}),
    );
  }

  void _onOutput(String data) => _emit(data);

  /// A resubscribe replays the session from scratch: clear first, or the same
  /// screen would be appended to the old one.
  void _onReset() => _emit('\u001b[2J\u001b[H');

  void _emit(String data) {
    if (_closed || data.isEmpty) return;
    _output.add(Uint8List.fromList(utf8.encode(data)));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_attached) _view.removeTerminalOutputListener(_onOutput);
    await _output.close();
  }
}

/// Conversation feed for a remote Claude session.
///
/// A broadcast controller with lazy subscription: nothing is subscribed on the
/// desktop until a widget actually listens, and the first listener gets the
/// existing history followed by live events.
class RemoteTranscriptFeed {
  RemoteTranscriptFeed({
    required SessionView view,
    required RemoteSessionPort port,
    required String sessionId,
    required Object owner,
    this.cache,
  }) : _view = view,
       _port = port,
       _sessionId = sessionId,
       _owner = owner;

  /// Optional bounded copy of the transcript, so a dropped connection does not
  /// take the visible history with it.
  final RemoteSessionCache? cache;

  final SessionView _view;
  final RemoteSessionPort _port;
  final String _sessionId;
  final Object _owner;

  late final StreamController<TranscriptEvent> _controller =
      StreamController<TranscriptEvent>.broadcast(
        onListen: _start,
        onCancel: _stop,
      );

  int _lastSeq = 0;
  int _seenRevision = -1;
  int _cacheSeq = 0;
  int _liveEvents = 0;
  Timer? _historyTimer;
  bool _started = false;
  bool _replayed = false;
  bool _closed = false;

  Stream<TranscriptEvent> get stream => _controller.stream;

  void _start() {
    if (_closed || _started) return;
    _started = true;
    _view.addListener(_pump);
    unawaited(
      _port.subscribe(_sessionId, owner: _owner).catchError((Object _) {}),
    );
    // The live view normally answers with the whole history, so the cache is a
    // fallback for the reconnect that answers with nothing. Waiting a moment
    // before using it keeps a healthy stream from showing every line twice.
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 700), () {
      _historyTimer = null;
      if (_liveEvents == 0) unawaited(_replayHistory());
    });
    _pump();
  }

  /// Play the kept history when the live stream stayed empty.
  Future<void> _replayHistory() async {
    final cache = this.cache;
    if (cache == null || _replayed || _closed || !_started) return;
    _replayed = true;
    final lines = await cache.read();
    if (_closed || !_started || _liveEvents > 0) return;
    for (final line in lines) {
      final entry = _cachedTranscript(line);
      if (entry != null && !_controller.isClosed) _controller.add(entry);
    }
  }

  /// Rebuild one cached line, dropping anything this build no longer knows.
  TranscriptEvent? _cachedTranscript(Map<String, dynamic> line) {
    TranscriptRole? role;
    for (final value in TranscriptRole.values) {
      if (value.name == line['role']) role = value;
    }
    final text = line['text'];
    if (role == null || text is! String) return null;
    final id = line['id'];
    final at = line['at'];
    final requestId = line['requestId'];
    return TranscriptEvent(
      id: id is String && id.isNotEmpty ? id : 'cache-${_cacheSeq++}',
      role: role,
      text: text,
      at: at is String ? DateTime.tryParse(at) : null,
      requestId: requestId is String ? requestId : null,
    );
  }

  void _stop() {
    if (!_started) return;
    _started = false;
    _historyTimer?.cancel();
    _historyTimer = null;
    _view.removeListener(_pump);
    _port.unsubscribe(_sessionId, owner: _owner);
  }

  void _pump() {
    if (_closed) return;
    // Streaming text notifies on every token; only a stored event can carry a
    // transcript entry, so skip the scan when the list did not move.
    final revision = _view.eventRevision;
    if (revision == _seenRevision) return;
    _seenRevision = revision;
    // A resubscribe restarts the view's sequence numbering; follow it, or every
    // later entry would look like a duplicate.
    final rewound = _view.lastSeq < _lastSeq;
    if (rewound) {
      _lastSeq = 0;
      // The computer replayed the conversation for this view, so the kept copy
      // is dropped instead of stacking a second history on top of it.
      if (cache != null) _replayed = true;
    }
    var first = rewound;
    for (final event in _view.events) {
      if (event.seq <= _lastSeq) continue;
      _lastSeq = event.seq;
      final entry = transcriptFromSessionEvent(event, _sessionId);
      if (entry != null) {
        _liveEvents += 1;
        _controller.add(entry);
        final cache = this.cache;
        if (cache != null) {
          unawaited(
            first
                ? cache.replaceWith(_cacheLine(entry))
                : cache.append(_cacheLine(entry)),
          );
          first = false;
        }
      }
    }
  }

  /// The fields the transcript view needs, in a stable shape.
  Map<String, dynamic> _cacheLine(TranscriptEvent entry) => <String, dynamic>{
    'id': entry.id,
    'role': entry.role.name,
    'text': entry.text,
    'at': ?entry.at?.toIso8601String(),
    'requestId': ?entry.requestId,
  };

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stop();
    await _controller.close();
  }
}

/// Live status of one remote session, kept in a [ValueNotifier] as the contract
/// asks. Listens to the view so a status change repaints only that row.
class RemoteSessionStatusNotifier extends ValueNotifier<HarnessSessionStatus> {
  RemoteSessionStatusNotifier({
    required SessionView view,
    required protocol.SessionStatus initial,
  }) : _view = view,
       super(remoteSessionStatus(initial)) {
    _view.addListener(_sync);
  }

  final SessionView _view;

  void _sync() {
    if (_disposed) return;
    if (_view.gone) {
      value = HarnessSessionStatus.exited;
      return;
    }
    value = remoteSessionStatus(_view.info.status);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _view.removeListener(_sync);
    super.dispose();
  }
}
