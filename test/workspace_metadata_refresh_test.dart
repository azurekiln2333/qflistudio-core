import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

void main() {
  StudioProfile? previous;
  setUp(() {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'workspace-metadata-refresh-test',
      appTitle: 'QFLIStudio+',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      offlineOnly: true,
    );
  });
  tearDown(() => StudioProfile.current = previous);

  testWidgets(
    'same-id external rename refreshes the live settings and cannot revert on expansion',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.unmount(tester));
      await fixture.mount(tester);
      await fixture.expand(tester, fixture.first, 'a');
      await tester.tap(_entry(fixture.first, 'a.txt'));
      await _pumpUntil(
        tester,
        () => _editor(tester).current?.name == 'a.txt',
        'open primary source',
      );
      final editor = _editor(tester);
      final pageState = tester.state(find.byType(EditorPage));
      final sessionKey = fixture.host.sessionInfos.single.key;
      final dirty = editor.current!;
      dirty.controller.text = 'unsaved primary text';
      await tester.pump();
      expect(dirty.dirty, isTrue);

      WorkspaceSaveResult? renameResult;
      Object? renameFailure;
      var renameCompleted = false;
      unawaited(
        fixture.workspaces
            .save(
              existing: fixture.saved,
              name: '外部重命名工作区',
              members: [fixture.first, fixture.second],
              primary: fixture.first,
            )
            .then<void>(
              (result) {
                renameResult = result;
                renameCompleted = true;
              },
              onError: (Object error, StackTrace stackTrace) {
                renameFailure = error;
                renameCompleted = true;
              },
            ),
      );
      await _pumpUntil(tester, () => renameCompleted, 'external metadata save');
      expect(renameFailure, isNull);
      expect(renameResult, isNotNull);
      expect(renameResult!.error, isNull);
      final renamed = renameResult!.workspace;
      expect(renamed, isNotNull);
      fixture.open(renamed!, [fixture.first, fixture.second]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(fixture.host.sessionInfos, hasLength(1));
      expect(fixture.host.sessionInfos.single.key, sessionKey);
      expect(fixture.host.activeProject?.id, fixture.first.id);
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.current, same(dirty));
      expect(_entry(fixture.first, 'a.txt').hitTestable(), findsOneWidget);
      expect(
        tester.widget<FileExplorer>(find.byType(FileExplorer)).workspace?.name,
        '外部重命名工作区',
      );

      // The explorer keeps its own saved metadata, so inspecting only the
      // parent's new widget would miss its stale settings dialog.
      await _openSettings(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('workspace-name-field')),
            )
            .controller!
            .text,
        '外部重命名工作区',
      );
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
        'settings cancel',
      );

      // Expanding another root emits EditorWorkspaceState. It must not send
      // the previous name back through the page and retained host.
      await fixture.expand(tester, fixture.second, 'b');
      expect(fixture.host.sessionInfos.single.workspace?.name, '外部重命名工作区');
      expect(
        tester.widget<FileExplorer>(find.byType(FileExplorer)).workspace?.name,
        '外部重命名工作区',
      );
      expect(find.text('外部重命名工作区 · 2 个项目'), findsOneWidget);
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.current, same(dirty));
      expect(dirty.controller.text, 'unsaved primary text');
      expect(dirty.dirty, isTrue);
      fixture.expectOriginalSources();
      await fixture.settle(tester);
      expect(fixture.persisted()['name'], '外部重命名工作区');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-id settings save updates host members and keeps a removed dirty buffer',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.unmount(tester));
      await fixture.mount(tester);
      await fixture.expand(tester, fixture.first, 'a');
      await fixture.expand(tester, fixture.second, 'b');
      await tester.tap(_entry(fixture.first, 'a.txt'));
      await _pumpUntil(
        tester,
        () => _editor(tester).current?.name == 'a.txt',
        'open primary source',
      );
      final editor = _editor(tester);
      final primaryBuffer = editor.current!;
      primaryBuffer.controller.text = 'unsaved primary text';
      await tester.pump();
      await tester.tap(_entry(fixture.second, 'b.txt'));
      await _pumpUntil(
        tester,
        () => editor.current?.name == 'b.txt',
        'open secondary source',
      );
      final removedBuffer = editor.current!;
      removedBuffer.controller.text = 'unsaved secondary recovery';
      await tester.pump();
      final pageState = tester.state(find.byType(EditorPage));
      final sessionKey = fixture.host.sessionInfos.single.key;

      // A name-only save has unchanged member paths. It must still reach the
      // retained host rather than being mistaken for a no-op attachment.
      await _openSettings(tester);
      await tester.enterText(
        find.byKey(const ValueKey('workspace-name-field')),
        '只重命名保留成员',
      );
      await tester.tap(find.widgetWithText(FilledButton, '应用'));
      await _pumpUntil(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            fixture.host.sessionInfos.single.workspace?.name == '只重命名保留成员',
        'name-only same-id workspace apply',
      );
      expect(fixture.host.sessionInfos.single.key, sessionKey);
      expect(fixture.host.sessionInfos.single.workspace?.memberPaths, [
        fixture.first.path,
        fixture.second.path,
      ]);
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.current, same(removedBuffer));

      await _openSettings(tester);
      await tester.enterText(
        find.byKey(const ValueKey('workspace-name-field')),
        '编辑器内重命名工作区',
      );
      final secondaryChoice = find.byKey(
        ValueKey('workspace-project-${fixture.second.id}'),
      );
      expect(tester.widget<CheckboxListTile>(secondaryChoice).value, isTrue);
      await tester.tap(secondaryChoice);
      await tester.tap(find.widgetWithText(FilledButton, '应用'));
      await _pumpUntil(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            fixture.host.sessionInfos.single.workspace?.name == '编辑器内重命名工作区',
        'same-id workspace apply',
      );

      final live = fixture.host.sessionInfos.single;
      expect(live.key, sessionKey);
      expect(live.workspace?.id, fixture.saved.id);
      expect(live.workspace?.memberPaths, [fixture.first.path]);
      expect(live.project.id, fixture.first.id);
      expect(fixture.host.sessionInfos, hasLength(1));
      expect(_root(fixture.second), findsNothing);
      expect(
        tester
            .widget<EditorPage>(find.byType(EditorPage))
            .workspaceMembers
            .map((project) => project.path),
        [fixture.first.path],
      );
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.files, containsAll([primaryBuffer, removedBuffer]));
      expect(editor.current, same(removedBuffer));
      expect(primaryBuffer.controller.text, 'unsaved primary text');
      expect(removedBuffer.controller.text, 'unsaved secondary recovery');
      expect(primaryBuffer.dirty, isTrue);
      expect(removedBuffer.dirty, isTrue);

      // A subsequent same-id reopen uses the current metadata and keeps the
      // same live page instead of reintroducing the removed member.
      fixture.host.minimize();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      fixture.open(live.workspace!, [fixture.first]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(fixture.host.sessionInfos.single.key, sessionKey);
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.files, contains(removedBuffer));
      expect(removedBuffer.controller.text, 'unsaved secondary recovery');
      expect(_root(fixture.second), findsNothing);
      await _openSettings(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('workspace-name-field')),
            )
            .controller!
            .text,
        '编辑器内重命名工作区',
      );
      expect(tester.widget<CheckboxListTile>(secondaryChoice).value, isFalse);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
        'settings cancel after reopen',
      );
      fixture.expectOriginalSources();
      await fixture.settle(tester);
      final document = fixture.persisted();
      expect(document['name'], '编辑器内重命名工作区');
      expect(
        (document['members'] as List).map(
          (member) => (member as Map<String, dynamic>)['projectId'],
        ),
        [fixture.first.id],
      );
      expect(tester.takeException(), isNull);
    },
  );
}

