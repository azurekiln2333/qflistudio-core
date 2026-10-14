import 'package:flutter/foundation.dart';

/// TEMPORARY on-device diagnostics for the terminal tab-bar investigation.
///
/// Remove this file, and every `EditorPageDiag.*` call, once the device
/// behaviour is understood. It exists because the tab-bar click-through symptom
/// does not reproduce under `flutter test`, so the real hit-test and focus path
/// has to be observed on hardware.
///
/// Two sinks are used on purpose:
///
/// * `print` — the OHOS Flutter engine forwards the Dart print port to hilog
///   tag `Flutter`, which is the only channel that survives a **release** hap.
///   `stderr`/`debugPrint` are stripped there.
/// * an in-memory ring buffer exposed through [lines] — so an on-screen panel
///   (or a VM-service eval) can read the trace even without a log capture.
abstract final class EditorPageDiag {
  /// Flip to `false` (or build with
  /// `--dart-define=QFLI_DIAG_TABBAR=false`) to silence the trace without
  /// removing the calls.
  static const bool enabled = bool.fromEnvironment(
    'QFLI_DIAG_TABBAR',
    defaultValue: false,
  );

  /// Most recent entries, newest last. Bounded, so a long session cannot grow
  /// it without limit.
  static final List<String> lines = <String>[];
  static const int _maxLines = 60;

  static void diag(String message) {
    if (!enabled) return;
    lines.add(message);
    if (lines.length > _maxLines) lines.removeAt(0);
    _emit('[DIAG-TABBAR] $message');
  }

  /// Isolated so the one suppression is unambiguous, and so the whole file can
  /// be deleted in a single edit once the device behaviour is understood.
  static void _emit(String message) {
    // The Dart print port is forwarded to hilog tag `Flutter` by the OHOS
    // engine; `stderr`/`debugPrint` are stripped from a release hap.
    // ignore: avoid_print
    print(message);
  }

  /// Emitted once at startup so a log capture can confirm the channel works
  /// before any interaction has happened.
  static void probeAlive(String where) =>
      diag('channel-alive from $where (enabled=$enabled, debug=$kDebugMode)');
}
