import 'dart:async';

import 'git_clone_progress.dart';

/// Parses Git's carriage-return and newline progress records into typed stages.
/// Raw stderr text is never passed to the observer.
class GitCloneProgressParser {
  GitCloneProgressParser(
    this.onProgress, {
    this.throttleInterval = const Duration(milliseconds: 100),
  });

  final GitCloneProgressCallback? onProgress;
  final Duration throttleInterval;
  final StringBuffer _line = StringBuffer();
  bool _closed = false;
  DateTime? _lastEmittedAt;
  GitCloneStage? _lastEmittedStage;
  GitCloneProgress? _pending;
  Timer? _timer;

  void add(List<int> bytes) {
    if (_closed) return;
    for (final byte in bytes) {
      if (byte == 13 || byte == 10) {
        _parseLine();
        _line.clear();
        continue;
      }
      if (byte >= 32 && byte < 127 && _line.length < 4096) {
        _line.writeCharCode(byte);
      }
    }
  }

  void close({bool flush = true}) {
    if (_closed) return;
    _closed = true;
    if (flush && _line.isNotEmpty) _parseLine();
    _line.clear();
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (flush && pending != null) _emit(pending);
  }

  void _parseLine() {
    final line = _line.toString();
    final percent = RegExp(
      r'^(Receiving objects|Resolving deltas|Updating files):\s*(\d+)%',
    ).firstMatch(line);
    final counts = RegExp(r'\((\d+)/(\d+)\)').firstMatch(line);
    if (percent == null) return;

    final stage = switch (percent.group(1)) {
      'Receiving objects' => GitCloneStage.receiving,
      'Resolving deltas' => GitCloneStage.resolving,
      'Updating files' => GitCloneStage.checkout,
      _ => null,
    };
    if (stage == null) return;

    final completed = counts == null
        ? (int.tryParse(percent.group(2) ?? '') ?? 0)
        : (int.tryParse(counts.group(1) ?? '') ?? 0);
    final total = counts == null
        ? 100
        : (int.tryParse(counts.group(2) ?? '') ?? 0);
    final byteMatch = RegExp(
      r'([\d.]+)\s*(bytes|KiB|MiB|GiB)\s*\|',
    ).firstMatch(line);
    final receivedBytes = byteMatch == null
        ? 0
        : _bytes(byteMatch.group(1) ?? '', byteMatch.group(2) ?? 'bytes');
    _offer(
      GitCloneProgress(
        stage: stage,
        completed: completed,
        total: total,
        receivedBytes: receivedBytes,
      ),
    );
  }

  void _offer(GitCloneProgress progress) {
    final stageChanged = progress.stage != _lastEmittedStage;
    final terminal = progress.total > 0 && progress.completed >= progress.total;
    final last = _lastEmittedAt;
    final elapsed = last == null
        ? throttleInterval
        : DateTime.now().difference(last);
    if (stageChanged || terminal || elapsed >= throttleInterval) {
      _timer?.cancel();
      _timer = null;
      _pending = null;
      _emit(progress);
      return;
    }

    _pending = progress;
    if (_timer != null) return;
    final wait = throttleInterval - elapsed;
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _timer = null;
      final pending = _pending;
      _pending = null;
      if (pending != null) _emit(pending);
    });
  }

  void _emit(GitCloneProgress progress) {
    _lastEmittedAt = DateTime.now();
    _lastEmittedStage = progress.stage;
    emitGitCloneProgress(onProgress, progress);
  }

  static int _bytes(String amount, String unit) {
    final value = double.tryParse(amount);
    if (value == null) return 0;
    final multiplier = switch (unit) {
      'KiB' => 1024,
      'MiB' => 1024 * 1024,
      'GiB' => 1024 * 1024 * 1024,
      _ => 1,
    };
    return (value * multiplier).round();
  }
}
