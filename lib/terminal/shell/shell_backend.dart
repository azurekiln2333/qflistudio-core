import 'dart:async';

import 'package:flutter/foundation.dart';

import 'command_parser.dart';

/// Where a chunk of shell output came from.
enum OutputKind {
  stdout,
  stderr,
  system,

  /// Control message consumed by the UI (currently only `clear`).
  control,
}

/// A piece of raw shell output.
@immutable
class ShellChunk {
  const ShellChunk(this.text, this.kind);

  final String text;
  final OutputKind kind;
}

/// Common contract for every shell implementation: a real OS process on
/// desktop / mobile, or the bundled virtual filesystem used for practice and as
/// a fallback on platforms without `dart:io`.
///
/// Implementations are [ChangeNotifier]s so the UI can react to `busy` and
/// `cwd` transitions without polling.
abstract class ShellBackend extends ChangeNotifier {
  /// Human readable name shown in the UI, e.g. `PowerShell`.
  String get shellLabel;

  /// Current working directory.
  String get cwd;

  /// [cwd] rendered for display, with a leading home directory shown as `~` the
  /// way a shell prompt does it.
  ///
  /// Only the prompt and the window subtitle use this. `pwd` still prints the
  /// real absolute path, matching what a real shell does.
  String get displayCwd;

  /// Prompt rendered in front of the input line.
  String get prompt;

  /// True while an external command is executing.
  bool get busy;

  /// Whether [interrupt] can actually stop a running command.
  bool get canInterrupt;

  /// Raw output stream. Chunks may split escape sequences mid-way.
  Stream<ShellChunk> get output;

  /// Runs [command]. Built-in commands are handled by the backend itself.
  Future<void> execute(String command);

  /// Exit status of the most recent external command, or null when the last
  /// command was a built-in (which has no process status) or none ran yet.
  int? get lastExitCode;

  /// Best-effort cancellation of the running command (Ctrl+C).
  Future<void> interrupt();

  /// Releases resources. Named `shutdown` to avoid clashing with
  /// [ChangeNotifier.dispose].
  Future<void> shutdown();

  /// Non-null while an interactive tool (netcat, telnet, an SSH shell, the SFTP
  /// prompt) owns the input line. The session then routes submitted lines to
  /// [sendLine] instead of executing them as commands.
  String? get attachLabel;

  /// True while [attachLabel] is set.
  bool get attached;

  /// Whether the attached tool echoes what it receives. When false the
  /// terminal must not echo either, or remote-echoed input would appear twice.
  bool get attachEcho;

  /// Whether the attached tool wants a prompt drawn on the input row.
  ///
  /// False when the far end prints its own prompt as ordinary output, so ours
  /// would appear as a second one ahead of the cursor.
  bool get attachPrompt;

  /// Whether the attached tool is asking for a secret. The terminal masks the
  /// input and keeps it out of the scrollback and the history.
  ///
  /// Distinct from `!attachEcho`: an `ssh` shell does not echo locally (the
  /// remote does) but is not secret.
  bool get attachSecret;

  /// Feeds one line of input to the attached tool.
  Future<void> sendLine(String line);

  /// Leaves interactive mode, tearing the connection down.
  void detach();
}

/// Minimal output surface shared by the portable built-in helper and the
/// backends, so the helper can be unit-tested without a [ChangeNotifier].
abstract interface class ShellSink {
  /// Emits [text] verbatim (no trailing newline is added).
  void raw(String text);

  /// Emits [text] followed by a newline.
  void line(String text);

  /// Emits a user-facing error line.
  void error(String text);
}

