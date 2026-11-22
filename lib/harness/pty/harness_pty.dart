// Pseudo-terminal seam shared by harness hosts.
//
// A harness host that has to run an interactive program (`herdr agent attach`,
// an agent CLI, a login shell) needs a real PTY: a pipe pair has no terminal
// semantics, so full-screen clients either refuse to start or render garbage.
// Core has no PTY implementation of its own; StudioMux (the local host) owns
// the ConPTY / forkpty layer. Hosts depend on this interface instead of on that
// implementation, so the platform code stays in one place and tests can inject
// a structural fake.
//
// Bytes are terminal output, never line-split, and `write` is raw input: no
// trimming, no appended newline, no key reinterpretation.

import 'dart:async';
import 'dart:typed_data';

/// One running pseudo-terminal.
abstract interface class HarnessPty {
  /// Operating-system process id once the child has started.
  int? get pid;

  /// Raw terminal output. Never line-split.
  Stream<Uint8List> get output;

  /// Completes with the child's exit code.
  Future<int> get exitCode;

  /// Writes raw bytes to the child's terminal.
  void write(Uint8List data);

  /// Applies a new terminal geometry.
  void resize(int columns, int rows);

  /// Ends the child and releases the PTY. Idempotent.
  Future<void> kill();
}

/// Starts a process attached to a new pseudo-terminal.
abstract interface class HarnessPtyFactory {
  Future<HarnessPty> start({
    required List<String> argv,

    /// Working directory for the child; null means "where Studio runs".
    String? workingDirectory,
    Map<String, String>? environment,
    int columns,
    int rows,
  });
}

/// The PTY could not be created (no platform support, spawn failure).
class HarnessPtyException implements Exception {
  const HarnessPtyException(this.message);

  final String message;

  @override
  String toString() => message;
}
