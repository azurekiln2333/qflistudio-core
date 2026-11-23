// 首页的 Agents 标签：一台手机上能看到的所有会话。
//
// 只做索引，不做管理：点一行跳到编辑器并选中那个会话（见 agents_entry.dart）。
// 首屏先画快照，网络或磁盘回来再替换。数据流见 design.md §3。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../i18n/studio_localizations.dart';
import '../../services/app_paths.dart';
import '../../shell/agent_runtime_factory.dart';
import '../../store/auth_store.dart';
import '../../store/project_store.dart';
import '../../store/settings_store.dart';
import '../../vibe_coding/vibe_agent_facade.dart';
import '../device_info.dart';
import '../harness_host.dart';
import '../hub/agents_index.dart';
import '../hub/agents_snapshot.dart';
import '../hub/harness_hub.dart';
import '../hub/harness_hosts.dart';
import '../hub/studio_session_index.dart';
import '../studio/studio_agent_host.dart';
import 'hub_status.dart';

/// 首页 Agents 标签的主体。
///
/// hub 由本页持有：打开标签时才建，切走时由首页保活但不重新建。
class HomeAgentsTab extends StatefulWidget {
  const HomeAgentsTab({
    super.key,
    required this.auth,
    required this.store,
    required this.settings,
    this.harnessHub,
    this.snapshotStore,
    this.sessionRoot,
    this.deviceInfo,
    this.runtime,
    this.onOpenSession,
    this.onOpenDetails,
  });

  /// 点一行时调用。由首页接到 `openAgentSession`，跳到编辑器并选中会话。
  final void Function(AgentsIndexRow row)? onOpenSession;

  /// 点详情时调用。由首页接到详情页。
  final void Function(AgentsIndexRow row)? onOpenDetails;

  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;

  /// 测试注入的 hub；为空时按产品策略装配。
  final HarnessHub? harnessHub;

  /// 测试注入的快照存储。
  final AgentsSnapshotStore? snapshotStore;

  /// 内置会话目录；为空时用应用数据目录下的 `agent_sessions`。
  final Directory? sessionRoot;

  /// 手机本机的设备信息；为空时读平台常量。
  final HarnessDeviceInfo? deviceInfo;

  /// 内置 Agent 的运行时。
  ///
  /// 为空时只读已装配好的那一个（[currentStudioAgentRuntime]），不会为了
  /// 列表去新建运行时。测试用它注入假运行时。
  final AgentRuntime? runtime;

  @override
  State<HomeAgentsTab> createState() => HomeAgentsTabState();
}

/// 对同文件的其他部分与测试开放的状态。
class HomeAgentsTabState extends State<HomeAgentsTab> {
  late final HarnessHub _hub;
  late final bool _ownsHub;
  late final AgentsSnapshotStore _snapshot;
  late final AgentsSnapshotWriter _writer;
  late final HarnessDeviceInfo _device;

  StreamSubscription<List<HarnessSessionInfo>>? _sub;
  List<AgentsIndexRow> _rows = const [];
  List<HarnessSessionInfo> _studioSessions = const [];
  bool _loading = true;
  Object? _error;
  bool _disposed = false;

  /// 已经挂上监听的运行时，避免重复挂。
  AgentRuntime? _watchedRuntime;

  /// 当前渲染的行，测试用来断言排序与合并。
  @visibleForTesting
  List<AgentsIndexRow> get rows => _rows;

  @override
  void initState() {
    super.initState();
    _device = widget.deviceInfo ?? currentDeviceInfo();
    _snapshot = widget.snapshotStore ?? AgentsSnapshotStore();
    _writer = AgentsSnapshotWriter(store: _snapshot);
    final injected = widget.harnessHub;
    _ownsHub = injected == null;
    _hub =
        injected ??
        HarnessHub(
          hosts: HarnessHosts.build(
            HubHostContext(
              auth: widget.auth,
              projectStore: widget.store,
              settings: widget.settings,
              // 首页没有打开的项目：内置 Agent 主机不在这里装配。
              projectRoot: '',
              desktop: AppPaths.isDesktop,
            ),
          ),
          desktop: AppPaths.isDesktop,
          hostBuildError: HarnessHosts.lastBuildError,
        );
    unawaited(_start());
  }

  /// 先读快照，再订阅 hub，最后读内置会话索引。
  Future<void> _start() async {
    final cached = await _snapshot.load();
    if (_disposed) return;
    if (cached.isNotEmpty) {
      setState(() => _rows = cached);
    }
    _hub.listenAll();
    _sub = _hub.watchSessions().listen(_onHubSessions);
    await _loadStudioSessions();
  }

  void _onHubSessions(List<HarnessSessionInfo> _) => _rebuild();

