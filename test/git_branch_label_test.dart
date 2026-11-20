import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/git/git_branch_label.dart';

void main() {
  late Directory sandbox;
  late Directory project;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('git_branch_label_test_');
    project = await Directory(p.join(sandbox.path, 'project')).create();
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  test('reads the branch from the project root HEAD with CRLF', () async {
    await _writeHead(p.join(project.path, '.git'), 'ref: refs/heads/main\r\n');

    expect(await readProjectGitBranch(project.path), 'main');
  });

  test('keeps a full unborn branch name without reading a ref', () async {
    await _writeHead(
      p.join(project.path, '.git'),
      'ref: refs/heads/feature/cards/分支\n',
    );
    // There is deliberately no refs directory or commit object.
    expect(await readProjectGitBranch(project.path), 'feature/cards/分支');
  });

  test('resolves a relative gitdir against the project directory', () async {
    final gitDirectory = p.join(
      sandbox.path,
      'metadata',
      'worktrees',
      'project',
    );
    await _writeHead(gitDirectory, 'ref: refs/heads/worktree/relative\n');
    await File(p.join(project.path, '.git')).writeAsString(
      'gitdir: ${p.relative(gitDirectory, from: project.path)}\n',
    );

    expect(await readProjectGitBranch(project.path), 'worktree/relative');
  });

  test('supports an absolute gitdir path containing spaces', () async {
    final gitDirectory = p.join(sandbox.path, 'linked git data', 'project');
    await _writeHead(gitDirectory, 'ref: refs/heads/worktree/absolute\n');
    await File(
      p.join(project.path, '.git'),
    ).writeAsString('gitdir: $gitDirectory\n');

    expect(await readProjectGitBranch(project.path), 'worktree/absolute');
  });

  for (final length in [40, 64]) {
    test('labels a detached $length-digit hexadecimal HEAD', () async {
      final hash = List.filled(
        5,
        'abcdef0123456789',
      ).join().substring(0, length);
      await _writeHead(p.join(project.path, '.git'), '$hash\n');

      expect(await readProjectGitBranch(project.path), '分离 HEAD · abcdef0');
    });
  }

  test('does not discover a repository in a parent directory', () async {
    await _writeHead(p.join(sandbox.path, '.git'), 'ref: refs/heads/parent\n');

    expect(await readProjectGitBranch(project.path), isNull);
    expect(await readProjectGitBranch(p.join(sandbox.path, 'missing')), isNull);
  });

  test('returns null for missing or malformed HEAD metadata', () async {
    final gitDirectory = p.join(project.path, '.git');
    await Directory(gitDirectory).create();
    expect(await readProjectGitBranch(project.path), isNull);

    for (final head in [
      '',
      'ref: refs/heads/\n',
      'ref: refs/tags/v1\n',
      'ref: refs/heads/bad name\n',
      'ref: refs/heads/feature/../main\n',
      'ref: refs/heads/main\nextra\n',
      '${List.filled(39, 'a').join()}\n',
      '${List.filled(40, 'z').join()}\n',
    ]) {
      await _writeHead(gitDirectory, head);
      expect(await readProjectGitBranch(project.path), isNull, reason: head);
    }

    await File(p.join(gitDirectory, 'HEAD')).writeAsBytes([0xff, 0xfe]);
    expect(await readProjectGitBranch(project.path), isNull);
  });

  test('returns null for a broken gitdir file', () async {
    final marker = File(p.join(project.path, '.git'));
    for (final value in [
      '',
      'gitdir: \n',
      'not a gitdir file\n',
      'gitdir: ../missing\n',
      'gitdir: ../metadata\nextra\n',
    ]) {
      await marker.writeAsString(value);
      expect(await readProjectGitBranch(project.path), isNull, reason: value);
    }
  });
}

Future<void> _writeHead(String gitDirectory, String head) async {
  await Directory(gitDirectory).create(recursive: true);
  await File(p.join(gitDirectory, 'HEAD')).writeAsString(head);
}
