import 'dart:convert';
import 'dart:io';

import 'content_identity.dart';
import 'python_topics.dart';

/// Exports authored programs without changing shared aggregate assets.
Future<void> main(List<String> args) async {
  final (units, mismatches, assetDigests) = buildInventory(
    includeShipped: args.length == 2 && args.last == '--shipped',
  );
  final payload = const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'origin': args.length == 2
        ? 'authored plus every shipped aggregate/legacy representation'
        : 'authored; generated assets require a separate consistency check',
    'topicCount': pythonTopics.length,
    'assetMismatches': mismatches,
    'assetDigests': assetDigests,
    'units': units,
  });
  if (args.isEmpty ||
      args.length > 2 ||
      args.length == 2 && args.last != '--shipped') {
    throw ArgumentError(
      'Pass output JSON path and optional --shipped. No aggregate is modified.',
    );
  }
  final output = File(args.first);
  await output.parent.create(recursive: true);
  await output.writeAsString('$payload\n');  stdout.writeln(
    'Exported ${units.length} units from ${pythonTopics.length} topics.',
  );
}

/// 按现有模型生成清单。
///
/// 抽出来是为了能脱离文件系统直接测试；返回值的三项分别对应
/// 单元列表、与已发布资产的差异、已读资产的摘要。
(
  List<Map<String, Object?>>,
  List<String>,
  Map<String, String>,
)
buildInventory({bool includeShipped = false}) {
  final units = <Map<String, Object?>>[];
  for (final topic in pythonTopics) {
    units.add({
      'id': '${topic.exampleId}:authored',
      'topic': topic.id,
      'kind': 'authored-main',
      'code': topic.code,
      'expectedOutput': topic.output,
      // `PythonTopic` 只有原始 stdin；没有按用例拆开的夹具。
      'inputFixtures': {
        if (topic.input != null) 'stdin': topic.input!,
      },
      'runtime': topic.runtime.name,
      'hasBehaviorCheck': true,
    });
    for (var i = 0; i < topic.tasks.length; i++) {
      final task = topic.tasks[i];
      units.add({
        'id': '${topic.tutorialId}:answer-${i + 1}',
        'topic': topic.id,
        'kind': 'exercise-answer',
        'prompt': task.prompt,
        'hint': task.hint,
        'answer': task.answer,
        // `PythonTask` 只有题目、提示、参考答案三项，没有校验脚本与夹具。
        'code': task.answer,
        'expectedOutput': null,
        'inputFixtures': <String, String>{},
        'runtime': topic.runtime.name,
        'hasBehaviorCheck': false,
      });
    }
  }
  final mismatches = <String>[];
  final assetDigests = <String, String>{};
  if (includeShipped) {
    _addShipped(units, mismatches, assetDigests);
  }
  return (units, mismatches, assetDigests);
}

