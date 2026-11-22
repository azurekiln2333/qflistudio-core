/// Trellis 项目读取：只读 `.trellis` 下的普通文件，不跟随符号链接。
///
/// 识别条件是项目根目录存在普通 `.trellis` 目录，且其中有一份非空的
/// `workflow.md`。任务、开发者与规范索引都由本文件直接解析——本文件**从不**
/// 执行脚本。官方脚本 `get_context.py` 只在 `trellis_context.dart` 里、且两道
/// 开关都打开时才会运行，否则回退到这里的结果。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 任务所处的工作流阶段。
///
/// 阶段编号对应 `.trellis/workflow.md` 的 Phase 1/2/3。
enum TrellisTaskPhase {
  planning('阶段 1 Plan', '1.1'),
  executing('阶段 2 Execute', '2.1'),
  finishing('阶段 3 Finish', '3.3'),
  archived('已归档', ''),
  unknown('未知阶段', '');

  const TrellisTaskPhase(this.label, this.step);

  /// 可直接显示的阶段名。
  final String label;

  /// 该阶段的建议起始步骤；空串表示没有步骤。
  final String step;
}

/// 任务目录里的一份产物文档。
class TrellisTaskDoc {
  const TrellisTaskDoc({
    required this.name,
    required this.relativePath,
    required this.exists,
  });

  /// 文件名，例如 `prd.md`。
  final String name;

  /// 相对项目根的路径。
  final String relativePath;

  final bool exists;
}

/// 一个 Trellis 任务的只读视图，来自 `task.json`。
class TrellisTask {
  const TrellisTask({
    required this.dirName,
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.docs,
    this.priority,
    this.assignee,
    this.creator,
    this.parent,
    this.children = const [],
    this.createdAt,
    this.completedAt,
  });

  /// 任务目录名，例如 `11-22-harness-hub`。
  final String dirName;

  /// `task.json` 的 `id`。
  final String id;

  final String title;
  final String description;

  /// 原始状态：`planning`、`in_progress`、`completed` 等。
  final String status;

  /// prd、design、implement 三份产物及其存在性。
  final List<TrellisTaskDoc> docs;

  final String? priority;
  final String? assignee;
  final String? creator;

  /// 父任务名；没有父任务时为 null。
  final String? parent;

  /// 子任务名。
  final List<String> children;

  final DateTime? createdAt;
  final DateTime? completedAt;

  /// 任务目录，相对项目根。
  String get relativePath => '.trellis/tasks/$dirName';

  /// 是否还需要跟进。已归档、已完成、已取消的任务都不算活跃。
  bool get isActive =>
      !const {'completed', 'done', 'archived', 'cancelled'}.contains(status);

  /// 当前阶段的显示信息。
  TrellisTaskPhase get phase => switch (status) {
    'planning' => TrellisTaskPhase.planning,
    'in_progress' => TrellisTaskPhase.executing,
    'completed' || 'done' => TrellisTaskPhase.finishing,
    'archived' => TrellisTaskPhase.archived,
    _ => TrellisTaskPhase.unknown,
  };

  /// 有内容的产物名。
  List<String> get existingDocs => [
    for (final doc in docs)
      if (doc.exists) doc.name,
  ];
}

/// `.trellis/spec/<层>/index.md` 的只读视图。
class TrellisSpecIndex {
  const TrellisSpecIndex({required this.layer, required this.relativePath});

  /// 层名，例如 `frontend`、`backend`。
  final String layer;

  /// 相对项目根的路径。
  final String relativePath;
}

/// 一个已识别的 Trellis 项目。
class TrellisProject {
  const TrellisProject({
    required this.root,
    required this.developer,
    required this.tasks,
    required this.currentTask,
    required this.specIndexes,
  });

  /// 项目根目录的绝对路径。
  final String root;

  /// `.trellis/.developer` 里的名字；没有时为空串。
  final String developer;

  /// `.trellis/tasks/*/task.json` 解析出的全部任务，按目录名排序。
  final List<TrellisTask> tasks;

  /// 当前任务；无法确定时为 null。
  final TrellisTask? currentTask;

  /// 存在 `index.md` 的规范层。
  final List<TrellisSpecIndex> specIndexes;

  /// 工作流文件的相对路径。
  static const String workflowPath = '.trellis/workflow.md';

  /// 任务文件的字节上限；超过上限的任务跳过。
  static const int maxTaskJsonBytes = 64 * 1024;

  /// 需要跟进的任务。
  List<TrellisTask> get activeTasks => [
    for (final task in tasks)
      if (task.isActive) task,
  ];

  /// 分配给 [developer] 的活跃任务。
  List<TrellisTask> activeTasksOf(String developer) => [
    for (final task in activeTasks)
      if (task.assignee == developer) task,
  ];

  /// 按任务目录名查找。
  TrellisTask? taskNamed(String dirName) {
    for (final task in tasks) {
      if (task.dirName == dirName) return task;
    }
    return null;
  }

