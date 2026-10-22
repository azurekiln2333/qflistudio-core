import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 项目内会话记忆文件（`<项目>/history.json`）：
/// - 每个文件的光标位置（打开文件时自动定位）
/// - 上次打开的文件列表与激活标签（打开项目时恢复现场）
class FileCursor {
  const FileCursor({
    required this.baseIndex,
    required this.baseOffset,
    required this.extentIndex,
    required this.extentOffset,
  });

  final int baseIndex;
  final int baseOffset;
  final int extentIndex;
  final int extentOffset;

  Map<String, dynamic> toJson() => {
    'baseIndex': baseIndex,
    'baseOffset': baseOffset,
    'extentIndex': extentIndex,
    'extentOffset': extentOffset,
  };

  static FileCursor fromJson(Map<String, dynamic> j) => FileCursor(
    baseIndex: (j['baseIndex'] as num?)?.toInt() ?? 0,
    baseOffset: (j['baseOffset'] as num?)?.toInt() ?? 0,
    extentIndex: (j['extentIndex'] as num?)?.toInt() ?? 0,
    extentOffset: (j['extentOffset'] as num?)?.toInt() ?? 0,
  );
}

/// An ordered workspace tab, relative to its registered owner project.
class ProjectDocumentSession {
  const ProjectDocumentSession({
    required this.projectPath,
    required this.relativePath,
    required this.cursor,
    this.isActive = false,
  });

  final String projectPath;
  final String relativePath;
  final FileCursor cursor;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'projectPath': projectPath,
    'relativePath': relativePath,
    'cursor': cursor.toJson(),
    'isActive': isActive,
  };

  static ProjectDocumentSession? fromJson(Object? value) {
    if (value is! Map ||
        value['projectPath'] is! String ||
        value['relativePath'] is! String ||
        value['cursor'] is! Map) {
      return null;
    }
    try {
      return ProjectDocumentSession(
        projectPath: value['projectPath'] as String,
        relativePath: value['relativePath'] as String,
        cursor: FileCursor.fromJson(
          Map<String, dynamic>.from(value['cursor'] as Map),
        ),
        isActive: value['isActive'] == true,
      );
    } on Object {
      return null;
    }
  }
}

/// 一次会话快照。
class ProjectSession {
  const ProjectSession({
    required this.cursors,
    required this.openFiles,
    required this.activeFile,
    this.expandedDirs = const [],
    this.treeRootExpanded = true,
    this.workspaceRoots = const [],
    this.documents = const [],
  });

  /// 相对路径 → 光标。
  final Map<String, FileCursor> cursors;

  /// 上次打开的文件（相对路径，按标签顺序）。
  final List<String> openFiles;

  /// 上次激活的标签。
  final String? activeFile;

  /// 文件树展开的目录（相对路径）。
  final List<String> expandedDirs;

  /// Old sessions without this field keep the root expanded.
  final bool treeRootExpanded;

  /// Local project roots selected for this editor's workspace.
  final List<String> workspaceRoots;
  final List<ProjectDocumentSession> documents;
}

abstract final class ProjectHistory {
  static final Map<String, Future<void>> _writes = {};

  static File historyFile(String projectPath) =>
      File(p.join(projectPath, 'history.json'));

  static String _queueKey(String projectPath) {
    try {
      // A junction/symlink alias writes the same physical history file. Resolve
      // synchronously so callers enter its lane in invocation order.
      return p.canonicalize(Directory(projectPath).resolveSymbolicLinksSync());
    } on FileSystemException {
      return p.canonicalize(projectPath);
    }
  }

  static Future<ProjectSession> load(String projectPath) async {
    final key = _queueKey(projectPath);
    // A reconstructed explorer can load before its predecessor's unawaited
    // expansion save finishes. Observe all writes already queued for this root.
    while (true) {
      final pending = _writes[key];
      if (pending == null) break;
      await pending;
      if (identical(pending, _writes[key])) break;
    }
    return _read(projectPath);
  }

