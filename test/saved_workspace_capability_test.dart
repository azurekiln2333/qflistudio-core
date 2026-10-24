import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/editor_workspace.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

void main() {
  StudioProfile? previous;
  setUp(() => previous = StudioProfile.current);
  tearDown(() => StudioProfile.current = previous);

  test('null and existing profiles enable named workspaces independently', () {
    StudioProfile.current = null;
    expect(supportsSavedWorkspaces, isTrue);
    expect(isMainStudioRelease, isTrue);
    for (final productKey in [
      StudioProductCatalog.qfliStudioKey,
      StudioProductCatalog.jsonKey,
    ]) {
      for (final offlineOnly in [true, false]) {
        for (final showHomeTabs in [true, false]) {
          final profile = StudioProfile(
            id: 'capability-default',
            appTitle: 'Workspace capability',
            templates: const [],
            productKey: productKey,
            offlineOnly: offlineOnly,
            showHomeTabs: showHomeTabs,
          );
          StudioProfile.current = profile;
          expect(profile.supportsSavedWorkspaces, isTrue);
          expect(supportsSavedWorkspaces, isTrue);
          expect(profile.offlineOnly, offlineOnly);
          expect(profile.showHomeTabs, showHomeTabs);
          expect(
            isMainStudioRelease,
            productKey == StudioProductCatalog.qfliStudioKey,
          );
        }
      }
    }
  });

  test('explicit opt-out does not change identity or network policy', () {
    for (final productKey in [
      StudioProductCatalog.qfliStudioKey,
      StudioProductCatalog.jsonKey,
    ]) {
      for (final offlineOnly in [true, false]) {
        StudioProfile.current = _profile(
          productKey: productKey,
          offlineOnly: offlineOnly,
          supportsSavedWorkspaces: false,
        );
        expect(supportsSavedWorkspaces, isFalse);
        expect(StudioProfile.current!.offlineOnly, offlineOnly);
        expect(
          isMainStudioRelease,
          productKey == StudioProductCatalog.qfliStudioKey,
        );
      }
    }
  });

  for (final offlineOnly in [true, false]) {
    testWidgets(
      'child explorer saves a named local workspace with offlineOnly=$offlineOnly',
      (tester) async {
        StudioProfile.current = _profile(offlineOnly: offlineOnly);
        final fixture = (await tester.runAsync(_ExplorerFixture.create))!;
        await fixture.mount(tester);
        await tester.tap(find.byTooltip('工作区项目'));
        await _until(
          tester,
          () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );
        final name = find.byKey(const ValueKey('workspace-name-field'));
        expect(name.hitTestable(), findsOneWidget);
        await tester.enterText(name, 'Child local workspace');
        await tester.tap(
          find.byKey(ValueKey('workspace-project-${fixture.secondary.id}')),
        );
        await tester.tap(find.widgetWithText(FilledButton, '保存'));
        await _until(tester, () => fixture.changed?.saved != null);

        final saved = fixture.workspaces.workspaces.single;
        expect(saved.name, 'Child local workspace');
        expect(saved.memberPaths, [
          fixture.primary.path,
          fixture.secondary.path,
        ]);
        expect(fixture.changed!.saved!.id, saved.id);
        expect(
          File(
            p.join(fixture.workspaceRoot.path, '${saved.id}.json'),
          ).existsSync(),
          isTrue,
        );
        fixture.expectSourcesUnchanged();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opted-out child retains its legacy membership picker', (
    tester,
  ) async {
    StudioProfile.current = _profile(supportsSavedWorkspaces: false);
    final fixture = (await tester.runAsync(_ExplorerFixture.create))!;
    await fixture.mount(tester);
    await tester.tap(find.byTooltip('工作区项目'));
    await _until(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('workspace-name-field')), findsNothing);
    await tester.tap(
      find.byKey(ValueKey('workspace-project-${fixture.secondary.id}')),
    );
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await _until(
      tester,
      () => find
          .byKey(ValueKey('workspace-root-${fixture.secondary.path}'))
          .evaluate()
          .isNotEmpty,
    );
    List<String>? persistedRoots;
    ProjectHistory.load(fixture.primary.path).then((history) {
      persistedRoots = history.workspaceRoots;
    });
    await _until(tester, () => persistedRoots != null);
    expect(persistedRoots, contains(fixture.secondary.path));
    expect(fixture.workspaces.workspaces, isEmpty);
    expect(fixture.changed, isNull);
    fixture.expectSourcesUnchanged();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opted-out main disables unnamed workspace creation', (
    tester,
  ) async {
    StudioProfile.current = _profile(
      productKey: StudioProductCatalog.qfliStudioKey,
      supportsSavedWorkspaces: false,
    );
    final fixture = (await tester.runAsync(_ExplorerFixture.create))!;
    await fixture.mount(tester);
    final action = tester.widget<IconButton>(_workspaceAction());
    expect(action.onPressed, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.workspaces.workspaces, isEmpty);
    fixture.expectSourcesUnchanged();
  });

  for (final productKey in [
    StudioProductCatalog.qfliStudioKey,
    StudioProductCatalog.jsonKey,
  ]) {
    testWidgets('opted-out $productKey still manages an explicit document', (
      tester,
    ) async {
      StudioProfile.current = _profile(
        productKey: productKey,
        supportsSavedWorkspaces: false,
      );
      final fixture = (await tester.runAsync(
        () => _ExplorerFixture.create(saveWorkspace: true),
      ))!;
      await fixture.mount(tester);
      final originalId = fixture.saved!.id;
      final action = tester.widget<IconButton>(_workspaceAction());
      expect(action.onPressed, isNotNull);
      await tester.tap(find.byTooltip('工作区项目'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(find.text('工作区设置').hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('workspace-name-field')),
        'Retained explicit workspace',
      );
      await tester.tap(find.widgetWithText(FilledButton, '应用'));
      await _until(
        tester,
        () => fixture.changed?.saved?.name == 'Retained explicit workspace',
      );
      expect(fixture.workspaces.workspaces.single.id, originalId);
      expect(
        fixture.workspaces.workspaces.single.name,
        'Retained explicit workspace',
      );
      fixture.expectSourcesUnchanged();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cloud primary refuses named saving before opening its dialog', (
    tester,
  ) async {
    StudioProfile.current = _profile(offlineOnly: false);
    final fixture = (await tester.runAsync(
      () => _ExplorerFixture.create(cloudPrimary: true),
    ))!;
    await fixture.mount(tester);
    expect(fixture.primary.isCloud, isTrue);
    expect(
      tester.widget<IconButton>(_workspaceAction()).onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('工作区项目'));
    await _until(
      tester,
      () => find.text('仅本地项目可保存工作区，请先打开本地项目').evaluate().isNotEmpty,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('workspace-name-field')), findsNothing);
    expect(fixture.workspaces.workspaces, isEmpty);
    expect(fixture.workspaceRoot.listSync(), isEmpty);
    expect(fixture.changed, isNull);
    fixture.expectSourcesUnchanged();
    expect(tester.takeException(), isNull);
  });
}

Finder _workspaceAction() => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == '工作区项目',
);

