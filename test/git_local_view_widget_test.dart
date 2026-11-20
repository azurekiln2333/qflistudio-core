import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/git/git_backend.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/git/git_local_view.dart';
import 'package:qfli_studio_core/pages/git/git_worktree_guard.dart';
import 'package:qfli_studio_core/pages/git_page.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

/// Widget-level regression for the visible Git integration.
///
/// These run only in cloud CI. They cover the three behaviours that broke
/// repeatedly in review: a usable mobile entry, remote refs that cannot be
/// checked out by tapping, and the dirty-buffer guard refusing a checkout.
void main() {
  Project project() => Project.create(
    name: 'Demo',
    path: '/ci/isolated/projects/Demo',
    language: 'dart',
    type: 'dart',
  );

  Future<void> pumpView(
    WidgetTester tester, {
    required GitBackend backend,
    GitWorktreeGuard? guard,
    GitWorktreeChanged? changed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitLocalRepositoryView(
            project: project(),
            backend: backend,
            beforeWorktreeChange: guard,
            onWorktreeChanged: changed,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a local project renders the real Git view, not a refusal', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: GitPage(project: project(), auth: AuthStore(), backend: backend),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-local-unsupported')), findsNothing);
    expect(find.byKey(const ValueKey('git-repo-header')), findsOneWidget);
    expect(find.text('Demo'), findsWidgets);
    expect(find.byKey(const ValueKey('git-stage-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-commit')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-branches')), findsOneWidget);
  });

  testWidgets('a remote-only branch cannot be selected for checkout', (
    tester,
  ) async {
    var checkoutCalls = 0;
    final backend = _FakeBackend(onCheckout: (_) => checkoutCalls++);
    await pumpView(tester, backend: backend);

    await tester.tap(find.byKey(const ValueKey('git-branches')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-branches-dialog')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('git-remote-branch-note')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('git-remote-branch-origin/main')),
    );
    await tester.pumpAndSettle();

    // The dialog stays open: a remote ref is a merge target, not a checkout.
    expect(find.byKey(const ValueKey('git-branches-dialog')), findsOneWidget);
    expect(checkoutCalls, 0);

    await tester.tap(find.byKey(const ValueKey('git-branch-main')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-branches-dialog')), findsNothing);
  });

  testWidgets('a refused dirty-buffer guard stops the checkout entirely', (
    tester,
  ) async {
    var checkoutCalls = 0;
    var guardCalls = 0;
    final backend = _FakeBackend(onCheckout: (_) => checkoutCalls++);
    await pumpView(
      tester,
      backend: backend,
      guard: (request) async {
        guardCalls++;
        expect(request.operation, contains('dev'));
        return false;
      },
    );

    await tester.tap(find.byKey(const ValueKey('git-branches')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('git-branch-dev')));
    await tester.pumpAndSettle();

    expect(guardCalls, 1);
    expect(checkoutCalls, 0);
    expect(backend.stageAllCalls, 0);
  });

  testWidgets('an allowed guard refreshes clean buffers after a switch', (
    tester,
  ) async {
    var checkoutCalls = 0;
    var refreshed = 0;
    bool? sawForced;
    final backend = _FakeBackend(onCheckout: (_) => checkoutCalls++);
    await pumpView(
      tester,
      backend: backend,
      guard: (_) async => true,
      changed: (root, {bool diskMayHaveChanged = false}) async {
        refreshed++;
        sawForced = diskMayHaveChanged;
      },
    );

    await tester.tap(find.byKey(const ValueKey('git-branches')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('git-branch-dev')));
    await tester.pumpAndSettle();

    expect(checkoutCalls, 1);
    expect(refreshed, 1);
    expect(sawForced, isFalse);
  });

  testWidgets('complete-merge is offered only for a real merge state', (
    tester,
  ) async {
    final backend = _FakeBackend(
      value: const GitSnapshot(
        isRepository: true,
        branch: 'main',
        state: 'rebase_merge',
        conflicts: ['file.txt'],
      ),
    );
    await pumpView(tester, backend: backend);

    expect(
      find.byKey(const ValueKey('git-interrupted-operation')),
      findsOneWidget,
    );
    expect(find.text('变基进行中'), findsOneWidget);
    expect(find.text('合并进行中'), findsNothing);
    expect(find.byKey(const ValueKey('git-complete-merge')), findsNothing);
  });

  testWidgets('a real merge state offers completion', (tester) async {
    final backend = _FakeBackend(
      value: const GitSnapshot(
        isRepository: true,
        branch: 'main',
        state: 'merge',
        conflicts: ['file.txt'],
      ),
    );
    await pumpView(tester, backend: backend);

    expect(find.byKey(const ValueKey('git-conflict-card')), findsOneWidget);
    // Conflicts are unresolved, so completion stays disabled until staged.
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('git-complete-merge')),
    );
    expect(button.onPressed, isNull);
  });
}

class _FakeBackend implements GitBackend {
  _FakeBackend({this.value = _defaultSnapshot, this.onCheckout});

  static const GitSnapshot _defaultSnapshot = GitSnapshot(
    isRepository: true,
    branch: 'main',
    oid: '0123456',
    branches: [
      GitBranchInfo(name: 'main', current: true),
      GitBranchInfo(name: 'dev'),
      GitBranchInfo(name: 'origin/main', remote: true),
    ],
  );

  final GitSnapshot value;
  final void Function(String name)? onCheckout;
  int stageAllCalls = 0;

  @override
  String get root => '/ci/isolated/projects/Demo';

  @override
  GitBackendKind get kind => GitBackendKind.native;

  @override
  Future<GitSnapshot> snapshot() async => value;

  @override
  Future<void> checkout(String name) async => onCheckout?.call(name);

  @override
  Future<void> stageAll() async => stageAllCalls++;

  @override
  Future<void> init() async {}

  @override
  Future<void> stage(List<String> paths) async {}

  @override
  Future<void> unstage(List<String> paths) async {}

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
