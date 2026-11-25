import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/shortcut_label.dart';
import 'package:qfli_studio_core/shell/workbench_explorer.dart';
import 'package:qfli_studio_core/shell/workbench_theme.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

void main() {
  late _Fixture fixture;
  StudioProfile? previousProfile;

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'workbench-header-test',
      appTitle: 'Explorer test',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
    );
    fixture = await _Fixture.create();
  });

  tearDown(() => StudioProfile.current = previousProfile);

  // R5/R14 and design 11.2: the files page has one header owned by the real
  // FileExplorer, not another shell title plus a phone picker/summary strip.
  for (final brightness in Brightness.values) {
    for (final layout in [
      (factor: AppFormFactor.desktop, width: 300.0),
      (factor: AppFormFactor.desktop, width: 220.0),
      (factor: AppFormFactor.tablet, width: 300.0),
      (factor: AppFormFactor.tablet, width: 220.0),
      (factor: AppFormFactor.tablet, width: 480.0),
    ]) {
      testWidgets(
        'one ${layout.factor.name} files header at ${layout.width} in ${brightness.name}',
        (tester) async {
          await fixture.mount(
            tester,
            formFactor: layout.factor,
            width: layout.width,
            brightness: brightness,
          );
          final desktop = layout.factor == AppFormFactor.desktop;
          final height = desktop ? 40.0 : 48.0;
          final target = desktop ? 32.0 : 48.0;
          final header = find.byKey(const ValueKey('file-explorer-header'));
          final back = find.byKey(WorkbenchExplorer.backKey);
          final title = find.byKey(
            const ValueKey('file-explorer-header-project-name'),
          );
          final more = find.byKey(const ValueKey('file-explorer-more'));
          final newFile = find.byTooltip('新建文件 (${shortcutLabel('Ctrl+N')})');
          expect(tester.getSize(header), Size(layout.width, height));
          expect(tester.getSize(back), Size(target, height));
          expect(tester.getSize(more), Size(target, height));
          expect(tester.getSize(newFile), Size(target, height));
          expect(tester.getSize(title).width, greaterThanOrEqualTo(72));
          final text = tester.widget<Text>(title);
          expect(text.data, fixture.first.name);
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          expect(
            text.style,
            Theme.of(tester.element(title)).textTheme.titleSmall,
          );
          expect(find.text(fixture.first.name), findsNWidgets(2));
          expect(
            find.byKey(const ValueKey('file-explorer-project-picker')),
            findsNothing,
          );
          expect(find.textContaining('工作区 ·'), findsNothing);
          expect(find.byTooltip('工作区项目'), findsNothing);
          final root = find.byKey(ValueKey('file-row-${fixture.first.path}'));
          expect(
            tester.getTopLeft(root).dy,
            tester.getTopLeft(header).dy + height + 3,
          );
          final fullActions = layout.width >= (desktop ? 276 : 388);
          final showsSearch = layout.width >= (desktop ? 212 : 292);
          expect(
            find.byTooltip('新建文件夹'),
            fullActions ? findsOneWidget : findsNothing,
          );
          expect(
            find.byTooltip('刷新'),
            fullActions ? findsOneWidget : findsNothing,
          );
          expect(
            find.byTooltip('搜索文件'),
            showsSearch ? findsOneWidget : findsNothing,
          );
          if (showsSearch) {
            expect(
              tester.getSize(find.byTooltip('搜索文件')),
              Size(target, height),
            );
          }
          final fileState = tester.state(find.byType(FileExplorer));
          await tester.tap(more);
          await tester.pumpAndSettle();
          expect(find.text('工作区设置'), findsOneWidget);
          expect(find.text('全部折叠'), findsOneWidget);
          expect(
            find.byKey(
              ValueKey('file-explorer-workspace-member-${fixture.first.id}'),
            ),
            findsNothing,
          );
          if (!fullActions) {
            expect(find.text('新建文件夹'), findsOneWidget);
            expect(find.text('刷新'), findsOneWidget);
          }
          if (!showsSearch) expect(find.text('搜索文件'), findsOneWidget);
          final collapse = find.widgetWithText(MenuItemButton, '全部折叠');
          expect(tester.getSize(collapse).height, desktop ? 32 : 48);
          await tester.tap(collapse);
          await tester.pumpAndSettle();
          expect(find.text('first.dart'), findsNothing);
          expect(root, findsOneWidget);
          expect(tester.state(find.byType(FileExplorer)), same(fileState));
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(fixture.shell.explorerPage, ExplorerPage.projects);
          expect(fixture.shell.activeEditor, same(fixture.editor));
          fixture.shell.showFiles();
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(FileExplorer)), same(fileState));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'minimum tablet sidebar keeps search and refresh usable in More',
    (tester) async {
      await fixture.mount(tester, formFactor: AppFormFactor.tablet, width: 220);
      final more = find.byKey(const ValueKey('file-explorer-more'));
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '搜索文件'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'first.dart');
      await _waitFor(
        tester,
        () => find.text('first.dart').evaluate().isNotEmpty,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '退出搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.runAsync(
        () => File(
          p.join(fixture.first.path, 'added.dart'),
        ).writeAsString('const added = 1;'),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '刷新'));
      await _waitFor(
        tester,
        () => find.text('added.dart').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace settings remain reachable without a summary strip', (
    tester,
  ) async {
    await fixture.mount(tester);
    final state = tester.state(find.byType(FileExplorer));
    await tester.tap(find.byKey(const ValueKey('file-explorer-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '工作区设置'));
    await _waitFor(
      tester,
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FileExplorer)), same(state));
    expect(find.byTooltip('工作区项目'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multi-member More switches browse identity and preserves editor ownership',
    (tester) async {
      late SavedWorkspace workspace;
      await tester.runAsync(() async {
        final result = await fixture.workspaces.save(
          name: 'Header workspace',
          primary: fixture.first,
          members: [fixture.first, fixture.second],
        );
        workspace = result.workspace!;
        await fixture.editor.openPath(p.join(fixture.first.path, 'first.dart'));
      });
      await fixture.mount(
        tester,
        formFactor: AppFormFactor.tablet,
        workspace: workspace,
      );
      final state = tester.state(find.byType(FileExplorer));
      final openFile = fixture.editor.current;
      final more = find.byKey(const ValueKey('file-explorer-more'));
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('添加项目到工作区'), findsOneWidget);
      final member = find.byKey(
        ValueKey('file-explorer-workspace-member-${fixture.second.id}'),
      );
      expect(tester.getSize(member).height, 48);
      expect(find.byTooltip('新建文件夹'), findsNothing);
      await tester.tap(member);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('file-explorer-header-project-name')),
            )
            .data,
        fixture.second.name,
      );
      expect(fixture.store.lastBrowsedProjectId, fixture.second.id);
      expect(fixture.editor.current, same(openFile));
      expect(fixture.editor.project, same(fixture.first));
      expect(tester.state(find.byType(FileExplorer)), same(state));
      expect(find.textContaining('工作区 ·'), findsNothing);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: member, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(MenuItemButton, '添加项目到工作区'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(fixture.third.name), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.workspaces.byId(workspace.id)!.members, hasLength(2));
      expect(fixture.editor.current, same(openFile));
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '添加项目到工作区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fixture.third.name));
      await tester.tap(find.byKey(const ValueKey('workspace-add-confirm')));
      await _waitFor(
        tester,
        () => fixture.workspaces.byId(workspace.id)!.members.length == 3,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey('file-explorer-workspace-member-${fixture.third.id}'),
        ),
        findsOneWidget,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(fixture.editor.current, same(openFile));
      expect(tester.state(find.byType(FileExplorer)), same(state));
      expect(tester.takeException(), isNull);
    },
  );
}

