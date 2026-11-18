import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_selection_toolbar.dart';
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

import 'support/ohos_target.dart';

void main() {
  StudioProfile? previous;
  setUp(() {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'workspace-project-switch-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
    );
  });
  tearDown(() => StudioProfile.current = previous);

  testWidgets(
    'workspace selector adds a non-member in one dialog and keeps identity, order and dirty buffers',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.unmount(tester));
      await fixture.mount(tester, retained: true);
      await fixture.expandWorkspace(tester);
      await tester.tap(_entry(fixture.first, 'a.txt'));
      await _pumpUntil(tester, () => _editor(tester).current != null, 'open A');
      final editor = _editor(tester);
      final pageState = tester.state(find.byType(EditorPage));
      final buffer = editor.current!;
      const dirtyText = 'unsaved workspace A';
      buffer.controller.text = dirtyText;
      await tester.pump();
      expect(buffer.dirty, isTrue);

      // 工作区模式下，标题即入口：一次点击就开多选。
      await tester.tap(fixture.picker);
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
        'add projects dialog',
      );

      // 已有成员固定勾选且不可取消，所以只能新增。
      for (final member in [fixture.first, fixture.second]) {
        final tile = tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('workspace-existing-${member.id}')),
        );
        expect(tile.value, isTrue);
        expect(tile.onChanged, isNull, reason: '已有成员不能被取消');
      }

      await tester.tap(
        find.byKey(ValueKey('workspace-add-${fixture.external.id}')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-add-confirm')));
      await _pumpUntil(
        tester,
        () => fixture.savedMembers().length == 3,
        'workspace gains the external member',
      );

      // 只追加：身份、名称、顺序都保留，外部项目排在末尾。
      final stored = fixture.savedWorkspacesById();
      expect(stored.id, fixture.saved.id);
      expect(stored.name, fixture.saved.name);
      expect(stored.members.map((m) => m.projectId).toList(), [
        fixture.first.id,
        fixture.second.id,
        fixture.external.id,
      ]);
      expect(stored.members.first.primary, isTrue, reason: '主成员身份不变');

      // 编辑器页、编辑器、脏缓冲都不受影响。
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.current, same(buffer));
      expect(buffer.controller.text, dirtyText);
      expect(buffer.dirty, isTrue);

      // 树刷新后包含新成员。
      await _pumpUntil(
        tester,
        () => _root(fixture.external).evaluate().isNotEmpty,
        'tree refreshes with the new member',
      );
      expect(_rootOrder(), [
        'workspace-root-${fixture.first.path}',
        'workspace-root-${fixture.second.path}',
        'workspace-root-${fixture.external.path}',
      ]);

      fixture.expectOriginalSources();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling workspace additions keeps the tree and dirty buffer',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.unmount(tester));
      await fixture.mount(tester, retained: true);
      await fixture.expandWorkspace(tester);
      await tester.tap(_entry(fixture.first, 'a.txt'));
      await _pumpUntil(tester, () => _editor(tester).current != null, 'open A');
      final editor = _editor(tester);
      final pageState = tester.state(find.byType(EditorPage));
      final buffer = editor.current!;
      buffer.controller.text = 'unsaved member A';
      await tester.pump();
      final treeScroll = _treeScroll(tester);

      final treeOffset = treeScroll.position.pixels;
      await tester.tap(fixture.picker);
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
        'additions picker',
      );
      await tester.tap(find.text('取消').last);
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
        'cancel additions',
      );

      // 同一个页面实例、同一个编辑器、同一个脏缓冲。
      expect(tester.state(find.byType(EditorPage)), same(pageState));
      expect(_editor(tester), same(editor));
      expect(editor.current, same(buffer));
      expect(buffer.controller.text, 'unsaved member A');
      expect(buffer.dirty, isTrue);
      expect(_treeScroll(tester), same(treeScroll));
      expect(treeScroll.position.pixels, treeOffset);
      // 浏览只换默认树，不增减成员。
      fixture.expectSavedMembersUnchanged();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plain project selector browses another project without navigating',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.unmount(tester));
      // 无工作区：普通项目模式。
      await fixture.mount(tester, retained: true, workspace: false);
      expect(_rootOrder(), ['workspace-root-${fixture.first.path}']);
      final firstPage = tester.state(find.byType(EditorPage));
      final pushesBefore = fixture.host.sessionInfos.length;

      await fixture.browseProject(tester, fixture.external);

      // 临时浏览：树换成外部项目，但页面和项目不变，也没有新会话。
      expect(_rootOrder(), ['workspace-root-${fixture.external.path}']);
      expect(
        tester.widget<EditorPage>(find.byType(EditorPage)).project.id,
        fixture.first.id,
        reason: '不能切换编辑器和 Agent 所属项目',
      );
      expect(tester.state(find.byType(EditorPage)), same(firstPage));
      expect(fixture.host.sessionInfos, hasLength(pushesBefore));
      expect(
        fixture.host.sessionInfos.every((session) => session.workspace == null),
        isTrue,
      );
      await _pumpUntil(
        tester,
        () => _entry(
          fixture.external,
          'src_c',
        ).hitTestable().evaluate().isNotEmpty,
        'external tree',
      );
      await tester.tap(_entry(fixture.external, 'src_c'));
      await _pumpUntil(
        tester,
        () => _entry(
          fixture.external,
          'c.txt',
        ).hitTestable().evaluate().isNotEmpty,
        'external file',
      );
      await tester.tap(_entry(fixture.external, 'c.txt'));
      await _pumpUntil(
        tester,
        () => _editor(tester).current != null,
        'open external file',
      );
      expect(
        _editor(tester).current!.path,
        p.join(fixture.external.path, 'src_c', 'c.txt'),
      );
      expect(
        tester.widget<EditorPage>(find.byType(EditorPage)).project.id,
        fixture.first.id,
      );

      // 还能浏览回来。
      await fixture.browseProject(tester, fixture.first);
      expect(_rootOrder(), ['workspace-root-${fixture.first.path}']);
      expect(tester.state(find.byType(EditorPage)), same(firstPage));
      fixture.expectSavedMembersUnchanged();
      expect(tester.takeException(), isNull);
    },
  );
}

