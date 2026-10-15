import 'dart:convert';

import 'package:qfli_studio_core/content/content_repository.dart';

/// Two Java groups with a hundred lessons/examples, plus excluded Python rows.
final tutorialSource = jsonEncode({
  'schemaVersion': 1,
  'entries': [
    for (var chapter = 0; chapter < 2; chapter++)
      {
        ..._metadata('java-chapter-$chapter'),
        'title': 'Java chapter $chapter',
        'lessons': [
          for (var lesson = 0; lesson < 50; lesson++)
            {
              'id': 'java-lesson-$chapter-$lesson',
              'title': 'Java lesson $chapter-$lesson',
              'summary': 'Lesson summary $chapter-$lesson',
              'concepts': ['output'],
              'explain': 'Explanation $chapter-$lesson',
              'code': 'System.out.println("$chapter-$lesson");',
              'output': '$chapter-$lesson',
              'objective': 'Print a value',
              'prerequisites': ['main'],
              'pitfalls': ['Missing semicolon'],
              'exercises': [
                {
                  'prompt': 'Change the value',
                  'hint': 'Edit the string',
                  'answer': 'Another value',
                },
              ],
            },
        ],
      },
    {
      ..._metadata('python-chapter', language: 'python'),
      'title': 'Python chapter',
      'lessons': [
        {'id': 'python-lesson', 'title': 'Python lesson'},
      ],
    },
  ],
});

final exampleSource = jsonEncode({
  'schemaVersion': 1,
  'entries': [
    for (var index = 0; index < 100; index++)
      {
        ..._metadata('java-example-$index'),
        'title': 'Java example $index',
        'summary': 'Example summary $index',
        'code': 'System.out.println("example $index");',
        'expectedOutput': 'example $index',
        'inputFixtures': {'stdin': 'Ada\n'},
        'templateType': 'java',
        'sourceLessonId': 'java-lesson-1-49',
      },
    {
      ..._metadata('python-example', language: 'python'),
      'title': 'Python example',
      'code': 'print("python")',
    },
  ],
});

Map<String, Object?> _metadata(String id, {String language = 'java'}) => {
  'id': id,
  'language': language,
  'type': language,
  'locale': 'en',
  'level': 'beginner',
  'title': id,
  'summary': 'Learn output',
  'concepts': ['output'],
  'source': 'test-fixture',
  'license': 'CC BY 4.0',
  'updatedAt': '2026-10-15',
};

ContentCatalog fixtureCatalog() => ContentCatalog.fromJson(
  tutorialsSource: tutorialSource,
  examplesSource: exampleSource,
);

class FixtureContentRepository implements ContentRepository {
  FixtureContentRepository(this.catalog);

  final ContentCatalog catalog;

  @override
  Future<ContentCatalog> load() async => catalog;

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async => catalog.tutorials.where(filter.matches).toList();

  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async => catalog.examples.where(filter.matches).toList();
}
