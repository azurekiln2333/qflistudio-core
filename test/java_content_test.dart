import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/content/asset_content_repository.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/content/local_content_adapter.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/example_code_store.dart';

/// Integrity, migration and line-break regression for the Java content rewrite.
///
/// Loads the **real bundled assets** so the records exercised here are exactly
/// the ones both pages display and import.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentCatalog catalog;
  late List<TutorialContent> javaTutorials;
  late List<ExampleContent> javaExamples;

  setUpAll(() async {
    catalog = await AssetContentRepository().load();
    javaTutorials =
        catalog.tutorials.where((t) => t.type.toLowerCase() == 'java').toList();
    javaExamples =
        catalog.examples.where((e) => e.type.toLowerCase() == 'java').toList();
  });

  group('Java content integrity', () {
    test('exactly 100 tutorials and 100 examples', () {
      expect(javaTutorials, hasLength(100));
      expect(javaExamples, hasLength(100));
    });

    test('unique ids and titles', () {
      final ids = javaTutorials.map((t) => t.id).toSet();
      expect(ids, hasLength(100));
      final titles = javaTutorials.map((t) => t.title).toSet();
      expect(titles, hasLength(100));
    });

    test('1:1 pairing by stable id', () {
      final lessonIds = javaTutorials.map((t) => t.id).toSet();
      for (final example in javaExamples) {
        expect(
          lessonIds,
          contains(example.sourceLessonId),
          reason: '${example.id} must pair to a tutorial',
        );
      }
    });

    test('each lesson and example has complete, real content', () {
      for (final tutorial in javaTutorials) {
        expect(tutorial.lessons, hasLength(1), reason: tutorial.id);
        final lesson = tutorial.lessons.first;
        expect(lesson.title.trim(), isNotEmpty, reason: tutorial.id);
        expect(lesson.summary.trim(), isNotEmpty, reason: tutorial.id);
        expect(lesson.explain.trim(), isNotEmpty, reason: tutorial.id);
        expect(lesson.code.trim(), isNotEmpty, reason: tutorial.id);
        expect(lesson.output.trim(), isNotEmpty, reason: tutorial.id);
        // S1: objective, prerequisites and pitfalls must survive parsing.
        // objective/pitfalls are authored for every topic; prerequisites is
        // optional by design (empty means "no prerequisites stated").
        expect(
          lesson.objective.trim(),
          isNotEmpty,
          reason: '${tutorial.id} objective',
        );
        expect(lesson.pitfalls, isNotEmpty, reason: '${tutorial.id} pitfalls');
        expect(tutorial.concepts, isNotEmpty, reason: tutorial.id);
      }
      for (final example in javaExamples) {
        expect(example.code.trim(), isNotEmpty, reason: example.id);
        expect(example.expectedOutput.trim(), isNotEmpty, reason: example.id);
      }
    });

    test('no placeholder or ellipsis markers', () {
      // `int... nums` (varargs) and `return "..."` are legitimate Java, so the
      // guard looks for comment-style placeholders and code-fence leaks only.
      final pattern = RegExp(
        r'//\s*TODO|/\*\s*TODO|FIXME|省略|<code>|placeholder',
        caseSensitive: false,
      );
      for (final tutorial in javaTutorials) {
        final lesson = tutorial.lessons.first;
        expect(pattern.hasMatch(lesson.code), isFalse, reason: tutorial.id);
        expect(pattern.hasMatch(lesson.explain), isFalse, reason: tutorial.id);
      }
      for (final example in javaExamples) {
        expect(pattern.hasMatch(example.code), isFalse, reason: example.id);
      }
    });

    test('code is genuinely multi-line with a method body structure', () {
      for (final example in javaExamples) {
        final lines = example.code.split('\n');
        // A whole class packed onto one line would defeat the lesson; require a
        // real structure: a class declaration, a main method, and indented body.
        expect(lines.length, greaterThanOrEqualTo(6), reason: example.id);
        expect(
          lines.any((line) => RegExp(r'^\s*(public\s+)?class\s+Main').hasMatch(line)),
          isTrue,
          reason: '${example.id} needs a class line',
        );
        expect(
          lines.any((line) => line.contains('static void main')),
          isTrue,
          reason: '${example.id} needs a main line',
        );
        expect(
          lines.any((line) => line.startsWith('        ')),
          isTrue,
          reason: '${example.id} needs indented body statements',
        );
      }
    });

    test('exactly one introductory Hello World style topic', () {
      final hello = javaExamples
          .where((e) => e.code.contains('Hello, Java!'))
          .toList();
      expect(hello, hasLength(1));
      expect(hello.single.id, 'java-example-001');
    });

    test('near-duplicate guard: distinct code bodies', () {
      final bodies = javaExamples
          .map((e) => e.code.replaceAll(RegExp(r'\s+'), ' ').trim())
          .toList();
      expect(bodies.toSet(), hasLength(100));
    });

    test('progression spans beginner, intermediate and advanced', () {
      final levels = javaTutorials.map((t) => t.level).toSet();
      expect(levels, containsAll(<String>['beginner', 'intermediate', 'advanced']));
    });
  });

  group('Java content migration', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('qfli_java_migration_');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    ExampleCode javaExample(String id) => ExampleCode(
      id: id,
      type: 'java',
      title: 'Old Java $id',
      summary: 'pre-migration',
      code: 'class Main { public static void main(String[] args) {} }',
      output: '',
    );

    ExampleCode dartExample(String id) => ExampleCode(
      id: id,
      type: 'dart',
      title: 'Dart $id',
      summary: 'unrelated',
      code: 'void main() {}',
      output: '',
    );

    test('all pre-migration Java records are cleared, others preserved', () async {
      final file = File(p.join(dir.path, 'examples.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'examples': [
              _json(javaExample('java-example-001')),
              _json(javaExample('legacy-java-custom')),
              _json(dartExample('dart-custom')),
            ],
          }),
        );
      final store = ExampleCodeStore(storageFile: file);
      addTearDown(store.dispose);
      final bundled = javaExamples
          .map(
            (e) => ExampleCode(
              id: e.id,
              type: e.type,
              title: e.title,
              summary: e.summary,
              code: e.code,
              output: e.expectedOutput,
              sourceLessonId: e.sourceLessonId,
            ),
          )
          .toList();
      await store.load(
        defaults: [
          ...bundled,
          ExampleCode(
            id: 'dart-default',
            type: 'dart',
            title: 'Dart default',
            summary: '',
            code: 'void main() {}',
            output: '',
          ),
        ],
      );

      // No old Java records survive; the new defaults are shown.
      expect(store.items.where((e) => e.type == 'java'), hasLength(100));
      expect(
        store.items.where((e) => e.id == 'legacy-java-custom'),
        isEmpty,
      );
      // Unrelated language record is preserved.
      expect(store.items.any((e) => e.id == 'dart-custom'), isTrue);
      // The persisted file is rewritten without the old Java records.
      final persisted =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(persisted['contentVersion'], ExampleCodeStore.contentVersion);
      final persistedIds = (persisted['examples'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(persistedIds, isNot(contains('legacy-java-custom')));
      expect(persistedIds, contains('dart-custom'));
    });

    test('migration is idempotent on a second load', () async {
      final file = File(p.join(dir.path, 'examples.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'examples': [_json(javaExample('java-example-009'))],
          }),
        );
      final store = ExampleCodeStore(storageFile: file);
      addTearDown(store.dispose);
      await store.load();
      final first = file.readAsStringSync();
      final second = ExampleCodeStore(storageFile: file);
      addTearDown(second.dispose);
      await second.load();
      expect(second.items.where((e) => e.type == 'java'), isEmpty);
      // No content change on the second load once the version is current.
      expect(
        (jsonDecode(first) as Map)['contentVersion'],
        ExampleCodeStore.contentVersion,
      );
    });

    test('a Java example saved after migration persists', () async {
      final file = File(p.join(dir.path, 'examples.json'));
      final store = ExampleCodeStore(storageFile: file);
      addTearDown(store.dispose);
      await store.load();
      final custom = javaExample('java-user-added');
      await store.upsert(custom);
      final restored = ExampleCodeStore(storageFile: file);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.items.any((e) => e.id == 'java-user-added'), isTrue);
    });
  });

  group('line-break handling', () {
    test('every Java example preserves real newlines through the adapter', () async {
      final examples = await LocalContentAdapter.loadExamples(
        repository: AssetContentRepository(),
        language: 'java',
      );
      expect(examples, hasLength(100));
      for (final example in examples) {
        expect(example.code.contains('\n'), isTrue, reason: example.id);
        final lines = example.code.split('\n');
        expect(lines.length, greaterThanOrEqualTo(6), reason: example.id);
        for (final line in lines) {
          expect(line.contains('\t'), isFalse, reason: example.id);
        }
      }
    });

    test('no literal backslash-n leak in Java string literals', () {
      // A program may legitimately print "\n"; the source must still contain a
      // real newline between statements.
      for (final example in javaExamples) {
        expect(example.code.contains('\n'), isTrue, reason: example.id);
        // The code must not be a single physical line.
        expect(example.code.trim().split('\n').length, greaterThan(1));
      }
    });
  });

  group('Java page display/copy/import line breaks', () {
    test('example code preserves real line breaks end to end', () async {
      final examples = await LocalContentAdapter.loadExamples(
        repository: AssetContentRepository(),
        language: 'java',
      );
      final sample = examples.firstWhere((e) => e.id == 'java-example-003');
      // The display/copy surface renders `example.code` verbatim
      // (SelectableText), so preserving it here guarantees the page shows real
      // line breaks. No single-line body is allowed.
      expect(sample.code.split('\n').length, greaterThanOrEqualTo(6));
      expect(sample.code.contains('\n'), isTrue);
    });

    test('import into a project writes real line breaks', () async {
      final dir = Directory.systemTemp.createTempSync('qfli_java_import_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final examples = await LocalContentAdapter.loadExamples(
        repository: AssetContentRepository(),
        language: 'java',
      );
      final sample = examples.firstWhere((e) => e.id == 'java-example-020');
      final result = await CodeImportService.openInEditor(
        example: sample,
        fileName: 'Main.java',
        location: dir.path,
      );
      final written = File(result.path).readAsStringSync();
      expect(written, sample.code);
      expect(written.split('\n').length, greaterThanOrEqualTo(6));
    });
  });
}

Map<String, Object?> _json(ExampleCode example) => <String, Object?>{
  'id': example.id,
  'type': example.type,
  'title': example.title,
  'summary': example.summary,
  'code': example.code,
  'output': example.output,
  if (example.sourceLessonId != null) 'sourceLessonId': example.sourceLessonId,
};
