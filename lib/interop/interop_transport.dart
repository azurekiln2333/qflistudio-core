/// The channel between the Studio Dart side and the ArkTS interop bridge.
///
/// Dart cannot start another bundle directly; ArkTS does it. This file is the
/// only place that knows the channel names, so the Dart runner logic runs
/// against [InteropTransport] and the tests run against a fake.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'interop_protocol.dart';
import 'interop_targets.dart';

/// Result of asking a receiver whether it is installed and capable.
class InteropProbe {
  const InteropProbe({
    required this.available,
    this.protocol,
    this.languages = const <String>{},
    this.diagnostic,
  });

  const InteropProbe.missing(String this.diagnostic)
    : available = false,
      protocol = null,
      languages = const <String>{};

  final bool available;

  /// Protocol the receiver answered with, when available.
  final String? protocol;

  /// Languages the receiver reported through the handshake.
  final Set<String> languages;
  final String? diagnostic;
}

/// A request that has been handed to the platform and can be cancelled.
class InteropLaunch {
  const InteropLaunch({
    required this.request,
    required this.events,
    required this.cancel,
  });

  final InteropRequest request;

  /// Response events in arrival order, filtered by the transport for protocol,
  /// session and sequence. Completes normally after a terminal event.
  final Stream<InteropEvent> events;

  /// Asks the receiver to stop. Safe to call after the stream closed.
  final Future<void> Function() cancel;
}

/// What the Dart side needs from the platform.
abstract interface class InteropTransport {
  /// Whether cross-app invocation exists on this platform at all.
  bool get isSupported;

  /// Asks [target] to answer the handshake. Never throws for a missing app.
  Future<InteropProbe> probe(InteropTarget target);

  /// Starts [request] on [target]. Throws [InteropException] with
  /// `app_missing` when the platform cannot start the ability.
  Future<InteropLaunch> start(InteropTarget target, InteropRequest request);
}

/// Channel-backed transport used on OHOS.
class MethodChannelInteropTransport implements InteropTransport {
  const MethodChannelInteropTransport();

  static const MethodChannel methods = MethodChannel('qfli_interop/bridge');
  static const EventChannel events = EventChannel('qfli_interop/bridge/events');

  static const Set<TargetPlatform> _supported = <TargetPlatform>{
    TargetPlatform.ohos,
  };

  @override
  bool get isSupported {
    if (_supported.contains(defaultTargetPlatform)) return true;
    // HarmonyOS reports as ohos once the engine is patched; a manual override
    // keeps the channel reachable in a debug build on an older engine.
    return Platform.environment['QFLI_INTEROP'] == '1';
  }

  @override
  Future<InteropProbe> probe(InteropTarget target) async {
    if (!isSupported) {
      return const InteropProbe.missing('当前平台不支持跨应用调用。');
    }
    try {
      final raw = await methods.invokeMapMethod<String, Object?>('probe', {
        'bundleName': target.bundleName,
        'abilityName': target.abilityName,
        'language': target.language,
        'protocol': kInteropProtocol,
      });
      if (raw == null) {
        return const InteropProbe.missing('对方没有回应能力探测。');
      }
      final available = raw['available'] == true;
      if (!available) {
        return InteropProbe.missing('${raw['diagnostic'] ?? '对方应用未安装或未响应。'}');
      }
      final languages = <String>{};
      final rawLanguages = raw['languages'];
      if (rawLanguages is List) {
        for (final item in rawLanguages) {
          if (item is String) languages.add(item);
        }
      }
      return InteropProbe(
        available: true,
        protocol: raw['protocol'] as String?,
        languages: languages,
      );
    } on MissingPluginException {
      return const InteropProbe.missing('跨应用通道未注册。');
    } on PlatformException catch (error) {
      return InteropProbe.missing(error.message ?? error.code);
    }
  }

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    if (!isSupported) {
      throw const InteropException(
        InteropErrorCode.unsupportedLanguage,
        '当前平台不支持跨应用调用。',
      );
    }
    // Build the launch parameters first: validation throws here, before any
    // ability is started, so a malformed request never reaches another app.
    final parameters = request.toLaunchParameters();
    final stream = events.receiveBroadcastStream().map(
      (raw) => InteropEvent.fromLaunchParameters(
        Map<String, Object?>.from(raw as Map),
      ),
    );
    try {
      await methods.invokeMethod<void>('start', {
        'bundleName': target.bundleName,
        'abilityName': target.abilityName,
        'parameters': parameters,
      });
    } on MissingPluginException {
      throw const InteropException(
        InteropErrorCode.transportFailure,
        '跨应用通道未注册。',
      );
    } on PlatformException catch (error) {
      if (error.code == 'app_missing') {
        throw InteropException(
          InteropErrorCode.appMissing,
          error.message ?? InteropTargets.installHint(target.language),
        );
      }
      throw InteropException(
        InteropErrorCode.transportFailure,
        error.message ?? '无法启动 ${target.productName}。',
      );
    }
    final sequencer = InteropEventSequencer(request.sessionId);
    final controller = StreamController<InteropEvent>();
    final subscription = stream.listen(
      (event) {
        final accepted = sequencer.accept(event);
        if (accepted != null) controller.add(accepted);
        if (sequencer.finished) controller.close();
      },
      onError: (Object error) {
        if (error is InteropException) {
          controller.addError(error);
        } else {
          controller.addError(
            InteropException(InteropErrorCode.transportFailure, '$error'),
          );
        }
        controller.close();
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: true,
    );
    var cancelled = false;
    return InteropLaunch(
      request: request,
      events: controller.stream,
      cancel: () async {
        if (cancelled) return;
        cancelled = true;
        try {
          await methods.invokeMethod<void>('cancel', {
            'sessionId': request.sessionId,
          });
        } on MissingPluginException {
          // The bridge is gone; the receiver's own timeout still applies.
        } on PlatformException {
          // A failed cancel must not mask the run's real outcome.
        }
        await subscription.cancel();
        if (!controller.isClosed) await controller.close();
      },
    );
  }
}

/// Transport for platforms where no bridge exists. It refuses loudly instead
/// of pretending a run happened.
class UnavailableInteropTransport implements InteropTransport {
  const UnavailableInteropTransport({this.reason = '当前平台不支持跨应用调用。'});

  final String reason;

  @override
  bool get isSupported => false;

  @override
  Future<InteropProbe> probe(InteropTarget target) async =>
      InteropProbe.missing(reason);

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async => throw InteropException(InteropErrorCode.appMissing, reason);
}
