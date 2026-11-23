import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/github/github_auth_controller.dart';
import 'package:qfli_studio_core/github/github_models.dart';
import 'package:qfli_studio_core/github/github_scope.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/git/github_repository_list.dart';
import 'package:qfli_studio_core/pages/git/github_repository_picker.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/home_project_tabs.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

// Cloud CI only. The real HomeTab owns pagination, ordering and retention.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform oldPaths;
  StudioProfile? oldProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_home_github_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
  });
  setUp(() {
    oldProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'studio',
      appTitle: 'Studio',
      templates: [],
      offlineOnly: false,
    );
  });
  tearDown(() => StudioProfile.current = oldProfile);
  tearDownAll(() {
    PathProviderPlatform.instance = oldPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('connection inserts an inline tab using the existing pager', (
    tester,
  ) async {
    final fixture = _Fixture(root);
    await _mount(tester, fixture);
    expect(_tab('github'), findsNothing);
    expect(
      find.byType(GitHubRepositoryList, skipOffstage: false),
      findsNothing,
    );
    fixture.github.connect();
    await _settle(tester);
    expect(_tab('github'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
    expect(
      find.byType(GitHubRepositoryList, skipOffstage: false),
      findsNothing,
    );
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(
      tester.widget<TabBarView>(find.byType(TabBarView)).controller,
      same(controller),
    );

    await _select(tester, 'github');
    expect(find.text('octocat/hello-world').hitTestable(), findsOneWidget);
    expect(find.byType(GitHubRepositoryPicker), findsNothing);
    final search = find.byKey(const ValueKey('github-search'));
    final searchController = tester.widget<TextField>(search).controller;
    await tester.enterText(search, 'hello');
    await tester.pump();
    await _select(tester, 'history');
    await _select(tester, 'github');
    expect(tester.widget<TextField>(search).controller, same(searchController));
    expect(searchController!.text, 'hello');
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller,
      same(controller),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'disconnect preserves local projects and the saved tab position',
    (tester) async {
      final fixture = _Fixture(root)..github.connect();
      final saved = [
        'favorite',
        'github',
        'history',
        'all',
        'workspace',
        'cloud',
        'agents',
      ];
      final backend = LocalMemoryBackend(
        jsonEncode({'version': 1, 'order': saved}),
      );
      await _mount(tester, fixture, backend: backend);
      expect(_order(tester), saved);
      await _select(tester, 'github');
      fixture.github.disconnectForTest();
      await _settle(tester);
      expect(
        _order(tester),
        saved.where((value) => value != 'github').toList(),
      );
      final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
      expect(_order(tester)[controller.index], 'history');
      expect(fixture.projects.projects.single.id, fixture.project.id);
      expect(Directory(fixture.project.path).existsSync(), isTrue);
      fixture.github.connect();
      await _settle(tester);
      expect(_order(tester), saved);
      expect(fixture.projects.projects.single.id, fixture.project.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'embedded Projects shows GitHub without Agents or a connection menu',
    (tester) async {
      final fixture = _Fixture(root)..github.connect();
      await _mount(tester, fixture, embedded: true);
      expect(_tab('agents'), findsNothing);
      expect(_tab('github'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await _select(tester, 'github');
      expect(find.text('octocat/hello-world').hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('github-connect')), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _settle(tester);
      expect(find.text('连接 GitHub'), findsNothing);
      expect(find.text('Connect GitHub'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Finder _tab(String scope) => find.byKey(ValueKey('home-scope-tab-$scope'));

List<String> _order(WidgetTester tester) => [
  for (final tab in tester.widgetList<Tab>(
    find.descendant(of: find.byType(TabBar), matching: find.byType(Tab)),
  ))
    ((tab.key! as ValueKey<String>).value).replaceFirst('home-scope-tab-', ''),
];

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _select(WidgetTester tester, String scope) async {
  await tester.ensureVisible(_tab(scope));
  await _settle(tester);
  await tester.tap(_tab(scope));
  await _settle(tester);
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  LocalStoreBackend? backend,
  bool embedded = false,
}) async {
  tester.view.physicalSize = Size(embedded ? 300 : 900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(fixture.projects.load);
  await tester.pumpWidget(
    GitHubScope(
      controller: fixture.github,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: StudioLocalizations.supportedLocales,
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
          embedded: embedded,
          showAgentsScope: !embedded,
          agentsTabBuilder: (_) => const Text('Agent fixture'),
          tabOrderStore: HomeTabOrderStore(
            backend: backend ?? LocalMemoryBackend(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

class _Fixture {
  _Fixture(Directory root) {
    final directory = root.createTempSync('case_');
    final folder = Directory(p.join(directory.path, 'Local'))..createSync();
    project = Project.create(name: 'Local', path: folder.path);
    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'projects': [project.toJson()],
        }),
      );
    projects = ProjectStore(storageFile: registry);
    addTearDown(() {
      github.dispose();
      auth.dispose();
      settings.dispose();
      projects.dispose();
    });
  }
  final github = _GitHub();
  final auth = AuthStore();
  final settings = SettingsStore();
  late final Project project;
  late final ProjectStore projects;
}

class _GitHub extends GitHubAuthController {
  bool connected = false;
  @override
  GitHubAuthStatus get status =>
      connected ? GitHubAuthStatus.authenticated : GitHubAuthStatus.signedOut;
  @override
  bool get hasConnection => connected;
  @override
  GitHubAccount? get account =>
      connected ? const GitHubAccount(id: 1, login: 'octocat') : null;
  @override
  List<GitHubRepository> get repositories => connected
      ? const [
          GitHubRepository(
            id: 7,
            name: 'hello-world',
            fullName: 'octocat/hello-world',
            ownerLogin: 'octocat',
            isPrivate: false,
            htmlUrl: 'https://github.com/octocat/hello-world',
            cloneUrl: 'https://github.com/octocat/hello-world.git',
          ),
        ]
      : const [];
  void connect() {
    connected = true;
    notifyListeners();
  }

  void disconnectForTest() {
    connected = false;
    notifyListeners();
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}
