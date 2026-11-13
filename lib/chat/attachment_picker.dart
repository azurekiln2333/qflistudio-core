import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';
import '../workspace/saved_workspace.dart';
import '../workspace/workspace_store.dart';

/// 加号的两个附件来源，见 design.md §2 与 §4 第 3 条。
enum AttachmentSource {
  /// 当前项目内的文件，agent 可以直接读。
  project,

  /// 同一已保存工作区内其它项目的文件。
  workspace,
}

/// 一个可附件的文件。
@immutable
class AttachmentFile {
  const AttachmentFile({
    required this.label,
    required this.path,
    required this.group,
    this.readOnly = false,
  });

  /// 列表里显示的名字。
  final String label;

  /// 传给 agent 的路径，直接进 `attachedPaths`。
  ///
  /// 项目内文件用相对路径（`/` 分隔）。项目外文件用绝对路径，
  /// 由 harness 登记进本会话的只读白名单。
  final String path;

  /// 分组标题：项目名，或「本项目」。
  final String group;

  /// 只读：agent 能读正文，不能写、不能改。项目外文件为 true。
  final bool readOnly;
}

/// 项目内文件树，按相对路径排序。
///
/// 路径用相对路径（`/` 分隔）：agent 的 `read_file` 只接受项目内相对路径，
/// 因此这里直接给传参形态，不传绝对路径。
///
/// [limit] 是防御上限：大项目不该把界面拖住。超出时返回已收集的部分，并由
/// 调用方显示提示。
Future<List<AttachmentFile>> listProjectAttachments(
  String projectRoot, {
  int limit = 400,
}) async {
  final files = await _walk(projectRoot, limit: limit);
  final group = p.basename(projectRoot);
  return [
    for (final file in files)
      AttachmentFile(
        label: p.relative(file.path, from: projectRoot).replaceAll('\\', '/'),
        path: p.relative(file.path, from: projectRoot).replaceAll('\\', '/'),
        group: group,
      ),
  ];
}

/// 工作区内其它项目的文件。
///
/// 路径用绝对路径：多根工作区没有唯一的「工作区根」，相对路径会有歧义。
/// 这些文件在项目根之外，agent 只能读、不能写，所以标为只读。
Future<List<AttachmentFile>> listWorkspaceAttachments({
  required String projectRoot,
  required List<SavedWorkspace> workspaces,
  int limit = 400,
}) async {
  final key = workspacePathKey(projectRoot);
  SavedWorkspace? host;
  for (final workspace in workspaces) {
    if (workspace.memberPaths.any((path) => workspacePathKey(path) == key)) {
      host = workspace;
      break;
    }
  }
  if (host == null) return const [];
  final result = <AttachmentFile>[];
  for (final member in host.members) {
    if (workspacePathKey(member.path) == key) continue;
    final files = await _walk(member.path, limit: limit - result.length);
    for (final file in files) {
      result.add(
        AttachmentFile(
          label: p.relative(file.path, from: member.path).replaceAll('\\', '/'),
          path: file.path,
          group: member.name,
          readOnly: true,
        ),
      );
      if (result.length >= limit) return result;
    }
    if (result.length >= limit) return result;
  }
  return result;
}

/// 递归列出文件，跳过点目录与已知的构建产物目录。
Future<List<File>> _walk(String root, {required int limit}) async {
  final directory = Directory(root);
  if (!await directory.exists()) return const [];
  final files = <File>[];
  Future<void> visit(Directory current) async {
    if (files.length >= limit) return;
    final List<FileSystemEntity> children;
    try {
      children = await FileService.listSorted(current.path);
    } on FileSystemException {
      return;
    }
    for (final entity in children) {
      if (files.length >= limit) return;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is Link) continue;
      if (entity is Directory) {
        if (_skipDirs.contains(name.toLowerCase())) continue;
        await visit(entity);
      } else if (entity is File) {
        files.add(entity);
      }
    }
  }

  await visit(directory);
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

const Set<String> _skipDirs = {
  'build',
  'node_modules',
  '.git',
  '.dart_tool',
  'oh_modules',
  'target',
  'dist',
  'out',
};

/// 打开附件选择器，返回用户确认的路径；取消返回 null。
Future<List<String>?> showAttachmentPicker(
  BuildContext context, {
  required AttachmentSource source,
  required String projectRoot,
  required WorkspaceStore workspaces,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AttachmentPickerSheet(
      source: source,
      load: () => switch (source) {
        AttachmentSource.project => listProjectAttachments(projectRoot),
        AttachmentSource.workspace => listWorkspaceAttachments(
          projectRoot: projectRoot,
          workspaces: workspaces.workspaces,
        ),
      },
    ),
  );
}

/// 附件选择面板。多选，确认后一次性返回。
class AttachmentPickerSheet extends StatefulWidget {
  const AttachmentPickerSheet({
    super.key,
    required this.source,
    required this.load,
  });

  final AttachmentSource source;

  /// 候选文件来源；测试可注入固定列表。
  final Future<List<AttachmentFile>> Function() load;

  @override
  State<AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<AttachmentPickerSheet> {
  late Future<List<AttachmentFile>> _future;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  String get _title => switch (widget.source) {
    AttachmentSource.project => '项目文件',
    AttachmentSource.workspace => '工作区文件',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(_title, style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          if (widget.source == AttachmentSource.workspace)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '这些文件来自其它项目，Agent 只读，不能修改。'
                '要改文件就先复制到本项目。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<AttachmentFile>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _emptyState(
                    context,
                    title: '读取文件失败',
                    hint: '${snapshot.error}',
                  );
                }
                final files = snapshot.data ?? const <AttachmentFile>[];
                if (files.isEmpty) {
                  return _emptyState(
                    context,
                    title: widget.source == AttachmentSource.project
                        ? '这个项目还没有文件'
                        : '没有找到工作区文件',
                    hint: widget.source == AttachmentSource.project
                        ? '先在编辑器里新建一个文件，再回来附加。'
                        : '把其它项目加入同一工作区后，这里会列出它们的文件。',
                  );
                }
                return ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return CheckboxListTile(
                      key: ValueKey('attachment-${file.path}'),
                      dense: true,
                      value: _selected.contains(file.path),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(file.path);
                        } else {
                          _selected.remove(file.path);
                        }
                      }),
                      title: Text(
                        file.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      subtitle: Text(
                        file.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  key: const ValueKey('attachment-confirm'),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected.toList()),
                  child: Text(
                    _selected.isEmpty ? '选择文件' : '附加 ${_selected.length} 个文件',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required String title,
    required String hint,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.file_open_outlined,
              size: 28,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // 空状态也要有一个主操作（G7）：这里没有可附加的文件，
            // 能做的只有关掉面板。
            FilledButton.tonal(
              key: const ValueKey('attachment-empty-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }
}
