import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/archive_share_service.dart';
import 'package:qfli_studio_core/services/cloud_cache_service.dart';
import 'package:qfli_studio_core/services/cloud_project_actions.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/services/project_zip_service.dart';
import 'package:qfli_studio_core/services/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late PathProviderPlatform original;
  const channel = MethodChannel('qflistudio/platform');

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('qfli-share-test-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(p.join(fixture.path, 'support'));
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PathProviderPlatform.instance = original;
    await fixture.delete(recursive: true);
  });

  Future<String> file(String path, List<int> bytes) async {
    final target = File(p.join(fixture.path, path));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
    return target.path;
  }

  test(
    'selection ZIP contains selected binary only, not siblings or metadata',
    () async {
      final selected = await file('project/src/data.bin', [0, 255, 128, 0]);
      await file('project/private.txt', [9]);
      await file('project/.qfli/project.json', [123, 125]);
      final destination = p.join(fixture.path, 'file.zip');
      await ProjectZipService.exportSelectionToFile(
        projectRoot: p.join(fixture.path, 'project'),
        selectedPath: selected,
        destination: destination,
      );
      final zip = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      expect(zip.map((entry) => entry.name), ['data.bin']);
      expect(zip.single.content, [0, 255, 128, 0]);
    },
  );

  test(
    'folder ZIP preserves only its selected subtree and empty folders',
    () async {
      await file('project/src/one.bin', [1, 2, 3]);
      await file('project/other/two.bin', [4]);
      await Directory(p.join(fixture.path, 'project/src/empty')).create();
      final destination = p.join(fixture.path, 'folder.zip');
      await ProjectZipService.exportSelectionToFile(
        projectRoot: p.join(fixture.path, 'project'),
        selectedPath: p.join(fixture.path, 'project/src'),
        destination: destination,
      );
      final zip = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      expect(zip.find('src/one.bin')!.content, [1, 2, 3]);
      expect(zip.find('src/empty/')!.isDirectory, isTrue);
      expect(zip.find('other/two.bin'), isNull);
      expect(zip.find('.qfli/project.json'), isNull);
    },
  );

  test('outside selection and project-local output are rejected', () async {
    final selected = await file('project/one.bin', [1]);
    final outside = await file('outside.bin', [2]);
    final root = p.join(fixture.path, 'project');
    await expectLater(
      ProjectZipService.exportSelectionToFile(
        projectRoot: root,
        selectedPath: outside,
        destination: p.join(fixture.path, 'outside.zip'),
      ),
      throwsA(isA<ProjectZipException>()),
    );
    await expectLater(
      ProjectZipService.exportSelectionToFile(
        projectRoot: root,
        selectedPath: selected,
        destination: p.join(root, 'recursive.zip'),
      ),
      throwsA(isA<ProjectZipException>()),
    );
  });

  test(
    'links are rejected before ZIP handoff',
    () async {
      await file('project/keep', [1]);
      final outside = await file('outside/data', [99]);
      await Link(
        p.join(fixture.path, 'project/escape'),
      ).create(p.dirname(outside));
      await expectLater(
        ProjectZipService.exportSelectionToFile(
          projectRoot: p.join(fixture.path, 'project'),
          selectedPath: p.join(fixture.path, 'project/escape/data'),
          destination: p.join(fixture.path, 'escape.zip'),
        ),
        throwsA(isA<ProjectZipException>()),
      );
    },
    skip: Platform.isWindows
        ? 'Symlink creation requires host privileges.'
        : false,
  );

  test(
    'native ZIP handoff uses MIME and retains archive after dismissal',
    () async {
      await file('project/one.bin', [0, 255]);
      MethodCall? request;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            request = call;
            expect(
              await File((call.arguments as Map)['path'] as String).exists(),
              isTrue,
            );
            return true; // Handoff, not proof of recipient delivery.
          });
      final project = Project.create(
        name: 'project',
        path: p.join(fixture.path, 'project'),
      );
      final result = await ArchiveShareService.shareProject(project);
      expect(result.status, ArchiveShareStatus.shared);
      expect(request!.method, 'shareFile');
      expect((request!.arguments as Map)['mimeType'], 'application/zip');
      expect(result.path, endsWith('.zip'));
      expect(await File(result.path).exists(), isTrue);
      expect(await File(p.join(project.path, 'one.bin')).readAsBytes(), [
        0,
        255,
      ]);
    },
  );

  test(
    'unsupported retains ZIP for save and cloud without snapshot cannot share',
    () async {
      await file('project/one.bin', [7]);
      var shares = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            shares++;
            return false;
          });
      final project = Project.create(
        name: 'project',
        path: p.join(fixture.path, 'project'),
      );
      final result = await ArchiveShareService.shareProject(project);
      expect(result.status, ArchiveShareStatus.unsupported);
      expect(await File(result.path).exists(), isTrue);
      project.cloudId = 'proj_missing_snapshot';
      await expectLater(
        ArchiveShareService.shareProject(project),
        throwsA(isA<ProjectZipException>()),
      );
      expect(
        shares,
        1,
        reason: 'An incomplete cloud export never opens native sharing.',
      );
    },
  );

  test(
    'cloud ZIP uses only complete snapshot payload, never workspace or manifest',
    () async {
      final snapshotPath = p.join(fixture.path, 'cache/snapshot/files');
      await file('cache/snapshot/files/raw.bin', [0, 255, 1]);
      await file('cache/snapshot/manifest.json', [9]);
      await file('workspace/unsent.txt', [8]);
      final auth = AuthStore();
      await auth.signIn('session-a', _user('account-a'));
      final store = ProjectStore(
        storageFile: File(p.join(fixture.path, 'registry.json')),
      );
      final cache = CloudCacheService();
      final actions = _Snapshots(
        auth: auth,
        store: store,
        cache: cache,
        payload: snapshotPath,
      );
      addTearDown(() {
        actions.dispose();
        cache.dispose();
        store.dispose();
        auth.dispose();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
      final project = Project.create(
        name: 'cloud',
        path: p.join(fixture.path, 'workspace'),
        cloudId: 'proj_cloud',
      );
      final result = await ArchiveShareService.shareProject(
        project,
        token: 'session-a',
        accountId: 'account-a',
        cloudActions: actions,
      );
      final zip = ZipDecoder().decodeBytes(
        await File(result.path).readAsBytes(),
      );
      expect(zip.map((entry) => entry.name), ['raw.bin']);
      expect(zip.single.content, [0, 255, 1]);
      expect(actions.snapshots, 1);
      expect(actions.releases, 1);
      expect(await File(p.join(project.path, 'unsent.txt')).readAsBytes(), [8]);
    },
  );

  test(
    'cloud generation is captured before path preparation and A-B-A cancels handoff',
    () async {
      final payload = p.join(fixture.path, 'payload');
      await file('payload/raw.bin', [1]);
      final auth = AuthStore();
      await auth.signIn('session-a', _user('account-a'));
      final store = ProjectStore(
        storageFile: File(p.join(fixture.path, 'registry.json')),
      );
      final cache = CloudCacheService();
      final actions = _Snapshots(
        auth: auth,
        store: store,
        cache: cache,
        payload: payload,
      );
      addTearDown(() {
        actions.dispose();
        cache.dispose();
        store.dispose();
        auth.dispose();
      });
      final paths = _GatedPaths(p.join(fixture.path, 'support'));
      PathProviderPlatform.instance = paths;
      var shares = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            shares++;
            return true;
          });
      final pending = ArchiveShareService.shareProject(
        Project.create(
          name: 'cloud',
          path: p.join(fixture.path, 'workspace'),
          cloudId: 'proj_cloud',
        ),
        token: 'session-a',
        accountId: 'account-a',
        cloudActions: actions,
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<CloudOperationException>()),
      );
      await paths.started.future;
      expect(
        actions.snapshots,
        1,
        reason: 'The snapshot session is captured before path-provider I/O.',
      );
      actions.generation++; // A -> B.
      actions.generation++; // B -> A, even with equal token/account values.
      paths.release.complete();
      await rejected;
      expect(shares, 0);
      expect(actions.releases, 1);
    },
  );

  test(
    'a failed cloud snapshot never reaches the native share transport',
    () async {
      final auth = AuthStore();
      await auth.signIn('session-a', _user('account-a'));
      final store = ProjectStore(
        storageFile: File(p.join(fixture.path, 'registry.json')),
      );
      final cache = CloudCacheService();
      final actions = _Snapshots(
        auth: auth,
        store: store,
        cache: cache,
        payload: fixture.path,
      )..fail = true;
      addTearDown(() {
        actions.dispose();
        cache.dispose();
        store.dispose();
        auth.dispose();
      });
      var shares = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            shares++;
            return true;
          });
      await expectLater(
        ArchiveShareService.shareProject(
          Project.create(
            name: 'cloud',
            path: fixture.path,
            cloudId: 'proj_cloud',
          ),
          token: 'session-a',
          accountId: 'account-a',
          cloudActions: actions,
        ),
        throwsA(isA<CloudOperationException>()),
      );
      expect(shares, 0);
    },
  );

  test('native failure is not silently reported as unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'SHARE_FAILED', message: 'Unavailable');
        });
    await expectLater(
      ShareService.shareFile(path: '/prepared/file.zip', title: 'archive'),
      throwsA(isA<PlatformException>()),
    );
  });
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

class _Snapshots extends CloudProjectActions {
  _Snapshots({
    required super.auth,
    required super.store,
    required super.cache,
    required this.payload,
  });
  final String payload;
  int snapshots = 0;
  int releases = 0;
  int generation = 0;
  bool fail = false;
  @override
  Future<CloudSnapshot> prepareSnapshot(Project project) {
    snapshots++;
    final captured = generation;
    if (fail) {
      return Future.error(
        const CloudOperationException('partial', 'Snapshot download failed.'),
      );
    }
    return Future.value(
      CloudSnapshot(
        path: payload,
        fileCount: 1,
        bytes: 3,
        cachedAt: DateTime.utc(2026),
        ensureCurrent: () {
          if (generation != captured) {
            throw const CloudOperationException(
              'sessionChanged',
              'Account changed.',
            );
          }
        },
        release: () async {
          releases++;
        },
      ),
    );
  }
}

class _GatedPaths extends _Paths {
  _GatedPaths(super.path);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> getApplicationSupportPath() async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return path;
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}
