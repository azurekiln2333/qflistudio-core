import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/home_project_tabs.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

/// Home project tabs: default order, drag reorder, persistence and the removal
/// of the cloud project entry the overflow menu used to carry (R2, R3, R4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPaths;
  StudioProfile? originalProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_home_tabs_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
  });

  setUp(() {
    originalProfile = StudioProfile.current;
    StudioProfile.current = _profile();
  });

  tearDown(() {
    StudioProfile.current = originalProfile;
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('the default tab order keeps history first and appends Agents', (
    tester,
  ) async {
    await _mount(tester, _Fixture.create(root));
    expect(_tabLabels(tester), [
      '历史项目',
      '工作区',
      '全部项目',
      '收藏项目',
      '云端项目',
      'Agents',
    ]);
  });

  testWidgets('launch opens the first tab of that order', (tester) async {
    await _mount(tester, _Fixture.create(root));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    expect(
      find.byKey(const ValueKey('home-scope-page-history')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('Agents uses the shared pager and repeated taps keep it open', (
    tester,
  ) async {
    var builds = 0;
    await _mount(
      tester,
      _Fixture.create(root),
      agentsTabBuilder: (_) {
        builds++;
        return const _AgentsNavigationProbe();
      },
    );
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    final pager = tester.widget<TabBarView>(find.byType(TabBarView));
    expect(pager.controller, same(bar.controller));
    expect(builds, 0);

    await tester.tap(_tabFinder('Agents'));
    await _settle(tester);
    expect(bar.controller!.index, 5);
    expect(find.text('Session 0').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Advance session'));
    await tester.pump();

    await tester.tap(_tabFinder('Agents'));
    await _settle(tester);
    expect(bar.controller!.index, 5);
    expect(find.text('Session 1').hitTestable(), findsOneWidget);

    await tester.tap(_tabFinder('历史项目'));
    await _settle(tester);
    expect(bar.controller!.index, 0);
    expect(find.text('Session 1').hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('home-scope-page-history')).hitTestable(),
      findsOneWidget,
    );

    await tester.tap(_tabFinder('Agents'));
    await _settle(tester);
    expect(find.text('Session 1').hitTestable(), findsOneWidget);
    expect(builds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping selects Agents lazily and updates the same tab bar', (
    tester,
  ) async {
    var builds = 0;
    final backend = LocalMemoryBackend(
      jsonEncode({
        'version': 1,
        'order': ['history', 'agents', 'all', 'workspace', 'favorite', 'cloud'],
      }),
    );
    await _mount(
      tester,
      _Fixture.create(root),
      backend: backend,
      agentsTabBuilder: (_) {
        builds++;
        return const _AgentsNavigationProbe();
      },
    );
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(builds, 0, reason: 'An adjacent Agents page must not start hosts.');

    await _swipeScope(tester, const Offset(-600, 0));
    expect(controller.index, 1);
    expect(builds, 1);
    expect(find.text('Session 0').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Advance session'));
    await tester.pump();

    await _swipeScope(tester, const Offset(-600, 0));
    expect(controller.index, 2);
    expect(
      find.byKey(const ValueKey('home-scope-page-all')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Session 1').hitTestable(), findsNothing);

    await _swipeScope(tester, const Offset(600, 0));
    expect(controller.index, 1);
    expect(find.text('Session 1').hitTestable(), findsOneWidget);
    await _swipeScope(tester, const Offset(600, 0));
    expect(controller.index, 0);
    expect(builds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging selected Agents keeps its state and persists its order',
    (tester) async {
      final fixture = _Fixture.create(root);
      final backend = LocalMemoryBackend();
      await _mount(
        tester,
        fixture,
        backend: backend,
        agentsTabBuilder: (_) => const _AgentsNavigationProbe(),
      );
      await tester.tap(_tabFinder('Agents'));
      await _settle(tester);
      await tester.tap(find.text('Advance session'));
      await tester.pump();

      await _dragTab(tester, from: 'Agents', to: '历史项目');
      expect(_tabLabels(tester).first, 'Agents');
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
      expect(find.text('Session 1').hitTestable(), findsOneWidget);
      final payload = jsonDecode(backend.payload!) as Map<String, dynamic>;
      expect(payload['order'], [
        'agents',
        'history',
        'workspace',
        'all',
        'favorite',
        'cloud',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await _mount(
        tester,
        fixture,
        backend: backend,
        agentsTabBuilder: (_) => const _AgentsNavigationProbe(),
      );
      expect(_tabLabels(tester).first, 'Agents');
      await tester.tap(_tabFinder('Agents'));
      await _settle(tester);
      expect(find.text('Session 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Agents and project tabs remain selectable on a narrow screen', (
    tester,
  ) async {
    await _mount(
      tester,
      _Fixture.create(root),
      agentsTabBuilder: (_) => const _AgentsNavigationProbe(),
    );
    tester.view.physicalSize = const Size(320, 700);
    await tester.pump();
    await tester.ensureVisible(_tabFinder('Agents'));
    await tester.tap(_tabFinder('Agents'));
    await _settle(tester);
    expect(find.text('Session 0').hitTestable(), findsOneWidget);
    await tester.ensureVisible(_tabFinder('全部项目'));
    await tester.tap(_tabFinder('全部项目'));
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('home-scope-page-all')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Session 0').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agents callbacks still navigate after closing project search', (
    tester,
  ) async {
    await _mount(
      tester,
      _Fixture.create(root),
      agentsTabBuilder: (homeContext) => Center(
        child: TextButton(
          onPressed: () => Navigator.of(homeContext).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Session destination')),
            ),
          ),
          child: const Text('Open session'),
        ),
      ),
    );
    await tester.tap(_tabFinder('Agents'));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.search));
    await _settle(tester);
    expect(find.byType(TabBarView), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _settle(tester);
    await tester.tap(find.text('Open session'));
    await _settle(tester);
    expect(find.text('Session destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cloud scope can be missing without breaking the order', (
    tester,
  ) async {
    StudioProfile.current = _profile(offlineOnly: true);
    await _mount(tester, _Fixture.create(root));
    expect(_tabLabels(tester), ['历史项目', '工作区', '全部项目', '收藏项目', 'Agents']);
  });

  testWidgets('a saved order is applied on the next build', (tester) async {
    final backend = LocalMemoryBackend(
      jsonEncode({
        'version': 1,
        'order': ['cloud', 'favorite', 'history', 'workspace', 'all'],
      }),
    );
    await _mount(tester, _Fixture.create(root), backend: backend);
    expect(_tabLabels(tester), [
      '云端项目',
      '收藏项目',
      '历史项目',
      '工作区',
      '全部项目',
      'Agents',
    ]);
  });

  testWidgets(
    'a saved order with unknown identifiers still renders every tab once',
    (tester) async {
      final backend = LocalMemoryBackend(
        jsonEncode({
          'version': 1,
          'order': ['gone', 'cloud', 'cloud', 'workspace'],
        }),
      );
      await _mount(tester, _Fixture.create(root), backend: backend);
      // Unknown and duplicate entries are dropped; the rest is appended in
      // default order.
      expect(_tabLabels(tester), [
        '云端项目',
        '工作区',
        '历史项目',
        '全部项目',
        '收藏项目',
        'Agents',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long-press dragging a tab reorders it and the order is saved', (
    tester,
  ) async {
    final fixture = _Fixture.create(root);
    final backend = LocalMemoryBackend();
    await _mount(tester, fixture, backend: backend);
    expect(_tabLabels(tester), [
      '历史项目',
      '工作区',
      '全部项目',
      '收藏项目',
      '云端项目',
      'Agents',
    ]);

    await _dragTab(tester, from: '全部项目', to: '收藏项目');
    expect(_tabLabels(tester), [
      '历史项目',
      '工作区',
      '收藏项目',
      '全部项目',
      '云端项目',
      'Agents',
    ]);

    final payload = jsonDecode(backend.payload!) as Map<String, dynamic>;
    expect(payload['order'], [
      'history',
      'workspace',
      'favorite',
      'all',
      'cloud',
      'agents',
    ]);

    // Rebuilding the page against the same storage keeps the new order.
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await _mount(tester, fixture, backend: backend);
    expect(_tabLabels(tester), [
      '历史项目',
      '工作区',
      '收藏项目',
      '全部项目',
      '云端项目',
      'Agents',
    ]);
  });

  testWidgets('dragging a tab in front of the selected one keeps it selected', (
    tester,
  ) async {
    await _mount(tester, _Fixture.create(root));
    await tester.tap(_tabFinder('工作区'));
    await _settle(tester);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);

    // 收藏项目 moves in front of the selected tab, so the selected scope stays
    // selected at the index it moved to rather than at the old index.
    await _dragTab(tester, from: '收藏项目', to: '历史项目');
    expect(_tabLabels(tester), [
      '收藏项目',
      '历史项目',
      '工作区',
      '全部项目',
      '云端项目',
      'Agents',
    ]);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    expect(
      find.byKey(const ValueKey('home-scope-page-workspace')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag before the saved order is read keeps the rest of it', (
    tester,
  ) async {
    // A backend that only becomes readable after the user has already dragged,
    // which is what a start that is still resolving its storage looks like.
    final backend = _DeferredBackend(
      jsonEncode({
        'version': 1,
        'order': ['cloud', 'favorite', 'history', 'workspace', 'all'],
      }),
    );
    await _mount(tester, _Fixture.create(root), backend: backend);
    // The store could not read yet, so the default order is what is shown.
    expect(_tabLabels(tester), [
      '历史项目',
      '工作区',
      '全部项目',
      '收藏项目',
      '云端项目',
      'Agents',
    ]);

    backend.release();
    await _dragTab(tester, from: '全部项目', to: '收藏项目');

    // 全部项目 moves behind 收藏项目; the untouched tabs keep the saved order
    // (云端项目 first) instead of snapping back to the default.
    final payload = jsonDecode(backend.payload!) as Map<String, dynamic>;
    expect(payload['order'], [
      'cloud',
      'favorite',
      'all',
      'history',
      'workspace',
      'agents',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await _mount(tester, _Fixture.create(root), backend: backend);
    expect(_tabLabels(tester), [
      '云端项目',
      '收藏项目',
      '全部项目',
      '历史项目',
      '工作区',
      'Agents',
    ]);
  });

  testWidgets('the overflow menu no longer offers a new cloud project', (
    tester,
  ) async {
    final fixture = _Fixture.create(root);
    await _mount(tester, fixture, loggedIn: true);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await _settle(tester);

    // The cloud scope exists, so this is a real absence rather than a product
    // without the feature.
    expect(find.text('云端项目'), findsWidgets);
    expect(find.text('新建云端项目'), findsNothing);
    // The remaining entries are untouched.
    expect(find.text('导入项目（.qsz）'), findsOneWidget);
    expect(find.text('移除失效项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

StudioProfile _profile({bool offlineOnly = false}) => StudioProfile(
  id: 'studio',
  appTitle: 'QFLIStudioN',
  templates: const [ProjectTemplate.java],
  isOffline: false,
  offlineOnly: offlineOnly,
  productKey: StudioProductCatalog.qfliStudioKey,
);

/// Tab labels left to right.
///
/// The tab entries are drag targets, not `Tab` widgets, so the order is read
/// from the rendered positions of the labels inside the bar.
List<String> _tabLabels(WidgetTester tester) {
  final labels = find.descendant(
    of: find.byType(TabBar),
    matching: find.byType(Text),
  );
  final entries = [
    for (final element in labels.evaluate())
      (
        (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
        (element.widget as Text).data ?? '',
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final entry in entries) entry.$2];
}

Finder _tabFinder(String label) =>
    find.descendant(of: find.byType(TabBar), matching: find.text(label));

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  LocalStoreBackend? backend,
  bool loggedIn = false,
  WidgetBuilder? agentsTabBuilder,
}) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.runAsync(fixture.projects.load);
  if (loggedIn && !fixture.auth.isLoggedIn) {
    await tester.runAsync(
      () => fixture.auth.signIn(
        'token-tabs',
        const CommunityUser(
          id: 'u1',
          username: 'tester',
          nickname: 'Tester',
          bio: '',
          avatarColor: '#2196F3',
          points: 0,
          checkinStreak: 0,
          provider: 'local',
        ),
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeTab(
        store: fixture.projects,
        auth: fixture.auth,
        settings: fixture.settings,
        agentsTabBuilder: agentsTabBuilder,
        tabOrderStore: HomeTabOrderStore(
          backend: backend ?? LocalMemoryBackend(),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Long-presses [from] and drops it on [to].
Future<void> _dragTab(
  WidgetTester tester, {
  required String from,
  required String to,
}) async {
  final start = tester.getCenter(
    find.byKey(ValueKey('home-scope-drag-${_scopeKeyOf(from)}')),
  );
  // Aim at the tab body, not the drag target's two-pixel edge, so the drop lands
  // inside the target radius of the neighbouring tab.
  final end = tester.getCenter(_tabFinder(to));
  final gesture = await tester.startGesture(start);
  // Longer than kLongPressTimeout (500ms) so LongPressDraggable claims the
  // pointer before it moves.
  await tester.pump(const Duration(milliseconds: 700));
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await _settle(tester);
}

String _scopeKeyOf(String label) => switch (label) {
  '全部项目' => 'all',
  '历史项目' => 'history',
  '收藏项目' => 'favorite',
  '工作区' => 'workspace',
  '云端项目' => 'cloud',
  'Agents' => 'agents',
  _ => label,
};

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _swipeScope(WidgetTester tester, Offset offset) async {
  final pager = find.byType(TabBarView);
  final pageView = tester.widget<PageView>(
    find.descendant(of: pager, matching: find.byType(PageView)),
  );
  await tester.drag(pager, offset);
  // A swipe uses a spring simulation, not the fixed-duration tab-tap
  // animation. TabController publishes the final index at scroll end.
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    if (!pageView.controller!.position.isScrollingNotifier.value) {
      await tester.pump();
      return;
    }
  }
  fail('Home scope pager did not finish the swipe within 1600ms.');
}

class _Fixture {
  _Fixture(this.directory, this.projects);

  final Directory directory;
  final ProjectStore projects;
  final auth = AuthStore();
  final settings = SettingsStore();

  factory _Fixture.create(Directory root) {
    final directory = root.createTempSync('tabs_');
    final projectDirectory = Directory(p.join(directory.path, 'Alpha'))
      ..createSync();
    File(
      p.join(projectDirectory.path, 'Main.java'),
    ).writeAsStringSync('class Main {}');
    final project = Project.create(
      name: 'Alpha',
      path: projectDirectory.path,
      language: 'Java',
      type: 'java',
    );
    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'projects': [project.toJson()],
        }),
      );
    final store = ProjectStore(storageFile: registry);
    addTearDown(() {
      store.dispose();
    });
    return _Fixture(directory, store);
  }
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}

/// Stateful session content isolates pager behavior from host and disk work.
class _AgentsNavigationProbe extends StatefulWidget {
  const _AgentsNavigationProbe();

  @override
  State<_AgentsNavigationProbe> createState() => _AgentsNavigationProbeState();
}

class _AgentsNavigationProbeState extends State<_AgentsNavigationProbe> {
  int revision = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Session $revision'),
        TextButton(
          onPressed: () => setState(() => revision++),
          child: const Text('Advance session'),
        ),
      ],
    ),
  );
}

/// A stored payload that can only be read after [release].
///
/// Stands in for a start that has not resolved its storage location yet: the
/// page must not block on the read, and the first drag must still honour the
/// order that was stored earlier.
class _DeferredBackend extends LocalMemoryBackend {
  _DeferredBackend(String initial) : _content = initial;

  final String _content;
  bool _released = false;

  void release() => _released = true;

  @override
  bool get isReady => _released;

  @override
  Future<String?> read() async => _released ? (payload ?? _content) : null;
}
