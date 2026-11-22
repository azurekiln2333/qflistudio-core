// Narrow ports over the existing remote-control module.
//
// RemoteHarnessHost must not reach into RemoteController's internals, and it
// must be testable without a socket, a relay or a paired computer. These three
// interfaces are the whole surface the harness layer uses; the `...Adapter`
// classes below delegate to the real controllers and hold no logic of their own.
//
// Deliberately unchanged by this file: the wire protocol, request ids, reconnect
// and replay semantics, and the rule that approvals only ever follow an explicit
// user reply. The adapters forward and nothing else.

import 'package:flutter/foundation.dart';

import '../../remote_control/models/herdr.dart'
    show
        HerdrActionReport,
        HerdrActions,
        HerdrAgent,
        HerdrOutput,
        HerdrReadSource;
import '../../remote_control/models/protocol.dart'
    show
        CodexPage,
        CodexPendingRequest,
        CodexProject,
        CodexThread,
        CodexTranscript,
        CodexTurn,
        SessionInfo;
import '../../remote_control/state/codex_thread_view.dart';
import '../../remote_control/state/herdr_controller.dart';
import '../../remote_control/state/remote_controller.dart';
import '../../remote_control/state/session_view.dart';

/// Everything the harness layer needs from one paired computer's sessions.
abstract interface class RemoteSessionPort {
  /// Fires when the connection, the agent or the session list changes.
  Listenable get changes;

  bool get isOnline;

  ConnectionPhase get phase;

  /// Computer name to show as the host label.
  String get hostLabel;

  /// Stable pairing id; falls back to the relay host when unnamed.
  String get hostId;

  List<SessionInfo> get sessions;

  SessionView view(SessionInfo info);

  Future<void> refreshSessions();

  Future<void> subscribe(String id, {required Object owner});

  void unsubscribe(String id, {required Object owner});

  Future<void> send(String id, String text);

  Future<void> respondPermission(
    String id,
    String requestId,
    String decision, {
    String? message,
    Map<String, String>? answers,
  });

  Future<void> terminalInput(String id, String data);

  Future<void> terminalResize(String id, int cols, int rows);

  Future<void> closeSession(String id);

  Future<SessionInfo> createSession({required String cwd, String? prompt});

  Future<SessionInfo> createTerminal({required String cwd});
}

/// Delegates to the real [RemoteController]; no behaviour is added.
class RemoteControllerSessionAdapter implements RemoteSessionPort {
  RemoteControllerSessionAdapter(this.controller);

  final RemoteController controller;

  @override
  Listenable get changes => controller;

  @override
  bool get isOnline => controller.isOnline;

  @override
  ConnectionPhase get phase => controller.phase;

  @override
  String get hostLabel => controller.agentName;

  @override
  String get hostId {
    final pairing = controller.pairing;
    if (pairing != null && pairing.agentId.isNotEmpty) return pairing.agentId;
    return controller.agent?.host ?? 'remote';
  }

  @override
  List<SessionInfo> get sessions => controller.sessions;

  @override
  SessionView view(SessionInfo info) => controller.view(info);

  @override
  Future<void> refreshSessions() => controller.refreshSessions();

  @override
  Future<void> subscribe(String id, {required Object owner}) =>
      controller.subscribe(id, owner: owner);

  @override
  void unsubscribe(String id, {required Object owner}) =>
      controller.unsubscribe(id, owner: owner);

  @override
  Future<void> send(String id, String text) => controller.send(id, text);

  @override
  Future<void> respondPermission(
    String id,
    String requestId,
    String decision, {
    String? message,
    Map<String, String>? answers,
  }) => controller.respondPermission(
    id,
    requestId,
    decision,
    message: message,
    answers: answers,
  );

  @override
  Future<void> terminalInput(String id, String data) =>
      controller.terminalInput(id, data);

  @override
  Future<void> terminalResize(String id, int cols, int rows) =>
      controller.terminalResize(id, cols, rows);

  @override
  Future<void> closeSession(String id) => controller.closeSession(id);

  @override
  Future<SessionInfo> createSession({required String cwd, String? prompt}) =>
      controller.createSession(cwd: cwd, prompt: prompt);

  @override
  Future<SessionInfo> createTerminal({required String cwd}) =>
      controller.createTerminal(cwd: cwd);
}

/// Herdr panes on the paired computer.
abstract interface class RemoteHerdrPort {
  Listenable get changes;

  bool get canControl;

  List<HerdrAgent> get agents;

  /// Last pushed screen text for [paneId]; empty before the first push.
  String paneText(String paneId);

  Future<void> refresh();

  Future<HerdrOutput> read(String paneId, {HerdrReadSource source, int lines});

  Future<HerdrActionReport> sendText(String paneId, String text);

  Future<HerdrActionReport> sendKeys(String paneId, List<String> keys);

  Future<HerdrActionReport> prompt(String paneId, String text);