StudioProfile _profile({
  String productKey = StudioProductCatalog.jsonKey,
  bool offlineOnly = true,
  bool supportsSavedWorkspaces = true,
}) => StudioProfile(
  id: 'workspace-capability',
  appTitle: 'Workspace capability',
  templates: const [],
  productKey: productKey,
  offlineOnly: offlineOnly,
  showHomeTabs: false,
  supportsSavedWorkspaces: supportsSavedWorkspaces,
);

class _ExplorerFixture {
  _ExplorerFixture(this.directory, this.primary, this.secondary, this.store);

  final Directory directory;
  final Project primary;
  final Project secondary;
  final ProjectStore store;
  final settings = SettingsStore();
  late final editor = EditorController(project: primary);
  late final workspaceRoot = Directory(p.join(directory.path, 'workspaces'));
  late final workspaces = WorkspaceStore(root: workspaceRoot);
  SavedWorkspace? saved;
  EditorWorkspaceState? changed;

  static Future<_ExplorerFixture> create({
    bool cloudPrimary = false,
    bool saveWorkspace = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'qfli_workspace_capability_',
    );
    Project createProject(String name, {bool cloud = false}) {
      final path = Directory(p.join(directory.path, name))..createSync();
      File(
        p.join(path.path, 'main.json'),
      ).writeAsStringSync('{"owner":"$name"}\n');
      return Project.create(
        name: name,
        path: path.path,
        cloudId: cloud ? 'workspace-cloud-primary' : null,
        type: 'json',
        language: 'JSON',
      );
    }

    final primary = createProject('Primary', cloud: cloudPrimary);
    final secondary = createProject('Secondary');
    final registry = File(p.join(directory.path, 'projects.json'))
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'projects': [primary.toJson(), secondary.toJson()],
        }),
      );
    final store = ProjectStore(storageFile: registry);
    await store.load();
    final fixture = _ExplorerFixture(directory, primary, secondary, store);
    await fixture.workspaces.load();
    if (saveWorkspace) {
      final result = await fixture.workspaces.save(
        name: 'Existing explicit workspace',
        members: [primary, secondary],
        primary: primary,
      );
      expect(result.error, isNull);
      fixture.saved = result.workspace!;
    }
    return fixture;
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => dispose(tester));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: FileExplorer(
              project: primary,
              editor: editor,
              store: store,
              settings: settings,
              workspace: saved,
              workspaceMembers: saved == null ? const [] : [primary, secondary],
              workspaceStore: workspaces,
              onWorkspaceChanged: (state) => changed = state,
            ),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () => find
          .byKey(ValueKey('workspace-root-${primary.path}'))
          .evaluate()
          .isNotEmpty,
    );
  }

  void expectSourcesUnchanged() {
    for (final project in [primary, secondary]) {
      expect(
        File(p.join(project.path, 'main.json')).readAsStringSync(),
        '{"owner":"${project.name}"}\n',
      );
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var drained = false;
    Future.wait([
      ProjectHistory.load(primary.path),
      ProjectHistory.load(secondary.path),
      workspaces.settle(),
      store.refresh(),
    ]).then((_) => drained = true);
    await _until(tester, () => drained);
    editor.dispose();
    settings.dispose();
    store.dispose();
    workspaces.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue, reason: 'Workspace capability UI did not settle');
}
