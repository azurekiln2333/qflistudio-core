import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import 'editor_page.dart';

/// Opens a live project, or resumes its existing editor. Hosted opens finish
/// immediately; standalone callers keep the ordinary Navigator route lifetime.
Future<void> openEditorPage(
  BuildContext context, {
  required Project project,
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
  String? initialOpenPath,
}) async {
  final controller = RetainedEditorScope.maybeOf(context);
  if (controller != null) {
    controller.open(
      project: project,
      auth: auth,
      store: store,
      settings: settings,
      initialOpenPath: initialOpenPath,
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => EditorPage(
        project: project,
        auth: auth,
        store: store,
        settings: settings,
        initialOpenPath: initialOpenPath,
      ),
    ),
  );
}

class RetainedEditorScope extends InheritedNotifier<RetainedEditorController> {
  const RetainedEditorScope({
    super.key,
    required RetainedEditorController controller,
    required super.child,
  }) : super(notifier: controller);

  static RetainedEditorController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RetainedEditorScope>()
      ?.notifier;
}

/// Owns mounted editor lifetimes, independently of the Home route stack.
class RetainedEditorController extends ChangeNotifier {
  RetainedEditorController() {
    _rootObserver = _RootEditorObserver(this);
  }

  late final _RootEditorObserver _rootObserver;
  NavigatorObserver get navigatorObserver => _rootObserver;
  final _sessions = <String, _EditorSession>{};
  String? _active;
  String? _lastActive;
  bool _handlingBack = false;
  bool _selectingProject = false;

  bool get isVisible => _active != null;
  Project? get activeProject => _sessions[_active]?.project;
  List<Project> get projects =>
      List.unmodifiable(_sessions.values.map((session) => session.project));

  String _projectKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  void open({
    required Project project,
    required AuthStore auth,
    required ProjectStore store,
    required SettingsStore settings,
    String? initialOpenPath,
  }) {
    final key = _projectKey(project.path);
    final session = _sessions.putIfAbsent(
      key,
      () => _EditorSession(project, auth, store, settings),
    );
    if (initialOpenPath != null) {
      session.initialOpenPath = initialOpenPath;
      session.openRequest++;
    }
    _activate(key);
  }

  void resume(Project project) {
    final key = _projectKey(project.path);
    if (_sessions.containsKey(key)) _activate(key);
  }

  void _activate(String key) {
    if (_active != key) _sessions[_active]?.visible.value = false;
    FocusManager.instance.primaryFocus?.unfocus();
    _active = _lastActive = key;
    _sessions[key]!.visible.value = true;
    _rootObserver.setEditorVisible(true);
    notifyListeners();
  }

  void minimize() {
    if (!isVisible) return;
    // Capture live view state before mobile re_editor handles focus loss.
    _sessions[_active]!.visible.value = false;
    FocusManager.instance.primaryFocus?.unfocus();
    _active = null;
    _rootObserver.setEditorVisible(false);
    notifyListeners();
  }

  void _setSelectingProject(bool selecting) {
    _selectingProject = selecting;
    notifyListeners();
  }

  // Only EditorPage's explicit close action calls this, after dirty-file
  // confirmation. Minimize and project switching never remove a session.
  void _close(String key) {
    FocusManager.instance.primaryFocus?.unfocus();
    _sessions.remove(key)?.visible.dispose();
    if (_active == key) _active = null;
    if (_lastActive == key) {
      _lastActive = _sessions.isEmpty ? null : _sessions.keys.last;
    }
    _rootObserver.setEditorVisible(isVisible);
    notifyListeners();
  }

  Future<void> _back() async {
    if (_handlingBack || !isVisible) return;
    _handlingBack = true;
    final key = _active;
    try {
      final navigator = _sessions[key]?.navigatorKey.currentState;
      final handled = await navigator?.maybePop() ?? false;
      if (!handled && _active == key) minimize();
    } finally {
      _handlingBack = false;
    }
  }

  @override
  void dispose() {
    _rootObserver.detach();
    for (final session in _sessions.values) {
      session.visible.dispose();
    }
    super.dispose();
  }
}

class _EditorSession {
  _EditorSession(this.project, this.auth, this.store, this.settings);

  final Project project;
  final AuthStore auth;
  final ProjectStore store;
  final SettingsStore settings;
  final navigatorKey = GlobalKey<NavigatorState>();
  final visible = ValueNotifier<bool>(false);
  String? initialOpenPath;
  int openRequest = 0;
}

