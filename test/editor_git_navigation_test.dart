import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/git/git_backend.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/git/git_worktree_guard.dart';
import 'package:qfli_studio_core/pages/git_page.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

/// The editor is the only place that knows which project owns the active
/// document in a multi-root workspace. These cases drive the real navigation:
///
/// - Git opens for the active *foreign* owner, not the primary project.
/// - A dirty buffer in that owner makes the worktree guard refuse, the
///   checkout never reaches the backend, and the unsaved text survives.
///
/// Real file I/O is involved, so waits pair `tester.pump` with `runAsync`
/// delays, the same pattern as `workspace_editor_session_test.dart`.
void main() {
  late Directory root;
  late Project primary;
  late Project secondary;
  late ProjectStore store;
  late SettingsStore settings;
  late AuthStore auth;
  late WorkspaceStore workspaceStore;
  late List<Project> factoryCalls;
  late _FakeBackend backend;

  String secondaryFile() => p.join(secondary.path, 'notes.txt');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli_editor_git_');
    for (final name in ['primary', 'secondary']) {
      final dir = Directory(p.join(root.path, name))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync('$name text\n');
    }
    primary = Project.create(
      name: 'Primary',
      path: p.join(root.path, 'primary'),
    );
    secondary = Project.create(
      name: 'Secondary',
      path: p.join(root.path, 'secondary'),
    );
    store = ProjectStore(storageFile: File(p.join(root.path, 'projects.json')));
    File(p.join(root.path, 'projects.json')).writeAsStringSync(
      jsonEncode({
        'projects': [primary.toJson(), secondary.toJson()],
      }),
    );
    await store.load();
    settings = SettingsStore();
    auth = AuthStore();
    workspaceStore = WorkspaceStore(root: Directory(p.join(root.path, 'ws')));
    factoryCalls = [];
    backend = _FakeBackend(root: secondary.path);
  });

  tearDown(() async {
    await workspaceStore.settle();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle during teardown.
    }
  });

  /// Pumps until [condition] holds, letting real I/O progress in between.
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition,
    String reason,
  ) async {
    for (var attempt = 0; attempt < 250; attempt++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    fail('timed out waiting for $reason');
  }

  Future<void> tapExplorerRow(WidgetTester tester, String path) async {
    final row = find.byKey(ValueKey('file-row-$path'));
    if (row.evaluate().isEmpty) {
      final rootRow = find.byKey(ValueKey('workspace-root-${secondary.path}'));
      await tester.tap(rootRow);
      await tester.pump(const Duration(milliseconds: 20));
      // The tree loads children asynchronously, so wait for the row instead of
      // assuming one frame was enough.
      await waitFor(
        tester,
        () => find.byKey(ValueKey('file-row-$path')).evaluate().isNotEmpty,
        'the secondary tree expands to list its file',
      );
    }
    expect(row, findsOneWidget, reason: 'file row must be listed');
    await tester.tap(row);
  }

  /// Opens the secondary project's file through the explorer and returns the
  /// live [EditorController] once that document is actually active.
  Future<EditorController> openSecondaryDocument(WidgetTester tester) async {
    final target = secondaryFile();
    await tapExplorerRow(tester, target);
    late EditorController editor;
    await waitFor(tester, () {
      final bars = find.byType(EditorProblemsBar);
      if (bars.evaluate().isEmpty) return false;
      editor = tester.widget<EditorProblemsBar>(bars.first).analysis.editor;
      return editor.current != null &&
          p.equals(editor.current!.path, target) &&
          p.equals(editor.current!.projectRootPath, secondary.path);
    }, 'the secondary document becomes active');
    return editor;
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    final saved = (await tester.runAsync(
      () => workspaceStore.save(
        name: 'Git workspace',
        members: [primary, secondary],
        primary: primary,
      ),
    ))!.workspace!;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: primary,
          auth: auth,
          store: store,
          settings: settings,
          workspace: saved,
          workspaceMembers: [primary, secondary],
          workspaceStore: workspaceStore,
          agentEnabled: false,
          gitBackendFactory: (project) {
            factoryCalls.add(project);
            return backend;
          },
        ),
      ),
    );
    final open = find.byTooltip('打开文件树');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await waitFor(
      tester,
      () => find.byType(FileExplorer).evaluate().isNotEmpty,
      'explorer mounts',
    );
    await waitFor(
      tester,
      () => find
          .byKey(ValueKey('workspace-root-${secondary.path}'))
          .evaluate()
          .isNotEmpty,
      'workspace roots are listed',
    );
  }

  Future<GitPage> openGitPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('quick-git')));
    await waitFor(
      tester,
      () => find.byType(GitPage).evaluate().isNotEmpty,
      'Git page opens',
    );
    return tester.widget<GitPage>(find.byType(GitPage));
  }

  testWidgets('Git opens for the active foreign owner, not the primary', (
    tester,
  ) async {
    await pumpEditor(tester);
    final editor = await openSecondaryDocument(tester);
    expect(editor.current!.ownerProjectName, secondary.name);

    final page = await openGitPage(tester);

    expect(page.project.id, secondary.id);
    expect(page.project.path, secondary.path);
    expect(factoryCalls, hasLength(1));
    expect(factoryCalls.single.id, secondary.id);
    expect(backend.root, secondary.path);
    expect(page.beforeWorktreeChange, isNotNull);
    expect(page.onWorktreeChanged, isNotNull);
  });

  testWidgets('a dirty foreign buffer makes the guard refuse and keeps text', (
    tester,
  ) async {
    await pumpEditor(tester);
    final editor = await openSecondaryDocument(tester);

    final document = editor.current!;
    document.controller.text = 'unsaved secondary edit';
    await tester.pump(const Duration(milliseconds: 20));
    expect(document.dirty, isTrue);

    final page = await openGitPage(tester);
    final guard = page.beforeWorktreeChange!;
    var allowed = true;
    // Drive the real editor hook against the dirty owner root.
    final pending = guard(
      GitWorktreeChangeRequest(root: secondary.path, operation: '切换到 dev'),
    ).then((value) => allowed = value);
    await waitFor(
      tester,
      () => find
          .byKey(const ValueKey('editor-git-dirty-guard'))
          .evaluate()
          .isNotEmpty,
      'the dirty-buffer dialog appears',
    );

    await tester.tap(find.byKey(const ValueKey('editor-git-dirty-cancel')));
    await waitFor(tester, () {
      return find
          .byKey(const ValueKey('editor-git-dirty-guard'))
          .evaluate()
          .isEmpty;
    }, 'the dirty-buffer dialog closes');
    await tester.runAsync(() => pending);

    expect(allowed, isFalse, reason: 'a refused guard cancels the operation');
    expect(backend.checkoutCalls, 0);
    // The refused operation never discarded the unsaved text.
    expect(document.dirty, isTrue);
    expect(document.controller.text, 'unsaved secondary edit');
    expect(
      File(secondaryFile()).readAsStringSync(),
      'secondary text\n',
      reason: 'the disk copy is untouched',
    );
  });
}

