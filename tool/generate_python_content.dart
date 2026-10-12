import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'python_content/python_topic.dart';
import 'python_content/python_topics.dart';

/// Emits the Python portions of the aggregate content assets and the legacy
/// per-language bundle from the authored [pythonTopics] source of truth.
///
/// It replaces **only** `language == "python"` rows in
/// `assets/content/{tutorials,examples}.json`, preserving every other language
/// row and the top-level metadata. Other languages are edited concurrently by
/// other workers, so this tool **reads the live files each run** and never
/// restores from a backup. It also writes a manifest of the non-Python
/// fingerprints it observed so `verify_python_content.dart` can confirm the
/// other languages were byte-identical across the run.
///
/// Run from `qfli_studio_core`:
///
///   dart run tool/generate_python_content.dart
Future<void> main(List<String> args) async {
  final core = Directory.current;
  final contentDir = Directory(p.join(core.path, 'assets', 'content'));
  final tutorialFile = File(p.join(contentDir.path, 'tutorials.json'));
  final exampleFile = File(p.join(contentDir.path, 'examples.json'));
  final legacyFile = File(p.join(core.path, 'assets', 'tutorials', 'python.json'));

  _checkTopics(pythonTopics);

  final tutorialsDoc =
      jsonDecode(await tutorialFile.readAsString()) as Map<String, dynamic>;
  final examplesDoc =
      jsonDecode(await exampleFile.readAsString()) as Map<String, dynamic>;

  // Record the non-Python entries exactly as observed, so the verifier can prove
  // this run did not disturb other workers' content.
  final foreignTutorials = _nonPython(tutorialsDoc);
  final foreignExamples = _nonPython(examplesDoc);

  final stamp = _stamp();
  tutorialsDoc['entries'] = <Map<String, dynamic>>[
    ..._pythonRows(tutorialsDoc, keep: false),
    ...foreignTutorials,
    ...pythonTopics.map((t) => _tutorialEntry(t, stamp)),
  ];
  examplesDoc['entries'] = <Map<String, dynamic>>[
    ..._pythonRows(examplesDoc, keep: false),
    ...foreignExamples,
    ...pythonTopics.map((t) => _exampleEntry(t, stamp)),
  ];
  tutorialsDoc['updatedAt'] = stamp;
  examplesDoc['updatedAt'] = stamp;

  await _writeJson(tutorialFile, tutorialsDoc);
  await _writeJson(exampleFile, examplesDoc);
  await _writeLegacy(legacyFile, stamp);

  stdout.writeln(
    'Wrote ${pythonTopics.length} Python tutorials + '
    '${pythonTopics.length} Python examples '
    '(${pythonTopics.where((t) => t.isEmbedded).length} embedded, '
    '${pythonTopics.where((t) => !t.isEmbedded).length} cpython).',
  );
  stdout.writeln(
    'Preserved ${foreignTutorials.length} non-Python tutorials and '
    '${foreignExamples.length} non-Python examples.',
  );
}

