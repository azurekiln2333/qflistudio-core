import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/tutorial.dart';
import 'app_paths.dart';
import 'file_backup.dart';
import 'file_service.dart';
import 'example_input_fixtures.dart';
import 'go_source_file_name.dart';
import 'java_source_renamer.dart';
import 'project_config.dart';
import 'project_templates.dart';

typedef CodeImportResult = ({Project project, String path});

enum CodeImportFailure {
  invalidFileName,
  fileExists,
  projectUnavailable,
  storageUnavailable,
}

class CodeImportException implements Exception {
  const CodeImportException(this.reason, [this.detail]);

  final CodeImportFailure reason;
  final String? detail;

  @override
  String toString() => 'CodeImportException(${reason.name}): ${detail ?? ''}';
}

abstract final class CodeImportService {
  static final _projectWrites = <String, Future<void>>{};

  /// Allows tests to pause between real writes and inject a later failure.
  @visibleForTesting
  static Future<void> Function(String path)? beforeProjectFileWriteForTesting;

  /// Allows tests to save after backup, before the replacement snapshot.
  @visibleForTesting
  static Future<void> Function(String path)? beforeProjectFileReplaceForTesting;

  /// Synchronous fault/timing hook; production creation never yields here.
  @visibleForTesting
  static void Function(String path)? afterProjectFileCreateForTesting;

  /// Source plus validated fixtures, relative to the actual project root.
  static Map<String, String> projectFiles({
    required ExampleCode example,
    required String entryFile,
    String? code,
  }) {
    final source = entryFile.replaceAll('\\', '/');
    try {
      final fixtures = ExampleInputFixtures.files(example.inputFixtures);
      final files = ExampleInputFixtures.files({source: code ?? example.code});
      final identity = source.toLowerCase();
      if (fixtures.keys.any(
        (name) =>
            name.toLowerCase() == identity ||
            name.toLowerCase().startsWith('$identity/') ||
            identity.startsWith('${name.toLowerCase()}/'),
      )) {
        throw const FormatException('Fixture conflicts with source');
      }
      return {...files, ...fixtures};
    } on FormatException catch (error) {
      throw CodeImportException(CodeImportFailure.invalidFileName, '$error');
    }
  }

  /// All affected files, so a single replacement prompt includes stdin/data.
  static List<String> destinationPaths({
    required Project project,
    required ExampleCode example,
    required String fileName,
  }) {
    final resolved = resolveImport(example, fileName);
    final source = destinationPath(
      project: project,
      example: example,
      fileName: resolved.fileName,
    );
    return [
      for (final name in projectFiles(
        example: example,
        entryFile: p.relative(source, from: project.path),
        code: resolved.code,
      ).keys)
        p.join(project.path, name),
    ];
  }

  static Future<T> _serialized<T>(
    String root,
    Future<T> Function() write,
  ) async {
    final key = p.normalize(p.absolute(root));
    final previous = _projectWrites[key];
    final done = Completer<void>();
    _projectWrites[key] = done.future;
    try {
      if (previous != null) await previous;
      return await write();
    } finally {
      done.complete();
      if (identical(_projectWrites[key], done.future)) {
        _projectWrites.remove(key);
      }
    }
  }

