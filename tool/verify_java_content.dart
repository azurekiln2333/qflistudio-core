import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'java_content/java_topic.dart';
import 'java_content/java_topics.dart';

/// Tolerant UTF-8 decoder for host-codepage compiler diagnostics.
const Utf8Codec _lenient = Utf8Codec(allowMalformed: true);

/// Verifies the FINAL shipped Java content:
///
///  1. Cross-checks every authored topic against its emitted tutorial, example
///     and legacy lesson records and fails on any code/output mismatch (so stale
///     generated content cannot pass).
///  2. Compiles and runs the code **read from the emitted assets** (the shipped
///     payload), not the authored source.
///  3. Records real `javac`/`java` version output and final asset hashes.
///
/// The caller must regenerate first; this tool does not write assets.
///
///   dart run tool/verify_java_content.dart [jdkHome]
Future<void> main(List<String> args) async {
  final javac = _resolveTool(args, 'javac');
  final java = _resolveTool(args, 'java');
  if (javac == null || java == null) {
    stderr.writeln('No JDK found. Pass a JDK home or set JAVA_HOME.');
    exitCode = 2;
    return;
  }

  final core = Directory.current;
  final tutorialFile = File(p.join(core.path, 'assets/content/tutorials.json'));
  final exampleFile = File(p.join(core.path, 'assets/content/examples.json'));
  final legacyFile = File(p.join(core.path, 'assets/tutorials/java.json'));

  final tutorials = _javaEntries(tutorialFile);
  final examples = _javaEntries(exampleFile);
  final legacyLessons = _legacyLessons(legacyFile);

  stdout.writeln('Using javac: $javac');
  stdout.writeln('Using java:  $java');
  final javacVersion = await _version(javac, const ['-version']);
  final javaVersion = await _version(java, const ['-version']);
  stdout.writeln('javac -version: $javacVersion');
  stdout.writeln('java -version:  $javaVersion');

  final workRoot = Directory.systemTemp.createTempSync('qfli_java_verify_');
  final results = <Map<String, Object?>>[];
  var passed = 0;
  var failed = 0;
  try {
    for (final topic in javaTopics) {
      final mismatch = _crossCheck(topic, tutorials, examples, legacyLessons);
      if (mismatch != null) {
        failed++;
        results.add(<String, Object?>{
          'id': topic.exampleId,
          'status': 'asset_mismatch',
          'detail': mismatch,
        });
        continue;
      }

      // Compile/run the payload exactly as emitted (not the authored string).
      final emittedCode = examples[topic.exampleId]!['code'] as String;
      final emittedOutput =
          (examples[topic.exampleId]!['expectedOutput'] as String)
              .replaceAll('\r\n', '\n')
              .trimRight();

      final project = Directory(p.join(workRoot.path, 't${topic.id}'))
        ..createSync(recursive: true);
      File(p.join(project.path, 'Main.java')).writeAsStringSync(emittedCode);
      final fixtures = examples[topic.exampleId]!['inputFixtures'];
      if (fixtures is Map && fixtures['stdin'] is String) {
        File(
          p.join(project.path, 'input.txt'),
        ).writeAsStringSync(fixtures['stdin'] as String);
      }
      final classes = Directory(p.join(project.path, 'classes'))..createSync();

      final compile = await Process.run(javac, <String>[
        '--release',
        '17',
        '-encoding',
        'UTF-8',
        '-d',
        classes.path,
        p.join(project.path, 'Main.java'),
      ], runInShell: false, stdoutEncoding: _lenient, stderrEncoding: _lenient);
      if (compile.exitCode != 0) {
        failed++;
        results.add(<String, Object?>{
          'id': topic.exampleId,
          'status': 'compile_error',
          'detail': '${compile.stdout}${compile.stderr}'.trim(),
        });
        continue;
      }

      final run = await Process.run(java, <String>[
        '-Dfile.encoding=UTF-8',
        '-Dstdout.encoding=UTF-8',
        '-classpath',
        classes.path,
        'Main',
      ], runInShell: false, workingDirectory: project.path, stdoutEncoding: _lenient, stderrEncoding: _lenient);
      final actual = (run.stdout as String).replaceAll('\r\n', '\n').trimRight();
      final ok = run.exitCode == 0 && actual == emittedOutput;
      if (ok) {
        passed++;
        results.add(<String, Object?>{'id': topic.exampleId, 'status': 'ok'});
      } else {
        failed++;
        results.add(<String, Object?>{
          'id': topic.exampleId,
          'status': 'mismatch',
          'exitCode': run.exitCode,
          'expected': emittedOutput,
          'actual': actual,
          'stderr': (run.stderr as String).trim(),
        });
      }
    }
  } finally {
    if (workRoot.existsSync()) {
      try {
        workRoot.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    }
  }

  final report = <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'hostJavac': javac,
    'hostJava': java,
    'javacVersion': javacVersion,
    'javaVersion': javaVersion,
    'releaseTarget': '17',
    'topicSource': _sha256(
      p.join(core.path, 'tool', 'java_content', 'java_topics.dart'),
    ),
    'tutorialAsset': _assetIdentity(tutorialFile),
    'exampleAsset': _assetIdentity(exampleFile),
    'legacyAsset': _assetIdentity(legacyFile),
    'total': javaTopics.length,
    'passed': passed,
    'failed': failed,
    'results': results,
  };
  final reportFile = File(
    p.join(
      core.path,
      '..',
      'qfli_java',
      '.trellis',
      'tasks',
      '10-09-java-tutorial-rewrite',
      'research',
      'java-content-verification.json',
    ),
  );
  await reportFile.create(recursive: true);
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  stdout.writeln(
    'Verified emitted payload: $passed passed, $failed failed of ${javaTopics.length}.',
  );
  stdout.writeln('Report: ${reportFile.path}');
  if (failed > 0) exitCode = 1;
}

