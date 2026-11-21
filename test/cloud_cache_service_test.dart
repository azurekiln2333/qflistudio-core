// Regression sources for cloud CI only. Do not execute locally in this task.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/config/api_config.dart';
import 'package:qfli_studio_core/models/cloud_project.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/cloud_cache_paths.dart';
import 'package:qfli_studio_core/services/cloud_cache_service.dart';
import 'package:qfli_studio_core/services/cloud_sync_service.dart';

const _portableConflicts = <List<String>>[
  ['A.txt', 'a.txt'],
  ['A/x.txt', 'a/y.txt'],
  ['Root/Child/x.txt', 'Root/child/y.txt'],
  ['dir', 'dir/file'],
  ['A', 'a/file'],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _CloudApi api;
  late CloudCacheService cache;
  late CloudProjectScope scope;
  late CloudSession session;
  late Project project;
  var current = true;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-scoped-cloud-');
    api = _CloudApi();
    cache = CloudCacheService(api: api, projectsRootOverride: root.path);
    scope = CloudProjectScope(origin: ApiConfig.origin, accountId: 'user_a');
    current = true;
    session = CloudSession(
      scope: scope,
      token: 'private-session',
      isCurrent: () => current,
    );
    final path = await cache.projectRoot(scope, 'proj_a');
    project = Project.create(
      name: 'same display name',
      path: p.join(path, 'workspace'),
      cloudId: 'proj_a',
      cloudOrigin: scope.origin,
      cloudAccountId: scope.accountId,
    );
  });
  tearDown(() async {
    cache.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'origin, account and cloud id form separate canonical storage keys',
    () async {
      final otherAccount = CloudProjectScope(
        origin: scope.origin,
        accountId: 'user_b',
      );
      final otherOrigin = CloudProjectScope(
        origin: 'https://other.example',
        accountId: scope.accountId,
      );
      final paths = {
        await cache.projectRoot(scope, 'proj_a'),
        await cache.projectRoot(otherAccount, 'proj_a'),
        await cache.projectRoot(otherOrigin, 'proj_a'),
        await cache.projectRoot(scope, 'proj_b'),
      };
      expect(paths, hasLength(4));
      for (final path in paths) {
        expect(p.isWithin(p.join(root.path, 'cloudProjects'), path), isTrue);
        expect(path, isNot(contains('private-session')));
      }
    },
  );

  test(
    'fresh complete binary snapshot has payload-only files and manifest status',
    () async {
      api.files = {
        'src/main.dart': utf8.encode('main'),
        'assets/raw.bin': [0, 255, 128, 1],
      };
      final states = <CloudCachePhase>[];
      cache.addListener(() => states.add(cache.status(scope, 'proj_a').phase));
      final snapshot = await cache.prepareSnapshot(
        project: project,
        session: session,
      );
      try {
        expect(
          File(p.join(snapshot.path, 'assets', 'raw.bin')).readAsBytesSync(),
          [0, 255, 128, 1],
        );
        expect(snapshot.fileCount, 2);
        expect(snapshot.bytes, 8);
        expect(api.treeCalls, 2);
        expect(api.readCalls, containsAll(['src/main.dart', 'assets/raw.bin']));
        expect(
          Directory(snapshot.path)
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => p.relative(f.path, from: snapshot.path)),
          unorderedEquals([
            p.join('src', 'main.dart'),
            p.join('assets', 'raw.bin'),
          ]),
        );
        expect(states, contains(CloudCachePhase.caching));
        expect(cache.status(scope, 'proj_a').phase, CloudCachePhase.cached);
        final restarted = CloudCacheService(
          api: api,
          projectsRootOverride: root.path,
        );
        final restored = await restarted.inspect(project, session);
        expect(restored.phase, CloudCachePhase.cached);
        expect(restored.fileCount, 2);
        expect(restored.bytes, 8);
        expect(restored.cachedAt, snapshot.cachedAt);
        restarted.dispose();
      } finally {
        await snapshot.release();
      }
    },
  );

  test('partial refresh never replaces the last complete manifest', () async {
    api.files = {
      'one': [1],
      'two': [2],
    };
    final first = await cache.prepareSnapshot(
      project: project,
      session: session,
    );
    final manifest = File(
      p.join(await cache.projectRoot(scope, 'proj_a'), 'manifest.json'),
    );
    final before = manifest.readAsStringSync();
    await first.release();
    api.failPath = 'two';
    await expectLater(
      cache.prepareSnapshot(project: project, session: session),
      throwsA(isA<ApiException>()),
    );
    expect(manifest.readAsStringSync(), before);
    final failed = cache.status(scope, 'proj_a');
    expect(failed.phase, CloudCachePhase.failed);
    expect(failed.cachedAt, first.cachedAt);
    expect(failed.fileCount, 2);
    expect(failed.error, isNot(contains('private-session')));
    expect(File(p.join(first.path, 'one')).readAsBytesSync(), [1]);
    final snapshots = Directory(p.dirname(first.path)).parent;
    expect(
      snapshots.listSync().where(
        (e) => p.basename(e.path).startsWith('.stage-'),
      ),
      isEmpty,
    );
  });

  test(
    'folder presence without a valid complete manifest is never cached',
    () async {
      Directory(project.path).createSync(recursive: true);
      File(
        p.join(project.path, 'unsent.txt'),
      ).writeAsStringSync('do not overwrite');
      expect(
        (await cache.inspect(project, session)).phase,
        CloudCachePhase.notCached,
      );
    },
  );

  for (final invalid in [
    '../outside',
    '/absolute',
    r'C:\drive',
    r'foo\..\escape',
    'a/../b',
    'a//b',
    'nul.txt',
    'name.',
    'a\u0000b',
  ]) {
    test(
      'rejects unsafe remote path $invalid before reading any file',
      () async {
        api.files = {
          invalid: [1],
        };
        await expectLater(
          cache.prepareSnapshot(project: project, session: session),
          throwsA(isA<CloudOperationException>()),
        );
        expect(api.readCalls, isEmpty);
      },
    );
  }

  for (final original in _portableConflicts) {
    for (final reversed in [false, true]) {
      final paths = reversed ? original.reversed.toList() : original;
      test(
        'rejects portable prefix conflict $paths before downloads',
        () async {
          api.files = {
            for (final path in paths) path: [1],
          };
          await expectLater(
            cache.update(project, session),
            throwsA(
              isA<CloudOperationException>().having(
                (error) => error.code,
                'code',
                'path',
              ),
            ),
          );
          expect(api.readCalls, isEmpty);
          expect(
            File(
              p.join(await cache.projectRoot(scope, 'proj_a'), 'manifest.json'),
            ).existsSync(),
            isFalse,
          );
        },
      );

      test(
        'manifest rejects portable prefix conflict $paths before payload reads',
        () async {
          final ownedRoot = await cache.projectRoot(scope, 'proj_a');
          cache.ensureOwner(ownedRoot, project, session);
          // No payload files exist. The namespace error must win over a missing
          // file error, proving the whole manifest is preflighted first.
          Directory(
            p.join(ownedRoot, 'snapshots', 'snapshot-prefix', 'files'),
          ).createSync(recursive: true);
          File(p.join(ownedRoot, 'manifest.json')).writeAsStringSync(
            jsonEncode({
              'version': 1,
              'complete': true,
              'scope': scope.key,
              'cloudId': project.cloudId,
              'generation': 'snapshot-prefix',
              'cachedAt': DateTime.utc(2026, 11, 21).toIso8601String(),
              'fileCount': paths.length,
              'bytes': paths.length,
              'files': [
                for (final path in paths)
                  {
                    'path': path,
                    'bytes': 1,
                    'hash': sha256.convert([1]).toString(),
                  },
              ],
            }),
          );
          await expectLater(
            cache.restoreWorkspace(project, session, project.path),
            throwsA(
              isA<CloudOperationException>()
                  .having((error) => error.code, 'code', 'manifest')
                  .having(
                    (error) => error.message,
                    'namespace error',
                    anyOf('云端路径大小写冲突', '云端文件与目录冲突'),
                  ),
            ),
          );
          expect(api.treeCalls, 0);
          expect(api.readCalls, isEmpty);
        },
      );
    }
  }

  test(
    'consistent shared directory prefixes survive manifest restart',
    () async {
      api.files = {
        'A/Shared/x.txt': [1],
        'A/Shared/y.txt': [2],
        'A/Other/z.txt': [3],
      };
      await cache.update(project, session);
      final restarted = CloudCacheService(
        api: api,
        projectsRootOverride: root.path,
      );
      try {
        final restored = await restarted.inspect(project, session);
        expect(restored.phase, CloudCachePhase.cached);
        expect(restored.fileCount, 3);
        expect(restored.bytes, 3);
        expect(api.readCalls, hasLength(3));
      } finally {
        restarted.dispose();
      }
    },
  );

  test('scope switch during read publishes no manifest or snapshot', () async {
    api.files = {
      'one': [1],
    };
    api.readGate = Completer<void>();
    final pending = cache.prepareSnapshot(project: project, session: session);
    await api.readStarted.future;
    current = false;
    api.readGate!.complete();
    await expectLater(pending, throwsA(isA<CloudOperationException>()));
    final rootPath = await cache.projectRoot(scope, 'proj_a');
    expect(File(p.join(rootPath, 'manifest.json')).existsSync(), isFalse);
  });

  test(
    'snapshot refresh does not touch canonical or old unsent mirrors',
    () async {
      Directory(project.path).createSync(recursive: true);
      File(p.join(project.path, 'unsent.txt')).writeAsStringSync('local edits');
      final old = Directory(p.join(root.path, 'cloud_projects', 'legacy'))
        ..createSync(recursive: true);
      File(p.join(old.path, 'old.txt')).writeAsStringSync('legacy edits');
      // An unmarked nonempty root is not implicitly adopted.
      await expectLater(
        cache.update(project, session),
        throwsA(isA<CloudOperationException>()),
      );
      expect(
        File(p.join(project.path, 'unsent.txt')).readAsStringSync(),
        'local edits',
      );
      expect(
        File(p.join(old.path, 'old.txt')).readAsStringSync(),
        'legacy edits',
      );
    },
  );

  test('clear refuses export lease, active editor and dirty files', () async {
    final service = await CloudSyncService.open(
      cloudId: 'proj_a',
      name: 'test',
      scope: scope,
      session: session,
      cache: cache,
    );
    api.files = {
      'remote': [1],
    };
    final snapshot = await cache.prepareSnapshot(
      project: project,
      session: session,
    );
    await expectLater(
      cache.clear(project, session),
      throwsA(isA<CloudOperationException>()),
    );
    await snapshot.release();
    await expectLater(
      cache.clear(project, session),
      throwsA(isA<CloudOperationException>()),
    );
    service.dispose();
    File(p.join(project.path, 'unsent')).writeAsStringSync('keep');
    await expectLater(
      cache.clear(project, session),
      throwsA(isA<CloudOperationException>()),
    );
    expect(File(p.join(project.path, 'unsent')).readAsStringSync(), 'keep');
    expect(api.deleteCalls, 0);
  });

  test(
    'clear of a complete cache removes only current scope, never remote',
    () async {
      api.files = {
        'remote': [1],
      };
      await cache.update(project, session);
      final other = Directory(
        await cache.projectRoot(
          CloudProjectScope(origin: scope.origin, accountId: 'user_b'),
          'proj_a',
        ),
      );
      other.createSync(recursive: true);
      File(p.join(other.path, 'keep')).writeAsStringSync('other account');
      await cache.clear(project, session);
      expect(
        Directory(await cache.projectRoot(scope, 'proj_a')).existsSync(),
        isFalse,
      );
      expect(File(p.join(other.path, 'keep')).existsSync(), isTrue);
      expect(cache.status(scope, 'proj_a').phase, CloudCachePhase.notCached);
      expect(api.deleteCalls, 0);
    },
  );

  test(
    'pull preserves a changed workspace and never prunes local-only files',
    () async {
      final service = await CloudSyncService.open(
        cloudId: 'proj_a',
        name: 'test',
        scope: scope,
        session: session,
        cache: cache,
      );
      try {
        api.files = {
          'one': [1],
          'two': [2],
        };
        expect((await service.pullAll(token: session.token)).error, isNull);
        final one = File(p.join(service.localPath, 'one'))
          ..writeAsBytesSync([9]);
        final localOnly = File(p.join(service.localPath, 'local-only'))
          ..writeAsStringSync('keep');
        api.files = {
          'one': [3],
        };
        final rejected = await service.pullAll(token: session.token);
        expect(rejected.error, isNotNull);
        expect(one.readAsBytesSync(), [9]);
        expect(File(p.join(service.localPath, 'two')).readAsBytesSync(), [2]);
        expect(localOnly.readAsStringSync(), 'keep');
        final snapshot = await cache.prepareSnapshot(
          project: project,
          session: session,
        );
        expect(File(p.join(snapshot.path, 'one')).readAsBytesSync(), [3]);
        expect(File(p.join(snapshot.path, 'two')).existsSync(), isFalse);
        expect(File(p.join(snapshot.path, 'local-only')).existsSync(), isFalse);
        await snapshot.release();
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'cached payload restores a new workspace without a network pull',
    () async {
      api.files = {
        'remote': [1, 2, 3],
      };
      await cache.update(project, session);
      final before = api.treeCalls;
      final service = await CloudSyncService.open(
        cloudId: 'proj_a',
        name: 'test',
        scope: scope,
        session: session,
        cache: cache,
      );
      try {
        expect(File(p.join(service.localPath, 'remote')).readAsBytesSync(), [
          1,
          2,
          3,
        ]);
        expect(api.treeCalls, before);
      } finally {
        service.dispose();
      }
    },
  );

  test('pull and clear preserve a pending local deletion', () async {
    final service = await CloudSyncService.open(
      cloudId: 'proj_a',
      name: 'test',
      scope: scope,
      session: session,
      cache: cache,
    );
    api.files = {
      'remote': [1],
    };
    expect((await service.pullAll(token: session.token)).error, isNull);
    File(p.join(service.localPath, 'remote')).deleteSync();
    final result = await service.pullAll(token: session.token);
    expect(result.error, isNotNull);
    expect(File(p.join(service.localPath, 'remote')).existsSync(), isFalse);
    service.dispose();
    await expectLater(
      cache.clear(project, session),
      throwsA(isA<CloudOperationException>()),
    );
  });

  test(
    'failed operation state survives restart with the prior good snapshot',
    () async {
      api.files = {
        'one': [1],
      };
      await cache.update(project, session);
      api.failPath = 'one';
      await expectLater(
        cache.update(project, session),
        throwsA(isA<ApiException>()),
      );
      final restarted = CloudCacheService(
        api: api,
        projectsRootOverride: root.path,
      );
      final restored = await restarted.inspect(project, session);
      expect(restored.phase, CloudCachePhase.failed);
      expect(restored.cachedAt, isNotNull);
      expect(restored.fileCount, 1);
      expect(restored.error, isNotNull);
      restarted.dispose();
    },
  );

  test('link escape is rejected by the common path boundary', () async {
    final real = Directory(p.join(root.path, 'real'))..createSync();
    final link = Link(p.join(root.path, 'alias'));
    try {
      await link.create(real.path);
    } on FileSystemException {
      markTestSkipped('Host cannot create links');
      return;
    }
    expect(
      () => CloudCachePaths.noLinks(p.join(link.path, 'file')),
      throwsA(isA<CloudOperationException>()),
    );
  });
}

class _CloudApi extends ApiClient {
  Map<String, List<int>> files = {};
  String? failPath;
  int treeCalls = 0;
  int deleteCalls = 0;
  final readCalls = <String>[];
  Completer<void>? readGate;
  final readStarted = Completer<void>();
  @override
  Future<Map<String, dynamic>> cloudFileTree(String token, String id) async {
    treeCalls++;
    return {
      'files': [
        for (final path in files.keys) {'path': path, 'mtime': 1.0},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> cloudReadFile(
    String token,
    String id,
    String path,
  ) async {
    readCalls.add(path);
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    if (path == failPath) throw ApiException('private-session must not leak');
    return {'content': base64Encode(files[path]!)};
  }

  @override
  Future<void> cloudDeleteProject(String token, String id) async {
    deleteCalls++;
  }
}
