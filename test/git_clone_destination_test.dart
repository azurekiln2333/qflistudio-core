// R2 cloud regressions. Sources only: do not run locally.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/git_clone_service.dart';
import 'package:qfli_studio_core/store/project_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform original;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('git-projects-destinations-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = original;
    await root.delete(recursive: true);
  });

  test('default allocator reserves distinct gitProjects children', () async {
    final store = _Registry();
    addTearDown(store.dispose);
    final paths = <String>[];
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final service = GitCloneService(
      store: store,
      desktop: true,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            paths.add(path);
            if (paths.length == 2) entered.complete();
            await release.future;
            await File(p.join(path, 'README.md')).writeAsString('source');
          },
    );
    final oldPath = await Directory(p.join(root.path, 'existing')).create();
    final oldFile = await File(
      p.join(oldPath.path, 'keep.txt'),
    ).writeAsString('keep');
    const request = GitCloneRequest(url: 'https://github.com/owner/repo.git');
    final first = service.clone(request);
    final second = service.clone(request);
    try {
      await entered.future.timeout(const Duration(seconds: 5));
    } finally {
      release.complete();
    }
    final results = await Future.wait([first, second]);
    final expected = p.join((await AppPaths.projectsRoot())!, 'gitProjects');
    expect(paths, hasLength(2));
    expect(paths.toSet(), hasLength(2));
    expect(paths.every((path) => p.equals(p.dirname(path), expected)), isTrue);
    expect(results.every((result) => result.ok), isTrue);
    expect(await oldFile.readAsString(), 'keep');
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Registry extends ProjectStore {
  @override
  Future<ProjectResult> addExisting(String rawPath) async =>
      (error: null, project: Project.create(name: 'repo', path: rawPath));
}
