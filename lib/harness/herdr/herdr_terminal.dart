// The raw terminal behind a Herdr session.
//
// Two implementations share one interface:
//
//   * [HerdrPtyTerminal] runs `herdr agent attach <target>` inside a real PTY.
//     That is the live view: bytes flow continuously, input reaches the pane
//     with no round trip through a snapshot, and closing it only detaches —
//     the pane and its agent keep running.
//   * [HerdrSnapshotTerminal] is the fallback for builds without a PTY layer.
//     It replays `pane read` snapshots and turns typed bytes into
//     `pane send-text` / `pane send-keys` calls.
//
// Both feed the same contract type, so the Agents terminal tab does not care
// which one is underneath. Neither implementation stops the session: `close()`
// releases the view only, matching `HarnessSessionHandle.detach()`.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Listenable;

import '../../remote_control/models/herdr.dart' show HerdrPaneSnapshot;
import '../harness_host.dart' show HarnessTerminalChannel;
import '../pty/harness_pty.dart';
import 'herdr_input.dart';

/// A Herdr terminal plus an explicit release step.
abstract interface class HerdrTerminal implements HarnessTerminalChannel {
  /// Releases this view. The pane keeps running.
  Future<void> close();

  /// Last known geometry, for snapshot replay fallbacks.
  int get columns;
  int get rows;
}

/// Live terminal through `herdr agent attach` in a PTY.
class HerdrPtyTerminal implements HerdrTerminal {
  HerdrPtyTerminal._(this._pty, this._output, this._columns, this._rows);

  /// Starts the attach client. [argv] is the full command, including the Herdr
  /// executable, so the caller owns path resolution.
  static Future<HerdrPtyTerminal> start({
    required HarnessPtyFactory factory,
    required List<String> argv,
    String? workingDirectory,
    int columns = 100,
    int rows = 30,
  }) async {
    final pty = await factory.start(
      argv: argv,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
    );
    final output = StreamController<Uint8List>.broadcast();
    final terminal = HerdrPtyTerminal._(pty, output, columns, rows);
    terminal._listen();
    return terminal;
  }

  final HarnessPty _pty;
  final StreamController<Uint8List> _output;
  StreamSubscription<Uint8List>? _subscription;
  bool _closed = false;

  void _listen() {
    _subscription = _pty.output.listen(
      (data) {
        if (!_closed) _output.add(data);
      },
      onError: (Object _) {},
      onDone: () {
        if (!_closed) unawaited(_output.close());
      },
    );
  }

  int? get pid => _pty.pid;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) {
    if (_closed) return;
    _pty.write(data);
  }

  @override
  void resize(int columns, int rows) {
    if (_closed) return;
    _pty.resize(columns, rows);
    _columns = columns;
    _rows = rows;
  }

  int _columns;
  int _rows;

  @override
  int get columns => _columns;

  @override
  int get rows => _rows;

  /// Detaches: kills the attach client only. The pane keeps running.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _pty.kill();
    await _output.close();
  }
}

/// Snapshot-backed terminal for builds without a PTY.
///
/// Herdr has no incremental output stream on the CLI: `pane read` returns the
/// screen. Replaying the whole screen when it changes is therefore correct
/// rather than lossy — and the replay is normalised by [HerdrPaneSnapshot],
/// which is the same code the remote Herdr view uses, so line endings and grid
/// padding behave identically.
class HerdrSnapshotTerminal implements HerdrTerminal {
  HerdrSnapshotTerminal({
    required Future<String> Function() readPane,
    required Future<void> Function(String text) sendText,
    required Future<void> Function(List<String> keys) sendKeys,
    this.interval = const Duration(milliseconds: 1500),
    this.translator = const HerdrInputTranslator(),
    this.onError,
    this.changes,
    int columns = 100,
    int rows = 30,
  }) : _readPane = readPane,
       _sendText = sendText,
       _sendKeys = sendKeys,
       _columns = columns,
       _rows = rows;

