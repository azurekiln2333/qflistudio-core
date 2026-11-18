/// Experimental OHOS Java execution on its own channel and session lifecycle.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/ohos_platform.dart';
import 'interop_protocol.dart';
import 'interop_targets.dart';
import 'interop_transport.dart';
import 'interop_zip.dart';

class MethodChannelBackgroundInteropTransport implements InteropTransport {
  const MethodChannelBackgroundInteropTransport({
    this.startupGrace = const Duration(seconds: 10),
    this.cancellationGrace = const Duration(seconds: 3),
  });

  static const methods = MethodChannel('qfli_interop/background');
  static const events = EventChannel('qfli_interop/background/events');
  static _BackgroundSession? _active;

  final Duration startupGrace;
  final Duration cancellationGrace;

  @override
  bool get isSupported => isOhosPlatform;

  @override
  Future<InteropProbe> probe(InteropTarget target) async =>
      const InteropProbe.unknown('后台运行能力将在启动时验证。');

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    if (!isSupported ||
        target.language != 'java' ||
        request.language != 'java') {
      throw const InteropException(
        InteropErrorCode.unsupportedLanguage,
        '后台运行仅支持 OHOS Java 项目。',
      );
    }
    final parameters = request.toLaunchParameters();
    if (_active != null) {
      throw const InteropException(
        InteropErrorCode.transportFailure,
        '已有后台运行任务，请等待任务结束。',
      );
    }
    late final _BackgroundSession session;
    session = _BackgroundSession(
      target: target,
      request: request,
      parameters: parameters,
      startupGrace: startupGrace,
      cancellationGrace: cancellationGrace,
      onDisposed: () {
        if (identical(_active, session)) _active = null;
      },
    );
    _active = session;
    // Return ownership before asynchronous preparation. Stop and page disposal
    // can now cancel even while the platform start method has not returned.
    unawaited(session.start());
    return InteropLaunch(
      request: request,
      events: session.output.stream,
      cancel: session.cancel,
      stop: session.stop,
    );
  }
}

class _BackgroundSession {
  _BackgroundSession({
    required this.target,
    required this.request,
    required this.parameters,
    required this.startupGrace,
    required this.cancellationGrace,
    required this.onDisposed,
  }) : sequencer = InteropEventSequencer(request.sessionId);

  final InteropTarget target;
  final InteropRequest request;
  final Map<String, String> parameters;
  final Duration startupGrace;
  final Duration cancellationGrace;
  final VoidCallback onDisposed;
  final InteropEventSequencer sequencer;
  final output = StreamController<InteropEvent>(sync: true);
  final _terminal = Completer<void>();
  final _disposed = Completer<void>();
  StreamSubscription<dynamic>? _subscription;
  Timer? _deadline;
  Future<void>? _cancellation;
  String? _zipPath;
  int _lastSeq = 0;
  bool _finished = false;
  bool _startIssued = false;
  bool _timedOut = false;
  InteropStop? _outcome;

  Map<String, Object?> get _identity => <String, Object?>{
    'sessionId': request.sessionId,
    'sessionToken': request.sessionToken,
  };