  /// Closes a pane (ending the session). Callers confirm first.
  Future<void> closePane(String paneId);
}

/// Delegates to the existing [HerdrController].
class HerdrControllerAdapter implements RemoteHerdrPort {
  HerdrControllerAdapter({required this.controller, required this.remote});

  final HerdrController controller;
  final RemoteController remote;

  @override
  Listenable get changes => controller;

  @override
  bool get canControl => controller.canControl;

  @override
  List<HerdrAgent> get agents => controller.agents;

  @override
  String paneText(String paneId) => controller.paneText(paneId);

  @override
  Future<void> refresh() => controller.refresh();

  @override
  Future<HerdrOutput> read(
    String paneId, {
    HerdrReadSource source = HerdrReadSource.recent,
    int lines = 200,
  }) => controller.read(paneId, source: source, lines: lines);

  @override
  Future<HerdrActionReport> sendText(String paneId, String text) =>
      controller.sendText(paneId, text);

  @override
  Future<HerdrActionReport> sendKeys(String paneId, List<String> keys) =>
      controller.sendKeys(paneId, keys);

  @override
  Future<HerdrActionReport> prompt(String paneId, String text) =>
      controller.prompt(paneId, text);

  @override
  Future<void> closePane(String paneId) async {
    // HerdrActions owns the wire shape; hand-building the map here would go
    // silently wrong the day a field is renamed.
    await remote.herdrAct(HerdrActions.paneClose(paneId));
  }
}

/// The desktop Codex catalog and thread transcript.
abstract interface class RemoteCodexPort {
  bool get available;

  bool get canControl;

  /// First page of the most recent threads, newest first as the desktop ranks
  /// them.
  Future<List<CodexThread>> recentThreads();

  Future<CodexTranscript> read(String threadId, {String? cursor});

  Future<void> send(String threadId, String text, {String? turnId});

  Future<void> respond(
    String threadId,
    String requestId,
    String decision, {
    Map<String, List<String>>? answers,
  });

  Future<void> interrupt(String threadId, String turnId);

  Future<CodexPage<CodexProject>> projects({String? cursor});

  /// Opens one thread transcript. Reuses the module's [CodexThreadView] rather
  /// than re-implementing paging, notices and its polling fallback.
  RemoteCodexThreadView openThread(CodexThread thread);
}

/// One Codex thread as the harness layer sees it.
abstract interface class RemoteCodexThreadView {
  Listenable get changes;

  CodexThread get thread;

  List<CodexTurn> get turns;

  List<CodexPendingRequest> get pendingRequests;

  String? get error;

  bool get loaded;

  bool get canControl;

  bool get canSend;

  Future<void> load({bool refresh});

  Future<void> dispose();
}

/// Adapts the real [CodexThreadView].
class CodexThreadViewAdapter implements RemoteCodexThreadView {
  CodexThreadViewAdapter(this._view);

  final CodexThreadView _view;

  @override
  Listenable get changes => _view;

  @override
  CodexThread get thread => _view.thread;

  @override
  List<CodexTurn> get turns => List<CodexTurn>.unmodifiable(_view.turns);

  @override
  List<CodexPendingRequest> get pendingRequests =>
      List<CodexPendingRequest>.unmodifiable(_view.pendingRequests);

  @override
  String? get error => _view.error;

  @override
  bool get loaded => _view.loaded;

  @override
  bool get canControl => _view.canControl;

  @override
  bool get canSend => _view.canSend;

  @override
  Future<void> load({bool refresh = false}) => _view.load(refresh: refresh);

  @override
  Future<void> dispose() async => _view.dispose();
}

/// Delegates to the existing [RemoteController] Codex calls.
class RemoteControllerCodexAdapter implements RemoteCodexPort {
  RemoteControllerCodexAdapter(this.controller);

  final RemoteController controller;

  @override
  bool get available => controller.agent?.codex?.available == true;

  @override
  bool get canControl => controller.agent?.codex?.canControl == true;

  @override
  Future<List<CodexThread>> recentThreads() async {
    final page = await controller.codexThreads();
    return page.items;
  }

  @override
  Future<CodexTranscript> read(String threadId, {String? cursor}) =>
      controller.codexRead(threadId, cursor: cursor);

  @override
  Future<void> send(String threadId, String text, {String? turnId}) =>
      controller.codexSend(threadId, text, turnId: turnId);

  @override
  Future<void> respond(
    String threadId,
    String requestId,
    String decision, {
    Map<String, List<String>>? answers,
  }) =>
      controller.codexRespond(threadId, requestId, decision, answers: answers);

  @override
  Future<void> interrupt(String threadId, String turnId) =>
      controller.codexInterrupt(threadId, turnId);

  @override
  Future<CodexPage<CodexProject>> projects({String? cursor}) =>
      controller.codexProjects(cursor: cursor);

  @override
  RemoteCodexThreadView openThread(CodexThread thread) =>
      CodexThreadViewAdapter(CodexThreadView(controller, thread));
}
