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
import 'package:path_provider/path_provider.dart';

import 'interop_protocol.dart';
import 'interop_targets.dart';
import 'interop_zip.dart';

/// Result of asking a receiver whether it is installed and capable.
///
/// The platform cannot always answer "installed yes/no": reading another
/// app's bundle record needs a permission Studio may not hold. So the answer
/// keeps three states instead of collapsing them into one bool:
///
///   - [status] `installed` — the receiver answered and can serve the run.
///   - [status] `missing` — the receiver is not installed, or explicitly
///     refused. The user gets an actionable hint.
///   - [status] `unknown` — Studio could not find out. The caller must not
///     claim either way; it offers to try and falls back to the online
///     terminal when the start really fails.
class InteropProbe {
  const InteropProbe({
    required this.status,
    this.protocol,
    this.languages = const <String>{},
    this.diagnostic,
  });

  /// The receiver is installed and answered the handshake.
  const InteropProbe.installed({this.protocol, this.languages = const <String>{}})
    : status = InteropProbeStatus.installed,
      diagnostic = null;

  /// The receiver is not installed. [diagnostic] says what to install.
  const InteropProbe.missing(String this.diagnostic)
    : status = InteropProbeStatus.missing,
      protocol = null,
      languages = const <String>{};

  /// Studio could not determine whether the receiver is installed.
  const InteropProbe.unknown(String this.diagnostic)
    : status = InteropProbeStatus.unknown,
      protocol = null,
      languages = const <String>{};

  final InteropProbeStatus status;

  /// Protocol the receiver answered with, when installed.
  final String? protocol;

  /// Languages the receiver reported through the handshake.
  final Set<String> languages;
  final String? diagnostic;

  /// Whether the run should be offered. Unknown is "try it": the start call
  /// still fails honestly and the caller falls back.
  bool get available => status != InteropProbeStatus.missing;

  /// Whether the answer is a confirmed installation.
  bool get isInstalled => status == InteropProbeStatus.installed;
}

/// The three answers a handshake can give.
enum InteropProbeStatus { installed, missing, unknown }

/// A request that has been handed to the platform and can be cancelled.
class InteropLaunch {
  const InteropLaunch({
    required this.request,
    required this.events,
    required this.cancel,
    this.stop,
  });

  final InteropRequest request;

  /// Response events in arrival order, filtered by the transport for protocol,
  /// session and sequence. Completes normally after a terminal event.
  final Stream<InteropEvent> events;

  /// Asks the receiver to stop. Safe to call after the stream closed.
  ///
  /// A transport that can prove the stop returns a terminal outcome through
  /// [stop] instead. [InteropRunner] prefers [stop] so it does not report a
  /// stop the receiver never confirmed.
  final Future<void> Function() cancel;

  /// Confirmed stop: completes after the receiver's own terminal event.
  ///
  /// Null means this transport cannot confirm a stop, and its [cancel] is
  /// only a request. The background route always supplies this.
  final Future<InteropStop> Function()? stop;
}

/// The receiver's own answer to a stop request.
///
/// [confirmed] is true only when the receiver's terminal event arrived inside
/// the acknowledgement budget. A local timeout, a local failure, or a stop the
/// receiver never answered is a diagnostic, not a cancellation.
class InteropStop {
  const InteropStop({
    required this.exitCode,
    required this.message,
    this.confirmed = true,
  });

  final int exitCode;

  /// The receiver's terminal text, or the reason no answer arrived.
  final String message;
  final bool confirmed;
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
        return const InteropProbe.unknown('对方没有回应能力探测。');
      }
      final diagnostic = raw['diagnostic'] as String?;
      // The bridge answers `available` plus `installed`. A bridge that does not
      // report `installed` at all is an old build, so its answer is unknown.
      final installed = raw['installed'];
      if (installed == false || raw['available'] == false) {
        return InteropProbe.missing(
          diagnostic ?? InteropTargets.installHint(target.language),
        );
      }
      if (installed != true) {
        return InteropProbe.unknown(
          diagnostic ?? '无法确认 ${target.productName} 是否已安装。',
        );
      }
      final languages = <String>{};
      final rawLanguages = raw['languages'];
      if (rawLanguages is List) {
        for (final item in rawLanguages) {
          if (item is String) languages.add(item);
        }
      }
      return InteropProbe.installed(
        protocol: raw['protocol'] as String?,
        languages: languages,
      );
    } on MissingPluginException {
      return const InteropProbe.missing('跨应用通道未注册。');
    } on PlatformException catch (error) {
      // A registered channel answered a PlatformException: the bridge exists
      // and refused this probe. Calling that "missing" would tell the user to
      // install an app that is already answering.
      return InteropProbe.unknown(
        error.message ?? '无法确认配套应用是否可用（${error.code}）。',
      );
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
    // The payload crosses as one zip under a file-URI read grant. Dart writes
    // it into the shared sandbox cache; the bridge only grants the URI.
    parameters['zipPath'] = await writePayloadZip(
      cacheDirectory: (await getTemporaryDirectory()).path,
      sessionId: request.sessionId,
      files: request.files,
    );
    // A frame can arrive with the platform's number type instead of the
    // protocol's string form, so the two integer fields are normalized here
    // before the strict decoder reads them. The bridge publishes `seq` and
    // `exitCode` as strings today, so this only covers an engine that hands
    // them back as numbers; a non-integral value stays a number and is still
    // rejected.
    final stream = events.receiveBroadcastStream().map(
      (raw) => InteropEvent.fromLaunchParameters(
        interopWireMap(Map<String, Object?>.from(raw as Map)),
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

/// Numeric fields the protocol declares as integers.
///
/// Only these two keys are normalized; payload text and nested maps are never
/// rewritten.
const Set<String> _integerWireFields = <String>{'seq', 'exitCode'};

/// Normalizes the platform shape of the protocol's numeric fields.
///
/// The OHOS engine delivers channel numbers as `double`, so an integral `1.0`
/// would stringify as `"1.0"` and be rejected by the strict integer reader in
/// `InteropEvent.fromLaunchParameters`. Only a finite, exactly integral value is
/// converted. A fractional, NaN or infinite value is passed through unchanged
/// so the strict reader still rejects it; this function never invents a valid
/// event and never touches anything but `seq` and `exitCode`.
Map<String, Object?> interopWireMap(Map<String, Object?> raw) {
  final out = <String, Object?>{};
  raw.forEach((key, value) {
    out[key] = _integerWireFields.contains(key) ? _asWireInteger(value) : value;
  });
  return out;
}

Object? _asWireInteger(Object? value) {
  if (value is! double || !value.isFinite) return value;
  if (value != value.roundToDouble()) return value;
  // Beyond 2^53 a `double` no longer names one integer exactly, so it stays a
  // double and the strict reader rejects it.
  if (value.abs() > 9007199254740992) return value;
  return value.toInt();
}
