// 旧「远程电脑」入口的落点：编辑器页的 Agents 面板。
//
// 远程会话管理已经并入 Agents 面板，独立首页只剩配对设置（设备与远程）。
// 工具页的旧卡片改为调用这里：挑一个本地项目，打开编辑器，并让页面首帧就
// 落在 Agents 面板上。没有项目时给出说明，而不是推一个空页面。

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../editor/retained_editor_host.dart';
import '../../store/auth_store.dart';
import '../../store/project_store.dart';
import '../../store/settings_store.dart';
import '../../models/project.dart';
import '../../sync/placeholder_project.dart';
import '../harness_host.dart';
import '../harness_session_target.dart';
import '../hub/agents_index.dart';
import '../hub/harness_hub.dart';
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
/// 找项目的顺序：会话目录对应的本地项目 → 该会话已建的占位项目 →
/// 新建一个占位项目。只有全都不成时才用最近的本地项目（需求 9.7）。
/// 配对电脑上的会话不拿别的项目当工作目录：那样编辑器显示的目录、
/// 文件树与保存位置都不是用户以为的那个项目。
Future<void> openAgentSession(
  BuildContext context, {
  required AgentsIndexRow row,
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
  HarnessHub? harnessHub,
}) async {
  final target = await resolveSessionProject(store, row);
  if (target == null) {
    if (!context.mounted) return;
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
/// 配对本机之外的会话（已绑定电脑、内置 Agent）没有本地目录可比，于是走
/// 占位项目（需求 12）：已经有就复用，没有就建一个，并登记到项目列表。
/// 占位项目只承载会话，项目文件要用户确认后才拉，见
/// [PlaceholderProjects.pullFiles]。这样的会话不发到别的项目上：编辑器显示
/// 的目录、文件树与保存位置都会变成另一个项目（需求 9.7 只允许本机会话
/// 退回最近的项目）。
Future<Project?> resolveSessionProject(
  ProjectStore store,
  AgentsIndexRow row,
) async {
  final local = _projectForSession(store, row.session.cwd);
  if (local != null) return local;

  if (row.session.hostId != kStudioHostId &&
      row.hostKind != HarnessHostKind.remote) {
    return _pickLocalProject(store);
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

/// 会话目录对应的本地项目。路径规范化后再比，云端项目不参与。
Project? _projectForSession(ProjectStore store, String? cwd) {
  if (cwd == null || cwd.isEmpty) return null;
  final wanted = p.normalize(p.absolute(cwd));
  for (final project in store.projects) {
    if (project.isCloud) continue;
    if (p.equals(p.normalize(p.absolute(project.path)), wanted)) {
      return project;
    }
  }
  return null;
}
