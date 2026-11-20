import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/home_project_tabs.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_card_git_');
  });

  tearDownAll(() async {
    await root.delete(recursive: true);
  });

  testWidgets('repository card displays its branch and full tooltip', (
    tester,
  ) async {
    const branch = 'feature/project-card';
    final project = await _project(tester, root, branch: branch);
    await _mount(tester, project);
    await _waitForBranch(tester, branch);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && (widget.message?.contains(branch) ?? false),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('revision reloads HEAD without replacing the project', (
    tester,
  ) async {
    final project = await _project(tester, root, branch: 'main');
    await _mount(tester, project);
    await _waitForBranch(tester, 'main');

    await _writeBranch(tester, project, 'feature/checkout');
    await _mount(tester, project, revision: 1);
    await _waitForBranch(tester, 'feature/checkout');

    expect(find.text('main'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('resuming reloads a branch changed outside the App', (
    tester,
  ) async {
    final project = await _project(tester, root, branch: 'main');
    await _mount(tester, project);
    await _waitForBranch(tester, 'main');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _writeBranch(tester, project, 'feature/external-checkout');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _waitForBranch(tester, 'feature/external-checkout');

    expect(find.text('main'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('minimizing the retained editor refreshes Home branch cards', (
    tester,
  ) async {
    final previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'card-git-return-test',
      appTitle: 'Studio',
      templates: [],
      isOffline: true,
      supportsSavedWorkspaces: false,
    );
    addTearDown(() => StudioProfile.current = previousProfile);
    final project = await _project(tester, root, branch: 'main');
    final store = ProjectStore(
      storageFile: File(p.join(project.path, 'registry.json')),
    );
    final auth = AuthStore();
    final settings = SettingsStore();
    final retainedEditor = RetainedEditorController();
    addTearDown(store.dispose);
    addTearDown(auth.dispose);
    addTearDown(settings.dispose);
    addTearDown(retainedEditor.dispose);
    await tester.runAsync(() async {
      await store.load();
      final result = await store.addExisting(project.path);
      expect(result.error, isNull);
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          StudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: RetainedEditorScope(
          controller: retainedEditor,
          child: HomeTab(
            store: store,
            auth: auth,
            settings: settings,
            tabOrderStore: HomeTabOrderStore(backend: LocalMemoryBackend()),
          ),
        ),
      ),
    );
    await _waitForBranch(tester, 'main', visibleOnly: true);

    // No retained host is mounted: this exercises the real visibility owner
    // without starting EditorPage or any editor-side service.
    retainedEditor.open(
      project: project,
      auth: auth,
      store: store,
      settings: settings,
    );
    await tester.pump();
    await _writeBranch(tester, project, 'feature/retained-checkout');
    retainedEditor.minimize();
    await tester.pump();
    await _waitForBranch(
      tester,
      'feature/retained-checkout',
      visibleOnly: true,
    );

    expect(find.text('main').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('ordinary and cloud project cards hide local branch metadata', (
    tester,
  ) async {
    final ordinary = await _project(tester, root);
    await _mount(tester, ordinary);
    await _drainMetadata(tester);
    expect(find.byIcon(Icons.call_split_outlined), findsNothing);

    final repository = await _project(tester, root, branch: 'cloud-local-copy');
    final cloud = Project.create(
      name: 'Cloud project',
      path: repository.path,
      cloudId: 'cloud-project',
    );
    await _mount(tester, cloud);
    await _drainMetadata(tester);

    expect(find.text('cloud-local-copy'), findsNothing);
    expect(find.byIcon(Icons.call_split_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('reused card clears the branch when its project path changes', (
    tester,
  ) async {
    final first = await _project(tester, root, branch: 'feature/first');
    final second = await _project(tester, root, branch: 'feature/second');
    await _mount(tester, first);
    await _waitForBranch(tester, 'feature/first');
    await _mount(tester, second);
    await _waitForBranch(tester, 'feature/second');

    expect(find.text('feature/first'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('cloud conversion hides the branch on the same project object', (
    tester,
  ) async {
    final project = await _project(tester, root, branch: 'feature/local-only');
    await _mount(tester, project);
    await _waitForBranch(tester, 'feature/local-only');

    project.cloudId = 'cloud-project';
    await _mount(tester, project);
    await _drainMetadata(tester);

    expect(find.text('feature/local-only'), findsNothing);
    expect(find.byIcon(Icons.call_split_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('long branch fits a narrow card at text scale $textScale', (
      tester,
    ) async {
      const branch =
          'feature/a-very-long-project-branch-name/that-must-not-overflow';
      final project = await _project(tester, root, branch: branch);
      await _mount(tester, project, textScale: textScale);
      await _waitForBranch(tester, branch);

      final text = tester.widget<Text>(find.text(branch));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }
}

Future<Project> _project(
  WidgetTester tester,
  Directory root, {
  String? branch,
}) async {
  return (await tester.runAsync(() async {
    final directory = await root.createTemp('project_');
    if (branch != null) {
      final head = File(p.join(directory.path, '.git', 'HEAD'));
      await head.parent.create(recursive: true);
      await head.writeAsString('ref: refs/heads/$branch\n', flush: true);
    }
    return Project.create(name: 'Project', path: directory.path);
  }))!;
}

Future<void> _writeBranch(
  WidgetTester tester,
  Project project,
  String branch,
) async {
  await tester.runAsync(() async {
    await File(
      p.join(project.path, '.git', 'HEAD'),
    ).writeAsString('ref: refs/heads/$branch\n', flush: true);
  });
}

Future<void> _mount(
  WidgetTester tester,
  Project project, {
  int revision = 0,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 296,
              height: 180,
              child: ProjectCard(
                project: project,
                gitRefreshRevision: revision,
                onOpen: () {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _waitForBranch(
  WidgetTester tester,
  String branch, {
  bool visibleOnly = false,
}) async {
  final finder = visibleOnly
      ? find.text(branch).hitTestable()
      : find.text(branch);
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

Future<void> _drainMetadata(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _drainMetadata(tester);
}
