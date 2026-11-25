// 首页的 Agents 标签：一台手机上能看到的所有会话。
//
// 只做索引，不做管理：点一行跳到编辑器并选中那个会话（见 agents_entry.dart）。
// 首屏先画快照，网络或磁盘回来再替换。数据流见 design.md §3。
//
// 已绑定电脑的主机要异步打开存储，所以由本页在打开时补接（`addHost`）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../i18n/studio_localizations.dart';
import '../../services/app_paths.dart';
import '../../shell/agent_runtime_factory.dart';
import '../../shell/large_screen_controller.dart';
import '../../store/auth_store.dart';
import '../../store/project_store.dart';
import '../../store/settings_store.dart';
import '../../vibe_coding/vibe_agent_facade.dart';
import '../device_info.dart';
import '../harness_host.dart';
import '../hub/agents_index.dart';
import '../hub/agents_snapshot.dart';
import '../hub/default_harness_hosts.dart';
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
    this.remoteHostOpener,
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

  /// 测试注入的已绑定电脑主机；为空时调 [openRemoteHarnessHost]。
  ///
  /// 真的实现会打开远程存储并连上电脑，测试里给一台假主机。
  final Future<HarnessHost?> Function()? remoteHostOpener;

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

  /// 快照带来的行。主机的新行与它同键时顶掉它。
  ///
  /// 只留着几秒没意义：主机没报的会话不能永远留在列表里。
  List<AgentsIndexRow> _stale = const [];
  List<HarnessSessionInfo> _studioSessions = const [];
  bool _loading = true;
  Object? _error;
  bool _disposed = false;

  /// 已经挂上监听的运行时，避免重复挂。
  AgentRuntime? _watchedRuntime;

  /// 正在补接已绑定的电脑，避免打开与下拉刷新同时开两条连接。
  bool _attachingRemote = false;
  final TextEditingController _search = TextEditingController();

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
      setState(() {
        _stale = cached;
        _rows = cached;
      });
    }
    _hub.listenAll();
    _sub = _hub.watchSessions().listen(_onHubSessions);
    unawaited(_attachRemoteHost());
    await _loadStudioSessions();
  }

  /// 接上已绑定的电脑。
  ///
  /// hub 的构造是同步的，远程主机要先异步打开存储，所以走 [HarnessHub.addHost]。
  /// 已经有远程主机时不重复开：一个 hub 一条连接。
  Future<void> _attachRemoteHost() async {
    if (_attachingRemote) return;
    if (_hub.hosts.any((host) => host.kind == HarnessHostKind.remote)) return;
    _attachingRemote = true;
    HarnessHost? host;
    try {
      final opener = widget.remoteHostOpener ?? openRemoteHarnessHost;
      host = await opener();
    } on Object {
      // 打不开远程存储只影响已绑定电脑那一栏，不拦内置会话与本机。
      host = null;
    } finally {
      _attachingRemote = false;
    }
    if (host == null) return;
    if (_disposed) {
      await host.dispose();
      return;
    }
    _hub.addHost(host);
    if (_disposed) return;
    _hub.listenAll();
    _rebuild();
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

  /// 合并 hub 的行、内置会话与还在顶用的快照行。
  ///
  /// 主机已经报了的主机不再用快照兜底：快照里的旧会话不能永远留在列表里。
  /// 还没接上的主机（比如电脑刚要连）继续显示快照，首屏不闪空白。
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
    // 主机真的报过一次列表才算「听到」：只订阅、还没开口时，
    // 快照里的行要继续顶首屏，否则列表会先闪一下空白。
    // 空列表也是有效报告，此时快照必须让位。
    final heard = <String>{
      for (final host in _hub.hosts)
        if (_hub.hasLoadedSessionsFor(host.id) &&
            _hub.sessionErrorOf(host.id) == null)
          host.id,
    };
    final staleRows = <AgentsIndexRow>[
      for (final row in _stale)
        if (!heard.contains(row.session.hostId)) row,
    ];
    final rows = sortAgentsRows(
      dedupeAgentsRows(<AgentsIndexRow>[
        ...hubRows,
        ...studioRows,
        ...staleRows,
      ]),
    );
    setState(() {
      _rows = rows;
      _loading = false;
    });
    _writer.schedule(rows);
  }

  /// 下拉刷新：重订阅主机、补开电脑连接并重读内置索引。
  Future<void> refresh() async {
    _hub.listenAll();
    await _attachRemoteHost();
    await _hub.refresh();
    await _loadStudioSessions();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _unwatchRuntime();
    _writer.dispose();
    _search.dispose();
    if (_ownsHub) _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    if (LargeScreenScope.maybeOf(context) != null) {
      return _buildWorkbench(context);
    }
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

  Widget _buildWorkbench(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = StudioLocalizations.of(context);
    final desktop = LargeScreenScope.isDesktop(context);
    final query = _search.text.trim().toLowerCase();
    final groups = <String, List<AgentsIndexRow>>{};
    for (final row in _rows) {
      if (query.isNotEmpty &&
          ![
            row.session.title,
            row.session.cwd ?? '',
            row.hostLabel,
          ].any((value) => value.toLowerCase().contains(query))) {
        continue;
      }
      groups.putIfAbsent(row.session.hostId, () => []).add(row);
    }
    return Material(
      key: const ValueKey('agents-workbench-panel'),
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('agents-workbench-header'),
            height: desktop ? 40 : 48,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Agents', style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    key: const ValueKey('agents-workbench-refresh'),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).refreshIndicatorSemanticLabel,
                    constraints: BoxConstraints.tightFor(
                      width: desktop ? 32 : 48,
                      height: desktop ? 32 : 48,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: refresh,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              height: desktop ? 36 : 48,
              child: TextField(
                key: const ValueKey('agents-workbench-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: '搜索会话',
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  prefixIconConstraints: BoxConstraints.tightFor(
                    width: desktop ? 36 : 48,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.primary, width: 2),
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.agentsRefreshFailed,
                key: const ValueKey('agents-refresh-failed'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(
                    key: ValueKey('agents-loading'),
                    child: CircularProgressIndicator(),
                  )
                : groups.isEmpty
                ? Center(
                    key: const ValueKey('agents-empty'),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        query.isEmpty ? l10n.agentsEmpty : '没有匹配的会话',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView(
                    key: const ValueKey('agents-list'),
                    padding: EdgeInsets.zero,
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          key: ValueKey('agents-host-${entry.key}'),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            entry.value.first.hostLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final row in entry.value)
                          AgentsRowTile(
                            row: row,
                            onTap: widget.onOpenSession == null
                                ? null
                                : () => widget.onOpenSession!(row),
                            onDetails: widget.onOpenDetails == null
                                ? null
                                : () => widget.onOpenDetails!(row),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
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
    if (LargeScreenScope.maybeOf(context) != null) {
      return _WorkbenchAgentsRow(row: row, onTap: onTap, onDetails: onDetails);
    }
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

class _WorkbenchAgentsRow extends StatefulWidget {
  const _WorkbenchAgentsRow({required this.row, this.onTap, this.onDetails});

  final AgentsIndexRow row;
  final VoidCallback? onTap;
  final VoidCallback? onDetails;

  @override
  State<_WorkbenchAgentsRow> createState() => _WorkbenchAgentsRowState();
}

class _WorkbenchAgentsRowState extends State<_WorkbenchAgentsRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = widget.row;
    final height = LargeScreenScope.isDesktop(context) ? 32.0 : 48.0;
    return Tooltip(
      message: [
        row.session.title,
        row.hostLabel,
        row.session.cwd ?? '',
      ].join('\n'),
      child: InkWell(
        key: ValueKey('agents-row-${row.rowKey}'),
        onTap: widget.onTap,
        mouseCursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onFocusChange: (value) => setState(() => _focused = value),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return scheme.onSurface.withValues(alpha: 0.10);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.onSurface.withValues(alpha: 0.08);
          }
          return null;
        }),
        child: Container(
          height: height,
          padding: const EdgeInsets.only(left: 12, right: 4),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              _StatusDot(
                status: row.session.status,
                label: harnessStatusLabel(row.session.status),
                rowKey: row.rowKey,
                themed: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (row.session.updatedAt case final updated?) ...[
                const SizedBox(width: 6),
                Text(
                  harnessRelativeTime(updated),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (widget.onDetails != null)
                IconButton(
                  key: ValueKey('agents-details-${row.rowKey}'),
                  tooltip: StudioLocalizations.of(context).agentsDetails,
                  constraints: BoxConstraints.tightFor(
                    width: height,
                    height: height,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.info_outline,
                    size: LargeScreenScope.isDesktop(context) ? 16 : 20,
                  ),
                  onPressed: widget.onDetails,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态圆点。
///
/// Phone colors retain their original status mapping. Workbench colors use
/// ColorScheme roles. Both expose status text; unknown remains an outline.
class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.status,
    required this.label,
    required this.rowKey,
    this.themed = false,
  });

  final bool themed;
  final HarnessSessionStatus status;

  /// 状态的文字说法，读屏与长按都能读到。
  final String label;

  /// 所属行的键，圆点的键带上它才不会跟别的行重复。
  final String rowKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final role = switch (status) {
      HarnessSessionStatus.blocked => scheme.tertiary,
      HarnessSessionStatus.working => scheme.primary,
      HarnessSessionStatus.idle => scheme.onSurfaceVariant,
      HarnessSessionStatus.done => scheme.secondary,
      HarnessSessionStatus.exited => scheme.error,
      HarnessSessionStatus.unknown => scheme.outline,
    };
    return Semantics(
      container: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Container(
          key: ValueKey('agents-status-$rowKey'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: themed
                ? (status == HarnessSessionStatus.unknown ? null : role)
                : harnessStatusDotColor(status),
            border: Border.all(
              color: themed
                  ? role
                  : harnessStatusDotBorderColor(scheme, status),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
