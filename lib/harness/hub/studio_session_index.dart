// 内置 Agent 的会话索引：只读 `agent_sessions/index.json` 的元数据。
//
// 首页要显示内置会话，但不能为了列表去读每个 `.jsonl` 正文（裁定 R2）。
// 索引是会话存储自己维护的，本文件只读不写，也不改它的版本。
// 格式见 design.md §2.6。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../harness_host.dart';

/// 读 `agent_sessions/index.json`，映射成主机会话。
///
/// 默认状态是 [HarnessSessionStatus.idle]：磁盘上的会话没有正在运行的进程。
/// 调用方传了 [read] 的 `statusOf` 时用运行时给的真状态，不传就保持 idle。
class StudioSessionIndex {
  StudioSessionIndex({required this.root});

  /// 会话目录，通常是 `<应用数据目录>/agent_sessions`。
  final Directory root;

  /// 索引文件。
  File get indexFile => File(p.join(root.path, 'index.json'));

  /// 读索引。
  ///
  /// 文件缺失、格式不对、条目缺字段都按空处理，不抛错：首页不该因为一个坏
  /// 索引就整页打不开。
  ///
  /// [statusOf] 可选：已经有运行时在跑时，用它把磁盘上的 idle 换成真状态。
  /// 本函数自己不会去建运行时。
  Future<List<HarnessSessionInfo>> read({
    required String hostId,
    required String Function(String projectId) cwdOf,
    HarnessSessionStatus Function(String sessionId)? statusOf,
  }) async {
    final file = indexFile;
    if (!await file.exists()) return const <HarnessSessionInfo>[];
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FileSystemException {
      return const <HarnessSessionInfo>[];
    } on FormatException {
      return const <HarnessSessionInfo>[];
    }
    if (decoded is! Map) return const <HarnessSessionInfo>[];
    final rawSessions = decoded['sessions'];
    if (rawSessions is! List) return const <HarnessSessionInfo>[];

    final sessions = <HarnessSessionInfo>[];
    for (final raw in rawSessions) {
      if (raw is! Map) continue;
      final id = _string(raw['id']);
      // 空 id 也算坏条目：`_string` 会把 "" 原样返回，
      // 只判 null 会把无 id 的条目带进列表。
      if (id == null || id.isEmpty) continue;
      final updatedAt = DateTime.tryParse(_string(raw['updatedAt']) ?? '');
      if (updatedAt == null) continue;
      final projectId = _string(raw['projectId']) ?? '';
      sessions.add(
        HarnessSessionInfo(
          id: id,
          hostId: hostId,
          providerId: _providerId,
          title: _string(raw['title']) ?? _defaultTitle,
          status: statusOf?.call(id) ?? HarnessSessionStatus.idle,
          capabilities: _capabilities,
          cwd: projectId.isEmpty ? '' : cwdOf(projectId),
          updatedAt: updatedAt,
          sourceRef: id,
        ),
      );
    }
    sessions.sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    return List<HarnessSessionInfo>.unmodifiable(sessions);
  }

  /// 内置 Agent 的 provider 标识，与会话主机一致。
  static const String _providerId = 'studio';

  /// 内置会话的标题占位，与 `AgentSessionStore.defaultTitle` 同一写法。
  static const String _defaultTitle = '新会话';

  /// 内置会话只有对话、输入、确认与停止，没有终端。
  static const Set<HarnessCapability> _capabilities = {
    HarnessCapability.transcript,
    HarnessCapability.prompt,
  };

  static String? _string(Object? value) {
    if (value is String) return value;
    if (value == null) return null;
    return value.toString();
  }
}

/// 把一条索引会话换成另一个状态。
///
/// 运行时的活动状态会变，索引不必重读磁盘：只改状态字段，其余原样搬过去。
HarnessSessionInfo studioSessionWithStatus(
  HarnessSessionInfo session,
  HarnessSessionStatus status,
) => HarnessSessionInfo(
  id: session.id,
  hostId: session.hostId,
  providerId: session.providerId,
  title: session.title,
  status: status,
  capabilities: session.capabilities,
  cwd: session.cwd,
  updatedAt: session.updatedAt,
  sourceRef: session.sourceRef,
);