  static ProjectSession _read(String projectPath) {
    try {
      final file = historyFile(projectPath);
      if (!file.existsSync()) {
        return const ProjectSession(
          cursors: {},
          openFiles: [],
          activeFile: null,
        );
      }
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final files = data['files'] is Map
          ? Map<String, dynamic>.from(data['files'] as Map)
          : <String, dynamic>{};
      return ProjectSession(
        cursors: {
          for (final e in files.entries)
            e.key: FileCursor.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
        },
        openFiles: [
          for (final f in (data['openFiles'] as List? ?? [])) f as String,
        ],
        activeFile: data['activeFile'] as String?,
        expandedDirs: [
          for (final d in (data['expandedDirs'] as List? ?? [])) d as String,
        ],
        treeRootExpanded: data['treeRootExpanded'] as bool? ?? true,
        workspaceRoots: [
          for (final path in (data['workspaceRoots'] as List? ?? []))
            path as String,
        ],
        documents: [
          for (final raw
              in (data['documents'] is List
                      ? data['documents'] as List
                      : const [])
                  .take(512))
            ?ProjectDocumentSession.fromJson(raw),
        ],
      );
    } catch (_) {
      // 配置损坏时按空会话处理。
      return const ProjectSession(
        cursors: {},
        openFiles: [],
        activeFile: null,
        expandedDirs: [],
      );
    }
  }

  /// 只更新文件树展开目录（保留会话其他字段）。
  static Future<void> saveExpandedDirs(
    String projectPath,
    List<String> dirs, {
    bool? treeRootExpanded,
  }) {
    final snapshot = List<String>.of(dirs);
    return _enqueue(projectPath, () async {
      final session = _read(projectPath);
      await _write(
        projectPath,
        cursors: session.cursors,
        openFiles: session.openFiles,
        activeFile: session.activeFile,
        expandedDirs: snapshot,
        treeRootExpanded: treeRootExpanded ?? session.treeRootExpanded,
        workspaceRoots: session.workspaceRoots,
        documents: session.documents,
      );
    });
  }

  /// Updates workspace membership without replacing editor or tree state.
  static Future<void> saveWorkspaceRoots(
    String projectPath,
    List<String> roots,
  ) {
    final snapshot = List<String>.of(roots);
    return _enqueue(projectPath, () async {
      final session = _read(projectPath);
      await _write(
        projectPath,
        cursors: session.cursors,
        openFiles: session.openFiles,
        activeFile: session.activeFile,
        expandedDirs: session.expandedDirs,
        treeRootExpanded: session.treeRootExpanded,
        workspaceRoots: snapshot,
        documents: session.documents,
      );
    });
  }

  static Future<void> save(
    String projectPath, {
    required Map<String, FileCursor> cursors,
    required List<String> openFiles,
    required String? activeFile,
    List<String>? expandedDirs,
    List<ProjectDocumentSession>? documents,
  }) {
    // Capture callers' mutable collections before entering the write queue.
    final cursorSnapshot = Map<String, FileCursor>.of(cursors);
    final fileSnapshot = List<String>.of(openFiles);
    final dirSnapshot = expandedDirs == null
        ? null
        : List<String>.of(expandedDirs);
    final documentSnapshot = documents == null
        ? null
        : List<ProjectDocumentSession>.of(documents);
    return _enqueue(projectPath, () async {
      final session = _read(projectPath);
      await _write(
        projectPath,
        cursors: cursorSnapshot,
        openFiles: fileSnapshot,
        activeFile: activeFile,
        expandedDirs: dirSnapshot ?? session.expandedDirs,
        treeRootExpanded: session.treeRootExpanded,
        workspaceRoots: session.workspaceRoots,
        documents: documentSnapshot ?? session.documents,
      );
    });
  }

  static Future<void> _enqueue(
    String projectPath,
    Future<void> Function() write,
  ) {
    final key = _queueKey(projectPath);
    final previous = _writes[key];
    final next = () async {
      if (previous != null) await previous;
      await write();
    }();
    _writes[key] = next;
    return next.whenComplete(() {
      if (identical(_writes[key], next)) _writes.remove(key);
    });
  }

  static Future<void> _write(
    String projectPath, {
    required Map<String, FileCursor> cursors,
    required List<String> openFiles,
    required String? activeFile,
    required List<String> expandedDirs,
    required bool treeRootExpanded,
    required List<String> workspaceRoots,
    required List<ProjectDocumentSession> documents,
  }) async {
    try {
      final file = historyFile(projectPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'openFiles': openFiles,
          'activeFile': activeFile,
          'expandedDirs': expandedDirs,
          'treeRootExpanded': treeRootExpanded,
          'workspaceRoots': workspaceRoots,
          'documents': [for (final document in documents) document.toJson()],
          'files': {for (final e in cursors.entries) e.key: e.value.toJson()},
        }),
        flush: true,
      );
    } catch (_) {
      // 写失败不打断编辑。
    }
  }
}
