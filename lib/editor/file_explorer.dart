import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../store/project_store.dart';
import '../shell/large_screen_controller.dart';
import '../services/file_service.dart';
import '../editor/new_file_dialog.dart';
import '../store/settings_store.dart';
import '../editor/project_history.dart';
import '../pages/file_history_page.dart';
import '../services/recycle_bin.dart';
import '../services/picker_service.dart';
import '../services/project_file_access.dart';
import '../services/resource_import_service.dart';
import '../i18n/studio_localizations.dart';
import '../widgets/project_dialogs.dart';
import '../workspace/editor_workspace.dart';
import '../workspace/saved_workspace.dart';
import '../workspace/workspace_dialogs.dart';
import '../workspace/workspace_store.dart';
import '../shell/workbench_state.dart';
import 'editor_controller.dart';

class FileNode {
  const FileNode({required this.path, required this.name, required this.isDir});

  final String path;
  final String name;
  final bool isDir;
}

/// 编辑器左侧的文件树面板（宽度由外层容器约束）。
class FileExplorer extends StatefulWidget {
  const FileExplorer({
    super.key,
    required this.project,
    required this.editor,
    required this.store,
    required this.settings,
    this.onFileOpened,
    this.onEntryDeleted,
    this.onShareEntry,
    this.outlined = true,
    this.workspace,
    this.workspaceMembers = const [],
    this.workspaceStore,
    this.onWorkspaceChanged,
    this.onProjectSelected,
    this.headerTrailing,
    this.sections,
    this.refreshSignal,
    this.largeScreen = false,
  });

  /// 大屏模式由外壳传入。它移除卡片装饰，并按桌面或平板选择行高。
  final bool largeScreen;

  /// 标题栏最右侧的控件：文件/会话切换按钮。
  ///
  /// 放在项目选择器之后、所有动作按钮的最右边，与相邻动作同一个触摸尺寸。
  /// 标题栏里只有这一行，没有独立的分段条。
  final Widget? headerTrailing;

  /// 有值时这个卡片同时装载「文件」和「会话」两种主体。
  ///
  /// 卡片外框和标题行只有一套；切换只替换卡片内部的主体，不会出现两个
  /// 外框或第二层标题。
  final FileExplorerSections? sections;

  /// 外部要求刷新文件树时递增。
  ///
  /// 编辑器页在 agent 写入、新建或删除文件后用它把磁盘变化拉进树里；
  /// 树自己不需要知道事件从哪来。
  final ValueListenable<int>? refreshSignal;

  /// 是否由本组件自绘 MD3 outlined 卡片外观（圆角 + 细描边）。
  ///
  /// 设为 false 时仅渲染内容，外观交给外层容器（例如抽屉里的自定义卡片）。
  final bool outlined;

  final Project project;
  final EditorController editor;

  /// 项目设置（新建文件的自定义后缀）。
  final SettingsStore settings;

  /// 全部项目列表（跨项目浏览用）。
  final ProjectStore store;

  /// 文件/文件夹被删除后的回调（云端项目推送删除）。
  final ValueChanged<String>? onEntryDeleted;

  /// The editor owns credentials and export lifecycle, not the tree. Ownership
  /// is resolved from the selected node, including other workspace roots.
  final Future<void> Function(Project owner, String path)? onShareEntry;

  /// 文件成功打开后的回调（抽屉模式下用于自动关闭抽屉）。
  final VoidCallback? onFileOpened;

  /// Explicitly saved workspace this editor session belongs to, if any.
  ///
  /// Null means a standalone project open: the tree shows only [project] and
  /// never restores another project's workspace membership.
  final SavedWorkspace? workspace;

  /// Resolved surviving members of [workspace], including [project].
  final List<Project> workspaceMembers;

  /// Store used when the user saves or updates a workspace from the tree.
  final WorkspaceStore? workspaceStore;

  /// Reports workspace metadata or tree-expansion changes back to the editor so
  /// the session can be persisted into the workspace document (not history).
  final ValueChanged<EditorWorkspaceState>? onWorkspaceChanged;

  /// Opens an external project in its own editor session.
  final ValueChanged<Project>? onProjectSelected;

  /// 项目内按名称递归搜索文件（跳过 .git/node_modules/build 等重目录）。
  static List<FileNode> searchFiles(String rootPath, String query) {
    final results = <FileNode>[];
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return results;
    const skipDirs = {'.git', 'node_modules', 'build', '.dart_tool', '.idea'};
    void walk(Directory dir) {
      if (results.length >= 200) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      entries.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (skipDirs.contains(name) || name.startsWith('.')) continue;
          walk(e);
        } else if (name.toLowerCase().contains(keyword)) {
          results.add(FileNode(path: e.path, name: name, isDir: false));
          if (results.length >= 200) return;
        }
      }
    }

    walk(Directory(rootPath));
    return results;
  }

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

/// 卡片内两段主体的配置：文件树与会话列表共用一套外框和标题行。
///
/// [state] 是唯一的选中态来源；[sessions] 为 null 时主体显示等待，标题行
/// 仍在，所以随时可以切回文件树。
class FileExplorerSections {
  const FileExplorerSections({
    required this.state,
    required this.sessions,
    this.onNewSession,
    this.onStopAllSessions,
  });

  final WorkbenchState state;

  /// 会话列表主体；未就绪时为 null。
  final Widget? sessions;

  /// 会话段标题行里的新建动作。
  final VoidCallback? onNewSession;

  /// 会话段标题行里的「全部停止」。
  final VoidCallback? onStopAllSessions;
}

class _FileExplorerState extends State<FileExplorer> {
  /// 标题行文字的水平入场内边距。文件段与会话段共用，切段时标题不跳位。
  static const double _headerTitleInset = 8;

  final Map<String, List<FileNode>> _children = {};
  final Set<String> _expanded = {};
  final TextEditingController _searchController = TextEditingController();
  bool _searchOpen = false;
  String _searchQuery = '';
  late Project _browsing;
  late FileNode _root;
  int _treeGeneration = 0;
  Future<void>? _restoring;

  /// 本条失败只提示一次，避免刷新时重复弹条。
  bool _listingFailureShown = false;

  /// 上一次报过错的目录；它读成功后才重新允许提示。
  String? _listingFailurePath;
  List<Project> _workspaceProjects = [];
  SavedWorkspace? _savedWorkspace;
  Map<String, List<String>> _workspaceExpandedDirs = {};
  Map<String, bool> _workspaceRootExpanded = {};

  WorkspaceStore get _workspaceStore =>
      widget.workspaceStore ?? WorkspaceStore.instance;

