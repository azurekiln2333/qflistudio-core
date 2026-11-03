import 'package:flutter_test/flutter_test.dart';

import '../tool/python_content/export_inventory.dart';
import '../tool/python_content/python_topics.dart';

/// Pins the inventory exporter to the current authored model.
///
/// The exporter once read `validation`, `output` and per-task `inputFixtures`
/// from `PythonTask`, none of which exist. Nothing compiled it, so the drift
/// went unnoticed. These cases run it against the real curriculum.
void main() {
  test('builds one authored unit per topic plus one per task', () {
    final (units, mismatches, _) = buildInventory();

    final taskCount = pythonTopics.fold<int>(
      0,
      (sum, topic) => sum + topic.tasks.length,
    );
    expect(units, hasLength(pythonTopics.length + taskCount));
    // Without `--shipped` nothing is read from disk, so nothing can differ.
    expect(mismatches, isEmpty);

    final main = units.first;
    expect(main['kind'], 'authored-main');
    expect(main['id'], '${pythonTopics.first.exampleId}:authored');
    expect(main['code'], pythonTopics.first.code);
    expect(main['expectedOutput'], pythonTopics.first.output);
    expect(main['hasBehaviorCheck'], isTrue);
  });

  test('exercise answers carry only the authored fields', () {
    final (units, _, _) = buildInventory();
    final topic = pythonTopics.firstWhere((topic) => topic.tasks.isNotEmpty);
    final answers = units
        .where((unit) => unit['kind'] == 'exercise-answer')
        .where((unit) => unit['topic'] == topic.id)
        .toList();

    expect(answers, hasLength(topic.tasks.length));
    for (var i = 0; i < answers.length; i++) {
      final answer = answers[i];
      final task = topic.tasks[i];
      expect(
        answer['id'],
        '${topic.tutorialId}:answer-${i + 1}',
        reason: 'answer ids are stable and 1-based',
      );
      expect(answer['prompt'], task.prompt);
      expect(answer['hint'], task.hint);
      expect(answer['answer'], task.answer);
      expect(answer['code'], task.answer);
      // No validation script and no expectation exist in the model.
      expect(answer['expectedOutput'], isNull);
      expect(answer['inputFixtures'], isEmpty);
      expect(answer['hasBehaviorCheck'], isFalse);
    }
  });

  test('a topic stdin reaches the authored unit as a fixture', () {
    final withInput = pythonTopics.where((topic) => topic.input != null);
    final without = pythonTopics.where((topic) => topic.input == null);
    expect(withInput, isNotEmpty, reason: 'the curriculum has stdin topics');
    expect(without, isNotEmpty, reason: 'and topics without stdin');

    final (units, _, _) = buildInventory();
    for (final topic in withInput) {
      final unit = units.firstWhere(
        (unit) => unit['id'] == '${topic.exampleId}:authored',
      );
      expect(unit['inputFixtures'], {'stdin': topic.input});
    }
    final empty = units.firstWhere(
      (unit) => unit['id'] == '${without.first.exampleId}:authored',
    );
    expect(empty['inputFixtures'], isEmpty);
  });
}
