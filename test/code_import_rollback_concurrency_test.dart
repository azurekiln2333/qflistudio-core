import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/file_backup.dart';

const _example = ExampleCode(
  id: 'rollback-concurrency',
  type: 'c',
  title: 'Input fixture',
  summary: '',
  code: 'int main(void) { return 0; }\r\n',
  output: '',
  inputFixtures: {
    'data/earlier.txt': 'imported fixture\n',
    'stdin': 'imported input\n',
  },
);

void main() {
  late Directory root;
  late String? previousBackupBase;
  setUp(() {
    root = Directory.systemTemp.createTempSync('qfli_import_rollback_');
    previousBackupBase = FileBackup.baseOverride;
    FileBackup.baseOverride = root.path;
  });
  tearDown(() async {
    CodeImportService.beforeProjectFileWriteForTesting = null;
    CodeImportService.beforeProjectFileReplaceForTesting = null;
    CodeImportService.afterProjectFileCreateForTesting = null;
    FileBackup.baseOverride = previousBackupBase;
    await root.delete(recursive: true);
  });

  for (final afterBackup in [false, true]) {
    test(
      'rollback restores a save completed ${afterBackup ? 'after backup' : 'after preflight'} before replacement',
      () async {
        final source = File(p.join(root.path, 'src', 'read.c'));
        source.parent.createSync();
        source.writeAsBytesSync([0, 255, 13, 10, 7]);
        final savedBytes = utf8.encode('用户在替换前保存\r\n');
        final input = File(p.join(root.path, 'input.txt'))
          ..writeAsStringSync('original input');
        final blocker = File(p.join(root.path, 'backup-blocker'))
          ..writeAsStringSync('not a backup directory');
        Future<void> save(String path) async {
          if (p.equals(path, source.path)) {
            await source.writeAsBytes(savedBytes, flush: true);
          }
        }

        CodeImportService.beforeProjectFileWriteForTesting = (path) async {
          if (!afterBackup) await save(path);
          if (p.equals(path, input.path)) {
            FileBackup.baseOverride = blocker.path;
          }
        };
        if (afterBackup) {
          CodeImportService.beforeProjectFileReplaceForTesting = save;
        }
        await expectLater(
          CodeImportService.importIntoProject(
            project: _project(root),
            example: _example,
            fileName: 'read.c',
            overwrite: true,
          ),
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.message,
              'message',
              isNot(contains('rollback conflict')),
            ),
          ),
        );
        expect(source.readAsBytesSync(), savedBytes);
        expect(input.readAsStringSync(), 'original input');
        expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
      },
    );
  }

  test(
    'rollback keeps a deletion completed after backup before replacement',
    () async {
      final source = File(p.join(root.path, 'src', 'read.c'));
      source.parent.createSync();
      source.writeAsStringSync('original source');
      final input = File(p.join(root.path, 'input.txt'))
        ..writeAsStringSync('original input');
      final blocker = File(p.join(root.path, 'backup-blocker'))
        ..writeAsStringSync('not a backup directory');
      CodeImportService.beforeProjectFileReplaceForTesting = (path) async {
        if (p.equals(path, source.path)) await source.delete();
      };
      CodeImportService.beforeProjectFileWriteForTesting = (path) async {
        if (p.equals(path, input.path)) FileBackup.baseOverride = blocker.path;
      };
      await expectLater(
        CodeImportService.importIntoProject(
          project: _project(root),
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(source.existsSync(), isFalse);
      expect(input.readAsStringSync(), 'original input');
      expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
    },
  );

  test('a file created after preflight still requires replacement', () async {
    final source = File(p.join(root.path, 'src', 'read.c'));
    final savedBytes = utf8.encode('concurrently created source');
    CodeImportService.beforeProjectFileWriteForTesting = (path) async {
      if (p.equals(path, source.path)) {
        await source.writeAsBytes(savedBytes, flush: true);
      }
    };
    await expectLater(
      CodeImportService.importIntoProject(
        project: _project(root),
        example: _example,
        fileName: 'read.c',
      ),
      throwsA(
        isA<CodeImportException>().having(
          (error) => error.reason,
          'reason',
          CodeImportFailure.fileExists,
        ),
      ),
    );
    expect(source.readAsBytesSync(), savedBytes);
    expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'input.txt')).existsSync(), isFalse);
  });

  test(
    'a save queued at name reservation sees complete content and survives rollback',
    () async {
      final source = File(p.join(root.path, 'src', 'read.c'));
      final savedBytes = utf8.encode('saved after new import\r\n');
      final saved = Completer<void>();
      List<int>? beforeSave;
      final input = File(p.join(root.path, 'input.txt'))
        ..writeAsStringSync('original input');
      final blocker = File(p.join(root.path, 'backup-blocker'))
        ..writeAsStringSync('not a backup directory');
      CodeImportService.afterProjectFileCreateForTesting = (path) {
        if (!p.equals(path, source.path)) return;
        scheduleMicrotask(() {
          try {
            beforeSave = source.readAsBytesSync();
            source.writeAsBytesSync(savedBytes, flush: true);
            saved.complete();
          } catch (error, stack) {
            saved.completeError(error, stack);
          }
        });
      };
      CodeImportService.beforeProjectFileWriteForTesting = (path) async {
        if (!p.equals(path, input.path)) return;
        await saved.future.timeout(const Duration(seconds: 5));
        FileBackup.baseOverride = blocker.path;
      };
      await expectLater(
        CodeImportService.importIntoProject(
          project: _project(root),
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        ),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('rollback conflict'),
          ),
        ),
      );
      expect(beforeSave, utf8.encode(_example.code));
      expect(source.readAsBytesSync(), savedBytes);
      expect(input.readAsStringSync(), 'original input');
      expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
    },
  );

  for (final state in ['empty', 'changed', 'partial']) {
    final changed = state != 'empty';
    test(
      'failed new write ${changed ? 'preserves $state content' : 'removes its empty reservation'}',
      () async {
        final source = File(p.join(root.path, 'src', 'read.c'));
        final changedBytes = state == 'partial'
            ? utf8.encode(_example.code).sublist(0, 6)
            : utf8.encode('another writer completed this save');
        CodeImportService.afterProjectFileCreateForTesting = (path) {
          if (!p.equals(path, source.path)) return;
          if (changed) source.writeAsBytesSync(changedBytes, flush: true);
          throw const FileSystemException('injected new write failure');
        };
        await expectLater(
          CodeImportService.importIntoProject(
            project: _project(root),
            example: _example,
            fileName: 'read.c',
          ),
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.message,
              'message',
              changed
                  ? contains('cleanup conflict')
                  : isNot(contains('cleanup conflict')),
            ),
          ),
        );
        expect(source.existsSync(), changed);
        if (changed) {
          expect(source.readAsBytesSync(), changedBytes);
        } else {
          expect(source.parent.existsSync(), isFalse);
        }
        expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
        expect(File(p.join(root.path, 'input.txt')).existsSync(), isFalse);
      },
    );
  }

  for (final existing in [false, true]) {
    test(
      'a late linked parent cannot redirect a ${existing ? 'replacement' : 'new file'} outside its root',
      () async {
        final outside = Directory.systemTemp.createTempSync(
          'qfli_import_outside_',
        );
        final source = File(p.join(root.path, 'src', 'read.c'));
        source.parent.createSync();
        if (existing) source.writeAsStringSync('original source');
        final outsideFile = File(p.join(outside.path, 'read.c'))
          ..writeAsStringSync('outside source');
        final link = Link(source.parent.path);
        final moved = p.join(root.path, 'saved-src');
        try {
          // Probe capability before mutating the project directory on this host.
          final probe = Link(p.join(root.path, 'link-probe'));
          try {
            probe.createSync(outside.path);
            probe.deleteSync();
          } on FileSystemException {
            markTestSkipped('Host cannot create directory symbolic links');
            return;
          }
          CodeImportService.beforeProjectFileWriteForTesting = (path) async {
            if (!p.equals(path, source.path)) return;
            source.parent.renameSync(moved);
            link.createSync(outside.path);
          };
          await expectLater(
            CodeImportService.importIntoProject(
              project: _project(root),
              example: _example,
              fileName: 'read.c',
              overwrite: true,
            ),
            throwsA(
              isA<CodeImportException>().having(
                (error) => error.reason,
                'reason',
                CodeImportFailure.projectUnavailable,
              ),
            ),
          );
          expect(outsideFile.readAsStringSync(), 'outside source');
          final original = File(p.join(moved, 'read.c'));
          expect(original.existsSync(), existing);
          if (existing) expect(original.readAsStringSync(), 'original source');
          expect(outside.listSync().map((file) => p.basename(file.path)), [
            'read.c',
          ]);
        } finally {
          if (link.existsSync()) link.deleteSync();
          await outside.delete(recursive: true);
        }
      },
    );
  }

  for (final existing in [false, true]) {
    test(
      'later backup failure preserves concurrent save of ${existing ? 'replaced' : 'new'} source',
      () async {
        final source = File(p.join(root.path, 'src', 'read.c'));
        if (existing) {
          source.parent.createSync();
          source.writeAsBytesSync([0, 255, 13, 10, 7]);
        }
        final input = File(p.join(root.path, 'input.txt'))
          ..writeAsStringSync('original input');
        final blocker = File(p.join(root.path, 'backup-blocker'))
          ..writeAsStringSync('not a backup directory');
        final reachedFixture = Completer<void>();
        final continueImport = Completer<void>();
        CodeImportService.beforeProjectFileWriteForTesting = (path) async {
          if (!p.equals(path, input.path)) return;
          reachedFixture.complete();
          await continueImport.future;
          FileBackup.baseOverride = blocker.path;
        };
        final import = CodeImportService.importIntoProject(
          project: _project(root),
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        );
        final failed = expectLater(
          import,
          throwsA(
            isA<FileSystemException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('rollback conflict'),
                )
                .having(
                  (error) => error.message,
                  'preserved file',
                  contains(source.path),
                ),
          ),
        );
        await reachedFixture.future.timeout(const Duration(seconds: 5));
        expect(source.readAsBytesSync(), utf8.encode(_example.code));
        // A real writer completes while the import waits before the next file.
        final userBytes = utf8.encode('用户已保存的修改\r\n');
        await source.writeAsBytes(userBytes, flush: true);
        continueImport.complete();
        await failed;
        expect(source.readAsBytesSync(), userBytes);
        expect(input.readAsStringSync(), 'original input');
        expect(source.parent.existsSync(), isTrue);
        expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
        expect(
          root
              .listSync(recursive: true)
              .where(
                (entry) =>
                    p.basename(entry.path).startsWith('.qfli-code-import-'),
              ),
          isEmpty,
        );
      },
    );
  }

  test(
    'unchanged replaced source still rolls back its exact original bytes',
    () async {
      final source = File(p.join(root.path, 'src', 'read.c'));
      source.parent.createSync();
      final original = [0, 255, 13, 10, 7];
      source.writeAsBytesSync(original);
      final input = File(p.join(root.path, 'input.txt'))
        ..writeAsStringSync('original input');
      final blocker = File(p.join(root.path, 'backup-blocker'))
        ..writeAsStringSync('not a backup directory');
      CodeImportService.beforeProjectFileWriteForTesting = (path) async {
        if (p.equals(path, input.path)) FileBackup.baseOverride = blocker.path;
      };
      await expectLater(
        CodeImportService.importIntoProject(
          project: _project(root),
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        ),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            isNot(contains('rollback conflict')),
          ),
        ),
      );
      expect(source.readAsBytesSync(), original);
      expect(input.readAsStringSync(), 'original input');
      expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
    },
  );

  test(
    'rollback does not resurrect a concurrently deleted original source',
    () async {
      final source = File(p.join(root.path, 'src', 'read.c'));
      source.parent.createSync();
      source.writeAsStringSync('original source');
      final input = File(p.join(root.path, 'input.txt'))
        ..writeAsStringSync('original input');
      final blocker = File(p.join(root.path, 'backup-blocker'))
        ..writeAsStringSync('not a backup directory');
      CodeImportService.beforeProjectFileWriteForTesting = (path) async {
        if (!p.equals(path, input.path)) return;
        await source.delete();
        FileBackup.baseOverride = blocker.path;
      };
      await expectLater(
        CodeImportService.importIntoProject(
          project: _project(root),
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        ),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('rollback conflict'),
          ),
        ),
      );
      expect(source.existsSync(), isFalse);
      expect(input.readAsStringSync(), 'original input');
      expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
    },
  );
}

Project _project(Directory root) =>
    Project.create(name: 'Existing', path: root.path, type: 'c', language: 'C');
