import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/tutorial.dart';
import 'app_paths.dart';
import 'file_backup.dart';
import 'file_service.dart';
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
  static final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f]');
  static final RegExp _reservedWindowsName = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3]|CONIN\$|CONOUT\$)(\.|$)',
    caseSensitive: false,
  );

  /// Java reserved words that cannot be a class name.
  static const Set<String> _javaKeywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
    'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package',
    'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp',
    'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient',
    'try', 'void', 'volatile', 'while', 'true', 'false', 'null', 'var', 'record',
    'sealed', 'permits', 'yield',
  };

  static final RegExp _javaIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Whether [type] is Java (case-insensitive).
  static bool isJavaType(String type) => type.trim().toLowerCase() == 'java';

  static ProjectTemplate? _templateForType(String type) =>
      ProjectTemplate.fromType(type) ??
      (type.trim().toLowerCase() == 'html' ? ProjectTemplate.html : null);

  static String suggestedFileName(String type) {
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
      _validateFileName(rawName.trim());
      return (fileName: rawName.trim(), code: example.code);
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

  static Future<void> _writeFile(
    File file,
    String code, {
    required String projectName,
    bool overwrite = false,
  }) async {
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
        final targetType = FileSystemEntity.typeSync(
          file.path,
          followLinks: false,
        );
        if (targetType != FileSystemEntityType.file &&
            targetType != FileSystemEntityType.notFound) {
          throw CodeImportException(CodeImportFailure.fileExists, file.path);
        }
        await temporaryFile.rename(file.path);
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
      return;
    }
    // Reserve the name exclusively so simultaneous imports cannot overwrite it.
    try {
      await file.create(exclusive: true);
    } on FileSystemException {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw CodeImportException(CodeImportFailure.fileExists, file.path);
      }
      rethrow;
    }
    try {
      await file.writeAsString(code, flush: true);
    } catch (_) {
      try {
        await file.delete();
      } on FileSystemException {
        // Preserve the write failure when cleaning our exclusively created file.
      }
      rethrow;
    }
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
      await file.parent.create(recursive: true);
      await _writeFile(file, resolved.code, projectName: example.title);
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
    final directory = Directory(project.path);
    await file.parent.create(recursive: true);
    final projectRoot = directory.resolveSymbolicLinksSync();
    final parentPath = file.parent.resolveSymbolicLinksSync();
    if (!p.equals(projectRoot, parentPath) &&
        !p.isWithin(projectRoot, parentPath)) {
      throw const CodeImportException(CodeImportFailure.projectUnavailable);
    }
    await _writeFile(
      file,
      resolved.code,
      projectName: project.name,
      overwrite: overwrite,
    );
    return (project: project, path: file.path);
  }
}
