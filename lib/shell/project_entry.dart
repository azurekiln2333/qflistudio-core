import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/composer_draft.dart';
import '../chat/composer_state.dart';
import '../editor/retained_editor_host.dart';
import '../models/project.dart';
import '../pages/project/project_page.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../vibe_coding/vibe_agent_facade.dart';
import '../workspace/workspace_store.dart';
import 'agent_runtime_factory.dart';
import 'workbench_shell.dart';
import 'workbench_state.dart';

/// 主页点项目后的落点：项目页（会话列表 + 输入卡片）。
Future<void> openProjectPage(
  BuildContext context, {
  required Project project,
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
  String? initialOpenPath,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ProjectEntryPage(
        project: project,
        auth: auth,
        store: store,
        settings: settings,
        initialOpenPath: initialOpenPath,
      ),
    ),
  );
}

/// 装配 agent 运行时，再把项目页挂上去。
///
/// 运行时需要异步读取应用数据目录，所以先加载再渲染。
class ProjectEntryPage extends StatefulWidget {
  const ProjectEntryPage({
    super.key,
    required this.project,
    required this.auth,
    required this.store,
    required this.settings,
    this.runtime,
    this.composerDefaults,
    this.persistComposerDefaults = true,
    this.initialOpenPath,
  });

  final Project project;
  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;

  /// 测试注入；为空时用应用级单例。
  final AgentRuntime? runtime;

  /// 每个项目记住的输入卡片选择；为空时用文件实现。
  final ComposerDefaultsStore? composerDefaults;

  /// 是否落盘保存输入卡片选择。
  ///
  /// widget 测试跑在 fake async 里，`AppPaths` 的目录探测会留下定时器，
  /// 测试传 false。
  final bool persistComposerDefaults;
  final String? initialOpenPath;

  @override
  State<ProjectEntryPage> createState() => _ProjectEntryPageState();
}

class _ProjectEntryPageState extends State<ProjectEntryPage> {
  AgentRuntime? _runtime;
  String? _error;
  late final ComposerDefaultsStore? _composerDefaults =
      widget.composerDefaults ??
      (widget.persistComposerDefaults ? FileComposerDefaultsStore() : null);

  @override
  void initState() {
    super.initState();
    _resolveRuntime();
  }

  Future<void> _resolveRuntime() async {
    final injected = widget.runtime;
    if (injected != null) {
      setState(() => _runtime = injected);
      return;
    }
    try {
      final runtime = await studioAgentRuntime(
        auth: widget.auth,
        store: widget.store,
        settings: widget.settings,
      );
      if (!mounted) return;
      setState(() => _runtime = runtime);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<bool> _openSession(String sessionId, ComposerDraft draft) async {
    final runtime = _runtime;
    if (runtime == null) return false;
    await _openWorkbench(
      runtime,
      sessionId: sessionId,
      draft: draft,
      pane: MainPane.agent,
    );
    return true;
  }

  /// 打开编辑器。
  ///
  /// 走现有的 `openEditorPage` 宿主，保留最小化/恢复与会话切换等既有行为。
  /// 工作台里的编辑器是另一个呈现，两处共用同一个 `EditorPage`。
  void _openEditor() => unawaited(
    openEditorPage(
      context,
      project: widget.project,
      auth: widget.auth,
      store: widget.store,
      settings: widget.settings,
      initialOpenPath: widget.initialOpenPath,
    ),
  );

  Future<void> _openWorkbench(
    AgentRuntime? runtime, {
    String? sessionId,
    ComposerDraft draft = ComposerDraft.empty,
    required MainPane pane,
  }) {
    final state = WorkbenchState(
      projectId: widget.project.id,
      sessionId: sessionId,
      mainPane: pane,
    );
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkbenchShell(
          project: widget.project,
          auth: widget.auth,
          store: widget.store,
          settings: widget.settings,
          runtime: runtime,
          state: state,
          initialSessionId: sessionId,
          draft: draft,
          composerDefaults: _composerDefaults,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (runtime == null) {
      // 运行时还在装配时也给出编辑器入口：编辑器不依赖 agent。
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.project.name),
          actions: [
            IconButton(
              key: const ValueKey('project-open-editor'),
              tooltip: '编辑器',
              onPressed: _openEditor,
              icon: const Icon(Icons.code),
            ),
          ],
        ),
        body: Center(
          child: _error == null
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('agent 运行时不可用：$_error'),
                ),
        ),
      );
    }
    return ProjectPage(
      project: widget.project,
      runtime: runtime,
      auth: widget.auth,
      workspaces: WorkspaceStore.instance,
      composerDefaults: _composerDefaults,
      onOpenSession: _openSession,
      onOpenEditor: _openEditor,
    );
  }
}
