// Mapping from the remote-control wire types onto the harness vocabulary.
//
// Pure functions only: these are the rules a reviewer can check without a
// socket, and the tests assert them directly. Everything here is read-only
// interpretation — no wire field is renamed and no request is invented.

import '../../remote_control/models/herdr.dart' as herdr;
import '../../remote_control/models/protocol.dart' as protocol;
import '../harness_host.dart';

/// Remote session status → harness status.
///
/// `error` is deliberately `unknown`: the session still exists and can accept
/// another prompt, so `exited` would be false, while `idle` would hide a failure
/// the user may need to see.
HarnessSessionStatus remoteSessionStatus(protocol.SessionStatus status) {
  switch (status) {
    case protocol.SessionStatus.starting:
      return HarnessSessionStatus.working;
    case protocol.SessionStatus.running:
      return HarnessSessionStatus.working;
    case protocol.SessionStatus.waiting:
      return HarnessSessionStatus.blocked;
    case protocol.SessionStatus.idle:
      return HarnessSessionStatus.idle;
    case protocol.SessionStatus.error:
      return HarnessSessionStatus.unknown;
    case protocol.SessionStatus.closed:
      return HarnessSessionStatus.exited;
  }
}

/// Herdr agent status → harness status, shared with the local host so both
/// paths colour a pane the same way.
HarnessSessionStatus remoteHerdrStatus(herdr.HerdrAgentStatus status) {
  switch (status) {
    case herdr.HerdrAgentStatus.idle:
      return HarnessSessionStatus.idle;
    case herdr.HerdrAgentStatus.working:
      return HarnessSessionStatus.working;
    case herdr.HerdrAgentStatus.blocked:
      return HarnessSessionStatus.blocked;
    case herdr.HerdrAgentStatus.done:
      return HarnessSessionStatus.done;
    case herdr.HerdrAgentStatus.unknown:
      return HarnessSessionStatus.unknown;
  }
}

/// Codex thread status is a free-form desktop string.
HarnessSessionStatus remoteCodexStatus(String status) {
  switch (status.toLowerCase()) {
    case 'active':
    case 'running':
    case 'working':
    case 'inprogress':
    case 'in_progress':
      return HarnessSessionStatus.working;
    case 'idle':
    case 'waiting':
    case 'ready':
      return HarnessSessionStatus.idle;
    case 'done':
    case 'complete':
    case 'completed':
    case 'finished':
      return HarnessSessionStatus.done;
    case 'blocked':
    case 'needsattention':
    case 'needs_attention':
    case 'approval':
      return HarnessSessionStatus.blocked;
    default:
      return HarnessSessionStatus.unknown;
  }
}

/// One remote Claude/terminal session as a hub row.
///
/// The id is prefixed so a session and a Codex thread with the same uuid can
/// never collide inside one host, and so `open()` can route on the prefix alone.
HarnessSessionInfo remoteSessionInfo({
  required String hostId,
  required protocol.SessionInfo session,
}) {
  final terminal = session.isTerminal;
  return HarnessSessionInfo(
    id: 'session:${session.id}',
    hostId: hostId,
    providerId: terminal ? 'shell' : 'claude',
    title: session.title.isEmpty
        ? (terminal ? '终端' : 'Claude Code')
        : session.title,
    status: remoteSessionStatus(session.status),
    capabilities: terminal
        ? const <HarnessCapability>{
            HarnessCapability.terminal,
            HarnessCapability.prompt,
            HarnessCapability.stop,
          }
        : const <HarnessCapability>{
            HarnessCapability.transcript,
            HarnessCapability.prompt,
            HarnessCapability.approve,
            HarnessCapability.stop,
          },
    cwd: session.cwd.isEmpty ? null : session.cwd,
    updatedAt: session.updatedAt,
    sourceRef: session.id,
  );
}

/// One Herdr pane on the paired computer.
HarnessSessionInfo remoteHerdrSessionInfo({
  required String hostId,
  required herdr.HerdrAgent agent,
}) => HarnessSessionInfo(
  id: 'herdr:${agent.paneId}',
  hostId: hostId,
  providerId: agent.agentKind.isEmpty ? 'herdr' : agent.agentKind,
  title: agent.terminalTitle.isNotEmpty
      ? agent.terminalTitle
      : (agent.name?.isNotEmpty == true ? agent.name! : agent.displayName),
  status: remoteHerdrStatus(agent.status),
  capabilities: const <HarnessCapability>{
    HarnessCapability.terminal,
    HarnessCapability.prompt,
    HarnessCapability.stop,
  },
  cwd: agent.cwd.isEmpty ? null : agent.cwd,
  sourceRef: agent.paneId,
);

