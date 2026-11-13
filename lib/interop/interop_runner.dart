/// Runs a Studio project through the sibling language app.
///
/// The result shape matches [ProgramRunResult] on purpose: the editor already
/// knows how to attach a streamed program run to the terminal, and a
/// cross-app run must look the same to the user. The difference is only that
/// the output comes from another app's toolchain instead of this process.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'interop_payload.dart';
import 'interop_protocol.dart';
import 'interop_targets.dart';
import 'interop_transport.dart';

/// Exit code used when the program never ran. Matches
/// `kProgramNotRunExitCode` in `services/studio_profile.dart`; duplicated here
/// so this library does not import the services layer.
const int kInteropNotRunExitCode = 127;

/// One cross-app run, from payload collection to the final exit code.
class InteropRun {
  InteropRun._({
    required this.title,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.cancel,
    this.diagnostics = const <String>[],
  });

  /// Title for the terminal header.
  final String title;
  final Stream<String> stdout;
  final Stream<String> stderr;
  final Future<int> exitCode;

  /// Stops the receiver. Null when nothing was started.
  final Future<void> Function()? cancel;

  /// Real failure lines that belong in the terminal (missing app, refusal).
  /// Empty on a successful start.
  final List<String> diagnostics;

  /// A run that never started. The terminal shows [diagnostics] and the exit
  /// code says the program did not run.
  factory InteropRun.failed(String title, List<String> diagnostics) =>
      InteropRun._(
        title: title,
        stdout: const Stream<String>.empty(),
        stderr: Stream<String>.fromIterable(diagnostics),
        exitCode: Future<int>.value(kInteropNotRunExitCode),
        diagnostics: List<String>.unmodifiable(diagnostics),
      );
}

/// Bridges a project directory to the matching sibling app.
class InteropRunner {
  const InteropRunner({
    InteropTransport transport = const MethodChannelInteropTransport(),
  }) : _transport = transport;

  final InteropTransport _transport;

  InteropTransport get transport => _transport;

  /// Whether this platform has a cross-app bridge at all.
  bool get isSupported => _transport.isSupported;

  /// Whether [language] has a sibling app this client can address.
  static bool supports(String language) =>
      InteropTargets.forLanguage(language) != null;

  /// Checks that [target] answers the handshake.
  Future<InteropProbe> probe(String language) async {
    final target = InteropTargets.forLanguage(language);
    if (target == null) {
      return InteropProbe.missing(InteropTargets.installHint(language));
    }
    return _transport.probe(target);
  }

