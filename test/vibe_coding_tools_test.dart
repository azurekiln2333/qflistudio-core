import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vibe-tools-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  VibeProjectFiles files() => VibeProjectFiles(projectRoot: root.path);

  Future<void> put(String relative, String content) async {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  group('path confinement', () {
    test('rejects absolute, parent traversal and NUL', () {
      final guard = files();
      expect(
        () => guard.resolve('/etc/passwd'),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'escape'),
        ),
      );
      expect(
        () => guard.resolve('C:\\Windows\\system32'),
        throwsA(isA<VibeToolException>()),
      );
      expect(
        () => guard.resolve('src/../../outside.py'),
        throwsA(isA<VibeToolException>()),
      );
      expect(
        () => guard.resolve('src/\u0000evil.py'),
        throwsA(isA<VibeToolException>()),
      );
      expect(
        () => guard.resolve('src/./a.py'),
        throwsA(isA<VibeToolException>()),
      );
    });

    test('maps . and an empty path to the project root', () {
      final guard = files();
      final root = guard.projectRoot;
      expect(guard.resolve(''), root);
      expect(guard.resolve('.'), root);
      expect(guard.resolve('./'), root);
      expect(guard.resolve(' . '), root);
    });

    test('protects metadata directories case-insensitively', () {
      final guard = files();
      for (final path in [
        '.qfli/project.json',
        '.QFLI/project.json',
        '.Git/config',
      ]) {
        expect(
          () => guard.resolve(path),
          throwsA(
            isA<VibeToolException>().having((e) => e.code, 'code', 'protected'),
          ),
        );
      }
    });

    test('rejects a symlink escape', () {
      final outside = Directory.systemTemp.createTempSync('vibe-outside-');
      try {
        File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
        final link = p.join(root.path, 'link');
        try {
          Link(link).createSync(outside.path);
        } on FileSystemException {
          // Some Windows hosts need privileges; skip when creation is refused.
          return;
        }
        expect(
          () => files().resolve('link/secret.txt'),
          throwsA(
            isA<VibeToolException>().having((e) => e.code, 'code', 'escape'),
          ),
        );
      } finally {
        outside.deleteSync(recursive: true);
      }
    });
  });

  group('read/write/edit', () {
    test('creates files and parent directories', () async {
      final result = await files().write('src/pkg/main.py', 'print(1)\n');
      expect(result.created, isTrue);
      expect(result.relativePath, 'src/pkg/main.py');
      expect(
        File(p.join(root.path, 'src', 'pkg', 'main.py')).readAsStringSync(),
        'print(1)\n',
      );
      expect(result.backupPath, isNull);
    });

    test('requires read before overwriting an existing file', () async {
      await put('main.py', 'x = 1\n');
      final guard = files();
      await expectLater(
        guard.write('main.py', 'x = 2\n'),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'not_read'),
        ),
      );
      expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 1\n');
    });

    test('overwrites after read and backs up the previous content', () async {
      await put('main.py', 'x = 1\n');
      final guard = files();
      expect(await guard.read('main.py'), 'x = 1\n');
      final result = await guard.write('main.py', 'x = 2\n');
      expect(result.created, isFalse);
      expect(result.backupPath, isNotNull);
      expect(File(result.backupPath!).readAsStringSync(), 'x = 1\n');
      expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 2\n');
      // Backup metadata travels with the copy.
      final sidecar = File('${result.backupPath!}.json');
      expect(jsonDecode(sidecar.readAsStringSync())['path'], 'main.py');
    });

    test('detects a concurrent disk change and refuses to write', () async {
      await put('main.py', 'x = 1\n');
      final guard = files();
      await guard.read('main.py');
      await put('main.py', 'x = 9\n');
      await expectLater(
        guard.write('main.py', 'x = 2\n'),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'conflict'),
        ),
      );
      expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 9\n');
    });

    test(
      'edit replaces one exact match and refuses ambiguous matches',
      () async {
        await put('main.py', 'a = 1\nb = 1\n');
        final guard = files();
        await guard.read('main.py');
        await expectLater(
          guard.edit('main.py', '= 1', '= 2'),
          throwsA(
            isA<VibeToolException>().having((e) => e.code, 'code', 'ambiguous'),
          ),
        );
        final result = await guard.edit('main.py', 'b = 1', 'b = 2');
        expect(result.relativePath, 'main.py');
        expect(
          File(p.join(root.path, 'main.py')).readAsStringSync(),
          'a = 1\nb = 2\n',
        );
      },
    );

    test('edit reports missing text without touching the file', () async {
      await put('main.py', 'x = 1\n');
      final guard = files();
      await guard.read('main.py');
      await expectLater(
        guard.edit('main.py', 'nope', 'y'),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'no_match'),
        ),
      );
      expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 1\n');
    });

    test(
      'rejects binary and non-UTF8 files instead of corrupting them',
      () async {
        File(
          p.join(root.path, 'blob.bin'),
        ).writeAsBytesSync([0xff, 0xfe, 0x00, 0x01]);
        final guard = files();
        await expectLater(
          guard.read('blob.bin'),
          throwsA(
            isA<VibeToolException>().having((e) => e.code, 'code', 'binary'),
          ),
        );
        await expectLater(
          guard.write('blob.bin', 'text'),
          throwsA(isA<VibeToolException>()),
        );
        expect(File(p.join(root.path, 'blob.bin')).readAsBytesSync(), [
          0xff,
          0xfe,
          0x00,
          0x01,
        ]);
      },
    );

    test('bounds read and write sizes', () async {
      await put('big.txt', 'a' * (300 * 1024));
      final guard = files();
      await expectLater(
        guard.read('big.txt'),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'too_large'),
        ),
      );
      await expectLater(
        guard.write('new.txt', 'b' * (300 * 1024)),
        throwsA(isA<VibeToolException>()),
      );
    });

    test('createOnly never overwrites', () async {
      await put('main.py', 'x = 1\n');
      final guard = files();
      await expectLater(
        guard.write('main.py', 'x = 2\n', createOnly: true),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'exists'),
        ),
      );
    });
  });

  group('list and snapshot', () {
    test('list skips hidden and dependency directories', () async {
      await put('src/a.py', 'a');
      await put('node_modules/pkg/index.js', 'x');
      await put('.hidden/secret.txt', 'x');
      await put('build/out.bin', 'x');
      final entries = await files().list();
      expect(entries.map((e) => e['path']), contains('src'));
      expect(entries.map((e) => e['path']), isNot(contains('node_modules')));
      expect(entries.map((e) => e['path']), isNot(contains('.hidden')));
      expect(entries.map((e) => e['path']), isNot(contains('build')));
      final src = await files().list(path: 'src');
      expect(src.single['path'], 'src/a.py');
      expect(src.single['bytes'], 1);
    });

    test('snapshot encodes files as bounded base64 without symlinks', () async {
      await put('main.py', 'print("hi")\n');
      await put('node_modules/dep.js', 'x');
      final snapshot = await VibeProjectSnapshot.collect(root.path);
      expect(snapshot.single['path'], 'main.py');
      expect(
        utf8.decode(base64Decode(snapshot.single['content']!)),
        'print("hi")\n',
      );
    });

    test('snapshot rejects more than 64 files and more than 256 KiB', () async {
      for (var i = 0; i < 65; i++) {
        await put('f$i.txt', 'x');
      }
      await expectLater(
        VibeProjectSnapshot.collect(root.path),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'too_large'),
        ),
      );

      root.deleteSync(recursive: true);
      root.createSync();
      await put('big.txt', 'a' * (300 * 1024));
      await expectLater(
        VibeProjectSnapshot.collect(root.path),
        throwsA(isA<VibeToolException>()),
      );
    });
  });

  group('concurrency and commit guard', () {
    Future<String> attempt(Future<void> Function() action) async {
      try {
        await action();
        return 'ok';
      } on VibeToolException catch (error) {
        return error.code;
      }
    }

    test('serializes concurrent writes from two instances', () async {
      await put('main.py', 'x = 1\n');
      final first = files();
      final second = files();
      await first.read('main.py');
      await second.read('main.py');
      final results = await Future.wait([
        attempt(() => first.write('main.py', 'x = 2\n')),
        attempt(() => second.write('main.py', 'x = 3\n')),
      ]);
      expect(results.where((value) => value == 'ok'), hasLength(1));
      expect(results.where((value) => value == 'conflict'), hasLength(1));
      final current = File(p.join(root.path, 'main.py')).readAsStringSync();
      expect(current, anyOf('x = 2\n', 'x = 3\n'));
    });

    test('createOnly is atomic across instances', () async {
      final first = files();
      final second = files();
      final results = await Future.wait([
        attempt(() => first.write('new.txt', 'a', createOnly: true)),
        attempt(() => second.write('new.txt', 'b', createOnly: true)),
      ]);
      expect(results.where((value) => value == 'ok'), hasLength(1));
      expect(results.where((value) => value == 'exists'), hasLength(1));
      expect(
        File(p.join(root.path, 'new.txt')).readAsStringSync(),
        anyOf('a', 'b'),
      );
    });

    test(
      'shouldWrite runs at the commit point and refuses the write',
      () async {
        await put('main.py', 'x = 1\n');
        var asked = 0;
        final guard = VibeProjectFiles(
          projectRoot: root.path,
          shouldWrite: (_) {
            asked++;
            return false;
          },
        );
        await guard.read('main.py');
        await expectLater(
          guard.write('main.py', 'x = 2\n'),
          throwsA(
            isA<VibeToolException>().having((e) => e.code, 'code', 'conflict'),
          ),
        );
        expect(asked, 1);
        expect(
          File(p.join(root.path, 'main.py')).readAsStringSync(),
          'x = 1\n',
        );
      },
    );

    test('shouldWrite refuses a create before any file appears', () async {
      final guard = VibeProjectFiles(
        projectRoot: root.path,
        shouldWrite: (_) => false,
      );
      await expectLater(
        guard.write('draft.txt', 'x', createOnly: true),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'conflict'),
        ),
      );
      expect(File(p.join(root.path, 'draft.txt')).existsSync(), isFalse);
    });

    test('alias root lists and shares the physical write queue', () async {
      await put('main.py', 'x = 1\n');
      final host = Directory.systemTemp.createTempSync('vibe-alias-');
      final linkPath = p.join(host.path, 'project');
      try {
        try {
          Link(linkPath).createSync(root.path);
        } on FileSystemException {
          return;
        }
        final alias = VibeProjectFiles(projectRoot: linkPath);
        expect(
          (await alias.list()).map((entry) => entry['path']),
          contains('main.py'),
        );
        final real = files();
        await real.read('main.py');
        await alias.read('main.py');
        final results = await Future.wait([
          attempt(() => real.write('main.py', 'x = 2\n')),
          attempt(() => alias.write('main.py', 'x = 3\n')),
        ]);
        expect(results.where((value) => value == 'ok'), hasLength(1));
        expect(results.where((value) => value == 'conflict'), hasLength(1));
      } finally {
        host.deleteSync(recursive: true);
      }
    });

    test('refuses backups when .qfli is a link outside the project', () async {
      final outside = Directory.systemTemp.createTempSync('vibe-backup-out-');
      try {
        await put('main.py', 'x = 1\n');
        try {
          Link(p.join(root.path, '.qfli')).createSync(outside.path);
        } on FileSystemException {
          return;
        }
        final guard = files();
        await guard.read('main.py');
        await expectLater(
          guard.write('main.py', 'x = 2\n'),
          throwsA(
            isA<VibeToolException>().having((e) => e.code, 'code', 'backup'),
          ),
        );
        expect(
          File(p.join(root.path, 'main.py')).readAsStringSync(),
          'x = 1\n',
        );
        expect(outside.listSync(), isEmpty);
      } finally {
        outside.deleteSync(recursive: true);
      }
    });
  });

  group('tool specs', () {
    test('expose every tool with object parameter schemas', () {
      final specs = vibeToolSpecs();
      expect(specs.map((s) => (s['function'] as Map)['name']).toList(), [
        'list_files',
        'read_file',
        'write_file',
        'edit_file',
        'run_command',
        'todo',
        'use_skill',
      ]);
      for (final spec in specs) {
        final function = spec['function'] as Map;
        expect(function['description'], isA<String>());
        expect((function['parameters'] as Map)['type'], 'object');
      }
    });
  });
}