  List<Project> get _workspace => [
    if (_savedWorkspace != null) widget.project else _browsing,
    for (final project in _workspaceProjects)
      if (!p.equals(
        project.path,
        _savedWorkspace != null ? widget.project.path : _browsing.path,
      ))
        project,
  ];

  List<FileNode> get _roots => [
    for (final project in _workspace)
      FileNode(path: project.path, name: project.name, isDir: true),
  ];

  Project _ownerOf(String path) {
    var owner = _browsing;
    var longestRoot = -1;
    for (final project in _workspace) {
      if ((p.equals(project.path, path) || p.isWithin(project.path, path)) &&
          project.path.length > longestRoot) {
        owner = project;
        longestRoot = project.path.length;
      }
    }
    return owner;
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    _searchController.dispose();
    super.dispose();
  }

  /// 外部要求刷新：重新读已展开目录，不动展开状态与滚动位置。
  void _onRefreshSignal() {
    if (!mounted) return;
    unawaited(_refresh());
  }

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onRefreshSignal);
    _applyWorkspaceState();
    // 恢复上次浏览的项目（失效则回落到当前项目）。
    // 先乐观地用记住的项目建树，再用异步校验纠正：`existsSync` 会在这里
    // 阻塞首帧，而这个判断只是选择根目录，不值得卡住动画。
    final remembered = widget.workspace != null || isMainStudioRelease
        ? null
        : widget.store.projectById(widget.store.lastBrowsedProjectId);
    _browsing = remembered ?? widget.project;
    _rebuildRoot();
    if (_savedWorkspace == null && !isMainStudioRelease) {
      // Legacy language-product behavior: an offline App's multi-root
      // membership still lives in that project's history.
      unawaited(_restoreLegacyWorkspace());
    }
    if (remembered != null && remembered.path != widget.project.path) {
      unawaited(_verifyBrowsing(remembered));
    }
  }

  @override
  void didUpdateWidget(covariant FileExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onRefreshSignal);
      widget.refreshSignal?.addListener(_onRefreshSignal);
    }
    final workspaceChanged = oldWidget.workspace?.id != widget.workspace?.id;
    final primaryChanged = !p.equals(
      oldWidget.project.path,
      widget.project.path,
    );
    final membersChanged = !_sameProjectPaths(
      oldWidget.workspaceMembers,
      widget.workspaceMembers,
    );
    if (!workspaceChanged && !membersChanged && !primaryChanged) {
      // A same-id rename must reach the next settings dialog and expansion
      // notification without rebuilding the live tree or resetting its scroll.
      if (!identical(oldWidget.workspace, widget.workspace)) {
        _savedWorkspace = widget.workspace;
      }
      return;
    }
    if (!workspaceChanged) {
      // Capture the outgoing live roots before the member list/primary moves,
      // otherwise the rebuild restores an already-cleared expansion state.
      _captureWorkspaceExpansion();
    }
    if (workspaceChanged) {
      _applyWorkspaceState();
      _browsing = widget.project;
    } else {
      _savedWorkspace = widget.workspace;
      _workspaceProjects = [
        for (final project in widget.workspaceMembers)
          if (!p.equals(project.path, widget.project.path)) project,
      ];
    }
    // The browsed root must stay a member: when the old primary A disappears
    // and the effective primary becomes B, browsing must follow to B instead
    // of keeping a root that is no longer part of the workspace.
    //
    // Membership comes from the resolved widget membership only. Deriving it
    // from `_workspace`/`_workspaceMembersOrdered` would be circular: those
    // include `_browsing`, so the stale root A would always look allowed.
    final allowed = [widget.project, ..._workspaceProjects];
    if (!allowed.any((project) => p.equals(project.path, _browsing.path))) {
      _browsing = widget.project;
    }
    setState(_rebuildRoot);
  }

  static bool _sameProjectPaths(List<Project> a, List<Project> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!p.equals(a[i].path, b[i].path)) return false;
    }
    return true;
  }

  void _applyWorkspaceState() {
    _workspaceSelectionRevision++;
    _savedWorkspace = widget.workspace;
    _workspaceProjects = [
      for (final project in widget.workspaceMembers)
        if (!p.equals(project.path, widget.project.path)) project,
    ];
    final expanded =
        widget.workspace?.session.expandedDirs ??
        const <String, List<String>>{};
    _workspaceExpandedDirs = {
      for (final entry in expanded.entries)
        entry.key: List<String>.of(entry.value),
    };
    _workspaceRootExpanded = {...?widget.workspace?.session.rootExpanded};
  }

  /// 校验记住的项目目录是否还在，已失效则回落到当前项目。
  Future<void> _verifyBrowsing(Project remembered) async {
    final generation = _treeGeneration;
    final exists = await Directory(remembered.path).exists();
    if (!mounted || generation != _treeGeneration || exists) return;
    setState(() => _browsing = widget.project);
    _rebuildRoot();
  }

  /// Guards legacy `history.json` membership restoration against a dialog that
  /// applied a newer selection while the load/stat work was still in flight.
  int _workspaceSelectionRevision = 0;

  /// Restores the legacy (language-product) membership stored in this
  /// project's `history.json`. The main release uses saved workspaces instead.
  Future<void> _restoreLegacyWorkspace() async {
    final revision = _workspaceSelectionRevision;
    final session = await ProjectHistory.load(widget.project.path);
    if (!mounted || revision != _workspaceSelectionRevision) return;
    final projects = <Project>[];
    for (final project in widget.store.projects) {
      if (project.isCloud ||
          !session.workspaceRoots.any((path) => p.equals(path, project.path))) {
        continue;
      }
      final exists = await Directory(project.path).exists();
      if (!mounted || revision != _workspaceSelectionRevision) return;
      if (exists) projects.add(project);
    }
    if (!mounted || revision != _workspaceSelectionRevision) return;
    if (projects.isEmpty) return;
    setState(() {
      _workspaceProjects = [
        for (final project in projects)
          if (!p.equals(project.path, widget.project.path)) project,
      ];
    });
    _rebuildRoot();
  }

  void _rebuildRoot() {
    _treeGeneration++;
    // 换了根目录，提示额度重置。
    _listingFailureShown = false;
    _listingFailurePath = null;
    _root = FileNode(path: _browsing.path, name: _browsing.name, isDir: true);
    _children.clear();
    _expanded
      ..clear()
      ..addAll(_roots.map((root) => root.path));
    for (final root in _roots) {
      unawaited(_loadChildren(root));
    }
    _restoring = Future.wait([
      for (final project in _workspace) _restoreExpanded(project),
    ]).then((_) {});
  }

  /// Explicitly saves or updates this editor's workspace.
  ///
  /// The dialog is available for a standalone project and for a single-project
  /// registry: a workspace can still be named and reopened from Home.
  Future<void> _manageWorkspace() async {
    if (_savedWorkspace == null &&
        supportsSavedWorkspaces &&
        widget.project.isCloud) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('仅本地项目可保存工作区，请先打开本地项目')));
      return;
    }
    if (_savedWorkspace == null && !supportsSavedWorkspaces) {
      if (!isMainStudioRelease) await _manageLegacyWorkspace();
      return;
    }
    final result = await showWorkspaceEditorDialog(
      context,
      workspaceStore: _workspaceStore,
      projectStore: widget.store,
      primary: widget.project,
      members: _workspaceMembersOrdered,
      saved: _savedWorkspace,
    );
    if (result == null || !mounted) return;
    _workspaceSelectionRevision++;
    if (result.deleted) {
      // Metadata only: project folders, history and open tabs stay untouched.
      setState(() {
        _savedWorkspace = null;
        _workspaceProjects = [];
        _workspaceExpandedDirs = {};
        _workspaceRootExpanded = {};
        _browsing = widget.project;
      });
      _rebuildRoot();
      widget.onWorkspaceChanged?.call(
        EditorWorkspaceState(saved: null, members: [widget.project]),
      );
      return;
    }
    final saved = result.workspace!;
    final members = _membersFor(saved);
    // Flush the outgoing roots before rebuilding so removing a root never
    // erases the expansion it should recover when added again.
    await _restoring;
    if (!mounted) return;
    // Merge, never replace: `_captureWorkspaceExpansion` overwrites only the
    // roots that are live right now, so an entry for a removed root survives
    // and a re-added root restores its previous expansion.
    _captureWorkspaceExpansion();
    setState(() {
      _savedWorkspace = saved;
      _workspaceProjects = [
        for (final project in members)
          if (!p.equals(project.path, widget.project.path)) project,
      ];
      _browsing = widget.project;
    });
    // Restore reads the merged map; only capture and save after it completes.
    _rebuildRoot();
    await _restoring;
    if (!mounted) return;
    _captureWorkspaceExpansion();
    _notifyWorkspace();
  }

  /// Language-product membership dialog, preserved from the pre-workspace
  /// contract: selection is applied immediately and stored in project history.
  Future<void> _manageLegacyWorkspace() async {
    final projects = widget.store.projects
        .where((project) => !project.isCloud)
        .toList(growable: false);
    final selected = {for (final project in _workspace) project.id};
    final result = await showDialog<List<Project>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('工作区项目'),
          content: SizedBox(
            width: 420,
            // Let AlertDialog scroll an intrinsically measurable project list.
            child: projects.isEmpty
                ? const Text('请先在项目列表添加本地项目。')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final project in projects)
                        CheckboxListTile(
                          key: ValueKey('workspace-project-${project.id}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(project.name),
                          subtitle: Text(project.path),
                          value: selected.contains(project.id),
                          onChanged: p.equals(project.path, _browsing.path)
                              ? null
                              : (value) => update(() {
                                  if (value == true) {
                                    selected.add(project.id);
                                  } else {
                                    selected.remove(project.id);
                                  }
                                }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [
                for (final project in projects)
                  if (selected.contains(project.id)) project,
              ]),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _restoring;
    if (!mounted) return;
    await _persistExpanded();
    if (!mounted) return;
    _workspaceSelectionRevision++;
    setState(() {
      _workspaceProjects = [
        for (final project in result)
          if (!p.equals(project.path, widget.project.path)) project,
      ];
    });
    unawaited(
      ProjectHistory.saveWorkspaceRoots(widget.project.path, [
        for (final project in result) project.path,
      ]),
    );
    _rebuildRoot();
  }

  List<Project> _membersFor(SavedWorkspace workspace) {
    final members = <Project>[];
    for (final member in workspace.members) {
      Project? match;
      for (final project in widget.store.projects) {
        if (project.id == member.projectId) {
          match = project;
          break;
        }
      }
      if (match == null) {
        final key = workspacePathKey(member.path);
        for (final project in widget.store.projects) {
          if (workspacePathKey(project.path) == key) {
            match = project;
            break;
          }
        }
      }
      if (match == null || match.isCloud) continue;
      if (members.any((project) => p.equals(project.path, match!.path))) {
        continue;
      }
      members.add(match);
    }
    if (!members.any(
      (project) => p.equals(project.path, widget.project.path),
    )) {
      members.insert(0, widget.project);
    }
    return members;
  }

  /// Ordered members with the editor's primary root first.
  List<Project> get _workspaceMembersOrdered => [
    widget.project,
    for (final project in _workspace)
      if (!p.equals(project.path, widget.project.path)) project,
  ];

  /// Merges the live roots' expansion into the saved maps.
  ///
  /// Entries for roots that are not mounted right now (a member that was
  /// removed, or one that has not been restored yet) are preserved so that
  /// removing and re-adding a root recovers its previous expansion. Only the
  /// roots that are actually displayed are overwritten.
  void _captureWorkspaceExpansion() {
    final expanded = Map<String, List<String>>.of(_workspaceExpandedDirs);
    final roots = Map<String, bool>.of(_workspaceRootExpanded);
    for (final project in _workspace) {
      final expandedKey = _sessionKey(expanded, project.path) ?? project.path;
      expanded[expandedKey] = [
        for (final path in _expanded)
          if (!p.equals(project.path, path) && p.isWithin(project.path, path))
            p.relative(path, from: project.path).replaceAll(r'\', '/'),
      ];
      final rootKey = _sessionKey(roots, project.path) ?? project.path;
      roots[rootKey] = _expanded.contains(project.path);
    }
    _workspaceExpandedDirs = expanded;
    _workspaceRootExpanded = roots;
  }

  void _notifyWorkspace() {
    final saved = _savedWorkspace;
    if (saved == null) return;
    widget.onWorkspaceChanged?.call(
      EditorWorkspaceState(
        saved: saved,
        members: _workspaceMembersOrdered,
        expandedDirs: _workspaceExpandedDirs,
        rootExpanded: _workspaceRootExpanded,
      ),
    );
  }

  /// 多选项目加入当前工作区。
  ///
  /// 已有成员默认勾上且不可取消，选中非成员后批量加入、持久化、刷新树；
  /// 不会暗中移除成员。
  Future<void> _pickProjectsToAddToWorkspace() async {
    final saved = _savedWorkspace;
    if (saved == null) return;
    final members = _workspaceMembersOrdered;
    final memberKeys = {for (final p in members) workspacePathKey(p.path)};
    final candidates = widget.store.projects
        .where(
          (project) =>
              !project.isCloud &&
              !memberKeys.contains(workspacePathKey(project.path)),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可加入的本地项目')));
      return;
    }
    final picked = await showDialog<List<Project>>(
      context: context,
      builder: (context) =>
          _AddProjectsDialog(members: members, candidates: candidates),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _addProjectsToWorkspace(picked);
  }

  /// The project picker only changes which tree is browsed.
  ///
  /// A normal session keeps its project and the Agent session on the edited
  /// project; browsing another project is temporary, matching the original
  /// cross-project file-open behaviour. Inside a saved workspace it is also a
  /// temporary browse when the target is a member, and a non-member is offered
  /// for addition to the workspace instead of silently navigating away.
  void _switchProject(Project project) {
    if (workspacePathKey(project.path) == workspacePathKey(_browsing.path)) {
      return;
    }
    if (_savedWorkspace != null) {
      final member = _workspace.any(
        (candidate) =>
            workspacePathKey(candidate.path) == workspacePathKey(project.path),
      );
      if (member) {
        setState(() {
          _browsing = project;
          _root = FileNode(path: project.path, name: project.name, isDir: true);
        });
        widget.store.setBrowsedProject(project);
      } else {
        unawaited(_addProjectsToWorkspace([project]));
      }
      return;
    }
    // Plain project session: never navigate, never change which project the
    // editor and the Agent belong to.
    setState(() {
      _browsing = project;
      _rebuildRoot();
    });
    widget.store.setBrowsedProject(project);
  }

  /// Offers the tapped non-member for addition to the saved workspace.
  ///
  /// One dialog, one write: the multi-select picker's confirm goes straight to
  /// [WorkspaceStore.addMembers], which only appends. Identity, name, member
  /// order, missing members and session data are kept; nothing is removed and no
  /// second naming/removal dialog is opened.
  Future<void> _addProjectsToWorkspace(List<Project> projects) async {
    final saved = _savedWorkspace;
    if (saved == null || projects.isEmpty) return;
    final existing = {for (final p in _workspace) workspacePathKey(p.path)};
    final additions = [
      for (final project in projects)
        if (!existing.contains(workspacePathKey(project.path))) project,
    ];
    if (additions.isEmpty) return;
    SavedWorkspace? merged;
    try {
      merged = await _workspaceStore.addMembers(saved.id, additions);
    } catch (_) {
      merged = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加入工作区失败：无法保存工作区记录')));
      }
      return;
    }
    if (!mounted) return;
    if (merged == null) {
      // 记录已被删除：不能假装成功。
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加入失败：该工作区记录已被删除')));
      return;
    }
    if (merged.members.length == _workspace.length) {
      // 没有任何新成员落盘，不要给出成功的错觉。
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('所选项目都已在该工作区里')));
      return;
    }
    final members = _membersFor(merged);
    await _restoring;
    if (!mounted) return;
    _captureWorkspaceExpansion();
    setState(() {
      _savedWorkspace = merged;
      _workspaceProjects = [
        for (final project in members)
          if (!p.equals(project.path, widget.project.path)) project,
      ];
    });
    _rebuildRoot();
    await _restoring;
    if (!mounted) return;
    _captureWorkspaceExpansion();
    _notifyWorkspace();
  }

  /// Finds the stored key for [path] in a workspace session map, tolerating
  /// Windows path casing and separator differences.
  String? _sessionKey(Map<String, Object?> map, String path) {
    final key = workspacePathKey(path);
    for (final candidate in map.keys) {
      if (workspacePathKey(candidate) == key) return candidate;
    }
    return null;
  }

  /// Restores this root's expansion.
  ///
  /// A saved workspace owns its expansion in the workspace document; a
  /// standalone project keeps using its own `history.json`.
  Future<void> _restoreExpanded(Project project) async {
    final generation = _treeGeneration;
    final projectPath = project.path;
    final saved = _savedWorkspace;
    if (saved != null) {
      final expandedKey = _sessionKey(_workspaceExpandedDirs, projectPath);
      final rootKey = _sessionKey(_workspaceRootExpanded, projectPath);
      if (rootKey != null && _workspaceRootExpanded[rootKey] == false) {
        _expanded.remove(projectPath);
      }
      for (final rel
          in expandedKey == null
              ? const <String>[]
              : _workspaceExpandedDirs[expandedKey]!) {
        final abs = p.normalize(
          p.isAbsolute(rel) ? rel : p.join(projectPath, rel),
        );
        if (!p.isWithin(projectPath, abs)) continue;
        final exists = await Directory(abs).exists();
        if (!mounted || generation != _treeGeneration) return;
        if (!exists) continue;
        _expanded.add(abs);
        if (!_children.containsKey(abs)) {
          unawaited(
            _loadChildren(
              FileNode(path: abs, name: p.basename(abs), isDir: true),
              generation: generation,
            ),
          );
        }
      }
      if (mounted) setState(() {});
      return;
    }
    final session = await ProjectHistory.load(projectPath);
    if (!mounted || generation != _treeGeneration) return;
    if (!session.treeRootExpanded) _expanded.remove(projectPath);
    for (final rel in session.expandedDirs) {
      final abs = p.normalize(
        p.isAbsolute(rel) ? rel : p.join(projectPath, rel),
      );
      if (!p.isWithin(projectPath, abs)) continue;
      final exists = await Directory(abs).exists();
      if (!mounted || generation != _treeGeneration) return;
      if (!exists) continue;
      _expanded.add(abs);
      if (!_children.containsKey(abs)) {
        unawaited(
          _loadChildren(
            FileNode(path: abs, name: p.basename(abs), isDir: true),
            generation: generation,
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  /// 展开状态持久化。
  Future<void> _persistExpanded() async {
    if (_savedWorkspace != null) {
      _captureWorkspaceExpansion();
      _notifyWorkspace();
      return;
    }
    if (!isMainStudioRelease) {
      // Legacy language products keep per-root expansion in project history.
      await Future.wait([
        for (final project in _workspace)
          ProjectHistory.saveExpandedDirs(project.path, [
            for (final path in _expanded)
              if (p.isWithin(project.path, path))
                p.relative(path, from: project.path).replaceAll(r'\', '/'),
          ], treeRootExpanded: _expanded.contains(project.path)),
      ]);
      return;
    }
    await ProjectHistory.saveExpandedDirs(
      widget.project.path,
      [
        for (final path in _expanded)
          if (p.isWithin(widget.project.path, path))
            p.relative(path, from: widget.project.path).replaceAll(r'\', '/'),
      ],
      treeRootExpanded: _expanded.contains(widget.project.path),
    );
  }

  List<FileNode> _childrenOf(FileNode dir) => _children[dir.path] ?? const [];

  /// 外部根的目录读不到时提示一次，不把失败藏成空目录。
  void _showListingFailure(String path) {
    if (_listingFailureShown) return;
    _listingFailureShown = true;
    _listingFailurePath = path;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('外部文件夹暂时读不到：${p.basename(path)}')));
  }

  /// 报过错的那一层恢复成功后，重新允许下一次提示。
  void _clearListingFailure(String path) {
    if (!_listingFailureShown || _listingFailurePath != path) return;
    _listingFailureShown = false;
    _listingFailurePath = null;
  }

  /// 打开搜索命中的文件（成功后收起侧栏/抽屉，与树内打开一致）。
  Future<void> _openSearchResult(String path) async {
    final owner = _ownerOf(path);
    final error = await widget.editor.openPath(
      path,
      ownerProjectName: owner.name,
      ownerProjectPath: owner.path,
      ownerProjectType: owner.type,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onFileOpened?.call();
  }

  Future<void> _loadChildren(FileNode dir, {int? generation}) async {
    final expectedGeneration = generation ?? _treeGeneration;
    List<FileNode> nodes = const [];
    var listed = false;
    try {
      // Async listing: a project directory can hold thousands of entries, and
      // the sync form blocks the isolate that is also driving the page
      // transition.
      final entities = await FileService.listSorted(dir.path);
      nodes = [
        for (final entity in entities)
          FileNode(
            path: entity.path,
            name: p.basename(entity.path),
            isDir: entity is Directory,
          ),
      ];
      listed = true;
    } on FileSystemException {
      nodes = const [];
    } on PlatformException {
      // 原生返回错误（权限被收回、书签失效）。保留旧节点并报一次。
      nodes = _children[dir.path] ?? const [];
      if (mounted && expectedGeneration == _treeGeneration) {
        _showListingFailure(dir.path);
      }
    } on StateError {
      // 外部根的列表由原生提供。原生没就绪时不能把空列表当成
      // 「这层目录什么都没有」——那样读取、新建都看不出真实的权限失败。
      // 保留上一次的节点，并把失败告诉用户。
      nodes = _children[dir.path] ?? const [];
      if (mounted && expectedGeneration == _treeGeneration) {
        _showListingFailure(dir.path);
      }
    }
    if (!mounted || expectedGeneration != _treeGeneration) return;
    // 只有真正读到才重置提示额度。放在 catch 之后无条件执行，
    // 会让失败当场就把额度重新武装，提示永远不只一次。
    if (listed) {
      _clearListingFailure(dir.path);
      // 列表读成功才能判定哪些子项已经不在了。失败时不能动缓存，
      // 否则下一层会拿着旧路径去读已经不存在的目录。
      _pruneStaleDescendants(dir.path, nodes);
    }
    setState(() => _children[dir.path] = nodes);
  }

  /// 目录读成功后，丢掉已经不存在的下一层缓存。
  ///
  /// 只在父层拿到可信列表时调用。失败路径不碰缓存，
  /// 保证「读不到」时旧节点还能继续显示。
  void _pruneStaleDescendants(String dirPath, List<FileNode> children) {
    final alive = <String>{
      for (final child in children)
        if (child.isDir) child.path,
    };
    final removed = _children.keys
        .where((path) => p.dirname(path) == dirPath && !alive.contains(path))
        .toList();
    bool isRemoved(String path) =>
        removed.any((root) => p.equals(root, path) || p.isWithin(root, path));
    _children.removeWhere((path, _) => isRemoved(path));
    _expanded.removeWhere(isRemoved);
  }

  Future<void> _refresh() async {
    final generation = _treeGeneration;
    for (final root in _roots) {
      await _loadChildren(root, generation: generation);
      if (!mounted || generation != _treeGeneration) return;
    }
    for (final path in _expanded.toList()) {
      if (_roots.any((root) => p.equals(root.path, path))) continue;
      await _loadChildren(
        FileNode(path: path, name: p.basename(path), isDir: true),
        generation: generation,
      );
      if (!mounted || generation != _treeGeneration) return;
    }
  }

  Future<void> _importResources(
    FileNode directory, {
    required bool photos,
  }) async {
    final documents = <PickedDocument>[];
    if (photos) {
      documents.addAll(await PickerService.pickPhotos());
    } else {
      final document = await PickerService.pickDocument(extensions: const []);
      if (document != null) documents.add(document);
    }
    if (documents.isEmpty || !mounted) return;
    final l = StudioLocalizations.of(context);
    final result = await ResourceImportService.importDocuments(
      documents: documents,
      destinationDirectory: directory.path,
      resolveConflict: (name) async =>
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l.replaceExistingResource),
              content: Text(l.replaceResourceMessage(name)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l.replaceResource),
                ),
              ],
            ),
          ) ??
          false,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    if (result.imported > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.importFinished(result.imported))),
      );
    }
    if (result.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.importFailed}${result.errors.join('; ')}')),
      );
    }
  }

  Future<void> _toggle(FileNode node) async {
    final generation = _treeGeneration;
    // Apply a tap after restoration so it cannot be undone by a late restore,
    // or persist an incomplete set while the saved directories are loading.
    await _restoring;
    if (!mounted || generation != _treeGeneration) return;
    if (_expanded.remove(node.path)) {
      setState(() {});
      unawaited(_persistExpanded());
      return;
    }
    _expanded.add(node.path);
    if (!_children.containsKey(node.path)) _loadChildren(node);
    setState(() {});
    unawaited(_persistExpanded());
  }

  Future<void> _openFile(FileNode node) async {
    final owner = _ownerOf(node.path);
    final error = await widget.editor.openPath(
      node.path,
      ownerProjectName: owner.name,
      ownerProjectPath: owner.path,
      ownerProjectType: owner.type,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onFileOpened?.call();
  }

  Future<void> _create(FileNode? dirNode, bool isDir) async {
    final generation = _treeGeneration;
    final dirPath = dirNode?.path ?? _root.path;
    final owner = _ownerOf(dirPath);
    final String? name;
    if (isDir) {
      name = await showNewNameDialog(
        context,
        title: '新建文件夹',
        actionLabel: '创建',
        actionIcon: Icons.create_new_folder_outlined,
      );
    } else {
      name = await showNewFileDialog(
        context,
        settings: widget.settings,
        projectLanguage: owner.language,
      );
    }
    if (name == null || !mounted) return;
    final path = p.join(dirPath, name);
    final external = ProjectFileAccess.isExternal(path);
    if (!external &&
        (Directory(path).existsSync() || File(path).existsSync())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('“$name”已存在')));
      return;
    }
    try {
      if (isDir) {
        await Directory(path).create();
      } else if (external) {
        // 外部根新建文件走协调写入：占位目录要靠原生触发下载。
        await ProjectFileAccess.writeBytes(path, const <int>[]);
      } else {
        await File(path).writeAsString('');
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建失败：${e.message}')));
      }
      return;
    }
    await _restoring;
    if (!mounted || generation != _treeGeneration) return;
    _expanded.add(dirPath);
    unawaited(_persistExpanded());
    await _loadChildren(
      FileNode(path: dirPath, name: p.basename(dirPath), isDir: true),
    );
    if (mounted && generation == _treeGeneration && !isDir) {
      await _openFile(FileNode(path: path, name: name, isDir: false));
    }
  }

  Future<void> _delete(FileNode node) async {
    final owner = _ownerOf(node.path);
    final confirmed = await showDeleteEntryConfirm(
      context,
      name: node.name,
      isFolder: node.isDir,
    );
    if (!confirmed || !mounted) return;
    // 先压缩备份到回收站 files_bin，失败则中止删除。
    final backupError = await RecycleBin.backupEntry(
      node.isDir ? Directory(node.path) : File(node.path),
      projectName: owner.name,
    );
    if (backupError != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已取消删除：$backupError')));
      }
      return;
    }
    try {
      final entity = node.isDir
          ? Directory(node.path)
          : File(node.path) as FileSystemEntity;
      await entity.delete(recursive: true);
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：${e.message}')));
      }
      return;
    }
    // Backup/deletion may finish after the entire editor has been disposed.
    if (!mounted) return;
    widget.editor.closePathsUnder(node.path);
    if (p.isWithin(widget.project.path, node.path)) {
      widget.onEntryDeleted?.call(node.path);
    }
    final parentPath = p.dirname(node.path);
    await _loadChildren(
      FileNode(path: parentPath, name: p.basename(parentPath), isDir: true),
    );
  }

  void _showMenu(FileNode node, Offset position) {
    final isRoot = _roots.any((root) => p.equals(node.path, root.path));
    final owner = _ownerOf(node.path);
    // 外部根是用户自己的目录：不提供删除，用户要删就回系统文件管理器。
    final external = ProjectFileAccess.isExternal(node.path);
    final l = StudioLocalizations.of(context);
    final items = <PopupMenuEntry<String>>[
      if (!node.isDir)
        const PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 10),
              Text('打开'),
            ],
          ),
        ),
      if (node.isDir) ...[
        PopupMenuItem(
          value: 'import_resource',
          child: Row(
            children: [
              const Icon(Icons.file_upload_outlined, size: 18),
              const SizedBox(width: 10),
              Text(l.importResource),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import_photo',
          child: Row(
            children: [
              const Icon(Icons.photo_library_outlined, size: 18),
              const SizedBox(width: 10),
              Text(l.importPhoto),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_file',
          child: Row(
            children: [
              Icon(Icons.note_add_outlined, size: 18),
              SizedBox(width: 10),
              Text('新建文件'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_folder',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 18),
              SizedBox(width: 10),
              Text('新建文件夹'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 10),
              Text('刷新'),
            ],
          ),
        ),
      ],
      if (!node.isDir)
        const PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              Icon(Icons.history, size: 18),
              SizedBox(width: 10),
              Text('历史版本'),
            ],
          ),
        ),
      if (widget.onShareEntry != null)
        const PopupMenuItem(
          value: 'share_zip',
          child: Row(
            children: [
              Icon(Icons.folder_zip_outlined, size: 18),
              SizedBox(width: 10),
              Text('ZIP 分享'),
            ],
          ),
        ),
      if (!isRoot && !external)
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 10),
              Text('删除'),
            ],
          ),
        ),
    ];
    if (items.isEmpty) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'open':
          _openFile(node);
        case 'new_file':
          _create(node, false);
        case 'new_folder':
          _create(node, true);
        case 'import_resource':
          _importResources(node, photos: false);
        case 'import_photo':
          _importResources(node, photos: true);
        case 'refresh':
          _loadChildren(node);
        case 'delete':
          _delete(node);
        case 'share_zip':
          unawaited(widget.onShareEntry!(owner, node.path));
        case 'history':
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FileHistoryPage(
                originalPath: node.path,
                projectName: owner.name,
                projectPath: owner.path,
                onOpenVersion: (backupFile, timeLabel) {
                  widget.editor
                      .openPath(
                        backupFile.path,
                        ownerProjectName: owner.name,
                        ownerProjectPath: owner.path,
                        readOnly: true,
                        timeLabel: timeLabel,
                      )
                      .then((error) {
                        if (error != null && mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(error)));
                        }
                      });
                },
                onRestored: () async {
                  // 恢复后刷新原文件内容（已打开的普通标签）。
                  final idx = widget.editor.files.indexWhere(
                    (f) => p.equals(f.path, node.path),
                  );
                  if (idx >= 0 && !widget.editor.files[idx].readOnly) {
                    widget.editor.files[idx].controller.text = await File(
                      node.path,
                    ).readAsString();
                  }
                },
              ),
            ),
          );
      }
    });
  }

  Widget _buildSearchResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paths = <String>{};
    final results = [
      for (final project in _workspace)
        for (final node in FileExplorer.searchFiles(project.path, _searchQuery))
          if (paths.add(p.canonicalize(node.path))) node,
    ].take(200).toList(growable: false);
    if (results.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的文件',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final node = results[i];
        final owner = _ownerOf(node.path);
        final rel = p.isWithin(owner.path, node.path)
            ? p.relative(node.path, from: owner.path).replaceAll(r'\', '/')
            : node.path;
        if (widget.largeScreen) {
          return Tooltip(message: rel, child: _buildRow(context, node, 0));
        }
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            FileService.iconForFile(node.name),
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Text(
            _workspace.length > 1 ? '${owner.name}/$rel' : rel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          onTap: () => _openSearchResult(node.path),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = widget.largeScreen
        ? ListenableBuilder(
            listenable: widget.editor,
            builder: (context, _) => _buildBody(context, scheme),
          )
        : _buildBody(context, scheme);
    if (widget.largeScreen) {
      return Material(color: scheme.surfaceContainerLow, child: body);
    }
    if (!widget.outlined) {
      return ColoredBox(color: scheme.surfaceContainerLow, child: body);
    }
    // MaterialCardView outlined：圆角表面 + outlineVariant 细描边，无阴影。
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
      child: body,
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    final sections = widget.sections;
    if (sections == null) return _buildBodyContent(context, scheme, null);
    return AnimatedBuilder(
      animation: sections.state,
      builder: (context, _) => _buildBodyContent(context, scheme, sections),
    );
  }

  Widget _buildBodyContent(
    BuildContext context,
    ColorScheme scheme,
    FileExplorerSections? sections,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            // Grows instead of clipping when large text needs more than 48px,
            // so short panels only give up space from the tree below.
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                const SizedBox(width: 4),
                // 项目选择器在最左，开着标题栏剩余宽度。
                Expanded(child: _buildHeaderTitle(context, scheme, sections)),
                ..._buildHeaderActions(context, sections, constraints.maxWidth),
                // 文件/会话切换固定在右端，和动作按钮同一个尺寸。
                if (widget.headerTrailing case final trailing?) ...[trailing],
                const SizedBox(width: 4),
              ],
            ),
          ),
          // Always visible: saving a workspace must stay reachable even when
          // the panel is short and the registry has a single project.
          if (sections == null ||
              sections.state.sidebarSection == SidebarSection.files)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      _savedWorkspace == null
                          ? Icons.folder_copy_outlined
                          : Icons.workspaces_outline,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _savedWorkspace == null
                            ? '工作区 · ${_workspace.length} 个项目'
                            : '${_savedWorkspace!.name} · ${_workspace.length} 个项目',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '工作区项目',
                      icon: const Icon(Icons.tune, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed:
                          _savedWorkspace != null ||
                              supportsSavedWorkspaces ||
                              !isMainStudioRelease
                          ? _manageWorkspace
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          Expanded(child: _buildPanelBody(context, sections)),
        ],
      ),
    );
  }

  /// 共享标题栏左侧的主标题：文件段是项目选择器，会话段是会话标题。
  ///
  /// 两段用同一条左侧线、同一个字号：[_headerTitleInset] 与 `labelLarge`。
  /// 切段时标题不跳位。
  Widget _buildHeaderTitle(
    BuildContext context,
    ColorScheme scheme,
    FileExplorerSections? sections,
  ) {
    if (sections != null &&
        sections.state.sidebarSection == SidebarSection.sessions) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _headerTitleInset),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '会话',
            key: const ValueKey('sidebar-sessions-title'),
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (_savedWorkspace != null) {
      // 工作区里直接开多选：不再先弹菜单再嵌一层选项目。
      return Tooltip(
        message: '选择项目加入当前工作区',
        child: InkWell(
          key: const ValueKey('file-explorer-project-picker'),
          onTap: () => unawaited(_pickProjectsToAddToWorkspace()),
          borderRadius: BorderRadius.circular(8),
          child: _buildTitleChip(context, scheme),
        ),
      );
    }
    return PopupMenuButton<Project>(
      key: const ValueKey('file-explorer-project-picker'),
      tooltip: '浏览项目（跨项目打开文件）',
      onSelected: _switchProject,
      itemBuilder: (context) => [
        for (final p in widget.store.projects)
          PopupMenuItem<Project>(
            value: p,
            child: Row(
              children: [
                Icon(
                  p.isCloud ? Icons.cloud_outlined : Icons.folder_outlined,
                  size: 18,
                  color: p.path == _browsing.path
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (p.path == _browsing.path)
                  Icon(Icons.check, size: 16, color: scheme.primary),
              ],
            ),
          ),
      ],
      child: _buildTitleChip(context, scheme),
    );
  }

  Widget _buildTitleChip(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _headerTitleInset,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _browsing.name,
              style: Theme.of(context).textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 工作区里点标题是多选加入，不适合再挂一个“下拉”箭头。
          if (_savedWorkspace == null)
            const Icon(Icons.arrow_drop_down, size: 18)
          else
            const Icon(Icons.playlist_add, size: 18),
        ],
      ),
    );
  }

  /// 共享标题栏右侧的动作：跟随当前分段，文件动作与会话动作互不混杂。
  ///
  /// 宽度不够时（如 280 宽的持久侧边栏）只留新建文件和搜索，新建文件夹与
  /// 刷新收进带文字的溢出菜单，以免项目选择器被挤到不可用。所有操作仍可达。
  List<Widget> _buildHeaderActions(
    BuildContext context,
    FileExplorerSections? sections,
    double availableWidth,
  ) {
    if (sections != null &&
        sections.state.sidebarSection == SidebarSection.sessions) {
      return [
        if (sections.onNewSession != null)
          _headerAction(
            key: const ValueKey('session-new'),
            tooltip: '新会话',
            icon: Icons.add_comment_outlined,
            onPressed: sections.onNewSession!,
          ),
        if (sections.onStopAllSessions != null)
          _headerMenu(
            key: const ValueKey('session-list-menu'),
            tooltip: '会话操作',
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'stop_all', height: 44, child: Text('全部停止')),
            ],
            onSelected: (action) {
              if (action == 'stop_all') sections.onStopAllSessions!();
            },
          ),
      ];
    }
    // 动作预算从实际可用宽度算：减去左右内边距、右端切换按钮和项目选择器
    // 的最小宽度，剩下的才是按钮能用的空间。每个按钮（含溢出）44。
    const horizontalChrome = 4.0 + 4.0; // 左内边距 + 右内边距
    const pickerFloor = 96.0;
    // 右端切换按钮就是一个 44 的动作按钮。
    final switchWidth = widget.headerTrailing == null ? 0.0 : 44.0;
    final actionBudget =
        availableWidth - horizontalChrome - switchWidth - pickerFloor;
    // 四个动作都就地放：新建文件、新建文件夹、搜索、刷新。
    const fullActions = 44.0 * 4;
    final fitsAll = actionBudget >= fullActions;
    // 三个触摸目标：新建文件 + 搜索 + 溢出菜单。
    const compactActions = 44.0 * 3;
    final ultraCompact = actionBudget < compactActions;
    final compact = !fitsAll;
    return [
      _headerAction(
        tooltip: '新建文件',
        icon: Icons.note_add_outlined,
        onPressed: () => _create(null, false),
      ),
      if (!ultraCompact)
        _headerAction(
          tooltip: _searchOpen ? '退出搜索' : '搜索文件',
          icon: _searchOpen ? Icons.close : Icons.search,
          onPressed: () {
            setState(() {
              _searchOpen = !_searchOpen;
              _searchQuery = '';
              _searchController.clear();
            });
          },
        ),
      if (compact)
        _headerMenu(
          key: const ValueKey('file-explorer-more'),
          tooltip: '更多文件操作',
          itemBuilder: (context) => [
            if (ultraCompact)
              const PopupMenuItem(
                value: 'search',
                height: 44,
                child: Text('搜索文件'),
              ),
            const PopupMenuItem(
              value: 'new-folder',
              height: 44,
              child: Text('新建文件夹'),
            ),
            const PopupMenuItem(
              value: 'refresh',
              height: 44,
              child: Text('刷新'),
            ),
          ],
          onSelected: (action) {
            if (action == 'search') {
              setState(() {
                _searchOpen = true;
                _searchQuery = '';
                _searchController.clear();
              });
            }
            if (action == 'new-folder') _create(null, true);
            if (action == 'refresh') _refresh();
          },
        )
      else ...[
        _headerAction(
          tooltip: '新建文件夹',
          icon: Icons.create_new_folder_outlined,
          onPressed: () => _create(null, true),
        ),
        _headerAction(tooltip: '刷新', icon: Icons.refresh, onPressed: _refresh),
      ],
    ];
  }

  /// 标题栏动作的统一几何：44×44 触摸盒、零内边距、标准密度。
  ///
  /// 同时用于 [IconButton] 和 [PopupMenuButton]（后者内部就是 IconButton）。
  /// 两种模式下尺寸、内边距、对齐都一致，按钮不会因为模式不同而跳动。
  static const ButtonStyle _headerActionStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(44, 44)),
    maximumSize: WidgetStatePropertyAll(Size(44, 44)),
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    alignment: Alignment.center,
  );

  /// 标题栏里的图标动作按钮。几何由 [_headerActionStyle] 统一。
  Widget _headerAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Key? key,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 20,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: _headerActionStyle,
      icon: Icon(icon),
    );
  }

  /// 标题栏里的溢出菜单按钮。几何与图标动作完全一致。
  Widget _headerMenu({
    required Key key,
    required String tooltip,
    required List<PopupMenuEntry<String>> Function(BuildContext) itemBuilder,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      key: key,
      tooltip: tooltip,
      itemBuilder: itemBuilder,
      onSelected: onSelected,
      iconSize: 20,
      padding: EdgeInsets.zero,
      style: _headerActionStyle,
      icon: const Icon(Icons.more_vert),
    );
  }

  /// 卡片主体：文件段是文件树，会话段是会话列表。
  Widget _buildPanelBody(BuildContext context, FileExplorerSections? sections) {
    if (sections != null &&
        sections.state.sidebarSection == SidebarSection.sessions) {
      return sections.sessions ??
          const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                hintText: '按文件名搜索（含子目录）',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        Expanded(
          child: _searchOpen && _searchQuery.trim().isNotEmpty
              ? _buildSearchResults(context)
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapUp: (details) =>
                      _showMenu(_root, details.globalPosition),
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.largeScreen ? 2 : 8,
                    ),
                    children: [
                      for (final root in _roots)
                        KeyedSubtree(
                          key: ValueKey('workspace-root-${root.path}'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildRow(context, root, 0),
                              if (_expanded.contains(root.path))
                                for (final node in _childrenOf(root))
                                  _buildNode(context, node, 1),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 标题行里的紧凑动作按钮。
  Widget _buildNode(BuildContext context, FileNode node, int depth) {
    final expanded = node.isDir && _expanded.contains(node.path);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(context, node, depth),
        if (expanded)
          for (final child in _childrenOf(node))
            _buildNode(context, child, depth + 1),
      ],
    );
  }

  Widget _buildRow(BuildContext context, FileNode node, int depth) {
    final scheme = Theme.of(context).colorScheme;
    final selected = !node.isDir && widget.editor.current?.path == node.path;
    final dirty = !node.isDir && widget.editor.isDirty(node.path);
    final row = GestureDetector(
      key: ValueKey('file-row-${node.path}'),
      onLongPressStart: (details) => _showMenu(node, details.globalPosition),
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? widget.largeScreen
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.6)
              : null,
          borderRadius: widget.largeScreen
              ? BorderRadius.zero
              : BorderRadius.circular(8),
        ),
        child: InkWell(
          mouseCursor: widget.largeScreen ? SystemMouseCursors.click : null,
          hoverColor: widget.largeScreen
              ? scheme.onSurface.withValues(alpha: 0.08)
              : null,
          highlightColor: widget.largeScreen
              ? scheme.onSurface.withValues(alpha: 0.10)
              : null,
          focusColor: widget.largeScreen
              ? scheme.onSurface.withValues(alpha: 0.10)
              : null,
          onTap: () {
            if (node.isDir) {
              _toggle(node);
            } else {
              _openFile(node);
            }
          },
          onSecondaryTapUp: (details) =>
              _showMenu(node, details.globalPosition),
          child: ConstrainedBox(
            // Tree rows grow with the text scale; a fixed 34px row overflowed
            // by a couple of pixels at 2.0x on short panels.
            constraints: BoxConstraints(
              minHeight: widget.largeScreen
                  ? (LargeScreenScope.isDesktop(context) ? 28 : 40)
                  : 34,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: widget.largeScreen
                    ? (LargeScreenScope.isDesktop(context) ? 0 : 3)
                    : 3,
              ),
              child: Row(
                children: [
                  SizedBox(width: 8.0 + depth * 18.0),
                  if (node.isDir)
                    Icon(
                      _expanded.contains(node.path)
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    )
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 2),
                  Icon(
                    node.isDir
                        ? (_expanded.contains(node.path)
                              ? Icons.folder_open
                              : Icons.folder_outlined)
                        : FileService.iconForFile(node.name),
                    size: 18,
                    color: node.isDir
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: depth == 0 ? FontWeight.w600 : null,
                        color: node.isDir
                            ? scheme.onSurface
                            : (selected
                                  ? widget.largeScreen
                                        ? scheme.onSecondaryContainer
                                        : scheme.onSurface
                                  : scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  if (dirty)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.largeScreen ? 0 : 4),
      child: row,
    );
  }
}

/// 多选项目加入工作区。已有成员固定勾选且不可取消，所以只会新增。
class _AddProjectsDialog extends StatefulWidget {
  const _AddProjectsDialog({required this.members, required this.candidates});

  final List<Project> members;
  final List<Project> candidates;

  @override
  State<_AddProjectsDialog> createState() => _AddProjectsDialogState();
}

class _AddProjectsDialogState extends State<_AddProjectsDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('加入当前工作区'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '已有成员保持不变。勾选要加入的项目后确认。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final member in widget.members)
              CheckboxListTile(
                key: ValueKey('workspace-existing-${member.id}'),
                contentPadding: EdgeInsets.zero,
                value: true,
                onChanged: null,
                title: Text(member.name),
              ),
            for (final project in widget.candidates)
              CheckboxListTile(
                key: ValueKey('workspace-add-${project.id}'),
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(project.path),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selected.add(project.path);
                  } else {
                    _selected.remove(project.path);
                  }
                }),
                title: Text(project.name),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('workspace-add-confirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                  for (final project in widget.candidates)
                    if (_selected.contains(project.path)) project,
                ]),
          child: const Text('加入'),
        ),
      ],
    );
  }
}