  /// Collects [projectRoot], sends it to the matching sibling app and streams
  /// its real output. Never throws for a missing app or a refused payload:
  /// those become a [InteropRun] with `diagnostics` and exit code 127.
  Future<InteropRun> run({
    required String projectRoot,
    required String language,
    required String entryFile,
    String stdin = '',
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final target = InteropTargets.forLanguage(language);
    final title = '运行 ${p.basename(entryFile)}（${interopLabel(language)}）';
    if (target == null) {
      return InteropRun.failed(title, <String>[
        InteropTargets.installHint(language),
      ]);
    }
    if (!_transport.isSupported) {
      return InteropRun.failed(title, <String>['当前平台不支持跨应用调用。']);
    }
    final entry = _relativeEntry(projectRoot, entryFile);
    if (entry == null) {
      return InteropRun.failed(title, <String>['入口文件不在项目内或无法读取：$entryFile']);
    }

    final List<InteropPayloadFile> files;
    try {
      files = await InteropProjectPayload.collect(projectRoot);
    } on InteropException catch (error) {
      return InteropRun.failed(title, <String>[error.message]);
    }
    if (files.isEmpty) {
      return InteropRun.failed(title, <String>['项目里没有可编译的文件。']);
    }
    if (!files.any((file) => file.path == entry)) {
      return InteropRun.failed(title, <String>['入口文件不在跨应用 payload 中：$entry']);
    }

    final request = InteropRequest(
      sessionId: InteropSession.create(),
      sessionToken: _sessionToken(),
      language: target.language,
      entry: entry,
      action: InteropAction.run,
      callerBundle: InteropStudio.bundleName,
      bridgeAction: InteropStudio.bridgeAction,
      files: files,
      stdin: stdin,
      timeoutMs: timeout.inMilliseconds.clamp(
        InteropLimits.minTimeoutMs,
        InteropLimits.maxTimeoutMs,
      ),
    );
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exit = Completer<int>();
    final retained = _Retainer(InteropLimits.maxRetainedOutputBytes);
    InteropLaunch? launch;

    void finish(int code) {
      if (exit.isCompleted) return;
      exit.complete(code);
      unawaited(stdoutController.close());
      unawaited(stderrController.close());
    }

    void emit(bool isError, String text) {
      if (text.isEmpty) return;
      final kept = retained.take(text);
      if (kept.isEmpty) return;
      final controller = isError ? stderrController : stdoutController;
      if (!controller.isClosed) controller.add(kept);
    }

    try {
      launch = await _transport.start(target, request);
    } on InteropException catch (error) {
      return InteropRun.failed(title, <String>[error.message]);
    }

    late final InteropLaunch started;
    started = launch;
    final subscription = started.events.listen(
      (event) {
        switch (event.kind) {
          case InteropEventKind.accepted:
          case InteropEventKind.progress:
            // Stage lines are the receiver's own wording; they belong in the
            // terminal as system output so the user sees real progress.
            emit(false, '· ${event.text}');
          case InteropEventKind.stdout:
            emit(false, event.text);
          case InteropEventKind.stderr:
            emit(true, event.text);
          case InteropEventKind.artifact:
            emit(false, '产物：${event.text}');
          case InteropEventKind.error:
            emit(true, _errorText(event));
            finish(event.exitCode ?? _errorExitCode(event.code));
          case InteropEventKind.done:
            // A `done` text is the receiver's closing note, not program
            // output. The background route streams real stdout and stderr, so
            // its closing note belongs in the diagnostic stream; the shared
            // foreground receiver aggregates the run into one frame, so its
            // text is all the output there is and stays on stdout.
            if (event.text.isNotEmpty) {
              if (started.stop != null) {
                emit(true, event.text);
              } else {
                emit(false, event.text);
              }
            }
            finish(event.exitCode ?? 1);
        }
      },
      onError: (Object error) {
        emit(true, error is InteropException ? error.message : '$error');
        finish(kInteropNotRunExitCode);
      },
      onDone: () {
        if (!exit.isCompleted) {
          emit(true, '跨应用运行会话中断，未收到完成事件。');
          finish(kInteropNotRunExitCode);
        }
      },
      cancelOnError: true,
    );
    unawaited(
      exit.future.whenComplete(() {
        unawaited(subscription.cancel());
      }),
    );

    return InteropRun._(
      title: title,
      stdout: stdoutController.stream,
      stderr: stderrController.stream,
      exitCode: exit.future,
      cancel: () async {
        if (exit.isCompleted) return;
        final stop = started.stop;
        if (stop == null) {
          // The foreground receiver has no start method that reports a real
          // process stop, so its cancel is a request and the exit code says
          // exactly that. Never promote it to a confirmed cancellation.
          await started.cancel();
          emit(false, '已请求停止跨应用运行。');
          finish(130);
          return;
        }
        // A stop the receiver never acknowledged is a diagnostic, not a
        // cancellation: emit its own code instead of inventing 130.
        final outcome = await stop();
        emit(true, outcome.message);
        finish(outcome.exitCode);
      },
    );
  }

  /// Routes one agent command to the matching sibling app (R7).
  ///
  /// Returns null when the command is outside the accepted grammar or the
  /// platform has no bridge, which tells the caller to keep its own execution
  /// path. The returned [InteropRun] has already run to completion.
  Future<InteropRun?> tryRunCommand({
    required String projectRoot,
    required String language,
    required String command,
  }) async {
    if (!_transport.isSupported) return null;
    final target = InteropTargets.forLanguage(language);
    if (target == null) return null;
    final parsed = _parseCommand(command, language);
    if (parsed == null) return null;
    final files = await InteropProjectPayload.collect(projectRoot);
    final entry = parsed.entry;
    if (entry != null && !files.any((file) => file.path == entry)) return null;
    final request = InteropRequest(
      sessionId: InteropSession.create(),
      sessionToken: _sessionToken(),
      language: target.language,
      entry: entry ?? '',
      action: parsed.action,
      callerBundle: InteropStudio.bundleName,
      bridgeAction: InteropStudio.bridgeAction,
      files: files,
    );
    try {
      final launch = await _transport.start(target, request);
      final buffer = _CommandBuffer();
      await for (final event in launch.events) {
        switch (event.kind) {
          case InteropEventKind.stdout:
          case InteropEventKind.progress:
          case InteropEventKind.accepted:
          case InteropEventKind.artifact:
            buffer.addOut(event.text);
          case InteropEventKind.stderr:
            buffer.addErr(event.text);
          case InteropEventKind.error:
            buffer.addErr(_errorText(event));
            buffer.exitCode = event.exitCode ?? _errorExitCode(event.code);
          case InteropEventKind.done:
            buffer.exitCode = event.exitCode ?? 1;
        }
      }
      return buffer.toRun(language: language, entry: entry ?? '');
    } on InteropException catch (error) {
      return InteropRun.failed(
        '编译 ${p.basename(projectRoot)}（${interopLabel(language)}）',
        <String>[error.message],
      );
    }
  }

  static String? _relativeEntry(String projectRoot, String entryFile) {
    final root = p.normalize(p.absolute(projectRoot));
    final entry = p.normalize(p.absolute(entryFile));
    if (!p.isWithin(root, entry)) return null;
    final relative = p.relative(entry, from: root).replaceAll('\\', '/');
    return InteropPath.isValid(relative) ? relative : null;
  }

  /// A fresh per-run secret for the response-event token check.
  static String _sessionToken() {
    final random = Random.secure();
    return List<String>.generate(24, (_) {
      return random.nextInt(16).toRadixString(16);
    }).join();
  }

  static String _errorText(InteropEvent event) {
    final message = event.text.isEmpty ? _codeLabel(event.code) : event.text;
    return '跨应用运行失败（${event.code ?? 'error'}）：$message';
  }

  static int _errorExitCode(String? code) {
    switch (code) {
      case InteropErrorCode.cancelled:
        return 130;
      case InteropErrorCode.timeout:
        return 124;
      default:
        return kInteropNotRunExitCode;
    }
  }

  static String _codeLabel(String? code) {
    switch (code) {
      case InteropErrorCode.badRequest:
        return '请求参数不合法';
      case InteropErrorCode.unsupportedProtocol:
        return '对方应用版本过旧，无法识别本协议';
      case InteropErrorCode.callerNotAllowed:
        return '对方应用拒绝了这个调用方';
      case InteropErrorCode.payloadTooLarge:
        return '项目超过跨应用传输上限';
      case InteropErrorCode.payloadIntegrity:
        return '项目内容校验失败';
      case InteropErrorCode.unsupportedLanguage:
        return '对方应用不支持这个语言';
      case InteropErrorCode.toolchainUnavailable:
        return '对方应用的本地工具链无法启动';
      case InteropErrorCode.compileFailed:
        return '编译失败';
      case InteropErrorCode.runFailed:
        return '程序返回非零退出码';
      case InteropErrorCode.timeout:
        return '运行超时';
      case InteropErrorCode.cancelled:
        return '运行已取消';
      default:
        return '对方应用内部错误';
    }
  }
}

/// User-facing language label used in a run title.
String interopLabel(String language) {
  switch (language.toLowerCase()) {
    case 'java':
      return 'QFLIJVMX 本地编译';
    case 'c':
    case 'cpp':
      return 'QFLIForge 本地编译';
    case 'python':
      return 'QFLIPyFlow 本地解释';
    default:
      return language;
  }
}

class _ParsedCommand {
  const _ParsedCommand({required this.action, this.entry});

