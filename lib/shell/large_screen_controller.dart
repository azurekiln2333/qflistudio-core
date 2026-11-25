import 'package:flutter/material.dart';

import '../layout/app_form_factor.dart';
import '../models/project.dart';
import '../services/app_paths.dart';
import '../layout/breakpoints.dart';
import 'workbench_chrome.dart';

enum ExplorerPage { projects, files }

/// Presentation state only. Project, editor and Agent lifetimes remain with
/// their existing owners. Resizing never replaces this controller.
class LargeScreenController extends ChangeNotifier {
  static const double minSidebarWidth = 220;
  static const double maxSidebarWidth = 480;
  static const double defaultSidebarWidth = Breakpoints.sidebarWidth;

  WorkbenchActivity _activity = WorkbenchActivity.explorer;
  ExplorerPage _explorerPage = ExplorerPage.projects;
  bool _sidebarVisible = true;
  bool _compact = false;
  bool _disposed = false;
  bool _scheduled = false;
  double _sidebarWidth = defaultSidebarWidth;
  Object? _activeEditor;
  final Map<Object, WidgetBuilder> _files = {};
  WidgetBuilder? _centerOverlay;

  WorkbenchActivity get activity => _activity;
  ExplorerPage get explorerPage => _explorerPage;
  bool get sidebarVisible => _sidebarVisible;
  bool get compact => _compact;
  double get sidebarWidth => _sidebarWidth;

  Object? _projectActionsOwner;
  VoidCallback? _createProject;
  VoidCallback? _openFolder;
  VoidCallback? _cloneRepository;
  ValueChanged<Project>? _openRecent;

  // The retained project panel owns the existing dialog/clone lifetimes.
  // Binding callbacks during its build does not notify or rebuild editors.
  void bindProjectActions(
    Object owner, {
    required VoidCallback create,
    required VoidCallback openFolder,
    required VoidCallback clone,
    required ValueChanged<Project> openRecent,
  }) {
    _projectActionsOwner = owner;
    _createProject = create;
    _openFolder = openFolder;
    _cloneRepository = clone;
    _openRecent = openRecent;
  }

  void unbindProjectActions(Object owner) {
    if (!identical(owner, _projectActionsOwner)) return;
    _projectActionsOwner = null;
    _createProject = _openFolder = _cloneRepository = null;
    _openRecent = null;
  }

  void createProject() => _createProject?.call();
  void openFolder() => _openFolder?.call();
  void cloneRepository() => _cloneRepository?.call();
  void openRecent(Project project) => _openRecent?.call(project);
  Object? get activeEditor => _activeEditor;
  Map<Object, WidgetBuilder> get filePanels => Map.unmodifiable(_files);

  /// 中央区域临时显示的内容，例如没有项目可落的 Agent 会话。
  ///
  /// 不为空时中央显示它，编辑器宿主保留在后台。打开任何项目都会清掉它。
  WidgetBuilder? get centerOverlay => _centerOverlay;

  void showCenterOverlay(WidgetBuilder builder) {
    _centerOverlay = builder;
    if (!showsWorkspace) _activity = WorkbenchActivity.agents;
    closeCompactSidebar();
    notifyListeners();
  }

  void closeCenterOverlay() {
    if (_centerOverlay == null) return;
    _centerOverlay = null;
    notifyListeners();
  }

  bool get showsWorkspace => switch (_activity) {
    WorkbenchActivity.explorer || WorkbenchActivity.agents => true,
    _ => false,
  };

  void select(WorkbenchActivity next, {bool toggle = true}) {
    final same = next == _activity;
    _activity = next;
    if (showsWorkspace) {
      _sidebarVisible = same && toggle ? !_sidebarVisible : true;
    }
    notifyListeners();
  }

  void showWorkspace() {
    if (showsWorkspace) return;
    _activity = WorkbenchActivity.explorer;
    notifyListeners();
  }

  void toggleSidebar() {
    if (!showsWorkspace) {
      _activity = WorkbenchActivity.explorer;
      _sidebarVisible = true;
    } else {
      _sidebarVisible = !_sidebarVisible;
    }
    notifyListeners();
  }

  void showProjects() {
    _activity = WorkbenchActivity.explorer;
    _explorerPage = ExplorerPage.projects;
    _sidebarVisible = true;
    notifyListeners();
  }

  void showFiles() {
    // An editor registers its tree on the following frame. Opening a project
    // may request this page before the panel is registered.
    _activity = WorkbenchActivity.explorer;
    _explorerPage = ExplorerPage.files;
    _sidebarVisible = true;
    notifyListeners();
  }

  void closeCompactSidebar() {
    if (!_compact || !_sidebarVisible) return;
    _sidebarVisible = false;
    notifyListeners();
  }

  /// Updates the retained sidebar width without changing the current page.
  void setSidebarWidth(double width) {
    if (!width.isFinite) return;
    final next = width.clamp(minSidebarWidth, maxSidebarWidth).toDouble();
    if ((next - _sidebarWidth).abs() < 0.1) return;
    _sidebarWidth = next;
    notifyListeners();
  }

  /// Restores the IDE default width after a double-click on the divider.
  void resetSidebarWidth() {
    if (_sidebarWidth == defaultSidebarWidth) return;
    _sidebarWidth = defaultSidebarWidth;
    notifyListeners();
  }

  // Layout information is sampled by the owner during build. It does not
  // notify or affect device-family selection.
  void setCompact(bool value) => _compact = value;

  void registerFiles(Object owner, WidgetBuilder builder) {
    if (identical(_files[owner], builder)) return;
    _files[owner] = builder;
    _notifyAfterFrame();
  }

  void activateFiles(Object? owner) {
    if (_activeEditor == owner) return;
    _activeEditor = owner;
    _notifyAfterFrame();
  }

  void refreshFiles() => _notifyAfterFrame();

  void unregisterFiles(Object owner) {
    _files.remove(owner);
    if (_activeEditor == owner) {
      _activeEditor = null;
      _explorerPage = ExplorerPage.projects;
    }
    _notifyAfterFrame();
  }

  void _notifyAfterFrame() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_projectActionsOwner case final owner?) unbindProjectActions(owner);
    _files.clear();
    super.dispose();
  }
}

/// Deliberately not an InheritedNotifier: changing the sidebar must not rebuild
/// the editor tree or its runtime. Only chrome and panel owners subscribe.
class LargeScreenScope extends InheritedWidget {
  const LargeScreenScope({
    super.key,
    required this.controller,
    this.formFactor,
    required super.child,
  });

  final LargeScreenController controller;
  final AppFormFactor? formFactor;

  /// Uses the resolved device family, including deterministic app overrides.
  /// Bare module fixtures retain their native platform default.
  static bool isDesktop(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LargeScreenScope>();
    return scope?.formFactor == null
        ? AppPaths.isDesktop
        : scope!.formFactor == AppFormFactor.desktop;
  }

  static LargeScreenController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LargeScreenScope>()
      ?.controller;

  @override
  bool updateShouldNotify(LargeScreenScope oldWidget) =>
      oldWidget.controller != controller || oldWidget.formFactor != formFactor;
}