EditorController _editor(WidgetTester tester) =>
    tester
            .widget<SelectionToolbarScope>(find.byType(SelectionToolbarScope))
            .editor
        as EditorController;

Finder _root(Project project) =>
    find.byKey(ValueKey('workspace-root-${project.path}'));

Finder _entry(Project project, String name) =>
    find.descendant(of: _root(project), matching: find.text(name));

List<String> _rootOrder() => find
    .byWidgetPredicate(
      (widget) =>
          widget is KeyedSubtree &&
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('workspace-root-'),
    )
    .evaluate()
    .map((element) => (element.widget.key as ValueKey<String>).value)
    .toList();

ScrollableState _treeScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(FileExplorer),
        matching: find.byType(Scrollable),
      ),
    );

Future<void> _waitForProject(WidgetTester tester, Project project) async {
  await _pumpUntil(
    tester,
    () =>
        find.byType(EditorPage).evaluate().length == 1 &&
        tester.widget<EditorPage>(find.byType(EditorPage)).project.id ==
            project.id &&
        _root(project).evaluate().isNotEmpty,
    'visible editor ${project.name}',
  );
  final openTree = find.byTooltip('打开文件树').hitTestable();
  if (openTree.evaluate().isNotEmpty) {
    await tester.tap(openTree);
  }
  await _pumpUntil(
    tester,
    () => _root(project).hitTestable().evaluate().isNotEmpty,
    'interactive tree ${project.name}',
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
    this.external,
  );

  final Directory directory;
  final ProjectStore projects;
  final WorkspaceStore workspaces;
  final SavedWorkspace saved;
  final Project first;
  final Project second;
  final Project external;
  final auth = AuthStore();
  final settings = SettingsStore();
  final host = RetainedEditorController();

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'workspace_switch_',
    );
    final projects = ProjectStore(
      storageFile: File(p.join(directory.path, 'projects.json')),
    );
    await projects.load();
    final registered = <Project>[];
    for (final letter in ['a', 'b', 'c']) {
      final root = Directory(p.join(directory.path, 'project_$letter'));
      await Directory(p.join(root.path, 'src_$letter')).create(recursive: true);
      await File(
        p.join(root.path, 'src_$letter', '$letter.txt'),
      ).writeAsString('source $letter');
      if (letter == 'b') {
        for (var index = 0; index < 30; index++) {
          await File(
            p.join(root.path, 'src_b', 'z_$index.txt'),
          ).writeAsString('tail');
        }
      }
      final result = await projects.addExisting(root.path);
      if (result.project == null) throw StateError(result.error!);
      registered.add(result.project!);
    }
    final workspaces = WorkspaceStore(
      root: Directory(p.join(directory.path, 'workspaces')),
    );
    await workspaces.load();
    final result = await workspaces.save(
      name: '工作区 A+B',
      members: [registered[0], registered[1]],
      primary: registered[0],
    );
    if (result.workspace == null) throw StateError(result.error!);
    return _Fixture(
      directory,
      projects,
      workspaces,
      result.workspace!,
      registered[0],
      registered[1],
      registered[2],
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    required bool retained,
    bool workspace = true,
  }) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: ohosPlatform),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorObservers: retained ? [host.navigatorObserver] : [],
        builder: retained
            ? (context, child) =>
                  RetainedEditorHost(controller: host, child: child!)
            : null,
        home: retained
            ? const Scaffold(body: Text('首页'))
            : EditorPage(
                project: first,
                auth: auth,
                store: projects,
                settings: settings,
                workspace: workspace ? saved : null,
                workspaceMembers: workspace ? [first, second] : const [],
                workspaceStore: workspaces,
              ),
      ),
    );
    if (retained) {
      host.open(
        project: first,
        auth: auth,
        store: projects,
        settings: settings,
        workspace: workspace ? saved : null,
        workspaceProjects: workspace ? [first, second] : const [],
        workspaceStore: workspaces,
      );
    }
    await _waitForProject(tester, first);
    await _pumpUntil(
      tester,
      () =>
          _entry(first, 'src_a').hitTestable().evaluate().isNotEmpty &&
          (!workspace ||
              _entry(second, 'src_b').hitTestable().evaluate().isNotEmpty),
      'workspace directory reads',
    );
  }

  /// 标题栏里的入口：工作区模式是加入按钮，普通模式是浏览菜单。
  Finder get picker =>
      find.byKey(const ValueKey('file-explorer-project-picker'));

  /// 落盘记录里的成员 id，按顺序。
  List<String> savedMembers() =>
      savedWorkspacesById().members.map((member) => member.projectId).toList();

  /// 从磁盘重新读取当前工作区记录。
  SavedWorkspace savedWorkspacesById() {
    final document =
        jsonDecode(
              File(
                p.join(directory.path, 'workspaces', '${saved.id}.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return SavedWorkspace.fromJson(document)!;
  }

  /// 通过标题栏选择器浏览另一个项目，不假定它会导航。
  Future<void> browseProject(WidgetTester tester, Project project) async {
    final entry = picker.hitTestable();
    expect(entry, findsOneWidget, reason: '项目选择器应当可用');
    await tester.tap(entry);
    // 工作区模式会直接弹多选；普通模式弹菜单。两种情况都等到出现项目名。
    await _pumpUntil(
      tester,
      () => find.text(project.name).evaluate().isNotEmpty,
      'project selector for ${project.name}',
    );
    final item = find.text(project.name).last;
    await tester.ensureVisible(item);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> expandWorkspace(WidgetTester tester) async {
    await tester.tap(_entry(first, 'src_a'));
    await tester.tap(_entry(second, 'src_b'));
    await _pumpUntil(
      tester,
      () =>
          _entry(first, 'a.txt').evaluate().isNotEmpty &&
          _entry(second, 'b.txt').evaluate().isNotEmpty,
      'workspace expansion',
    );
  }

  void expectSavedMembersUnchanged() {
    final document =
        jsonDecode(
              File(
                p.join(directory.path, 'workspaces', '${saved.id}.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      (document['members'] as List).map(
        (member) => (member as Map<String, dynamic>)['projectId'],
      ),
      [first.id, second.id],
    );
    expect(workspaces.byId(saved.id)!.memberPaths, [first.path, second.path]);
  }

  void expectOriginalSources() {
    for (final pair in [(first, 'a'), (second, 'b'), (external, 'c')]) {
      expect(
        File(
          p.join(pair.$1.path, 'src_${pair.$2}', '${pair.$2}.txt'),
        ).readAsStringSync(),
        'source ${pair.$2}',
      );
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    var drained = false;
    final pending = Future.wait([
      workspaces.settle(),
      projects.refresh(),
      for (final project in [first, second, external])
        ProjectHistory.load(project.path),
    ]);
    pending.then((_) => drained = true);
    await _pumpUntil(tester, () => drained, 'workspace IO drain');
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
