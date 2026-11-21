// Regression sources for cloud CI. Local validation is static-only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/config/api_config.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/cloud_cache_service.dart';
import 'package:qfli_studio_core/services/cloud_project_actions.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AuthStore auth;
  late ProjectStore store;
  late _ActionsApi api;
  late CloudCacheService cache;
  late CloudProjectActions actions;
  late CloudProjectScope scope;
  late Project project;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-cloud-actions-');
    auth = AuthStore(storageFile: File(p.join(root.path, 'auth.json')));
    await auth.load();
    await auth.signIn('token_a', _user('user_a'));
    store = ProjectStore(storageFile: File(p.join(root.path, 'projects.json')));
    await store.load();
    api = _ActionsApi();
    cache = CloudCacheService(
      api: api,
      projectsRootOverride: p.join(root.path, 'projects'),
    );
    actions = CloudProjectActions(
      auth: auth,
      store: store,
      api: api,
      cache: cache,
    );
    scope = CloudProjectScope(origin: ApiConfig.origin, accountId: 'user_a');
    final result = await store.addCloudProject(
      name: 'cloud',
      cloudId: 'proj_a',
      cachePath: p.join(await cache.projectRoot(scope, 'proj_a'), 'workspace'),
      scope: scope,
    );
    project = result.project!;
  });
  tearDown(() async {
    actions.dispose();
    cache.dispose();
    auth.dispose();
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('remote failure retains registered card and every cache byte', () async {
    Directory(project.path).createSync(recursive: true);
    final unsent = File(p.join(project.path, 'unsent'))
      ..writeAsStringSync('keep');
    api.failDelete = true;
    final result = await actions.deleteProject(project);
    expect(result.remoteDeleted, isFalse);
    expect(result.error, isNotNull);
    expect(actions.projects.single.id, project.id);
    expect(unsent.readAsStringSync(), 'keep');
    final registry =
        jsonDecode(File(p.join(root.path, 'projects.json')).readAsStringSync())
            as Map;
    expect(registry['projects'], hasLength(1));
  });

  test(
    'successful deletion waits for registry and preserves unsent edits',
    () async {
      Directory(project.path).createSync(recursive: true);
      final unsent = File(p.join(project.path, 'unsent'))
        ..writeAsStringSync('keep');
      final result = await actions.deleteProject(project);
      expect(result.remoteDeleted, isTrue);
      expect(result.cleanupError, isNull);
      expect(actions.projects, isEmpty);
      final restored = ProjectStore(
        storageFile: File(p.join(root.path, 'projects.json')),
      );
      await restored.load();
      expect(restored.cloudProjectsFor(scope), isEmpty);
      expect(unsent.readAsStringSync(), 'keep');
      restored.dispose();
    },
  );

  test('list fetched before deletion cannot resurrect the card', () async {
    api.listGate = Completer<void>();
    final refresh = actions.refresh();
    await api.listStarted.future;
    expect((await actions.deleteProject(project)).remoteDeleted, isTrue);
    api.listGate!.complete();
    await refresh;
    expect(actions.projects, isEmpty);
    final ticket = store.invalidateCloudRefresh(scope);
    // Even a later stale server list cannot beat the deletion tombstone.
    await store.mergeCloudProjects([project], scope: scope, generation: ticket);
    expect(actions.projects, isEmpty);
  });

  test('duplicate delete is rejected without a second request', () async {
    api.deleteGate = Completer<void>();
    final first = actions.deleteProject(project);
    await api.deleteStarted.future;
    final second = await actions.deleteProject(project);
    expect(second.remoteDeleted, isFalse);
    expect(api.deletes, 1);
    api.deleteGate!.complete();
    expect((await first).remoteDeleted, isTrue);
  });

  test(
    'account switch invalidates delayed list and hides old account projects',
    () async {
      api.listGate = Completer<void>();
      final refresh = actions.refresh();
      await api.listStarted.future;
      await auth.signIn('token_b', _user('user_b'));
      api.listGate!.complete();
      await expectLater(refresh, throwsA(isA<CloudOperationException>()));
      expect(actions.projects, isEmpty);
      expect(store.cloudProjectsFor(scope).single, project);
    },
  );

  test(
    'deferred deletion after account switch persists only the captured scope',
    () async {
      final other = CloudProjectScope(
        origin: scope.origin,
        accountId: 'user_b',
      );
      final otherResult = await store.addCloudProject(
        name: 'other account',
        cloudId: 'proj_a',
        cachePath: p.join(
          await cache.projectRoot(other, 'proj_a'),
          'workspace',
        ),
        scope: other,
      );
      Directory(project.path).createSync(recursive: true);
      File(
        p.join(project.path, 'unsent'),
      ).writeAsStringSync('keep old account bytes');
      api.deleteGate = Completer<void>();
      final pending = actions.deleteProject(project);
      await api.deleteStarted.future;
      await auth.signIn('token_b', _user('user_b'));
      api.deleteGate!.complete();
      final result = await pending;
      expect(result.remoteDeleted, isTrue);
      expect(result.cleanupError, isNull);
      expect(actions.projects.single.id, otherResult.project!.id);
      final registry = File(p.join(root.path, 'projects.json'));
      final data =
          jsonDecode(registry.readAsStringSync()) as Map<String, dynamic>;
      expect(data['deletedCloud'], contains('${scope.key}/proj_a'));
      // Even an old row accidentally retained in the registry cannot reappear.
      (data['projects'] as List).add(project.toJson());
      registry.writeAsStringSync(jsonEncode(data));
      final restored = ProjectStore(storageFile: registry);
      await restored.load();
      expect(restored.cloudProjectsFor(scope), isEmpty);
      expect(
        restored.cloudProjectsFor(other).single.id,
        otherResult.project!.id,
      );
      final ticket = restored.invalidateCloudRefresh(scope);
      await restored.mergeCloudProjects(
        [project],
        scope: scope,
        generation: ticket,
      );
      expect(restored.cloudProjectsFor(scope), isEmpty);
      expect(
        File(p.join(project.path, 'unsent')).readAsStringSync(),
        'keep old account bytes',
      );
      restored.dispose();
    },
  );

  test(
    'deferred deletion after logout awaits durable registry removal',
    () async {
      api.deleteGate = Completer<void>();
      final pending = actions.deleteProject(project);
      await api.deleteStarted.future;
      await auth.clearLocalData();
      api.deleteGate!.complete();
      final result = await pending;
      expect(result.remoteDeleted, isTrue);
      expect(result.cleanupError, isNull);
      final restored = ProjectStore(
        storageFile: File(p.join(root.path, 'projects.json')),
      );
      await restored.load();
      expect(restored.cloudProjectsFor(scope), isEmpty);
      restored.dispose();
    },
  );

  test(
    'complete refresh reconciles absent rows only in the current scope',
    () async {
      final other = CloudProjectScope(
        origin: scope.origin,
        accountId: 'user_b',
      );
      await store.addCloudProject(
        name: 'other',
        cloudId: 'proj_a',
        cachePath: 'untouched-other-mirror',
        scope: other,
      );
      Directory(project.path).createSync(recursive: true);
      File(p.join(project.path, 'unsent')).writeAsStringSync('keep');
      api.listItems = [];
      await actions.refresh();
      expect(actions.projects, isEmpty);
      expect(store.cloudProjectsFor(other), hasLength(1));
      expect(File(p.join(project.path, 'unsent')).readAsStringSync(), 'keep');
      final restored = ProjectStore(
        storageFile: File(p.join(root.path, 'projects.json')),
      );
      await restored.load();
      expect(restored.cloudProjectsFor(scope), isEmpty);
      expect(restored.cloudProjectsFor(other), hasLength(1));
      restored.dispose();
    },
  );

  test(
    'same cloud id in two accounts remains two persistent records',
    () async {
      final other = CloudProjectScope(
        origin: scope.origin,
        accountId: 'user_b',
      );
      final result = await store.addCloudProject(
        name: 'same remote id',
        cloudId: 'proj_a',
        cachePath: p.join(
          await cache.projectRoot(other, 'proj_a'),
          'workspace',
        ),
        scope: other,
      );
      expect(result.error, isNull);
      expect(store.cloudProjectsFor(scope), hasLength(1));
      expect(store.cloudProjectsFor(other), hasLength(1));
      final restored = ProjectStore(
        storageFile: File(p.join(root.path, 'projects.json')),
      );
      await restored.load();
      expect(restored.cloudProjectsFor(other), hasLength(1));
      restored.dispose();
    },
  );

  test(
    'unowned legacy cloud row is preserved but never attached to current account',
    () async {
      final legacy = Project.create(
        name: 'legacy',
        path: p.join(root.path, 'old'),
        cloudId: 'proj_old',
      );
      expect(legacy.belongsToCloudScope(scope), isFalse);
      final stale = store.invalidateCloudRefresh(scope);
      store.invalidateCloudRefresh(scope);
      await store.mergeCloudProjects([legacy], scope: scope, generation: stale);
      expect(actions.projects, [project]);
    },
  );

  test('workspace export does not require registry membership', () async {
    final standalone = Project.create(
      name: 'workspace owner',
      path: 'unused',
      cloudId: 'proj_detached',
      cloudOrigin: scope.origin,
      cloudAccountId: scope.accountId,
    );
    final snapshot = await actions.prepareSnapshot(standalone);
    expect(snapshot.fileCount, 1);
    expect(File(p.join(snapshot.path, 'remote')).readAsStringSync(), 'remote');
    snapshot.ensureCurrent();
    await snapshot.release();
  });

  test(
    'disposing a facade does not invalidate another editor session',
    () async {
      final snapshot = await actions.prepareSnapshot(project);
      final second = CloudProjectActions(
        auth: auth,
        store: store,
        api: api,
        cache: cache,
      );
      second.dispose();
      snapshot.ensureCurrent();
      await snapshot.release();
    },
  );
}

CommunityUser _user(String id) => CommunityUser(
  id: id,
  username: id,
  nickname: id,
  bio: '',
  avatarColor: '#000000',
  points: 0,
  checkinStreak: 0,
  provider: 'test',
);

class _ActionsApi extends ApiClient {
  List<Map<String, dynamic>> listItems = [
    {'id': 'proj_a', 'name': 'cloud'},
  ];
  bool failDelete = false;
  int deletes = 0;
  Completer<void>? listGate;
  Completer<void>? deleteGate;
  final listStarted = Completer<void>();
  final deleteStarted = Completer<void>();
  @override
  Future<List<Map<String, dynamic>>> cloudProjects(String token) async {
    if (!listStarted.isCompleted) listStarted.complete();
    await listGate?.future;
    return listItems;
  }

  @override
  Future<void> cloudDeleteProject(String token, String id) async {
    deletes++;
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteGate?.future;
    if (failDelete) throw ApiException('delete failed');
  }

  @override
  Future<Map<String, dynamic>> cloudFileTree(String token, String id) async => {
    'files': [
      {'path': 'remote', 'mtime': 1.0},
    ],
  };
  @override
  Future<Map<String, dynamic>> cloudReadFile(
    String token,
    String id,
    String path,
  ) async => {'content': base64Encode(utf8.encode('remote'))};
}
