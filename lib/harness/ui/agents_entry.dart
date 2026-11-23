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
import '../harness_session_target.dart';
import '../hub/agents_index.dart';
import '../hub/harness_hub.dart';

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
/// 优先用会话自己的目录找项目；找不到时用最近的本地项目。一个本地项目
/// 都没有时不推空页面，只说明原因。
Future<void> openAgentSession(
  BuildContext context, {
  required AgentsIndexRow row,
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
  HarnessHub? harnessHub,
}) async {
  final target =
      _projectForSession(store, row.session.cwd) ?? _pickLocalProject(store);
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
