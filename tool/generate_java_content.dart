import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'java_content/java_topic.dart';
import 'java_content/java_topics.dart';

/// Emits the Java portions of the aggregate content assets and the legacy
/// per-language bundle from the authored [javaTopics] source of truth.
///
/// It replaces **only** `language == "java"` rows in
/// `assets/content/{tutorials,examples}.json`, preserving every other language
/// row and the top-level metadata. Run from `qfli_studio_core`:
///
///   dart run tool/generate_java_content.dart
Future<void> main(List<String> args) async {
  final core = Directory.current;
  final contentDir = Directory(p.join(core.path, 'assets', 'content'));
  final tutorialFile = File(p.join(contentDir.path, 'tutorials.json'));
  final exampleFile = File(p.join(contentDir.path, 'examples.json'));
  final legacyFile = File(
    p.join(core.path, 'assets', 'tutorials', 'java.json'),
  );

  _checkUnique(javaTopics);

  final tutorialsDoc =
      jsonDecode(await tutorialFile.readAsString()) as Map<String, dynamic>;
  final examplesDoc =
      jsonDecode(await exampleFile.readAsString()) as Map<String, dynamic>;

  final tutorialEntries = (tutorialsDoc['entries'] as List)
      .cast<Map<String, dynamic>>()
      .where((e) => e['language'] != 'java')
      .toList();
  final exampleEntries = (examplesDoc['entries'] as List)
      .cast<Map<String, dynamic>>()
      .where((e) => e['language'] != 'java')
      .toList();

  final stamp = _stamp();
  tutorialsDoc['entries'] = <Map<String, dynamic>>[
    ...tutorialEntries,
    ...javaTopics.map((t) => _tutorialEntry(t, stamp)),
  ];
  tutorialsDoc['updatedAt'] = stamp;
  examplesDoc['entries'] = <Map<String, dynamic>>[
    ...exampleEntries,
    ...javaTopics.map((t) => _exampleEntry(t, stamp)),
  ];
  examplesDoc['updatedAt'] = stamp;

  await _writeJson(tutorialFile, tutorialsDoc);
  await _writeJson(exampleFile, examplesDoc);
  await _writeLegacy(legacyFile, stamp);

  stdout.writeln(
    'Wrote ${javaTopics.length} Java tutorials + '
    '${javaTopics.length} Java examples.',
  );
}

String _stamp() {
  final now = DateTime.now().toUtc();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

void _checkUnique(List<JavaTopic> topics) {
  final ids = <int>{};
  final titles = <String>{};
  for (final t in topics) {
    if (!ids.add(t.id)) {
      throw StateError('Duplicate topic id ${t.id}');
    }
    if (!titles.add(t.title)) {
      throw StateError('Duplicate topic title ${t.title}');
    }
  }
  for (var index = 0; index < topics.length; index++) {
    if (topics[index].id != index + 1) {
      throw StateError('Topic ids must be contiguous and ordered at $index');
    }
  }
}

Map<String, dynamic> _tutorialEntry(JavaTopic t, String stamp) {
  return <String, dynamic>{
    'id': t.tutorialId,
    'language': 'java',
    'type': 'java',
    'locale': 'zh-CN',
    'level': t.level,
    'title': t.title,
    'summary': t.summary,
    'concepts': t.concepts,
    'source': 'QFLI Java 教程（原创）',
    'license': 'Original QFLI curriculum. CC BY 4.0',
    'updatedAt': stamp,
    'lessons': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '${t.tutorialId}-lesson',
        'title': t.title,
        'summary': t.summary,
        'concepts': t.concepts,
        'objective': t.objective,
        'prerequisites': t.prerequisites,
        'explain': t.explain,
        'code': t.code,
        'output': t.output,
        'inputFixtures': _inputFixtures(t),
        'pitfalls': t.pitfalls,
        'exercises': <Map<String, String>>[
          for (final task in _tasksFor(t))
            <String, String>{
              'prompt': task.prompt,
              'hint': task.hint,
              'answer': task.answer,
            },
        ],
      },
    ],
  };
}