/// One Codex thread from the paired computer's catalog.
HarnessSessionInfo remoteCodexSessionInfo({
  required String hostId,
  required protocol.CodexThread thread,
}) => HarnessSessionInfo(
  id: 'codex:${thread.id}',
  hostId: hostId,
  providerId: 'codex',
  title: thread.title.isEmpty ? 'Codex' : thread.title,
  status: remoteCodexStatus(thread.status),
  capabilities: const <HarnessCapability>{
    HarnessCapability.transcript,
    HarnessCapability.prompt,
    HarnessCapability.approve,
  },
  cwd: thread.cwd.isEmpty ? null : thread.cwd,
  updatedAt: thread.updatedAt,
  sourceRef: thread.id,
);

/// One stored session event as a transcript entry, or null when the event is
/// not conversation (terminal bytes belong to the terminal channel).
TranscriptEvent? transcriptFromSessionEvent(
  protocol.SessionEvent event,
  String sessionId,
) {
  final id = '$sessionId:${event.seq}';
  final at = event.ts;
  switch (event) {
    case protocol.UserEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.user,
        text: event.text,
        at: at,
      );
    case protocol.AssistantEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.assistant,
        text: event.text,
        at: at,
      );
    case protocol.ThinkingEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.assistant,
        text: event.text,
        at: at,
      );
    case protocol.ToolUseEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.tool,
        text: event.summary.isEmpty ? event.name : event.summary,
        at: at,
      );
    case protocol.ToolResultEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.tool,
        text: event.content,
        at: at,
      );
    case protocol.PermissionRequestEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.tool,
        text: event.title.isEmpty
            ? (event.description ?? event.toolName)
            : event.title,
        at: at,
        requestId: event.requestId,
        options: _permissionOptions(event),
      );
    case protocol.PermissionResolvedEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.system,
        text: '已处理权限请求：${event.decision}',
        at: at,
      );
    case protocol.ResultEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.system,
        text: event.text,
        at: at,
      );
    case protocol.SystemEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.system,
        text: event.text,
        at: at,
      );
    case protocol.ErrorEvent():
      return TranscriptEvent(
        id: id,
        role: TranscriptRole.system,
        text: event.text,
        at: at,
      );
    case protocol.TerminalOutputEvent():
      return null;
    case protocol.UnknownEvent():
      return null;
  }
}

/// Options a reply can carry for one permission card.
///
/// A question only accepts its listed labels; a plain permission request accepts
/// the three wire decisions. Approval is never implied — the caller has to send
/// an explicit [HarnessReply].
List<String> _permissionOptions(protocol.PermissionRequestEvent event) {
  final questions = event.questions;
  if (questions != null && questions.isNotEmpty) {
    return <String>[
      for (final question in questions)
        for (final option in question.options) option.label,
    ];
  }
  return <String>['allow', if (event.canAlwaysAllow) 'allow_always', 'deny'];
}

/// One Codex transcript item as a harness transcript entry.
TranscriptEvent codexItemTranscript(
  protocol.CodexTurn turn,
  protocol.CodexItem item, {
  required String threadId,
}) {
  final kind = item.kind.toLowerCase();
  final role = switch (kind) {
    'user' || 'usermessage' => TranscriptRole.user,
    'assistant' || 'agentmessage' || 'message' => TranscriptRole.assistant,
    'reasoning' || 'thinking' => TranscriptRole.assistant,
    'tool' || 'toolcall' || 'tooluse' || 'command' => TranscriptRole.tool,
    _ => TranscriptRole.system,
  };
  return TranscriptEvent(
    id: '$threadId:${turn.id}:${item.id}',
    role: role,
    text: item.text,
  );
}

/// One pending Codex approval as a transcript entry that can be replied to.
TranscriptEvent codexPendingTranscript(
  protocol.CodexPendingRequest request, {
  required String threadId,
}) {
  final options = <String>[
    for (final question in request.questions)
      for (final option in question.options) option.label,
  ];
  return TranscriptEvent(
    id: '$threadId:request:${request.requestId}',
    role: TranscriptRole.tool,
    text: request.title.isEmpty
        ? (request.description ?? request.kind)
        : request.title,
    requestId: request.requestId,
    options: options.isEmpty ? const <String>['accept', 'deny'] : options,
  );
}