class _FakeBackend implements GitBackend {
  _FakeBackend({required this.root});

  @override
  final String root;

  int checkoutCalls = 0;

  @override
  GitBackendKind get kind => GitBackendKind.native;

  @override
  Future<GitSnapshot> snapshot() async => const GitSnapshot(
    isRepository: true,
    branch: 'main',
    oid: '0123456',
    branches: [GitBranchInfo(name: 'main', current: true)],
  );

  @override
  Future<void> checkout(String name) async => checkoutCalls++;

  @override
  Future<void> init() async {}

  @override
  Future<void> stage(List<String> paths) async {}

  @override
  Future<void> unstage(List<String> paths) async {}

  @override
  Future<void> stageAll() async {}

  @override
  Future<GitDiffData> diff(String path, {required GitChangeArea area}) async =>
      const GitDiffData();

  @override
  Future<List<GitCommitInfo>> history({int limit = 20}) async => [];

  @override
  Future<String> commit(String message, GitIdentity identity) async => 'oid';

  @override
  Future<void> createBranch(String name) async {}

  @override
  Future<GitMergeResult> merge(String ref, GitIdentity identity) async =>
      GitMergeResult.upToDate;

  @override
  Future<String> completeMerge(String message, GitIdentity identity) async =>
      'oid';

  @override
  Future<void> setRemote(String name, String url) async {}

  @override
  Future<void> fetch({
    String remote = 'origin',
    GitCredentials? credentials,
  }) async {}

  @override
  Future<void> push({
    String remote = 'origin',
    GitCredentials? credentials,
  }) async {}

  @override
  Future<void> pullRebase() async {}

  @override
  void cancelNetwork() {}

  @override
  Future<void> dispose() async {}
}