  static Future<void> _writeProjectFiles({
    required String root,
    required Map<String, String> files,
    required String projectName,
    bool overwrite = false,
  }) => _serialized(root, () async {
    final absoluteRoot = p.normalize(Directory(root).absolute.path);
    if (!Directory(absoluteRoot).existsSync()) {
      throw const CodeImportException(CodeImportFailure.projectUnavailable);
    }
    final originals = <String, List<int>?>{};
    // Preflight the complete set before creating any source/data file or folder.
    for (final name in files.keys) {
      final path = p.normalize(p.join(absoluteRoot, name));
      if (!p.isWithin(absoluteRoot, path)) {
        throw const CodeImportException(CodeImportFailure.projectUnavailable);
      }
      var parent = p.dirname(path);
      while (!p.equals(parent, absoluteRoot)) {
        final type = FileSystemEntity.typeSync(parent, followLinks: false);
        if (type == FileSystemEntityType.file) {
          throw FileSystemException('Import parent is a file', parent);
        }
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw CodeImportException(
            CodeImportFailure.projectUnavailable,
            parent,
          );
        }
        parent = p.dirname(parent);
      }
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          (type != FileSystemEntityType.file || !overwrite)) {
        throw CodeImportException(CodeImportFailure.fileExists, path);
      }
    }
    final written = <String, List<int>>{};
    final createdDirectories = <String>[];
    try {
      for (final entry in files.entries) {
        final file = File(p.normalize(p.join(absoluteRoot, entry.key)));
        final missing = <String>[];
        var parent = file.parent.path;
        while (!Directory(parent).existsSync()) {
          missing.add(parent);
          parent = p.dirname(parent);
        }
        for (final path in missing.reversed) {
          await Directory(path).create();
          createdDirectories.add(path);
        }
        // Check again after await; an import must never follow a new link.
        _checkPhysicalParent(file, absoluteRoot);
        final beforeWrite = beforeProjectFileWriteForTesting;
        if (beforeWrite != null) await beforeWrite(file.path);
        originals[file.path] = await _writeFile(
          file,
          entry.value,
          projectRoot: absoluteRoot,
          projectName: projectName,
          overwrite: overwrite,
        );
        written[file.path] = utf8.encode(entry.value);
      }
    } catch (error, stack) {
      Object? rollbackError;
      final conflicts = <String>[];
      for (final entry in written.entries.toList().reversed) {
        final path = entry.key;
        try {
          final file = File(path);
          final type = FileSystemEntity.typeSync(path, followLinks: false);
          if (type != FileSystemEntityType.file) {
            conflicts.add(path);
            continue;
          }
          final resolvedRoot = Directory(
            absoluteRoot,
          ).resolveSymbolicLinksSync();
          final resolvedParent = file.parent.resolveSymbolicLinksSync();
          if ((!p.equals(resolvedRoot, resolvedParent) &&
                  !p.isWithin(resolvedRoot, resolvedParent)) ||
              !listEquals(file.readAsBytesSync(), entry.value)) {
            conflicts.add(path);
            continue;
          }
          // Do not introduce an async yield between comparison and recovery.
          final bytes = originals[path];
          if (bytes == null) {
            file.deleteSync();
          } else {
            file.writeAsBytesSync(bytes, flush: true);
          }
        } on Object catch (failure) {
          rollbackError ??= failure;
        }
      }
      for (final path in createdDirectories.reversed) {
        try {
          await Directory(path).delete();
        } on FileSystemException {
          // Only remove empty directories created by this import.
        }
      }
      if (conflicts.isNotEmpty) {
        throw FileSystemException(
          'Import failed ($error); rollback conflict: concurrent changes '
          'preserved for ${conflicts.join(', ')}'
          '${rollbackError == null ? '' : '; rollback failed ($rollbackError)'}',
          root,
        );
      }
      if (rollbackError != null) {
        throw FileSystemException(
          'Import failed ($error); rollback failed ($rollbackError)',
          root,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  });
  static final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f]');
  static final RegExp _reservedWindowsName = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3]|CONIN\$|CONOUT\$)(\.|$)',
    caseSensitive: false,
  );

  /// Java reserved words that cannot be a class name.
  static const Set<String> _javaKeywords = {
    'abstract',
    'assert',
    'boolean',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extends',
    'final',
    'finally',
    'float',
    'for',
    'goto',
    'if',
    'implements',
    'import',
    'instanceof',
    'int',
    'interface',
    'long',
    'native',
    'new',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'static',
    'strictfp',
    'super',
    'switch',
    'synchronized',
    'this',
    'throw',
    'throws',
    'transient',
    'try',
    'void',
    'volatile',
    'while',
    'true',
    'false',
    'null',
    'var',
    'record',
    'sealed',
    'permits',
    'yield',
  };

  static final RegExp _javaIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Whether [type] is Java (case-insensitive).
  static bool isJavaType(String type) => type.trim().toLowerCase() == 'java';

  static ProjectTemplate? _templateForType(String type) =>
      ProjectTemplate.fromType(type) ??
      (type.trim().toLowerCase() == 'html' ? ProjectTemplate.html : null);

  /// A source-aware default; explicit import filenames remain unchanged.
  static String suggestedFileName(String type, {String? code}) {
    if (type.trim().toLowerCase() == 'go' && code != null) {
      return GoSourceFileName.suggested(code);
    }
    final mainFile = _templateForType(type)?.mainFile;
    return mainFile == null ? 'snippet.txt' : p.basename(mainFile);
  }

  /// The runnable entry class name inferred from [code], defaulting to `Main`.
  ///
  /// Used to initialize the import dialog with the bare class name (no
  /// `.java`). Falls back to `Main` when the source cannot be interpreted.
  static String suggestedClassName(String code) {
    if (code.trim().isEmpty) return 'Main';
    try {
      return JavaSourceRenamer.analyze(code).className;
    } on JavaSourceRenameException {
      return 'Main';
    }
  }

  /// Whether [name] is a legal simple Java class name (identifier, not a
  /// keyword, no path separators or traversal).
  static bool isValidClassName(String name) {
    final trimmed = name.trim();
    if (trimmed != name) return false;
    if (!_javaIdentifier.hasMatch(trimmed)) return false;
    if (_javaKeywords.contains(trimmed)) return false;
    return true;
  }

  /// Normalizes pasted class-name input: trims, strips a single trailing
  /// `.java` extension, and strips any path prefix so a pasted filename becomes
  /// the bare class name. Throws when the result is not a legal class name.
  static String normalizeClassNameInput(String raw) {
    var value = raw.trim();
    if (value.toLowerCase().endsWith('.java')) {
      value = value.substring(0, value.length - '.java'.length);
    }
    // Drop any directory prefix from a pasted path.
    value = value.replaceAll('\\', '/');
    final slash = value.lastIndexOf('/');
    if (slash >= 0) value = value.substring(slash + 1);
    if (!isValidClassName(value)) {
      throw const CodeImportException(CodeImportFailure.invalidFileName);
    }
    return value;
  }

  /// The `.java` file name for a class name, formed exactly `<ClassName>.java`.
  static String javaFileNameForClass(String className) {
    if (!isValidClassName(className)) {
      throw const CodeImportException(CodeImportFailure.invalidFileName);
    }
    return '$className.java';
  }

  /// Resolves the import target for [example] from the raw dialog value.
  ///
  /// For Java this returns the `<ClassName>.java` file name and the source with
  /// the entry class renamed to `<ClassName>` (declaration, constructors and
  /// self-references), preserving comments, string/char/text-block literals,
  /// package statements and formatting. For other languages it returns the raw
  /// value and the example's code unchanged.
  ///
  /// Throws [CodeImportException] when the Java source cannot be safely
  /// interpreted or the rename would collide, so a renamed file is never written
  /// with stale class code.
  static ({String fileName, String code}) resolveImport(
    ExampleCode example,
    String rawName,
  ) {
    if (!isJavaType(example.type)) {
      _validateFileName(rawName);
      return (fileName: rawName, code: example.code);
    }
    final className = normalizeClassNameInput(rawName);
    final fileName = javaFileNameForClass(className);
    final JavaEntryInfo info;
    try {
      info = JavaSourceRenamer.analyze(example.code);
    } on JavaSourceRenameException {
      throw const CodeImportException(CodeImportFailure.invalidFileName);
    }
    if (info.className == className) {
      return (fileName: fileName, code: example.code);
    }
    try {
      return (
        fileName: fileName,
        code: JavaSourceRenamer.renameEntryClass(
          example.code,
          oldName: info.className,
          newName: className,
        ),
      );
    } on JavaSourceRenameException {
      // Name collision or otherwise unsafe rename: fail clearly instead of
      // writing stale class code under a renamed file.
      throw const CodeImportException(CodeImportFailure.invalidFileName);
    }
  }

  static bool isValidFileName(String fileName) =>
      FileService.isValidEntryName(fileName) &&
      fileName == fileName.trim() &&
      fileName.length <= 255 &&
      !fileName.endsWith('.') &&
      !_controlCharacters.hasMatch(fileName) &&
      !_reservedWindowsName.hasMatch(fileName);

  static void _validateFileName(String fileName) {
    if (!isValidFileName(fileName)) {
      throw CodeImportException(CodeImportFailure.invalidFileName, fileName);
    }
  }

  static void _checkPhysicalParent(File file, String projectRoot) {
    final resolvedParent = file.parent.resolveSymbolicLinksSync();
    final resolvedRoot = Directory(projectRoot).resolveSymbolicLinksSync();
    if (!p.equals(resolvedRoot, resolvedParent) &&
        !p.isWithin(resolvedRoot, resolvedParent)) {
      throw const CodeImportException(CodeImportFailure.projectUnavailable);
    }
  }

  static Future<List<int>?> _writeFile(
    File file,
    String code, {
    required String projectRoot,
    required String projectName,
    bool overwrite = false,
  }) async {
    _checkPhysicalParent(file, projectRoot);
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.file || !overwrite) {
        throw CodeImportException(CodeImportFailure.fileExists, file.path);
      }
      final temporaryDirectory = await file.parent.createTemp(
        '.qfli-code-import-',
      );
      final temporaryFile = File(p.join(temporaryDirectory.path, 'source'));
      try {
        await temporaryFile.writeAsString(code, flush: true);
        final backupError = await FileBackup.backupBeforeOverwrite(
          file,
          projectName: projectName,
        );
        if (backupError != null) {
          throw FileSystemException(backupError, file.path);
        }
        final beforeReplace = beforeProjectFileReplaceForTesting;
        if (beforeReplace != null) await beforeReplace(file.path);
        _checkPhysicalParent(file, projectRoot);
        final targetType = FileSystemEntity.typeSync(
          file.path,
          followLinks: false,
        );
        if (targetType != FileSystemEntityType.file &&
            targetType != FileSystemEntityType.notFound) {
          throw CodeImportException(CodeImportFailure.fileExists, file.path);
        }
        // Snapshot the bytes actually replaced, after all asynchronous work.
        // No same-isolate save can run between this snapshot and the rename.
        final original = targetType == FileSystemEntityType.file
            ? file.readAsBytesSync()
            : null;
        temporaryFile.renameSync(file.path);
        return original;
      } finally {
        try {
          await temporaryFile.delete();
        } on FileSystemException {
          // A successful rename already moved the temporary file.
        }
        try {
          await temporaryDirectory.delete();
        } on FileSystemException {
          // Never delete unrelated entries that may have appeared in the directory.
        }
      }
    }
    final expectedBytes = utf8.encode(code);
    // Keep the final checks, reservation and write in one synchronous section.
    // A same-isolate save must see either no file or the complete import.
    _checkPhysicalParent(file, projectRoot);
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw CodeImportException(CodeImportFailure.fileExists, file.path);
    }
    try {
      file.createSync(exclusive: true);
    } on FileSystemException {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw CodeImportException(CodeImportFailure.fileExists, file.path);
      }
      rethrow;
    }
    try {
      afterProjectFileCreateForTesting?.call(file.path);
      file.writeAsStringSync(code, flush: true);
    } catch (error, stack) {
      var recovered = false;
      Object? cleanupError;
      try {
        recovered = _removeFailedNewFile(file, projectRoot, expectedBytes);
      } on Object catch (failure) {
        cleanupError = failure;
      }
      if (!recovered) {
        throw FileSystemException(
          'Import write failed ($error); cleanup conflict: current target '
          'preserved${cleanupError == null ? '' : '; cleanup failed ($cleanupError)'}',
          file.path,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
    return null;
  }

  static bool _removeFailedNewFile(
    File file,
    String projectRoot,
    List<int> expectedBytes,
  ) {
    _checkPhysicalParent(file, projectRoot);
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.file) return false;
    final current = file.readAsBytesSync();
    // A failed write may have left unknown partial content. Preserve that too:
    // without an OS identity/CAS primitive it cannot safely be called ours.
    if (current.isNotEmpty && !listEquals(current, expectedBytes)) return false;
    file.deleteSync();
    return true;
  }

  static Future<CodeImportResult> openInEditor({
    required ExampleCode example,
    required String fileName,
    String? location,
  }) async {
    final resolved = resolveImport(example, fileName);
    _validateFileName(resolved.fileName);
    final base = location ?? await AppPaths.storageDirectory();
    if (base == null || base.trim().isEmpty || !Directory(base).existsSync()) {
      throw const CodeImportException(CodeImportFailure.storageUnavailable);
    }
    final snippets = Directory(p.join(base, 'code_snippets'));
    await snippets.create(recursive: true);
    final directory = await snippets.createTemp('snippet_');
    final template = _templateForType(example.type);
    final entryFile = p.join(
      p.dirname(template?.mainFile ?? 'src/snippet.txt'),
      resolved.fileName,
    );
    final file = File(p.join(directory.path, entryFile));
    try {
      await _writeProjectFiles(
        root: directory.path,
        files: projectFiles(
          example: example,
          entryFile: entryFile,
          code: resolved.code,
        ),
        projectName: example.title,
      );
      final project = Project.create(
        name: example.title.trim().isEmpty
            ? p.basenameWithoutExtension(resolved.fileName)
            : example.title,
        path: directory.path,
        type: template?.type ?? example.type.trim().toLowerCase(),
        language: template?.language ?? example.type.trim(),
      );
      await ProjectConfig.write(
        projectRoot: project.path,
        name: project.name,
        language: project.language,
        type: project.type,
        entryFile: entryFile,
        strict: true,
      );
      return (project: project, path: file.path);
    } catch (_) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Preserve the import error if its new directory cannot be removed.
      }
      rethrow;
    }
  }

  static String destinationPath({
    required Project project,
    required ExampleCode example,
    required String fileName,
  }) {
    _validateFileName(fileName);
    final directory = Directory(project.path);
    if (project.isCloud ||
        project.path.trim().isEmpty ||
        !directory.existsSync()) {
      throw const CodeImportException(CodeImportFailure.projectUnavailable);
    }
    final template =
        _templateForType(project.type) ??
        ProjectTemplate.fromLanguage(project.language) ??
        _templateForType(example.type);
    final folder = p.dirname(template?.mainFile ?? 'src/snippet.txt');
    return p.normalize(p.join(directory.absolute.path, folder, fileName));
  }

  static Future<CodeImportResult> importIntoProject({
    required Project project,
    required ExampleCode example,
    required String fileName,
    bool overwrite = false,
  }) async {
    final resolved = resolveImport(example, fileName);
    final file = File(
      destinationPath(
        project: project,
        example: example,
        fileName: resolved.fileName,
      ),
    );
    await _writeProjectFiles(
      root: project.path,
      files: projectFiles(
        example: example,
        entryFile: p.relative(file.path, from: project.path),
        code: resolved.code,
      ),
      projectName: project.name,
      overwrite: overwrite,
    );
    return (project: project, path: file.path);
  }
}