  /// How often the screen is re-read while the view is open.
  ///
  /// One CLI call per interval per open pane, and none while reading. The live
  /// path is the PTY attach; this is the fallback, so "slow" is the right
  /// trade-off against a tight poll loop.
  final Duration interval;
  final HerdrInputTranslator translator;

  /// Reports input failures so the UI can show them instead of dropping keys.
  final void Function(Object error)? onError;

  /// Optional change source (a controller push, not a poll). When given, a
  /// change repaints immediately instead of waiting for [interval].
  final Listenable? changes;

  final Future<String> Function() _readPane;
  final Future<void> Function(String text) _sendText;
  final Future<void> Function(List<String> keys) _sendKeys;

  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  Timer? _timer;
  String? _last;
  bool _reading = false;
  bool _closed = false;
  final List<HerdrInputOp> _pending = <HerdrInputOp>[];
  Future<void>? _draining;
  int _columns;
  int _rows;

  void start() {
    if (_closed || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_pump()));
    changes?.addListener(_onChanges);
    unawaited(_pump());
  }

  void _onChanges() => unawaited(_pump());

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  int get columns => _columns;

  @override
  int get rows => _rows;

  @override
  void write(Uint8List data) {
    if (_closed) return;
    final ops = translator.translate(data);
    if (ops.isEmpty) return;
    // One queue for every chunk: the CLI calls are sequential, but two `write`s
    // used to race, so `pane send-keys enter` could overtake the text before it.
    _pending.addAll(ops);
    _draining ??= _drain();
  }

  @override
  void resize(int columns, int rows) {
    _columns = columns;
    _rows = rows;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    changes?.removeListener(_onChanges);
    _timer?.cancel();
    _timer = null;
    await _output.close();
  }

  Future<void> _pump() async {
    if (_closed || _reading) return;
    _reading = true;
    try {
      final text = await _readPane();
      if (_closed || text == _last) return;
      _last = text;
      final snapshot = HerdrPaneSnapshot.fromText(
        text,
        fallbackColumns: _columns,
      );
      // Clear then replay: a snapshot is a screen, not a stream, so anything
      // else would stack old and new screens.
      _emit('\u001b[2J\u001b[H');
      _emit(snapshot.replayText);
    } catch (_) {
      // A transient read failure keeps the last screen; the next tick retries.
    } finally {
      _reading = false;
    }
  }

  void _emit(String text) {
    if (_closed) return;
    _output.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed) {
      // A short window lets a typing burst land in one batch: every key otherwise
      // costs its own `herdr` process (50-200 ms on Windows), which makes the
      // pane feel broken.
      await Future<void>.delayed(const Duration(milliseconds: 12));
      if (_closed || _pending.isEmpty) break;
      final batch = List<HerdrInputOp>.of(_pending);
      _pending.clear();
      // Adjacent literal text is merged so a typed word is one `send-text` call;
      // keys stay boundaries, so their order is unchanged.
      for (final op in _coalesce(batch)) {
        if (_closed) break;
        try {
          switch (op) {
            case HerdrSendTextOp():
              await _sendText(op.text);
            case HerdrSendKeysOp():
              await _sendKeys(op.keys);
          }
        } catch (error) {
          onError?.call(error);
        }
      }
    }
    _draining = null;
  }

  /// Merges consecutive literal-text ops, leaving key ops as boundaries.
  static List<HerdrInputOp> _coalesce(List<HerdrInputOp> ops) {
    final merged = <HerdrInputOp>[];
    final text = StringBuffer();
    void flush() {
      if (text.isEmpty) return;
      merged.add(HerdrSendTextOp(text.toString()));
      text.clear();
    }

    for (final op in ops) {
      switch (op) {
        case HerdrSendTextOp():
          text.write(op.text);
        case HerdrSendKeysOp():
          flush();
          merged.add(op);
      }
    }
    flush();
    return merged;
  }
}
