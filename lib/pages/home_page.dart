import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../content/asset_content_repository.dart';
import '../content/content_repository.dart';
import '../editor/retained_editor_host.dart';
import '../harness/hub/harness_hub.dart';
import '../harness/hub/harness_hosts.dart';
import '../harness/ui/agent_session_details_page.dart';
import '../harness/ui/agents_entry.dart';
import '../harness/ui/home_agents_tab.dart';
import '../models/project.dart';
import '../config/api_config.dart';
import '../services/cloud_project_actions.dart';
import '../services/archive_share_service.dart';
import '../services/app_paths.dart';
import '../services/api_client.dart';
import '../services/cloud_sync_service.dart';
import '../git/git_backend.dart';
import '../services/example_code_store.dart';
import '../services/git_clone_service.dart';
import '../services/project_templates.dart';
import '../services/picker_service.dart';
import '../services/project_zip_service.dart';
import '../services/studio_profile.dart';
import '../services/task_activity_service.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../widgets/collapsed_search_field.dart';
import 'git/git_clone_dialog.dart';
import 'git/github_repository_picker.dart';
import 'home_project_tabs.dart';
import 'local_content_pages.dart';
import 'quick_tools_page.dart';
import 'terminax_terminal_page.dart';
import '../i18n/studio_localizations.dart';
import 'community/post_list_page.dart';
import '../widgets/home_git_clone_tasks.dart';
import '../widgets/project_card.dart';
import '../widgets/project_dialogs.dart';
import '../widgets/retained_page.dart';
import 'profile_page.dart';
import '../services/local_audit_service.dart';
import '../editor/open_performance.dart';
import '../services/local_stats_service.dart';
import '../workspace/saved_workspaces_tab.dart';

/// 应用外壳：功能、教程、示例和个人页均为独立页面。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.auth,
    required this.settings,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _currentIndex = ValueNotifier<int>(0);
  final _examples = ExampleCodeStore();
  ContentRepository? _contentRepository;

  // Tutorial and example tabs share one lazy asset load and parse.
  ContentRepository get _sharedContentRepository => _contentRepository ??=
      StudioProfile.current?.contentRepositoryFactory?.call() ??
      AssetContentRepository();
  late final PageController _pageController;
  final Map<int, Widget> _pages = {};
  late Widget _pageView;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageView = _createPageView();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.auth != widget.auth ||
        oldWidget.settings != widget.settings) {
      _pages.clear();
      _pageView = _createPageView();
    }
  }

  Widget _createPageView() => PageView.builder(
    key: const ValueKey('home-page-view'),
    controller: _pageController,
    // Four pages: home, tools, content and profile. Tutorials and example code
    // share one page (R6), so the separate example destination is gone; the
    // remaining pages keep their old indexes.
    itemCount: 4,
    onPageChanged: (index) => _currentIndex.value = index,
    itemBuilder: (context, index) => _pages.putIfAbsent(index, () {
      final profile = StudioProfile.current;
      return RetainedPage(
        key: ValueKey('home-page-$index'),
        child: ValueListenableBuilder<int>(
          valueListenable: _currentIndex,
          child: _buildPage(
            this.context,
            index,
            // Content tabs fall back to their local variants when the product
            // has a bundled content source, and for every offline-only product.
            // A networked product still ships its own catalog and must read it
            // from assets rather than from the server.
            profile?.offlineOnly == true ||
                profile?.contentRepositoryFactory != null,
            profile,
          ),
          builder: (context, selected, child) =>
              TickerMode(enabled: selected == index, child: child!),
        ),
      );
    }),
  );

  @override
  void dispose() {
    _pageController.dispose();
    _currentIndex.dispose();
    _examples.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? _currentIndex.value.toDouble();
    if ((page - index).abs() < 0.001) return;
    if ((page - index).abs() > 1) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final extendedRail = MediaQuery.sizeOf(context).width >= 1200;
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: l10n.home,
      ),
      NavigationDestination(
        icon: const Icon(Icons.apps_outlined),
        selectedIcon: const Icon(Icons.apps),
        label: l10n.tools,
      ),
      NavigationDestination(
        icon: const Icon(Icons.menu_book_outlined),
        selectedIcon: const Icon(Icons.menu_book),
        label: l10n.tutorial,
      ),
      // Tutorials and example code are one page; there is no separate example
      // destination any more (R6).
      // The profile page is always offered, including for offline-only products.
      // It used to be replaced by the examples tab under `isOffline`, which made
      // the account/settings entry unreachable; the page itself now hides its
      // networked sections when `offlineOnly` is set.
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: l10n.profile,
      ),
    ];
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) ...[
            ValueListenableBuilder<int>(
              valueListenable: _currentIndex,
              builder: (context, selected, _) => NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: _selectPage,
                extended: extendedRail,
                labelType: extendedRail
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                groupAlignment: -0.7,
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: destination.icon,
                      selectedIcon: destination.selectedIcon,
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
          ],
          Expanded(child: _pageView),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : ValueListenableBuilder<int>(
              valueListenable: _currentIndex,
              builder: (context, selected, _) => NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: _selectPage,
                destinations: destinations,
              ),
            ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    int index,
    bool offline,
    StudioProfile? profile,
  ) {
    return switch (index) {
      0 => HomeTab(
        store: widget.store,
        auth: widget.auth,
        settings: widget.settings,
      ),
      1 => FunctionsTab(
        store: widget.store,
        toolsTabBuilder: profile?.toolsTabBuilder,
        onOpenTerminal: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TerminaxTerminalPage(store: widget.store),
          ),
        ),
        onOpenContentTool: _isContentProduct
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContentToolsPage(store: widget.store),
                ),
              )
            : null,
      ),
      2 =>
        offline
            ? TutorialCenterPage(
                language: profile!.id,
                store: widget.store,
                auth: widget.auth,
                settings: widget.settings,
                examples: _examples,
                repository: _sharedContentRepository,
              )
            : TutorialsTab(auth: widget.auth),
      3 => ProfileTab(
        auth: widget.auth,
        settings: widget.settings,
        store: widget.store,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  bool get _isContentProduct =>
      StudioProfile.current?.toolsPageBuilder != null ||
      switch (StudioProfile.current?.productKey) {
        StudioProductCatalog.jsonKey ||
        StudioProductCatalog.noteKey ||
        StudioProductCatalog.sqlabKey => true,
        _ => false,
      };
}

