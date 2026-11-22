// Typed mirror of the `herdr agent list` / `workspace list` JSON that HerdrHost
// reads. Field names are the ones herdr 0.9.x actually prints (snake_case, and
// nullable where the schema says nullable) so a rename on Herdr's side breaks a
// parsing test instead of shipping as an empty label.
//
// Deliberately no `agent_session` here: that object carries the agent's private
// session-log path, and HerdrHost has no business holding it. Log reading
// belongs to the local host's readers.

import 'package:flutter/foundation.dart';

import '../harness_host.dart';

/// Lifecycle as Herdr reports it. `idle` and `done` both accept input.
enum HerdrAgentStatus { idle, working, blocked, done, unknown }

/// Unknown statuses degrade to [HerdrAgentStatus.unknown] so a newer Herdr
/// never makes an older Studio throw.
HerdrAgentStatus parseHerdrAgentStatus(Object? value) {
  for (final status in HerdrAgentStatus.values) {
    if (status.name == value) return status;
  }
  return HerdrAgentStatus.unknown;
}

/// Herdr status → harness status.
///
/// `idle` and `done` are both "ready for input", but they are not the same
/// thing to a user: `done` means the last turn finished and nobody has looked
/// at it yet, while `idle` means the agent is simply waiting. Keeping them
/// apart lets the Agents list show a completion badge.
HarnessSessionStatus harnessStatusFor(HerdrAgentStatus status) {
  switch (status) {
    case HerdrAgentStatus.idle:
      return HarnessSessionStatus.idle;
    case HerdrAgentStatus.working:
      return HarnessSessionStatus.working;
    case HerdrAgentStatus.blocked:
      return HarnessSessionStatus.blocked;
    case HerdrAgentStatus.done:
      return HarnessSessionStatus.done;
    case HerdrAgentStatus.unknown:
      return HarnessSessionStatus.unknown;
  }
}

/// One agent pane as returned by `herdr agent list`.
@immutable
class HerdrAgentInfo {
  const HerdrAgentInfo({
    required this.paneId,
    required this.workspaceId,
    required this.tabId,
    required this.agentKind,
    required this.status,
    required this.focused,
    this.cwd,
    this.name,
    this.title,
    this.interactiveReady,
    this.completionSeq,
    this.stateChangeSeq,
    this.revision,
    this.launchPending = false,
  });

  factory HerdrAgentInfo.fromJson(Map<String, dynamic> json) => HerdrAgentInfo(
    paneId: _str(json['pane_id']) ?? '',
    workspaceId: _str(json['workspace_id']) ?? '',
    tabId: _str(json['tab_id']) ?? '',
    agentKind: _str(json['agent']) ?? _str(json['display_agent']) ?? '',
    status: parseHerdrAgentStatus(json['agent_status']),
    focused: json['focused'] == true,
    cwd: _str(json['cwd']),
    name: _str(json['name']),
    title:
        _str(json['terminal_title_stripped']) ??
        _str(json['terminal_title']) ??
        _str(json['title']),
    interactiveReady: json['interactive_ready'] == true,
    completionSeq: _int(json['completion_seq']),
    stateChangeSeq: _int(json['state_change_seq']),
    revision: _int(json['revision']),
    launchPending: json['launch_pending'] == true,
  );

  final String paneId;
  final String workspaceId;
  final String tabId;

  /// Agent label Herdr detected in the pane (`claude`, `codex`, `pi`, ...).
  final String agentKind;
  final HerdrAgentStatus status;
  final bool focused;
  final String? cwd;

  /// User-assigned pane name; also the preferred prompt target.
  final String? name;

  /// Stripped terminal title, e.g. `执行 A D 盘独立构建 | analysis`.
  final String? title;
  final bool? interactiveReady;
  final int? completionSeq;
  final int? stateChangeSeq;
  final int? revision;
  final bool launchPending;

  /// `agent prompt` / `send-keys` target: the pane name when the user gave one,
  /// otherwise the pane id. A bare kind label is never a legal target.
  String get target => (name != null && name!.isNotEmpty) ? name! : paneId;

  /// Harness provider id used for grouping: the detected agent kind, or the
  /// host's shell when the pane hosts no agent.
  String get providerId => agentKind.isEmpty ? 'shell' : agentKind;

  /// Session title: terminal title, then the pane name, then a readable id.
  String get displayTitle {
    final titleText = title;
    if (titleText != null && titleText.isNotEmpty) return titleText;
    final nameText = name;
    if (nameText != null && nameText.isNotEmpty) return nameText;
    return agentKind.isEmpty ? paneId : '$agentKind · $paneId';
  }

  /// A Herdr pane can be typed into, prompted, and its pane closed. There is no
  /// structured transcript and no approval API: approvals happen in the pane.
  static const Set<HarnessCapability> capabilities = <HarnessCapability>{
    HarnessCapability.terminal,
    HarnessCapability.prompt,
    HarnessCapability.stop,
  };

  HarnessSessionInfo toSessionInfo({required String hostId}) =>
      HarnessSessionInfo(
        id: paneId,
        hostId: hostId,
        providerId: providerId,
        title: displayTitle,
        status: harnessStatusFor(status),
        capabilities: capabilities,
        cwd: cwd,
        sourceRef: paneId,
      );

  HerdrAgentInfo copyWith({HerdrAgentStatus? status}) => HerdrAgentInfo(
    paneId: paneId,
    workspaceId: workspaceId,
    tabId: tabId,
    agentKind: agentKind,
    status: status ?? this.status,
    focused: focused,
    cwd: cwd,
    name: name,
    title: title,
    interactiveReady: interactiveReady,
    completionSeq: completionSeq,
    stateChangeSeq: stateChangeSeq,
    revision: revision,
    launchPending: launchPending,
  );
}

/// One workspace as returned by `herdr workspace list`.
@immutable
class HerdrWorkspaceInfo {
  const HerdrWorkspaceInfo({
    required this.workspaceId,
    required this.label,
    required this.number,
    required this.focused,
    required this.status,
    required this.paneCount,
    required this.tabCount,
  });

  factory HerdrWorkspaceInfo.fromJson(Map<String, dynamic> json) =>
      HerdrWorkspaceInfo(
        workspaceId: _str(json['workspace_id']) ?? '',
        label: _str(json['label']) ?? '',
        number: _int(json['number']) ?? 0,
        focused: json['focused'] == true,
        status: parseHerdrAgentStatus(json['agent_status']),
        paneCount: _int(json['pane_count']) ?? 0,
        tabCount: _int(json['tab_count']) ?? 0,
      );

  final String workspaceId;
  final String label;
  final int number;
  final bool focused;
  final HerdrAgentStatus status;
  final int paneCount;
  final int tabCount;

  /// Workspace label with a stable fallback, for grouping headers.
  String get displayLabel => label.isEmpty ? workspaceId : label;
}

/// Result of `herdr status`: a two-section `key: value` text dump, not JSON.
@immutable
class HerdrServerStatus {
  const HerdrServerStatus({
    this.clientVersion,
    this.clientProtocol,
    this.serverRunning = false,
    this.serverVersion,
    this.socket,
  });

  final String? clientVersion;
  final int? clientProtocol;
  final bool serverRunning;
  final String? serverVersion;
  final String? socket;
}

/// Nullable-safe string field: Herdr prints `null` for absent texts.
String? _str(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;