/// Place in MaterialApp.builder, above and alongside the root Navigator.
/// Each editor's Navigator is therefore its own root for dialogs and menus.
class RetainedEditorHost extends StatelessWidget {
  const RetainedEditorHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final RetainedEditorController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => RetainedEditorScope(
    controller: controller,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Overlay.wrap(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _retained(visible: !controller.isVisible, child: child),
            for (final entry in controller._sessions.entries)
              _retained(
                key: ValueKey(entry.key),
                visible: controller._active == entry.key,
                child: HeroControllerScope.none(
                  child: NotificationListener<NavigationNotification>(
                    onNotification: (_) => true,
                    child: ScaffoldMessenger(
                      child: Navigator(
                        key: entry.value.navigatorKey,
                        onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => _SessionEditor(
                            controller: controller,
                            sessionKey: entry.key,
                            session: entry.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!controller.isVisible &&
                !controller._selectingProject &&
                controller._sessions.isNotEmpty)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(24),
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                controller._activate(controller._lastActive!),
                            icon: const Icon(Icons.code),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                '返回编辑器 · ${controller._sessions[controller._lastActive]!.project.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (controller._sessions.length > 1)
                            Builder(
                              builder: (context) => IconButton(
                                tooltip: '切换编辑器',
                                icon: const Icon(Icons.expand_less),
                                onPressed: () =>
                                    unawaited(_showSessionMenu(context)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showSessionMenu(BuildContext anchorContext) async {
    // The restore control is a sibling of the root Navigator, so its context
    // cannot be used with showMenu. Use the observed Navigator's own Overlay.
    final navigator = controller.navigatorObserver.navigator;
    final overlay = navigator?.overlay;
    if (navigator == null || overlay == null) return;
    final anchor = anchorContext.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    // These render boxes are siblings. Convert through global coordinates;
    // passing overlayBox as localToGlobal's ancestor would be invalid.
    final rect = Rect.fromPoints(
      overlayBox.globalToLocal(anchor.localToGlobal(Offset.zero)),
      overlayBox.globalToLocal(
        anchor.localToGlobal(anchor.size.bottomRight(Offset.zero)),
      ),
    );
    // The host paints above the root Overlay. Hide its restore control while
    // the modal menu is open so it cannot cover items or intercept the barrier.
    controller._setSelectingProject(true);
    String? selected;
    try {
      selected = await showMenu<String>(
        context: overlay.context,
        position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
        items: [
          for (final entry in controller._sessions.entries)
            PopupMenuItem(
              value: entry.key,
              child: Text(entry.value.project.name),
            ),
        ],
      );
    } finally {
      if (navigator.mounted) controller._setSelectingProject(false);
    }
    if (selected != null &&
        navigator.mounted &&
        controller._sessions.containsKey(selected)) {
      controller._activate(selected);
    }
  }

  Widget _retained({Key? key, required bool visible, required Widget child}) =>
      Offstage(
        key: key,
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: ExcludeFocus(excluding: !visible, child: child),
        ),
      );
}

// The route's builder keeps the same EditorPage state while requests change.
class _SessionEditor extends StatelessWidget {
  const _SessionEditor({
    required this.controller,
    required this.sessionKey,
    required this.session,
  });

  final RetainedEditorController controller;
  final String sessionKey;
  final _EditorSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => EditorPage(
      project: session.project,
      auth: session.auth,
      store: session.store,
      settings: session.settings,
      initialOpenPath: session.initialOpenPath,
      openRequest: session.openRequest,
      retainedVisibility: session.visible,
      onMinimize: controller.minimize,
      onClose: () => controller._close(sessionKey),
    ),
  );
}

class _EditorPopEntry extends PopEntry<Object?> {
  _EditorPopEntry(this.controller);

  final RetainedEditorController controller;
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(true);

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && controller.isVisible) unawaited(controller._back());
  }
}

// A PopScope in MaterialApp.builder has no enclosing route. Register its
// equivalent on the actual top Home/content route to receive platform Back
// before that Navigator can pop a route hidden behind the active editor.
class _RootEditorObserver extends NavigatorObserver {
  _RootEditorObserver(RetainedEditorController controller)
    : _entry = _EditorPopEntry(controller);

  final _EditorPopEntry _entry;
  ModalRoute<dynamic>? _route;

  void setEditorVisible(bool visible) {
    _entry.canPopNotifier.value = !visible;
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _route?.unregisterPopEntry(_entry);
    _route = topRoute is ModalRoute<dynamic> ? topRoute : null;
    _route?.registerPopEntry(_entry);
  }

  void detach() {
    _route?.unregisterPopEntry(_entry);
    _route = null;
    _entry.canPopNotifier.dispose();
  }
}
