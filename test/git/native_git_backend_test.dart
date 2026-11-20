import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/git/git_backend.dart';
import 'package:qfli_studio_core/git/native_git_backend.dart';

void main() {
  group('NativeGitBackend.snapshot', () {
    test('maps combined status flags, branches and redacted remotes', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..headValue = const NativeHeadData(
          branch: 'main',
          oid: 'abc123',
          state: 'merge',
        )
        ..statusValue = const <NativeStatusData>[
          NativeStatusData('both.txt', (1 << 0) | (1 << 8)),
          NativeStatusData('staged.txt', 1 << 1),
          NativeStatusData('worktree.txt', 1 << 9),
          NativeStatusData('new.txt', 1 << 7),
          NativeStatusData('conflict.txt', 1 << 15),
        ]
        ..branchesValue = const <NativeBranchData>[
          NativeBranchData(
            name: 'main',
            current: true,
            upstream: 'origin/main',
          ),
          NativeBranchData(name: 'origin/main', remote: true),
          NativeBranchData(name: 'origin/HEAD', remote: true),
        ]
        ..remotesValue = const <NativeRemoteData>[
          NativeRemoteData(
            name: 'origin',
            url: 'https://user:secret@example.com/team/repo.git',
          ),
        ];
      final api = _FakeApi(repository);
      final backend = NativeGitBackend(directory.path, api: api);

      final snapshot = await backend.snapshot();

      expect(api.initializeCalls, 1);
      expect(snapshot.isRepository, isTrue);
      expect(snapshot.branch, 'main');
      expect(snapshot.oid, 'abc123');
      expect(snapshot.state, 'merge');
      expect(snapshot.changes, hasLength(5));
      expect(
        snapshot.changes
            .singleWhere((change) => change.path == 'both.txt')
            .staged,
        isTrue,
      );
      expect(
        snapshot.changes
            .singleWhere((change) => change.path == 'both.txt')
            .unstaged,
        isTrue,
      );
      expect(
        snapshot.changes
            .singleWhere((change) => change.path == 'worktree.txt')
            .unstaged,
        isTrue,
      );
      expect(
        snapshot.changes
            .singleWhere((change) => change.path == 'new.txt')
            .untracked,
        isTrue,
      );
      expect(
        snapshot.changes
            .singleWhere((change) => change.path == 'new.txt')
            .unstaged,
        isFalse,
      );
      expect(
        snapshot.changes
            .singleWhere((change) => change.path == 'conflict.txt')
            .conflict,
        isTrue,
      );
      expect(snapshot.conflicts, <String>['conflict.txt']);
      expect(snapshot.branches.map((branch) => branch.name), <String>[
        'main',
        'origin/main',
      ]);
      expect(snapshot.branches.first.upstream, 'origin/main');
      expect(snapshot.remotes.single.url, isNot(contains('secret')));
      expect(snapshot.remotes.single.url, contains('[redacted]@'));
    });

    test('returns a non-repository snapshot without touching native', () async {
      final directory = _plainDirectory();
      final repository = _FakeRepository();
      final api = _FakeApi(repository);
      final backend = NativeGitBackend(directory.path, api: api);

      final snapshot = await backend.snapshot();

      expect(snapshot.isRepository, isFalse);
      expect(api.initializeCalls, 0);
      expect(repository.statusCalls, 0);
    });

    test('keeps an unborn branch but drops an empty oid', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..headValue = const NativeHeadData(branch: 'main', oid: null);
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      final snapshot = await backend.snapshot();

      expect(snapshot.isRepository, isTrue);
      expect(snapshot.branch, 'main');
      expect(snapshot.oid, isNull);
    });

    test('normalizes a detached HEAD to a null branch', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..headValue = const NativeHeadData(branch: null, oid: 'abc');
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      final snapshot = await backend.snapshot();

      expect(snapshot.branch, isNull);
      expect(snapshot.oid, 'abc');
    });

    test('redacts credentials from unexpected native failures', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..statusError = Exception(
          'cannot read https://alice:supersecret@example.com/repo',
        );
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      await expectLater(
        backend.snapshot(),
        throwsA(
          isA<GitOperationException>()
              .having(
                (error) => error.message,
                'message',
                isNot(contains('supersecret')),
              )
              .having(
                (error) => error.message,
                'message',
                contains('[redacted]@'),
              ),
        ),
      );
    });
  });

  group('NativeGitBackend validation', () {
    test('rejects invalid identity and message before native work', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository();
      final api = _FakeApi(repository);
      final backend = NativeGitBackend(directory.path, api: api);
      const valid = GitIdentity(name: 'Ada', email: 'ada@example.com');

      await expectLater(
        backend.commit('   ', valid),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'invalid',
          ),
        ),
      );
      await expectLater(
        backend.commit(
          'message',
          const GitIdentity(name: 'Ada', email: 'not-an-email'),
        ),
        throwsA(isA<GitOperationException>()),
      );
      expect(repository.commitCalls, 0);
      expect(api.initializeCalls, 0);
    });

    test('passes exact identity and message to the native commit', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()..commitOid = 'new-oid';
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      final oid = await backend.commit(
        '提交信息\n\n正文',
        const GitIdentity(name: 'Ada', email: 'ada@example.com'),
      );

      expect(oid, 'new-oid');
      expect(repository.lastCommitMessage, '提交信息\n\n正文');
      expect(repository.lastCommitName, 'Ada');
      expect(repository.lastCommitEmail, 'ada@example.com');
    });

    test('rejects traversal, absolute and backslash paths', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository();
      final api = _FakeApi(repository);
      final backend = NativeGitBackend(directory.path, api: api);

      for (final path in <String>['../escape', '/abs', r'dir\file', '.']) {
        await expectLater(
          backend.stage(<String>[path]),
          throwsA(
            isA<GitOperationException>().having(
              (error) => error.kind,
              'kind',
              'invalid',
            ),
          ),
        );
      }
      expect(repository.stageCalls, 0);
      expect(api.initializeCalls, 0);
    });

    test('passes exact Unicode paths to the native index', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository();
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      await backend.stage(<String>['目录/文件 name.txt']);
      await backend.unstage(<String>['目录/文件 name.txt']);

      expect(repository.stagedPaths, <String>['目录/文件 name.txt']);
      expect(repository.unstagedPaths, <String>['目录/文件 name.txt']);
    });

    test('rejects remote URLs with embedded credentials', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository();
      final api = _FakeApi(repository);
      final backend = NativeGitBackend(directory.path, api: api);

      await expectLater(
        backend.setRemote(
          'origin',
          'https://user:token@example.com/team/repo.git',
        ),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'invalid',
          ),
        ),
      );
      expect(repository.setRemoteCalls, 0);
      expect(api.initializeCalls, 0);
    });
  });

  group('NativeGitBackend network operations', () {
    test('push uses an explicit current-branch refspec', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..headValue = const NativeHeadData(branch: 'feature/x', oid: 'abc');
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      await backend.push(
        credentials: const GitCredentials(username: 'ada', token: 'secret'),
      );

      expect(
        repository.lastPushRefspec,
        'refs/heads/feature/x:refs/heads/feature/x',
      );
      expect(repository.lastPushUsername, 'ada');
      expect(repository.lastPushToken, 'secret');
      expect(repository.lastPushCancel?.disposed, isTrue);
    });

    test('push fails clearly for detached and unborn HEAD', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..headValue = const NativeHeadData(branch: null, oid: 'abc');
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      await expectLater(
        backend.push(),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.message,
            'message',
            contains('请先提交并切换到本地分支'),
          ),
        ),
      );
      expect(repository.pushCalls, 0);

      repository.headValue = const NativeHeadData(branch: 'main', oid: null);
      await expectLater(backend.push(), throwsA(isA<GitOperationException>()));
      expect(repository.pushCalls, 0);
    });

    test(
      'cancels the active native token and disposes it after completion',
      () async {
        final directory = _repositoryDirectory();
        final repository = _FakeRepository()..fetchGate = Completer<void>();
        final backend = NativeGitBackend(
          directory.path,
          api: _FakeApi(repository),
        );

        final pending = backend.fetch();
        await repository.fetchStarted.future;
        final cancel = repository.lastFetchCancel!;

        backend.cancelNetwork();
        expect(cancel.cancelCalls, 1);
        expect(cancel.disposed, isFalse);

        repository.fetchGate!.complete();
        await pending;
        expect(cancel.disposed, isTrue);
      },
    );

    test('dispose waits for an in-flight fetch', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()..fetchGate = Completer<void>();
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      final pending = backend.fetch();
      await repository.fetchStarted.future;
      var disposed = false;
      final disposing = backend.dispose().then((_) => disposed = true);

      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);

      repository.fetchGate!.complete();
      await pending;
      await disposing;
      expect(disposed, isTrue);
      await expectLater(
        backend.fetch(),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'cancelled',
          ),
        ),
      );
    });

    test('offline policy blocks fetch before native initialization', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository();
      final api = _FakeApi(repository);
      final backend = NativeGitBackend(
        directory.path,
        api: api,
        isOffline: () => true,
      );

      await expectLater(
        backend.fetch(),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'offline',
          ),
        ),
      );
      expect(api.initializeCalls, 0);
      expect(repository.fetchCalls, 0);
    });

    test('pullRebase reports an explicit unsupported failure', () async {
      final directory = _repositoryDirectory();
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(_FakeRepository()),
      );

      await expectLater(
        backend.pullRebase(),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'unsupported',
          ),
        ),
      );
    });
  });

  group('NativeGitBackend clone', () {
    test('bridges cancellation to the native token and releases it', () async {
      final api = _FakeApi(_FakeRepository());
      final cancellation = GitCloneCancellation();
      final future = NativeGitBackend.cloneRepository(
        url: 'https://example.com/team/repo.git',
        path: p.join(_plainDirectory().path, 'clone'),
        cancellation: cancellation,
        api: api,
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'cancelled',
          ),
        ),
      );

      await api.cloneStarted.future;
      final cancel = api.cloneCancel!;
      cancellation.cancel();
      expect(cancel.cancelCalls, 1);

      api.cloneGate!.complete();
      await expectation;
      expect(cancel.disposed, isTrue);

      cancellation.cancel();
      expect(cancel.cancelCalls, 1);
      cancellation.dispose();
    });

    test('offline policy blocks clone before plugin initialization', () async {
      final api = _FakeApi(_FakeRepository());
      await expectLater(
        NativeGitBackend.cloneRepository(
          url: 'https://example.com/team/repo.git',
          path: p.join(_plainDirectory().path, 'clone'),
          api: api,
          isOffline: () => true,
        ),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'offline',
          ),
        ),
      );
      expect(api.initializeCalls, 0);
      expect(api.cloneCalls, 0);
    });

    test('redacts credentials from clone transport errors', () async {
      final api = _FakeApi(_FakeRepository())
        ..cloneError = Exception(
          'connect failed https://alice:supersecret@example.com/repo.git',
        );
      final path = p.join(_plainDirectory().path, 'clone');

      await expectLater(
        NativeGitBackend.cloneRepository(
          url: 'https://example.com/team/repo.git',
          path: path,
          api: api,
        ),
        throwsA(
          isA<GitOperationException>()
              .having(
                (error) => error.message,
                'message',
                isNot(contains('supersecret')),
              )
              .having(
                (error) => error.message,
                'message',
                contains('[redacted]@'),
              ),
        ),
      );
      expect(api.cloneCancel?.disposed, isTrue);
    });

    test('a completed clone disposes the cancel token', () async {
      final api = _FakeApi(_FakeRepository());
      final path = p.join(_plainDirectory().path, 'clone');

      await NativeGitBackend.cloneRepository(
        url: 'https://example.com/team/repo.git',
        path: path,
        api: api,
      );

      expect(api.cloneCalls, 1);
      expect(api.cloneCancel?.disposed, isTrue);
    });
  });

  group('NativeGitBackend reads and serialization', () {
    test('diff selects index and history clamps its bound', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..diffValue = const NativeDiffData(
          patch: 'patch',
          binary: false,
          truncated: true,
        )
        ..logValue = <NativeCommitData>[
          NativeCommitData(
            oid: 'abc',
            message: 'one',
            authorName: 'Ada',
            authorEmail: 'ada@example.com',
            time: DateTime.utc(2026, 1, 2),
          ),
        ];
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      final diff = await backend.diff('目录/文件.txt', area: GitChangeArea.staged);
      final history = await backend.history(limit: 500);

      expect(diff.patch, 'patch');
      expect(diff.truncated, isTrue);
      expect(repository.lastDiffPath, '目录/文件.txt');
      expect(repository.lastDiffStaged, isTrue);
      expect(repository.lastLogLimit, 200);
      expect(history.single.message, 'one');
    });

    test('history is empty for an unborn HEAD without a native log', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..headValue = const NativeHeadData(branch: 'main', oid: null);
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      expect(await backend.history(), isEmpty);
      expect(repository.logCalls, 0);
    });

    test(
      'merges map native results and completeMerge keeps identity',
      () async {
        final directory = _repositoryDirectory();
        final repository = _FakeRepository()
          ..mergeResult = 3
          ..commitMergeOid = 'merge-oid';
        final backend = NativeGitBackend(
          directory.path,
          api: _FakeApi(repository),
        );
        const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');

        expect(
          await backend.merge('origin/main', identity),
          GitMergeResult.conflicts,
        );
        expect(repository.lastMergeRef, 'origin/main');
        expect(await backend.completeMerge('合并', identity), 'merge-oid');
        expect(repository.lastMergeCommitMessage, '合并');
        expect(repository.lastMergeCommitEmail, 'ada@example.com');
      },
    );

    test('serializes mutations across instances of the same root', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()..commitGate = Completer<void>();
      final first = NativeGitBackend(directory.path, api: _FakeApi(repository));
      final second = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );
      const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');

      final a = first.commit('one', identity);
      final b = second.commit('two', identity);
      await repository.commitStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(repository.commitOrder, <String>['one']);

      repository.commitGate!.complete();
      await Future.wait(<Future<String>>[a, b]);
      expect(repository.commitOrder, <String>['one', 'two']);
    });
  });

  group('NativeGitBackend nested project roots', () {
    test('refuses a snapshot below another worktree', () async {
      final outer = _repositoryDirectory();
      final nested = Directory(p.join(outer.path, 'sub'))..createSync();
      final repository = _FakeRepository();
      final backend = NativeGitBackend(nested.path, api: _FakeApi(repository));

      await expectLater(
        backend.snapshot(),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'invalid',
          ),
        ),
      );
      expect(repository.statusCalls, 0);
    });

    test('refuses init below another worktree before native work', () async {
      final outer = _repositoryDirectory();
      final nested = Directory(p.join(outer.path, 'sub'))..createSync();
      final api = _FakeApi(_FakeRepository());
      final backend = NativeGitBackend(nested.path, api: api);

      await expectLater(backend.init(), throwsA(isA<GitOperationException>()));
      expect(api.initCalls, 0);
      expect(api.initializeCalls, 0);
      expect(Directory(p.join(nested.path, '.git')).existsSync(), isFalse);
    });

    test(
      'refuses index, history and remote work below another worktree',
      () async {
        final outer = _repositoryDirectory();
        final nested = Directory(p.join(outer.path, 'sub'))..createSync();
        final repository = _FakeRepository();
        final backend = NativeGitBackend(
          nested.path,
          api: _FakeApi(repository),
        );
        const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');

        final mutations = <Future<void> Function()>[
          () => backend.stage(<String>['a.dart']),
          () => backend.unstage(<String>['a.dart']),
          () => backend.stageAll(),
          () => backend.diff('a.dart', area: GitChangeArea.worktree),
          () => backend.commit('msg', identity),
          () => backend.merge('main', identity),
          () => backend.setRemote('origin', 'https://example.com/a.git'),
        ];
        for (final mutation in mutations) {
          await expectLater(mutation(), throwsA(isA<GitOperationException>()));
        }
        await expectLater(
          backend.history(),
          throwsA(isA<GitOperationException>()),
        );
        expect(repository.stageCalls, 0);
        expect(repository.commitCalls, 0);
        expect(repository.setRemoteCalls, 0);
      },
    );
  });

  group('NativeGitBackend network policy', () {
    test(
      'refuses fetch when the product turned offline while queueing',
      () async {
        final directory = _repositoryDirectory();
        final repository = _FakeRepository();
        final blockerRepository = _FakeRepository()
          ..commitGate = Completer<void>();
        const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');

        final blocker = NativeGitBackend(
          directory.path,
          api: _FakeApi(blockerRepository),
        );
        final held = blocker.commit('block', identity);
        var offline = false;
        final gated = NativeGitBackend(
          directory.path,
          api: _FakeApi(repository),
          isOffline: () => offline,
        );
        final fetch = gated.fetch();
        offline = true;
        blockerRepository.commitGate!.complete();
        await Future.wait(<Future<Object?>>[
          held,
          fetch.catchError((Object error) => error),
        ]);

        await expectLater(
          fetch,
          throwsA(
            isA<GitOperationException>().having(
              (error) => error.kind,
              'kind',
              'offline',
            ),
          ),
        );
        expect(repository.fetchCalls, 0);
      },
    );

    test('a cancelled request does not cancel the next one', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository();
      final blockerRepository = _FakeRepository()
        ..commitGate = Completer<void>();
      const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');

      final first = NativeGitBackend(directory.path, api: _FakeApi(repository));
      final held = first.fetch();
      first.cancelNetwork();
      await Future.wait(<Future<Object?>>[
        held.catchError((Object error) => error),
      ]);
      expect(repository.fetchCalls, 1);

      final blocker = NativeGitBackend(
        directory.path,
        api: _FakeApi(blockerRepository),
      );
      final second = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );
      final gate = blocker.commit('block', identity);
      final pending = second.fetch();
      blockerRepository.commitGate!.complete();
      await gate;
      await pending;

      expect(repository.lastFetchCancel?.cancelCalls, 0);
    });
  });

  group('NativeGitBackend branch checkout', () {
    test('refuses a remote-only branch without checkout', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..branchesValue = const <NativeBranchData>[
          NativeBranchData(name: 'origin/main', remote: true),
        ];
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      await expectLater(
        backend.checkout('origin/main'),
        throwsA(
          isA<GitOperationException>().having(
            (error) => error.kind,
            'kind',
            'invalid',
          ),
        ),
      );
      expect(repository.checkoutCalls, 0);
    });

    test('checks out a local branch', () async {
      final directory = _repositoryDirectory();
      final repository = _FakeRepository()
        ..branchesValue = const <NativeBranchData>[
          NativeBranchData(name: 'main', current: true),
          NativeBranchData(name: 'feature', upstream: 'origin/feature'),
        ];
      final backend = NativeGitBackend(
        directory.path,
        api: _FakeApi(repository),
      );

      await backend.checkout('feature');
      expect(repository.lastCheckout, 'feature');
    });
  });
}

