// Open handles for the paired computer.
//
// Three kinds share one contract: a Claude/terminal session, a Herdr pane, and a
// Codex thread. They differ only in which remote controller answers the verb:
//
//   * Claude/terminal → RemoteController.send / respondPermission /
//     terminalInput / closeSession
//   * Herdr pane      → HerdrController.sendText / sendKeys / prompt, pane_close
//   * Codex thread    → RemoteController.codexSend / codexRespond
//
// Two invariants hold in all three:
//   * `detach()` releases the view. It never sends `session_close` or closes a
//     pane, so the session keeps running on the desktop.
//   * `reply()` is the only path that sends an approval, and an unknown decision
//     is treated as a refusal — never as consent.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../remote_control/models/herdr.dart' as herdr;
import '../../remote_control/models/protocol.dart' as protocol;
import '../../remote_control/state/session_view.dart';
import '../harness_host.dart';
import '../herdr/herdr_terminal.dart';
import 'remote_mapping.dart';
import 'remote_ports.dart';
import 'remote_terminal.dart';

/// A Claude or shell session on the paired computer.
class RemoteSessionHandle implements HarnessSessionHandle {
  RemoteSessionHandle({
    required RemoteSessionPort port,
    required protocol.SessionInfo session,
    required String hostId,
    required Future<void> Function(RemoteSessionHandle handle) onDetached,
  }) : _port = port,
       _session = session,
       _hostId = hostId,
       _onDetached = onDetached,
       _owner = Object() {
    _view = port.view(session);
    _status = RemoteSessionStatusNotifier(view: _view, initial: session.status);
    if (session.isTerminal) {
      _terminal = RemoteTerminalChannel(
        view: _view,
        port: port,
        sessionId: session.id,
      );
    } else {
      _transcript = RemoteTranscriptFeed(
        view: _view,
        port: port,
        sessionId: session.id,
        owner: _owner,
      );
    }
  }

  final RemoteSessionPort _port;
  final protocol.SessionInfo _session;
  final String _hostId;
  final Future<void> Function(RemoteSessionHandle handle) _onDetached;
  final Object _owner;

  late final SessionView _view;
  late final RemoteSessionStatusNotifier _status;
  RemoteTranscriptFeed? _transcript;
  RemoteTerminalChannel? _terminal;
  bool _detached = false;
  bool _stopped = false;

  @override
  HarnessSessionInfo get info =>
      remoteSessionInfo(hostId: _hostId, session: _view.info);

  @override
  ValueListenable<HarnessSessionStatus> get status => _status;

  @override
  Stream<TranscriptEvent>? get transcript => _transcript?.stream;

  /// Null once the view is released or the session ended, matching
  /// [HerdrSessionHandle]: the channel is closed, so handing it out would look
  /// like a live terminal that drops every keystroke.
  @override
  HarnessTerminalChannel? get terminal =>
      (_stopped || _detached) ? null : _terminal;

  /// Whether this handle can no longer be reused. The host drops such a handle
  /// so reopening the same id builds a live one instead of returning a corpse.
  bool get isEnded => _stopped || _detached;

  @override
  Future<void> sendPrompt(String text) async {
    if (text.trim().isEmpty) return;
    if (_session.isTerminal) {
      // A shell has no prompt verb: type the line and press Enter.
      await _port.terminalInput(_session.id, '${text.trim()}\r');
      return;
    }
    await _port.send(_session.id, text);
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    final request = _pendingRequest(reply.requestId);
    if (request == null) {
      throw StateError('该权限请求已失效或已被处理');
    }
    if (request.isQuestion) {
      final answers = <String, String>{};
      final chosen = reply.choice.trim();
      for (final question in request.questions!) {
        final matches = question.options.any(
          (option) => option.label == chosen,
        );
        final answer = matches ? chosen : (reply.text?.trim() ?? '');
        if (answer.isNotEmpty) answers[question.question] = answer;
      }
      if (answers.isEmpty) {
        throw StateError('请先填写问题答案');
      }
      await _port.respondPermission(
        _session.id,
        reply.requestId,
        'allow',
        answers: answers,
      );
      return;
    }
    const decisions = <String>{'allow', 'allow_always', 'deny'};
    // Anything unrecognised is a refusal: failing closed is the only safe
    // default for an approval.
    final decision = decisions.contains(reply.choice) ? reply.choice : 'deny';
    await _port.respondPermission(
      _session.id,
      reply.requestId,
      decision,
      message: reply.text,
    );
  }

  protocol.PermissionRequestEvent? _pendingRequest(String requestId) {
    for (final event in _view.events.reversed) {
      if (event is protocol.PermissionRequestEvent &&
          event.requestId == requestId &&
          _view.resolutionFor(requestId) == null) {
        return event;
      }
    }
    return null;
  }

