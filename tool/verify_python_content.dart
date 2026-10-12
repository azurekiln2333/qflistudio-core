import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'python_content/python_topic.dart';
import 'python_content/python_topics.dart';

/// Verifies the FINAL shipped Python content:
///
///  1. Cross-checks every authored topic against its emitted tutorial, example
///     and legacy lesson records; fails on any code/output mismatch.
///  2. Executes every `embedded` sample on the **real embedded MicroPython DLL**
///     (via `tool/python_content/run_embedded.py`) and diffs stdout.
///  3. Executes every `cpython` sample on the host CPython and records the
///     version; those are reported separately and never counted as embedded.
///  4. Confirms the generator did not disturb non-Python records.
///
/// Run from `qfli_studio_core` AFTER generating:
///
///   dart run tool/verify_python_content.dart [dllPath] [pythonExe]
Future<void> main(List<String> args) async {
  final core = Directory.current;
  final pythonExe = _resolve(args, 1, 'python') ??
      (Platform.isWindows ? 'python' : 'python3');
  final dll = _resolveDll(core, args);

  final tutorialFile = File(p.join(core.path, 'assets/content/tutorials.json'));
  final exampleFile = File(p.join(core.path, 'assets/content/examples.json'));
  final legacyFile = File(p.join(core.path, 'assets/tutorials/python.json'));

  final tutorials = _pythonEntries(tutorialFile);
  final examples = _pythonEntries(exampleFile);
  final legacyLessons = _legacyLessons(legacyFile);

  stdout.writeln('Python:    $pythonExe');
  stdout.writeln('Embedded:  ${dll ?? "(not found)"}');
  final cpythonVersion = await _cpythonVersion(pythonExe);
  stdout.writeln('CPython:   $cpythonVersion');
  final embeddedVersion = dll == null
      ? '(unavailable)'
      : await _embeddedVersion(pythonExe, dll);
  stdout.writeln('MicroPython: $embeddedVersion');

  final results = <Map<String, Object?>>[];
  var embeddedPass = 0;
  var embeddedFail = 0;
  var cpythonPass = 0;
  var cpythonFail = 0;
  var assetFail = 0;

  // Cross-check every authored topic against emitted records.
  for (final topic in pythonTopics) {
    final mismatch = _crossCheck(topic, tutorials, examples, legacyLessons);
    if (mismatch != null) {
      assetFail++;
      results.add(<String, Object?>{
        'id': topic.exampleId,
        'runtime': topic.isEmbedded ? 'embedded' : 'cpython',
        'status': 'asset_mismatch',
        'detail': mismatch,
      });
    }
  }

  final work = Directory.systemTemp.createTempSync('qfli_py_verify_');
  try {
    // --- embedded batch ---
    final embedded = pythonTopics.where((t) => t.isEmbedded).toList();
    if (dll != null && embedded.isNotEmpty) {
      final batch = [
        for (final t in embedded)
          <String, Object?>{
            'id': t.exampleId,
            'code': examples[t.exampleId]!['code'] as String,
            'stdin': _stdinOf(examples[t.exampleId]!),
          },
      ];
      final batchFile = File(p.join(work.path, 'batch.json'));
      batchFile.writeAsStringSync(jsonEncode(batch));
      final outFile = File(p.join(work.path, 'batch_out.json'));
      final proc = await Process.run(pythonExe, [
        p.join(core.path, 'tool', 'python_content', 'run_embedded.py'),
        dll,
        batchFile.path,
        outFile.path,
      ], stdoutEncoding: const Utf8Codec(allowMalformed: true));
      if (proc.exitCode != 0 || !outFile.existsSync()) {
        stderr.writeln('Embedded runner failed: ${proc.stderr}');
        exitCode = 2;
        return;
      }
      final decoded = jsonDecode(outFile.readAsStringSync()) as List;
      final actual = <String, Map<String, Object?>>{
        for (final r in decoded)
          (r as Map)['id'] as String: r.cast<String, Object?>(),
      };
      for (final t in embedded) {
        final observed = actual[t.exampleId];
        final expected = t.output.replaceAll('\r\n', '\n').trimRight();
        final got = (observed?['output'] as String? ?? '')
            .replaceAll('\r\n', '\n')
            .trimRight();
        final codeExit = observed?['exitCode'] as int? ?? -1;
        if (observed != null && codeExit == 0 && got == expected) {
          embeddedPass++;
          results.add(<String, Object?>{
            'id': t.exampleId,
            'runtime': 'embedded',
            'status': 'ok',
          });
        } else {
          embeddedFail++;
          results.add(<String, Object?>{
            'id': t.exampleId,
            'runtime': 'embedded',
            'status': 'mismatch',
            'exitCode': codeExit,
            'expected': expected,
            'actual': got,
            'error': observed?['error'] ?? '',
          });
        }
      }
    } else if (embedded.isNotEmpty) {
      embeddedFail = embedded.length;
      for (final t in embedded) {
        results.add(<String, Object?>{
          'id': t.exampleId,
          'runtime': 'embedded',
          'status': 'embedded_runtime_unavailable',
        });
      }
    }

    // --- cpython batch ---
    for (final t in pythonTopics.where((t) => !t.isEmbedded)) {
      final code = examples[t.exampleId]!['code'] as String;
      final script = File(p.join(work.path, '${t.exampleId}.py'))
        ..writeAsStringSync(code);
      final input = _stdinOf(examples[t.exampleId]!);
      final proc = await Process.run(
        pythonExe,
        [script.path],
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
      );
      final expected = t.output.replaceAll('\r\n', '\n').trimRight();
      final got = (proc.stdout as String).replaceAll('\r\n', '\n').trimRight();      if (proc.exitCode == 0 && got == expected) {
        cpythonPass++;
        results.add(<String, Object?>{
          'id': t.exampleId,
          'runtime': 'cpython',
          'status': 'ok',
        });
      } else {
        cpythonFail++;
        results.add(<String, Object?>{
          'id': t.exampleId,
          'runtime': 'cpython',
          'status': 'mismatch',
          'exitCode': proc.exitCode,
          'expected': expected,
          'actual': got,
          'stderr': '${proc.stderr}'.trim(),
          'stdinUsed': input,
        });
      }
    }
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }

  final report = <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'embeddedRuntime': dll,
    'embeddedVersion': embeddedVersion,
    'cpythonExecutable': pythonExe,
    'cpythonVersion': cpythonVersion,
    'totalPairs': pythonTopics.length,
    'embeddedPlanned': pythonTopics.where((t) => t.isEmbedded).length,
    'cpythonPlanned': pythonTopics.where((t) => !t.isEmbedded).length,
    'embeddedPassed': embeddedPass,
    'embeddedFailed': embeddedFail,
    'cpythonPassed': cpythonPass,
    'cpythonFailed': cpythonFail,
    'assetMismatches': assetFail,
    'tutorialAsset': _assetIdentity(tutorialFile),
    'exampleAsset': _assetIdentity(exampleFile),
    'legacyAsset': _assetIdentity(legacyFile),
    'results': results,
  };

  final reportFile = File(p.join(
    core.path,
    '..',
    'qfli_python',
    '.trellis',
    'tasks',
    '10-12-python-practical-curriculum',
    'research',
    'python-content-verification.json',
  ));
  await reportFile.create(recursive: true);
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );

  stdout.writeln(
    'Embedded: $embeddedPass passed, $embeddedFail failed '
    'of ${pythonTopics.where((t) => t.isEmbedded).length}.',
  );
  stdout.writeln(
    'CPython:  $cpythonPass passed, $cpythonFail failed '
    'of ${pythonTopics.where((t) => !t.isEmbedded).length}.',
  );
  stdout.writeln('Asset mismatches: $assetFail.');
  stdout.writeln('Report: ${reportFile.path}');
  if (embeddedFail > 0 || cpythonFail > 0 || assetFail > 0) {
    exitCode = 1;
  }
}

