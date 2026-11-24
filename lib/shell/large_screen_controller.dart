import 'package:flutter/material.dart';

import 'workbench_chrome.dart';

/// Presentation state only. Project, editor and Agent lifetimes remain with
/// their existing owners. Resizing never replaces this controller.
class LargeScreenController extends ChangeNotifier {
  WorkbenchActivity _activity = WorkbenchActivity.projects;
  bool _sidebarVisible = true;
  bool _compact = false;
  bool _disposed = false;
  bool _scheduled = false;
  Object? _activeEditor;
  final Map<Object, WidgetBuilder> _files = {};
  WidgetBuilder? _centerOverlay;

  WorkbenchActivity get activity => _activity;
  bool get sidebarVisible => _sidebarVisible;
  bool get compact => _compact;
  Object? get activeEditor => _activeEditor;
  Map<Object, WidgetBuilder> get filePanels => Map.unmodifiable(_files);

  /// 中央区域临时显示的内容，例如没有项目可落的 Agent 会话。
  ///
  /// 不为空时中央显示它，编辑器宿主保留在后台。打开任何项目都会清掉它。
  WidgetBuilder? get centerOverlay => _centerOverlay;

  void showCenterOverlay(WidgetBuilder builder) {
    _centerOverlay = builder;
    notifyListeners();
  }

  void closeCenterOverlay() {
    if (_centerOverlay == null) return;
    _centerOverlay = null;
    notifyListeners();
  }

  bool get showsWorkspace => switch (_activity) {
    WorkbenchActivity.projects ||
    WorkbenchActivity.files ||
    WorkbenchActivity.agents => true,
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
    _activity = WorkbenchActivity.projects;
    notifyListeners();
  }

  void closeCompactSidebar() {
    if (!_compact || !_sidebarVisible) return;
    _sidebarVisible = false;
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
    if (_activeEditor == owner) _activeEditor = null;
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
    required super.child,
  });

  final LargeScreenController controller;

  static LargeScreenController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LargeScreenScope>()
      ?.controller;

  @override
  bool updateShouldNotify(LargeScreenScope oldWidget) =>
      oldWidget.controller != controller;
}