  final InteropAction action;

  /// Entry file for a run. Null for a compile of every source in the payload.
  final String? entry;
}

/// Accepted agent commands. Anything else returns null so the caller keeps its
/// existing path; guessing at a shell would let a command mean something
/// different in the sibling app.
_ParsedCommand? _parseCommand(String command, String language) {
  final words = command.trim().split(RegExp(r'\s+'));
  if (words.isEmpty) return null;
  switch (language.toLowerCase()) {
    case 'java':
      if (words.length == 1 && words.first == 'javac') {
        return const _ParsedCommand(action: InteropAction.compile);
      }
      return null;
    case 'c':
    case 'cpp':
      return null;
    case 'python':
      if (words.length == 2 &&
          const <String>{'python', 'python3'}.contains(words.first)) {
        final entry = words[1].replaceAll('\\', '/');
        if (!InteropPath.isValid(entry)) return null;
        return _ParsedCommand(action: InteropAction.run, entry: entry);
      }
      return null;
    default:
      return null;
  }
}

/// Keeps the first [limit] bytes of output. Later bytes are dropped rather
/// than silently replacing earlier evidence.
class _Retainer {
  _Retainer(this.limit);

  final int limit;
  int _used = 0;

  String take(String text) {
    if (_used >= limit) return '';
    final encoded = utf8.encode(text);
    if (_used + encoded.length <= limit) {
      _used += encoded.length;
      return text;
    }
    // Cut on a character boundary so the caller never sees half a rune.
    final remaining = limit - _used;
    final units = text.codeUnits;
    var keep = 0;
    var bytes = 0;
    while (keep < units.length) {
      final unit = units[keep];
      final width = unit < 0x80
          ? 1
          : unit < 0x800
          ? 2
          : (unit >= 0xD800 && unit <= 0xDBFF)
          ? 0
          : 3;
      if (bytes + width > remaining) break;
      bytes += width;
      keep++;
    }
    _used += bytes;
    return keep == 0 ? '' : text.substring(0, keep);
  }
}

class _CommandBuffer {
  final StringBuffer _out = StringBuffer();
  final StringBuffer _err = StringBuffer();
  int exitCode = kInteropNotRunExitCode;

  void addOut(String text) {
    if (text.isEmpty) return;
    if (_out.isNotEmpty) _out.write('\n');
    _out.write(text);
  }

  void addErr(String text) {
    if (text.isEmpty) return;
    if (_err.isNotEmpty) _err.write('\n');
    _err.write(text);
  }

  InteropRun toRun({required String language, required String entry}) {
    final out = _out.toString();
    final err = _err.toString();
    final code = exitCode;
    return InteropRun._(
      title: entry.isEmpty
          ? '编译项目（${interopLabel(language)}）'
          : '运行 ${p.basename(entry)}（${interopLabel(language)}）',
      stdout: Stream<String>.fromIterable(
        out.isEmpty ? const <String>[] : <String>[out],
      ),
      stderr: Stream<String>.fromIterable(
        err.isEmpty ? const <String>[] : <String>[err],
      ),
      exitCode: Future<int>.value(code),
      diagnostics: err.isEmpty ? const <String>[] : <String>[err],
    );
  }
}
