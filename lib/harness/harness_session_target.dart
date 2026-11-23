// 打开编辑器时要选中的会话：主机 id 加会话 id。
//
// 单独一个文件，编辑器与 Agent 入口都只依赖它，不互相依赖。

import 'package:flutter/foundation.dart';

/// 打开编辑器时首帧要选中的会话。
///
/// 主机 id 决定用哪条路打开：`studio` 走内置面板，其它主机走 Hub。
@immutable
class HarnessSessionTarget {
  const HarnessSessionTarget({required this.hostId, required this.sessionId});

  /// 会话所属主机的 id，与 [HarnessHost.id] 相同。
  final String hostId;

  /// 会话 id，与 [HarnessSessionInfo.id] 相同。
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HarnessSessionTarget &&
          other.hostId == hostId &&
          other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(hostId, sessionId);

  @override
  String toString() => 'HarnessSessionTarget($hostId, $sessionId)';
}