  /// Releases the view only. The desktop session keeps running.
  @override
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    await _transcript?.close();
    await _terminal?.close();
    _port.unsubscribe(_session.id, owner: _owner);
    await _onDetached(this);
  }

  /// Ends the desktop session. Callers confirm first.
  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _transcript?.close();
    await _terminal?.close();
    await _port.closeSession(_session.id);
    _status.value = HarnessSessionStatus.exited;
  }

  void dispose() {
    if (!_detached) {
      _detached = true;
      unawaited(_transcript?.close());
      unawaited(_terminal?.close());
      _port.unsubscribe(_session.id, owner: _owner);
    }
    _status.dispose();
  }
}

/// A Herdr pane on the paired computer.
class RemoteHerdrHandle implements HarnessSessionHandle {
  RemoteHerdrHandle({
    required RemoteHerdrPort herdrPort,
    required herdr.HerdrAgent agent,
    required String hostId,
    required Future<void> Function(RemoteHerdrHandle handle) onDetached,
  }) : _herdr = herdrPort,
       _agent = agent,
       _hostId = hostId,
       _onDetached = onDetached,
       _status = ValueNotifier<HarnessSessionStatus>(
         remoteHerdrStatus(agent.status),
       ) {
    _terminal = HerdrSnapshotTerminal(
      // Read the pane instead of replaying the push cache: the harness host owns
      // no `HerdrPaneLease`, so it must not compete with the Remote Computer page
      // for the one live subscription. A push, when one arrives, only makes the
      // next repaint immediate.
      readPane: () async => (await _herdr.read(paneId)).text,
      sendText: (text) => _herdr.sendText(paneId, text),
      sendKeys: (keys) => _herdr.sendKeys(paneId, keys),
      changes: herdrPort.changes,
    )..start();
  }

  final RemoteHerdrPort _herdr;
  final String _hostId;
  final Future<void> Function(RemoteHerdrHandle handle) _onDetached;
  final ValueNotifier<HarnessSessionStatus> _status;
  HerdrSnapshotTerminal? _terminal;

  herdr.HerdrAgent _agent;
  bool _detached = false;
  bool _stopped = false;
  bool _statusDisposed = false;

  /// See [RemoteSessionHandle.isEnded].
  bool get isEnded => _stopped || _detached;

  String get paneId => _agent.paneId;

  /// Applies a fresher row from the desktop's Herdr push.
  void update(herdr.HerdrAgent agent) {
    _agent = agent;
    if (!_statusDisposed) _status.value = remoteHerdrStatus(agent.status);
  }

  /// The pane vanished from the desktop's list (closed elsewhere).
  void markExited() {
    if (!_statusDisposed) _status.value = HarnessSessionStatus.exited;
  }

  @override
  HarnessSessionInfo get info =>
      remoteHerdrSessionInfo(hostId: _hostId, agent: _agent);

  @override
  ValueListenable<HarnessSessionStatus> get status => _status;

  /// Herdr has no structured transcript on the wire either.
  @override
  Stream<TranscriptEvent>? get transcript => null;

  @override
  HarnessTerminalChannel? get terminal =>
      (_stopped || _detached) ? null : _terminal;

  @override
  Future<void> sendPrompt(String text) async {
    if (text.trim().isEmpty) return;
    await _herdr.prompt(_agent.paneId, text);
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    throw UnsupportedError('Herdr 面板没有结构化审批，请在终端中直接回答。');
  }

  @override
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    await _terminal?.close();
    _terminal = null;
    await _onDetached(this);
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _terminal?.close();
    _terminal = null;
    await _herdr.closePane(_agent.paneId);
    if (!_statusDisposed) _status.value = HarnessSessionStatus.exited;
  }

  void dispose() {
    if (!_detached) {
      _detached = true;
      unawaited(_terminal?.close());
      _terminal = null;
    }
    _statusDisposed = true;
    _status.dispose();
  }
}

/// A Codex thread on the paired computer.
class RemoteCodexThreadHandle implements HarnessSessionHandle {
  RemoteCodexThreadHandle({
    required RemoteCodexPort codex,
    required RemoteCodexThreadView view,
    required String hostId,
    required Future<void> Function(RemoteCodexThreadHandle handle) onDetached,
  }) : _codex = codex,
       _view = view,
       _hostId = hostId,
       _onDetached = onDetached {
    _status = ValueNotifier<HarnessSessionStatus>(
      remoteCodexStatus(view.thread.status),
    );
    _feed = _CodexTranscriptFeed(view: view);
    // The thread is pushed, not polled: without this listener the row would keep
    // showing the status the thread had when it was opened.
    view.changes.addListener(_syncStatus);
    unawaited(_view.load(refresh: true));
  }