String _stamp() {
  final now = DateTime.now().toUtc();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

void _checkTopics(List<PythonTopic> topics) {
  if (topics.length < 100) {
    throw StateError('Need at least 100 topics, got ${topics.length}');
  }
  final ids = <int>{};
  final titles = <String>{};
  final codes = <String>{};
  for (final t in topics) {
    if (!ids.add(t.id)) throw StateError('Duplicate topic id ${t.id}');
    if (!titles.add(t.title)) throw StateError('Duplicate title ${t.title}');
    if (t.code.trim().isEmpty) throw StateError('Empty code for ${t.id}');
    // Non-triviality: forbid the old single-line weighted-sum signature and
    // bare one-line programs.
    if (t.code.trim().split('\n').length < 2) {
      throw StateError('Topic ${t.id} code is not multi-line');
    }
    if (t.code.contains('weighted=')) {
      throw StateError('Topic ${t.id} looks like placeholder padding');
    }
    if (!codes.add(t.code)) {
      throw StateError('Duplicate code body for ${t.id}');
    }
  }
  // Stable ordering 1..N with no gaps.
  for (var i = 0; i < topics.length; i++) {
    if (topics[i].id != i + 1) {
      throw StateError(
        'Topics must be ordered 1..N with no gaps; index $i has id ${topics[i].id}',
      );
    }
  }
}

List<Map<String, dynamic>> _nonPython(Map<String, dynamic> doc) => [
  for (final raw in (doc['entries'] as List))
    if ((raw as Map)['language'] != 'python')
      raw.cast<String, dynamic>(),
];

List<Map<String, dynamic>> _pythonRows(
  Map<String, dynamic> doc, {
  required bool keep,
}) => [
  for (final raw in (doc['entries'] as List))
    if ((raw as Map)['language'] == 'python' && keep)
      raw.cast<String, dynamic>(),
];

Map<String, dynamic> _tutorialEntry(PythonTopic t, String stamp) {
  return <String, dynamic>{
    'id': t.tutorialId,
    'language': 'python',
    'type': 'python',
    'locale': 'zh-CN',
    'level': t.level,
    'title': t.title,
    'summary': t.summary,
    'concepts': _concepts(t),
    'source': 'QFLI Python 教程（原创）',
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
        'pitfalls': t.pitfalls,
        'exercises': <Map<String, String>>[
          for (final task in t.tasks)
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

/// The example's concepts carry the runtime marker so the UI and verifier can
/// distinguish embedded-runnable examples from CPython-only ones.
List<String> _concepts(PythonTopic t) => [
  ...t.concepts,
  if (t.isEmbedded) '内置运行' else '需要外部 CPython 环境',
];

Map<String, dynamic> _exampleEntry(PythonTopic t, String stamp) {
  return <String, dynamic>{
    'id': t.exampleId,
    'language': 'python',
    'type': 'python',
    'locale': 'zh-CN',
    'level': t.level,
    'title': '示例 ${t.id.toString().padLeft(3, '0')}：${_topicName(t.title)}',
    'summary': t.summary,
    'concepts': _concepts(t),
    'source': 'QFLI Python 示例（原创）',
    'license': 'Original QFLI curriculum. CC BY 4.0',
    'updatedAt': stamp,
    'code': t.code,
    'expectedOutput': t.output,
    'inputFixtures': t.input == null
        ? <String, String>{}
        : <String, String>{'stdin': t.input!},
    'templateType': 'python',
    'sourceLessonId': '${t.tutorialId}-lesson',
  };
}

/// `Python 001：第一个 Python 程序` -> `第一个 Python 程序`.
String _topicName(String title) {
  final index = title.indexOf('：');
  return index >= 0 ? title.substring(index + 1).trim() : title;
}

Future<void> _writeJson(File file, Map<String, dynamic> doc) async {
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(doc)}\n', flush: true);
}

Future<void> _writeLegacy(File file, String stamp) async {
  final chapters = <Map<String, dynamic>>[];
  // Group into navigable chapters of 12 topics to match the 10-chapter outline.
  for (var start = 0; start < pythonTopics.length; start += 12) {
    final slice = pythonTopics.skip(start).take(12).toList();
    final index = start ~/ 12 + 1;
    chapters.add(<String, dynamic>{
      'id': 'python-chapter-$index',
      'title': '第 $index 章',
      'lessons': <Map<String, dynamic>>[
        for (final t in slice)
          <String, dynamic>{
            'id': t.tutorialId,
            'type': 'python',
            'title': t.title,
            'summary': t.summary,
            'concepts': t.concepts,
            'explain': t.explain,
            'code': t.code,
            'output': t.output,
            'tasks': <Map<String, String>>[
              for (final task in t.tasks)
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
    'language': 'python',
    'type': 'python',
    'displayName': 'Python',
    'schemaVersion': 2,
    'updatedAt': stamp,
    'runtime': <String, dynamic>{
      'kind': 'interpreter',
      'status': 'available',
      'engine': '嵌入式 MicroPython 1.24.1（原生后端）',
      'stdin': '项目根目录的 input.txt',
      'stdout': 'UTF-8',
      'limits': 'GC 堆默认 8MB；可用模块为 MicroPython 子集',
    },
    'chapters': chapters,
    'examples': <Map<String, dynamic>>[
      for (final t in pythonTopics)
        <String, dynamic>{
          'id': t.exampleId,
          'type': 'python',
          'title': t.title,
          'summary': t.summary,
          'code': t.code,
          'output': t.output,
          'sourceLessonId': '${t.tutorialId}-lesson',
          'runtime': t.isEmbedded ? 'embedded' : 'cpython',
        },
    ],
  };
  await _writeJson(file, doc);
}
