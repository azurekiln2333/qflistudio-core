/// Python tutorial/example content: the authored source of truth.
///
/// This file is data only (no `dart:io`). `tool/generate_python_content.dart`
/// reads [pythonTopics] and emits the two aggregate JSON assets plus the legacy
/// `assets/tutorials/python.json` bundle.
///
/// Runtime contract (verified against the embedded MicroPython 1.24.1 runtime,
/// not CPython): every [PythonTopic] with `runtime == embedded` must actually
/// run on the bundled interpreter; `runtime == cpython` lessons are taught but
/// explicitly labeled as needing an external CPython environment and are
/// verified in CPython, never credited to the embedded runtime.
library;

/// Where a lesson's companion code runs.
enum PythonRuntime {
  /// Runs in the bundled embedded MicroPython runtime (verified there).
  embedded,

  /// Requires an external CPython environment; labeled as such.
  cpython,
}

/// One authored topic: a tutorial lesson and its paired runnable example.
class PythonTopic {
  const PythonTopic({
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
    this.tasks = const <PythonTask>[],
    this.runtime = PythonRuntime.embedded,
  });

  /// Stable numeric id, 1..120.
  final int id;

  /// `beginner` | `intermediate` | `advanced`.
  final String level;

  final String title;
  final String summary;
  final List<String> concepts;
  final String objective;

  /// Substantive Chinese prose explaining this topic's specific concepts.
  final String explain;

  /// Complete, runnable, multi-line program.
  final String code;

  /// Exact stdout the program prints (normalized by the verifier).
  final String output;

  final List<String> pitfalls;
  final List<String> prerequisites;

  /// Optional stdin fed as the project's `input.txt`.
  final String? input;

  final List<PythonTask> tasks;

  /// Which environment [code] is verified in.
  final PythonRuntime runtime;

  bool get isEmbedded => runtime == PythonRuntime.embedded;

  String get tutorialId => 'python-tutorial-${id.toString().padLeft(3, '0')}';
  String get exampleId => 'python-example-${id.toString().padLeft(3, '0')}';
}

/// A practice prompt attached to a lesson.
class PythonTask {
  const PythonTask({
    required this.prompt,
    required this.hint,
    required this.answer,
  });

  final String prompt;
  final String hint;
  final String answer;
}