  /// 读内置会话索引。目录拿不到就当作没有内置会话。
  Future<void> _loadStudioSessions() async {
    try {
      final root = widget.sessionRoot ?? await _defaultSessionRoot();
      if (_disposed) return;
      _watchRuntime();
      final sessions = root == null
          ? const <HarnessSessionInfo>[]
          : await StudioSessionIndex(root: root).read(
              hostId: _studioHostId,
              cwdOf: _cwdOf,
              statusOf: _statusOfStudioSession,
            );
      if (_disposed) return;
      setState(() {
        _studioSessions = sessions;
        _loading = false;
        _error = null;
      });
      _rebuild();
    } on Object catch (error) {
      if (_disposed) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  /// 已装配好的内置 Agent 运行时；没跑过时为 null。
  ///
  /// 不调 [studioAgentRuntime]：那个会为了拿一个运行时把整条流水线起来。
  AgentRuntime? get _liveRuntime =>
      widget.runtime ?? currentStudioAgentRuntime();

  /// 内置会话的真状态。没有运行时就是 idle。
  HarnessSessionStatus _statusOfStudioSession(String sessionId) {
    final runtime = _liveRuntime;
    if (runtime == null) return HarnessSessionStatus.idle;
    return mapStudioLiveStatus(runtime.statusOf(sessionId));
  }

  /// 运行时活动状态变了就跟着改列表里的状态，不重读磁盘。
  void _watchRuntime() {
    final runtime = _liveRuntime;
    if (runtime == null || identical(runtime, _watchedRuntime)) return;
    _unwatchRuntime();
    _watchedRuntime = runtime;
    runtime.liveChanges.addListener(_onRuntimeChanged);
  }

  void _unwatchRuntime() {
    final runtime = _watchedRuntime;
    if (runtime == null) return;
    runtime.liveChanges.removeListener(_onRuntimeChanged);
    _watchedRuntime = null;
  }

  void _onRuntimeChanged() {
    if (_disposed) return;
    final runtime = _liveRuntime;
    if (runtime == null) return;
    _studioSessions = <HarnessSessionInfo>[
      for (final session in _studioSessions)
        studioSessionWithStatus(
          session,
          mapStudioLiveStatus(runtime.statusOf(session.id)),
        ),
    ];
    _rebuild();
  }

  /// 应用数据目录下的会话目录。
  Future<Directory?> _defaultSessionRoot() async {
    final base = await AppPaths.storageDirectory();
    if (base == null || base.isEmpty) return null;
    return Directory(p.join(base, 'agent_sessions'));
  }

  /// 会话所属项目的本地目录。项目已删时给空串。
  String _cwdOf(String projectId) {
    for (final project in widget.store.projects) {
      if (project.id == projectId) return project.path;
    }
    return '';
  }

  void _rebuild() {
    if (_disposed) return;
    final hubRows = buildAgentsIndex(
      hosts: _hub.hosts,
      sessions: _hub.allSessions,
      deviceOf: harnessDeviceOf,
    );
    final studioRows = <AgentsIndexRow>[
      for (final session in _studioSessions)
        AgentsIndexRow(
          session: session,
          hostLabel: agentsHostLabel(
            kind: HarnessHostKind.studio,
            hostLabel: '',
            device: _device,
          ),
          hostKind: HarnessHostKind.studio,
          device: _device,
        ),
    ];
    final rows = sortAgentsRows(
      dedupeAgentsRows(<AgentsIndexRow>[...hubRows, ...studioRows]),
    );
    setState(() {
      _rows = rows;
      _loading = false;
    });
    _writer.schedule(rows);
  }

  /// 下拉刷新：重订阅主机并重读内置索引。
  Future<void> refresh() async {
    _hub.listenAll();
    await _loadStudioSessions();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _unwatchRuntime();
    _writer.dispose();
    if (_ownsHub) _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    if (_loading && _rows.isEmpty) {
      return Center(
        key: const ValueKey('agents-loading'),
        child: const CircularProgressIndicator(),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: _rows.isEmpty
          ? ListView(
              key: const ValueKey('agents-empty'),
              children: [
                const SizedBox(height: 96),
                Center(
                  child: Text(
                    l10n.agentsEmpty,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.agentsEmptyHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              key: const ValueKey('agents-list'),
              itemCount: _rows.length + (_error == null ? 0 : 1),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (_error != null && index == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.agentsRefreshFailed,
                      key: const ValueKey('agents-refresh-failed'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                final row = _rows[index - (_error == null ? 0 : 1)];
                final open = widget.onOpenSession;
                final details = widget.onOpenDetails;
                return AgentsRowTile(
                  row: row,
                  onTap: open == null ? null : () => open(row),
                  onDetails: details == null ? null : () => details(row),
                );
              },
            ),
    );
  }

  /// 内置 Agent 的主机 id，与 `kStudioHostId` 同一写法。
  static const String _studioHostId = 'studio';
}

/// 列表里的一行：状态圆点、标题、端标注与会话路径、相对时间与详情入口。
class AgentsRowTile extends StatelessWidget {
  const AgentsRowTile({
    super.key,
    required this.row,
    this.onTap,
    this.onDetails,
  });

  final AgentsIndexRow row;
  final VoidCallback? onTap;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = row.session.status;
    final path = row.session.cwd;
    final updatedAt = row.session.updatedAt;
    return InkWell(
      key: ValueKey('agents-row-${row.rowKey}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _StatusDot(
              status: status,
              label: harnessStatusLabel(status),
              rowKey: row.rowKey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      row.hostLabel,
                      if (path != null && path.isNotEmpty) p.basename(path),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (updatedAt != null) ...[
              const SizedBox(width: 8),
              Text(
                harnessRelativeTime(updatedAt),
                style: theme.textTheme.labelSmall,
              ),
            ],
            IconButton(
              key: ValueKey('agents-details-${row.rowKey}'),
              tooltip: StudioLocalizations.of(context).agentsDetails,
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: onDetails,
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态圆点。
///
/// 颜色固定，不取主题色（裁定 R3）。未知画空心圈。文字语义标签同时给
/// 读屏与长按提示，不只靠颜色区分。
class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.status,
    required this.label,
    required this.rowKey,
  });

  final HarnessSessionStatus status;

  /// 状态的文字说法，读屏与长按都能读到。
  final String label;

  /// 所属行的键，圆点的键带上它才不会跟别的行重复。
  final String rowKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          key: ValueKey('agents-status-$rowKey'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: harnessStatusDotColor(status),
            border: Border.all(
              color: harnessStatusDotBorderColor(scheme, status),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