Directory _repositoryDirectory() {
  final directory = _plainDirectory();
  Directory(p.join(directory.path, '.git')).createSync();
  return directory;
}

Directory _plainDirectory() {
  final directory = Directory.systemTemp.createTempSync('qfli_native_git_');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

class _FakeApi implements NativeGitApi {
  _FakeApi(this.repository);

  final _FakeRepository repository;
  int initializeCalls = 0;
  int initCalls = 0;
  int cloneCalls = 0;
  Completer<void>? cloneGate;
  final Completer<void> cloneStarted = Completer<void>();
  _FakeCancel? cloneCancel;
  Object? cloneError;

  @override
  Future<void> ensureInitialized() async {
    initializeCalls++;
  }

  @override
  NativeRepository open(String root) => repository;

  @override
  Future<NativeRepository> init(String root) async {
    initCalls++;
    return repository;
  }

  @override
  NativeCancelHandle createCancel() => _FakeCancel();

  @override
  Future<void> clone({
    required String url,
    required String path,
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  }) async {
    cloneCalls++;
    cloneCancel = cancel as _FakeCancel?;
    if (!cloneStarted.isCompleted) cloneStarted.complete();
    final gate = cloneGate;
    if (gate != null) await gate.future;
    final failure = cloneError;
    if (failure != null) throw failure;
  }
}

class _FakeCancel implements NativeCancelHandle {
  int cancelCalls = 0;
  bool disposed = false;

  @override
  void cancel() => cancelCalls++;

  @override
  void dispose() => disposed = true;
}

class _FakeRepository implements NativeRepository {
  NativeHeadData headValue = const NativeHeadData(branch: 'main', oid: 'abc');
  List<NativeStatusData> statusValue = const <NativeStatusData>[];
  List<NativeBranchData> branchesValue = const <NativeBranchData>[];
  List<NativeRemoteData> remotesValue = const <NativeRemoteData>[];
  NativeDiffData diffValue = const NativeDiffData();
  List<NativeCommitData> logValue = const <NativeCommitData>[];
  int mergeResult = 0;
  String commitOid = 'abc';
  String commitMergeOid = 'merge';
  Object? statusError;

  int statusCalls = 0;
  int commitCalls = 0;
  int pushCalls = 0;
  int fetchCalls = 0;
  int logCalls = 0;
  int stageCalls = 0;
  int checkoutCalls = 0;
  String? lastCheckout;
  int setRemoteCalls = 0;
  List<String> stagedPaths = const <String>[];
  List<String> unstagedPaths = const <String>[];
  String? lastCommitMessage;
  String? lastCommitName;
  String? lastCommitEmail;
  String? lastPushRefspec;
  String? lastPushUsername;
  String? lastPushToken;
  _FakeCancel? lastPushCancel;
  String? lastFetchRemote;
  _FakeCancel? lastFetchCancel;
  String? lastDiffPath;
  bool? lastDiffStaged;
  int? lastLogLimit;
  String? lastMergeRef;
  String? lastMergeCommitMessage;
  String? lastMergeCommitEmail;
  List<String>? _staged;
  final List<String> commitOrder = <String>[];
  Completer<void>? commitGate;
  final Completer<void> commitStarted = Completer<void>();

  @override
  Future<void> addAll() async {}

  @override
  Future<void> stagePaths(List<String> paths) async {
    stageCalls++;
    _staged = List<String>.of(paths);
    stagedPaths = _staged!;
  }

  @override
  Future<void> unstagePaths(List<String> paths) async {
    unstagedPaths = List<String>.of(paths);
  }

  @override
  Future<String> commit(String message, String name, String email) async {
    commitCalls++;
    lastCommitMessage = message;
    lastCommitName = name;
    lastCommitEmail = email;
    commitOrder.add(message);
    if (!commitStarted.isCompleted) commitStarted.complete();
    final gate = commitGate;
    if (gate != null) {
      commitGate = null;
      await gate.future;
    }
    return commitOid;
  }

  @override
  Future<void> createBranch(String name) async {}

  @override
  Future<void> checkout(String name) async {
    checkoutCalls++;
    lastCheckout = name;
  }

  @override
  Future<int> merge(String ref, String name, String email) async {
    lastMergeRef = ref;
    return mergeResult;
  }

  @override
  Future<String> commitMerge(String message, String name, String email) async {
    lastMergeCommitMessage = message;
    lastMergeCommitEmail = email;
    return commitMergeOid;
  }

  @override
  Future<List<NativeStatusData>> status() async {
    statusCalls++;
    final failure = statusError;
    if (failure != null) throw failure;
    return statusValue;
  }

  @override
  Future<NativeHeadData> head() async => headValue;

  @override
  Future<List<NativeBranchData>> branches() async => branchesValue;

  @override
  Future<List<NativeRemoteData>> remotes() async => remotesValue;

  @override
  Future<NativeDiffData> diff({String? path, bool staged = false}) async {
    lastDiffPath = path;
    lastDiffStaged = staged;
    return diffValue;
  }

  @override
  Future<List<NativeCommitData>> log({int limit = 20}) async {
    logCalls++;
    lastLogLimit = limit;
    return logValue;
  }

  @override
  Future<void> setRemote(String name, String url) async {
    setRemoteCalls++;
  }

  @override
  Future<void> fetch({
    String remote = 'origin',
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  }) async {
    fetchCalls++;
    lastFetchRemote = remote;
    lastFetchCancel = cancel as _FakeCancel?;
    if (!fetchStarted.isCompleted) fetchStarted.complete();
    final gate = fetchGate;
    if (gate != null) await gate.future;
    final failure = fetchError;
    if (failure != null) throw failure;
  }

  @override
  Future<void> push({
    String remote = 'origin',
    required String refspec,
    String? username,
    String? token,
    NativeCancelHandle? cancel,
  }) async {
    pushCalls++;
    lastPushRefspec = refspec;
    lastPushUsername = username;
    lastPushToken = token;
    lastPushCancel = cancel as _FakeCancel?;
  }

  Completer<void>? fetchGate;
  final Completer<void> fetchStarted = Completer<void>();
  Object? fetchError;
}
