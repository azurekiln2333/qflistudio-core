import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content/asset_content_repository.dart';
import '../content/content_repository.dart';
import '../editor/retained_editor_host.dart';
import '../harness/hub/harness_hub.dart';
import '../harness/hub/harness_hosts.dart';
import '../harness/ui/agent_session_details_page.dart';
import '../harness/ui/agents_entry.dart';
import '../harness/ui/home_agents_tab.dart';
import '../layout/app_form_factor.dart';
import '../layout/breakpoints.dart';
import '../pages/home_page.dart';
import '../pages/local_content_pages.dart';
import '../pages/profile_page.dart';
import '../pages/quick_tools_page.dart';
import '../pages/settings_page.dart';
import '../pages/terminax_terminal_page.dart';
import '../services/app_paths.dart';
import '../services/desktop_folder_drop.dart';
import '../services/example_code_store.dart';
import '../services/studio_profile.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import 'large_screen_controller.dart';
import 'workbench_chrome.dart';
import 'workbench_explorer.dart';
import 'workbench_theme.dart';

/// One route for project selection and editing on desktop/tablet. Editors stay
/// in their existing retained host; only the surrounding presentation differs.
class LargeScreenWorkbench extends StatefulWidget {
  const LargeScreenWorkbench({
    super.key,
    required this.editors,
    required this.store,
    required this.auth,
    required this.settings,
    this.formFactor,
  });

  final RetainedEditorController editors;
  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;
  final AppFormFactor? formFactor;

  @override
  State<LargeScreenWorkbench> createState() => _LargeScreenWorkbenchState();
}

class _LargeScreenWorkbenchState extends State<LargeScreenWorkbench> {
  final _layout = LargeScreenController();
  final _examples = ExampleCodeStore();
  final _pages = <WorkbenchActivity, Widget>{};
  final _scaffold = GlobalKey<ScaffoldMessengerState>();
  ContentRepository? _content;
  HarnessHub? _agents;
  DesktopFolderDrop? _drop;
  String? _resumeSession;
  String? _visibleSession;
  final _visitedFiles = <Object>{};
  late final Widget _editorHost;