/// Shared plumbing: output stream, built-in commands, busy bookkeeping and the
/// [NetHost] implementation every backend hands to the network toolkit.
abstract class BaseShellBackend extends ChangeNotifier
    implements ShellBackend, ShellSink {
  // Synchronous delivery matters: output must land in the session buffer before
  // `execute` completes, otherwise a following command echo could be inserted
  // in the middle of this command's output.
  final StreamController<ShellChunk> _controller =
      StreamController<ShellChunk>.broadcast(sync: true);

  bool _busy = false;
  bool _disposed = false;
  String _cwd = '';
  int? _lastExitCode;

  @override
  int? get lastExitCode => _lastExitCode;

  /// Records the exit status of the last external command. Called by
  /// [runExternal] implementations; resets to null for built-ins.
  @protected
  set lastExitCode(int? value) => _lastExitCode = value;

  void Function()? _cancelHandler;
  bool _cancelRequested = false;

  @override
  Stream<ShellChunk> get output => _controller.stream;

  @override
  String get cwd => _cwd;

  /// Directory that `~` stands for, or null when this backend has no home.
  ///
  /// Deliberately not part of [ShellBackend]: only the backend itself needs it,
  /// to build the prompt and to expand `~` in paths.
  @protected
  String? get homeDirectory => null;

  @override
  String get displayCwd => compactPath(cwd);

  /// [path] with a leading [homeDirectory] replaced by `~`.
  ///
  /// Shared by every backend so the prompt looks the same everywhere, and
  /// public so tests can pin down the boundary cases (a sibling directory whose
  /// name merely starts with the home path must not be compacted).
  String compactPath(String path) {
    final home = homeDirectory;
    if (home == null || home.isEmpty) return path;
    if (path == home) return '~';
    // Match either separator so a Windows home (`C:\Users\me`) compacts even
    // when the session is holding a forward-slash path.
    for (final separator in const <String>['/', r'\']) {
      if (path.startsWith('$home$separator')) {
        return '~${path.substring(home.length)}';
      }
    }
    return path;
  }

  @override
  bool get busy => _busy;

  @override
  bool get canInterrupt => true;

  @override
  String? get attachLabel => null;

  @override
  bool get attached => false;

  @override
  bool get attachEcho => true;

  @override
  bool get attachPrompt => true;

  @override
  bool get attachSecret => false;

  @protected
  set cwd(String value) {
    if (_cwd == value) return;
    _cwd = value;
    _notify();
  }

  @protected
  set busyState(bool value) {
    if (_busy == value) return;
    _busy = value;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @protected
  void emit(String text, [OutputKind kind = OutputKind.stdout]) {
    if (_disposed || text.isEmpty) return;
    _controller.add(ShellChunk(text, kind));
  }

  @override
  void raw(String text) => emit(text);

  @override
  void line(String text) => emitLine(text);

  @override
  void error(String text) => emitLine(text, OutputKind.stderr);

  @protected
  void emitLine(String text, [OutputKind kind = OutputKind.stdout]) =>
      emit('$text\n', kind);

  // --------------------------------------------------------------- execution

  @override
  Future<void> execute(String command) async {
    if (_busy || attached) return;
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    // The whole lifecycle — built-in or external, sync or async — runs under
    // `busy` so the pane's derived state cannot get stuck and a second command
    // cannot race the first.
    busyState = true;
    // Open the cancellation window *before* the first asynchronous boundary so
    // an interrupt() in the same turn as execute() is not lost. The subclass
    // reads this flag and must not reset it.
    _cancelRequested = false;
    onCommandStart();
    try {
      // Built-ins have no process status.
      _lastExitCode = null;
      if (await handleBuiltin(trimmed)) return;
      await runExternal(trimmed);
    } catch (error) {
      emitLine('shell: $error', OutputKind.stderr);
    } finally {
      busyState = false;
      onCommandEnd();
    }
  }

  /// True once [interrupt] has been requested for the current command.
  @protected
  bool get cancelRequested => _cancelRequested;

  /// Called at the start of an accepted command, before its first await, so a
  /// subclass can install its cancellation bookkeeping.
  @protected
  void onCommandStart() {}

  /// Called when an accepted command finishes (success, failure, cancel).
  @protected
  void onCommandEnd() {}

  /// Records a cancellation request for the running command. A request with no
  /// command in flight is dropped so it cannot poison the next command.
  @protected
  void requestCancel() {
    if (_busy) _cancelRequested = true;
  }

  /// Commands shared by every backend. Returns true when fully handled.
  ///
  /// Order is deliberate:
  ///   1. Shell syntax (pipes/redirection/chaining/expansion) is classified
  ///      first and, when present, is never treated as built-in operands.
  ///   2. Trivial cross-platform built-ins (`clear`, `pwd`, `help`, `cd`).
  ///   3. Portable real-filesystem commands provided by the IO implementation.
  ///
  /// A portable command that fails (bad option, missing file) still returns
  /// true: it was recognised, so it must not fall through to a shell that would
  /// silently reinterpret it.
  @protected
  Future<bool> handleBuiltin(String command) async {
    final policy = escapePolicy;
    final syntax = CommandParser.classify(command, escapePolicy: policy);
    if (syntax == CommandSyntax.empty) return true;

    // Compound syntax needs a real shell. Signal the caller to use the
    // external path; built-ins must never see the operator characters.
    if (syntax == CommandSyntax.compound) return false;

    final parsed = CommandParser.tokenize(command, escapePolicy: policy);
    if (!parsed.ok) {
      emitLine(parsed.error!, OutputKind.stderr);
      return true;
    }
    final tokens = parsed.tokens;
    if (tokens.isEmpty) return true;

    final name = tokens.first.text;
    final args = tokens.sublist(1);
    switch (name) {
      case 'clear':
      case 'cls':
        if (args.isNotEmpty) {
          emitLine('$name: too many arguments', OutputKind.stderr);
          return true;
        }
        emit('clear', OutputKind.control);
        return true;
      case 'pwd':
        if (args.isNotEmpty) {
          emitLine('pwd: too many arguments', OutputKind.stderr);
          return true;
        }
        emitLine(cwd);
        return true;
      case 'help':
        emitLine(helpText);
        return true;
      case 'cd':
        return changeDirectoryTokens(args);
    }

    return handlePortableBuiltin(tokens.first, args);
  }

  /// Runs a portable real-filesystem command, or returns false when [name] is
  /// not one of them. Implemented by the IO backend; the default reports the
  /// platform limitation.
  @protected
  bool handlePortableBuiltin(CommandToken name, List<CommandToken> args) =>
      false;

  /// How this backend's host treats backslashes. Defaults to POSIX escaping;
  /// the Windows IO backend overrides it to a literal-separator policy so
  /// classification and tokenization stay consistent on both hosts.
  @protected
  EscapePolicy get escapePolicy => EscapePolicy.backslashEscapes;

  /// [cd] with already-tokenized arguments, so quoted paths survive.
  @protected
  Future<bool> changeDirectoryTokens(List<CommandToken> args) async {
    final operands = <CommandToken>[];
    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && arg.text == '--') {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        emitLine('cd: unsupported option: ${arg.text}', OutputKind.stderr);
        return true;
      }
      operands.add(arg);
    }
    if (operands.length > 1) {
      emitLine('cd: too many arguments', OutputKind.stderr);
      return true;
    }
    if (operands.isEmpty) {
      // Only `cd` with no argument defaults to the home directory.
      return changeDirectoryToken(null);
    }
    final operand = operands.first;
    if (operand.text.isEmpty) {
      emitLine('cd: empty path operand', OutputKind.stderr);
      return true;
    }
    return changeDirectoryToken(operand);
  }

  /// Changes directory for an already-tokenized operand. A null token means a
  /// no-argument `cd` (home). Quoted operands do not expand a literal `~`.
  @protected
  Future<bool> changeDirectoryToken(CommandToken? operand) => changeDirectory(
    operand == null || !operand.quoted ? (operand?.text ?? '~') : operand.text,
    expandTilde: operand == null || !operand.quoted,
  );

  /// Multi-line help text shown by the `help` built-in.
  @protected
  String get helpText;

  /// Resolves [target] and updates [cwd]. Returns true when handled, even if
  /// the directory does not exist (the error is reported via [emit]). When
  /// [expandTilde] is false a literal `~` operand is not the home directory.
  @protected
  Future<bool> changeDirectory(String target, {bool expandTilde = true});

  /// Executes a non-built-in command.
  @protected
  Future<void> runExternal(String command);

  @override
  Future<void> sendLine(String line) async {
    // QFLI local sessions do not attach network tools.
  }

  @override
  void detach() {}

  @override
  Future<void> interrupt() async {
    // Mark first so the request survives even if it arrives before the child
    // process exists.
    requestCancel();
    final cancel = _cancelHandler;
    if (cancel != null) {
      emitLine('^C', OutputKind.system);
      cancel();
      return;
    }
    await onInterrupt();
  }

  /// Ctrl+C handling for backends that own a child process directly. Called
  /// only when no cancellable task is registered.
  @protected
  Future<void> onInterrupt() async {}

  // --------------------------------------------------------------- lifecycle

  @override
  Future<void> shutdown() async {
    _disposed = true;
    _cancelHandler = null;
    await _controller.close();
    dispose();
  }
}
