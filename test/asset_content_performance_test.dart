import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/content/asset_content_repository.dart';
import 'package:qfli_studio_core/content/content_repository.dart';

import 'support/content_catalog_fixture.dart';

const _tutorialKey =
    'packages/qfli_studio_core/${AssetContentRepository.tutorialAsset}';
const _exampleKey =
    'packages/qfli_studio_core/${AssetContentRepository.exampleAsset}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent load and filtered queries share one complete catalog',
    () async {
      final release = Completer<void>();
      final bundle = _StringBundle({
        _tutorialKey: tutorialSource,
        _exampleKey: exampleSource,
      }, release: release.future);
      final repository = AssetContentRepository(bundle: bundle);
      final load = repository.load();
      final tutorials = repository.tutorials(
        filter: const ContentFilter(language: 'java'),
      );
      final examples = repository.examples(
        filter: ContentFilter.forProduct('jvmx'),
      );

      expect(repository.load(), same(load));
      // Both reads must start before either can complete. Sequential loading
      // fails here without requiring any wall-clock performance threshold.
      expect(bundle.requests, {_tutorialKey: 1, _exampleKey: 1});
      release.complete();

      final catalog = await load;
      final javaTutorials = await tutorials;
      final javaExamples = await examples;
      expect(catalog.schemaVersion, 1);
      expect(catalog.tutorials, hasLength(3));
      expect(catalog.examples, hasLength(101));
      expect(javaTutorials, hasLength(2));
      expect(javaExamples, hasLength(100));
      expect(javaTutorials.first, same(catalog.tutorials.first));
      expect(javaExamples.last, same(catalog.examples[99]));
      expect(await repository.load(), same(catalog));
      expect(bundle.requests, {_tutorialKey: 1, _exampleKey: 1});

      final tutorial = javaTutorials.last;
      expect(tutorial.id, 'java-chapter-1');
      expect(tutorial.language, 'java');
      expect(tutorial.type, 'java');
      expect(tutorial.locale, 'en');
      expect(tutorial.level, 'beginner');
      expect(tutorial.title, 'Java chapter 1');
      expect(tutorial.summary, 'Learn output');
      expect(tutorial.concepts, ['output']);
      expect(tutorial.source, 'test-fixture');
      expect(tutorial.license, 'CC BY 4.0');
      expect(tutorial.updatedAt, '2026-10-15');
      expect(tutorial.hasExplicitId, isTrue);
      expect(tutorial.hasExplicitLanguage, isTrue);
      expect(tutorial.hasExplicitType, isTrue);
      expect(tutorial.lessons, hasLength(50));
      final lesson = tutorial.lessons.last;
      expect(lesson.id, 'java-lesson-1-49');
      expect(lesson.title, 'Java lesson 1-49');
      expect(lesson.summary, 'Lesson summary 1-49');
      expect(lesson.concepts, ['output']);
      expect(lesson.explain, 'Explanation 1-49');
      expect(lesson.code, 'System.out.println("1-49");');
      expect(lesson.output, '1-49');
      expect(lesson.objective, 'Print a value');
      expect(lesson.prerequisites, ['main']);
      expect(lesson.pitfalls, ['Missing semicolon']);
      expect(lesson.exercises.single.prompt, 'Change the value');
      expect(lesson.exercises.single.hint, 'Edit the string');
      expect(lesson.exercises.single.answer, 'Another value');
      final example = javaExamples.last;
      expect(example.id, 'java-example-99');
      expect(example.title, 'Java example 99');
      expect(example.summary, 'Example summary 99');
      expect(example.code, 'System.out.println("example 99");');
      expect(example.expectedOutput, 'example 99');
      expect(example.inputFixtures, {'stdin': 'Ada\n'});
      expect(example.templateType, 'java');
      expect(example.sourceLessonId, lesson.id);
    },
  );

  for (final document in ['tutorials', 'examples']) {
    for (final malformed in {
      'invalid JSON': '{broken JSON',
      'invalid entries': '{"entries":42}',
    }.entries) {
      test(
        '$document ${malformed.key} retains its type, details and cache',
        () async {
          final source = malformed.value;
          final tutorials = document == 'tutorials' ? source : tutorialSource;
          final examples = document == 'examples' ? source : exampleSource;
          late ContentFormatException expected;
          try {
            ContentCatalog.fromJson(
              tutorialsSource: tutorials,
              examplesSource: examples,
            );
            fail('The invalid document must fail to parse');
          } on ContentFormatException catch (error) {
            expected = error;
          }
          final bundle = _StringBundle({
            _tutorialKey: tutorials,
            _exampleKey: examples,
          });
          final repository = AssetContentRepository(bundle: bundle);
          final load = repository.load();
          final failure = throwsA(
            isA<ContentFormatException>()
                .having(
                  (error) => error.document,
                  'document',
                  expected.document,
                )
                .having((error) => error.message, 'message', expected.message),
          );
          await Future.wait([
            expectLater(load, failure),
            expectLater(repository.tutorials(), failure),
            expectLater(repository.examples(), failure),
          ]);
          expect(repository.load(), same(load));
          await expectLater(repository.load(), failure);
          expect(bundle.requests, {_tutorialKey: 1, _exampleKey: 1});
        },
      );
    }
  }

  test(
    'missing assets retain package/local fallback failure details',
    () async {
      final bundle = _StringBundle({_exampleKey: exampleSource});
      final repository = AssetContentRepository(bundle: bundle);
      final failure = throwsA(
        isA<ContentAssetException>()
            .having(
              (error) => error.asset,
              'asset',
              AssetContentRepository.tutorialAsset,
            )
            .having((error) => error.failures, 'failures', [
              '$_tutorialKey: Missing test asset: $_tutorialKey',
              '${AssetContentRepository.tutorialAsset}: Missing test asset: '
                  '${AssetContentRepository.tutorialAsset}',
            ]),
      );
      final load = repository.load();
      await expectLater(load, failure);
      expect(repository.load(), same(load));
      await expectLater(repository.examples(), failure);
      expect(bundle.requests, {
        _tutorialKey: 1,
        AssetContentRepository.tutorialAsset: 1,
        _exampleKey: 1,
      });
    },
  );
}

class _StringBundle extends AssetBundle {
  _StringBundle(this.sources, {this.release});

  final Map<String, String> sources;
  final Future<void>? release;
  final Map<String, int> requests = {};

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    requests.update(key, (count) => count + 1, ifAbsent: () => 1);
    await release;
    final source = sources[key];
    if (source == null) throw FlutterError('Missing test asset: $key');
    return source;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}