void _addShipped(
  List<Map<String, Object?>> units,
  List<String> mismatches,
  Map<String, String> assetDigests,
) {
  Map<String, dynamic> read(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    assetDigests[path] = contentDigest(bytes);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Map<String, Map> indexed(List values, {bool pythonOnly = false}) {
    final result = <String, Map>{};
    for (final raw in values.cast<Map>()) {
      if (pythonOnly && raw['language'] != 'python') continue;
      final id = raw['id'] as String;
      if (result.containsKey(id)) mismatches.add('Duplicate emitted ID: $id');
      result[id] = raw;
    }
    if (result.length != pythonTopics.length) {
      mismatches.add(
        'Expected ${pythonTopics.length} records, found ${result.length}',
      );
    }
    return result;
  }

  final tutorials = indexed(
    read('assets/content/tutorials.json')['entries'] as List,
    pythonOnly: true,
  );
  final examples = indexed(
    read('assets/content/examples.json')['entries'] as List,
    pythonOnly: true,
  );
  final legacy = read('assets/tutorials/python.json');
  final legacyLessons = indexed([
    for (final chapter in legacy['chapters'] as List)
      ...(chapter['lessons'] as List),
  ]);
  final legacyExamples = indexed(legacy['examples'] as List);
  final authored = List<Map<String, Object?>>.of(units);

  void compare(String label, Object? actual, Object? expected) {
    if (canonicalContentJson(actual) != canonicalContentJson(expected)) {
      mismatches.add(label);
    }
  }

  void mainUnit(
    Map<String, Object?> base,
    Map? raw,
    String form,
    String outputKey,
  ) {
    final id = '${base['id']}:$form';
    compare('$id code', raw?['code'], base['code']);
    compare('$id output', raw?[outputKey], base['expectedOutput']);
    compare('$id fixtures', raw?['inputFixtures'], base['inputFixtures']);
    units.add({
      ...base,
      'id': id,
      'kind': form,
      'code': raw?['code'] as String? ?? '',
      'expectedOutput': raw?[outputKey],
      'inputFixtures': raw?['inputFixtures'] ?? <String, String>{},
      'hasBehaviorCheck': raw?[outputKey] is String,
    });
  }

  for (final topic in pythonTopics) {
    final base = authored.firstWhere(
      (unit) => unit['topic'] == topic.id && unit['kind'] == 'authored-main',
    );
    final tutorial = tutorials[topic.tutorialId];
    final lessons = tutorial?['lessons'] as List? ?? const [];
    if (lessons.length != 1) {
      mismatches.add('${topic.tutorialId}: expected one lesson');
    }
    final lesson = lessons.isEmpty ? null : lessons.first as Map;
    final oldLesson = legacyLessons[topic.tutorialId];
    final example = examples[topic.exampleId];
    compare(
      '${topic.tutorialId}: entry fixtures',
      tutorial?['inputFixtures'],
      base['inputFixtures'],
    );
    compare(
      '${topic.exampleId}: pairing',
      example?['sourceLessonId'],
      '${topic.tutorialId}-lesson',
    );
    final concepts = example?['concepts'] as List? ?? const [];
    if (!concepts.contains('内置运行') || concepts.contains('需要外部 CPython 环境')) {
      mismatches.add('${topic.exampleId}: not labeled embedded');
    }
    mainUnit(base, example, 'aggregate-example', 'expectedOutput');
    mainUnit(base, lesson, 'aggregate-lesson', 'output');
    mainUnit(base, legacyExamples[topic.exampleId], 'legacy-example', 'output');
    mainUnit(base, oldLesson, 'legacy-lesson', 'output');
    for (final form in {
      'aggregate-answer': lesson?['exercises'],
      'legacy-answer': oldLesson?['tasks'],
    }.entries) {
      final answers = form.value as List? ?? const [];
      if (answers.length != topic.tasks.length) {
        mismatches.add('${topic.tutorialId}: ${form.key} count');
      }
      for (var i = 0; i < topic.tasks.length; i++) {
        final answerBase = authored.firstWhere(
          (unit) => unit['id'] == '${topic.tutorialId}:answer-${i + 1}',
        );
        final raw = i < answers.length ? answers[i] as Map : null;
        final expected = topic.tasks[i];
        final id = '${answerBase['id']}:${form.key}';
        compare('$id prompt', raw?['prompt'], expected.prompt);
        compare('$id hint', raw?['hint'], expected.hint);
        compare('$id answer', raw?['answer'], expected.answer);
        // `PythonTask` 只有题目、提示、参考答案三项，没有校验脚本与预期输出。
        // 比对侧照旧读已发布字段，作者侧按空值比对。
        compare('$id validation', raw?['validation'], null);
        compare('$id output', raw?['expectedOutput'], null);
        compare(
          '$id fixtures',
          raw?['inputFixtures'],
          answerBase['inputFixtures'],
        );
        final validation = raw?['validation'] as String? ?? '';
        units.add({
          ...answerBase,
          'id': id,
          'kind': form.key,
          'answer': raw?['answer'] ?? '',
          'validation': validation,
          'code': '${raw?['answer'] ?? ''}\n$validation',
          'expectedOutput': raw?['expectedOutput'],
          'inputFixtures': raw?['inputFixtures'] ?? <String, String>{},
          'hasBehaviorCheck':
              raw?['expectedOutput'] is String || validation.trim().isNotEmpty,
        });
      }
    }
  }
}