  Future<void> start() async {
    _deadline = Timer(
      Duration(milliseconds: request.timeoutMs) + startupGrace,
      () {
        _timedOut = true;
        unawaited(cancel());
      },
    );
    try {
      // A single-subscription output controller buffers early events until
      // InteropRunner listens, including a terminal event during start().
      _subscription = MethodChannelBackgroundInteropTransport.events
          .receiveBroadcastStream()
          .listen(
            _receive,
            onError: (Object error) => _fail(error),
            onDone: () {
              if (!_finished) _fail(StateError('后台运行通道已关闭。'));
            },
          );
      await _writeZip();
      if (_finished) {
        await _deleteZip();
        return;
      }
      _startIssued = true;
      await _invokeStart();
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// Writes this session's payload into its own private cache root.
  Future<void> _writeZip() async {
    final cache = await getTemporaryDirectory();
    if (_finished) return;
    // The legacy zip writer removes stale files in its output directory.
    // Give this path a private cache root so it cannot remove a legacy run.
    _zipPath = await writePayloadZip(
      cacheDirectory: p.join(cache.path, 'qfli_interop_background'),
      sessionId: request.sessionId,
      files: request.files,
    );
  }

  /// Invokes native start with a bounded call.
  ///
  /// The native side subscribes, requests notification permission and starts
  /// the ability before it answers. Each of those steps has its own platform
  /// bound, but the channel promise itself has none, so a lost reply must
  /// expire as a real failure instead of leaving the run hanging.
  Future<void> _invokeStart() async {
    parameters['zipPath'] = _zipPath!;
    try {
      await MethodChannelBackgroundInteropTransport.methods
          .invokeMethod<void>('start', <String, Object?>{
            'bundleName': target.bundleName,
            'abilityName': 'InteropBackgroundAbility',
            'parameters': parameters,
          })
          .timeout(startupGrace);
    } on TimeoutException {
      throw const InteropException(
        InteropErrorCode.transportFailure,
        '后台运行启动未在限定时间内确认。',
      );
    }
  }

  void _receive(dynamic raw) {
    if (_finished || raw is! Map) return;
    // Authenticate before parsing so another session cannot end this run by
    // supplying a malformed frame or a different protocol.
    if (raw['sessionId'] != request.sessionId ||
        raw['sessionToken'] != request.sessionToken) {
      return;
    }
    try {
      final event = sequencer.accept(
        InteropEvent.fromLaunchParameters(interopWireMap(
          Map<String, Object?>.from(raw),
        )),
      );
      if (event == null) return;
      _lastSeq = event.seq;
      if (event.isTerminal) {
        // A real terminal frame from the receiver is the only acknowledgement
        // that a stop was honoured. A local timeout that replaces the reported
        // outcome is still an acknowledgement: the receiver ended too.
        _finish(
          _timedOut
              ? _failure(InteropErrorCode.timeout, '后台运行超时。', 124)
              : event,
          receiverAcknowledged: true,
        );
      } else {
        output.add(event);
      }
    } on Object catch (error) {
      _fail(error);
    }
  }

  InteropEvent _failure(String code, String message, int exitCode) =>
      InteropEvent(
        sessionId: request.sessionId,
        seq: _lastSeq + 1,
        kind: InteropEventKind.error,
        code: code,
        text: message,
        exitCode: exitCode,
      );

  void _fail(Object error) {
    if (_finished) return;
    final message = switch (error) {
      MissingPluginException() => '后台运行通道未注册。',
      PlatformException() => error.message ?? error.code,
      InteropException() => error.message,
      _ => '后台运行失败：$error',
    };
    final code = error is PlatformException && error.code == 'app_missing'
        ? InteropErrorCode.appMissing
        : InteropErrorCode.transportFailure;
    _finish(_failure(code, message, 127));
  }

  /// Completes the session with one terminal event.
  ///
  /// [receiverAcknowledged] is true only when the terminal event came from the
  /// receiver. A locally synthesized failure, a local timeout or a cancellation
  /// with no answer is not an acknowledgement, so the reported stop cannot be
  /// mistaken for one.
  void _finish(InteropEvent event, {bool receiverAcknowledged = false}) {
    if (_finished) return;
    _finished = true;
    _deadline?.cancel();
    _outcome = InteropStop(
      exitCode: event.exitCode ?? 127,
      message: event.text.isEmpty ? '后台运行已结束' : event.text,
      confirmed: receiverAcknowledged,
    );
    output.add(event);
    unawaited(output.close());
    _terminal.complete();
    unawaited(_dispose());
  }

  Future<void> cancel() => _cancellation ??= _cancel();

  /// Stops the run and waits for the receiver's own terminal event.
  ///
  /// [cancel] only asks. This is the confirmed outcome [InteropRunner] must
  /// report, so a stop the receiver never acknowledged cannot look like a
  /// clean cancellation.
  Future<InteropStop> stop() async {
    if (_finished) {
      await _disposed.future;
      return _outcome ??
          const InteropStop(
            exitCode: 127,
            message: '后台运行已结束，但没有收到结果。',
            confirmed: false,
          );
    }
    await cancel();
    return _outcome ??
        const InteropStop(
          exitCode: 127,
          message: '后台运行通道已关闭，未收到停止确认。',
          confirmed: false,
        );
  }

  Future<void> _cancel() async {
    if (!_finished && !_startIssued) {
      _finish(
        _failure(
          _timedOut ? InteropErrorCode.timeout : InteropErrorCode.cancelled,
          _timedOut ? '后台运行超时。' : '后台运行已取消。',
          _timedOut ? 124 : 130,
        ),
      );
    } else if (!_finished) {
      // A successful method reply only acknowledges dispatch. Wait for the
      // receiver's terminal frame before InteropRunner may report a stop.
      unawaited(_sendControl('cancel'));
      try {
        await _terminal.future.timeout(cancellationGrace);
      } on TimeoutException {
        _finish(
          _failure(
            _timedOut
                ? InteropErrorCode.timeout
                : InteropErrorCode.transportFailure,
            _timedOut ? '后台运行超时，未收到停止确认。' : '未收到后台运行的停止确认。',
            _timedOut ? 124 : 127,
          ),
        );
      }
    }
    await _disposed.future;
  }

  Future<void> _sendControl(String method) async {
    try {
      await MethodChannelBackgroundInteropTransport.methods
          .invokeMethod<void>(method, _identity)
          .timeout(cancellationGrace);
    } on Object {
      // A method reply is not a terminal acknowledgement. The bounded wait
      // above diagnoses missing confirmation without claiming cancellation.
    }
  }

  Future<void> _dispose() async {
    try {
      try {
        await _subscription?.cancel().timeout(cancellationGrace);
      } on Object {
        // A broken event channel must not prevent native session disposal.
      }
      await _sendControl('dispose');
      await _deleteZip();
    } finally {
      onDisposed();
      _disposed.complete();
    }
  }

  Future<void> _deleteZip() async {
    final path = _zipPath;
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // The native bridge may already have released this session's payload.
    }
  }
}