  /// 判断项目根下是否有可用的 Trellis 工作流。
  ///
  /// `.trellis` 或 `workflow.md` 是链接时视为不可用，与规则加载保持一致。
  static bool hasWorkflow(String projectRoot) {
    final directory = p.join(projectRoot, '.trellis');
    final workflow = File(p.join(directory, 'workflow.md'));
    try {
      if (FileSystemEntity.typeSync(directory, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      if (FileSystemEntity.typeSync(workflow.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return false;
      }
      return readTextHead(workflow, 4 * 1024).trim().isNotEmpty;
    } on FileSystemException {
      return false;
    }
  }

  /// 解析项目；没有可用工作流时返回 null。
  ///
  /// [currentTaskName] 可显式指定当前任务目录名；为 null 时读
  /// `.trellis/.runtime/sessions/` 里最近一次记录的指针。
  static Future<TrellisProject?> load(
    String projectRoot, {
    String? currentTaskName,
  }) async {
    if (!hasWorkflow(projectRoot)) return null;
    final developer = await _readDeveloper(projectRoot);
    final tasks = await _readTasks(projectRoot);
    final specIndexes = await _readSpecIndexes(projectRoot);
    final resolvedName =
        currentTaskName ?? await _readRuntimeTaskName(projectRoot);
    TrellisTask? current;
    for (final task in tasks) {
      if (task.dirName == resolvedName) {
        current = task;
        break;
      }
    }
    return TrellisProject(
      root: projectRoot,
      developer: developer,
      tasks: tasks,
      currentTask: current,
      specIndexes: specIndexes,
    );
  }

  static Future<String> _readDeveloper(String projectRoot) async {
    final file = File(p.join(projectRoot, '.trellis', '.developer'));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return '';
    }
    final String text;
    try {
      text = readTextHead(file, 4 * 1024);
    } on FileSystemException {
      return '';
    }
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('name=')) continue;
      final name = trimmed.substring(5).trim();
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  /// 读任务目录；单个任务坏了只跳过它。
  static Future<List<TrellisTask>> _readTasks(String projectRoot) async {
    final dir = p.join(projectRoot, '.trellis', 'tasks');
    if (FileSystemEntity.typeSync(dir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return const [];
    }
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list(followLinks: false).toList();
    } on FileSystemException {
      return const [];
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    final tasks = <TrellisTask>[];
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final dirName = p.basename(entry.path);
      final file = File(p.join(entry.path, 'task.json'));
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final task = _taskFromFile(projectRoot, dirName, file);
      if (task != null) tasks.add(task);
    }
    return tasks;
  }

  static TrellisTask? _taskFromFile(
    String projectRoot,
    String dirName,
    File file,
  ) {
    final String text;
    try {
      text = readTextHead(file, maxTaskJsonBytes);
    } on FileSystemException {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final title = _string(decoded['title']) ?? _string(decoded['name']);
    if (title == null || title.isEmpty) return null;
    final base = '.trellis/tasks/$dirName';
    final docs = [
      for (final name in kVibeTrellisTaskDocs)
        TrellisTaskDoc(
          name: name,
          relativePath: '$base/$name',
          exists:
              FileSystemEntity.typeSync(
                p.joinAll([projectRoot, ...'$base/$name'.split('/')]),
                followLinks: false,
              ) ==
              FileSystemEntityType.file,
        ),
    ];
    return TrellisTask(
      dirName: dirName,
      id: _string(decoded['id']) ?? dirName,
      title: title,
      description: _string(decoded['description']) ?? '',
      status: _string(decoded['status']) ?? 'unknown',
      docs: docs,
      priority: _string(decoded['priority']),
      assignee: _string(decoded['assignee']),
      creator: _string(decoded['creator']),
      parent: _string(decoded['parent']),
      children: _stringList(decoded['children']),
      createdAt: _date(decoded['createdAt']),
      completedAt: _date(decoded['completedAt']),
    );
  }

  static Future<List<TrellisSpecIndex>> _readSpecIndexes(
    String projectRoot,
  ) async {
    final dir = p.join(projectRoot, '.trellis', 'spec');
    if (FileSystemEntity.typeSync(dir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return const [];
    }
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list(followLinks: false).toList();
    } on FileSystemException {
      return const [];
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    final indexes = <TrellisSpecIndex>[];
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final layer = p.basename(entry.path);
      final relative = '.trellis/spec/$layer/index.md';
      final file = File(p.joinAll([projectRoot, ...relative.split('/')]));
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      indexes.add(TrellisSpecIndex(layer: layer, relativePath: relative));
    }
    return indexes;
  }

  /// 读最近的会话指针，取其中的当前任务目录名。
  ///
  /// 指针只含平台名、时间与任务路径，不含任何凭据。读不到时返回 null。
  static Future<String?> _readRuntimeTaskName(String projectRoot) async {
    final dir = p.join(projectRoot, '.trellis', '.runtime', 'sessions');
    if (FileSystemEntity.typeSync(dir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list(followLinks: false).toList();
    } on FileSystemException {
      return null;
    }
    String? bestName;
    DateTime? bestSeen;
    for (final entry in entries) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final String text;
      try {
        text = readTextHead(entry, 16 * 1024);
      } on FileSystemException {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final name = taskNameOfRef(_string(decoded['current_task']));
      if (name == null) continue;
      final seen = _date(decoded['last_seen_at']);
      if (bestName == null ||
          (seen != null && (bestSeen == null || seen.isAfter(bestSeen)))) {
        bestName = name;
        bestSeen = seen;
      }
    }
    return bestName;
  }
}

/// 任务产物文件名，按阅读顺序。
const List<String> kVibeTrellisTaskDocs = [
  'prd.md',
  'design.md',
  'implement.md',
];

/// 把 `.trellis/tasks/<name>` 这样的引用换成任务目录名。
String? taskNameOfRef(String? ref) {
  if (ref == null) return null;
  final normalized = ref.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) return null;
  final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  final last = segments.last;
  return last.isEmpty ? null : last;
}

/// 只读文件开头 [maxBytes] 字节，按 UTF-8 宽松解码。
///
/// 读不到时抛 [FileSystemException]，由调用方决定跳过。
String readTextHead(File file, int maxBytes) {
  final length = file.lengthSync();
  if (length <= maxBytes) return file.readAsStringSync();
  final handle = file.openSync();
  try {
    return utf8.decode(handle.readSync(maxBytes), allowMalformed: true);
  } finally {
    handle.closeSync();
  }
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is String && entry.trim().isNotEmpty) entry.trim(),
  ];
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value.trim());
}
