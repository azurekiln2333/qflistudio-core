// One open Herdr pane view.
//
// The handle is the only object the Agents UI holds. It owns the raw terminal
// (attach PTY or snapshot fallback) and translates the contract verbs onto herdr
// commands. It never approves anything: Herdr has no approval API, so an agent
// waiting on a dialog is answered in the pane itself and the session shows up as
// `blocked`.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../harness_host.dart';
import 'herdr_cli.dart';
import 'herdr_models.dart';
import 'herdr_terminal.dart';

class HerdrSessionHandle implements HarnessSessionHandle {
  HerdrSessionHandle({
    required HerdrCli cli,
    required HerdrAgentInfo agent,
    required HerdrTerminal terminal,
    required Future<void> Function() onChanged,
    required Future<void> Function(HerdrSessionHandle handle) onDetached,
    this.hostId = 'herdr',
  }) : _cli = cli,
       _agent = agent,
       _terminal = terminal,
       _onChanged = onChanged,
       _onDetached = onDetached,
       _status = ValueNotifier<HarnessSessionStatus>(
         harnessStatusFor(agent.status),
       );

  final HerdrCli _cli;
  final HerdrTerminal _terminal;
  final Future<void> Function() _onChanged;
  final Future<void> Function(HerdrSessionHandle handle) _onDetached;
  final ValueNotifier<HarnessSessionStatus> _status;

  /// Host id stamped into [HarnessSessionInfo].
  final String hostId;

  HerdrAgentInfo _agent;
  HarnessSessionInfo? _info;
  bool _detached = false;
  bool _stopped = false;
  bool _statusDisposed = false;

  HerdrAgentInfo get agent => _agent;

  /// Whether this handle is finished (stopped or released). [HerdrHost] drops
  /// such a handle instead of handing a dead terminal to the next caller.
  bool get isEnded => _stopped || _detached;

  @override
  HarnessSessionInfo get info => _info ??= _agent.toSessionInfo(hostId: hostId);

  @override
  ValueListenable<HarnessSessionStatus> get status => _status;

  /// Herdr has no structured transcript; the terminal is the transcript.
  @override
  Stream<TranscriptEvent>? get transcript => null;

  @override
  HarnessTerminalChannel? get terminal =>
      (_stopped || _detached) ? null : _terminal;

  /// Applies a fresher row from `herdr agent list`.
  void update(HerdrAgentInfo agent) {
    _agent = agent;
    _info = agent.toSessionInfo(hostId: hostId);
    if (!_statusDisposed) _status.value = harnessStatusFor(agent.status);
  }

  /// Marks the pane as gone (closed outside Studio).
  void markExited() {
    if (!_statusDisposed) _status.value = HarnessSessionStatus.exited;
  }

  @override
  Future<void> sendPrompt(String text) async {
    if (text.trim().isEmpty) return;
    // A rejected submission (blocked agent) is reported, never retried: Herdr
    // may already have written part of the input.
    await _cli.prompt(_agent.target, text);
    unawaited(_onChanged());
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    // Approvals are not representable here. Answering with keys would guess
    // which dialog is on screen, which is exactly how a wrong choice gets
    // applied silently.
    throw UnsupportedError('Herdr 会话没有结构化审批，请在终端中直接回答。');
  }

  /// Releases the view only: the pane and its agent keep running.
  @override
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    await _terminal.close();
    await _onDetached(this);
  }

  /// Ends the session by closing its pane. Callers confirm first.
  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _terminal.close();
    await _cli.closePane(_agent.paneId);
    if (!_statusDisposed) _status.value = HarnessSessionStatus.exited;
    unawaited(_onChanged());
  }

  void dispose() {
    if (!_detached) {
      _detached = true;
      unawaited(_terminal.close());
    }
    _statusDisposed = true;
    _status.dispose();
  }
}