class _Fixture {
  _Fixture(this.root, this.store, this.first, this.second, this.third)
    : editor = EditorController(project: first),
      settings = SettingsStore(
        storageFile: File(p.join(root.path, 'settings.json')),
      ),
      workspaces = WorkspaceStore(
        root: Directory(p.join(root.path, 'workspaces')),
      );

  final Directory root;
  final ProjectStore store;
  final Project first;
  final Project second;
  final Project third;
  final EditorController editor;
  final SettingsStore settings;
  final WorkspaceStore workspaces;
  final shell = LargeScreenController();

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'workbench_files_header_',
    );
    final store = ProjectStore(
      storageFile: File(p.join(root.path, 'projects.json')),
    );
    await store.load();
    for (final name in ['first', 'second', 'third']) {
      final directory = Directory(p.join(root.path, name));
      await directory.create();
      await File(
        p.join(directory.path, '$name.dart'),
      ).writeAsString('const value = 1;');
      await store.addExisting(directory.path);
    }
    final fixture = _Fixture(
      root,
      store,
      store.projects.singleWhere((project) => project.name == 'first'),
      store.projects.singleWhere((project) => project.name == 'second'),
      store.projects.singleWhere((project) => project.name == 'third'),
    );
    await fixture.workspaces.load();
    return fixture;
  }

  Future<void> mount(
    WidgetTester tester, {
    AppFormFactor formFactor = AppFormFactor.desktop,
    double width = 300,
    Brightness brightness = Brightness.light,
    SavedWorkspace? workspace,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      var drained = false;
      Future.wait([
        ProjectHistory.load(first.path),
        ProjectHistory.load(second.path),
        store.refresh(),
        workspaces.settle(),
      ]).then((_) => drained = true);
      await _waitFor(tester, () => drained);
      editor.dispose();
      settings.dispose();
      shell.dispose();
      store.dispose();
      workspaces.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    });
    shell.activateFiles(editor);
    shell.showFiles();
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkbenchTheme.from(
          ThemeData(colorSchemeSeed: Colors.indigo, brightness: brightness),
          formFactor: formFactor,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 180,
              child: LargeScreenScope(
                controller: shell,
                formFactor: formFactor,
                child: WorkbenchExplorer(
                  controller: shell,
                  projectName: first.name,
                  projects: const Text('Projects fixture'),
                  files: FileExplorer(
                    largeScreen: true,
                    project: first,
                    editor: editor,
                    store: store,
                    settings: settings,
                    workspace: workspace,
                    workspaceMembers: workspace == null
                        ? const []
                        : [first, second],
                    workspaceStore: workspaces,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitFor(tester, () => find.text('first.dart').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'Explorer IO did not finish');
}
