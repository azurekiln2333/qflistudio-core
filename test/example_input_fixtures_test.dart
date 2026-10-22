import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/content/local_content_adapter.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/demo_run_service.dart';
import 'package:qfli_studio_core/services/example_code_store.dart';
import 'package:qfli_studio_core/services/example_input_fixtures.dart';
import 'package:qfli_studio_core/services/file_backup.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/tutorial_service.dart';
import 'package:qfli_studio_core/store/project_store.dart';

const _example = ExampleCode(
  id: 'input-example',
  type: 'c',
  title: 'Input',
  summary: '',
  code: '#include <stdio.h>\nint main() { return 0; }\n',
  output: '',
  inputFixtures: {'stdin': '42\r\n', 'data/names.txt': '李明\n'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('qfli_fixture_');
    FileBackup.baseOverride = root.path;
  });
  tearDown(() async {
    FileBackup.baseOverride = null;
    await root.delete(recursive: true);
  });

  test(
    'aggregate and legacy lesson/example projections preserve exact fixtures',
    () async {
      final lesson = {
        'id': 'lesson',
        'code': 'read()',
        'inputFixtures': {'stdin': '甲\r\n'},
      };
      final repository = _Repository(
        _catalog(
          tutorialDocument: {
            'entries': [
              {
                'id': 'tutorial',
                'type': 'c',
                'language': 'c',
                'lessons': [lesson],
              },
            ],
          },
          exampleDocument: {
            'entries': [
              {
                'id': 'example',
                'type': 'c',
                'language': 'c',
                'sourceLessonId': 'lesson',
                'inputFixtures': {'stdin': '42\r\n'},
              },
            ],
          },
        ),
      );
      final tutorial = (await LocalContentAdapter.loadTutorial(
        repository: repository,
        language: 'c',
        displayName: 'C',
      ))!;
      expect(tutorial.allLessons.single.inputFixtures, {'stdin': '甲\r\n'});
      final examples = await LocalContentAdapter.loadExamples(
        repository: repository,
        language: 'c',
      );
      expect(examples.single.copyWith(code: 'edited').inputFixtures, {
        'stdin': '42\r\n',
      });
      final legacy = TutorialService.parse(
        'c',
        jsonEncode({
          'chapters': [
            {
              'lessons': [lesson],
            },
          ],
        }),
      );
      expect(legacy.examples.single.inputFixtures, {'stdin': '甲\r\n'});
    },
  );

  test(
    'legacy aggregate lessons inherit paired fixtures once without losing explicit input',
    () async {
      final repository = _Repository(
        _catalog(
          tutorialDocument: {
            'entries': [
              {
                'id': 'tutorial',
                'type': 'c',
                'language': 'c',
                'lessons': [
                  {'id': 'lesson', 'code': 'read()'},
                ],
              },
            ],
          },
          exampleDocument: {
            'entries': [
              {
                'id': 'example',
                'type': 'c',
                'language': 'c',
                'sourceLessonId': 'lesson',
                'input': '42\n',
              },
            ],
          },
        ),
      );
      final tutorial = (await LocalContentAdapter.loadTutorial(
        repository: repository,
        language: 'c',
        displayName: 'C',
      ))!;
      expect(tutorial.allLessons.single.inputFixtures, {'stdin': '42\n'});
      expect(repository.exampleReads, 1);
    },
  );

  test(
    'saved overrides retain fixtures across write, reload and old metadata fallback',
    () async {
      final file = File(p.join(root.path, 'examples.json'));
      final store = ExampleCodeStore(storageFile: file);
      await store.load(defaults: [_example]);
      await store.upsert(_example.copyWith(code: 'edited'));
      store.dispose();
      final reloaded = ExampleCodeStore(storageFile: file);
      await reloaded.load(defaults: [_example]);
      expect(reloaded.items.single.inputFixtures, _example.inputFixtures);
      await reloaded.importJson(
        jsonEncode({
          'examples': [
            {
              'id': _example.id,
              'type': 'c',
              'title': 'Input',
              'code': 'old saved code',
            },
          ],
        }),
      );
      expect(reloaded.items.single.inputFixtures, _example.inputFixtures);
      reloaded.dispose();
    },
  );

  test(
    'scratch and registered projects materialize root stdin and relative data',
    () async {
      final snippet = await CodeImportService.openInEditor(
        example: _example,
        fileName: 'read.c',
        location: root.path,
      );
      expect(
        File(p.join(snippet.project.path, 'input.txt')).readAsStringSync(),
        '42\r\n',
      );
      expect(
        File(p.join(snippet.project.path, 'data/names.txt')).readAsStringSync(),
        '李明\n',
      );
      final store = ProjectStore(
        storageFile: File(p.join(root.path, 'registry.json')),
      );
      await store.load();
      final created = await store.createProjectFromExample(
        name: 'Input',
        example: _example,
        fileName: 'custom.c',
        location: root.path,
      );
      expect(created.error, isNull);
      expect(
        File(p.join(created.project!.path, 'input.txt')).readAsStringSync(),
        '42\r\n',
      );
      store.dispose();
    },
  );

  test(
    'existing fixture conflict preflights every file and requires replacement',
    () async {
      final project = Project.create(
        name: 'Existing',
        path: root.path,
        type: 'c',
        language: 'C',
      );
      final input = File(p.join(root.path, 'input.txt'))
        ..writeAsStringSync('user input');
      expect(
        CodeImportService.destinationPaths(
          project: project,
          example: _example,
          fileName: 'read.c',
        ),
        contains(input.path),
      );
      await expectLater(
        CodeImportService.importIntoProject(
          project: project,
          example: _example,
          fileName: 'read.c',
        ),
        throwsA(isA<CodeImportException>()),
      );
      expect(input.readAsStringSync(), 'user input');
      expect(Directory(p.join(root.path, 'src')).existsSync(), isFalse);
      await CodeImportService.importIntoProject(
        project: project,
        example: _example,
        fileName: 'read.c',
        overwrite: true,
      );
      expect(input.readAsStringSync(), '42\r\n');
      expect(File(p.join(root.path, 'data/names.txt')).existsSync(), isTrue);
    },
  );

  test(
    'malformed, alias, source and directory conflicts never create partial files',
    () async {
      for (final name in [
        '../escape',
        '/absolute',
        'C:/escape',
        'a/../x',
        'a\\x',
        '.qfli/project.json',
        'NUL.txt',
        'a//x',
      ]) {
        expect(
          () => ExampleInputFixtures.files({name: 'bad'}),
          throwsFormatException,
        );
      }
      expect(
        () => ExampleInputFixtures.files({'stdin': 'a', 'input.txt': 'b'}),
        throwsFormatException,
      );
      expect(
        () => ExampleInputFixtures.files({'a': 'a', 'a/b': 'b'}),
        throwsFormatException,
      );
      final project = Project.create(
        name: 'Existing',
        path: root.path,
        type: 'c',
        language: 'C',
      );
      Directory(p.join(root.path, 'input.txt')).createSync();
      await expectLater(
        CodeImportService.importIntoProject(
          project: project,
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        ),
        throwsA(isA<CodeImportException>()),
      );
      expect(Directory(p.join(root.path, 'src')).existsSync(), isFalse);
      expect(
        () => CodeImportService.projectFiles(
          example: _example,
          entryFile: 'input.txt',
        ),
        throwsA(isA<CodeImportException>()),
      );
    },
  );

  test(
    'a later backup failure rolls back an earlier newly imported source',
    () async {
      final blocked = File(p.join(root.path, 'backup-blocker'))
        ..writeAsStringSync('block');
      FileBackup.baseOverride = blocked.path;
      final input = File(p.join(root.path, 'input.txt'))
        ..writeAsStringSync('user input');
      final project = Project.create(
        name: 'Existing',
        path: root.path,
        type: 'c',
        language: 'C',
      );
      await expectLater(
        CodeImportService.importIntoProject(
          project: project,
          example: _example,
          fileName: 'read.c',
          overwrite: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(input.readAsStringSync(), 'user input');
      expect(File(p.join(root.path, 'src/read.c')).existsSync(), isFalse);
      expect(Directory(p.join(root.path, 'src')).existsSync(), isFalse);
      expect(Directory(p.join(root.path, 'data')).existsSync(), isFalse);
    },
  );

  test(
    'Java direct demo passes fixture to the real runner preparation path',
    () async {
      final previous = StudioProfile.current;
      final runner = _Runner();
      StudioProfile.current = StudioProfile(
        id: 'java',
        appTitle: 'Java',
        templates: const [],
        runner: runner,
        isOffline: true,
      );
      try {
        final session = await DemoRunService.start(
          const ExampleCode(
            id: 'java-input',
            type: 'java',
            title: 'Input',
            summary: '',
            output: '',
            code:
                'public class Main { public static void main(String[] args) {} }',
            inputFixtures: {'stdin': '12\n'},
          ),
          location: root.path,
        );
        expect(runner.input, '12\n');
        await session.dispose();
        expect(session.directory.existsSync(), isFalse);
      } finally {
        StudioProfile.current = previous;
      }
    },
  );
}

class _Repository implements ContentRepository {
  _Repository(this.catalog);
  final ContentCatalog catalog;
  int exampleReads = 0;
  @override
  Future<ContentCatalog> load() async => catalog;
  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async => catalog.tutorials.where(filter.matches).toList();
  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async {
    exampleReads++;
    return catalog.examples.where(filter.matches).toList();
  }
}

class _Runner implements ProgramRunner {
  String? input;
  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    input = await File(p.join(projectPath, 'input.txt')).readAsString();
    return ProgramRunResult(
      title: 'Fixture demo',
      stdout: const Stream.empty(),
      stderr: const Stream.empty(),
      exitCode: Future.value(0),
    );
  }
}

ContentCatalog _catalog({
  required Object tutorialDocument,
  required Object exampleDocument,
}) => ContentCatalog.fromJson(
  tutorialsSource: jsonEncode(tutorialDocument),
  examplesSource: jsonEncode(exampleDocument),
);
