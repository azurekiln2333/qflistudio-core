import 'package:flutter/foundation.dart';

enum AppRestoreStatus { completed, needsRecovery }

/// A cold restore invalidates runtime and store objects created this launch.
/// Keep the app behind this gate until the process has been fully restarted.
abstract final class AppRestoreGate {
  static final ValueNotifier<AppRestoreStatus?> status = ValueNotifier(null);

  static void requireRestart() => status.value = AppRestoreStatus.completed;

  static void requireRecovery() =>
      status.value = AppRestoreStatus.needsRecovery;
}