/// Practice tasks for a topic: the authored ones, or a concrete per-topic
/// exercise derived from the topic's own code so every lesson has a real
/// hands-on task without a shared placeholder.
List<JavaTask> _tasksFor(JavaTopic t) {
  if (t.tasks.isNotEmpty) return t.tasks;
  return <JavaTask>[
    JavaTask(
      prompt: '运行示例，观察输出，然后修改程序让结果体现一个新的输入。',
      hint: '改动示例中的常量或数据，重新编译运行，确认输出随之改变。',
      answer:
          '把 ${t.concepts.isEmpty ? '示例数据' : t.concepts.first} 相关的一处取值改成你自己的数据后重新运行。',
    ),
  ];
}

Map<String, dynamic> _exampleEntry(JavaTopic t, String stamp) {
  return <String, dynamic>{
    'id': t.exampleId,
    'language': 'java',
    'type': 'java',
    'locale': 'zh-CN',
    'level': t.level,
    'title': '示例 ${t.id.toString().padLeft(3, '0')}：${_topicName(t.title)}',
    'summary': t.summary,
    'concepts': t.concepts,
    'source': 'QFLI Java 示例（原创）',
    'license': 'Original QFLI curriculum. CC BY 4.0',
    'updatedAt': stamp,
    'code': t.code,
    'expectedOutput': t.output,
    'inputFixtures': _inputFixtures(t),
    'templateType': 'java',
    'sourceLessonId': t.tutorialId,
  };
}

/// `Java 001：第一个 Java 程序` -> `第一个 Java 程序`.
String _topicName(String title) {
  final index = title.indexOf('：');
  return index >= 0 ? title.substring(index + 1).trim() : title;
}

Map<String, String> _inputFixtures(JavaTopic topic) => topic.input == null
    ? <String, String>{}
    : <String, String>{'stdin': topic.input!};

Future<void> _writeJson(File file, Map<String, dynamic> doc) async {
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(doc)}\n', flush: true);
}

Future<void> _writeLegacy(File file, String stamp) async {
  final chapters = <Map<String, dynamic>>[];
  // Chapters of 20 topics keep the expanding legacy bundle navigable.
  for (var start = 0; start < javaTopics.length; start += 20) {
    final slice = javaTopics.skip(start).take(20).toList();
    final index = start ~/ 20 + 1;
    chapters.add(<String, dynamic>{
      'id': 'java-chapter-$index',
      'title': '第 $index 章',
      'lessons': <Map<String, dynamic>>[
        for (final t in slice)
          <String, dynamic>{
            'id': t.tutorialId,
            'type': 'java',
            'title': t.title,
            'summary': t.summary,
            'concepts': t.concepts,
            'explain': t.explain,
            'code': t.code,
            'output': t.output,
            'inputFixtures': _inputFixtures(t),
            'tasks': <Map<String, String>>[
              for (final task in _tasksFor(t))
                <String, String>{
                  'prompt': task.prompt,
                  'hint': task.hint,
                  'answer': task.answer,
                },
            ],
          },
      ],
    });
  }
  final doc = <String, dynamic>{
    'language': 'java',
    'type': 'java',
    'displayName': 'Java',
    'schemaVersion': 2,
    'updatedAt': stamp,
    'runtime': <String, dynamic>{
      'kind': 'jdk',
      'status': 'available',
      'engine': 'OpenJDK (javac/java)',
      'stdin': 'input.txt',
      'stdout': 'UTF-8',
      'limits': 'mobile sandbox',
    },
    'chapters': chapters,
    'examples': <Map<String, dynamic>>[
      for (final t in javaTopics)
        <String, dynamic>{
          'id': t.exampleId,
          'type': 'java',
          'title': t.title,
          'summary': t.summary,
          'code': t.code,
          'output': t.output,
          'inputFixtures': _inputFixtures(t),
          'sourceLessonId': t.tutorialId,
        },
    ],
  };
  await _writeJson(file, doc);
}