EditorController _editor(WidgetTester tester) =>
    tester.widget<FileExplorer>(find.byType(FileExplorer)).editor;

Finder _root(Project project) =>
    find.byKey(ValueKey('workspace-root-${project.path}'));

Finder _entry(Project project, String name) =>
    find.descendant(of: _root(project), matching: find.text(name));

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('工作区项目').hitTestable());
  await _pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
    'workspace settings',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String operation,
) async {
  for (var attempt = 0; attempt < 150 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: '$operation did not finish');
  await tester.pump(const Duration(milliseconds: 300));
}

class _Fixture {
  _Fixture(
    this.directory,
    this.projects,
    this.workspaces,
    this.saved,
    this.first,
    this.second,
  );

  final Directory directory;
  final ProjectStore projects;
  final WorkspaceStore workspaces;
  final SavedWorkspace saved;
  final Project first;
  final Project second;
  final auth = AuthStore();
  final settings = SettingsStore();
  final host = RetainedEditorController();

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'workspace_metadata_',
    );
    final projects = ProjectStore(
      storageFile: File(p.join(directory.path, 'projects.json')),
    );
    await projects.load();
    final registered = <Project>[];
    for (final letter in ['a', 'b']) {
      final root = Directory(p.join(directory.path, 'project_$letter'));
      await Directory(p.join(root.path, 'src_$letter')).create(recursive: true);
      await File(
        p.join(root.path, 'src_$letter', '$letter.txt'),
      ).writeAsString('source $letter');
      final result = await projects.addExisting(root.path);
      if (result.project == null) throw StateError(result.error!);
      registered.add(result.project!);
    }
    final workspaces = WorkspaceStore(
      root: Directory(p.join(directory.path, 'workspaces')),
    );
    await workspaces.load();
    final result = await workspaces.save(
      name: '原工作区',
      members: registered,
      primary: registered.first,
    );
    if (result.workspace == null) throw StateError(result.error!);
    return _Fixture(
      directory,
      projects,
      workspaces,
      result.workspace!,
      registered[0],
      registered[1],
    );
  }

  void open(SavedWorkspace workspace, List<Project> members) {
    host.open(
      project: first,
      auth: auth,
      store: projects,
      settings: settings,
      workspace: workspace,
      workspaceProjects: members,
      workspaceStore: workspaces,
    );
  }

  Future<void> mount(WidgetTester tester) async {
    settings.autoSave = false;
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.ohos),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorObservers: [host.navigatorObserver],
        builder: (context, child) =>
            RetainedEditorHost(controller: host, child: child!),
        home: const Scaffold(body: Text('首页')),
      ),
    );
    open(saved, [first, second]);
    await _pumpUntil(
      tester,
      () => find.byTooltip('打开文件树').hitTestable().evaluate().isNotEmpty,
      'retained editor mount',
    );
    await tester.tap(find.byTooltip('打开文件树'));
    await _pumpUntil(
      tester,
      () =>
          _entry(first, 'src_a').hitTestable().evaluate().isNotEmpty &&
          _entry(second, 'src_b').hitTestable().evaluate().isNotEmpty,
      'workspace root reads',
    );
  }

  Future<void> expand(
    WidgetTester tester,
    Project project,
    String letter,
  ) async {
    await tester.tap(_entry(project, 'src_$letter'));
    await _pumpUntil(
      tester,
      () => _entry(project, '$letter.txt').hitTestable().evaluate().isNotEmpty,
      'expand ${project.name}',
    );
  }

  void expectOriginalSources() {
    for (final pair in [(first, 'a'), (second, 'b')]) {
      expect(
        File(
          p.join(pair.$1.path, 'src_${pair.$2}', '${pair.$2}.txt'),
        ).readAsStringSync(),
        'source ${pair.$2}',
      );
    }
  }

  Map<String, dynamic> persisted() =>
      jsonDecode(
            File(
              p.join(directory.path, 'workspaces', '${saved.id}.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  Future<void> settle(WidgetTester tester) async {
    var drained = false;
    final pending = workspaces.settle().then((_) => drained = true);
    await _pumpUntil(tester, () => drained, 'workspace IO drain');
    await pending;
  }

  Future<void> unmount(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    var drained = false;
    final pending = Future.wait([
      workspaces.settle(),
      projects.refresh(),
      ProjectHistory.load(first.path),
      ProjectHistory.load(second.path),
    ]);
    pending.then((_) => drained = true);
    await _pumpUntil(tester, () => drained, 'unmounted workspace IO drain');
    await pending;
    for (var round = 0; round < 4; round++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  void dispose() {
    host.dispose();
    auth.dispose();
    settings.dispose();
    projects.dispose();
    workspaces.dispose();
    directory.deleteSync(recursive: true);
  }
}
