import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/git/cli_git_backend.dart';
import 'package:qfli_studio_core/git/git_backend.dart';

// These scenarios execute Git only on the cloud runner. They never use a user
// repository or a network remote. All fixtures live below one temporary root.
void main() {
  const author = GitIdentity(name: 'CI Author', email: 'ci@example.invalid');
  late Directory fixture;
  late Directory repository;
  late CliGitBackend backend;

  Future<String> git(List<String> args, {String? cwd}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: cwd ?? repository.path,
      environment: {'GIT_TERMINAL_PROMPT': '0'},
    );
    if (result.exitCode != 0) {
      throw StateError('Fixture Git failed: ${result.stderr}');
    }
    return result.stdout.toString();
  }

  Future<void> write(String path, String text) async {
    final file = File(p.join(repository.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<String> commit(String text) async {
    await backend.stageAll();
    return backend.commit(text, author);
  }

  group(
    'CLI Git in disposable cloud repositories',
    () {
      setUp(() async {
        fixture = await Directory.systemTemp.createTemp('qfli-git-ci-');
        repository = await Directory(p.join(fixture.path, 'repo')).create();
        await git(['init', '-b', 'main']);
        await git(['config', 'commit.gpgsign', 'false']);
        await git(['config', 'user.name', author.name]);
        await git(['config', 'user.email', author.email]);
        backend = CliGitBackend(repository.path);
      });

      tearDown(() async {
        await backend.dispose();
        await fixture.delete(recursive: true);
      });

      test(
        'unborn stage/unstage is literal and commit uses only the index',
        () async {
          await write('[selected].txt', 'selected\n');
          await write('s.txt', 'unselected\n');
          final empty = await backend.snapshot();
          expect(empty.isRepository, isTrue);
          expect(empty.oid, isNull);
          expect(await backend.history(), isEmpty);

          await backend.stage(['[selected].txt']);
          expect(
            (await backend.snapshot()).changes
                .where((c) => c.staged)
                .map((c) => c.path),
            ['[selected].txt'],
          );
          await backend.unstage(['[selected].txt']);
          expect(await git(['diff', '--cached', '--name-only']), isEmpty);
          expect(
            await File(
              p.join(repository.path, '[selected].txt'),
            ).readAsString(),
            'selected\n',
          );

          await backend.stage(['[selected].txt']);
          final oid = await backend.commit('Only selected', author);
          expect(oid, matches(RegExp(r'^[0-9a-f]{40}$')));
          expect(
            await git(['ls-tree', '--name-only', 'HEAD']),
            '[selected].txt\n',
          );
          expect((await backend.snapshot()).changes.single.path, 's.txt');
        },
      );

      test(
        'diff distinguishes staged/worktree and preserves patch lines',
        () async {
          await write('text.txt', 'base\n');
          await commit('Base');
          await write('text.txt', 'staged\n');
          await backend.stage(['text.txt']);
          await write('text.txt', 'worktree\n');

          final change = (await backend.snapshot()).changes.single;
          expect(change.staged, isTrue);
          expect(change.unstaged, isTrue);
          final staged = await backend.diff(
            'text.txt',
            area: GitChangeArea.staged,
          );
          final worktree = await backend.diff(
            'text.txt',
            area: GitChangeArea.worktree,
          );
          expect(staged.patch, contains('-base'));
          expect(staged.patch, contains('+staged'));
          expect(staged.patch, isNot(contains('+worktree')));
          expect(worktree.patch, contains('-staged'));
          expect(worktree.patch, contains('+worktree'));

          await backend.unstage(['text.txt']);
          expect(await git(['diff', '--cached', '--name-only']), isEmpty);
          expect(
            await File(p.join(repository.path, 'text.txt')).readAsString(),
            'worktree\n',
          );
        },
      );

      test('rename is represented as separate literal index paths', () async {
        await write('old.txt', 'content\n');
        await commit('Base');
        await File(
          p.join(repository.path, 'old.txt'),
        ).rename(p.join(repository.path, 'new.txt'));
        await backend.stageAll();
        final changes = (await backend.snapshot()).changes;
        expect(changes.map((c) => c.path).toSet(), {'old.txt', 'new.txt'});
        expect(changes.every((c) => c.staged), isTrue);
        await backend.unstage(changes.map((c) => c.path).toList());
        expect(await git(['diff', '--cached', '--name-only']), isEmpty);
        expect(await File(p.join(repository.path, 'new.txt')).exists(), isTrue);
      });

      test(
        'branch, remote, push, fetch and clone use real local transport',
        () async {
          await write('文件.txt', 'payload\n');
          final oid = await commit('Initial');
          await backend.createBranch('feature');
          await backend.checkout('feature');
          expect((await backend.snapshot()).branch, 'feature');
          await backend.checkout('main');

          final remote = await Directory(p.join(fixture.path, 'bare')).create();
          await git(['init', '--bare', '-b', 'main'], cwd: remote.path);
          final remoteUrl = remote.uri.toString();
          await backend.setRemote('origin', remoteUrl);
          await backend.push();
          await backend.fetch();
          final snapshot = await backend.snapshot();
          expect(snapshot.remotes.single.url, remoteUrl);
          expect(
            snapshot.branches.any((b) => b.name == 'origin/main' && b.remote),
            isTrue,
          );
          await expectLater(
            backend.checkout('origin/main'),
            throwsA(isA<GitOperationException>()),
          );
          expect((await backend.snapshot()).branch, 'main');

          final destination = await Directory(
            p.join(fixture.path, 'cloned'),
          ).create();
          await CliGitBackend.cloneRepository(
            url: remoteUrl,
            path: destination.path,
          );
          expect(
            await File(p.join(destination.path, '文件.txt')).readAsString(),
            'payload\n',
          );
          expect(
            (await git(['rev-parse', 'HEAD'], cwd: destination.path)).trim(),
            oid,
          );
        },
      );

      test(
        'merge conflict remains visible and completion commits resolved index',
        () async {
          await write('conflict.txt', 'base\n');
          await commit('Base');
          await backend.createBranch('feature');
          await backend.checkout('feature');
          await write('conflict.txt', 'feature\n');
          await commit('Feature');
          await backend.checkout('main');
          await write('conflict.txt', 'main\n');
          await commit('Main');

          expect(
            await backend.merge('feature', author),
            GitMergeResult.conflicts,
          );
          final conflicted = await backend.snapshot();
          expect(conflicted.state, 'merge');
          expect(conflicted.conflicts, ['conflict.txt']);
          await expectLater(
            backend.completeMerge('Unresolved', author),
            throwsA(isA<GitOperationException>()),
          );
          await write('conflict.txt', 'resolved\n');
          await backend.stage(['conflict.txt']);
          await backend.completeMerge('Resolve', author);
          final resolved = await backend.snapshot();
          expect(resolved.state, 'clean');
          expect(resolved.conflicts, isEmpty);
          expect(
            (await git([
              'rev-list',
              '--parents',
              '-n',
              '1',
              'HEAD',
            ])).trim().split(' '),
            hasLength(3),
          );
        },
      );

      test(
        'nested project is refused before a path can target the wrong file',
        () async {
          await write('sub/file.txt', 'base\n');
          await commit('Base');
          final nested = CliGitBackend(p.join(repository.path, 'sub'));
          try {
            final before = await git(['rev-parse', 'HEAD']);
            await write('sub/file.txt', 'changed\n');
            final operations = <Future<dynamic> Function()>[
              () => nested.snapshot(),
              () => nested.init(),
              () => nested.stage(['file.txt']),
              () => nested.unstage(['file.txt']),
              () => nested.stageAll(),
              () => nested.diff('file.txt', area: GitChangeArea.worktree),
              () => nested.history(),
              () => nested.commit('Wrong root', author),
              () => nested.createBranch('wrong-root'),
              () => nested.checkout('main'),
              () => nested.setRemote('bad', 'https://example.invalid/repo.git'),
            ];
            for (final operation in operations) {
              await expectLater(
                operation(),
                throwsA(isA<GitOperationException>()),
              );
            }
            expect(await git(['rev-parse', 'HEAD']), before);
            expect(await git(['diff', '--cached', '--name-only']), isEmpty);
            expect(
              await Directory(p.join(repository.path, 'sub', '.git')).exists(),
              isFalse,
            );
            expect(await git(['remote']), isEmpty);
          } finally {
            await nested.dispose();
          }
        },
      );

      test('a stopped pull is reported as rebase, never as merge', () async {
        await write('conflict.txt', 'base\n');
        await commit('Base');
        final remote = await Directory(p.join(fixture.path, 'remote')).create();
        await git(['init', '--bare', '-b', 'main'], cwd: remote.path);
        await backend.setRemote('origin', remote.uri.toString());
        await backend.push();
        final peerPath = p.join(fixture.path, 'peer');
        await git(['clone', remote.path, peerPath], cwd: fixture.path);
        await File(p.join(peerPath, 'conflict.txt')).writeAsString('remote\n');
        await git(['add', '--', 'conflict.txt'], cwd: peerPath);
        await git([
          '-c',
          'user.name=Peer',
          '-c',
          'user.email=peer@example.invalid',
          '-c',
          'commit.gpgsign=false',
          'commit',
          '-m',
          'Remote change',
        ], cwd: peerPath);
        await git(['push', 'origin', 'main'], cwd: peerPath);
        await write('conflict.txt', 'local\n');
        await commit('Local change');

        await expectLater(
          backend.pullRebase(),
          throwsA(isA<GitOperationException>()),
        );
        final stopped = await backend.snapshot();
        expect(stopped.state, startsWith('rebase'));
        expect(stopped.conflicts, ['conflict.txt']);
        await expectLater(
          backend.completeMerge('Wrong completion', author),
          throwsA(isA<GitOperationException>()),
        );
        expect((await backend.snapshot()).state, startsWith('rebase'));
      });
    },
    skip: Platform.environment['CI'] != 'true'
        ? 'Git scenarios execute only in cloud CI'
        : false,
  );
}
