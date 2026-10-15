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
class RetainedEditorHost extends StatefulWidget {
  const RetainedEditorHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final RetainedEditorController controller;
  final Widget child;

  @override
  State<RetainedEditorHost> createState() => _RetainedEditorHostState();
}

class _RetainedEditorHostState extends State<RetainedEditorHost>
    with TickerProviderStateMixin {
  final _motions = <String, AnimationController>{};
  final _targets = <String, bool>{};
  final _editorChildren = <String, Widget>{};
  bool _reduceMotion = false;

  RetainedEditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_syncSessions);
    _syncSessions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      for (final entry in _motions.entries) {
        entry.value.value = _targets[entry.key] == true ? 1 : 0;
      }
    }
  }

  @override
  void didUpdateWidget(covariant RetainedEditorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_syncSessions);
      _disposeMotions();
      controller.addListener(_syncSessions);
      _syncSessions();
    }
  }

  void _syncSessions() {
    for (final key in _motions.keys.toList()) {
      if (controller._sessions.containsKey(key)) continue;
      _motions.remove(key)!.dispose();
      _targets.remove(key);
      _editorChildren.remove(key);
    }
    for (final entry in controller._sessions.entries) {
      final motion = _motions.putIfAbsent(
        entry.key,
        () => AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 140),
        ),
      );
      _editorChildren.putIfAbsent(
        entry.key,
        () => _editorChild(entry.key, entry.value),
      );
      final visible = controller._active == entry.key;
      if (_targets[entry.key] == visible) continue;
      _targets[entry.key] = visible;
      if (_reduceMotion) {
        motion.value = visible ? 1 : 0;
      } else if (visible) {
        motion.forward();
      } else {
        motion.reverse();
      }
    }
    setState(() {});
  }

  Widget _editorChild(String key, _EditorSession session) =>
      HeroControllerScope.none(
        child: NotificationListener<NavigationNotification>(
          onNotification: (_) => true,
          child: ScaffoldMessenger(
            child: Navigator(
              key: session.navigatorKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => _SessionEditor(
                  controller: controller,
                  sessionKey: key,
                  session: session,
                ),
              ),
            ),
          ),
        ),
      );

  void _disposeMotions() {
    for (final motion in _motions.values) {
      motion.dispose();
    }
    _motions.clear();
    _targets.clear();
    _editorChildren.clear();
  }

  @override
  void dispose() {
    controller.removeListener(_syncSessions);
    _disposeMotions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RetainedEditorScope(
    controller: controller,
    child: AnimatedBuilder(
      animation: Listenable.merge(_motions.values.toList()),
      builder: (context, _) => Overlay.wrap(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _retained(
              visible:
                  !controller.isVisible ||
                  _motions.values.any((motion) => motion.isAnimating),
              interactive: !controller.isVisible,
              child: widget.child,
            ),
            // Keep the active editor above an exiting project. The keyed
            // layers and cached Navigator children keep their live identity
            // when the paint order changes.
            for (final entry in [
              ...controller._sessions.entries.where(
                (entry) => entry.key != controller._active,
              ),
              ...controller._sessions.entries.where(
                (entry) => entry.key == controller._active,
              ),
            ])
              _animatedEditor(
                key: ValueKey(entry.key),
                visible: controller._active == entry.key,
                motion: _motions[entry.key]!,
                child: _editorChildren[entry.key]!,
              ),
            if (!controller.isVisible &&
                !_motions.values.any((motion) => motion.isAnimating) &&
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

  Widget _animatedEditor({
    required Key key,
    required bool visible,
    required AnimationController motion,
    required Widget child,
  }) {
    final eased = motion.drive(CurveTween(curve: Curves.easeOutCubic));
    return _retained(
      key: key,
      visible: visible || !motion.isDismissed,
      interactive: visible,
      child: FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: eased.drive(
            Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _retained({
    Key? key,
    required bool visible,
    required bool interactive,
    required Widget child,
  }) => Offstage(
    key: key,
    offstage: !visible,
    child: TickerMode(
      enabled: interactive,
      child: ExcludeFocus(
        excluding: !interactive,
        child: ExcludeSemantics(
          excluding: !interactive,
          child: IgnorePointer(ignoring: !interactive, child: child),
        ),
      ),
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
