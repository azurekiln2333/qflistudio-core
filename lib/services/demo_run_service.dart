import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/tutorial.dart';
import 'app_paths.dart';
import 'code_import_service.dart';
import 'java_source_renamer.dart';
import 'runner_service.dart';

/// Runs a Java lesson/example in an isolated ASCII scratch project so the
/// current user project, editor content and active runs are never touched.
///
/// The lesson code is written as `<EntryClass>.java` (entry class inferred from
/// the source, defaulting to `Main`), executed through the real
/// [RunnerService.runProject] path (the language app's `ProgramRunner`), and the
/// scratch directory is removed when the caller disposes the session.
class DemoRunSession {
  DemoRunSession._(this.result, this.directory);

  /// Creates a session for tests (controller lifecycle, cleanup failures).
  factory DemoRunSession.forTest(RunResult result, Directory directory) =>
      DemoRunSession._(result, directory);

  final RunResult result;
  final Directory directory;

  bool _cleaned = false;

  /// Cancels the run (when supported) and removes the scratch directory.
  Future<void> dispose() async {
    if (_cleaned) return;
    _cleaned = true;
    try {
      await result.cancel?.call();
    } on Object {
      // Cancellation is best-effort; cleanup still proceeds.
    }
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A locked scratch file on Windows will be reclaimed by the OS temp dir.
    }
  }
}

class DemoRunFailure implements Exception {
  const DemoRunFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class DemoRunService {
  /// Test seam: overrides the scratch root when set.
  static String? scratchRootOverride;

  /// Test seam: when set, replaces the whole start path. Used to exercise raw
  /// startup failures and cleanup failures in controller tests.
  static Future<DemoRunSession> Function(ExampleCode example)? startOverride;

  /// Prepares and starts a run for [example]. Throws [DemoRunFailure] for a
  /// missing runtime, uninterpretable source, or storage failure.
  ///
  /// [location] overrides the scratch root (tests); production uses
  /// [AppPaths.storageDirectory].
  static Future<DemoRunSession> start(
    ExampleCode example, {
    String? location,
  }) async {
    final override = startOverride;
    if (override != null) return override(example);
    final base =
        location ?? scratchRootOverride ?? await AppPaths.storageDirectory();
    if (base == null || base.trim().isEmpty) {
      throw const DemoRunFailure('无法创建临时运行目录');
    }
    final root = Directory(p.join(base, 'demo_runs'))
      ..createSync(recursive: true);
    final directory = root.createTempSync('_run_');

    final info = _entryInfo(example.code);
    final entryFile = File(p.join(directory.path, '${info.className}.java'));
    final RunResult? result;
    try {
      final files = CodeImportService.projectFiles(
        example: example,
        entryFile: '${info.className}.java',
        code: info.code,
      );
      for (final entry in files.entries) {
        final file = File(p.join(directory.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value, flush: true);
      }
      result = await RunnerService.runProject(
        projectPath: directory.path,
        entryFile: entryFile.path,
      );
    } on Object catch (error) {
      _safeDelete(directory);
      throw DemoRunFailure('运行失败：$error');
    }
    if (result == null) {
      _safeDelete(directory);
      throw const DemoRunFailure('无法运行该示例');
    }
    return DemoRunSession._(result, directory);
  }

  static ({String className, String code}) _entryInfo(String source) {
    try {
      final info = JavaSourceRenamer.analyze(source);
      return (className: info.className, code: source);
    } on JavaSourceRenameException {
      // Fall back to Main; if the source declares another entry the runner's
      // javac error is surfaced honestly to the user.
      return (className: 'Main', code: source);
    }
  }

  static void _safeDelete(Directory directory) {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }
}
