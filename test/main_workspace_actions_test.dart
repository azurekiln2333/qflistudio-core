import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/saved_workspaces_tab.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

/// Release actions must work through the real toolbar, dialog and Home card.
void main() {
  StudioProfile? previous;

  setUp(() {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'main-workspace-actions-test',
      appTitle: 'QFLIStudio+',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
    );
  });

  tearDown(() => StudioProfile.current = previous);

  testWidgets(
    'one-project toolbar saves a named document, updates members and opens from Home',
    (tester) async {
      // Finish fixture IO before mounting: running queued store writes entirely
      // in the widget test's fake zone can otherwise deadlock the first pump.
      final fixture = (await tester.runAsync(
        () => _Fixture.create(registerSecond: false),
      ))!;
      addTearDown(fixture.dispose);
      final controller = RetainedEditorController();
      addTearDown(controller.dispose);
      expect(fixture.projects.projects, hasLength(1));

      await fixture.mountExplorer(tester);
      await tester.tap(find.byTooltip('工作区项目'));
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('workspace-name-field'))
            .evaluate()
            .isNotEmpty,
        'one-project workspace dialog',
      );
      expect(find.text('保存工作区'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      final primaryChoice = tester.widget<CheckboxListTile>(
        find.byKey(ValueKey('workspace-project-${fixture.first.id}')),
      );
      expect(primaryChoice.value, isTrue);
      expect(primaryChoice.onChanged, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('workspace-name-field')),
        'Release workbench',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await _pumpUntil(
        tester,
        () =>
            fixture.workspaces.workspaces.length == 1 &&
            find.byType(AlertDialog).evaluate().isEmpty &&
            find.text('Release workbench · 1 个项目').evaluate().isNotEmpty,
        'workspace save and explorer promotion',
      );

      final saved = fixture.workspaces.workspaces.single;
      final document = fixture.document(saved);
      expect(document.existsSync(), isTrue);
      expect(p.basename(document.parent.path), 'workspaces');
      expect(p.basename(document.parent.parent.path), 'data');
      final initialJson = fixture.readDocument(saved);
      expect(initialJson['name'], 'Release workbench');
      expect((initialJson['members'] as List).map((member) => member['path']), [
        fixture.first.path,
      ]);

      final second = (await tester.runAsync(fixture.registerSecond))!;
      await tester.tap(find.byTooltip('工作区项目'));
      await _pumpUntil(
        tester,
        () => find.text('工作区设置').evaluate().isNotEmpty,
        'saved workspace settings',
      );
      final secondChoice = find.byKey(
        ValueKey('workspace-project-${second.id}'),
      );
      expect(tester.widget<CheckboxListTile>(secondChoice).value, isFalse);
      await tester.tap(secondChoice);
      await tester.enterText(
        find.byKey(const ValueKey('workspace-name-field')),
        'Release tools',
      );
      await tester.tap(find.widgetWithText(FilledButton, '应用'));
      await _pumpUntil(
        tester,
        () =>
            fixture.workspaces.byId(saved.id)?.members.length == 2 &&
            find.byType(AlertDialog).evaluate().isEmpty &&
            fixture.root(second).evaluate().isNotEmpty,
        'workspace member update',
      );

      expect(fixture.workspaces.workspaces, hasLength(1));
      expect(find.text('Release tools · 2 个项目'), findsOneWidget);
      final updatedJson = fixture.readDocument(saved);
      expect(updatedJson['id'], saved.id);
      expect(updatedJson['name'], 'Release tools');
      expect((updatedJson['members'] as List).map((member) => member['path']), [
        fixture.first.path,
        second.path,
      ]);
      expect(
        fixture.workspaceDirectory.listSync().whereType<File>().map(
          (file) => p.basename(file.path),
        ),
        ['${saved.id}.json'],
      );
      expect(fixture.source(fixture.first).readAsStringSync(), 'first source');
      expect(fixture.source(second).readAsStringSync(), 'second source');

      await fixture.mountHome(tester, controller, 'Release tools');
      await tester.tap(find.text('Release tools'));
      await _pumpUntil(
        tester,
        () => controller.sessionInfos.isNotEmpty,
        'Home workspace card open',
      );
      expect(controller.sessionInfos, hasLength(1));
      expect(controller.activeProject?.path, fixture.first.path);
      expect(controller.sessionInfos.single.workspace?.id, saved.id);
      expect(controller.sessionInfos.single.workspace?.name, 'Release tools');
      expect(controller.sessionInfos.single.workspace?.memberPaths, [
        fixture.first.path,
        second.path,
      ]);
      await fixture.unmountAndDrain(tester);
    },
  );

  for (final missingPrimary in [false, true]) {
    testWidgets(
      'Home reports a missing ${missingPrimary ? 'primary' : 'secondary'} and opens only after proceed',
      (tester) async {
        late _Fixture fixture;
        late SavedWorkspace saved;
        await tester.runAsync(() async {
          fixture = await _Fixture.create();
          saved = await fixture.seedWorkspace();
          final missing = missingPrimary ? fixture.first : fixture.second!;
          await Directory(missing.path).delete(recursive: true);
        });
        addTearDown(fixture.dispose);
        final controller = RetainedEditorController();
        addTearDown(controller.dispose);
        final missing = missingPrimary ? fixture.first : fixture.second!;
        final survivor = missingPrimary ? fixture.second! : fixture.first;

        await fixture.mountHome(tester, controller, saved.name);
        await tester.tap(find.text(saved.name));
        await _pumpUntil(
          tester,
          () => find.text('部分项目不可用').evaluate().isNotEmpty,
          'missing-member dialog',
        );
        expect(find.textContaining(missing.path), findsOneWidget);
        expect(
          find.textContaining('主项目已缺失'),
          missingPrimary ? findsOneWidget : findsNothing,
        );
        expect(controller.sessionInfos, isEmpty);
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await tester.pumpAndSettle();
        expect(controller.sessionInfos, isEmpty);

        await tester.tap(find.text(saved.name));
        await _pumpUntil(
          tester,
          () => find.text('继续打开').evaluate().isNotEmpty,
          'reopened missing-member dialog',
        );
        await tester.tap(find.widgetWithText(FilledButton, '继续打开'));
        await _pumpUntil(
          tester,
          () => controller.sessionInfos.isNotEmpty,
          'surviving workspace member open',
        );
        expect(controller.sessionInfos, hasLength(1));
        expect(controller.activeProject?.path, survivor.path);
        expect(controller.sessionInfos.single.workspace?.id, saved.id);
        // Missing-member recovery never silently rewrites the saved references.
        expect(fixture.workspaces.byId(saved.id)?.members, hasLength(2));
        expect(fixture.document(saved).existsSync(), isTrue);
        await fixture.unmountAndDrain(tester);
      },
    );
  }

  testWidgets(
    'all unregistered members show recovery actions and metadata deletion leaves source folders',
    (tester) async {
      late _Fixture fixture;
      late SavedWorkspace saved;
      await tester.runAsync(() async {
        fixture = await _Fixture.create();
        saved = await fixture.seedWorkspace();
        fixture.projects.remove(fixture.first);
        fixture.projects.remove(fixture.second!);
        await fixture.projects.refresh();
      });
      addTearDown(fixture.dispose);
      final controller = RetainedEditorController();
      addTearDown(controller.dispose);

      await fixture.mountHome(tester, controller, saved.name);
      await tester.tap(find.text(saved.name));
      await _pumpUntil(
        tester,
        () => find.text('无法打开工作区').evaluate().isNotEmpty,
        'all-missing recovery dialog',
      );
      expect(find.textContaining(fixture.first.path), findsOneWidget);
      expect(find.textContaining(fixture.second!.path), findsOneWidget);
      expect(find.textContaining('请重新添加这些项目'), findsOneWidget);
      expect(find.text('继续打开'), findsNothing);
      expect(controller.sessionInfos, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      expect(fixture.document(saved).existsSync(), isTrue);

      await tester.tap(find.text(saved.name));
      await _pumpUntil(
        tester,
        () => find.text('无法打开工作区').evaluate().isNotEmpty,
        'all-missing dialog reopened',
      );
      await tester.tap(find.widgetWithText(FilledButton, '删除工作区记录'));
      await tester.pumpAndSettle();
      expect(find.text('删除工作区记录'), findsOneWidget);
      expect(find.textContaining('不会删除其中任何项目文件夹'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除记录'));
      await _pumpUntil(
        tester,
        () => find.text('还没有保存的工作区').evaluate().isNotEmpty,
        'Home empty state after metadata deletion',
      );
      expect(controller.sessionInfos, isEmpty);
      expect(fixture.document(saved).existsSync(), isFalse);
      expect(fixture.source(fixture.first).readAsStringSync(), 'first source');
      expect(
        fixture.source(fixture.second!).readAsStringSync(),
        'second source',
      );
      await fixture.unmountAndDrain(tester);
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() complete,
  String operation,
) async {
  for (var attempt = 0; attempt < 100 && !complete(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(complete(), isTrue, reason: '$operation did not finish');
  // Finish any dialog transition before the next physical click.
  await tester.pump(const Duration(milliseconds: 250));
}

class _Fixture {
  _Fixture(this.directory, this.projects, this.workspaces, this.first)
    : editor = EditorController(project: first);

  final Directory directory;
  final ProjectStore projects;
  final WorkspaceStore workspaces;
  final Project first;
  Project? second;
  final EditorController editor;
  final auth = AuthStore();
  final settings = SettingsStore();

  Directory get workspaceDirectory =>
      Directory(p.join(directory.path, 'data', 'workspaces'));

  static Future<_Fixture> create({bool registerSecond = true}) async {
    final directory = await Directory.systemTemp.createTemp('qfli_ws_actions_');
    for (final name in ['first', 'second']) {
      final root = Directory(p.join(directory.path, name));
      await root.create();
      await File(p.join(root.path, 'main.txt')).writeAsString('$name source');
    }
    final data = await Directory(p.join(directory.path, 'data')).create();
    final projects = ProjectStore(
      storageFile: File(p.join(data.path, 'projects.json')),
    );
    await projects.load();
    final first = await projects.addExisting(p.join(directory.path, 'first'));
    if (first.project == null) throw StateError(first.error!);
    final workspaces = WorkspaceStore(
      root: Directory(p.join(data.path, 'workspaces')),
    );
    await workspaces.load();
    final fixture = _Fixture(directory, projects, workspaces, first.project!);
    if (registerSecond) await fixture.registerSecond();
    return fixture;
  }

  Future<Project> registerSecond() async {
    final result = await projects.addExisting(p.join(directory.path, 'second'));
    if (result.project == null) throw StateError(result.error!);
    return second = result.project!;
  }

  Future<SavedWorkspace> seedWorkspace() async {
    final result = await workspaces.save(
      name: 'Release workbench',
      members: [first, second!],
      primary: first,
    );
    if (result.workspace == null) throw StateError(result.error!);
    return result.workspace!;
  }

  Finder root(Project project) =>
      find.byKey(ValueKey('workspace-root-${project.path}'));

  File source(Project project) => File(p.join(project.path, 'main.txt'));

  File document(SavedWorkspace workspace) =>
      File(p.join(workspaceDirectory.path, '${workspace.id}.json'));

  Map<String, dynamic> readDocument(SavedWorkspace workspace) =>
      jsonDecode(document(workspace).readAsStringSync())
          as Map<String, dynamic>;

  Future<void> mountExplorer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              height: 550,
              child: FileExplorer(
                project: first,
                editor: editor,
                store: projects,
                settings: settings,
                workspaceStore: workspaces,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => root(first).evaluate().isNotEmpty,
      'standalone explorer tree',
    );
  }

  Future<void> mountHome(
    WidgetTester tester,
    RetainedEditorController controller,
    String workspaceName,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RetainedEditorScope(
          controller: controller,
          child: Scaffold(
            body: SavedWorkspacesTab(
              store: projects,
              auth: auth,
              settings: settings,
              workspaceStore: workspaces,
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text(workspaceName).evaluate().isNotEmpty,
      'saved workspace Home card',
    );
  }

  Future<void> unmountAndDrain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var complete = false;
    // Pump continuations that originated in fake time while allowing file IO
    // to finish in real time; awaiting them inside runAsync alone can stall.
    final pending = Future.wait([workspaces.settle(), projects.refresh()]);
    pending.then((_) => complete = true);
    await _pumpUntil(tester, () => complete, 'fixture IO drain');
    await pending;
  }

  void dispose() {
    editor.dispose();
    auth.dispose();
    settings.dispose();
    projects.dispose();
    workspaces.dispose();
    directory.deleteSync(recursive: true);
  }
}