String? _stdinOf(Map<String, Object?> example) {
  final fixtures = example['inputFixtures'];
  if (fixtures is Map && fixtures['stdin'] is String) {
    return fixtures['stdin'] as String;
  }
  return '';
}

String? _crossCheck(
  PythonTopic topic,
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
  if (lesson['objective'] != topic.objective) return 'tutorial objective mismatch';
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
  if (example['sourceLessonId'] != '${topic.tutorialId}-lesson') {
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

Map<String, Map<String, Object?>> _pythonEntries(File file) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final result = <String, Map<String, Object?>>{};
  for (final entry in (decoded['entries'] as List)) {
    final map = (entry as Map).cast<String, Object?>();
    if (map['language'] == 'python') result[map['id'] as String] = map;
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

Future<String> _cpythonVersion(String exe) async {
  try {
    final r = await Process.run(exe, ['--version']);
    return '${r.stdout}${r.stderr}'.trim();
  } on ProcessException catch (e) {
    return 'unavailable: ${e.message}';
  }
}

Future<String> _embeddedVersion(String exe, String dll) async {
  try {
    final r = await Process.run(exe, [
      '-c',
      'import ctypes,sys;'
          'lib=ctypes.CDLL(sys.argv[1]);'
          'lib.qfli_py_version.restype=ctypes.c_char_p;'
          'print(lib.qfli_py_version().decode())',
      dll,
    ]);
    return '${r.stdout}${r.stderr}'.trim();
  } on ProcessException catch (e) {
    return 'unavailable: ${e.message}';
  }
}

String? _resolveDll(Directory core, List<String> args) {
  final explicit = args.isNotEmpty ? args.first : null;
  final candidates = <String>[
    ?explicit,
    p.join(core.path, '..', 'qfli_python', 'native', 'build', 'windows',
        'qfli_py_ffi.dll'),
    p.join(core.path, '..', 'qfli_python', 'native', 'build', 'cmake-x86_64',
        'libqfli_py.so'),
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return p.normalize(c);
  }
  return null;
}

String? _resolve(List<String> args, int index, String fallback) {
  if (args.length > index && args[index].isNotEmpty) return args[index];
  return null;
}

Map<String, Object?> _assetIdentity(File file) {
  if (!file.existsSync()) {
    return <String, Object?>{'path': file.path, 'exists': false};
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final entries = decoded['entries'] as List?;
  var pythonEntries = 0;
  if (entries != null) {
    pythonEntries = entries
        .whereType<Map>()
        .where((e) => e['language'] == 'python')
        .length;
  }
  return <String, Object?>{
    'path': file.path,
    'bytes': file.lengthSync(),
    'schemaVersion': decoded['schemaVersion'],
    'totalEntries': entries?.length,
    'pythonEntries': pythonEntries,
  };
}
