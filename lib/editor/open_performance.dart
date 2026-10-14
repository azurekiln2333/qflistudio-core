import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';

/// Opt-in timing instrumentation for the project-open path.
///
/// Off by default — enable with
/// `flutter run --dart-define=QFLI_PERF=true`, or `flutter build hap
/// --dart-define=QFLI_PERF=true` for an on-device capture. When disabled every
/// method returns immediately, so the cost is a single const check per call.
///
/// Why this exists: the open path could not be timed inside a widget test
/// (`EditorPage` does real file IO and keeps timers alive, so awaiting it hangs
/// the runner). These marks record the same phases on a real device, which is
/// also the only place the numbers mean anything.
abstract final class OpenPerformance {
  /// Compile-time switch. `bool.fromEnvironment` means the disabled path is
  /// tree-shaken out of release builds.
  static const bool enabled = bool.fromEnvironment('QFLI_PERF');

  static const String _tag = 'QFLI_PERF';

  static Stopwatch? _watch;
  static int _fields = 0;
  static Duration _lastFrame = Duration.zero;

  /// Kept so the callback can be removed; `addTimingsCallback` returns void in
  /// this Flutter version, so the reference has to be held here.
  static void Function(List<FrameTiming>)? _timingsCallback;

  /// Begins a measurement, typically on the tap that opens a project.
  static void beginOpen(String projectName) {
    if (!enabled) return;
    _watch = Stopwatch()..start();
    _lastFrame = Duration.zero;
    _fields = 0;
    _timingsCallback ??= _onTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
    _mark('beginOpen "$projectName"');
  }

  /// Records a named phase against the current measurement.
  static void mark(String phase) {
    if (!enabled || _watch == null) return;
    _mark(phase);
  }

  static void _mark(String phase) {
    developer.log(
      '$phase at ${_watch!.elapsedMilliseconds} ms',
      name: _tag,
    );
  }

  /// Finishes the measurement and reports the frame statistics collected over
  /// the same window.
  static void endOpen() {
    if (!enabled || _watch == null) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _mark('endOpen (total ${_watch!.elapsedMilliseconds} ms, $_fields frames)');
    _watch = null;
  }

  /// Counts dropped and total frames while a measurement is running, using the
  /// engine's own build+raster times rather than wall-clock guesses.
  static void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final total = timing.totalSpan;
      _lastFrame = total;
      _fields++;
      // 16 ms is one frame at 60 Hz; anything past it is a visible drooped
      // frame worth reporting on its own line.
      if (total > const Duration(milliseconds: 16)) {
        developer.log(
          'frame ${timing.frameNumber} slow: '
          'build ${timing.buildDuration.inMilliseconds} ms, '
          'raster ${timing.rasterDuration.inMilliseconds} ms',
          name: _tag,
        );
      }
    }
  }

  /// The most recent frame's total span, for a quick read.
  static Duration get lastFrame => _lastFrame;
}
