import 'dart:async';
import 'dart:io';

import 'package:qfli_studio_core/editor/editor_page_diag.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../config/ohos_platform.dart';
import '../models/project.dart';
import '../pages/git_page.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../community/community_widgets.dart';
import 'editor_delete_fix.dart';
import 'editor_selection_toolbar.dart';
import '../services/cloud_sync_service.dart';
import '../services/file_encoding.dart';
import '../services/code_formatter.dart';
import '../services/local_web_server.dart';
import '../services/runner_service.dart';
import '../services/online_program.dart';
import '../services/share_service.dart';
import '../services/studio_profile.dart';
import '../services/web_preview_file.dart';
import '../services/task_activity_service.dart';
import '../widgets/retained_page.dart';
import '../workspace/editor_workspace.dart';
import '../workspace/saved_workspace.dart';
import '../workspace/workspace_store.dart';
import 'editor_fonts.dart';
import 'code_minimap.dart';
import 'symbols_bar.dart';
import 'editor_controller.dart';
import 'editor_analysis_controller.dart';
import 'editor_bottom_inset.dart';
import 'editor_debug_controller.dart';
import 'editor_debug_widgets.dart';
import 'editor_output_panel.dart';
import 'editor_diagnostics.dart';
import 'editor_find_panel.dart';
import 'file_explorer.dart';
import 'highlight_themes.dart';
import 'open_file.dart';
import 'editor_problems_bar.dart';
import 'project_history.dart';
import 'terminal_pane.dart';
import 'package:flutter/scheduler.dart';

import '../pages/settings_page.dart';
import '../pages/content_tools_pages.dart';
import '../services/local_audit_service.dart';
import '../services/local_stats_service.dart';
import '../services/picker_service.dart';
import 'ai_panel.dart';
import 'open_performance.dart';
import '../interop/interop_run_dialog.dart';
import '../interop/interop_sibling_memory.dart';
import '../interop/interop_targets.dart';
import '../layout/breakpoints.dart';
import '../shell/login_gate.dart';
import '../shell/workbench_state.dart';
import '../chat/composer_state.dart';
import '../vibe_coding/vibe_agent_facade.dart';
import 'agent/agent_dock.dart';
import 'agent/agent_pane_switcher.dart';
import 'agent/editor_agent_host.dart';
import 'agent/editor_sidebar_tabs.dart';
import 'agent/session_list_view.dart';

enum _BottomPanel {
  none,
  terminal,
  ai,
  problems,
  output,
  debug,
  debugConsole,
  ports,
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class FindIntent extends Intent {
  const FindIntent();
}

class GotoLineIntent extends Intent {
  const GotoLineIntent();
}

class FormatIntent extends Intent {
  const FormatIntent();
}

/// Borrows one controller and overrides only its newline entry point.
class _InlineSourceController extends CodeLineEditingControllerDelegate {
  _InlineSourceController({
    required super.delegate,
    required VoidCallback? Function() readOnNewLine,
  }) : _readOnNewLine = readOnNewLine;

  final VoidCallback? Function() _readOnNewLine;
  final List<VoidCallback> _forwardedListeners = [];
  bool _disposed = false;

