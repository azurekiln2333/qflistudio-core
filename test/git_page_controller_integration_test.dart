import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/git/git_backend.dart';
import 'package:qfli_studio_core/store/git_page_controller.dart';

void main() {
  late _Backend backend;
  late GitPageController controller;

  setUp(() {
    backend = _Backend();
    controller = GitPageController(
      backend: backend,
      identityStore: GitIdentityStore(
        initial: const GitIdentity(name: 'Author', email: 'ci@example.invalid'),
      ),
    );
  });

  tearDown(() async {
    await controller.close();
  });

  test('selected staging and index commit never invoke stageAll', () async {
    await controller.load();
    await controller.stage(const GitChange(path: '[literal].txt'));
    expect(backend.stagedPaths, ['[literal].txt']);
    expect(await controller.commit('Selected only'), isNull);
    expect(backend.commitCalls, 1);
    expect(backend.stageAllCalls, 0);
    expect(controller.isBusy, isFalse);
  });

  test(
    'a query owns the busy state and blocks a concurrent mutation',
    () async {
      await controller.load();
      backend.diffGate = Completer<GitDiffData>();
      final pending = controller.diff(
        const GitChange(path: 'file.txt'),
        area: GitChangeArea.worktree,
      );
      expect(controller.isBusy, isTrue);
      expect(await controller.stageAll(), isNotNull);
      expect(backend.stageAllCalls, 0);
      backend.diffGate!.complete(const GitDiffData(patch: '+new'));
      expect((await pending).value?.patch, '+new');
      expect(controller.isBusy, isFalse);
    },
  );

  test(
    'failed mutation refreshes partial repository state and keeps its error',
    () async {
      await controller.load();
      backend.failPull = true;
      final error = await controller.pullRebase();
      expect(error, contains('rebase stopped'));
      expect(controller.error, contains('rebase stopped'));
      expect(controller.state, 'rebase_merge');
      expect(controller.conflicts, ['file.txt']);
      expect(backend.snapshotCalls, 2);
      expect(controller.isBusy, isFalse);
      expect(
        controller.log.any((line) => line.text.contains('已完成拉取')),
        isFalse,
      );
    },
  );

  test(
    'closing suppresses stale results and waits for backend disposal',
    () async {
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);
      backend.diffGate = Completer<GitDiffData>();
      backend.disposeGate = Completer<void>();
      final pending = controller.diff(
        const GitChange(path: 'file.txt'),
        area: GitChangeArea.worktree,
      );
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      var closedAgain = false;
      final closingAgain = controller.close().then((_) => closedAgain = true);
      final afterClose = notifications;
      backend.diffGate!.complete(const GitDiffData(patch: '+stale'));
      expect((await pending).ok, isFalse);
      expect(notifications, afterClose);
      expect(closed, isFalse);
      expect(closedAgain, isFalse);
      backend.disposeGate!.complete();
      await closing;
      await closingAgain;
      expect(closed, isTrue);
      expect(closedAgain, isTrue);
      expect(backend.cancelCalls, greaterThanOrEqualTo(1));
      expect(backend.disposeCalls, 1);
    },
  );

  test(
    'cancelled network operation has no success log and clears busy state',
    () async {
      await controller.load();
      backend.fetchGate = Completer<void>();
      final pending = controller.fetch();
      expect(controller.isNetworkOperation, isTrue);
      controller.cancelNetwork();
      backend.fetchGate!.completeError(
        const GitOperationException('cancelled', kind: 'cancelled'),
      );
      expect(await pending, '已取消');
      expect(backend.cancelCalls, 1);
      expect(controller.isBusy, isFalse);
      expect(controller.isNetworkOperation, isFalse);
      expect(controller.log.any((line) => line.text == '已完成获取'), isFalse);
    },
  );
}

class _Backend implements GitBackend {
  GitSnapshot snapshotValue = const GitSnapshot(
    isRepository: true,
    branch: 'main',
  );
  int snapshotCalls = 0;
  int stageAllCalls = 0;
  int commitCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;
  List<String> stagedPaths = [];
  bool failPull = false;
  Completer<GitDiffData>? diffGate;
  Completer<void>? fetchGate;
  Completer<void>? disposeGate;

  @override
  String get root => '/ci/isolated-repository';
  @override
  GitBackendKind get kind => GitBackendKind.cli;
  @override
  Future<GitSnapshot> snapshot() async {
    snapshotCalls++;
    return snapshotValue;
  }

  @override
  Future<void> stage(List<String> paths) async => stagedPaths = List.of(paths);
  @override
  Future<void> stageAll() async => stageAllCalls++;
  @override
  Future<String> commit(String message, GitIdentity identity) async {
    commitCalls++;
    return '0123456789012345678901234567890123456789';
  }

  @override
  Future<GitDiffData> diff(String path, {required GitChangeArea area}) async =>
      diffGate == null ? const GitDiffData() : await diffGate!.future;
  @override
  Future<void> pullRebase() async {
    if (failPull) {
      snapshotValue = const GitSnapshot(
        isRepository: true,
        branch: 'main',
        state: 'rebase_merge',
        conflicts: ['file.txt'],
      );
      throw const GitOperationException('rebase stopped');
    }
  }

  @override
  Future<void> fetch({
    String remote = 'origin',
    GitCredentials? credentials,
  }) async {
    if (fetchGate != null) await fetchGate!.future;
  }

  @override
  void cancelNetwork() => cancelCalls++;
  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (disposeGate != null) await disposeGate!.future;
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> unstage(List<String> paths) async {}
  @override
  Future<List<GitCommitInfo>> history({int limit = 20}) async => [];
  @override
  Future<void> createBranch(String name) async {}
  @override
  Future<void> checkout(String name) async {}
  @override
  Future<GitMergeResult> merge(String ref, GitIdentity identity) async =>
      GitMergeResult.upToDate;
  @override
  Future<String> completeMerge(String message, GitIdentity identity) async =>
      'oid';
  @override
  Future<void> setRemote(String name, String url) async {}
  @override
  Future<void> push({
    String remote = 'origin',
    GitCredentials? credentials,
  }) async {}
}
