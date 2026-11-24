import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../content/asset_content_repository.dart';
import '../content/content_repository.dart';
import '../editor/retained_editor_host.dart';
import '../harness/hub/harness_hub.dart';
import '../harness/hub/harness_hosts.dart';
import '../harness/ui/agent_session_details_page.dart';
import '../harness/ui/agents_entry.dart';
import '../harness/ui/home_agents_tab.dart';
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
import '../widgets/project_dialogs.dart';
import 'large_screen_controller.dart';
import 'workbench_chrome.dart';
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
  });

  final RetainedEditorController editors;
  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;

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
      child: WorkbenchWelcome(onOpenProject: _addExisting),
    );
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
          _layout.showWorkspace();
          _layout.closeCompactSidebar();
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
    if (!widget.editors.isVisible) {
      _layout.activateFiles(null);
      return;
    }
    _resumeSession = null;
    _layout.showWorkspace();
    _layout.closeCompactSidebar();
  }

  void _select(WorkbenchActivity activity) {
    final wasWorkspace = _layout.showsWorkspace;
    _layout.select(activity);
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

  Future<void> _addExisting() async {
    final project = await showAddExistingDialog(context, widget.store);
    if (!mounted || project == null) return;
    widget.editors.open(
      project: project,
      auth: widget.auth,
      store: widget.store,
      settings: widget.settings,
    );
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
      WorkbenchActivity.projects => HomeTab(
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
      WorkbenchActivity.files => const SizedBox.shrink(),
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
          _select(WorkbenchActivity.projects);
        } else {
          unawaited(widget.editors.handleBack());
        }
      },
      child: child!,
    ),
    child: Theme(
      data: WorkbenchTheme.from(Theme.of(context)),
      child: LargeScreenScope(
        controller: _layout,
        child: RetainedEditorScope(
          controller: widget.editors,
          child: ScaffoldMessenger(
            key: _scaffold,
            child: Scaffold(
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < Breakpoints.sidebarPersistent;
                    _layout.setCompact(compact);
                    return ListenableBuilder(
                      listenable: _layout,
                      builder: (context, _) {
                        final workspace = _layout.showsWorkspace;
                        final sideWidth =
                            (constraints.maxWidth - WorkbenchActivityRail.width)
                                .clamp(0.0, Breakpoints.sidebarWidth);
                        final sideShown = workspace && _layout.sidebarVisible;
                        if (_layout.activity != WorkbenchActivity.files) {
                          _page(_layout.activity);
                        }
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
                                    key: const ValueKey('workbench-center'),
                                    left: !compact && sideShown ? sideWidth : 0,
                                    child: _center(workspace),
                                  ),
                                  if (compact && sideShown)
                                    Positioned.fill(
                                      key: const ValueKey('workbench-scrim'),
                                      child: GestureDetector(
                                        onTap: _layout.closeCompactSidebar,
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
  );

  Widget _center(bool workspace) => LayoutBuilder(
    builder: (context, constraints) => MediaQuery(
      data: MediaQuery.of(context).copyWith(size: constraints.biggest),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _retain(
            key: const ValueKey('workbench-editor-host'),
            visible: workspace,
            child: _editorHost,
          ),
          for (final entry in _pages.entries)
            if (entry.key != WorkbenchActivity.projects &&
                entry.key != WorkbenchActivity.agents)
              _retain(
                key: ValueKey(entry.key),
                visible: entry.key == _layout.activity,
                child: entry.value,
              ),
        ],
      ),
    ),
  );

  Widget _sidebar() {
    final panels = _layout.filePanels;
    _visitedFiles.removeWhere((owner) => !panels.containsKey(owner));
    if (_layout.activity == WorkbenchActivity.files) {
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
          for (final activity in [
            WorkbenchActivity.projects,
            WorkbenchActivity.agents,
          ])
            if (_pages[activity] case final page?)
              _retain(
                key: ValueKey(activity),
                visible: _layout.activity == activity,
                child: page,
              ),
          _retain(
            key: const ValueKey('workbench-files'),
            visible: _layout.activity == WorkbenchActivity.files,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_layout.activeEditor == null)
                  const Center(child: Text('先打开一个项目')),
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