/// 主页 Tab：项目列表 + 搜索 + 更多操作。
/// 项目页签：全部项目 / 历史项目 / 收藏项目，联网产品另有云端项目。
/// 页签顺序可由用户长按拖动调整，并保存在本机。
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.store,
    required this.auth,
    required this.settings,
    this.tabOrderStore,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;

  /// Where the dragged tab order is saved. The app leaves this null and uses
  /// the file-backed store; tests inject an in-memory backend.
  final HomeTabOrderStore? tabOrderStore;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeCloneTaskState {
  _HomeCloneTaskState({
    required this.id,
    required this.name,
    required this.cancellation,
  });

  final int id;
  final String name;
  final GitCloneCancellation cancellation;
  GitCloneProgress progress = const GitCloneProgress(
    stage: GitCloneStage.preparing,
  );
  bool cancelling = false;
}

/// 主页 Tab 的状态：项目列表 + 搜索 + 更多操作 + 可拖动的项目页签。
class _HomeTabState extends State<HomeTab>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _query = '';
  String _languageFilter = '';
  int _gitRefreshRevision = 0;
  RetainedEditorController? _retainedEditor;
  bool _retainedEditorVisible = false;
  String? _archiveBusyLabel;
  final Map<int, _HomeCloneTaskState> _cloneTasks = {};
  int _nextCloneTaskId = 0;
  late bool _loggedIn;
  Future<void>? _refreshRequest;
  // R3/R8: one C-owned observable handles all account-scoped cloud mutations.
  late CloudProjectActions _cloudActions;
  String? _accountIdentity;
  String? _accountToken;
  int _authSessionGeneration = 0;
  int _homeGeneration = 0;

  /// 首页 Agents 标签是否在前台。
  bool _agentsOpen = false;

  /// 首次打开 Agents 时建，之后保活：订阅与快照不用每次重建。
  Widget? _agentsTab;

  /// 首页持有的 hub。跳转时交给编辑器，避免同一台电脑开两条连接。
  HarnessHub? _agentsHub;

  // Capture the live AuthStore revision, not only its delayed notification.
  // The pair also invalidates work when this Home swaps its auth/store objects.
  ({int home, int session}) get _accountGeneration =>
      (home: _homeGeneration, session: widget.auth.sessionGeneration);
  final Set<String> _deletingCloudProjects = {};
  late final HomeTabOrderStore _tabOrderStore =
      widget.tabOrderStore ?? HomeTabOrderStore();

  /// Scopes this product offers, in default order.
  late List<ProjectScope> _orderedScopes = defaultProjectScopes(
    StudioProfile.current,
  );
  late final TabController _projectTabs = TabController(
    length: _orderedScopes.length,
    vsync: this,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loggedIn = widget.auth.isLoggedIn;
    _accountIdentity = widget.auth.user?.id;
    _accountToken = widget.auth.token;
    _authSessionGeneration = widget.auth.sessionGeneration;
    _cloudActions = CloudProjectActions(auth: widget.auth, store: widget.store)
      ..addListener(_onCloudChanged);
    widget.auth.addListener(_onAuthChanged);
    if (_loggedIn && StudioProfile.current?.offlineOnly != true) {
      unawaited(TaskActivityService.instance.refreshIfDue(widget.auth));
      unawaited(_inspectCloudCaches());
    }
  }

  /// R8: restore manifest metadata for scoped registry rows on first display.
  /// A folder's mere existence never marks a cache complete.
  Future<void> _inspectCloudCaches() async {
    final generation = _accountGeneration;
    final actions = _cloudActions;
    for (final project in actions.projects) {
      if (!mounted || generation != _accountGeneration) return;
      try {
        await actions.inspect(project);
      } catch (_) {
        // C retains an observable failed/notCached status. One corrupt manifest
        // must not prevent inspecting the remaining project cards.
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final retainedEditor = RetainedEditorScope.maybeOf(context);
    if (!identical(_retainedEditor, retainedEditor)) {
      _retainedEditor?.removeListener(_onRetainedEditorChanged);
      final wasVisible = _retainedEditorVisible;
      _retainedEditor = retainedEditor;
      _retainedEditorVisible = retainedEditor?.isVisible ?? false;
      retainedEditor?.addListener(_onRetainedEditorChanged);
      if (wasVisible && !_retainedEditorVisible) _gitRefreshRevision++;
    }
    _applySavedTabOrderIfReady();
  }

  void _onRetainedEditorChanged() {
    final visible = _retainedEditor?.isVisible ?? false;
    final returnedHome = _retainedEditorVisible && !visible;
    _retainedEditorVisible = visible;
    if (mounted && returnedHome) setState(() => _gitRefreshRevision++);
  }

  /// Reads the saved tab order once, as soon as the store can read without a
  /// storage probe.
  ///
  /// A normal start resolves its storage location during bootstrap, so the order
  /// is applied shortly after the first frame. When the location is not resolved
  /// yet (widget tests, or a platform still probing) the read is skipped: it
  /// would start a probe this frame has no reason to wait for, and the order is
  /// read on the first drag instead.
  void _applySavedTabOrderIfReady() {
    if (_savedTabOrderRequested || !_tabOrderStore.canReadNow) return;
    _savedTabOrderRequested = true;
    unawaited(_applySavedTabOrder());
  }

  bool _savedTabOrderRequested = false;

  /// Applies the saved tab order once the store has read it. A product whose
  /// scopes change still gets a valid bar: missing scopes are appended and
  /// unknown saved identifiers are dropped.
  Future<void> _applySavedTabOrder() async {
    _savedTabOrderRequested = true;
    await _tabOrderStore.load();
    if (!mounted) return;
    final saved = _tabOrderStore.order;
    if (saved.isEmpty) return;
    _applyTabOrder(saved);
  }

  /// Re-derives the rendered order from [saved] and the scopes the product
  /// offers right now. Keeps the selected scope selected when it still exists.
  void _applyTabOrder(List<ProjectScope> saved) {
    final ordered = resolveProjectScopes(
      saved,
      defaultProjectScopes(StudioProfile.current),
    );
    final selected = _orderedScopes.isEmpty
        ? ProjectScope.all
        : _orderedScopes[_projectTabs.index.clamp(
            0,
            _orderedScopes.length - 1,
          )];
    final nextIndex = ordered.indexOf(selected);
    if (listEquals(ordered, _orderedScopes)) return;
    setState(() => _orderedScopes = ordered);
    if (nextIndex >= 0 && nextIndex != _projectTabs.index) {
      _projectTabs.index = nextIndex;
    }
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth || oldWidget.store != widget.store) {
      oldWidget.auth.removeListener(_onAuthChanged);
      _cloudActions.removeListener(_onCloudChanged);
      _cloudActions.dispose();
      _homeGeneration++;
      _accountIdentity = widget.auth.user?.id;
      _accountToken = widget.auth.token;
      _authSessionGeneration = widget.auth.sessionGeneration;
      _refreshRequest = null;
      _deletingCloudProjects.clear();
      _cloudActions = CloudProjectActions(
        auth: widget.auth,
        store: widget.store,
      )..addListener(_onCloudChanged);
      widget.auth.addListener(_onAuthChanged);
      _loggedIn = widget.auth.isLoggedIn;
    }
  }

  void _onCloudChanged() {
    if (mounted) setState(() {});
  }

  void _onAuthChanged() {
    final loggedIn = widget.auth.isLoggedIn;
    final becameLoggedIn = loggedIn && !_loggedIn;
    final identity = widget.auth.user?.id;
    final token = widget.auth.token;
    final sessionGeneration = widget.auth.sessionGeneration;
    if (identity != _accountIdentity ||
        token != _accountToken ||
        sessionGeneration != _authSessionGeneration) {
      _homeGeneration++;
      _accountIdentity = identity;
      _accountToken = token;
      _authSessionGeneration = sessionGeneration;
      _refreshRequest = null;
      _deletingCloudProjects.clear();
      if (loggedIn && StudioProfile.current?.offlineOnly != true) {
        unawaited(_inspectCloudCaches());
      }
    }
    if (!mounted) return;
    setState(() => _loggedIn = loggedIn);
    if (becameLoggedIn && StudioProfile.current?.offlineOnly != true) {
      unawaited(TaskActivityService.instance.refreshIfDue(widget.auth));
    }
  }

  @override
  void dispose() {
    for (final task in _cloneTasks.values) {
      task.cancellation.cancel();
    }
    _retainedEditor?.removeListener(_onRetainedEditorChanged);
    _homeGeneration++;
    _cloudActions.removeListener(_onCloudChanged);
    _cloudActions.dispose();
    widget.auth.removeListener(_onAuthChanged);
    _searchController.dispose();
    _projectTabs.dispose();
    _agentsHub?.dispose();
    _agentsHub = null;
    super.dispose();
  }

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _query = '';
      _languageFilter = '';
      _searchController.clear();
    });
  }

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _query = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = StudioLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _searchOpen
            ? collapsedSearchToolbarHeight(context)
            : null,
        leading: _searchOpen
            ? IconButton(
                tooltip: l10n.exitSearch,
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeSearch,
              )
            : null,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: _searchOpen
            ? _buildSearchField()
            : Text(
                StudioProfile.current?.appTitle ?? 'QFLIStudioN',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
        actions: _searchOpen
            ? const [SizedBox(width: 8)]
            : [
                CollapsedSearchButton(
                  tooltip: l10n.searchProjects,
                  onPressed: _openSearch,
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.more,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'add_existing':
                        showAddExistingDialog(context, widget.store);
                      case 'remove_missing':
                        _removeMissingProjects(context);
                      case 'import_project':
                        unawaited(_importProjectArchive());
                      case 'clone_repository':
                        unawaited(_cloneRepository());
                      case 'github_repositories':
                        unawaited(_cloneGitHubRepositories());
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'import_project',
                      enabled: _archiveBusyLabel == null,
                      child: const Row(
                        children: [
                          Icon(Icons.unarchive_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('导入项目（.qsz）'),
                        ],
                      ),
                    ),
                    if (StudioProfile.current?.offlineOnly != true)
                      PopupMenuItem(
                        value: 'clone_repository',
                        enabled: _archiveBusyLabel == null,
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_download_outlined, size: 20),
                            SizedBox(width: 12),
                            Flexible(child: Text('克隆 Git 仓库')),
                          ],
                        ),
                      ),
                    if (StudioProfile.current?.offlineOnly != true)
                      PopupMenuItem(
                        value: 'github_repositories',
                        enabled: _archiveBusyLabel == null,
                        child: Row(
                          children: [
                            const Icon(Icons.source_outlined, size: 20),
                            const SizedBox(width: 12),
                            Flexible(child: Text(l10n.githubRepositories)),
                          ],
                        ),
                      ),
                    if (AppPaths.isDesktop)
                      PopupMenuItem(
                        value: 'add_existing',
                        child: Row(
                          children: [
                            Icon(Icons.folder_open_outlined, size: 20),
                            SizedBox(width: 12),
                            // 窄视口（以及系统字体放大）下菜单文字会超宽，
                            // 用 Flexible 包住让它们换行，而不是溢出报错。
                            Flexible(child: Text(l10n.addExistingProject)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'remove_missing',
                      child: Row(
                        children: [
                          Icon(Icons.folder_delete_outlined, size: 20),
                          SizedBox(width: 12),
                          Flexible(child: Text(l10n.removeMissingProjects)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
      ),
      floatingActionButton: _searchOpen
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createFromCurrentScope(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(l10n.createProject),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final taskPanelHeight = (constraints.maxHeight * 0.35)
              .clamp(0.0, HomeGitCloneTasks.defaultMaxHeight)
              .toDouble();
          return Column(
            children: [
              if (_archiveBusyLabel != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _archiveBusyLabel!,
                          key: const ValueKey('project-archive-progress'),
                        ),
                      ),
                    ],
                  ),
                ),
              HomeGitCloneTasks(
                maxHeight: taskPanelHeight,
                tasks: [
                  for (final task in _cloneTasks.values)
                    HomeGitCloneTask(
                      id: task.id,
                      name: task.name,
                      progress: task.progress,
                      cancelling: task.cancelling,
                      onCancel: () => _cancelClone(task.id),
                    ),
                ],
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.store,
                  builder: (context, _) {
                    if (_searchOpen) {
                      return _buildProjectList(
                        context,
                        scope: ProjectScope.all,
                        keyword: _query,
                      );
                    }
                    return Column(
                      children: [
                        _buildAgentsScopeBar(context, l10n),
                        Expanded(
                          child: Stack(
                            children: [
                              // 项目页不销毁：切回时页签与滚动位置都还在。
                              Offstage(
                                offstage: _agentsOpen,
                                child: TabBarView(
                                  controller: _projectTabs,
                                  children: [
                                    for (final scope in _orderedScopes)
                                      scope == ProjectScope.workspace
                                          ? SavedWorkspacesTab(
                                              key: const ValueKey(
                                                'home-scope-page-workspace',
                                              ),
                                              store: widget.store,
                                              auth: widget.auth,
                                              settings: widget.settings,
                                            )
                                          : KeyedSubtree(
                                              key: ValueKey(
                                                'home-scope-page-${scope.name}',
                                              ),
                                              child: _buildProjectList(
                                                context,
                                                scope: scope,
                                              ),
                                            ),
                                  ],
                                ),
                              ),
                              if (_agentsTab case final tab?)
                                Offstage(offstage: !_agentsOpen, child: tab),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 项目条：最左边是 Agents 入口，右边是原有的页签条。
  ///
  /// 入口放在 [TabBar] 外：页签条只装项目分类，Agents 不是第四个分类，
  /// 也不参与拖动排序。
  Widget _buildAgentsScopeBar(BuildContext context, StudioLocalizations l10n) {
    final theme = Theme.of(context);
    final selected = _agentsOpen;
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TextButton.icon(
            key: const ValueKey('home-agents-tab'),
            onPressed: _toggleAgents,
            icon: const Icon(Icons.hub_outlined, size: 18),
            label: Text(l10n.agentsTab),
            style: TextButton.styleFrom(
              foregroundColor: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              textStyle: theme.textTheme.labelLarge,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        Expanded(child: _buildScopeTabBar(context, l10n)),
      ],
    );
  }

  /// 切到 Agents 标签，或切回项目列表。
  void _toggleAgents() {
    setState(() {
      _agentsOpen = !_agentsOpen;
      if (_agentsOpen) _agentsTab ??= _buildAgentsTab(context);
    });
  }

  /// 建首页 Agents 标签。
  ///
  /// hub 由首页持有：跳转时交给编辑器，同一台电脑只开一条连接。
  Widget _buildAgentsTab(BuildContext context) {
    final hub = _agentsHub ??= HarnessHub(
      hosts: HarnessHosts.build(
        HubHostContext(
          auth: widget.auth,
          projectStore: widget.store,
          settings: widget.settings,
          // 首页没有打开的项目：内置 Agent 主机不在这里装配。
          projectRoot: '',
          desktop: AppPaths.isDesktop,
        ),
      ),
      desktop: AppPaths.isDesktop,
      hostBuildError: HarnessHosts.lastBuildError,
    );
    return HomeAgentsTab(
      auth: widget.auth,
      store: widget.store,
      settings: widget.settings,
      harnessHub: hub,
      onOpenSession: (row) => openAgentSession(
        context,
        row: row,
        auth: widget.auth,
        store: widget.store,
        settings: widget.settings,
        harnessHub: hub,
      ),
      onOpenDetails: (row) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AgentSessionDetailsPage(row: row),
        ),
      ),
    );
  }

  /// The project scope bar.
  ///
  /// Long-press starts a drag reorder: each tab carries a [LongPressDraggable]
  /// and a [DragTarget] sits between neighbouring tabs, because this Flutter
  /// version's `TabBar` reports `onLongPress` but has no `onReorder` of its own.
  /// A short tap still selects, a horizontal drag still scrolls the strip.
  Widget _buildScopeTabBar(BuildContext context, StudioLocalizations l10n) {
    String labelOf(ProjectScope scope) => switch (scope) {
      ProjectScope.all => l10n.allProjects,
      ProjectScope.history => l10n.historyProjects,
      ProjectScope.favorite => l10n.favoriteProjects,
      ProjectScope.workspace => '工作区',
      ProjectScope.cloud => l10n.cloudProjects,
    };
    Widget content(ProjectScope scope) => Tab(
      key: ValueKey('home-scope-tab-${scope.name}'),
      height: 36,
      child: Center(child: Text(labelOf(scope))),
    );
    Widget target(int index, Widget child) => DragTarget<int>(
      key: ValueKey('home-scope-drop-$index'),
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => _dropScopeTab(details.data, index),
      builder: (context, candidate, _) => Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: candidate.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        child: Center(child: child),
      ),
    );
    return TabBar(
      controller: _projectTabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      tabs: [
        for (var index = 0; index < _orderedScopes.length; index++)
          target(
            index,
            LongPressDraggable<int>(
              key: ValueKey('home-scope-drag-${_orderedScopes[index].name}'),
              data: index,
              feedback: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(labelOf(_orderedScopes[index])),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: content(_orderedScopes[index]),
              ),
              child: content(_orderedScopes[index]),
            ),
          ),
      ],
    );
  }

  /// Completes a drag reorder: moves the rendered order and saves it.
  ///
  /// The selected scope stays selected, so its index moves with it rather than
  /// jumping to whatever tab now occupies the old position. Dropping a tab
  /// before the selected one shifts the selection, so the index is recomputed
  /// from the scope that was selected before the move.
  Future<void> _dropScopeTab(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _orderedScopes.length) return;
    if (newIndex < 0 || newIndex >= _orderedScopes.length) return;
    final previous = List<ProjectScope>.of(_orderedScopes);
    final selected = previous[_projectTabs.index];
    final ordered = List<ProjectScope>.of(previous);
    // Remove first so `newIndex` is read against the shortened list, which is
    // what dropping on the target's slot means for both drag directions.
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    final nextIndex = ordered.indexOf(selected);
    setState(() => _orderedScopes = ordered);
    if (nextIndex >= 0 && nextIndex != _projectTabs.index) {
      _projectTabs.index = nextIndex;
    }
    // The saved order may not have been read yet: the first frame must not wait
    // on a file read, so it is fetched here, where it is actually needed.
    await _tabOrderStore.load();
    if (!mounted) return;
    final merged = mergeProjectScopeOrder(
      previous: previous,
      applied: _tabOrderStore.order,
      next: ordered,
      available: defaultProjectScopes(StudioProfile.current),
      moved: previous[oldIndex],
    );
    unawaited(_tabOrderStore.save(merged));
  }

  /// The expanded search bar.
  ///
  /// Uses the shared [CollapsedSearchField] so Home and the tutorial page show
  /// the same field. The filter itself is unchanged: [_query] is still matched
  /// against project names and paths in [_buildProjectList].
  Widget _buildSearchField() {
    final l10n = StudioLocalizations.of(context);
    return CollapsedSearchField(
      fieldKey: const ValueKey('home-project-search-field'),
      controller: _searchController,
      label: l10n.searchProjectHint,
      clearTooltip: l10n.clear,
      onChanged: (value) => setState(() => _query = value),
    );
  }

  /// 按页签取项目列表。
  List<Project> _projectsFor(ProjectScope scope) {
    // R3/R8: the shared registry may retain other accounts and legacy mirrors.
    // Only C's current-account projection is allowed to render cloud cards.
    final all = <Project>[
      ...widget.store.projects.where((project) => !project.isCloud),
      if (StudioProfile.current?.offlineOnly != true) ..._cloudActions.projects,
    ]..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    switch (scope) {
      case ProjectScope.all:
        final list = [
          ...all,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      case ProjectScope.history:
        return [...all];
      case ProjectScope.favorite:
        return all.where((p) => p.favorite).toList();
      case ProjectScope.workspace:
        return const [];
      case ProjectScope.cloud:
        return all.where((p) => p.isCloud).toList();
    }
  }

  /// 语言筛选芯片的候选：语言专属 App 只列出自己那一门语言。
  List<String> get _languageChips {
    final profile = StudioProfile.current;
    final source = ProjectLanguages.all.where((l) => l != '空项目');
    if (profile == null) return source.toList(growable: false);
    return profile.filterLanguages(source);
  }

  Widget _buildProjectList(
    BuildContext context, {
    required ProjectScope scope,
    String keyword = '',
  }) {
    var projects = _projectsFor(scope);
    final searching = keyword.isNotEmpty;
    if (searching) {
      final k = keyword.trim().toLowerCase();
      projects = projects
          .where(
            (p) =>
                p.name.toLowerCase().contains(k) ||
                p.path.toLowerCase().contains(k),
          )
          .toList();
    }
    if (scope == ProjectScope.all) {
      // 语言筛选 chips（全部项目页签），始终显示全部语言。
      final chipList = [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: FilterChip(
            label: Text(StudioLocalizations.of(context).allLanguages),
            selected: _languageFilter.isEmpty,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => setState(() => _languageFilter = ''),
          ),
        ),
        for (final lang in _languageChips)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              label: Text(lang),
              selected: _languageFilter == lang,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) => setState(() {
                _languageFilter = _languageFilter == lang ? '' : lang;
              }),
            ),
          ),
      ];
      if (_languageFilter.isNotEmpty) {
        projects = projects
            .where((p) => p.language == _languageFilter)
            .toList();
      }
      final body = projects.isEmpty
          ? _emptyScrollable(
              searching || _languageFilter.isNotEmpty
                  ? const _EmptySearchResult()
                  : _EmptyState(onCreate: () => _createProject(context)),
            )
          : _buildGridOrList(context, projects);
      // Single-language products can hide language chips without losing scopes.
      final showLanguageChips =
          (StudioProfile.current?.showHomeTabs ?? true) && chipList.length > 1;
      return Column(
        children: [
          if (showLanguageChips)
            // 高度随内容收缩；左右 12 与卡片外边距、TabBar labelPadding 对齐。
            // 下边距为 0：下方列表自带 8 的顶部内边距，避免叠成 16 的双倍空隙。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: chipList),
            ),
          Expanded(child: _refreshable(scope, body)),
        ],
      );
    }
    if (projects.isEmpty) {
      final empty = switch (scope) {
        ProjectScope.favorite => _buildSimpleEmpty(
          context,
          Icons.star_border_outlined,
          StudioLocalizations.of(context).favoriteProjects,
          StudioLocalizations.of(context).favoriteProjectHint,
        ),
        ProjectScope.cloud => _buildSimpleEmpty(
          context,
          Icons.cloud_outlined,
          StudioLocalizations.of(context).cloudProjects,
          StudioLocalizations.of(context).cloudProjectHintFab,
        ),
        _ =>
          searching
              ? const _EmptySearchResult()
              : _EmptyState(onCreate: () => _createProject(context)),
      };
      return _refreshable(scope, _emptyScrollable(empty));
    }
    return _refreshable(scope, _buildGridOrList(context, projects));
  }

  Widget _refreshable(ProjectScope scope, Widget child) =>
      RefreshIndicator(onRefresh: () => _refreshProjects(scope), child: child);

  Widget _emptyScrollable(Widget child) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    ],
  );

  Future<void> _refreshProjects(ProjectScope scope) async {
    if (_refreshRequest != null) return _refreshRequest;
    final request = _reloadProjects(scope);
    _refreshRequest = request;
    try {
      await request;
    } finally {
      if (identical(_refreshRequest, request)) _refreshRequest = null;
    }
  }

  Future<void> _reloadProjects(ProjectScope scope) async {
    final generation = _accountGeneration;
    final actions = _cloudActions;
    try {
      await widget.store.refresh();
      if (!mounted || generation != _accountGeneration) return;
      setState(() => _gitRefreshRevision++);
      if (StudioProfile.current?.offlineOnly == true || !actions.available) {
        return;
      }
      if (scope != ProjectScope.cloud && scope != ProjectScope.all) return;
      // R3: C owns list generations, scoped merging and deletion tombstones.
      // Never merge an independent cloud response here after a delete.
      await actions.refresh();
    } catch (error) {
      if (!mounted || generation != _accountGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? StudioLocalizations.of(
                    context,
                  ).cloudRefreshFailed(error.message)
                : StudioLocalizations.of(context).refreshProjectsFailed,
          ),
        ),
      );
    }
  }

  Widget _buildSimpleEmpty(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridOrList(BuildContext context, List<Project> projects) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        const padding = EdgeInsets.fromLTRB(12, 8, 12, 96);
        if (wide) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          // R8: make room for snapshot state/time/count/bytes on cloud cards.
          final hasCloud = projects.any((project) => project.isCloud);
          final itemExtent =
              ((hasCloud ? 40 : 24) + (hasCloud ? 68 : 38) * scale)
                  .clamp(hasCloud ? 132.0 : 90.0, hasCloud ? 260.0 : 180.0)
                  .toDouble();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1360),
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: padding,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: itemExtent,
                ),
                itemCount: projects.length,
                itemBuilder: (context, i) => _buildCard(context, projects[i]),
              ),
            ),
          );
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          itemCount: projects.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCard(context, projects[i]),
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, Project project) {
    return ProjectCard(
      project: project,
      gitRefreshRevision: _gitRefreshRevision,
      onOpen: () => _openProject(context, project),
      onRemove: () => _deleteProject(context, project),
      onToggleFavorite: (value) => widget.store.setFavorite(project, value),
      onExport: project.isCloud
          ? null
          : () => unawaited(_exportProjectArchive(project)),
      // R5/R6: sharing ZIP does not replace import-compatible .qsz export.
      onShare: () => unawaited(_shareProject(project)),
      // R8: snapshot state is observable and independent of directory existence.
      cacheStatus: project.isCloud ? _cloudActions.status(project) : null,
      cloudBusy:
          project.isCloud &&
          (_cloudActions.isBusy(project) ||
              _deletingCloudProjects.contains(project.id)),
      onCache: project.isCloud ? () => unawaited(_cacheProject(project)) : null,
      onClearCache: project.isCloud
          ? () => unawaited(_clearProjectCache(project))
          : null,
    );
  }

  // R5/R6: capture the account generation before download/ZIP/native handoff.
  Future<void> _shareProject(Project project) async {
    if (_archiveBusyLabel != null) return;
    final l10n = StudioLocalizations.of(context);
    final generation = _accountGeneration;
    final token = widget.auth.token;
    final accountId = widget.auth.user?.id;
    final actions = _cloudActions;
    bool current() =>
        mounted &&
        (!project.isCloud ||
            generation == _accountGeneration &&
                widget.auth.token == token &&
                widget.auth.user?.id == accountId);
    if (project.isCloud && (token == null || accountId == null)) return;
    setState(
      () => _archiveBusyLabel = project.isCloud
          ? l10n.preparingCloudShare
          : l10n.preparingProjectShare,
    );
    try {
      final result = await ArchiveShareService.shareProject(
        project,
        token: project.isCloud ? token : null,
        accountId: project.isCloud ? accountId : null,
        cloudActions: project.isCloud ? actions : null,
      );
      if (!mounted || !current()) return;
      if (result.status == ArchiveShareStatus.shared) {
        _showArchiveMessage(l10n.projectShareHandedOff);
        return;
      }
      // Unsupported is not success. Keep the finished ZIP and let the user save
      // that exact archive instead of downloading/compressing a second time.
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.shareUnsupportedTitle),
          content: Text(l10n.shareUnsupportedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.saveZip),
            ),
          ],
        ),
      );
      if (save != true || !current()) return;
      final location = await PickerService.saveDocument(
        suggestedName: p.basename(result.path),
      );
      if (location == null || !current()) return;
      final path = location.path;
      if (path != null && path.isNotEmpty) {
        // Write exactly the path confirmed by the system picker. Do not append an
        // extension and accidentally overwrite an unconfirmed sibling file.
        if (!p.equals(p.absolute(path), p.absolute(result.path))) {
          await File(result.path).copy(path);
        }
      } else if (location.uri case final uri? when uri.isNotEmpty) {
        final bytes = await File(result.path).readAsBytes();
        if (!current()) return;
        await PickerService.writeUri(uri, bytes);
      } else {
        throw const FileSystemException('No writable destination');
      }
      if (current()) _showArchiveMessage(l10n.zipSaved);
    } catch (_) {
      if (current()) _showArchiveMessage(l10n.projectShareFailed);
    } finally {
      if (mounted) setState(() => _archiveBusyLabel = null);
    }
  }

  // R8: cache/clear are distinct operations, never remote delete aliases.
  Future<void> _cacheProject(Project project) async {
    final generation = _accountGeneration;
    try {
      await _cloudActions.cacheProject(project);
    } catch (_) {
      if (mounted && generation == _accountGeneration) {
        _showArchiveMessage(StudioLocalizations.of(context).cacheActionFailed);
      }
    }
  }

  Future<void> _clearProjectCache(Project project) async {
    final generation = _accountGeneration;
    final actions = _cloudActions;
    final l10n = StudioLocalizations.of(context);
    final confirmed = await showClearCloudCacheConfirm(context, project);
    if (!confirmed || !mounted || generation != _accountGeneration) return;
    try {
      await actions.clearCache(project);
      if (mounted && generation == _accountGeneration) {
        _showArchiveMessage(l10n.cacheCleared);
      }
    } catch (_) {
      if (mounted && generation == _accountGeneration) {
        _showArchiveMessage(l10n.cacheActionFailed);
      }
    }
  }

  // R3: do not promise local recycle-bin recovery for permanent remote deletion.
  Future<void> _deleteCloudProject(Project project) async {
    if (_deletingCloudProjects.contains(project.id)) return;
    final generation = _accountGeneration;
    final actions = _cloudActions;
    final l10n = StudioLocalizations.of(context);
    // Reserve before the dialog so repeated taps cannot open duplicate deletes.
    setState(() => _deletingCloudProjects.add(project.id));
    try {
      final confirmed = await showDeleteCloudProjectConfirm(context, project);
      if (!confirmed || !mounted || generation != _accountGeneration) return;
      final result = await actions.deleteProject(project);
      if (!mounted || generation != _accountGeneration) return;
      _showArchiveMessage(
        !result.remoteDeleted
            ? l10n.cloudDeleteFailed
            : result.cleanupError != null
            ? l10n.cloudDeleteCleanupWarning
            : l10n.cloudDeleteSucceeded(project.name),
      );
    } catch (_) {
      if (mounted && generation == _accountGeneration) {
        _showArchiveMessage(l10n.cloudDeleteFailed);
      }
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _deletingCloudProjects.remove(project.id));
      }
    }
  }

  Future<void> _exportProjectArchive(Project project) async {
    if (_archiveBusyLabel != null) return;
    setState(() => _archiveBusyLabel = '正在选择导出位置…');
    try {
      var name = project.name
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
          .trim()
          .replaceAll(RegExp(r'[. ]+$'), '');
      if (name.isEmpty) name = 'project';
      final location = await PickerService.saveDocument(
        suggestedName: '$name.qsz',
      );
      if (!mounted || location == null) return;
      final path = location.path;
      final uri = location.uri;
      if ((path == null || path.isEmpty) && (uri == null || uri.isEmpty)) {
        throw const FileSystemException('系统未返回可写位置');
      }
      setState(() => _archiveBusyLabel = '正在压缩并导出项目…');
      if (path != null && path.isNotEmpty) {
        final needsExtension = !path.toLowerCase().endsWith('.qsz');
        final destination = needsExtension ? '$path.qsz' : path;
        // The picker confirms overwriting only the path the user selected.
        // An extension added here must not silently overwrite another file.
        if (needsExtension && await File(destination).exists()) {
          throw const FileSystemException('目标文件已存在，请直接选择 .qsz 文件并确认覆盖，或更换名称');
        }
        if (!mounted) return;
        await ProjectZipService.exportToFile(project, destination);
      } else {
        final bytes = await ProjectZipService.exportProject(project);
        if (!mounted) return;
        await PickerService.writeUri(uri!, bytes);
      }
      _showArchiveMessage('已导出项目「${project.name}」');
    } on Object catch (error) {
      _showArchiveMessage('导出失败：$error');
    } finally {
      if (mounted) setState(() => _archiveBusyLabel = null);
    }
  }

  Future<void> _importProjectArchive() async {
    if (_archiveBusyLabel != null) return;
    setState(() => _archiveBusyLabel = '正在选择项目压缩包…');
    try {
      final picked = await PickerService.pickDocument(
        extensions: const ['qsz'],
      );
      if (!mounted || picked == null) return;
      final path = picked.path;
      final uri = picked.uri;
      final name = picked.name ?? (path == null ? null : p.basename(path));
      if (name != null && !name.toLowerCase().endsWith('.qsz')) {
        throw const FormatException('请选择 .qsz 项目压缩包');
      }
      setState(() => _archiveBusyLabel = '正在读取并导入项目…');
      final bytes = path != null && path.isNotEmpty
          ? await File(path).readAsBytes()
          : uri != null && uri.isNotEmpty
          ? await PickerService.readUri(uri)
          : throw const FileSystemException('系统未返回可读文件');
      if (!mounted) return;
      final result = await widget.store.importProjectArchive(bytes);
      if (!mounted) return;
      if (result.error != null || result.project == null) {
        throw FormatException(result.error ?? '未能导入项目');
      }
      setState(() {
        _languageFilter = '';
        _query = '';
        _searchController.clear();
        _searchOpen = false;
      });
      _projectTabs.animateTo(_orderedScopes.indexOf(ProjectScope.all));
      _showArchiveMessage('已导入项目「${result.project!.name}」');
    } on Object catch (error) {
      _showArchiveMessage('导入失败：$error');
    } finally {
      if (mounted) setState(() => _archiveBusyLabel = null);
    }
  }

  Future<void> _cloneRepository() async {
    if (_archiveBusyLabel != null) return;
    final request = await showGitCloneDialog(
      context,
      desktop: AppPaths.isDesktop,
    );
    if (request == null || !mounted) return;
    await _runCloneRequest(request);
  }

  // R1: reuse the exact Home clone pipeline for every selected repository.
  Future<void> _cloneGitHubRepositories() async {
    if (_archiveBusyLabel != null) return;
    final requests = await showGitHubRepositoryPicker(context);
    if (!mounted || requests == null) return;
    for (final request in requests) {
      unawaited(_runCloneRequest(request));
    }
  }

  Future<void> _runCloneRequest(GitCloneRequest request) async {
    if (!mounted) return;
    final id = _nextCloneTaskId++;
    final cancellation = GitCloneCancellation();
    final task = _HomeCloneTaskState(
      id: id,
      name: request.name.trim().isNotEmpty
          ? request.name.trim()
          : cloneProjectName(request.url, ''),
      cancellation: cancellation,
    );
    setState(() => _cloneTasks[id] = task);

    final service = GitCloneService(store: widget.store);
    try {
      final outcome = await service.clone(
        request,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!mounted || !identical(_cloneTasks[id], task)) return;
          setState(() => task.progress = progress);
        },
      );
      if (!mounted) return;
      if (outcome.cancelled) {
        _showArchiveMessage('已取消克隆「${task.name}」');
        return;
      }
      final project = outcome.project;
      if (outcome.error != null || project == null) {
        final preserved = outcome.preservedPath;
        _showArchiveMessage(
          preserved == null
              ? '「${task.name}」克隆失败：${outcome.error ?? '未知错误'}'
              : '「${task.name}」克隆已下载，但注册失败：${outcome.error}。文件保留在 $preserved',
        );
        return;
      }
      setState(() {
        _languageFilter = '';
        _query = '';
        _searchController.clear();
        _searchOpen = false;
      });
      _projectTabs.animateTo(_orderedScopes.indexOf(ProjectScope.all));
      _showArchiveMessage('已克隆项目「${project.name}」');
    } on Object catch (error) {
      if (mounted) _showArchiveMessage('「${task.name}」克隆失败：$error');
    } finally {
      cancellation.dispose();
      if (mounted) {
        setState(() => _cloneTasks.remove(id));
      }
    }
  }

  void _cancelClone(int id) {
    final task = _cloneTasks[id];
    if (task == null || task.cancelling) return;
    task.cancellation.cancel();
    if (mounted) setState(() => task.cancelling = true);
  }

  void _showArchiveMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Creates what the visible tab implies.
  ///
  /// On the cloud scope the FAB opens the cloud project flow that used to live
  /// in the overflow menu; everywhere else it keeps the local project dialog it
  /// always opened. A cloud scope only exists for a logged-in networked
  /// product, and tapping before the session lands asks the user to sign in
  /// rather than silently creating something local.
  Future<void> _createFromCurrentScope(BuildContext context) async {
    final index = _projectTabs.index;
    final scope = index >= 0 && index < _orderedScopes.length
        ? _orderedScopes[index]
        : ProjectScope.all;
    if (scope != ProjectScope.cloud) {
      await _createProject(context);
      return;
    }
    if (!widget.auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(StudioLocalizations.of(context).cloudSignInRequired),
        ),
      );
      return;
    }
    await _createCloudProject(context);
  }

  Future<void> _createProject(BuildContext context) async {
    final result = await showCreateProjectDialog(context, widget.store);
    if (result != null && context.mounted) {
      TaskActivityService.report(widget.auth, 'create_project');
      unawaited(
        LocalStatsService.instance.recordFileCreated(
          project: result.project.name,
        ),
      );
      unawaited(
        LocalAuditService.instance.record(
          kind: LocalAuditKind.create,
          action: '创建项目 ${result.project.name}',
          project: result.project.name,
          path: result.project.path,
        ),
      );
      await _openProject(
        context,
        result.project,
        initialOpenFile: result.openFile,
      );
    }
  }

  Future<void> _openProject(
    BuildContext context,
    Project project, {
    String? initialOpenFile,
  }) async {
    OpenPerformance.beginOpen(project.name);
    // Captured before the await below: using the context after an async gap is
    // unsafe, and awaiting the existence check is the whole point here.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = StudioLocalizations.of(context);
    // `exists` instead of `existsSync`: a missing-project check must not block
    // the frame that starts the route transition. The rest of the method is
    // unchanged, including the snackbar for a missing path.
    final projectExists = project.isCloud
        ? true
        : await Directory(project.path).exists();
    OpenPerformance.mark('project path checked');
    if (!projectExists) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.missingProjectPath(project.path)),
          action: SnackBarAction(
            label: l10n.removeFromList,
            onPressed: () => widget.store.remove(project),
          ),
        ),
      );
      OpenPerformance.endOpen();
      return;
    }
    widget.store.touch(project);
    TaskActivityService.report(widget.auth, 'open_project');
    unawaited(
      LocalStatsService.instance.recordProjectOpened(project: project.name),
    );
    unawaited(
      LocalAuditService.instance.record(
        kind: LocalAuditKind.open,
        action: '打开项目 ${project.name}',
        project: project.name,
        path: project.path,
      ),
    );
    if (!context.mounted) return;
    await openEditorPage(
      context,
      project: project,
      auth: widget.auth,
      store: widget.store,
      settings: widget.settings,
      initialOpenPath: initialOpenFile,
    );
    if (mounted) setState(() => _gitRefreshRevision++);
    OpenPerformance.endOpen();
  }

  Future<void> _deleteProject(BuildContext context, Project project) async {
    if (project.isCloud) {
      await _deleteCloudProject(project);
      return;
    }
    final confirmed = await showDeleteProjectConfirm(context, project);
    if (!confirmed || !context.mounted) return;
    // 压缩备份可能耗时，显示进度提示。
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final l10n = StudioLocalizations.of(context);
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(l10n.backupAndDelete)),
            ],
          ),
        );
      },
    );
    final error = await widget.store.deleteProject(project);
    if (error == null) {
      unawaited(
        LocalStatsService.instance.recordFileDeleted(
          project: project.name,
          path: project.path,
        ),
      );
      unawaited(
        LocalAuditService.instance.record(
          kind: LocalAuditKind.delete,
          action: '删除项目 ${project.name}',
          project: project.name,
          path: project.path,
        ),
      );
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? StudioLocalizations.of(context).deletedProject(project.name),
        ),
      ),
    );
  }

  /// 批量移除目录已不存在的项目记录（不涉及磁盘删除）。
  Future<void> _removeMissingProjects(BuildContext context) async {
    final missing = widget.store.projects
        .where((p) => !p.isCloud && !Directory(p.path).existsSync())
        .toList();
    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(StudioLocalizations.of(context).noMissingProjects),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = StudioLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.removeMissingTitle),
          content: Text(
            l10n.removeMissingMessage(
              missing.length,
              missing.map((p) => '· ${p.name}').join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      for (final project in missing) {
        widget.store.remove(project);
      }
    }
  }

  Future<void> _createCloudProject(BuildContext context) async {
    final picked = await showDialog<(String, ProjectTemplate)>(
      context: context,
      builder: (context) {
        final l10n = StudioLocalizations.of(context);
        var template = defaultTemplate();
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.newCloudProject),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.projectName,
                    prefixIcon: Icon(Icons.cloud_upload_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownMenu<ProjectTemplate>(
                  initialSelection: template,
                  expandedInsets: EdgeInsets.zero,
                  label: Text(l10n.projectType),
                  onSelected: (value) {
                    if (value != null) setState(() => template = value);
                  },
                  dropdownMenuEntries: [
                    for (final t in availableTemplates())
                      DropdownMenuEntry(
                        value: t,
                        label: t.label,
                        leadingIcon: Icon(t.icon, size: 20),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  controller.text.trim().isEmpty
                      ? null
                      : (controller.text.trim(), template),
                ),
                child: Text(l10n.create),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !context.mounted) return;
    final (name, template) = picked;
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(StudioLocalizations.of(context).invalidProjectName),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(StudioLocalizations.of(context).creatingCloudProject),
        duration: Duration(seconds: 1),
      ),
    );
    // R7/R8: new mirrors and registry rows use the same captured account scope.
    final generation = _accountGeneration;
    final token = widget.auth.token;
    final accountId = widget.auth.user?.id;
    if (token == null || accountId == null) return;
    final scope = CloudProjectScope(
      origin: ApiConfig.origin,
      accountId: accountId,
    );
    final session = CloudSession(
      scope: scope,
      token: token,
      isCurrent: () =>
          mounted &&
          generation == _accountGeneration &&
          widget.auth.token == token &&
          widget.auth.user?.id == accountId,
    );
    final created = await CloudSyncService.createCloudProject(
      token: token,
      name: name,
      template: template,
      scope: scope,
      session: session,
    );
    if (!context.mounted ||
        generation != _accountGeneration ||
        widget.auth.token != token ||
        widget.auth.user?.id != accountId) {
      return;
    }
    if (created.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(created.error!)));
      return;
    }
    final service = await CloudSyncService.open(
      cloudId: created.id!,
      name: name,
      scope: scope,
      session: session,
    );
    if (!context.mounted ||
        generation != _accountGeneration ||
        widget.auth.token != token ||
        widget.auth.user?.id != accountId) {
      service.dispose();
      return;
    }
    final registered = await widget.store.addCloudProject(
      name: name,
      cloudId: '${created.id}',
      cachePath: service.localPath,
      language: template.language,
      scope: scope,
      session: session,
    );
    service.dispose();
    if (!context.mounted ||
        generation != _accountGeneration ||
        widget.auth.token != token ||
        widget.auth.user?.id != accountId) {
      return;
    }
    if (registered.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(registered.error!)));
      return;
    }
    TaskActivityService.report(widget.auth, 'create_project');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(StudioLocalizations.of(context).cloudProjectCreated),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = StudioLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(l10n.noMatchingProjects, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            l10n.searchProjectsHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = StudioLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(l10n.noProjects, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            AppPaths.isDesktop
                ? l10n.desktopCreateProjectHint
                : l10n.mobileCreateProjectHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(l10n.createProject),
          ),
        ],
      ),
    );
  }
}

/// 教程 Tab：社区教程内容（专区/标签/搜索/点赞/评论/分享）。
class TutorialsTab extends StatelessWidget {
  const TutorialsTab({super.key, required this.auth});

  final AuthStore auth;

  @override
  Widget build(BuildContext context) {
    return PostListPage(type: 'tutorial', auth: auth);
  }
}

/// 讨论 Tab：社区讨论内容。
class DiscussionTab extends StatelessWidget {
  const DiscussionTab({super.key, required this.auth});

  final AuthStore auth;

  @override
  Widget build(BuildContext context) {
    return PostListPage(type: 'discussion', auth: auth);
  }
}
