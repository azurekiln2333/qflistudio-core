// 旧「远程电脑」入口的落点：编辑器页的 Agents 面板。
//
// 远程会话管理已经并入 Agents 面板，独立首页只剩配对设置（设备与远程）。
// 工具页的旧卡片改为调用这里：挑一个本地项目，打开编辑器，并让页面首帧就
// 落在 Agents 面板上。没有项目时给出说明，而不是推一个空页面。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../editor/retained_editor_host.dart';
import '../../store/auth_store.dart';
import '../../store/project_store.dart';
import '../../store/settings_store.dart';
import '../../models/project.dart';
import '../../services/app_paths.dart';
import '../../shell/large_screen_controller.dart';
import '../../shell/workbench_chrome.dart';
import '../../shell/workbench_session_view.dart';
import '../../sync/placeholder_project.dart';
import '../harness_host.dart';
import '../harness_session_target.dart';
import '../hub/agents_index.dart';
import '../hub/harness_hub.dart';
import '../hub/harness_hosts.dart';
import '../studio/studio_agent_host.dart';

/// 打开 Agents 面板。
///
/// [project] 为空时用项目仓库里最近的一个本地项目；一个都没有时提示先建项目。
Future<void> openAgentsSurface(
  BuildContext context, {
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
  Project? project,
}) async {
  final target = project ?? _pickLocalProject(store);
  if (target == null) {
    if (!context.mounted) return;
    final workbench = LargeScreenScope.maybeOf(context);
    if (workbench != null) {
      workbench.select(WorkbenchActivity.agents, toggle: false);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('先打开一个项目'),
        content: const Text(
          'Agents 面板在编辑器里。新建或打开一个项目后，'
          '右侧的 Agent 面板就能看到本机、Herdr 和已绑定电脑的会话。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return;
  }
  await openEditorPage(
    context,
    project: target,
    auth: auth,
    store: store,
    settings: settings,
    revealAgentPane: true,
  );
}

/// 最近更新的本地项目。云端项目没有本地目录，不拿来当工作目录。
Project? _pickLocalProject(ProjectStore store) {
  final locals = store.projects.where((project) => !project.isCloud).toList();
  if (locals.isEmpty) return null;
  locals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return locals.first;
}

/// 打开首页列表里的一行：跳到编辑器并首帧选中该会话。
///
/// Workbench sessions use their own directory or a session-only center view.
/// Phone navigation keeps its existing project and placeholder behavior.
Future<void> openAgentSession(
  BuildContext context, {
  required AgentsIndexRow row,
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
  HarnessHub? harnessHub,
}) async {
  final workbench = LargeScreenScope.maybeOf(context);
  Project? target;
  if (workbench == null) {
    target = await resolveSessionProject(store, row);
  } else {
    try {
      target = await resolveSessionProject(store, row, workbench: true);
    } on Object {
      // Registration or placeholder storage can fail. The conversation must
      // still open independently of a writable editor project.
      target = null;
    }
  }
  if (target == null) {
    if (!context.mounted) return;
    if (workbench != null) {
      workbench.showWorkspace();
      workbench.showCenterOverlay(
        (_) => _SessionOverlay(
          key: ValueKey(row.rowKey),
          row: row,
          auth: auth,
          store: store,
          settings: settings,
          hub: harnessHub,
          onClose: workbench.closeCenterOverlay,
        ),
      );
      workbench.closeCompactSidebar();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('先打开一个项目'),
        content: const Text(
          'Agents 面板在编辑器里。新建或打开一个项目后，\n'
          '才能在这里执行 Agent 会话。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return;
  }
  if (!context.mounted) return;
  workbench?.closeCenterOverlay();
  await openEditorPage(
    context,
    project: target,
    auth: auth,
    store: store,
    settings: settings,
    revealAgentPane: true,
    harnessSession: HarnessSessionTarget(
      hostId: row.session.hostId,
      sessionId: row.session.id,
    ),
    harnessHub: harnessHub,
  );
}

/// 一行的会话应该落在哪个项目上。
///
/// [workbench] enables strict directory ownership without changing the phone
/// default. Desktop local sessions register their existing directory in place.
/// Unusable local directories return null, never an unrelated project. Remote
/// and built-in sessions keep their session-specific placeholder workflow.
Future<Project?> resolveSessionProject(
  ProjectStore store,
  AgentsIndexRow row, {
  bool workbench = false,
}) async {
  final localSession =
      row.session.hostId != kStudioHostId &&
      row.hostKind == HarnessHostKind.local;
  if (!workbench || localSession) {
    final local = _projectForSession(
      store,
      row.session.cwd,
      onlyLocal: workbench,
    );
    if (local != null) {
      if (!workbench || await Directory(local.path).exists()) return local;
      return null;
    }
  }

  if (localSession) {
    if (!workbench) return _pickLocalProject(store);
    final cwd = row.session.cwd;
    if (!AppPaths.isDesktop ||
        cwd == null ||
        cwd.trim().isEmpty ||
        !p.isAbsolute(cwd) ||
        !await Directory(cwd).exists()) {
      return null;
    }
    final registered = await store.addExisting(cwd);
    if (registered.error == null) return registered.project;
    // Another registration may have completed while this open was awaiting IO.
    return _projectForSession(store, cwd, onlyLocal: true);
  }

  final existing = store.deviceProjectFor(
    hostId: row.session.hostId,
    sessionId: row.session.id,
  );
  if (existing != null) return existing;

  const placeholders = PlaceholderProjects();
  final created = await placeholders.ensure(
    hostId: row.session.hostId,
    sessionId: row.session.id,
    title: row.session.title,
    deviceRoot: row.session.cwd,
  );
  if (created == null) return null;
  final result = await store.registerDeviceProject(created);
  if (result.error != null) return created;
  return result.project ?? created;
}

/// Owns a fallback hub only when the caller has no shared Home/workbench hub.
class _SessionOverlay extends StatefulWidget {
  const _SessionOverlay({
    super.key,
    required this.row,
    required this.auth,
    required this.store,
    required this.settings,
    required this.hub,
    required this.onClose,
  });

  final AgentsIndexRow row;
  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;
  final HarnessHub? hub;
  final VoidCallback onClose;

  @override
  State<_SessionOverlay> createState() => _SessionOverlayState();
}

class _SessionOverlayState extends State<_SessionOverlay> {
  late HarnessHub _hub;
  late bool _ownsHub;

  @override
  void initState() {
    super.initState();
    _replaceHub(widget.hub);
  }

  @override
  void didUpdateWidget(_SessionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hub, widget.hub)) _replaceHub(widget.hub);
  }

  void _replaceHub(HarnessHub? supplied) {
    final oldHub = _hubOrNull;
    final oldOwned = _hubInitialized && _ownsHub;
    _hub = supplied ?? _createFallbackHub();
    _ownsHub = supplied == null;
    if (oldOwned && oldHub != null) oldHub.dispose();
    _hubInitialized = true;
  }

  bool _hubInitialized = false;
  HarnessHub? get _hubOrNull => _hubInitialized ? _hub : null;

  HarnessHub _createFallbackHub() => HarnessHub(
    hosts: HarnessHosts.build(
      HubHostContext(
        auth: widget.auth,
        projectStore: widget.store,
        settings: widget.settings,
        projectRoot: '',
        desktop: AppPaths.isDesktop,
      ),
    ),
    desktop: AppPaths.isDesktop,
    hostBuildError: HarnessHosts.lastBuildError,
  );

  @override
  void dispose() {
    if (_ownsHub) _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WorkbenchSessionView(row: widget.row, hub: _hub, onClose: widget.onClose);
}

/// 会话目录对应的本地项目。路径规范化后再比，云端项目不参与。
Project? _projectForSession(
  ProjectStore store,
  String? cwd, {
  bool onlyLocal = false,
}) {
  if (cwd == null || cwd.isEmpty) return null;
  final wanted = p.normalize(p.absolute(cwd));
  for (final project in store.projects) {
    if (project.isCloud || (onlyLocal && project.isDevice)) continue;
    if (p.equals(p.normalize(p.absolute(project.path)), wanted)) {
      return project;
    }
  }
  return null;
}