  final RemoteCodexPort _codex;
  final RemoteCodexThreadView _view;
  final String _hostId;
  final Future<void> Function(RemoteCodexThreadHandle handle) _onDetached;
  late final ValueNotifier<HarnessSessionStatus> _status;
  late final _CodexTranscriptFeed _feed;
  bool _detached = false;
  bool _stopped = false;
  bool _statusDisposed = false;

  /// See [RemoteSessionHandle.isEnded].
  bool get isEnded => _stopped || _detached;

  void _syncStatus() {
    if (_statusDisposed) return;
    final next = remoteCodexStatus(_view.thread.status);
    if (next != _status.value) _status.value = next;
  }

  @override
  HarnessSessionInfo get info =>
      remoteCodexSessionInfo(hostId: _hostId, thread: _view.thread);

  @override
  ValueListenable<HarnessSessionStatus> get status => _status;

  @override
  Stream<TranscriptEvent>? get transcript => _feed.stream;

  @override
  HarnessTerminalChannel? get terminal => null;

  @override
  Future<void> sendPrompt(String text) async {
    if (text.trim().isEmpty) return;
    final thread = _view.thread;
    await _codex.send(thread.id, text, turnId: thread.activeTurnId);
    await _view.load(refresh: true);
  }

  @override
  Future<void> reply(HarnessReply reply) async {
    protocol.CodexPendingRequest? pending;
    for (final request in _view.pendingRequests) {
      if (request.requestId == reply.requestId) {
        pending = request;
        break;
      }
    }
    if (pending == null) {
      throw StateError('该审批已失效或已被处理');
    }
    final chosen = reply.choice.trim();
    final isAccept =
        chosen == 'accept' || chosen == 'allow' || chosen == 'allow_always';
    final answers = <String, List<String>>{};
    if (isAccept && pending.questions.isNotEmpty) {
      for (final question in pending.questions) {
        final matches = question.options.any(
          (option) => option.label == chosen,
        );
        final answer = matches ? chosen : (reply.text?.trim() ?? '');
        if (answer.isNotEmpty) answers[question.id] = <String>[answer];
      }
    }
    await _codex.respond(
      _view.thread.id,
      reply.requestId,
      isAccept ? 'accept' : 'deny',
      answers: answers.isEmpty ? null : answers,
    );
    await _view.load(refresh: true);
  }

  @override
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    _view.changes.removeListener(_syncStatus);
    await _feed.close();
    await _onDetached(this);
  }

  /// A Codex thread is a conversation, not a process: interrupting the active
  /// turn is the closest safe equivalent of "stop".
  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final thread = _view.thread;
    final turnId = thread.activeTurnId;
    if (turnId != null) {
      await _codex.interrupt(thread.id, turnId);
    }
    await detach();
  }

  Future<void> dispose() async {
    if (!_detached) {
      _detached = true;
      await _feed.close();
    }
    _view.changes.removeListener(_syncStatus);
    await _view.dispose();
    _statusDisposed = true;
    _status.dispose();
  }
}

/// Emits the Codex transcript as harness entries, including pending approvals.
class _CodexTranscriptFeed {
  _CodexTranscriptFeed({required RemoteCodexThreadView view}) : _view = view {
    _controller = StreamController<TranscriptEvent>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  final RemoteCodexThreadView _view;
  late final StreamController<TranscriptEvent> _controller;
  final Set<String> _emitted = <String>{};
  bool _listening = false;
  bool _closed = false;

  Stream<TranscriptEvent> get stream => _controller.stream;

  void _start() {
    if (_closed || _listening) return;
    _listening = true;
    _view.changes.addListener(_pump);
    _pump();
  }

  void _stop() {
    if (!_listening) return;
    _listening = false;
    _view.changes.removeListener(_pump);
  }

  void _pump() {
    if (_closed) return;
    final thread = _view.thread;
    for (final turn in _view.turns) {
      for (final item in turn.items) {
        final entry = codexItemTranscript(turn, item, threadId: thread.id);
        if (_emitted.add(entry.id)) _controller.add(entry);
      }
    }
    for (final request in _view.pendingRequests) {
      final entry = codexPendingTranscript(request, threadId: thread.id);
      if (_emitted.add(entry.id)) _controller.add(entry);
    }
    final error = _view.error;
    if (error != null && error.isNotEmpty) {
      final entry = TranscriptEvent(
        id: '${thread.id}:error:$error',
        role: TranscriptRole.system,
        text: error,
      );
      if (_emitted.add(entry.id)) _controller.add(entry);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stop();
    await _controller.close();
  }
}
