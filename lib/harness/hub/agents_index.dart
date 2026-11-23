// 首页 Agents 列表的一行，以及合并与排序规则。
//
// 纯函数：输入主机与会话，输出排好序的行。测试不需要挂界面。
// 排序见 design.md §2.5。

import 'package:flutter/foundation.dart';

import '../harness_host.dart';

/// 首页列表的一行。
@immutable
class AgentsIndexRow {
  const AgentsIndexRow({
    required this.session,
    required this.hostLabel,
    required this.hostKind,
    this.device,
  });

  /// 会话本身。
  final HarnessSessionInfo session;

  /// 端标注：本机、Herdr、已绑定电脑的设备名。
  final String hostLabel;

  /// 主机类型，决定端标注的默认写法。
  final HarnessHostKind hostKind;

  /// 主机所在设备的信息；主机不报设备信息时为 null。
  final HarnessDeviceInfo? device;

  /// 唯一键：同一台主机上会话 id 不重复。
  String get rowKey => '${session.hostId}:${session.id}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentsIndexRow &&
          other.session.id == session.id &&
          other.session.hostId == session.hostId &&
          other.hostLabel == hostLabel &&
          other.hostKind == hostKind &&
          other.session.status == session.status &&
          other.session.title == session.title;

  @override
  int get hashCode => Object.hash(
    session.hostId,
    session.id,
    hostLabel,
    hostKind,
    session.status,
    session.title,
  );
}

/// 状态权重：数字小的排前面。
///
/// 要人搭手的排最前，跑着的其次，之后才是收尾的状态。
int harnessStatusRank(HarnessSessionStatus status) {
  switch (status) {
    case HarnessSessionStatus.blocked:
      return 0;
    case HarnessSessionStatus.working:
      return 1;
    case HarnessSessionStatus.idle:
      return 2;
    case HarnessSessionStatus.done:
      return 3;
    case HarnessSessionStatus.exited:
      return 4;
    case HarnessSessionStatus.unknown:
      return 5;
  }
}

/// 端标注。
///
/// 本机与 Herdr 用固定写法；已绑定电脑优先用设备名，取不到时退回主机名。
String agentsHostLabel({
  required HarnessHostKind kind,
  required String hostLabel,
  HarnessDeviceInfo? device,
}) {
  switch (kind) {
    case HarnessHostKind.local:
      return '本机';
    case HarnessHostKind.studio:
      return '内置 Agent';
    case HarnessHostKind.remote:
      final name = device?.hostName?.trim();
      if (name != null && name.isNotEmpty) return name;
      final label = hostLabel.trim();
      return label.isEmpty ? '已绑定的电脑' : label;
  }
}

/// 合并会话列表并按状态、更新时间排序。
///
/// 找不到主机的会话直接丢弃：没有主机就开不了，列出来只会点出一句错误。
List<AgentsIndexRow> buildAgentsIndex({
  required Iterable<HarnessHost> hosts,
  required List<HarnessSessionInfo> sessions,
  required HarnessDeviceInfo? Function(HarnessHost host) deviceOf,
}) {
  final byId = <String, HarnessHost>{for (final host in hosts) host.id: host};
  final rows = <AgentsIndexRow>[];
  for (final session in sessions) {
    final host = byId[session.hostId];
    if (host == null) continue;
    final device = deviceOf(host);
    rows.add(
      AgentsIndexRow(
        session: session,
        hostLabel: agentsHostLabel(
          kind: host.kind,
          hostLabel: host.label,
          device: device,
        ),
        hostKind: host.kind,
        device: device,
      ),
    );
  }
  rows.sort(_compareRows);
  return List<AgentsIndexRow>.unmodifiable(rows);
}

/// 按状态、更新时间、标题排序。纯函数，不读任何外部状态。
///
/// 首页把 hub 的行与内置会话索引的行合并后还要再排一次，所以单独导出。
List<AgentsIndexRow> sortAgentsRows(List<AgentsIndexRow> rows) {
  final sorted = List<AgentsIndexRow>.of(rows)..sort(_compareRows);
  return List<AgentsIndexRow>.unmodifiable(sorted);
}

/// 按 [rowKey] 去重，先出现的行优先。
///
/// 内置会话可能既在 hub 里又在磁盘索引里：hub 的行带真实状态，排前面。
List<AgentsIndexRow> dedupeAgentsRows(Iterable<AgentsIndexRow> rows) {
  final seen = <String>{};
  final kept = <AgentsIndexRow>[];
  for (final row in rows) {
    if (seen.add(row.rowKey)) kept.add(row);
  }
  return List<AgentsIndexRow>.unmodifiable(kept);
}

int _compareRows(AgentsIndexRow a, AgentsIndexRow b) {
  final byStatus = harnessStatusRank(
    a.session.status,
  ).compareTo(harnessStatusRank(b.session.status));
  if (byStatus != 0) return byStatus;
  final aTime = a.session.updatedAt;
  final bTime = b.session.updatedAt;
  if (aTime != null || bTime != null) {
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    final byTime = bTime.compareTo(aTime);
    if (byTime != 0) return byTime;
  }
  final byTitle = a.session.title.toLowerCase().compareTo(
    b.session.title.toLowerCase(),
  );
  if (byTitle != 0) return byTitle;
  return a.rowKey.compareTo(b.rowKey);
}
