// Harness Hub contract. Every host (this computer, a paired computer,
// Studio's built-in agent) implements these types; the Agents UI depends
// only on this file. Changes go through the harness-hub task root.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum HarnessHostKind { local, remote, studio }

enum HarnessHostState { offline, connecting, online, unsupported }

enum HarnessSessionStatus { working, idle, done, blocked, exited, unknown }

enum HarnessCapability { transcript, terminal, prompt, approve, stop }

/// A harness that a host can launch (claude, codex, pi, shell, ...).
@immutable
class HarnessProviderInfo {
  const HarnessProviderInfo({
    required this.id,
    required this.label,
    required this.available,
    this.executable,
    this.builtIn = true,
  });

  final String id;
  final String label;
  final bool available;
  final String? executable;
  final bool builtIn;
}

@immutable
class HarnessSessionInfo {
  const HarnessSessionInfo({
    required this.id,
    required this.hostId,
    required this.providerId,
    required this.title,
    required this.status,
    required this.capabilities,
    this.cwd,
    this.updatedAt,
    this.sourceRef,
  });

  final String id;
  final String hostId;
  final String providerId;
  final String title;
  final HarnessSessionStatus status;
  final Set<HarnessCapability> capabilities;
  final String? cwd;
  final DateTime? updatedAt;

  /// Host-private reference: Herdr pane id, log file path, PTY id, ...
  final String? sourceRef;
}

@immutable
class HarnessLaunchRequest {
  const HarnessLaunchRequest({
    required this.providerId,
    required this.cwd,
    this.args = const [],
    this.title,
  });

  final String providerId;
  final String cwd;
  final List<String> args;
  final String? title;
}

enum TranscriptRole { user, assistant, tool, system }

/// One structured transcript entry. [requestId] is set when the entry asks
/// the user for an approval or an answer.
@immutable
class TranscriptEvent {
  const TranscriptEvent({
    required this.id,
    required this.role,
    required this.text,
    this.at,
    this.requestId,
    this.options = const [],
  });

  final String id;
  final TranscriptRole role;
  final String text;
  final DateTime? at;
  final String? requestId;
  final List<String> options;
}

@immutable
class HarnessReply {
  const HarnessReply({
    required this.requestId,
    required this.choice,
    this.text,
  });

  final String requestId;
  final String choice;
  final String? text;
}

/// Raw PTY channel. Bytes are terminal output, never line-split.
abstract class HarnessTerminalChannel {
  Stream<Uint8List> get output;
  void write(Uint8List data);
  void resize(int columns, int rows);
}

abstract class HarnessSessionHandle {
  HarnessSessionInfo get info;
  ValueListenable<HarnessSessionStatus> get status;

  /// Null when the session has no structured transcript.
  Stream<TranscriptEvent>? get transcript;

  /// Null when the session has no raw terminal.
  HarnessTerminalChannel? get terminal;

  Future<void> sendPrompt(String text);
  Future<void> reply(HarnessReply reply);

  /// Releases this view only. The session keeps running.
  Future<void> detach();

  /// Ends the session. Callers must get explicit user confirmation first.
  Future<void> stop();
}

abstract class HarnessHost {
  String get id;
  String get label;
  HarnessHostKind get kind;
  ValueListenable<HarnessHostState> get state;

  Stream<List<HarnessSessionInfo>> watchSessions();
  Future<List<HarnessProviderInfo>> providers();
  Future<HarnessSessionHandle> open(String sessionId);
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request);
  Future<void> dispose();
}

/// The operating system of the device a host runs on.
///
/// `unknown` means the host could not tell. The details view prints
/// `unknown` instead of guessing.
enum HarnessDeviceOs { android, ios, ohos, macos, windows, linux, unknown }

/// Where a host runs: its device name, system and system version.
///
/// Field names match the wire fields `hostName`, `os` and `osVersion`, so a
/// host that forwards a frame never renames a field. Every field may be
/// missing; the details view prints `unknown` for a missing one.
@immutable
class HarnessDeviceInfo {
  const HarnessDeviceInfo({
    this.hostName,
    this.os = HarnessDeviceOs.unknown,
    this.osVersion,
  });

  /// Display name of the device: the user's device name on a phone, the
  /// hostname on a computer.
  final String? hostName;

  /// Operating system. [HarnessDeviceOs.unknown] when the host cannot tell.
  final HarnessDeviceOs os;

  /// Human-readable version, kept verbatim. Never parsed or rewritten.
  final String? osVersion;

  /// Whether every field is absent. An empty value carries no information.
  bool get isEmpty =>
      (hostName?.trim().isEmpty ?? true) &&
      os == HarnessDeviceOs.unknown &&
      (osVersion?.trim().isEmpty ?? true);
}

/// Optional capability: a host that can report its device information.
///
/// [HarnessHost] deliberately gains no required member: four host
/// implementations and every test fake already implement it. A host that can
/// tell its device information implements this interface instead.
abstract class HarnessDeviceHost {
  ValueListenable<HarnessDeviceInfo> get device;
}

/// Device information of [host], or null when it does not report any.
HarnessDeviceInfo? harnessDeviceOf(HarnessHost host) {
  // The two types are unrelated, so Dart does not promote the variable;
  // a pattern binds a non-null copy.
  if (host case final HarnessDeviceHost deviceHost) {
    return deviceHost.device.value;
  }
  return null;
}
