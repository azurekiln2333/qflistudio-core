import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/git/git_backend.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/git_clone_service.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/store/project_store.dart';

void main() {
  late Directory container;
  late _Registry registry;

  setUp(() async {
    container = await Directory.systemTemp.createTemp('git-clone-ci-');
    registry = _Registry();
  });

  tearDown(() async {
    registry.dispose();
    await container.delete(recursive: true);
  });

  Future<GitCloneDestination> allocate({required String name}) async {
    final directory = await container.createTemp('$name-');
    return GitCloneDestination(path: directory.path, displayName: name);
  }

  test('reports lifecycle and backend progress without credentials', () async {
    final progress = <GitCloneProgress>[];
    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: allocate,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            onProgress?.call(
              const GitCloneProgress(
                stage: GitCloneStage.receiving,
                completed: 3,
                total: 4,
                receivedBytes: 2048,
              ),
            );
          },
    );

    final outcome = await service.clone(
      const GitCloneRequest(
        url: 'https://example.invalid/repo.git',
        username: 'private-user',
        token: 'private-token',
      ),
      onProgress: progress.add,
    );

    expect(outcome.ok, isTrue);
    expect(progress.map((event) => event.stage), <GitCloneStage>[
      GitCloneStage.preparing,
      GitCloneStage.connecting,
      GitCloneStage.receiving,
      GitCloneStage.registering,
    ]);
    expect(progress.last.fraction, isNull);
    expect(
      progress.any((event) => event.toString().contains('private-token')),
      isFalse,
    );
  });

  test('cancellation at registration boundary prevents registration', () async {
    final cancellation = GitCloneCancellation();
    String? reserved;
    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: allocate,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            reserved = path;
            await File(p.join(path, 'source.txt')).writeAsString('complete');
          },
    );

    final outcome = await service.clone(
      const GitCloneRequest(url: 'https://example.invalid/repo.git'),
      cancellation: cancellation,
      onProgress: (event) {
        if (event.stage == GitCloneStage.registering) cancellation.cancel();
      },
    );

    expect(outcome.cancelled, isTrue);
    expect(registry.calls, 0);
    expect(await Directory(reserved!).exists(), isFalse);
    cancellation.dispose();
  });

  test('a throwing progress listener cannot fail clone registration', () async {
    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: allocate,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {},
    );

    final outcome = await service.clone(
      const GitCloneRequest(url: 'https://example.invalid/repo.git'),
      onProgress: (_) => throw StateError('listener disposed'),
    );

    expect(outcome.ok, isTrue);
    expect(registry.calls, 1);
  });

  test(
    'failure removes its reserved directory and preserves a sibling',
    () async {
      final sibling = File(p.join(container.path, 'existing.txt'));
      await sibling.writeAsString('keep');
      String? reserved;
      final service = GitCloneService(
        store: registry,
        desktop: true,
        allocateDestination: allocate,
        cloneRunner:
            ({
              required url,
              required path,
              credentials,
              cancellation,
              onProgress,
            }) async {
              reserved = path;
              await File(p.join(path, 'partial.txt')).writeAsString('partial');
              throw const GitOperationException('clone failed');
            },
      );
      final outcome = await service.clone(
        const GitCloneRequest(url: 'https://example.invalid/repo.git'),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.error, 'clone failed');
      expect(await Directory(reserved!).exists(), isFalse);
      expect(await sibling.readAsString(), 'keep');
      expect(registry.calls, 0);
    },
  );

  test('registration failure keeps the complete clone recoverable', () async {
    registry.reject = true;
    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: allocate,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            await File(p.join(path, 'source.txt')).writeAsString('source');
          },
    );
    final outcome = await service.clone(
      const GitCloneRequest(url: 'https://example.invalid/repo.git'),
    );
    expect(outcome.ok, isFalse);
    expect(outcome.error, 'registry unavailable');
    expect(outcome.preservedPath, outcome.path);
    expect(
      await File(p.join(outcome.path!, 'source.txt')).readAsString(),
      'source',
    );
  });

  test('registration reads the requested name and existing language', () async {
    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: allocate,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            await ProjectConfig.write(
              projectRoot: path,
              name: 'Upstream',
              language: 'Python',
              type: 'python',
              strict: true,
            );
          },
    );
    final outcome = await service.clone(
      const GitCloneRequest(
        url: 'https://example.invalid/repo.git',
        name: 'My clone',
      ),
    );
    expect(outcome.ok, isTrue);
    expect(outcome.project!.name, 'My clone');
    expect(outcome.project!.language, 'Python');
    expect(outcome.project!.type, 'python');
    expect(outcome.project!.path, outcome.path);
  });

  test('pre-cancelled requests allocate nothing and never clone', () async {
    var allocations = 0;
    var clones = 0;
    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: ({required name}) async {
        allocations++;
        return allocate(name: name);
      },
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            clones++;
          },
    );
    final cancellation = GitCloneCancellation()..cancel();
    final outcome = await service.clone(
      const GitCloneRequest(url: 'https://example.invalid/repo.git'),
      cancellation: cancellation,
    );
    cancellation.dispose();
    expect(outcome.cancelled, isTrue);
    expect(allocations, 0);
    expect(clones, 0);
    expect(registry.calls, 0);
  });

  test('overlapping clones isolate cancellation, paths and progress', () async {
    final cancelA = GitCloneCancellation();
    final cancelB = GitCloneCancellation();
    final enteredA = Completer<void>();
    final enteredB = Completer<void>();
    final releaseA = Completer<void>();
    final releaseB = Completer<void>();
    final progressA = <GitCloneProgress>[];
    final progressB = <GitCloneProgress>[];
    String? pathA;
    String? pathB;

    addTearDown(cancelA.dispose);
    addTearDown(cancelB.dispose);
    addTearDown(() {
      if (!releaseA.isCompleted) releaseA.complete();
      if (!releaseB.isCompleted) releaseB.complete();
    });

    final service = GitCloneService(
      store: registry,
      desktop: true,
      allocateDestination: allocate,
      cloneRunner:
          ({
            required url,
            required path,
            credentials,
            cancellation,
            onProgress,
          }) async {
            if (url.endsWith('/a.git')) {
              pathA = path;
              enteredA.complete();
              onProgress?.call(
                const GitCloneProgress(
                  stage: GitCloneStage.receiving,
                  completed: 1,
                  total: 2,
                ),
              );
              await releaseA.future;
              await File(p.join(path, 'source.txt')).writeAsString('a');
            } else {
              pathB = path;
              enteredB.complete();
              onProgress?.call(
                const GitCloneProgress(
                  stage: GitCloneStage.receiving,
                  completed: 2,
                  total: 2,
                ),
              );
              await releaseB.future;
              await File(p.join(path, 'source.txt')).writeAsString('b');
            }
          },
    );

    final futureA = service.clone(
      const GitCloneRequest(url: 'https://example.invalid/a.git'),
      cancellation: cancelA,
      onProgress: progressA.add,
    );
    final futureB = service.clone(
      const GitCloneRequest(url: 'https://example.invalid/b.git'),
      cancellation: cancelB,
      onProgress: progressB.add,
    );

    var overlapObserved = false;
    try {
      await Future.wait(<Future<void>>[
        enteredA.future,
        enteredB.future,
      ]).timeout(const Duration(seconds: 5));
      overlapObserved = true;
    } on TimeoutException {
      // Release both runners below, then await both outcomes before failing.
    } finally {
      cancelA.cancel();
      if (!releaseA.isCompleted) releaseA.complete();
      if (!releaseB.isCompleted) releaseB.complete();
    }

    final outcomes = await Future.wait(<Future<GitCloneOutcome>>[
      futureA,
      futureB,
    ]).timeout(const Duration(seconds: 5));

    expect(overlapObserved, isTrue);

    expect(outcomes.first.cancelled, isTrue);
    expect(outcomes.first.project, isNull);
    expect(outcomes.last.ok, isTrue);
    expect(registry.calls, 1);
    expect(pathA, isNot(pathB));
    expect(await Directory(pathA!).exists(), isFalse);
    expect(await File(p.join(pathB!, 'source.txt')).readAsString(), 'b');
    expect(
      progressA.map((event) => event.stage),
      contains(GitCloneStage.receiving),
    );
    expect(
      progressB.map((event) => event.stage),
      contains(GitCloneStage.receiving),
    );
    expect(progressA, isNot(same(progressB)));
  });

  test(
    'cancellation during allocation releases only its reserved path',
    () async {
      final cancellation = GitCloneCancellation();
      var clones = 0;
      String? reserved;
      final service = GitCloneService(
        store: registry,
        desktop: true,
        allocateDestination: ({required name}) async {
          final destination = await allocate(name: name);
          reserved = destination.path;
          cancellation.cancel();
          return destination;
        },
        cloneRunner:
            ({
              required url,
              required path,
              credentials,
              cancellation,
              onProgress,
            }) async {
              clones++;
            },
      );
      final outcome = await service.clone(
        const GitCloneRequest(url: 'https://example.invalid/repo.git'),
        cancellation: cancellation,
      );
      cancellation.dispose();
      expect(outcome.cancelled, isTrue);
      expect(clones, 0);
      expect(registry.calls, 0);
      expect(await Directory(reserved!).exists(), isFalse);
    },
  );
}

class _Registry extends ProjectStore {
  int calls = 0;
  bool reject = false;

  @override
  Future<ProjectResult> addExisting(String rawPath) async {
    calls++;
    if (reject) return (error: 'registry unavailable', project: null);
    final metadata = ProjectConfig.readMetadata(rawPath);
    return (
      error: null,
      project: Project.create(
        name: metadata.name!,
        path: rawPath,
        language: metadata.language!,
        type: metadata.type!,
      ),
    );
  }
}