/// Returns a human-readable mismatch description, or null when the emitted
/// records exactly match the authored topic.
String? _crossCheck(
  JavaTopic topic,
  Map<String, Map<String, Object?>> tutorials,
  Map<String, Map<String, Object?>> examples,
  Map<String, String> legacyLessons,
) {
  final tutorial = tutorials[topic.tutorialId];
  if (tutorial == null) return 'missing tutorial ${topic.tutorialId}';
  final lessons = (tutorial['lessons'] as List?) ?? const [];
  if (lessons.isEmpty) return 'no lessons for ${topic.tutorialId}';
  final lesson = (lessons.first as Map).cast<String, Object?>();
  if (lesson['code'] != topic.code) return 'tutorial code mismatch';
  if (lesson['output'] != topic.output) return 'tutorial output mismatch';
  if (lesson['objective'] != topic.objective) {
    return 'tutorial objective mismatch';
  }
  if (!_sameList(lesson['pitfalls'], topic.pitfalls)) {
    return 'tutorial pitfalls mismatch';
  }
  if (!_sameList(lesson['prerequisites'], topic.prerequisites)) {
    return 'tutorial prerequisites mismatch';
  }

  final example = examples[topic.exampleId];
  if (example == null) return 'missing example ${topic.exampleId}';
  if (example['code'] != topic.code) return 'example code mismatch';
  if (example['expectedOutput'] != topic.output) {
    return 'example expectedOutput mismatch';
  }
  if (example['sourceLessonId'] != topic.tutorialId) {
    return 'example sourceLessonId mismatch';
  }

  final legacy = legacyLessons[topic.tutorialId];
  if (legacy == null) return 'missing legacy lesson ${topic.tutorialId}';
  if (legacy != topic.code) return 'legacy lesson code mismatch';
  return null;
}

bool _sameList(Object? value, List<String> expected) {
  if (value is! List) return expected.isEmpty;
  if (value.length != expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (value[i] != expected[i]) return false;
  }
  return true;
}

Map<String, Map<String, Object?>> _javaEntries(File file) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final result = <String, Map<String, Object?>>{};
  for (final entry in (decoded['entries'] as List)) {
    final map = (entry as Map).cast<String, Object?>();
    if (map['language'] == 'java') {
      result[map['id'] as String] = map;
    }
  }
  return result;
}

Map<String, String> _legacyLessons(File file) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final result = <String, String>{};
  for (final chapter in (decoded['chapters'] as List)) {
    for (final lesson in ((chapter as Map)['lessons'] as List)) {
      final map = (lesson as Map).cast<String, Object?>();
      result[map['id'] as String] = map['code'] as String;
    }
  }
  return result;
}

Future<String> _version(String tool, List<String> args) async {
  try {
    final result = await Process.run(
      tool,
      args,
      runInShell: false,
      stdoutEncoding: _lenient,
      stderrEncoding: _lenient,
    );
    final text = '${result.stdout}${result.stderr}'.trim();
    return text.split('\n').first.trim();
  } on ProcessException catch (error) {
    return 'unavailable: ${error.message}';
  }
}

String _sha256(String path) {
  final file = File(path);
  if (!file.existsSync()) return 'missing:$path';
  // Not a cryptographic hash (no crypto dep); a stable content fingerprint.
  var h = 17;
  for (final b in file.readAsBytesSync()) {
    h = (h * 31 + b) & 0x7fffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

Map<String, Object?> _assetIdentity(File file) {
  if (!file.existsSync()) {
    return <String, Object?>{'path': file.path, 'exists': false};
  }
  final source = file.readAsStringSync();
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  final entries = decoded['entries'] as List?;
  final chapters = decoded['chapters'] as List?;
  var javaEntries = 0;
  if (entries != null) {
    javaEntries = entries
        .whereType<Map>()
        .where((e) => e['language'] == 'java')
        .length;
  }
  return <String, Object?>{
    'path': file.path,
    'bytes': file.lengthSync(),
    'fingerprint': _sha256(file.path),
    'schemaVersion': decoded['schemaVersion'],
    'totalEntries': entries?.length,
    'javaEntries': entries == null ? null : javaEntries,
    'chapters': chapters?.length,
  };
}

String? _resolveTool(List<String> args, String tool) {
  if (args.isNotEmpty) {
    final home = args.first;
    final name = Platform.isWindows ? '$tool.exe' : tool;
    final candidate = File(p.join(home, 'bin', name));
    if (candidate.existsSync()) return candidate.path;
  }
  for (final env in <String?>[
    Platform.environment['QFLI_JAVA_HOME'],
    Platform.environment['JAVA_HOME'],
  ]) {
    if (env == null || env.isEmpty) continue;
    final name = Platform.isWindows ? '$tool.exe' : tool;
    final candidate = File(p.join(env, 'bin', name));
    if (candidate.existsSync()) return candidate.path;
  }
  return tool;
}
