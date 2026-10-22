/// Java tutorial/example content: the authored source of truth.
///
/// This file is data only (no `dart:io`). `tool/generate_java_content.dart`
/// reads [javaTopics] and emits the two aggregate JSON assets plus the legacy
/// `assets/tutorials/java.json` bundle.
///
/// Every [JavaTopic.code] is a complete, formatted, multi-line Java program
/// (companion classes on their own lines; class/main/body each indented). The
/// programs are verified with real `javac`/`java` by
/// `tool/verify_java_content.dart`, diffing stdout against [JavaTopic.output].
library;

/// One authored topic: a tutorial lesson and its paired runnable example.
class JavaTopic {
  const JavaTopic({
    required this.id,
    required this.level,
    required this.title,
    required this.summary,
    required this.concepts,
    required this.objective,
    required this.explain,
    required this.code,
    required this.output,
    required this.pitfalls,
    this.prerequisites = const <String>[],
    this.input,
    this.tasks = const <JavaTask>[],
  });

  /// Stable numeric id, retained as the curriculum expands.
  final int id;

  /// `beginner` | `intermediate` | `advanced`.
  final String level;

  final String title;
  final String summary;
  final List<String> concepts;
  final String objective;
  final String explain;

  /// Complete multi-line Java source. Must compile and run.
  final String code;

  /// Exact stdout the program prints (trailing newline normalized by verifier).
  final String output;

  final List<String> pitfalls;
  final List<String> prerequisites;

  /// Optional stdin fed as `input.txt`.
  final String? input;

  final List<JavaTask> tasks;

  String get tutorialId => 'java-tutorial-${id.toString().padLeft(3, '0')}';
  String get exampleId => 'java-example-${id.toString().padLeft(3, '0')}';
}

/// A practice prompt attached to a lesson.
class JavaTask {
  const JavaTask({
    required this.prompt,
    required this.hint,
    required this.answer,
  });

  final String prompt;
  final String hint;
  final String answer;
}
