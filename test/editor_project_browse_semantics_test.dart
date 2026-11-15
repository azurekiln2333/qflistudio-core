import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

/// 目录选择器的两种语义：
/// - 普通项目里只临时更换浏览的树，不导航、不改编辑器项目。
/// - 工作区里只做「加入成员」，一次确认、直写、保留已有成员。
///
/// 这些用例都碰真实文件 I/O，所以不使用 `pumpAndSettle`
/// （会等真实 IO 而挂死），统一用 [_pumpUntil] 轮询。
void main() {
  late Directory root;
  late Project primary;
  late Project other;
  late Project outsider;
  late ProjectStore store;
  late SettingsStore settings;
  late AuthStore auth;
  late WorkspaceStore workspaceStore;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli_browse_semantics_');
    for (final name in ['primary', 'other', 'outsider']) {
      final dir = Directory(p.join(root.path, name))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync(name);
    }
    primary = Project.create(
      name: 'Primary',
      path: p.join(root.path, 'primary'),
    );
    other = Project.create(name: 'Other', path: p.join(root.path, 'other'));
    outsider = Project.create(
      name: 'Outsider',
      path: p.join(root.path, 'outsider'),
    );
    store = ProjectStore(storageFile: File(p.join(root.path, 'projects.json')));
    File(p.join(root.path, 'projects.json')).writeAsStringSync(
      jsonEncode({
        'projects': [
          for (final project in [primary, other, outsider]) project.toJson(),
        ],
      }),
    );
    await store.load();
    settings = SettingsStore();
    auth = AuthStore();
    workspaceStore = WorkspaceStore(root: Directory(p.join(root.path, 'ws')));
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // 句柄可能还没释放。
    }
  });

  Future<_RouteCounter> pumpApp(
    WidgetTester tester, {
    SavedWorkspace? workspace,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var drained = false;
      final pending = Future.wait([
        workspaceStore.settle(),
        for (final project in [primary, other, outsider])
          ProjectHistory.load(project.path),
      ]).then((_) => drained = true);
      await _pumpUntil(tester, () => drained, 'queued writes drain');
      await pending;
    });
    final counter = _RouteCounter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [counter],
        home: EditorPage(
          project: primary,
          auth: auth,
          store: store,
          settings: settings,
          workspace: workspace,
          workspaceMembers: workspace == null ? const [] : [primary],
          workspaceStore: workspaceStore,
          agentEnabled: false,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(FileExplorer).evaluate().isNotEmpty,
      'explorer mounts',
    );
    // 宽屏默认收起侧边栏，展开后标题栏里的选择器才可点。
    final open = find.byTooltip('打开文件树');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
      await _pumpUntil(
        tester,
        () => _picker.hitTestable().evaluate().isNotEmpty,
        'sidebar opens',
      );
    }
    return counter;
  }

  group('普通项目的目录选择器只是临时浏览', () {
    testWidgets('选另一个项目只换文件树，不导航、不改编辑器项目', (tester) async {
      final counter = await pumpApp(tester);
      final pushesBefore = counter.pushes;
      expect(pushesBefore, greaterThanOrEqualTo(1));

      await _browseProject(tester, other);

      expect(counter.pushes, pushesBefore, reason: '临时浏览不能推路由');
      expect(find.byType(EditorPage), findsOneWidget);
      // 编辑器页所属项目没变。
      expect(
        tester.widget<EditorPage>(find.byType(EditorPage)).project.id,
        primary.id,
      );
      // 只是把浏览目标记成另一个项目。
      expect(store.lastBrowsedProjectId, other.id);
      // 没有新增中间路由。
      expect(find.byType(FileExplorer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('工作区里的目录选择器只加入成员', () {
    testWidgets('非成员要经确认，取消后成员不变', (tester) async {
      final saved = (await tester.runAsync(
        () => workspaceStore.save(
          name: '示例工作区',
          members: [primary],
          primary: primary,
        ),
      ))!.workspace!;
      final counter = await pumpApp(tester, workspace: saved);
      final pushesBefore = counter.pushes;

      // 工作区模式点标题直接开多选，没有嵌套的第二层菜单。
      await tester.tap(_picker);
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
        'add projects dialog',
      );
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('取消').last);
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
        'dialog closes',
      );

      expect(counter.pushes, pushesBefore, reason: '不能导航走');
      // 已有成员原样保留。
      await _reloadWorkspaces(tester, workspaceStore);
      final current = workspaceStore.workspaces.firstWhere(
        (w) => w.id == saved.id,
      );
      expect(current.memberPaths.map(workspacePathKey), [
        workspacePathKey(primary.path),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('多选加入只新增成员，已有成员保留', (tester) async {
      final saved = (await tester.runAsync(
        () => workspaceStore.save(
          name: '新增工作区',
          members: [primary],
          primary: primary,
        ),
      ))!.workspace!;
      await pumpApp(tester, workspace: saved);

      await tester.tap(_picker);
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
        'add projects dialog',
      );

      // 已有成员固定勾选且不可取消。
      final existing = tester.widget<CheckboxListTile>(
        find.byKey(ValueKey('workspace-existing-${primary.id}')),
      );
      expect(existing.value, isTrue);
      expect(existing.onChanged, isNull);

      await tester.tap(find.byKey(ValueKey('workspace-add-${other.id}')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('workspace-add-${outsider.id}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-add-confirm')));
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
        'confirm closes the dialog',
      );

      await _pumpUntil(
        tester,
        () => workspaceStore.byId(saved.id)?.members.length == 3,
        'members persist',
      );
      await _reloadWorkspaces(tester, workspaceStore);
      final current = workspaceStore.workspaces.firstWhere(
        (w) => w.id == saved.id,
      );
      final paths = current.memberPaths.map(workspacePathKey).toSet();
      expect(paths, contains(workspacePathKey(primary.path)));
      expect(paths, contains(workspacePathKey(other.path)));
      expect(paths, contains(workspacePathKey(outsider.path)));
      expect(tester.takeException(), isNull);
    });
  });
}

Finder get _picker =>
    find.byKey(const ValueKey('file-explorer-project-picker'));

Future<void> _reloadWorkspaces(
  WidgetTester tester,
  WorkspaceStore store,
) async {
  // A refresh may wait for editor writes queued in the fake-time zone.
  // Pump that zone while allowing filesystem IO to complete in real time.
  var loaded = false;
  final pending = store.load(force: true).then((_) => loaded = true);
  await _pumpUntil(tester, () => loaded, 'workspace refresh');
  await pending;
}

/// 点标题栏选择器并选一个项目。工作区模式弹多选，普通模式弹菜单。
Future<void> _browseProject(WidgetTester tester, Project project) async {
  final entry = _picker.hitTestable();
  expect(entry, findsOneWidget, reason: '项目选择器应当可用');
  await tester.tap(entry);
  await _pumpUntil(
    tester,
    () => find.text(project.name).evaluate().isNotEmpty,
    'selector shows ${project.name}',
  );
  final item = find.text(project.name).last;
  await tester.ensureVisible(item);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(item);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 轮询等待真实 IO 完成。不用 `pumpAndSettle`：它等的是动画，不是文件系统。
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
  await tester.pump(const Duration(milliseconds: 200));
}

class _RouteCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 弹出菜单和对话框也是 route，但它们不是页面导航；
    // 只统计全屏页面路由。
    if (route is PageRoute || route is ModalRoute) {
      if (route is! PopupRoute) pushes++;
    }
    super.didPush(route, previousRoute);
  }
}