  @override
  void applyNewLine() {
    if (_disposed) return;
    final onNewLine = _readOnNewLine();
    if (onNewLine != null) {
      onNewLine();
    } else {
      delegate.applyNewLine();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    _forwardedListeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_forwardedListeners.remove(listener)) {
      super.removeListener(listener);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final listener in _forwardedListeners.toList()) {
      super.removeListener(listener);
    }
    _forwardedListeners.clear();
    // The base delegate disposes the borrowed controller. Core owns that object.
  }
}

/// 编辑器页：左侧文件树卡片 + 可选文件标签栏 + re_editor 代码编辑区
/// + minimap 鸟瞰 + 本地终端面板 + 运行。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.project,
    required this.auth,
    required this.store,
    required this.settings,
    this.initialOpenPath,
    this.openRequest = 0,
    this.onMinimize,
    this.onClose,
    this.retainedVisibility,
    this.workspace,
    this.workspaceMembers = const [],
    this.workspaceStore,
    this.onWorkspaceSaved,
    this.onProjectSelected,
    this.agentRuntime,
    this.composerDefaults,
    this.agentEnabled = false,
  });

  final Project project;
  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;

  /// 进入编辑器后自动打开的文件（新建项目模板的主文件）。
  final String? initialOpenPath;

  /// A new request also opens a file when this page is already mounted. Existing
  /// open files are selected through EditorController without replacing text.
  final int openRequest;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final ValueListenable<bool>? retainedVisibility;

  /// Explicitly saved workspace this session belongs to, if any.
  ///
  /// A workspace open restores its own ordered tab/cursor session; a standalone
  /// open (null) never restores workspace membership or foreign tabs.
  final SavedWorkspace? workspace;

  /// Resolved surviving member projects for [workspace], primary first.
  final List<Project> workspaceMembers;

  /// Store that receives workspace session snapshots. Defaults to the shared
  /// [WorkspaceStore.instance].
  final WorkspaceStore? workspaceStore;

  /// Reports a newly attached saved workspace so a retained session can update
  /// its identity without rebuilding (and losing) the live editor state.
  final void Function(SavedWorkspace workspace, List<Project> members)?
  onWorkspaceSaved;

  /// Lets the retained owner open external projects as standalone sessions.
  final ValueChanged<Project>? onProjectSelected;

  /// 打开 Agent 面板的运行时。
  ///
  /// 为空时在第一次展开 Agent 面板时解析应用级单例；测试注入用。
  /// agent 嵌在本页内，不另开页面（design.md §11.1）。
  final AgentRuntime? agentRuntime;

  /// 按项目记住的模型 / 推理强度 / 权限模式（design.md §4 第 9 条）。
  ///
  /// 为空时用文件实现；测试注入内存实现，避开目录探测定时器。
  final ComposerDefaultsStore? composerDefaults;

  /// 是否把 agent 嵌入本页。
  ///
  /// 默认关闭：直接构造 `EditorPage` 的地方行为与基线完全一致（菜单「AI 助手」
  /// 打开旧面板，没有 agent 入口、分段和右栏）。宿主 `retained_editor_host`
  /// 负责按产品策略打开，见 design.md §11.2。
  final bool agentEnabled;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TickerProviderStateMixin {
  static const double _sidebarWidth = Breakpoints.sidebarWidth;
  static const double _cardMargin = 12;
  static const double _wideBreakpoint = 720;

  late final EditorController _editor;
  late final EditorAnalysisController _analysis;
  late final EditorDebugController _debugger;
  final _output = EditorOutputBuffer();
  final _previewConsole = EditorOutputBuffer();
  DebugPauseToken? _shownPause;
  Object? _loggedAnalysis;
  Future<void>? _stoppingPreview;
  bool _closeTerminalWhenIdle = false;
  final _sessionRestored = Completer<void>();
  Future<void> _pendingOpen = Future<void>.value();
  final _hiddenViews =
      <
        OpenFile,
        ({CodeLineSelection selection, double? vertical, double? horizontal})
      >{};
  int _visibilityGeneration = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<TerminalPaneState> _terminalKey =
      GlobalKey<TerminalPaneState>();

  TabController? _tabController;

  bool? _explorerVisible;
  bool _terminalCollapsed = false;
  bool _runningFileTool = false;
  bool _terminalCreated = false;
  bool _runningProject = false;

  /// Preferred expanded height, preserved across collapse and viewport clamps.
  double _terminalHeight = TerminalPanelMetrics.defaultExpandedHeight;

  /// Live height while a resize drag is in progress. Null when not dragging; the
  /// displayed height then comes from viewport clamping of [_terminalHeight].
  double? _terminalDragHeight;
  bool _draggingTerminal = false;

  /// Raw accumulated drag displacement from the anchor, kept *unclamped* so
  /// many small steps can cross the collapse threshold. The displayed height is
  /// [_terminalDragHeight] (clamped); the preference commits on drag end.
  double _terminalDragTotal = 0;

  /// Height the panel had when the current drag began. Raw gesture displacement
  /// is added to this anchor, so many small steps accumulate instead of each
  /// being clamped away.
  double _terminalDragAnchor = 0;

  bool _aiCollapsed = false;
  _BottomPanel _bottomPanel = _BottomPanel.none;
  bool get _terminalVisible => _bottomPanel == _BottomPanel.terminal;

  /// agent 宿主：持有侧边栏分段、主体分段和对话流收起状态。
  ///
  /// 离线产品为 null，页面上不出现任何 agent 控件。
  EditorAgentHost? _agentHost;

  /// 输入卡片的选择记忆。构造不触 IO，磁盘读写延到首次读取。
  ///
  /// 文件实现按实例缓存整张表，多实例会互相覆盖，故全应用共用一个。
  static final ComposerDefaultsStore _sharedComposerDefaults =
      FileComposerDefaultsStore();

  late final ComposerDefaultsStore _composerDefaults =
      widget.composerDefaults ?? _sharedComposerDefaults;

  /// 编辑器列与 Agent 面板的保活 key。
  ///
  /// 跨断点时两者在两套布局之间移动，[GlobalKey] 让同一份 Element（连同
  /// 终端会话、输入卡片草稿）原地迁移而不重建。
  final GlobalKey _editorColumnKey = GlobalKey(debugLabel: 'editor-column');
  final GlobalKey _agentPaneKey = GlobalKey(debugLabel: 'editor-agent-pane');

  /// Mirror of the terminal prompt's focus state, kept in sync by
  /// [_onTerminalInputFocusChanged].
  ///
  /// `EditorPage` needs it during layout to decide whether the panel may become
  /// header-only (see `build`'s `compactPanel`), and the pane owns the actual
  /// `FocusNode`.
  bool _terminalInputHasFocus = false;
  WebPreviewSession? _previewServer;
  StreamSubscription<String>? _debugSub;
  Timer? _historyTimer;
  final Map<String, Timer> _activityTimers = {};
  final Map<String, int> _manualSaveGeneration = {};
  final Map<String, int> _autoEditGeneration = {};
  bool _leaving = false;

  // Workspace session state is separate from project history. It is written to
  // the saved workspace document, never into another project's history.json.
  SavedWorkspace? _workspace;
  List<Project> _workspaceMembers = const [];
  Map<String, List<String>> _workspaceExpandedDirs = const {};
  Map<String, bool> _workspaceRootExpanded = const {};

  /// Tabs whose owner project disappeared while the session was live. Their
  /// buffers are kept, but saving/running would either fail or recreate a
  /// deleted directory, so both are blocked until the user exports the text.
  final Set<String> _orphanedPaths = {};

  WorkspaceStore get _workspaceStore =>
      widget.workspaceStore ?? WorkspaceStore.instance;

  // 双指缩放字号 + 滚动收键盘（raw pointer，不与编辑器手势竞争）。
  late double _fontSize;
  late double _savedFontSize;
  final Map<OpenFile, Widget> _codeViews = {};
  final Map<OpenFile, InlineDocumentEditor> _inlineDocuments = {};
  final Map<OpenFile, _InlineSourceController> _inlineSourceControllers = {};
  final Set<OpenFile> _inlineFocusDocuments = {};
  OpenFile? _inlineActiveDocument;
  bool _inlineRebuildQueued = false;
  final Map<int, Offset> _activePointers = {};
  double? _pinchStartDistance;
  double? _pinchStartFontSize;
  ValueChanged<double>? _pinchSourceFontSizeChanged;

  /// 长按空行时强制显示选择工具栏（仅粘贴），点击关闭后复位。
  bool _pasteToolbarVisible = false;
  Timer? _longPressTimer;

  // 云端同步（仅云端项目）。
  CloudSyncService? _cloud;
  StreamSubscription<SyncState>? _cloudSub;
  SyncState _syncState = SyncState.idle;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    // TEMP-DIAG (remove after device verification): trace every focus change so
    // a device reproduction shows exactly what receives focus after a tab-bar
    // touch, and in what order.
    FocusManager.instance.addListener(_diagFocus);
    EditorPageDiag.probeAlive('EditorPage.initState');
    _fontSize = _savedFontSize = widget.settings.editorFontSize;
    _applyWorkspace(widget.workspace, widget.workspaceMembers);
    _editor = EditorController(
      project: widget.project,
      onContentChanged: _onFileContentChanged,
    );
    _analysis = EditorAnalysisController(
      editor: _editor,
      analyzer: StudioProfile.current?.codeAnalyzer,
    );
    _debugger = EditorDebugController(
      editor: _editor,
      isFileAvailable: (file) => !_isOrphaned(file),
      isProjectAvailable: _isProjectAvailable,
    );
    _debugger.addListener(_onDebuggerChanged);
    _analysis.addListener(_onAnalysisChanged);
    widget.retainedVisibility?.addListener(_onRetainedVisibilityChanged);
    if (widget.agentEnabled && EditorAgentHost.supported) {
      final host = EditorAgentHost(
        project: widget.project,
        auth: widget.auth,
        store: widget.store,
        settings: widget.settings,
        runtime: widget.agentRuntime,
      );
      host.addListener(_onAgentHostChanged);
      _agentHost = host;
    }
    OpenPerformance.mark('EditorPage initState');
    _editor.addListener(_syncTabController);
    _editor.addListener(_onEditorChanged);
    widget.settings.addListener(_onSettingsChanged);
    if (widget.project.isCloud && StudioProfile.current?.offlineOnly != true) {
      CloudSyncService.open(
        cloudId: widget.project.cloudId!,
        cachePath: widget.project.path,
        name: widget.project.name,
      ).then((service) {
        if (!mounted) return;
        setState(() => _cloud = service);
        _cloudSub = service.stateStream.listen((state) {
          if (mounted) setState(() => _syncState = state);
        });
        _pullInitial();
      });
    }
    // Restore existing tabs, then select an explicitly requested file.
    //
    // Deferred past the first frame so the route transition is not competing
    // with file reads for the UI isolate: `_restoreSession` does stat/list IO
    // per open file, and on a phone that is enough to drop the first frames of
    // the push animation. The editor shows its empty state until this runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OpenPerformance.mark('EditorPage first frame');
      SchedulerBinding.instance.scheduleTask(
        () => _restoreSession().whenComplete(() {
          if (!_sessionRestored.isCompleted) _sessionRestored.complete();
          if (mounted) _scheduleHistorySave();
        }),
        Priority.animation,
        debugLabel: 'restoreSession',
      );
    });
  }

  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retainedVisibility != widget.retainedVisibility) {
      oldWidget.retainedVisibility?.removeListener(
        _onRetainedVisibilityChanged,
      );
      widget.retainedVisibility?.addListener(_onRetainedVisibilityChanged);
    }
    final path = widget.initialOpenPath;
    if (path != null &&
        (oldWidget.openRequest != widget.openRequest ||
            oldWidget.initialOpenPath != path)) {
      _pendingOpen = _pendingOpen.then((_) async {
        await _sessionRestored.future;
        if (mounted) await _openInitialFile(path);
      });
    }
    if (oldWidget.workspace?.id != widget.workspace?.id) {
      if (_workspace?.id == widget.workspace?.id) {
        // The same saved workspace was promoted into this live session; keep
        // the live expansion/tab state instead of reloading an older snapshot.
        _workspace = widget.workspace;
        _workspaceMembers = widget.workspaceMembers;
      } else {
        _applyWorkspace(widget.workspace, widget.workspaceMembers);
      }
    } else {
      if (!identical(oldWidget.workspace, widget.workspace)) {
        // Metadata can change while the retained identity stays the same.
        // Keep live expansion and dirty buffers instead of reloading a session.
        _workspace = widget.workspace;
      }
      if (!_sameWorkspaceMembers(
        oldWidget.workspaceMembers,
        widget.workspaceMembers,
      )) {
        _workspaceMembers = widget.workspaceMembers;
      }
    }
    if (oldWidget.workspace?.id != widget.workspace?.id ||
        !_sameWorkspaceMembers(
          oldWidget.workspaceMembers,
          widget.workspaceMembers,
        )) {
      _reconcileWorkspaceMembers();
    }
  }

  static bool _sameWorkspaceMembers(List<Project> a, List<Project> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!p.equals(a[i].path, b[i].path)) return false;
    }
    return true;
  }

  void _applyWorkspace(SavedWorkspace? workspace, List<Project> members) {
    _workspace = workspace;
    _workspaceMembers = members.isEmpty ? [widget.project] : members;
    final session = workspace?.session;
    final expanded = session?.expandedDirs ?? const <String, List<String>>{};
    _workspaceExpandedDirs = {
      for (final entry in expanded.entries)
        entry.key: List<String>.of(entry.value),
    };
    _workspaceRootExpanded = {...?session?.rootExpanded};
  }

  Future<void> _closeEditor() async {
    if (!await _confirmDiscardDirty() || !mounted) return;
    try {
      await _stopPreview();
      await _debugger.close();
    } catch (error) {
      _showSnack('关闭前清理失败，请重试：$error');
      return;
    }
    if (mounted) widget.onClose?.call();
  }

  void _onRetainedVisibilityChanged() {
    final generation = ++_visibilityGeneration;
    if (widget.retainedVisibility?.value != true) {
      if (_hiddenViews.isNotEmpty) return;
      for (final file in _editor.files) {
        final scroll = file.scrollController;
        _hiddenViews[file] = (
          selection: file.controller.selection,
          vertical: scroll.verticalScroller.hasClients
              ? scroll.verticalScroller.offset
              : null,
          horizontal: scroll.horizontalScroller.hasClients
              ? scroll.horizontalScroller.offset
              : null,
        );
      }
      return;
    }
    // Focus notifications run asynchronously, and mobile re_editor cancels
    // non-collapsed selections when losing focus. Restore only after the live
    // view has laid out again, without requesting editor or terminal focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _visibilityGeneration ||
          widget.retainedVisibility?.value != true) {
        return;
      }
      for (final entry in _hiddenViews.entries) {
        final file = entry.key;
        if (!_editor.files.contains(file)) continue;
        file.controller.selection = entry.value.selection;
        final scroll = file.scrollController;
        void restoreScroll(ScrollController controller, double? offset) {
          if (offset == null || !controller.hasClients) return;
          controller.jumpTo(
            offset
                .clamp(
                  controller.position.minScrollExtent,
                  controller.position.maxScrollExtent,
                )
                .toDouble(),
          );
        }

        restoreScroll(scroll.verticalScroller, entry.value.vertical);
        restoreScroll(scroll.horizontalScroller, entry.value.horizontal);
      }
      _hiddenViews.clear();
    });
  }

  Future<void> _restoreSession() async {
    if (!mounted) return;
    OpenPerformance.mark('restoreSession start');
    final workspaceSession = _workspace;
    final ProjectSession? history;
    final List<ProjectDocumentSession> documents;
    if (workspaceSession != null) {
      // A workspace restores only its own session document. Project history is
      // deliberately not consulted, so opening the same project standalone
      // cannot resurrect workspace tabs.
      history = null;
      documents = workspaceSession.session.documents;
      final expanded = workspaceSession.session.expandedDirs;
      _workspaceExpandedDirs = {
        for (final entry in expanded.entries)
          entry.key: List<String>.of(entry.value),
      };
      _workspaceRootExpanded = {...workspaceSession.session.rootExpanded};
    } else {
      final loaded = await ProjectHistory.load(widget.project.path);
      history = loaded;
      // The main release keeps standalone opens single-project: legacy
      // cross-root rows written by older builds are ignored rather than
      // restored as a workspace. Language products keep their history contract.
      documents = isMainStudioRelease
          ? [
              for (final document in loaded.documents)
                if (p.equals(document.projectPath, widget.project.path))
                  document,
            ]
          : loaded.documents;
    }
    if (!mounted) return;
    final restoredDocuments = documents.isNotEmpty
        ? documents
        : [
            for (final rel in history?.openFiles ?? const <String>[])
              ProjectDocumentSession(
                projectPath: widget.project.path,
                relativePath: rel,
                cursor:
                    history!.cursors[rel] ??
                    const FileCursor(
                      baseIndex: 0,
                      baseOffset: 0,
                      extentIndex: 0,
                      extentOffset: 0,
                    ),
                isActive: rel == history.activeFile,
              ),
          ];
    final opened = <String>[];
    String? activePath;
    final seen = <String>{};
    for (final document in restoredDocuments) {
      final Project owner;
      if (workspaceSession != null) {
        Project? match;
        for (final member in _workspaceMembers) {
          if (!member.isCloud && p.equals(member.path, document.projectPath)) {
            match = member;
            break;
          }
        }
        if (match == null) continue;
        owner = match;
      } else if (isMainStudioRelease) {
        if (!p.equals(document.projectPath, widget.project.path)) continue;
        owner = widget.project;
      } else {
        if (p.equals(document.projectPath, widget.project.path)) {
          owner = widget.project;
        } else {
          final matches = widget.store.projects.where(
            (project) =>
                !project.isCloud &&
                p.equals(project.path, document.projectPath),
          );
          if (matches.isEmpty) continue;
          owner = matches.first;
        }
      }
      if (p.isAbsolute(document.relativePath)) continue;
      final abs = p.normalize(p.join(owner.path, document.relativePath));
      if (!p.isWithin(owner.path, abs) || !seen.add(p.canonicalize(abs))) {
        continue;
      }
      // Async existence check: the sync form blocks the isolate once per
      // remembered tab, and a project can remember several.
      if (!await File(abs).exists()) continue;
      try {
        if (!p.isWithin(
          await Directory(owner.path).resolveSymbolicLinks(),
          await File(abs).resolveSymbolicLinks(),
        )) {
          continue;
        }
      } on FileSystemException {
        continue;
      }
      if (!mounted) return;
      final error = await _editor.openPath(
        abs,
        ownerProjectName: owner.name,
        ownerProjectPath: owner.path,
        ownerProjectType: owner.type,
        cursor: document.cursor,
      );
      if (!mounted) return;
      if (error == null) {
        opened.add(abs);
        if (document.isActive) activePath = abs;
      }
    }
    OpenPerformance.mark('restoreSession done (${opened.length} tabs)');
    final initialPath = widget.initialOpenPath;
    if (initialPath != null) {
      await _openInitialFile(initialPath);
      return;
    }
    if (opened.isNotEmpty) {
      if (activePath != null) {
        final idx = _editor.files.indexWhere(
          (f) => p.equals(f.path, activePath!),
        );
        if (idx >= 0) {
          _editor.select(idx);
          return;
        }
      }
      return;
    }
  }

  /// 保存会话（光标 + 打开列表）到项目内 history.json。
  Future<void> _saveHistory() async {
    if (!_sessionRestored.isCompleted) return;
    final cursors = <String, FileCursor>{};
    final openFiles = <String>[];
    final documents = <ProjectDocumentSession>[];
    String? activeRel;
    for (final f in _editor.files) {
      if (f.readOnly) continue;
      if (!p.isWithin(f.projectRootPath, f.path)) continue;
      // Orphaned buffers (owner left the workspace) never write their path back
      // into the saved session; recovery is explicit via "另存为…".
      if (_isOrphaned(f)) continue;
      final ownedByPrimary = p.equals(f.projectRootPath, widget.project.path);
      // The main release standalone history owns only this project's own tabs.
      if (_workspace == null && isMainStudioRelease && !ownedByPrimary) {
        continue;
      }
      final rel = p
          .relative(f.path, from: f.projectRootPath)
          .replaceAll('\\', '/');
      final sel = f.controller.selection;
      final cursor = FileCursor(
        // Folding changes visible indices; a restored document is unfolded.
        baseIndex: f.controller.codeLines.index2lineIndex(sel.baseIndex),
        baseOffset: sel.baseOffset,
        extentIndex: f.controller.codeLines.index2lineIndex(sel.extentIndex),
        extentOffset: sel.extentOffset,
      );
      documents.add(
        ProjectDocumentSession(
          projectPath: f.projectRootPath,
          relativePath: rel,
          cursor: cursor,
          isActive: identical(f, _editor.current),
        ),
      );
      if (ownedByPrimary) {
        openFiles.add(rel);
        cursors[rel] = cursor;
        if (identical(f, _editor.current)) activeRel = rel;
      }
    }
    final workspace = _workspace;
    if (workspace != null) {
      await _workspaceStore.saveSession(
        workspace,
        WorkspaceSessionSnapshot(
          primaryPath: widget.project.path,
          documents: documents,
          expandedDirs: _workspaceExpandedDirs,
          rootExpanded: _workspaceRootExpanded,
        ),
      );
      return;
    }
    await ProjectHistory.save(
      widget.project.path,
      cursors: cursors,
      openFiles: openFiles,
      activeFile: activeRel,
      documents: documents,
    );
  }

  /// Keeps the editor session in sync with the explorer's explicit workspace
  /// save/update/delete action. Workspace metadata and tabs are persisted into
  /// the workspace document; the project's own history is untouched.
  void _onWorkspaceChanged(EditorWorkspaceState state) {
    final attached = state.saved;
    setState(() {
      _workspace = state.saved;
      _workspaceMembers = state.members;
      _workspaceExpandedDirs = state.expandedDirs;
      _workspaceRootExpanded = state.rootExpanded;
    });
    if (attached != null) {
      widget.onWorkspaceSaved?.call(attached, state.members);
    }
    _reconcileWorkspaceMembers();
    unawaited(_saveHistory());
  }

  bool _isProjectAvailable(String projectPath) =>
      _workspace == null ||
      _workspaceMembers.any(
        (member) =>
            workspacePathKey(member.path) == workspacePathKey(projectPath),
      );

  bool _isOrphaned(OpenFile open) =>
      !_isProjectAvailable(open.projectRootPath) ||
      _orphanedPaths.contains(workspacePathKey(open.path));

  /// Drops clean tabs whose owner left the workspace and keeps dirty buffers
  /// as explicit recovery items. No source file is modified or recreated.
  void _reconcileWorkspaceMembers() {
    if (_workspace == null) {
      _orphanedPaths.clear();
      return;
    }
    final allowed = <String>{
      for (final member in _workspaceMembers) workspacePathKey(member.path),
    };
    for (var i = _editor.files.length - 1; i >= 0; i--) {
      final file = _editor.files[i];
      if (allowed.contains(workspacePathKey(file.projectRootPath))) {
        _orphanedPaths.remove(workspacePathKey(file.path));
        continue;
      }
      if (file.dirty) {
        _orphanedPaths.add(workspacePathKey(file.path));
      } else {
        _editor.closeAt(i);
      }
    }
    if (_orphanedPaths.isNotEmpty && mounted) {
      // Called from didUpdateWidget (build phase): defer to the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _orphanedPaths.isEmpty) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('部分项目已不可用；未保存的改动仍保留在编辑器中，可通过「另存为…」导出')),
        );
      });
    }
  }

  /// Explicit recovery for a buffer whose project root disappeared.
  Future<void> _recoverOrphanedFile() async {
    final open = _editor.current;
    if (open == null) return;
    final location = await PickerService.saveDocument(suggestedName: open.name);
    final path = location?.path;
    if (path == null || path.isEmpty) return;
    try {
      await File(path).writeAsBytes(
        TextCodec.byName(open.encoding).encode(open.controller.text),
        flush: true,
      );
      if (!mounted) return;
      _showSnack('已另存为 $path');
    } on FileSystemException catch (error) {
      if (mounted) _showSnack('另存失败：${error.message}');
    }
  }

  @override
  void dispose() {
    widget.retainedVisibility?.removeListener(_onRetainedVisibilityChanged);
    _agentHost?.removeListener(_onAgentHostChanged);
    _agentHost?.dispose();
    _agentHost = null;
    _hiddenViews.clear();
    // TEMP-DIAG (remove after device verification).
    FocusManager.instance.removeListener(_diagFocus);
    _leaving = true;
    for (final timer in _activityTimers.values) {
      timer.cancel();
      TaskActivityService.report(widget.auth, 'save_file');
    }
    _activityTimers.clear();
    _saveHistory(); // 离开编辑器时保存现场（异步落盘）
    widget.settings.removeListener(_onSettingsChanged);
    _editor.removeListener(_syncTabController);
    _editor.removeListener(_onEditorChanged);
    _longPressTimer?.cancel();
    _historyTimer?.cancel();
    _cloudSub?.cancel();
    _debugSub?.cancel();
    _cloud?.dispose();
    _tabController?.dispose();
    _analysis.removeListener(_onAnalysisChanged);
    _debugger.removeListener(_onDebuggerChanged);
    _debugger.dispose();
    _analysis.dispose();
    _output.dispose();
    _previewConsole.dispose();
    for (final controller in _inlineSourceControllers.values) {
      controller.dispose();
    }
    _inlineSourceControllers.clear();
    for (final contribution in _inlineDocuments.values) {
      contribution.removeListener(_onInlineDocumentChanged);
      contribution.dispose();
    }
    _inlineDocuments.clear();
    _inlineFocusDocuments.clear();
    _editor.dispose();
    unawaited(
      _stopPreview().catchError((Object error) {
        debugPrint('Editor preview cleanup failed: $error');
      }),
    );
    super.dispose();
  }

  Future<void> _pullInitial() async {
    final token = widget.auth.token;
    if (token == null) {
      setState(() => _syncError = '云端项目需要登录（我的页）');
      return;
    }
    final cacheEmpty = !_cloud!.existsAnyFile();
    final result = await _cloud!.pullAll(
      token: token,
      onlyIfMissing: !cacheEmpty,
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() => _syncError = result.error);
    } else if (result.pulled > 0) {
      setState(() => _syncError = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已从云端拉取 ${result.pulled} 个文件')));
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {
      if (_savedFontSize != widget.settings.editorFontSize) {
        _fontSize = _savedFontSize = widget.settings.editorFontSize;
      }
      _codeViews.clear();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _codeViews.clear();
  }

  void _onEditorChanged() {
    final current = _editor.current;
    if (!identical(_inlineActiveDocument, current)) {
      final previous = _inlineActiveDocument;
      _inlineActiveDocument = current;
      if (_inlineFocusDocuments.contains(previous) ||
          _inlineFocusDocuments.contains(current)) {
        _onInlineDocumentChanged();
      }
    }
    if (!_sessionRestored.isCompleted) return;
    if (_editor.current?.readOnly == true) return; // 历史快照只读
    _scheduleHistorySave();
  }

  void _scheduleHistorySave() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 1500), () {
      unawaited(_saveHistory());
    });
  }

  void _onFileContentChanged(OpenFile open) {
    _scheduleHistorySave();
    // A buffer whose project was removed must not be written back and recreate
    // the deleted directory; the user exports it explicitly instead.
    if (_isOrphaned(open)) return;
    if (!widget.settings.autoSave && !widget.project.isCloud) return;
    _activityTimers.remove(open.path)?.cancel();
    final editGeneration = (_autoEditGeneration[open.path] ?? 0) + 1;
    _autoEditGeneration[open.path] = editGeneration;
    final bytes = TextCodec.byName(open.encoding).encode(open.controller.text);
    final save = _editor.saveFile(
      open,
      backup: widget.settings.backupEnabled,
      bytes: bytes,
      shouldSave: () =>
          mounted && _editor.files.contains(open) && !_isOrphaned(open),
    );
    unawaited(
      _finishAutoSave(
        open.path,
        bytes,
        save,
        widget.auth.token,
        _manualSaveGeneration[open.path] ?? 0,
        editGeneration,
      ),
    );
  }

  /// Previous line count per path, so a save can report a line delta.
  /// Updated on every recorded save.
  final Map<String, int> _localLineCounts = {};

  /// Records a save into the local stats and audit stores.
  ///
  /// The line delta comes from the difference against the last recorded count
  /// for this path, which is the cheapest honest source: the editor does not
  /// hand out its previous buffer here, and keeping one integer per open file
  /// is far less work than the estimate is worth. The UI labels the figure as an
  /// estimate for that reason.
  Future<void> _recordLocalSave(String path, List<int> bytes) async {
    final name = p.basename(path);
    final lines = _lineCount(bytes);
    final previous = _localLineCounts[path];
    _localLineCounts[path] = lines;
    await LocalStatsService.instance.recordSave(
      project: widget.project.name,
      path: path,
      previousLineCount: previous,
      newLineCount: previous == null ? null : lines,
    );
    await LocalAuditService.instance.record(
      kind: LocalAuditKind.save,
      action: '保存 $name',
      project: widget.project.name,
      path: path,
    );
  }

  static int _lineCount(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    var lines = 1;
    for (final byte in bytes) {
      if (byte == 0x0A) lines++;
    }
    return lines;
  }

  Future<void> _finishAutoSave(
    String path,
    List<int> bytes,
    Future<String?> save,
    String? token,
    int manualGeneration,
    int editGeneration,
  ) async {
    final error = await save;
    if (error != null) {
      if (mounted) _showSnack('自动保存失败：$error');
      return;
    }
    if ((_manualSaveGeneration[path] ?? 0) == manualGeneration &&
        _autoEditGeneration[path] == editGeneration) {
      // Local stats/audit alongside the server-side activity report. The two
      // are independent: the server one queues a reward event, this one only
      // writes to the local JSON file.
      unawaited(_recordLocalSave(path, bytes));
      if (_leaving) {
        TaskActivityService.report(widget.auth, 'save_file');
      } else {
        _activityTimers.remove(path)?.cancel();
        _activityTimers[path] = Timer(const Duration(seconds: 2), () {
          _activityTimers.remove(path);
          TaskActivityService.report(widget.auth, 'save_file');
        });
      }
    }
    final cloud = _cloud;
    if (cloud == null || token == null || widget.auth.token != token) return;
    final syncError = await cloud.pushBytes(token, path, bytes);
    if (mounted && _syncError != syncError) {
      setState(() => _syncError = syncError);
    }
  }

  Future<void> _pullFromCloud() async {
    final token = widget.auth.token;
    if (token == null || _cloud == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从云端拉取？'),
        content: const Text('服务器文件将覆盖本地镜像中已存在的同名文件（未同步的本地修改会丢失）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('拉取'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _cloud!.pullAll(token: token);
    if (!mounted) return;
    if (result.error != null) {
      setState(() => _syncError = result.error);
    } else {
      setState(() => _syncError = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已更新 ${result.pulled} 个文件')));
    }
  }

  void _openGit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GitPage(project: widget.project, auth: widget.auth),
      ),
    );
  }

  /// 顶栏副标题：当前打开文件的路径（过长时省略中段）。
  String _currentFileSubtitle() {
    final open = _editor.current;
    if (open == null) return '未打开文件';
    final relative = p.isWithin(widget.project.path, open.path)
        ? p.relative(open.path, from: widget.project.path)
        : open.path;
    if (relative.length <= 36) return relative;
    return '…${p.separator}${p.basename(open.path)}';
  }

  void _undoCurrent() {
    final open = _editor.current;
    if (open == null) return;
    open.controller.undo();
  }

  // ---- 双指缩放字号 + 滚动收键盘（raw pointer 监听，不参与手势竞技场）----

  // TEMP-DIAG (remove after device verification): see [EditorPageDiag].
  FocusNode? _diagLastFocus;
  void _diagFocus() {
    if (!EditorPageDiag.enabled || !mounted || _leaving) return;
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _diagLastFocus)) return;
    _diagLastFocus = node;
    final focusContext = node?.context;
    EditorPageDiag.diag(
      'primaryFocus -> label=${node?.debugLabel} '
      'widget=${focusContext?.mounted == true ? focusContext!.widget.runtimeType : null} '
      'hasFocus=${node?.hasFocus}',
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    EditorPageDiag.diag(
      'editor Listener.onPointerDown pos=${event.position} '
      'visible=$_terminalVisible collapsed=$_terminalCollapsed '
      'dragging=$_draggingTerminal '
      'focusBefore=${FocusManager.instance.primaryFocus?.debugLabel}',
    );
    // Touching the editor area hides a visible paste toolbar.
    if (_pasteToolbarVisible) {
      setState(() => _pasteToolbarVisible = false);
    }
    // Touching the editor hands the layout back to the code: collapse the
    // terminal to its header. `_terminalHeight` is deliberately left untouched
    // so re-expanding restores the height the user had dragged to.
    //
    // Skipped while the user is dragging the panel's height, because that drag
    // drives the collapse state itself from the gesture.
    //
    // A raw `Listener.onPointerDown` is used (not a GestureDetector) so the
    // editor keeps full ownership of taps, selection, scrolling and the soft
    // keyboard: this only observes the touch.
    if (_terminalVisible && !_terminalCollapsed && !_draggingTerminal) {
      setState(() => _terminalCollapsed = true);
    }
    // OHOS fix: release the terminal's focus (and therefore its platform IME
    // connection) *before* the editor's tap can request focus. re_editor opens
    // its IME connection synchronously from a FocusNode listener, so without
    // this ordering the terminal's teardown runs after the editor's
    // TextInput.show and the OHOS IME dismisses the keyboard it just raised.
    if (isOhosPlatform && _terminalVisible) {
      _terminalKey.currentState?.unfocusInput();
    }
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      final points = _activePointers.values.toList();
      _pinchStartDistance = (points[0] - points[1]).distance;
      final open = _editor.current;
      final contribution = _inlineDocumentFor(open);
      final updateFontSize = contribution?.onSourceFontSizeChanged;
      _pinchSourceFontSizeChanged = updateFontSize == null
          ? null
          : (size) {
              if (open != null &&
                  _inlineDocumentAvailable(open) &&
                  identical(_inlineDocuments[open], contribution)) {
                updateFontSize(size);
              }
            };
      _pinchStartFontSize =
          contribution?.sourceTextStyle?.fontSize ?? _fontSize;
    } else if (_activePointers.length == 1) {
      // 单指按下：启动长按计时器，500ms 后弹出粘贴工具栏。
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted && !_pasteToolbarVisible) {
          setState(() => _pasteToolbarVisible = true);
        }
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _activePointers[event.pointer];
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.position;
    }
    // 手指移动超过阈值：取消长按计时器。
    if (_longPressTimer != null && start != null) {
      if ((start - event.position).distance > 14) {
        _longPressTimer!.cancel();
        _longPressTimer = null;
      }
    }
    if (_activePointers.length >= 2 && _pinchStartDistance != null) {
      final points = _activePointers.values.toList();
      final distance = (points[0] - points[1]).distance;
      if (_pinchStartDistance! > 0) {
        final fontSize =
            (_pinchStartFontSize! * distance / _pinchStartDistance!).clamp(
              EditorFonts.minSize,
              EditorFonts.maxSize,
            );
        final updateFontSize = _pinchSourceFontSizeChanged;
        if (updateFontSize != null) {
          updateFontSize(fontSize);
        } else {
          setState(() {
            _fontSize = fontSize;
            _codeViews.clear();
          });
        }
      }
      return;
    }
  }

  void _handlePointerUp(PointerEvent event) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      if (_pinchStartFontSize != null && _pinchSourceFontSizeChanged == null) {
        unawaited(widget.settings.setEditorFont(size: _fontSize));
      }
      _pinchStartDistance = null;
      _pinchStartFontSize = null;
      _pinchSourceFontSizeChanged = null;
    }
  }

  Future<void> _openInitialFile(String path) async {
    if (!mounted) return;
    // 模板主文件是相对路径（如 src/main.py），必须拼到项目根下。
    final abs = p.isAbsolute(path) ? path : p.join(widget.project.path, path);
    final error = await _editor.openPath(abs);
    OpenPerformance.mark('entry file loaded');
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// 标签页数量变化时同步 TabController。
  void _syncTabController() {
    if (!mounted) return;
    final count = _editor.files.length;
    _codeViews.removeWhere((file, _) => !_editor.files.contains(file));
    for (final file in _inlineDocuments.keys.toList()) {
      if (_editor.files.contains(file)) continue;
      _inlineSourceControllers.remove(file)?.dispose();
      final contribution = _inlineDocuments.remove(file)!;
      contribution.removeListener(_onInlineDocumentChanged);
      contribution.dispose();
      _inlineFocusDocuments.remove(file);
    }
    final old = _tabController;
    if (old != null && old.length == count) {
      if (old.index != _editor.currentIndex &&
          _editor.currentIndex >= 0 &&
          count > 0) {
        old.index = _editor.currentIndex;
      }
      return;
    }
    final initial = _editor.currentIndex.clamp(0, count > 0 ? count - 1 : 0);
    old?.dispose();
    if (count == 0) {
      _tabController = null;
    } else {
      _tabController = TabController(
        length: count,
        vsync: this,
        initialIndex: initial,
      );
      _tabController!.addListener(() {
        if (!_tabController!.indexIsChanging &&
            _tabController!.index != _editor.currentIndex) {
          _editor.select(_tabController!.index);
        }
      });
    }
    unawaited(_saveHistory()); // 打开/关闭标签后保存会话
    setState(() {});
  }

  void _toggleExplorer() {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    if (wide) {
      // 侧栏默认隐藏，第一次点击为展开。
      setState(() => _explorerVisible = !(_explorerVisible ?? false));
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  void _closeDrawer() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  // ---- Agent 面板 ----

  void _onAgentHostChanged() {
    if (mounted) setState(() {});
  }

  /// 展开 Agent 面板：宽屏展开右栏，中屏与窄屏切到 Agent 分段。
  ///
  /// 同时是「第一次展开」，运行时就从这里开始解析。
  void _showAgentPanel() {
    final host = _agentHost;
    if (host == null) return;
    host.activate();
    final layout = layoutOf(MediaQuery.sizeOf(context).width);
    if (layout == WorkbenchLayout.wide) {
      host.state.setAgentPaneCollapsed(false);
    } else {
      host.state.showMainPane(MainPane.agent);
      // 记下「展开过」：窗口拉宽后直接就是展开的对话流。
      host.state.setAgentPaneCollapsed(false);
    }
  }

  void _toggleAgentPanel() {
    final host = _agentHost;
    if (host == null) return;
    if (!_agentPanelActive) {
      _showAgentPanel();
    } else if (layoutOf(MediaQuery.sizeOf(context).width) ==
        WorkbenchLayout.wide) {
      _collapseAgentPanel();
    } else {
      host.state.showMainPane(MainPane.editor);
    }
  }

  /// 收起宽屏右栏。
  void _collapseAgentPanel() {
    final host = _agentHost;
    if (host == null) return;
    host.state.setAgentPaneCollapsed(true);
  }

  /// 切侧边栏分段。窄屏同时打开抽屉。
  void _showSidebarSection(SidebarSection section) {
    final host = _agentHost;
    if (host == null) return;
    host.activate();
    setState(() => _explorerVisible = true);
    host.state.showSidebarSection(section);
    if (layoutOf(MediaQuery.sizeOf(context).width) == WorkbenchLayout.narrow) {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  /// 新建会话并把它放到 Agent 面板上。
  Future<void> _createAgentSession() async {
    final host = _agentHost;
    final runtime = host?.runtime;
    if (host == null || runtime == null) return;
    final meta = await runtime.sessions.create(widget.project.id);
    if (!mounted) return;
    _selectAgentSession(meta.id);
  }

  /// 停止本项目下所有运行中的会话。运行时的会话记录和草稿都保留。
  void _stopAllAgentSessions(AgentRuntime? runtime) {
    runtime?.cancelAll();
  }

  /// 点选会话：Agent 面板显示它，窄屏切分段并关抽屉。
  void _selectAgentSession(String sessionId) {
    final host = _agentHost;
    if (host == null) return;
    host.selectSession(sessionId);
    final layout = layoutOf(MediaQuery.sizeOf(context).width);
    if (layout == WorkbenchLayout.wide) {
      host.state.setAgentPaneCollapsed(false);
    } else {
      host.state.showMainPane(MainPane.agent);
      host.state.setAgentPaneCollapsed(false);
      if (layout == WorkbenchLayout.narrow) _closeDrawer();
    }
  }

  /// 宽屏右栏的收起宽度。
  static const double _agentRailWidth = 48;

  /// Agent 面板是否已经展开。
  bool get _agentPanelActive {
    final host = _agentHost;
    if (host == null) return false;
    if (layoutOf(MediaQuery.sizeOf(context).width) == WorkbenchLayout.wide) {
      return !host.state.agentPaneCollapsed;
    }
    return host.state.mainPane == MainPane.agent;
  }

  /// 后台待确认或失败的会话数，用于顶栏与收起竖条角标。
  int _agentBadgeCount() {
    final host = _agentHost;
    final runtime = host?.runtime;
    if (host == null || runtime == null) return 0;
    return agentBadgeCount(
      runtime,
      widget.project.id,
      foregroundSessionId: _agentPanelActive ? host.state.sessionId : null,
    );
  }

  /// 宽屏右栏：展开时是会话框，收起时只剩竖条。
  ///
  /// 收起时对话流仍在树上（只是不画），所以恢复后草稿和消息都在。
  Widget _buildAgentDockStack(
    EditorAgentHost? host, {
    required bool collapsed,
    required Widget? pane,
  }) {
    if (host == null) return const SizedBox.shrink();
    final runtime = host.runtime;
    final content = runtime == null
        ? (pane ?? const SizedBox.shrink())
        : LoginGateScope(
            auth: widget.auth,
            child: AgentDock(
              runtime: runtime,
              state: host.state,
              onCollapse: _collapseAgentPanel,
              onCreateSession: _createAgentSession,
              child: pane ?? const SizedBox.shrink(),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: Breakpoints.agentPaneWidth,
          child: Offstage(offstage: collapsed, child: content),
        ),
        if (collapsed)
          AgentDockRail(
            onExpand: _showAgentPanel,
            badgeCount: _agentBadgeCount(),
          ),
      ],
    );
  }

  /// 侧边栏：一个卡片外框、一个标题行，主体在文件树与会话列表之间切换。
  ///
  /// 没有 agent 时只有文件树。[FileExplorer.sections] 持有会话主体，所以外框、
  /// 标题行和分段入口都只有一套；会话段选中时标题行仍在，随时能切回文件树。
  /// 抽屉和桌面侧边栏共用这里。
  Widget _buildSidebar(BuildContext context, {VoidCallback? onFileOpened}) {
    final host = _agentHost;
    if (host == null) {
      return _buildExplorerCard(context, onFileOpened: onFileOpened);
    }
    final runtime = host.runtime;
    Widget sectionSwitch() => AnimatedBuilder(
      animation: host.state,
      builder: (context, _) => SidebarSectionSwitch(
        section: host.state.sidebarSection,
        onChanged: _showSidebarSection,
      ),
    );
    return _buildExplorerCard(
      context,
      onFileOpened: onFileOpened,
      headerTrailing: sectionSwitch(),
      sections: FileExplorerSections(
        state: host.state,
        // 未激活时给出「会话」分段，点它才开始解析运行时；未解析好时主体
        // 显示等待，标题行和分段仍在。
        sessions: runtime == null
            ? null
            : SessionListView(
                runtime: runtime,
                state: host.state,
                projectId: widget.project.id,
                onSelect: _selectAgentSession,
                onCreate: _createAgentSession,
                embedded: true,
              ),
        onNewSession: _createAgentSession,
        onStopAllSessions: () => _stopAllAgentSessions(runtime),
      ),
    );
  }

  /// Agent 面板本体。运行时还没解析好时显示等待或错误。
  ///
  /// 外面包 [LoginGateScope]：输入卡片的登录门控需要一个能读到登录态的
  /// 作用域，编辑器页现在是唯一的提供者。
  Widget _buildAgentPane(EditorAgentHost host, {required bool active}) =>
      LoginGateScope(
        auth: widget.auth,
        child: EditorAgentPane(
          key: _agentPaneKey,
          project: widget.project,
          runtime: host.runtime,
          auth: widget.auth,
          settings: widget.settings,
          sessionId: host.state.sessionId,
          onSessionOpened: _selectAgentSession,
          error: host.error,
          onRetry: host.activate,
          composerDefaults: _composerDefaults,
          active: active,
        ),
      );

  // ---- 编辑动作 ----

  Future<void> _saveCurrent() async {
    final open = _editor.current;
    if (open == null || open.readOnly) return;
    final error = await _saveInlineDocument(open);
    if (error != null && mounted) _showSnack(error);
  }

  Future<String?> _saveInlineDocument(OpenFile open) async {
    if (!mounted || !_editor.files.contains(open)) return '文件已关闭';
    if (open.readOnly) return '历史快照只读';
    if (_isOrphaned(open)) {
      return '项目文件夹已不可用，请另存为导出改动';
    }
    final wasDirty = open.dirty;
    final token = widget.auth.token;
    final bytes = TextCodec.byName(open.encoding).encode(open.controller.text);
    final error = await _editor.saveFile(
      open,
      bytes: bytes,
      shouldSave: () =>
          mounted && _editor.files.contains(open) && !_isOrphaned(open),
    );
    if (error != null) return error;
    if (wasDirty) {
      _manualSaveGeneration[open.path] =
          (_manualSaveGeneration[open.path] ?? 0) + 1;
      _activityTimers.remove(open.path)?.cancel();
      TaskActivityService.report(widget.auth, 'save_file');
    }
    if (_cloud != null && token != null && widget.auth.token == token) {
      final syncError = await _cloud!.pushBytes(token, open.path, bytes);
      if (mounted) setState(() => _syncError = syncError);
    }
    return null;
  }

  void _openFind() {
    final open = _editor.current;
    if (open == null) return;
    open.findController.findMode();
  }

  void _showGotoLineDialog() {
    final open = _editor.current;
    if (open == null) return;
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到行'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: '行号（1 - ${open.controller.codeLines.length}）',
            prefixIcon: const Icon(Icons.pin),
          ),
          onSubmitted: (_) => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('跳转'),
          ),
        ],
      ),
    ).then((_) {
      final value = int.tryParse(controller.text);
      if (value == null || value < 1) return;
      final index = (value - 1).clamp(0, open.controller.codeLines.length - 1);
      open.controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: 0,
      );
      open.scrollController.makeVisible(
        CodeLinePosition(index: index, offset: 0),
      );
    });
  }

  void _formatCurrent() {
    final open = _editor.current;
    if (open == null) return;
    final result = CodeFormatter.format(open.name, open.controller.text);
    if (result.changed) {
      open.controller.text = result.text;
    }
  }

  Future<void> _runEditorTool(String id) async {
    final open = _editor.current;
    final tool = StudioProfile.current?.editorFileTools
        .where((tool) => tool.id == id)
        .firstOrNull;
    if (_runningFileTool ||
        _runningProject ||
        _debugger.busy ||
        _terminalKey.currentState?.hasRunningWork == true ||
        open == null ||
        open.readOnly ||
        _isOrphaned(open) ||
        tool == null) {
      return;
    }
    if (!tool.extensions.contains(p.extension(open.path).toLowerCase())) return;
    setState(() => _runningFileTool = true);
    try {
      await _saveCurrent();
      if (!mounted ||
          !_editor.files.contains(open) ||
          _isOrphaned(open) ||
          open.dirty) {
        return;
      }
      final EditorFileToolResult result;
      try {
        result = await tool.run(open.path, open.projectRootPath);
      } catch (error) {
        if (mounted) _showSnack('${tool.label}失败：$error');
        return;
      }
      if (!mounted) return;
      _output.append(
        '${tool.label}${result.success ? '完成' : '失败'}\n${result.message}\n',
      );
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${tool.label}${result.success ? '完成' : '失败'}'),
          content: SingleChildScrollView(child: SelectableText(result.message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _runningFileTool = false);
    }
  }

  bool _hasInlineDocumentEditor(OpenFile? open) {
    final profile = StudioProfile.current;
    return open != null &&
        profile?.inlineDocumentEditorFactory != null &&
        profile!.supportedFileExtensions.contains(
          p.extension(open.name).toLowerCase(),
        );
  }

  bool _inlineDocumentAvailable(OpenFile open) =>
      mounted && _editor.files.contains(open) && !_isOrphaned(open);

  InlineDocumentEditor? _inlineDocumentFor(OpenFile? open) {
    if (open == null || !_hasInlineDocumentEditor(open)) return null;
    final existing = _inlineDocuments[open];
    if (existing != null) return existing;
    final contribution = StudioProfile.current!.inlineDocumentEditorFactory!(
      InlineDocumentRequest(
        path: open.path,
        name: open.name,
        projectPath: open.projectRootPath,
        readOnly: open.readOnly,
        readEncoding: () => open.encoding,
        readDirty: () => open.dirty,
        controller: open.controller,
        focusNode: open.focusNode,
        scrollController: open.scrollController,
        findController: open.findController,
        save: () => _saveInlineDocument(open),
        openFile: (path) => _openInlineDocument(open, path),
        showProblems: () {
          if (_inlineDocumentAvailable(open)) _showPanel(_BottomPanel.problems);
        },
        showOutput: () {
          if (mounted && _editor.files.contains(open)) {
            _showPanel(_BottomPanel.output);
          }
        },
        recordOutput: (message) {
          if (mounted && _editor.files.contains(open)) _output.append(message);
        },
        isAvailable: () => _inlineDocumentAvailable(open),
        setFocusMode: (enabled) {
          if (!mounted || !_editor.files.contains(open)) return;
          setState(() {
            if (enabled) {
              _inlineFocusDocuments.add(open);
            } else {
              _inlineFocusDocuments.remove(open);
            }
          });
        },
      ),
    );
    _inlineDocuments[open] = contribution;
    _inlineSourceControllers[open] = _InlineSourceController(
      delegate: open.controller,
      readOnNewLine: () => _inlineDocuments[open]?.onSourceNewLine,
    );
    contribution.addListener(_onInlineDocumentChanged);
    return contribution;
  }

  void _onInlineDocumentChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_inlineRebuildQueued) return;
    _inlineRebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inlineRebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _invokeInlineDocumentAction(
    OpenFile open,
    InlineDocumentAction action,
  ) async {
    if (!mounted ||
        !_editor.files.contains(open) ||
        !identical(open, _editor.current) ||
        !action.enabled) {
      return;
    }
    try {
      await action.invoke(context);
    } catch (error) {
      if (mounted) _showSnack('操作失败：$error');
    }
  }

  Future<String?> _openInlineDocument(OpenFile source, String path) async {
    if (!_inlineDocumentAvailable(source)) return '文件所属项目已不可用';
    if (path.startsWith(r'\\') || path.startsWith('//')) {
      return '请选择本机项目文件';
    }
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme && uri.scheme.length > 1) {
      return '请先将文档导入本机项目';
    }
    final target = p.normalize(
      p.isAbsolute(path) ? path : p.join(source.projectRootPath, path),
    );
    final owners =
        <Project>[
          widget.project,
          ..._workspaceMembers,
          ...widget.store.projects.where((project) => !project.isCloud),
        ].where((project) => p.isWithin(project.path, target)).toList()..sort(
          (left, right) => right.path.length.compareTo(left.path.length),
        );
    if (owners.isEmpty) return '请先添加文件所属项目';
    final owner = owners.first;
    if (!_isProjectAvailable(owner.path)) return '文件所属项目不在当前工作区';
    try {
      final root = await Directory(owner.path).resolveSymbolicLinks();
      final resolved = await File(target).resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) return '文件不在项目目录内';
      if (!_inlineDocumentAvailable(source) ||
          !_isProjectAvailable(owner.path)) {
        return '文件所属项目已不可用';
      }
      return _editor.openPath(
        target,
        ownerProjectName: owner.name,
        ownerProjectPath: owner.path,
        ownerProjectType: owner.type,
        shouldOpen: () =>
            _inlineDocumentAvailable(source) && _isProjectAvailable(owner.path),
      );
    } on FileSystemException catch (error) {
      return '无法打开文件：${error.message}';
    }
  }

  Widget _buildDocumentView(BuildContext context, OpenFile open) {
    final contribution = _inlineDocumentFor(open);
    if (contribution == null) return _buildCodeView(context, open);
    return AnimatedBuilder(
      animation: contribution,
      builder: (context, _) =>
          contribution.build(context, _buildCodeView(context, open)),
    );
  }

  /// 当前文件能否交给产品自带的整页文档工具（如 Markdown 编辑/预览工作台）。
  bool _hasDocumentTool(OpenFile? open) {
    final profile = StudioProfile.current;
    if (open == null ||
        _hasInlineDocumentEditor(open) ||
        profile?.documentToolBuilder == null) {
      return false;
    }
    return profile!.supportedFileExtensions.contains(
      p.extension(open.name).toLowerCase(),
    );
  }

  void _openContentTool() {
    final open = _editor.current;
    if (open == null || _hasInlineDocumentEditor(open)) return;
    final documentTool = StudioProfile.current?.documentToolBuilder;
    if (documentTool != null && _hasDocumentTool(open)) {
      final page = documentTool(
        DocumentToolRequest(
          path: open.path,
          name: open.name,
          text: open.controller.text,
          projectPath: open.projectRootPath,
          readOnly: open.readOnly,
          save: (text) async {
            if (!mounted || !_editor.files.contains(open)) return '文件已关闭';
            if (_isOrphaned(open)) return '项目文件夹已不可用，请另存为导出改动';
            if (open.controller.text != text) {
              setState(() => open.controller.text = text);
            }
            return _editor.saveFile(
              open,
              shouldSave: () =>
                  mounted && _editor.files.contains(open) && !_isOrphaned(open),
            );
          },
        ),
      );
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      return;
    }
    final extension = p.extension(open.name).toLowerCase();
    if (extension != '.json' &&
        extension != '.md' &&
        extension != '.markdown') {
      return;
    }
    final page = extension == '.json'
        ? JsonToolPage(
            initialText: open.controller.text,
            onApply: (value) => setState(() => open.controller.text = value),
          )
        : MarkdownToolPage(
            initialText: open.controller.text,
            onApply: (value) => setState(() => open.controller.text = value),
          );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Runs the project entry on a normal tap, or an explicit [entryOverride]
  /// (the active file captured by a long press) through the same save and
  /// runtime routing. Calls with an override must validate it first.
  ///
  /// A normal tap sends the run straight to the sibling app that owns the
  /// entry's toolchain. Nothing probes first: the probe was a real ability
  /// start, and the run sent after it was refused with error 201 whenever the
  /// sibling app had not gone back to the background yet. The start call is the
  /// honest test, and `app_missing` means the app is not installed: that answer
  /// is remembered and this run falls back to Studio's own path. Every other
  /// failure is shown to the user. One gesture never runs twice.
  Future<void> _runProject({String? entryOverride}) async {
    if (_runningProject ||
        _runningFileTool ||
        _debugger.busy ||
        _terminalKey.currentState?.hasRunningWork == true) {
      return;
    }
    // Capture the owner before any asynchronous save or tab switch. A workspace
    // can contain several projects with different entries and relative inputs.
    final active = _editor.current;
    if (active != null && _isOrphaned(active)) {
      _showSnack('项目已从工作区移除，请先通过「另存为…」导出未保存的改动');
      return;
    }
    final projectPath = active?.projectRootPath ?? widget.project.path;
    final projectName = active?.ownerProjectName ?? widget.project.name;
    final sibling = _siblingAppFor(entryOverride ?? _entryFileOf(projectPath));
    if (sibling != null) {
      final outcome = await _runInSiblingApp();
      if (!mounted || outcome == null || !outcome.appMissing) return;
      // The sibling app is not installed. Remember it so later runs and the
      // tooltip take this path at once, then run here instead of nowhere.
      InteropSiblingMemory.instance.markMissing(sibling.language);
      setState(() {});
    }
    if (!Directory(projectPath).existsSync()) {
      setState(() {
        _terminalCreated = true;
        _closeTerminalWhenIdle = false;
        _terminalCollapsed = false;
        _bottomPanel = _BottomPanel.terminal;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _terminalKey.currentState?.expand();
      _terminalKey.currentState?.appendSystem('项目文件夹已不可用，无法运行（$projectPath）');
      return;
    }
    setState(() {
      _runningProject = true;
      _terminalCreated = true;
      _closeTerminalWhenIdle = false;
      _terminalCollapsed = false;
      _bottomPanel = _BottomPanel.terminal;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final pane = _terminalKey.currentState;
    if (pane == null) {
      setState(() => _runningProject = false);
      return;
    }
    pane.expand();
    var preparing = false;
    try {
      if (pane.busy) return;
      pane.beginPreparation();
      preparing = true;
      final sources = _editor.files
          .where(
            (open) =>
                p.equals(open.projectRootPath, projectPath) &&
                !_isOrphaned(open),
          )
          .toList();
      bool ownerAvailable() =>
          mounted &&
          (active == null ||
              (_editor.files.contains(active) && !_isOrphaned(active)));
      if (sources.any((open) => !_runSourceWithin(projectPath, open.path))) {
        pane.appendSystem('file is outside its project');
        return;
      }
      for (final open in sources) {
        final error = await _editor.saveFile(
          open,
          shouldSave: () =>
              ownerAvailable() &&
              _editor.files.contains(open) &&
              !_isOrphaned(open) &&
              _runSourceWithin(projectPath, open.path),
        );
        if (!mounted || !pane.mounted) return;
        if (error != null) {
          pane.appendSystem(error);
          return;
        }
      }
      if (!ownerAvailable() || sources.any((open) => open.dirty)) {
        pane.appendSystem('项目或源文件已更改，请确认后重新运行');
        return;
      }
      final entry = entryOverride ?? RunnerService.findEntry(projectPath);
      if (entry == null) {
        final hint = StudioProfile.current?.entryFileNames;
        pane.appendSystem(
          hint == null || hint.isEmpty
              ? '未找到可运行的入口文件（index.html / main.py / Main.java 等）'
              : '未找到可运行的入口文件（${hint.join(' / ')}）',
        );
        return;
      }
      if (!_runSourceWithin(projectPath, entry)) {
        pane.appendSystem('entry file is outside its project');
        return;
      }
      final ext = p.extension(entry).toLowerCase();
      // Without a language runner (SQLab has one), .sql goes to cloud MySQL.
      if (ext == '.sql' &&
          StudioProfile.current?.runner == null &&
          StudioProfile.current?.offlineOnly != true) {
        pane.finishPreparation();
        await pane.runCloudSql(entry);
        return;
      }
      if (pane.onlineSelected && ext != '.html' && ext != '.htm') {
        pane.finishPreparation();
        await pane.runOnlineProject(projectPath, entry);
        return;
      }

      if (ext == '.html' || ext == '.htm') {
        // Detach and stop the previous preview before starting a replacement so
        // no stale session or debug listener survives.
        await _stopPreview();
        if (!ownerAvailable()) return;
        WebPreviewSession? server;
        try {
          server =
              await (StudioProfile.current?.webPreviewFactory?.call(
                    projectPath,
                  ) ??
                  LocalWebServer.start(projectPath));
          if (!mounted) {
            _previewServer = server;
            await _stopPreview();
            return;
          }
          _previewServer = server;
          // The factory owns the configured document root and default entry.
          // Only an explicit active-file run asks it to resolve another file.
          final String targetUrl;
          if (entryOverride != null) {
            if (server is! WebFilePreviewSession) {
              throw StateError('preview does not support individual files');
            }
            targetUrl = server.urlForFile(entryOverride);
          } else {
            targetUrl = server.url;
          }
          if (mounted) setState(() {});
          // The same actual browser messages feed the retained Debug Console.
          // 页面 console 日志转发到终端面板（Web 调试）。
          _debugSub = server.debugStream.listen((line) {
            _previewConsole.append('$line\n');
            _terminalKey.currentState?.appendDebug(line);
          });
          await RunnerService.openUrl(targetUrl);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('预览服务已启动：$targetUrl'),
                action: SnackBarAction(
                  label: '复制地址',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: targetUrl)),
                ),
              ),
            );
          }
        } catch (error) {
          // A failed stop retains its real listener for Ports/close to retry.
          Object? cleanupError;
          if (server != null && identical(_previewServer, server)) {
            try {
              await _stopPreview();
            } catch (failure) {
              cleanupError = failure;
            }
          }
          if (mounted) {
            _showSnack(
              '${error is SocketException ? '启动预览服务失败：${error.message}' : error}'
              '${cleanupError == null ? '' : '；预览清理失败，请从 Ports 重试：$cleanupError'}',
            );
          }
        }
        return;
      }

      _output.append('运行 · $projectName/${p.basename(entry)}\n');
      final result = await RunnerService.runProject(
        projectPath: projectPath,
        entryFile: entry,
      );
      if (!mounted || !pane.mounted) {
        await result?.cancel?.call();
        await result?.managedProcess?.cancel();
        result?.process?.kill();
        return;
      }
      pane.finishPreparation();
      final hint = result?.hint;
      if (hint != null) {
        pane.appendSystem(hint);
        _output.append('$hint\n');
        if (StudioProfile.current?.offlineOnly != true &&
            OnlineProgram.supports(entry)) {
          await pane.runOnlineProject(projectPath, entry);
        }
        return;
      }
      // 应用内运行时（语言 App 注入）：直接接管输出流。
      final stdout = result?.stdout;
      final stderr = result?.stderr;
      final exitCode = result?.exitCode;
      if (result != null &&
          stdout != null &&
          stderr != null &&
          exitCode != null) {
        final code = await pane.attachOutput(
          title: result.title,
          stdout: stdout,
          stderr: stderr,
          exitCode: exitCode,
          cancel: result.cancel,
          onOutput: _recordProgramOutput,
          onExit: _recordProgramExit,
        );
        if (code == kProgramNotRunExitCode &&
            mounted &&
            pane.mounted &&
            StudioProfile.current?.offlineOnly != true &&
            OnlineProgram.supports(entry)) {
          pane.appendSystem('本地运行时不可用，转入在线运行');
          await pane.runOnlineProject(projectPath, entry);
        }
        unawaited(
          LocalStatsService.instance.recordRun(
            succeeded: code == 0,
            project: projectName,
          ),
        );
        unawaited(
          LocalAuditService.instance.record(
            kind: LocalAuditKind.run,
            action: '运行 ${p.basename(entry)}',
            project: projectName,
            path: entry,
            detail: '退出码 $code',
          ),
        );
        return;
      }
      final managedProcess = result?.managedProcess;
      if (managedProcess != null) {
        pane.attachManagedProcess(
          result!.title,
          managedProcess,
          onOutput: _recordProgramOutput,
          onExit: _recordProgramExit,
        );
        return;
      }
      final process = result?.process;
      if (process != null) {
        pane.attachProcess(
          result!.title,
          process,
          onOutput: _recordProgramOutput,
          onExit: _recordProgramExit,
        );
      }
    } catch (error) {
      if (mounted && pane.mounted) pane.appendSystem('cannot execute: $error');
    } finally {
      if (pane.mounted && preparing) pane.finishPreparation();
      if (mounted) setState(() => _runningProject = false);
    }
  }

  /// Long press on Run: run the file that is active when the gesture fires.
  ///
  /// Validation happens before any save so an invalid or deleted active file
  /// never gets recreated and never falls back to the project entry. A valid
  /// file reuses the same save and runtime routing as [_runProject].
  Future<void> _runActiveFile() async {
    if (_runningProject || _debugger.busy) return;
    final open = _editor.current;
    final reason = _activeFileRunError(open);
    if (reason != null) {
      setState(() {
        _terminalCreated = true;
        _closeTerminalWhenIdle = false;
        _terminalCollapsed = false;
        _bottomPanel = _BottomPanel.terminal;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _terminalKey.currentState?.expand();
      _terminalKey.currentState?.appendSystem(reason);
      return;
    }
    await _runProject(entryOverride: p.normalize(p.absolute(open!.path)));
  }

  /// Returns a short English reason when [open] cannot be run directly, or
  /// null when the selected file can be handed to the project runner.
  String? _activeFileRunError(OpenFile? open) {
    if (open == null) return 'no active file to run';
    if (open.readOnly) return 'active file is read-only';
    if (_isOrphaned(open)) return 'project folder is no longer available';
    if (!Directory(open.projectRootPath).existsSync()) {
      return 'project folder is no longer available';
    }
    final profile = StudioProfile.current;
    final ext = p.extension(open.name).toLowerCase();
    final supported = profile?.supportedFileExtensions ?? const <String>[];
    if (supported.isNotEmpty && !supported.contains(ext)) {
      return '${ext.isEmpty ? 'file' : ext} is not runnable here';
    }
    final root = p.normalize(p.absolute(open.projectRootPath));
    final path = p.normalize(p.absolute(open.path));
    if (!p.isWithin(root, path)) return 'active file is outside the project';
    if (!File(path).existsSync()) return 'active file no longer exists';
    if (!_runSourceWithin(root, path)) {
      return 'active file is outside the project';
    }
    return null;
  }

  bool _runSourceWithin(String projectPath, String path) {
    final root = p.normalize(p.absolute(projectPath));
    final source = p.normalize(p.absolute(path));
    if (!p.isWithin(root, source)) return false;
    try {
      final physicalRoot = Directory(root).resolveSymbolicLinksSync();
      final physicalSource =
          FileSystemEntity.typeSync(source) == FileSystemEntityType.notFound
          ? p.join(
              File(source).parent.resolveSymbolicLinksSync(),
              p.basename(source),
            )
          : File(source).resolveSymbolicLinksSync();
      return p.isWithin(physicalRoot, physicalSource);
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _openOnlineTerminal() async {
    setState(() {
      _terminalCreated = true;
      _closeTerminalWhenIdle = false;
      _terminalCollapsed = false;
      _bottomPanel = _BottomPanel.terminal;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _terminalKey.currentState?.showOnline();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onDebuggerChanged() {
    if (!mounted) return;
    setState(() {});
    final token = _debugger.snapshot?.pauseToken;
    if (token == null || token == _shownPause) return;
    _shownPause = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _debugger.snapshot?.pauseToken != token) return;
      final frame = _debugger.selectedFrame;
      if (frame?.location != null) unawaited(_debugger.navigate(frame!));
    });
  }

  void _onAnalysisChanged() {
    if (_analysis.pending ||
        ((StudioProfile.current?.productKey ??
                    StudioProductCatalog.qfliStudioKey) ==
                StudioProductCatalog.qfliStudioKey &&
            _analysis.analyzer == null)) {
      return;
    }
    final identity =
        _analysis.unavailableReason ??
        (_analysis.checked ? _analysis.problems : null);
    if (identity == null || identical(identity, _loggedAnalysis)) return;
    _loggedAnalysis = identity;
    final reason = _analysis.unavailableReason;
    _output.append(
      reason == null
          ? '检查 · ${_editor.current?.name ?? ""} · ${_analysis.problems.length} 个问题\n'
          : '检查不可用 · $reason\n',
    );
    for (final problem in _analysis.problems.take(50)) {
      _output.append('${_analysis.location(problem)} · ${problem.message}\n');
    }
    if (_analysis.problems.length > 50) _output.append('其余问题请查看 Problems\n');
  }

  void _recordProgramOutput(String text, bool isError) {
    _output.append('${isError ? "[stderr] " : ""}$text\n');
  }

  void _recordProgramExit(int code) => _output.append('退出码 $code\n');

  /// Tooltip for the Run button.
  ///
  /// The label names the sibling app that owns the entry file's toolchain, so
  /// the user can see where the button will run the project before pressing
  /// it. The name comes from the static target map on purpose: probing here
  /// would start the sibling app in the foreground on every project open,
  /// which reads as a crash to the user. An app this session already found
  /// missing is never named, because the button would then promise a run in an
  /// app that is not installed.
  String get _runButtonTooltip {
    final target = _interopTargetFor(
      _entryFileOf(_editor.current?.projectRootPath ?? widget.project.path),
    );
    final product = target?.productName;
    if (product == null ||
        InteropSiblingMemory.instance.isMissing(target!.language)) {
      return '运行（长按运行当前文件）';
    }
    return '运行（在 $product 中，长按运行当前文件）';
  }

  /// The device app that owns this project's toolchain, or null when none does.
  ///
  /// The entry file decides: a project can hold several files and only one of
  /// them names a toolchain. An entry that matches no receiver must produce no
  /// menu item, because an action that can only fail is worse than none.
  InteropTarget? _interopTargetFor(String? entryFile) {
    if (StudioProfile.current?.interopRunner == null || entryFile == null) {
      return null;
    }
    return InteropTargets.forEntryFile(entryFile);
  }

  /// Entry file of [projectPath], or null when the project has none.
  String? _entryFileOf(String projectPath) {
    final entry = RunnerService.findEntry(projectPath);
    return entry == null ? null : p.normalize(p.absolute(entry));
  }

  /// The sibling app a normal Run sends [entryFile] to, without asking it.
  ///
  /// The decision is static: the entry file names the toolchain, and the start
  /// call reports a missing app as `app_missing`. No probe runs here on
  /// purpose. The probe is a real ability start: it pulls the sibling app to the
  /// foreground, which pushes Studio into the background, and a background
  /// application may not start another application's UI ability — the run sent
  /// right after the probe was refused with error 201 whenever the sibling app
  /// had not exited yet.
  InteropTarget? _siblingAppFor(String? entryFile) {
    final runner = StudioProfile.current?.interopRunner;
    if (runner == null || !runner.isSupported) return null;
    final target = _interopTargetFor(entryFile);
    if (target == null) return null;
    if (InteropSiblingMemory.instance.isMissing(target.language)) return null;
    return target;
  }

  /// Compiles and runs the open project inside the sibling app that owns the
  /// toolchain, and reports how the dialog ended.
  ///
  /// A missing app is not a dialog result but a decision for the caller: the
  /// caller may run the project on its own path instead. The install hint is
  /// shown here so the user learns why the app it expected did not start.
  Future<InteropRunOutcome?> _runInSiblingApp() async {
    final runner = StudioProfile.current?.interopRunner;
    if (runner == null) return null;
    if (_runningProject ||
        _runningFileTool ||
        _debugger.busy ||
        _terminalKey.currentState?.hasRunningWork == true) {
      _showSnack('请先停止当前运行任务');
      return null;
    }
    final active = _editor.current;
    if (active != null && _isOrphaned(active)) {
      _showSnack('项目已从工作区移除，请先通过「另存为…」导出未保存的改动');
      return null;
    }
    final projectPath = active?.projectRootPath ?? widget.project.path;
    if (!Directory(projectPath).existsSync()) {
      _showSnack('项目文件夹已不可用（$projectPath）');
      return null;
    }
    // The payload is built from disk, so an unsaved buffer would compile bytes
    // the user cannot see. Refuse instead of guessing which version to run.
    final unsaved = _editor.files
        .where((open) => p.equals(open.projectRootPath, projectPath))
        .where((open) => open.dirty)
        .toList();
    if (unsaved.isNotEmpty) {
      _showSnack('请先保存 ${unsaved.length} 个未保存的文件');
      return null;
    }
    final entry = _entryFileOf(projectPath);
    final target = _interopTargetFor(entry);
    if (entry == null || target == null) {
      _showSnack('没有支持该项目入口的配套应用');
      return null;
    }
    // An explicit request from the menu runs even without a probe: probing
    // would pull the sibling app to the foreground and get the real start
    // refused with error 201. A missing app is reported by the start itself.
    final outcome = await showInteropRunDialog(
      context: context,
      projectRoot: projectPath,
      language: target.language,
      entryFile: entry,
      runner: runner,
    );
    if (!mounted || outcome == null) return null;
    if (outcome.appMissing) {
      _showSnack(outcome.diagnostic ?? '配套应用未安装，无法在本机编译运行。');
      return outcome;
    }
    _output.append(
      '跨应用运行 · ${p.basename(entry)} · ${target.productName} · 退出码 ${outcome.exitCode}\n',
    );
    unawaited(
      LocalStatsService.instance.recordRun(
        succeeded: outcome.exitCode == 0,
        project: active?.ownerProjectName ?? widget.project.name,
      ),
    );
    return outcome;
  }

  bool get _canRunBackground {
    final runner = StudioProfile.current?.backgroundInteropRunner;
    if (!isOhosPlatform ||
        runner == null ||
        !runner.isSupported) {
      return false;
    }
    final entry = _entryFileOf(
      _editor.current?.projectRootPath ?? widget.project.path,
    );
    return entry != null && p.extension(entry).toLowerCase() == '.java';
  }

  /// Explicit experiment: owns a terminal session without changing normal Run.
  Future<void> _runInBackgroundSiblingApp() async {
    final runner = StudioProfile.current?.backgroundInteropRunner;
    if (runner == null || !_canRunBackground) return;
    if (_runningProject ||
        _runningFileTool ||
        _debugger.busy ||
        _terminalKey.currentState?.hasRunningWork == true) {
      _showSnack('请先停止当前运行任务');
      return;
    }
    final active = _editor.current;
    if (active != null && _isOrphaned(active)) {
      _showSnack('项目已移除，请先导出未保存的改动');
      return;
    }
    final projectPath = active?.projectRootPath ?? widget.project.path;
    final entry = _entryFileOf(projectPath);
    if (!Directory(projectPath).existsSync() ||
        entry == null ||
        !_runSourceWithin(projectPath, entry)) {
      _showSnack('项目入口已不可用');
      return;
    }
    bool hasUnsavedFiles() => _editor.files.any(
      (open) => p.equals(open.projectRootPath, projectPath) && open.dirty,
    );
    if (hasUnsavedFiles()) {
      _showSnack('请先保存项目中的文件');
      return;
    }
    setState(() {
      _runningProject = true;
      _terminalCreated = true;
      _closeTerminalWhenIdle = false;
      _terminalCollapsed = false;
      _bottomPanel = _BottomPanel.terminal;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final pane = _terminalKey.currentState;
    if (pane == null) {
      setState(() => _runningProject = false);
      return;
    }
    try {
      if (pane.busy) return;
      pane.showLocal();
      pane.beginPreparation('后台运行（实验）· 无感调用验证中');
      if (hasUnsavedFiles() || (active != null && _isOrphaned(active))) {
        pane.appendSystem('项目或源文件已更改，请确认后重新运行');
        return;
      }
      final run = await runner.run(
        projectRoot: projectPath,
        language: 'java',
        entryFile: entry,
      );
      if (!mounted || !pane.mounted) {
        await run.cancel?.call();
        return;
      }
      pane.finishPreparation();
      final code = await pane.attachOutput(
        title: '后台运行（实验）· ${p.basename(entry)}',
        stdout: run.stdout,
        stderr: run.stderr,
        exitCode: run.exitCode,
        cancel: run.cancel,
        onOutput: _recordProgramOutput,
        onExit: _recordProgramExit,
      );
      unawaited(
        LocalStatsService.instance.recordRun(
          succeeded: code == 0,
          project: active?.ownerProjectName ?? widget.project.name,
        ),
      );
    } catch (error) {
      if (mounted && pane.mounted) pane.appendSystem('后台运行失败：$error');
    } finally {
      if (pane.mounted) pane.finishPreparation();
      if (mounted) setState(() => _runningProject = false);
    }
  }

  /// Runs the project in the online terminal instead of a sibling app.
  ///
  /// The menu keeps this next to the cross-app entry so a user who does not
  /// want the run to leave Studio has one obvious alternative, and so the
  /// normal Run path never looks like it silently changed target.
  Future<void> _runProjectOnline() async {
    if (_runningProject ||
        _runningFileTool ||
        _debugger.busy ||
        _terminalKey.currentState?.hasRunningWork == true) {
      _showSnack('请先停止当前运行任务');
      return;
    }
    final projectPath = _editor.current?.projectRootPath ?? widget.project.path;
    final entry = _entryFileOf(projectPath);
    if (entry == null) {
      _showSnack('未找到可运行的入口文件');
      return;
    }
    setState(() {
      _terminalCreated = true;
      _closeTerminalWhenIdle = false;
      _terminalCollapsed = false;
      _bottomPanel = _BottomPanel.terminal;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final pane = _terminalKey.currentState;
    if (pane == null) return;
    pane.expand();
    await pane.runOnlineProject(projectPath, entry);
  }

  Future<void> _startDebug(bool stopOnEntry) async {
    final active = _editor.current;
    if (active != null && _isOrphaned(active)) {
      _showSnack('项目已从工作区移除，请先通过「另存为…」导出未保存的改动');
      return;
    }
    if (_runningProject ||
        _runningFileTool ||
        _terminalKey.currentState?.hasRunningWork == true) {
      _showSnack('请先停止当前运行任务');
      return;
    }
    await _debugger.start(stopOnEntry: stopOnEntry);
  }

  void _showPanel(_BottomPanel panel) {
    _terminalKey.currentState?.unfocusInput();
    setState(() {
      _bottomPanel = panel;
      if (panel == _BottomPanel.terminal) {
        _terminalCreated = true;
        _closeTerminalWhenIdle = false;
      }
    });
  }

  Future<void> _stopPreview() {
    final pending = _stoppingPreview;
    if (pending != null) return pending;
    final server = _previewServer;
    if (server == null) return Future<void>.value();
    return _stoppingPreview = () async {
      try {
        await server.stop();
        if (identical(_previewServer, server)) {
          await _debugSub?.cancel();
          _debugSub = null;
          _previewServer = null;
        }
        if (mounted) setState(() {});
      } finally {
        _stoppingPreview = null;
      }
    }();
  }

  Widget _buildActivityPanel() {
    void close() => _showPanel(_BottomPanel.none);
    return switch (_bottomPanel) {
      _BottomPanel.debug => EditorDebugPanel(
        debug: _debugger,
        runBusy:
            _runningProject ||
            _runningFileTool ||
            _terminalKey.currentState?.hasRunningWork == true,
        onStart: _startDebug,
        onClose: close,
      ),
      _BottomPanel.output => EditorOutputPanel(
        output: _output,
        debug: _debugger,
        onClose: close,
      ),
      _BottomPanel.debugConsole => EditorDebugConsolePanel(
        previewConsole: _previewConsole,
        debug: _debugger,
        onClose: close,
      ),
      _BottomPanel.ports => EditorPortsPanel(
        preview: _previewServer,
        onStop: _stopPreview,
        onClose: close,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final wideAgentPane =
        layoutOf(MediaQuery.sizeOf(context).width) == WorkbenchLayout.wide;
    // 窄屏用原撤销按钮的位置切换面板。
    // 标题保留原宽度。
    final undoInMenu = _agentHost != null && !wide;
    final editorVisible = wideAgentPane || !_agentPanelActive;
    final focusMode = _inlineFocusDocuments.contains(_editor.current);
    final sidebarVisible = !focusMode && (_explorerVisible ?? false);
    // Android 的窗口铺到屏幕底边，导航条会压住最后一屏内容，由编辑器自己让位。
    final bottomInset = EditorBottomInset.insetOf(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyG, control: true):
            GotoLineIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, control: true): FormatIntent(),
      },
      child: Actions(
        actions: {
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (_) {
              _saveCurrent();
              return null;
            },
          ),
          FindIntent: CallbackAction<FindIntent>(
            onInvoke: (_) {
              _openFind();
              return null;
            },
          ),
          GotoLineIntent: CallbackAction<GotoLineIntent>(
            onInvoke: (_) {
              _showGotoLineDialog();
              return null;
            },
          ),
          FormatIntent: CallbackAction<FormatIntent>(
            onInvoke: (_) {
              _formatCurrent();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: _scaffoldKey,
            drawerScrimColor: scheme.surface,
            appBar: focusMode
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(kToolbarHeight),
                    child: SelectionToolbarScope(
                      editor: _editor,
                      controllerBuilder: () => _editor.current?.controller,
                      builder: (context, controller) {
                        // 选区非空时 leading / actions 必须传 null：AppBar 的 leading
                        // 槽位是定宽的，换成 0 宽的 widget 仍会占 56px。两者归零加上
                        // titleSpacing: 0，title 槽位才等于屏幕宽度。
                        final hasSelection =
                            editorVisible &&
                            controller != null &&
                            !controller.selection.isCollapsed &&
                            controller.selectedText.isNotEmpty;
                        final selected =
                            editorVisible &&
                                (hasSelection || _pasteToolbarVisible)
                            ? controller
                            : null;
                        final inlineOpen = _editor.current;
                        final inlineEditor = _inlineDocumentFor(inlineOpen);
                        final inlineActions =
                            inlineEditor?.actions ??
                            const <InlineDocumentAction>[];
                        final inlineMenu =
                            inlineEditor?.menuActions ??
                            const <InlineDocumentAction>[];
                        return AppBar(
                          backgroundColor: selected != null
                              ? scheme.surfaceContainerHigh
                              : null,
                          systemOverlayStyle: selected != null
                              ? SystemUiOverlayStyle(
                                  statusBarColor: scheme.surfaceContainerHigh,
                                  statusBarIconBrightness:
                                      scheme.brightness == Brightness.dark
                                      ? Brightness.light
                                      : Brightness.dark,
                                  statusBarBrightness: scheme.brightness,
                                )
                              : null,
                          leading: selected != null
                              ? null
                              : IconButton(
                                  tooltip: sidebarVisible ? '收起文件树' : '打开文件树',
                                  onPressed: _toggleExplorer,
                                  icon: const Icon(Icons.menu),
                                ),
                          automaticallyImplyLeading: false,
                          titleSpacing: 0,
                          title: selected != null
                              ? SelectionToolbarBar(
                                  controller: selected,
                                  pasteOnly: !hasSelection,
                                  onDismiss: _pasteToolbarVisible
                                      ? () => setState(
                                          () => _pasteToolbarVisible = false,
                                        )
                                      : null,
                                )
                              : _buildProjectTitle(context, scheme),
                          actions: selected != null
                              ? null
                              : [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_agentHost case final host?)
                                        AgentEntryButton(
                                          host: host,
                                          active: _agentPanelActive,
                                          switchesPane: !wideAgentPane,
                                          onPressed: _toggleAgentPanel,
                                        ),
                                      if (widget.onMinimize != null)
                                        IconButton(
                                          tooltip: '暂时收起编辑器',
                                          onPressed: widget.onMinimize,
                                          icon: const Icon(Icons.minimize),
                                        ),
                                      if (!undoInMenu)
                                        IconButton(
                                          tooltip: '撤销 (Ctrl+Z)',
                                          onPressed: _editor.current == null
                                              ? null
                                              : _undoCurrent,
                                          icon: const Icon(Icons.undo),
                                        ),
                                      if (inlineEditor != null)
                                        for (final action in inlineActions)
                                          IconButton(
                                            key: ValueKey(
                                              'inline-action-${action.id}',
                                            ),
                                            tooltip: action.label,
                                            onPressed: action.enabled
                                                ? () => unawaited(
                                                    _invokeInlineDocumentAction(
                                                      inlineOpen!,
                                                      action,
                                                    ),
                                                  )
                                                : null,
                                            icon: Icon(action.icon),
                                          )
                                      else if (_hasDocumentTool(
                                        _editor.current,
                                      ))
                                        IconButton(
                                          tooltip: '编辑与预览',
                                          onPressed: _openContentTool,
                                          icon: const Icon(
                                            Icons.chrome_reader_mode_outlined,
                                          ),
                                        )
                                      else
                                        // One gesture owner: a normal tap runs the
                                        // configured project entry, a long press runs
                                        // the file that is active when it fires.
                                        Tooltip(
                                          message: _runButtonTooltip,
                                          child: Semantics(
                                            button: true,
                                            enabled:
                                                !_runningProject &&
                                                !_debugger.busy,
                                            child: InkResponse(
                                              onTap:
                                                  _runningProject ||
                                                      _debugger.busy
                                                  ? null
                                                  : _runProject,
                                              onLongPress:
                                                  _runningProject ||
                                                      _debugger.busy
                                                  ? null
                                                  : _runActiveFile,
                                              canRequestFocus:
                                                  !_runningProject &&
                                                  !_debugger.busy,
                                              radius: 24,
                                              child: SizedBox.square(
                                                dimension:
                                                    kMinInteractiveDimension,
                                                child: Icon(
                                                  Icons.play_arrow,
                                                  color:
                                                      _runningProject ||
                                                          _debugger.busy
                                                      ? Theme.of(
                                                          context,
                                                        ).disabledColor
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      PopupMenuButton<String>(
                                        tooltip: '更多',
                                        icon: const Icon(Icons.more_vert),
                                        onSelected: (value) {
                                          if (value.startsWith('inline:')) {
                                            final id = value.substring(7);
                                            for (final action in inlineMenu) {
                                              if (action.id == id &&
                                                  inlineOpen != null) {
                                                unawaited(
                                                  _invokeInlineDocumentAction(
                                                    inlineOpen,
                                                    action,
                                                  ),
                                                );
                                                break;
                                              }
                                            }
                                            return;
                                          }
                                          if (value.startsWith('file_tool:')) {
                                            unawaited(
                                              _runEditorTool(
                                                value.substring(10),
                                              ),
                                            );
                                            return;
                                          }
                                          switch (value) {
                                            case 'undo':
                                              _undoCurrent();
                                            case 'save':
                                              _saveCurrent();
                                            case 'recover_orphan':
                                              unawaited(_recoverOrphanedFile());
                                            case 'interop_run':
                                              unawaited(_runInSiblingApp());
                                            case 'interop_background_run':
                                              unawaited(
                                                _runInBackgroundSiblingApp(),
                                              );
                                            case 'run_online':
                                              unawaited(_runProjectOnline());
                                            case 'close_editor':
                                              unawaited(_closeEditor());
                                            case 'find':
                                              _openFind();
                                            case 'goto':
                                              _showGotoLineDialog();
                                            case 'format':
                                              _formatCurrent();
                                            case 'content_tool':
                                              _openContentTool();
                                            case 'minimap':
                                              widget.settings.setMinimap(
                                                !widget.settings.minimap,
                                              );
                                            case 'output':
                                              _showPanel(_BottomPanel.output);
                                            case 'debug':
                                              _showPanel(_BottomPanel.debug);
                                            case 'debug_console':
                                              _showPanel(
                                                _BottomPanel.debugConsole,
                                              );
                                            case 'ports':
                                              _showPanel(_BottomPanel.ports);
                                            case 'terminal':
                                              _terminalCreated = true;
                                              _closeTerminalWhenIdle = false;
                                              setState(
                                                () => _bottomPanel =
                                                    _bottomPanel ==
                                                        _BottomPanel.terminal
                                                    ? _BottomPanel.none
                                                    : _BottomPanel.terminal,
                                              );
                                            case 'settings':
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => SettingsPage(
                                                    settings: widget.settings,
                                                    auth: widget.auth,
                                                    store: widget.store,
                                                    showAi:
                                                        StudioProfile
                                                            .current
                                                            ?.offlineOnly !=
                                                        true,
                                                  ),
                                                ),
                                              );
                                            case 'ai':
                                              // agent 打开时应用内只有一个 AI 入口，
                                              // 菜单直接开 Agent 面板；否则维持旧面板。
                                              if (_agentHost != null) {
                                                _showAgentPanel();
                                              } else {
                                                setState(
                                                  () => _bottomPanel =
                                                      _bottomPanel ==
                                                          _BottomPanel.ai
                                                      ? _BottomPanel.none
                                                      : _BottomPanel.ai,
                                                );
                                              }
                                            case 'online_terminal':
                                              unawaited(_openOnlineTerminal());
                                            case 'git':
                                              if (StudioProfile
                                                      .current
                                                      ?.offlineOnly !=
                                                  true) {
                                                _openGit();
                                              }
                                            case 'cloud_pull':
                                              if (StudioProfile
                                                      .current
                                                      ?.offlineOnly !=
                                                  true) {
                                                _pullFromCloud();
                                              }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (undoInMenu)
                                            PopupMenuItem(
                                              value: 'undo',
                                              enabled: _editor.current != null,
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.undo, size: 20),
                                                  SizedBox(width: 12),
                                                  Text('撤销'),
                                                ],
                                              ),
                                            ),
                                          for (final action in inlineMenu)
                                            PopupMenuItem<String>(
                                              key: ValueKey(
                                                'inline-menu-${action.id}',
                                              ),
                                              value: 'inline:${action.id}',
                                              enabled: action.enabled,
                                              child: Row(
                                                children: [
                                                  Icon(action.icon, size: 20),
                                                  const SizedBox(width: 12),
                                                  Flexible(
                                                    child: Text(action.label),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (inlineMenu.isNotEmpty)
                                            const PopupMenuDivider(),
                                          if (widget.onClose != null)
                                            const PopupMenuItem(
                                              value: 'close_editor',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.close, size: 20),
                                                  SizedBox(width: 12),
                                                  Text('关闭编辑器'),
                                                ],
                                              ),
                                            ),
                                          for (final tool
                                              in StudioProfile
                                                      .current
                                                      ?.editorFileTools ??
                                                  const <EditorFileTool>[])
                                            if (tool.extensions.contains(
                                              p
                                                  .extension(
                                                    _editor.current?.name ?? '',
                                                  )
                                                  .toLowerCase(),
                                            ))
                                              PopupMenuItem(
                                                value: 'file_tool:${tool.id}',
                                                enabled:
                                                    !_runningFileTool &&
                                                    _editor.current?.readOnly !=
                                                        true,
                                                child: Row(
                                                  children: [
                                                    Icon(tool.icon, size: 20),
                                                    const SizedBox(width: 12),
                                                    Flexible(
                                                      child: Text(tool.label),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          if (_editor.current != null &&
                                              _isOrphaned(_editor.current!))
                                            const PopupMenuItem(
                                              value: 'recover_orphan',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.save_as_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Flexible(
                                                    child: Text('另存为…（项目不可用）'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (_canRunBackground)
                                            PopupMenuItem(
                                              value: 'interop_background_run',
                                              enabled:
                                                  !_runningProject &&
                                                  !_runningFileTool &&
                                                  !_debugger.busy &&
                                                  _terminalKey
                                                          .currentState
                                                          ?.hasRunningWork !=
                                                      true,
                                              child: const Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .notifications_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Flexible(
                                                    child: Text('后台运行（实验）'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (_interopTargetFor(
                                                _entryFileOf(
                                                  _editor
                                                          .current
                                                          ?.projectRootPath ??
                                                      widget.project.path,
                                                ),
                                              )
                                              case final interopTarget?)
                                            PopupMenuItem(
                                              value: 'interop_run',
                                              enabled:
                                                  !_runningProject &&
                                                  !_debugger.busy,
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .developer_board_outlined,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Flexible(
                                                    child: Text(
                                                      '运行（${interopTarget.productName}）',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (_interopTargetFor(
                                                _entryFileOf(
                                                  _editor
                                                          .current
                                                          ?.projectRootPath ??
                                                      widget.project.path,
                                                ),
                                              ) !=
                                              null)
                                            PopupMenuItem(
                                              value: 'run_online',
                                              enabled:
                                                  !_runningProject &&
                                                  !_debugger.busy &&
                                                  StudioProfile
                                                          .current
                                                          ?.offlineOnly !=
                                                      true,
                                              child: const Row(
                                                children: [
                                                  Icon(
                                                    Icons.cloud_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Flexible(
                                                    child: Text('改用在线终端运行'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'save',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.save_outlined,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 12),
                                                Flexible(
                                                  child: Text('保存 (Ctrl+S)'),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'find',
                                            child: Row(
                                              children: [
                                                Icon(Icons.search, size: 20),
                                                SizedBox(width: 12),
                                                Flexible(
                                                  child: Text('查找替换 (Ctrl+F)'),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'goto',
                                            child: Row(
                                              children: [
                                                Icon(Icons.pin, size: 20),
                                                SizedBox(width: 12),
                                                Flexible(
                                                  child: Text('跳转到行 (Ctrl+G)'),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'format',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.format_align_left,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 12),
                                                Flexible(
                                                  child: Text('格式化 (Ctrl+I)'),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (inlineEditor == null &&
                                              (p
                                                          .extension(
                                                            _editor
                                                                    .current
                                                                    ?.name ??
                                                                '',
                                                          )
                                                          .toLowerCase() ==
                                                      '.json' ||
                                                  p
                                                          .extension(
                                                            _editor
                                                                    .current
                                                                    ?.name ??
                                                                '',
                                                          )
                                                          .toLowerCase() ==
                                                      '.md' ||
                                                  p
                                                          .extension(
                                                            _editor
                                                                    .current
                                                                    ?.name ??
                                                                '',
                                                          )
                                                          .toLowerCase() ==
                                                      '.markdown'))
                                            const PopupMenuItem(
                                              value: 'content_tool',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.preview_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text('内容工具'),
                                                ],
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'minimap',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  widget.settings.minimap
                                                      ? Icons
                                                            .visibility_off_outlined
                                                      : Icons
                                                            .visibility_outlined,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  widget.settings.minimap
                                                      ? '隐藏代码鸟瞰'
                                                      : '显示代码鸟瞰',
                                                ),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'output',
                                            child: Text('Output · 输出'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'debug',
                                            child: Text('调试'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'debug_console',
                                            child: Text('Debug Console'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'ports',
                                            child: Text('Ports · 本地端口'),
                                          ),
                                          PopupMenuItem(
                                            value: 'terminal',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  _terminalVisible
                                                      ? Icons.terminal_outlined
                                                      : Icons.terminal,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  _terminalVisible
                                                      ? '关闭终端'
                                                      : '打开终端',
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (StudioProfile
                                                  .current
                                                  ?.offlineOnly !=
                                              true)
                                            const PopupMenuItem(
                                              value: 'git',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.account_tree_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text('Git'),
                                                ],
                                              ),
                                            ),
                                          if (widget.project.isCloud &&
                                              StudioProfile
                                                      .current
                                                      ?.offlineOnly !=
                                                  true)
                                            const PopupMenuItem(
                                              value: 'cloud_pull',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .cloud_download_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text('从云端拉取'),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'settings',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.settings_outlined,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 12),
                                                Text('设置'),
                                              ],
                                            ),
                                          ),
                                          if (StudioProfile
                                                  .current
                                                  ?.offlineOnly !=
                                              true)
                                            PopupMenuItem(
                                              value: 'ai',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    _bottomPanel ==
                                                            _BottomPanel.ai
                                                        ? Icons
                                                              .auto_awesome_outlined
                                                        : Icons.auto_awesome,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    _bottomPanel ==
                                                            _BottomPanel.ai
                                                        ? '关闭 AI 助手'
                                                        : 'AI 助手',
                                                  ),
                                                ],
                                              ),
                                            ),

                                          if (StudioProfile
                                                  .current
                                                  ?.offlineOnly !=
                                              true)
                                            const PopupMenuItem(
                                              value: 'online_terminal',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.cloud_outlined,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text('在线终端（服务器执行）'),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ),
                                ],
                        );
                      },
                    ),
                  ),
            drawer: wide || focusMode
                ? null
                : Drawer(
                    width: _sidebarWidth + _cardMargin * 2,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(),
                    backgroundColor: scheme.surface,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(_cardMargin),
                        child: _buildSidebar(
                          context,
                          onFileOpened: _closeDrawer,
                        ),
                      ),
                    ),
                  ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final bodyHeight = constraints.maxHeight;
                final collapsedPanelHeight =
                    bodyHeight < TerminalPanelMetrics.collapsedTotalHeight
                    ? bodyHeight
                    : TerminalPanelMetrics.collapsedTotalHeight;
                // Leave a usable editor area: never let the panel exceed 70%, and
                // never compress the editor body below its minimum so the code
                // view can still lay out (re_editor asserts on a zero height).
                const minEditorHeight = 140.0;
                final seventyPercent = (bodyHeight * 0.7).toDouble();
                final heightLimited = bodyHeight - minEditorHeight;
                final ceiling = seventyPercent < heightLimited
                    ? seventyPercent
                    : heightLimited;
                final maxPanelHeight = ceiling
                    .clamp(collapsedPanelHeight, bodyHeight)
                    .toDouble();
                // The AI panel keeps its own pre-existing geometry: a 36 px
                // collapsed header and its original 112 px compact threshold,
                // independent of the terminal's metrics.
                const aiCollapsedHeight = 36.0;
                final aiCompact = maxPanelHeight < 112;
                // The terminal is compact (header only) when the viewport cannot
                // offer at least its minimum expanded height.
                final compactByHeight =
                    maxPanelHeight < TerminalPanelMetrics.minExpandedHeight;
                // Protection: never collapse to the header-only layout while the
                // prompt input holds focus.
                //
                // Opening the soft keyboard shrinks the body, which can push
                // `maxPanelHeight` under the threshold. Collapsing then would
                // hide the very input the user is typing into behind the
                // keyboard — a visible, focused, zero-height field. Skipping the
                // compact state instead compresses the transcript (and the
                // editor), so the prompt row always stays on screen.
                //
                // This is a direct statement of the invariant ("a focused input
                // must never be hidden") and therefore safer than recomputing
                // the threshold from a keyboard-free height, which only works if
                // the inset accounting stays in sync with the Scaffold's.
                final compactPanel = compactByHeight && !_terminalInputHasFocus;
                // While dragging, the displayed height follows the raw gesture;
                // otherwise it is the preserved preference clamped to the
                // current viewport.
                final effectivePreferred =
                    _terminalDragHeight ?? _terminalHeight;
                // The lower bound must never exceed the upper one: with the
                // keyboard up, `maxPanelHeight` can fall below the preferred
                // minimum (that is exactly the case the protection above keeps
                // non-compact). Clamping to an inverted range throws, so the
                // floor collapses to `maxPanelHeight` in that window and the
                // prompt row simply gets whatever height remains.
                final minPanelHeight =
                    maxPanelHeight < TerminalPanelMetrics.minExpandedHeight
                    ? maxPanelHeight
                    : TerminalPanelMetrics.minExpandedHeight;
                final terminalPanelHeight = _terminalCollapsed || compactPanel
                    ? collapsedPanelHeight
                    : effectivePreferred
                          .clamp(minPanelHeight, maxPanelHeight)
                          .toDouble();
                final aiPanelHeight = _aiCollapsed || aiCompact
                    ? aiCollapsedHeight
                    : 320.0.clamp(aiCollapsedHeight, maxPanelHeight).toDouble();
                return ListenableBuilder(
                  listenable: _editor,
                  builder: (context, _) {
                    _syncTabControllerIfNeeded();
                    // Wide layout: the file tree owns one horizontal slot and the
                    // full body height, and the editor's bottom panels live
                    // inside the right-hand column. A panel therefore cannot
                    // stretch underneath the sidebar.
                    //
                    // The plain `Column` below does not need overflow handling:
                    // every panel height is clamped to `maxPanelHeight`, which
                    // already reserves `minEditorHeight` for the editor, and at
                    // most one panel is visible at a time. The terminal stays
                    // `Offstage` while another panel is selected, and the rest
                    // are keyed off `_bottomPanel`.
                    final layout = layoutOf(MediaQuery.sizeOf(context).width);
                    final agentHost = _agentHost;
                    final agentEnabled = agentHost != null && !focusMode;
                    final agentCollapsed =
                        agentHost?.state.agentPaneCollapsed ?? true;
                    final agentVisible =
                        agentEnabled &&
                        (layout == WorkbenchLayout.wide
                            ? !agentCollapsed
                            : agentHost.state.mainPane == MainPane.agent);
                    final agentPane = agentEnabled
                        ? _buildAgentPane(agentHost, active: agentVisible)
                        : null;
                    final body = Row(
                      key: const ValueKey('editor-body-wide'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide && !focusMode)
                          ClipRect(
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.centerLeft,
                              widthFactor: sidebarVisible ? 1.0 : 0.0,
                              child: Padding(
                                padding: const EdgeInsets.all(_cardMargin),
                                child: SizedBox(
                                  key: const ValueKey('editor-sidebar-slot'),
                                  width: _sidebarWidth,
                                  child: _buildSidebar(context),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: KeyedSubtree(
                            key: _editorColumnKey,
                            child: Column(
                              key: const ValueKey('editor-right-column'),
                              children: [
                                Expanded(child: _buildEditorArea(context)),
                                if (_terminalCreated)
                                  Offstage(
                                    // Hide the terminal entirely when the body
                                    // cannot host both a useful terminal and the
                                    // editor's minimum, so the code view never
                                    // collapses to zero height.
                                    //
                                    // Never while the prompt holds focus: hiding
                                    // it would detach the caret's element and
                                    // close the keyboard the user is typing on.
                                    // In that window the editor gives up height
                                    // instead (the `Expanded` above shrinks),
                                    // which is the lesser loss.
                                    offstage:
                                        _bottomPanel != _BottomPanel.terminal ||
                                        (!_terminalInputHasFocus &&
                                            bodyHeight -
                                                    (bodyHeight <
                                                            TerminalPanelMetrics
                                                                .collapsedTotalHeight
                                                        ? bodyHeight
                                                        : TerminalPanelMetrics
                                                              .collapsedTotalHeight) <
                                                minEditorHeight),
                                    child: _buildTerminalPanel(
                                      terminalPanelHeight: terminalPanelHeight,
                                      maxPanelHeight: maxPanelHeight,
                                      collapsedPanelHeight:
                                          collapsedPanelHeight,
                                      compactPanel: compactPanel,
                                    ),
                                  ),
                                if ({
                                      _BottomPanel.debug,
                                      _BottomPanel.output,
                                      _BottomPanel.debugConsole,
                                      _BottomPanel.ports,
                                    }.contains(_bottomPanel) &&
                                    bodyHeight >= minEditorHeight + 96)
                                  SizedBox(
                                    height: maxPanelHeight
                                        .clamp(96.0, 300.0)
                                        .toDouble(),
                                    child: _buildActivityPanel(),
                                  ),
                                if (_bottomPanel == _BottomPanel.problems &&
                                    bodyHeight >= minEditorHeight + 48)
                                  SizedBox(
                                    height: maxPanelHeight
                                        .clamp(48.0, 240.0)
                                        .toDouble(),
                                    child: EditorProblemsPanel(
                                      analysis: _analysis,
                                      onClose: () => setState(
                                        () => _bottomPanel = _BottomPanel.none,
                                      ),
                                    ),
                                  ),
                                if (_bottomPanel == _BottomPanel.ai &&
                                    bodyHeight >= 36)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    height: aiPanelHeight,
                                    child: AiPanel(
                                      projectPath: widget.project.path,
                                      projectName: widget.project.name,
                                      language: widget.project.language,
                                      settings: widget.settings,
                                      auth: widget.auth,
                                      compact: aiCompact,
                                      onCollapseChanged: (collapsed) {
                                        if (mounted) {
                                          setState(
                                            () => _aiCollapsed = collapsed,
                                          );
                                        }
                                      },
                                      onClose: () {
                                        if (mounted) {
                                          setState(() {
                                            _bottomPanel = _BottomPanel.none;
                                            _aiCollapsed = false;
                                          });
                                        }
                                      },
                                      onFileCreated: (path) {
                                        _editor.openPath(path);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (agentEnabled && layout == WorkbenchLayout.wide)
                          SizedBox(
                            width: agentCollapsed
                                ? _agentRailWidth
                                : Breakpoints.agentPaneWidth,
                            child: _buildAgentDockStack(
                              agentHost,
                              collapsed: agentCollapsed,
                              pane: agentPane,
                            ),
                          ),
                      ],
                    );
                    // Body 铺到屏幕底边；Android 的导航条由这里让开，内部控件
                    // （终端面板、输入卡片、底部面板）跟着一起上移。
                    if (agentEnabled && layout != WorkbenchLayout.wide) {
                      return EditorBottomInset(
                        inset: bottomInset,
                        child: AgentPaneSwitcher(
                          state: agentHost.state,
                          editor: body,
                          agent: agentPane!,
                        ),
                      );
                    }
                    return EditorBottomInset(inset: bottomInset, child: body);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 防止在 build 外的监听回调中漏同步（不在 build 期间 setState）。
  void _syncTabControllerIfNeeded() {
    final count = _editor.files.length;
    if (_tabController == null && count > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController == null && _editor.files.isNotEmpty) {
          _syncTabController();
        }
      });
    }
  }

  /// The embedded terminal panel. Owns the authoritative collapsed state and
  /// the continuous resize gesture. Height animation is disabled while the user
  /// is actively dragging so the panel tracks the pointer without lag.
  Widget _buildTerminalPanel({
    required double terminalPanelHeight,
    required double maxPanelHeight,
    required double collapsedPanelHeight,
    required bool compactPanel,
  }) {
    final pane = TerminalPane(
      key: _terminalKey,
      workingDirectory: widget.project.path,
      auth: widget.auth,
      onlineEnabled: StudioProfile.current?.offlineOnly != true,
      executionBlocked: _debugger.busy || _runningFileTool,
      isExecutionBlocked: () => _debugger.busy || _runningFileTool,
      onRunningWorkChanged: (running) {
        if (!mounted) return;
        setState(() {
          if (!running && _closeTerminalWhenIdle) {
            _terminalCreated = false;
            _closeTerminalWhenIdle = false;
          }
        });
      },
      compact: compactPanel,
      collapsed: _terminalCollapsed,
      onCollapseChanged: (collapsed) {
        if (!mounted) return;
        setState(() {
          _terminalCollapsed = collapsed;
          if (!collapsed) {
            // A fresh expand carries the last user-preferred height back in.
            _terminalDragHeight = null;
          }
        });
      },
      onResizeStart: () {
        if (!mounted) return;
        setState(() {
          _draggingTerminal = true;
          _terminalDragAnchor = _terminalCollapsed
              ? collapsedPanelHeight
              : terminalPanelHeight;
          _terminalDragTotal = _terminalDragAnchor;
          _terminalDragHeight = _terminalDragAnchor;
          // A resize gesture must not pop the soft keyboard.
          _terminalKey.currentState?.unfocusInput();
        });
      },
      onResizeDelta: (delta) {
        if (!mounted) return;
        setState(() {
          // Accumulate the raw displacement unclamped so many small steps can
          // cross the collapse threshold or grow past the minimum.
          final anchor = _terminalDragAnchor > 0
              ? _terminalDragAnchor
              : (_terminalCollapsed
                    ? collapsedPanelHeight
                    : terminalPanelHeight);
          _terminalDragAnchor = anchor;
          _terminalDragTotal += delta;
          final next = _terminalDragTotal;
          if (next < TerminalPanelMetrics.collapseThreshold) {
            // Below the threshold the panel is collapsed to its header.
            _terminalCollapsed = true;
            _terminalDragHeight = collapsedPanelHeight;
            return;
          }
          _terminalCollapsed = false;
          final minExpanded =
              maxPanelHeight < TerminalPanelMetrics.minExpandedHeight
              ? maxPanelHeight
              : TerminalPanelMetrics.minExpandedHeight;
          // Clamp only the displayed drag height; the raw total keeps moving so
          // a drag can continue through the clamped band without stalling.
          _terminalDragHeight = next
              .clamp(minExpanded, maxPanelHeight)
              .toDouble();
        });
      },
      onResizeEnd: () {
        if (!mounted) return;
        setState(() {
          _draggingTerminal = false;
          // Commit the final expanded height as the preserved preference; a
          // collapsed end keeps the previous preferred height intact.
          final committed = _terminalDragHeight;
          if (!_terminalCollapsed && committed != null) {
            _terminalHeight = committed;
          }
          _terminalDragHeight = null;
        });
      },
      // Touching the terminal re-opens it and puts the caret in the prompt.
      // Expand first: the editor owns `_terminalCollapsed`, and focusing an
      // input that is still collapsed (zero height) would be lost.
      onActivated: () {
        EditorPageDiag.diag(
          'EditorPage.onActivated collapsed-before=$_terminalCollapsed '
          'visible=$_terminalVisible focusBefore='
          '${FocusManager.instance.primaryFocus?.debugLabel}',
        );
        if (!mounted) return;
        final needsExpand = _terminalCollapsed;
        if (!needsExpand) {
          // Already open: just make sure the caret is in the prompt.
          _terminalKey.currentState?.requestInputFocus();
          return;
        }
        setState(() {
          _terminalCollapsed = false;
          // A fresh expand carries the last user-preferred height back in.
          _terminalDragHeight = null;
        });
        // Focus after the expanded layout is on screen, otherwise the focus
        // request lands on a zero-height input and is dropped.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _terminalKey.currentState?.requestInputFocus();
        });
      },
      // Track the prompt's focus so `build` can refuse to collapse the panel to
      // its header-only layout while the user is typing.
      onInputFocusChanged: (focused) {
        if (!mounted || focused == _terminalInputHasFocus) return;
        setState(() => _terminalInputHasFocus = focused);
      },
      onClose: () {
        if (mounted) {
          final busy = _terminalKey.currentState?.hasRunningWork == true;
          setState(() {
            _bottomPanel = _BottomPanel.none;
            _terminalCollapsed = false;
            _terminalCreated = busy;
            _closeTerminalWhenIdle = busy;
            _terminalDragHeight = null;
            _draggingTerminal = false;
            _terminalInputHasFocus = false;
          });
        }
      },
    );

    // During an active drag (or once collapsed to the header), skip the height
    // animation entirely so the panel follows the pointer without a 150ms lag.
    // Skip the height animation when dragging, collapsed, or compact: an
    // animated transition through a tiny height briefly starves the editor body
    // (re_editor asserts on a zero-height line-number column).
    //
    // Also skip it while the prompt holds focus: the keyboard is then shrinking
    // the body every frame, and animating the panel toward its new height would
    // transiently overshoot the available space and overflow the body Column.
    if (_draggingTerminal ||
        _terminalCollapsed ||
        compactPanel ||
        _terminalInputHasFocus) {
      return SizedBox(height: terminalPanelHeight, child: pane);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: terminalPanelHeight,
      child: pane,
    );
  }

  /// 文件树卡片：外观（圆角 + 细描边、无阴影）由 [FileExplorer] 自绘。
  Widget _buildExplorerCard(
    BuildContext context, {
    VoidCallback? onFileOpened,
    Widget? headerTrailing,
    FileExplorerSections? sections,
  }) {
    return FileExplorer(
      headerTrailing: headerTrailing,
      sections: sections,
      project: widget.project,
      editor: _editor,
      store: widget.store,
      settings: widget.settings,
      onFileOpened: onFileOpened,
      workspace: _workspace,
      workspaceMembers: _workspaceMembers,
      workspaceStore: widget.workspaceStore,
      onWorkspaceChanged: _onWorkspaceChanged,
      onProjectSelected: (project) {
        final select = widget.onProjectSelected;
        if (select != null) {
          select(project);
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => EditorPage(
              project: project,
              auth: widget.auth,
              store: widget.store,
              settings: widget.settings,
              workspaceStore: widget.workspaceStore,
              agentEnabled: widget.agentEnabled,
            ),
          ),
        );
      },
      onEntryDeleted: _cloud == null
          ? null
          : (path) async {
              final token = widget.auth.token;
              if (token == null) return;
              final error = await _cloud!.pushDelete(token, path);
              if (mounted) setState(() => _syncError = error);
            },
    );
  }

  Widget _buildProjectTitle(BuildContext context, ColorScheme scheme) {
    // AppBar 的 titleSpacing 为 0，这里补回标题原本的 16px 起始间距。
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            _workspace == null
                ? _currentFileSubtitle()
                : '工作区「${_workspace!.name}」 · ${_currentFileSubtitle()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorArea(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = _editor.current;
    if (open == null || _tabController == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '在左侧选择要编辑的文件',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed chrome (tab bar + symbols bar + status bar) must never starve
        // the code view: re_editor asserts when its height reaches zero. Shed
        // optional chrome as the available height shrinks.
        final available = constraints.maxHeight;
        final contribution = _inlineDocumentFor(open);
        final focused = _inlineFocusDocuments.contains(open);
        final showTabs =
            !focused && widget.settings.showEditorTabs && available >= 220;
        final showSymbols =
            !focused &&
            available >= 160 &&
            (contribution?.showCoreSymbols ?? true);
        final showStatus =
            !focused &&
            available >= 110 &&
            (contribution?.showCoreStatus ?? true);
        return Column(
          children: [
            if (showTabs) _buildTabBar(context),
            Expanded(
              child: _editor.files.length <= 1 || !showTabs
                  ? _buildDocumentView(context, open)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        for (final file in _editor.files)
                          TickerMode(
                            key: ObjectKey(file),
                            enabled: identical(file, open),
                            child: _codeViews.putIfAbsent(
                              file,
                              () => RetainedPage(
                                child: _buildDocumentView(context, file),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (showSymbols)
              SymbolsBar(
                language:
                    languageForFileName(
                      open.name,
                      ownerType: open.projectType,
                    ).isNotEmpty
                    ? languageForFileName(
                        open.name,
                        ownerType: open.projectType,
                      )
                    : widget.project.language,
                controller: open.controller,
                symbols: _symbolsFor(open),
                onSymbolsEdited: (tokens) {
                  final lang =
                      languageForFileName(
                        open.name,
                        ownerType: open.projectType,
                      ).isNotEmpty
                      ? languageForFileName(
                          open.name,
                          ownerType: open.projectType,
                        )
                      : widget.project.language;
                  widget.settings.setSymbolBar(lang, tokens.join(' '));
                  setState(() {});
                },
              ),
            if (showStatus) _buildStatusBar(context, open),
          ],
        );
      },
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: [for (final file in _editor.files) _buildTab(context, file)],
      ),
    );
  }

  Widget _buildTab(BuildContext context, OpenFile open) {
    final scheme = Theme.of(context).colorScheme;
    final tab = Tab(
      height: 44,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              open.timeLabel != null ? Icons.history : _iconFor(open.name),
              size: 16,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Text(open.tabLabel(widget.project.name)),
            const SizedBox(width: 8),
            if (open.dirty)
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              )
            else
              GestureDetector(
                onTap: () => _closeTab(_editor.files.indexOf(open)),
                child: Icon(
                  Icons.close,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
    // 长按 / 右键：标签操作菜单。
    return GestureDetector(
      onLongPressStart: (details) => _showTabMenu(open, details.globalPosition),
      onSecondaryTapUp: (details) => _showTabMenu(open, details.globalPosition),
      child: tab,
    );
  }

  Future<void> _showTabMenu(OpenFile open, Offset position) async {
    final index = _editor.files.indexOf(open);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: const [
        PopupMenuItem(value: 'share', child: Text('分享文件')),
        PopupMenuItem(value: 'copy_name', child: Text('复制文件名')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'close_this', child: Text('关闭当前标签')),
        PopupMenuItem(value: 'close_others', child: Text('关闭其他标签')),
        PopupMenuItem(value: 'close_all', child: Text('关闭所有标签')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'share':
        final shared = await ShareService.shareText(
          title: open.name,
          text: open.controller.text,
        );
        if (!shared && mounted) {
          copyWithToast(context, '【${open.name}】\n${open.controller.text}');
        }
      case 'copy_name':
        copyWithToast(context, open.name);
      case 'close_this':
        await _closeTab(index);
      case 'close_others':
        if (await _confirmDiscardDirty(except: open)) {
          _editor.closeAll(keep: open);
        }
      case 'close_all':
        if (await _confirmDiscardDirty()) {
          _editor.closeAll();
        }
    }
  }

  /// 批量关闭前确认未保存内容。
  Future<bool> _confirmDiscardDirty({OpenFile? except}) async {
    final dirty = _editor.files
        .where((f) => f.dirty && (except == null || !identical(f, except)))
        .toList();
    if (dirty.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有未保存的更改'),
        content: Text('${dirty.length} 个文件未保存，丢弃并继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('丢弃'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _closeTab(int index) async {
    final open = _editor.files[index];
    if (open.dirty) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('未保存的更改'),
          content: Text('“${open.name}”有未保存的更改，保存后再关闭吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text('不保存'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || action == 'cancel') return;
      if (action == 'save') {
        final error = await _editor.saveFile(
          open,
          shouldSave: () =>
              mounted && _editor.files.contains(open) && !_isOrphaned(open),
        );
        if (!mounted) return;
        if (error != null) {
          _showSnack(error);
          return;
        }
      }
    }
    final currentIndex = _editor.files.indexOf(open);
    if (currentIndex >= 0) _editor.closeAt(currentIndex);
  }

  Widget _buildCodeView(BuildContext context, OpenFile open) {
    // Fires once per newly built code view: the point at which the entry file is
    // actually on screen and the user can type.
    OpenPerformance.mark('code view built (interactive)');
    final scheme = Theme.of(context).colorScheme;
    final contribution = _inlineDocumentFor(open);
    final sourceTextStyle = contribution?.sourceTextStyle;
    final textStyle = sourceTextStyle ?? widget.settings.editorTextStyle;
    final fontSize = sourceTextStyle?.fontSize ?? _fontSize;
    final theme = contribution?.sourceHighlightEnabled == false
        ? null
        : HighlightThemes.themeFor(
            context,
            open.name,
            null,
            settings: widget.settings,
            ownerType: open.projectType,
          );
    return EditorProblemsBar(
      analysis: _analysis,
      onOpenProblems: () => setState(() {
        _terminalKey.currentState?.unfocusInput();
        _bottomPanel = _BottomPanel.problems;
      }),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerUp,
              child: CodeEditor(
                controller: _inlineSourceControllers[open] ?? open.controller,
                focusNode: open.focusNode,
                scrollController: open.scrollController,
                findController: open.findController,
                shortcutOverrideActions: {
                  ...editorShortcutOverrides(open.controller),
                  ...?contribution?.shortcutOverrideActions,
                },
                style: CodeEditorStyle(
                  fontSize: fontSize,
                  fontFamily: textStyle.fontFamily,
                  fontFamilyFallback: textStyle.fontFamilyFallback,
                  fontWeight: textStyle.fontWeight,
                  fontStyle: textStyle.fontStyle,
                  fontHeight: textStyle.height,
                  backgroundColor:
                      theme?.theme['root']?.backgroundColor ?? scheme.surface,
                  textColor: theme?.theme['root']?.color ?? scheme.onSurface,
                  cursorColor:
                      HighlightThemes.editorColor(
                        widget.settings,
                        'editorCursor.foreground',
                      ) ??
                      scheme.primary,
                  selectionColor:
                      HighlightThemes.editorColor(
                        widget.settings,
                        'editor.selectionBackground',
                      ) ??
                      scheme.primary.withValues(alpha: 0.25),
                  highlightColor: scheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  cursorLineColor:
                      HighlightThemes.editorColor(
                        widget.settings,
                        'editor.lineHighlightBackground',
                      ) ??
                      scheme.surfaceContainerHighest,
                  chunkIndicatorColor: scheme.outlineVariant,
                  codeTheme: theme,
                ),
                wordWrap: false,
                autofocus: false,
                readOnly: open.readOnly,
                indicatorBuilder:
                    (context, editingController, chunkController, notifier) {
                      return Row(
                        children: [
                          if (_debugger.debugger != null && !open.readOnly)
                            EditorDebugGutter(
                              debug: _debugger,
                              file: open,
                              notifier: notifier,
                            ),
                          if (open.diagnostics case final diagnostics?)
                            EditorDiagnosticGutter(
                              diagnostics: diagnostics,
                              notifier: notifier,
                            ),
                          DefaultCodeLineNumber(
                            controller: editingController,
                            notifier: notifier,
                            minNumberCount: 1,
                            textStyle: textStyle.copyWith(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
                              fontSize: fontSize,
                            ),
                            focusedTextStyle: textStyle.copyWith(
                              color: scheme.primary,
                              fontSize: fontSize,
                            ),
                          ),
                          DefaultCodeChunkIndicator(
                            width: 18,
                            controller: chunkController,
                            notifier: notifier,
                          ),
                        ],
                      );
                    },
                findBuilder: (context, controller, readOnly) =>
                    EditorFindReplacePanel(
                      controller: controller,
                      readOnly: readOnly,
                    ),
              ),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
          if (widget.settings.minimap)
            CodeMinimap(
              controller: open.controller,
              scrollController: open.scrollController,
            ),
        ],
      ),
    );
  }

  Future<void> _showEncodingDialog(OpenFile open) async {
    final index = _editor.currentIndex;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件编码'),
        content: Text(
          '当前：${open.encoding}\n'
          '选择新编码后文件将以该编码重新打开，下次保存时写盘也使用它。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.only(bottom: 8),
        actions: [
          for (final name in TextCodec.names)
            ListTile(
              dense: true,
              title: Text(name),
              trailing: open.encoding == name ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(name),
            ),
        ],
      ),
    );
    if (picked == null || picked == open.encoding || !mounted) return;
    final error = await _editor.reopenWithEncoding(index, picked);
    if (!mounted) return;
    if (error != null) _showSnack(error);
  }

  /// 当前文件的快捷符号集：用户自定义优先，否则按语言默认。
  List<String> _symbolsFor(OpenFile open) {
    final lang =
        languageForFileName(open.name, ownerType: open.projectType).isNotEmpty
        ? languageForFileName(open.name, ownerType: open.projectType)
        : widget.project.language;
    final custom = widget.settings.symbolBars[lang];
    if (custom != null) {
      final value = custom.trim();
      if (value.isEmpty) return const [];
      return value.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }
    return kDefaultSymbolSets[lang] ??
        const [';', ':', '(', ')', '[', ']', '"', "'", '=', '<', '>'];
  }

  Widget _buildStatusBar(BuildContext context, OpenFile open) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([open.controller, widget.settings]),
      builder: (context, _) {
        final selection = open.controller.selection;
        final line = selection.extentIndex + 1;
        final column = selection.extentOffset + 1;
        final totalLines = open.controller.codeLines.length;
        String modifiedLabel = '';
        final modified = open.modifiedAt;
        if (modified != null) {
          final now = DateTime.now();
          final m = modified;
          modifiedLabel =
              (m.year == now.year && m.month == now.month && m.day == now.day)
              ? '修改于 ${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}'
              : '修改于 ${m.month}/${m.day}';
        }
        return Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                // 编码 chip：点击弹出编码选择，重新解码文件（保存时应用）。
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showEncodingDialog(open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.abc_outlined,
                          size: 13,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          open.encoding,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (constraints.maxWidth >= 520 &&
                    modifiedLabel.isNotEmpty) ...[
                  Text(
                    modifiedLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    '第 $line 行，第 $column 列 · 共 $totalLines 行',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.project.isCloud) ...[
                  const SizedBox(width: 12),
                  Icon(
                    switch (_syncState) {
                      SyncState.syncing => Icons.cloud_sync_outlined,
                      SyncState.synced => Icons.cloud_done_outlined,
                      SyncState.offline => Icons.cloud_off_outlined,
                      SyncState.idle => Icons.cloud_outlined,
                    },
                    size: 14,
                    color: switch (_syncState) {
                      SyncState.offline => scheme.error,
                      _ => scheme.primary,
                    },
                  ),
                  if (_syncError != null) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _syncError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ],
                if (open.dirty && !widget.project.isCloud) ...[
                  const SizedBox(width: 12),
                  Text(
                    '未保存',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.primary),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconFor(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    return switch (ext) {
      '.dart' => Icons.flutter_dash,
      '.json' => Icons.data_object,
      '.html' || '.htm' => Icons.web_outlined,
      '.md' || '.txt' => Icons.article_outlined,
      _ => Icons.code_outlined,
    };
  }
}
