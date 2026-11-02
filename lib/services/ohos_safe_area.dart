import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Top inset reported by the HarmonyOS host for the status bar and the
/// display cutout (punch hole / notch).
///
/// The host reads `window.WindowStage.getWindowAvoidArea(TYPE_SYSTEM)` and
/// `getWindowAvoidArea(TYPE_CUTOUT)`, converts the px values to logical
/// pixels, and pushes them over [channelName]. Folded and unfolded states
/// report different values, so the host also listens for `avoidAreaChange`.
///
/// The reported value is only a *minimum*: callers combine it with the
/// viewport padding that Flutter already derives, so a wrong or missing
/// report can never shrink the inset below what Flutter knows.
class OhosSafeArea {
  OhosSafeArea._();

  static const channelName = 'qflistudio/safe_area';

  static final ValueNotifier<double> _topAvoid = ValueNotifier<double>(0);
  static bool _listening = false;

  /// Latest top avoid height in logical pixels. Zero when the host cannot
  /// report it (non-HarmonyOS platforms, older hosts, or before first frame).
  static ValueListenable<double> get topAvoid => _topAvoid;

  /// Starts listening for host updates once. Safe to call from any page.
  static void ensureListening() {
    if (_listening) return;
    _listening = true;
    const channel = MethodChannel(channelName);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'update' && call.arguments is Map) {
        _apply(call.arguments as Map);
      }
      return null;
    });
    unawaited(_requestCurrent());
  }

  /// Reads the current value from the host. Missing plugin (other platforms)
  /// and platform errors keep the previous value.
  static Future<void> _requestCurrent() async {
    try {
      final value = await const MethodChannel(
        channelName,
      ).invokeMapMethod<String, Object?>('getSafeArea');
      if (value != null) _apply(value);
    } on MissingPluginException {
      // Not a HarmonyOS host.
    } on PlatformException {
      // Keep the last known value.
    }
  }

  static void _apply(Map<Object?, Object?> value) {
    final top = value['top'];
    if (top is num && top.isFinite && top >= 0) {
      _topAvoid.value = top.toDouble();
    }
  }

  /// Drops the cached value. The app keeps the last host answer for the whole
  /// process; tests reset it so cases stay independent.
  @visibleForTesting
  static void debugResetTopAvoid() {
    _topAvoid.value = 0;
  }

  /// Asks the host again for the current avoid area. The host only pushes a
  /// new value when the window changes; tests call this after a reset.
  @visibleForTesting
  static Future<void> debugRefetch() => _requestCurrent();

  /// Inset to add on top of [viewportTop] so that page content never sits
  /// under the status bar or the cutout.
  static double topInset(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).top;
    return math.max(padding, _topAvoid.value);
  }
}

/// Rebuilds [builder] when the host reports a new avoid area, so a late
/// answer still reaches a page that is already on screen.
class OhosSafeAreaBuilder extends StatelessWidget {
  const OhosSafeAreaBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, double topInset) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: OhosSafeArea.topAvoid,
      builder: (context, _, child) =>
          builder(context, OhosSafeArea.topInset(context)),
    );
  }
}