  @override
  void initState() {
    super.initState();
    widget.editors.setRootBackHandling(false);
    widget.editors.addListener(_editorsChanged);
    _editorHost = RetainedEditorHost(
      controller: widget.editors,
      showRestoreControl: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.store, _layout]),
        builder: (context, _) {
          if (_layout.activity == WorkbenchActivity.explorer &&
              _layout.sidebarVisible) {
            return WorkbenchShortcutHints(
              includeClone: StudioProfile.current?.offlineOnly != true,
            );
          }
          return WorkbenchWelcome(
            onOpenProject: _layout.openFolder,
            onCreateProject: _layout.createProject,
            onCloneRepository: StudioProfile.current?.offlineOnly == true
                ? null
                : _layout.cloneRepository,
            projects: widget.store.projects
                .where((project) => !project.isCloud)
                .toList(),
            onOpenRecent: _layout.openRecent,
          );
        },
      ),
    );
    _page(WorkbenchActivity.explorer);
    if (Platform.isWindows) {
      _drop = DesktopFolderDrop(
        store: widget.store,
        onOpen: (project) async {
          if (!mounted) return;
          widget.editors.open(
            project: project,
            auth: widget.auth,
            store: widget.store,
            settings: widget.settings,
          );
          _layout.closeCenterOverlay();
          _layout.showFiles();
        },
        onError: _showError,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_drop?.start());
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    _scaffold.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _editorsChanged() {
    if (!mounted) return;
    final session = widget.editors.activeSessionKey;
    // Popup notifications are not project opens. Keep a conversation overlay
    // until a session actually changes or an explicit open clears it.
    if (session == _visibleSession) return;
    _visibleSession = session;
    if (session == null) {
      _layout.activateFiles(null);
      return;
    }
    _resumeSession = null;
    _layout.closeCenterOverlay();
    _layout.showFiles();
  }

  void _select(WorkbenchActivity activity, {bool toggle = true}) {
    final wasWorkspace = _layout.showsWorkspace;
    _layout.select(activity, toggle: toggle);
    if (wasWorkspace && !_layout.showsWorkspace) {
      _resumeSession = widget.editors.activeSessionKey;
      widget.editors.minimize();
    } else if (!wasWorkspace && _layout.showsWorkspace) {
      final session = _resumeSession;
      if (session != null) {
        widget.editors.resumeSession(session);
        _layout.select(activity, toggle: false);
      }
    }
  }

  void _toggleSidebar() {
    if (!_layout.showsWorkspace) {
      _select(WorkbenchActivity.explorer, toggle: false);
    } else {
      _layout.toggleSidebar();
    }
  }

  Widget _agentsPanel() {
    final hub = _agents ??= HarnessHub(
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
    return Builder(
      builder: (context) => HomeAgentsTab(
        auth: widget.auth,
        store: widget.store,
        settings: widget.settings,
        harnessHub: hub,
        onOpenSession: (row) => unawaited(
          openAgentSession(
            context,
            row: row,
            auth: widget.auth,
            store: widget.store,
            settings: widget.settings,
            harnessHub: hub,
          ),
        ),
        onOpenDetails: (row) => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => AgentSessionDetailsPage(row: row)),
        ),
      ),
    );
  }

  Widget _page(WorkbenchActivity activity) => _pages.putIfAbsent(
    activity,
    () => switch (activity) {
      WorkbenchActivity.explorer => HomeTab(
        store: widget.store,
        auth: widget.auth,
        settings: widget.settings,
        embedded: true,
        showAgentsScope: false,
        onOpenProfile: () => _select(WorkbenchActivity.profile),
      ),
      WorkbenchActivity.agents => _agentsPanel(),
      WorkbenchActivity.profile => ProfileTab(
        auth: widget.auth,
        settings: widget.settings,
        store: widget.store,
      ),
      WorkbenchActivity.settings => SettingsPage(
        auth: widget.auth,
        settings: widget.settings,
        store: widget.store,
        showAi: StudioProfile.current?.offlineOnly != true,
      ),
      WorkbenchActivity.tools => FunctionsTab(
        store: widget.store,
        toolsTabBuilder: StudioProfile.current?.toolsTabBuilder,
        onOpenTerminal: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => TerminaxTerminalPage(store: widget.store),
          ),
        ),
        onOpenContentTool: StudioProfile.current?.toolsPageBuilder == null
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ContentToolsPage(store: widget.store),
                ),
              ),
      ),
      WorkbenchActivity.tutorial => _tutorialPage(),
    },
  );

  Widget _tutorialPage() {
    final profile = StudioProfile.current;
    if (profile?.offlineOnly == true ||
        profile?.contentRepositoryFactory != null) {
      _content ??=
          profile?.contentRepositoryFactory?.call() ?? AssetContentRepository();
      return TutorialCenterPage(
        language: profile?.id ?? '',
        store: widget.store,
        auth: widget.auth,
        settings: widget.settings,
        examples: _examples,
        repository: _content,
      );
    }
    return TutorialsTab(auth: widget.auth);
  }

  @override
  void dispose() {
    _drop?.dispose();
    widget.editors.removeListener(_editorsChanged);
    widget.editors.setRootBackHandling(true);
    _agents?.dispose();
    _examples.dispose();
    _pages.clear();
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.editors, _layout]),
    builder: (context, child) => PopScope(
      canPop: !widget.editors.isVisible && _layout.showsWorkspace,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_layout.showsWorkspace) {
          _select(WorkbenchActivity.explorer, toggle: false);
        } else {
          unawaited(widget.editors.handleBack());
        }
      },
      child: child!,
    ),
    child: Theme(
      data: WorkbenchTheme.from(
        Theme.of(context),
        formFactor:
            widget.formFactor ??
            (AppPaths.isDesktop ? AppFormFactor.desktop : AppFormFactor.tablet),
      ),
      child: LargeScreenScope(
        controller: _layout,
        formFactor:
            widget.formFactor ??
            (AppPaths.isDesktop ? AppFormFactor.desktop : AppFormFactor.tablet),
        child: Shortcuts(
          shortcuts: {
            _shortcut(LogicalKeyboardKey.keyN, shift: true):
                const _ProjectCommandIntent(_ProjectCommand.create),
            _shortcut(LogicalKeyboardKey.keyO): const _ProjectCommandIntent(
              _ProjectCommand.openFolder,
            ),
            if (StudioProfile.current?.offlineOnly != true)
              _shortcut(LogicalKeyboardKey.keyG, shift: true):
                  const _ProjectCommandIntent(_ProjectCommand.clone),
            _shortcut(LogicalKeyboardKey.keyB): const _ToggleSidebarIntent(),
            _shortcut(LogicalKeyboardKey.keyE, shift: true):
                const _SelectActivityIntent(WorkbenchActivity.explorer),
            _shortcut(LogicalKeyboardKey.keyA, shift: true):
                const _SelectActivityIntent(WorkbenchActivity.agents),
            _shortcut(LogicalKeyboardKey.comma): const _SelectActivityIntent(
              WorkbenchActivity.settings,
            ),
          },
          child: Actions(
            actions: {
              _ProjectCommandIntent: CallbackAction<_ProjectCommandIntent>(
                onInvoke: (intent) {
                  switch (intent.command) {
                    case _ProjectCommand.create:
                      _layout.createProject();
                    case _ProjectCommand.openFolder:
                      _layout.openFolder();
                    case _ProjectCommand.clone:
                      _layout.cloneRepository();
                  }
                  return null;
                },
              ),
              _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
                onInvoke: (_) {
                  _toggleSidebar();
                  return null;
                },
              ),
              _SelectActivityIntent: CallbackAction<_SelectActivityIntent>(
                onInvoke: (intent) {
                  _select(intent.activity, toggle: false);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: RetainedEditorScope(
                controller: widget.editors,
                child: ScaffoldMessenger(
                  key: _scaffold,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact =
                              constraints.maxWidth <
                              Breakpoints.sidebarPersistent;
                          _layout.setCompact(compact);
                          return ListenableBuilder(
                            listenable: _layout,
                            builder: (context, _) {
                              final workspace = _layout.showsWorkspace;
                              final availableSidebarWidth =
                                  (constraints.maxWidth -
                                          WorkbenchActivityRail.width)
                                      .clamp(0.0, double.infinity);
                              final dividerWidth =
                                  LargeScreenScope.isDesktop(context)
                                  ? WorkbenchSidebarDivider.desktopHitWidth
                                  : WorkbenchSidebarDivider.touchHitWidth;
                              final sideWidth = _layout.sidebarWidth
                                  .clamp(
                                    0.0,
                                    availableSidebarWidth.clamp(
                                      0.0,
                                      LargeScreenController.maxSidebarWidth,
                                    ),
                                  )
                                  .toDouble();
                              final sideShown =
                                  workspace && _layout.sidebarVisible;
                              _page(_layout.activity);
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListenableBuilder(
                                    listenable: widget.auth,
                                    builder: (context, _) {
                                      final user = widget.auth.user;
                                      final avatar = user?.avatarUrl ?? '';
                                      return WorkbenchActivityRail(
                                        selected: _layout.activity,
                                        onSelected: _select,
                                        accountLabel: user?.nickname,
                                        avatarImage: avatar.isEmpty
                                            ? null
                                            : NetworkImage(avatar),
                                      );
                                    },
                                  ),
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          key: const ValueKey(
                                            'workbench-center',
                                          ),
                                          left: !compact && sideShown
                                              ? sideWidth
                                              : 0,
                                          child: _center(workspace),
                                        ),
                                        if (compact && sideShown)
                                          Positioned.fill(
                                            key: const ValueKey(
                                              'workbench-scrim',
                                            ),
                                            child: GestureDetector(
                                              onTap:
                                                  _layout.closeCompactSidebar,
                                              child: ColoredBox(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .scrim
                                                    .withValues(alpha: 0.25),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          key: const ValueKey(
                                            'workbench-sidebar-slot',
                                          ),
                                          left: 0,
                                          top: 0,
                                          bottom: 0,
                                          width: sideWidth,
                                          child: _retain(
                                            visible: sideShown,
                                            child: _sidebar(),
                                          ),
                                        ),
                                        if (!compact && sideShown)
                                          Positioned(
                                            key: const ValueKey(
                                              'workbench-sidebar-divider-slot',
                                            ),
                                            left: sideWidth - dividerWidth / 2,
                                            top: 0,
                                            bottom: 0,
                                            width: dividerWidth,
                                            child: WorkbenchSidebarDivider(
                                              controller: _layout,
                                              touchLayout:
                                                  !LargeScreenScope.isDesktop(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  SingleActivator _shortcut(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(
        key,
        control: !Platform.isMacOS,
        meta: Platform.isMacOS,
        shift: shift,
      );

  Widget _center(bool workspace) => LayoutBuilder(
    builder: (context, constraints) => MediaQuery(
      data: MediaQuery.of(context).copyWith(size: constraints.biggest),
      child: Theme(
        data: Theme.of(context).copyWith(
          snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
            width: (constraints.maxWidth - 32).clamp(0.0, 480.0).toDouble(),
          ),
        ),
        child: Scaffold(
          key: const ValueKey('workbench-center-scaffold'),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _retain(
                key: const ValueKey('workbench-editor-host'),
                visible: workspace && _layout.centerOverlay == null,
                child: _editorHost,
              ),
              for (final entry in _pages.entries)
                if (entry.key != WorkbenchActivity.explorer &&
                    entry.key != WorkbenchActivity.agents)
                  _retain(
                    key: ValueKey(entry.key),
                    visible: entry.key == _layout.activity,
                    child: entry.value,
                  ),
              if (_layout.centerOverlay case final overlay?)
                _retain(
                  key: const ValueKey('workbench-center-overlay'),
                  visible: workspace,
                  child: Builder(builder: overlay),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sidebar() => Builder(
    builder: (context) => Theme(
      data: Theme.of(context).copyWith(
        snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
          width: _layout.sidebarWidth.clamp(0.0, 480.0).toDouble(),
        ),
      ),
      child: _sidebarContent(),
    ),
  );

  Widget _sidebarContent() {
    final panels = _layout.filePanels;
    _visitedFiles.removeWhere((owner) => !panels.containsKey(owner));
    if (_layout.activity == WorkbenchActivity.explorer &&
        _layout.explorerPage == ExplorerPage.files) {
      if (_layout.activeEditor case final owner?) {
        _visitedFiles.add(owner);
      }
    }
    return Material(
      key: const ValueKey('workbench-shared-sidebar'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_pages[WorkbenchActivity.explorer] case final projects?)
            _retain(
              key: const ValueKey('workbench-explorer'),
              visible: _layout.activity == WorkbenchActivity.explorer,
              child: WorkbenchExplorer(
                controller: _layout,
                projectName: widget.editors.activeProject?.name,
                projects: projects,
                files: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final entry in panels.entries.where(
                      (entry) => _visitedFiles.contains(entry.key),
                    ))
                      _retain(
                        key: ObjectKey(entry.key),
                        visible: identical(entry.key, _layout.activeEditor),
                        child: Builder(builder: entry.value),
                      ),
                  ],
                ),
              ),
            ),
          if (_pages[WorkbenchActivity.agents] case final agents?)
            _retain(
              key: const ValueKey('workbench-agents'),
              visible: _layout.activity == WorkbenchActivity.agents,
              child: agents,
            ),
        ],
      ),
    );
  }

  Widget _retain({Key? key, required bool visible, required Widget child}) =>
      Offstage(
        key: key,
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: ExcludeFocus(
            excluding: !visible,
            child: ExcludeSemantics(
              excluding: !visible,
              child: IgnorePointer(ignoring: !visible, child: child),
            ),
          ),
        ),
      );
}

enum _ProjectCommand { create, openFolder, clone }

class _ProjectCommandIntent extends Intent {
  const _ProjectCommandIntent(this.command);
  final _ProjectCommand command;
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _SelectActivityIntent extends Intent {
  const _SelectActivityIntent(this.activity);
  final WorkbenchActivity activity;
}
