import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/vibe_editor_bridge.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';

/// The agent must never overwrite text that only lives in an editor buffer.
/// These checks run in the tool thread *before* disk access, so a refused write
/// leaves both the buffer and the file untouched.
void main() {
  late Directory root;
  late Set<String> dirty;
  late EditorGuardedProjectFiles files;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vibe_bridge_');
    dirty = <String>{};
    files = EditorGuardedProjectFiles(
      projectRoot: root.path,
      hasUnsavedEdits: (absolute) => dirty.contains(p.normalize(absolute)),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> seed(String name, String content) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  Future<String> read(String name) =>
      File(p.join(root.path, name)).readAsString();

  test('write refuses a dirty buffer and leaves disk untouched', () async {
    final path = await seed('main.dart', 'user draft');
    await files.read('main.dart');
    dirty.add(p.normalize(path));

    await expectLater(
      files.write('main.dart', 'agent content'),
      throwsA(
        isA<VibeToolException>()
            .having((e) => e.code, 'code', 'conflict')
            .having((e) => e.message, 'message', contains('未保存')),
      ),
    );
    expect(await read('main.dart'), 'user draft');
  });

  test('edit refuses a dirty buffer before matching text', () async {
    final path = await seed('a.py', 'print(1)');
    await files.read('a.py');
    dirty.add(p.normalize(path));

    await expectLater(
      files.edit('a.py', 'print(1)', 'print(2)'),
      throwsA(
        isA<VibeToolException>().having((e) => e.code, 'code', 'conflict'),
      ),
    );
    expect(await read('a.py'), 'print(1)');
  });

  test('clean buffer writes succeed and are reported', () async {
    await seed('main.dart', 'old');
    await files.read('main.dart');

    final result = await files.write('main.dart', 'new');
    expect(result.created, isFalse);
    // The backup lives inside the project and is not the live file.
    expect(result.backupPath, isNotNull);
    expect(await read('main.dart'), 'new');
  });

  test('a new file does not need a prior read', () async {
    final result = await files.write('src/util.dart', 'void main() {}');
    expect(result.created, isTrue);
    expect(await read('src/util.dart'), 'void main() {}');
  });

  test('dirty guard does not block a path outside the editor set', () async {
    final path = await seed('b.dart', 'x');
    await files.read('b.dart');
    dirty.add(p.normalize(p.join(root.path, 'other.dart')));
    final result = await files.write('b.dart', 'y');
    expect(result.relativePath, 'b.dart');
    expect(p.normalize(path), p.normalize(p.join(root.path, 'b.dart')));
  });

  test(
    'commit-time guard refuses when the buffer turns dirty mid-write',
    () async {
      await seed('late.txt', 'disk');
      await files.read('late.txt');
      // First call (eager check) is clean; the commit-time check sees dirty and
      // must still refuse, leaving the disk copy intact.
      var calls = 0;
      final guarded = EditorGuardedProjectFiles(
        projectRoot: root.path,
        hasUnsavedEdits: (_) {
          calls++;
          return calls >= 2;
        },
      );
      await guarded.read('late.txt');
      await expectLater(
        guarded.write('late.txt', 'agent'),
        throwsA(
          isA<VibeToolException>().having((e) => e.code, 'code', 'conflict'),
        ),
      );
      expect(await read('late.txt'), 'disk');
    },
  );

  test('disk changes outside the session still conflict', () async {
    await seed('c.txt', 'one');
    await files.read('c.txt');
    await File(p.join(root.path, 'c.txt')).writeAsString('external');

    await expectLater(
      files.write('c.txt', 'agent'),
      throwsA(
        isA<VibeToolException>().having((e) => e.code, 'code', 'conflict'),
      ),
    );
    expect(await read('c.txt'), 'external');
  });
}
