import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../services/app_paths.dart';
import '../services/picker_service.dart';
import '../services/recovery_service.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';

String recoveryTitle(RecoveryKind kind) => switch (kind) {
  RecoveryKind.projects => '项目回收站',
  RecoveryKind.files => '文件回收站',
  RecoveryKind.backups => '文件备份',
  RecoveryKind.history => '历史版本',
};

IconData recoveryIcon(RecoveryKind kind) => switch (kind) {
  RecoveryKind.projects => Icons.folder_delete_outlined,
  RecoveryKind.files => Icons.delete_sweep_outlined,
  RecoveryKind.backups => Icons.backup_outlined,
  RecoveryKind.history => Icons.history,
};

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({
    super.key,
    required this.kind,
    required this.store,
    required this.settings,
  });

  final RecoveryKind kind;
  final ProjectStore store;
  final SettingsStore settings;

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  late Future<List<RecoveryEntry>> _entries = RecoveryService.list(widget.kind);
  bool _busy = false;

  Future<void> _refresh() async {
    final request = RecoveryService.list(widget.kind);
    setState(() => _entries = request);
    await request;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(recoveryTitle(widget.kind)),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (widget.kind == RecoveryKind.backups)
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => SwitchListTile(
              title: const Text('保存前备份'),
              value: widget.settings.backupEnabled,
              onChanged: widget.settings.setBackupEnabled,
            ),
          ),
        Expanded(
          child: FutureBuilder<List<RecoveryEntry>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('读取失败：${snapshot.error}'),
                  ),
                );
              }
              final entries = snapshot.data ?? [];
              final groups = <String, List<RecoveryEntry>>{};
              if (widget.kind == RecoveryKind.history) {
                for (final entry in entries) {
                  (groups[entry.groupKey] ??= []).add(entry);
                }
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: entries.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(48),
                            child: Column(
                              children: [
                                Icon(
                                  recoveryIcon(widget.kind),
                                  size: 40,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.kind == RecoveryKind.history
                                      ? '暂无历史版本'
                                      : '暂无记录',
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: widget.kind == RecoveryKind.history
                            ? groups.length
                            : entries.length,
                        itemBuilder: (context, index) {
                          if (widget.kind != RecoveryKind.history) {
                            return _entry(entries[index]);
                          }
                          final versions = groups.values.elementAt(index);
                          return ExpansionTile(
                            leading: const Icon(Icons.history),
                            title: Text(
                              versions.first.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${versions.first.originalPath ?? versions.first.projectName ?? ''} · ${versions.length} 个版本',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            children: [
                              for (final version in versions)
                                _entry(version, timeline: true),
                            ],
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _entry(RecoveryEntry entry, {bool timeline = false}) => ListTile(
    leading: Icon(
      entry.archive ? Icons.inventory_2_outlined : Icons.description_outlined,
    ),
    title: Text(
      timeline
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.time)
          : entry.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      [
        if (!timeline) DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.time),
        if (entry.projectName?.isNotEmpty == true) entry.projectName!,
        if (widget.kind == RecoveryKind.projects && entry.originalPath != null)
          entry.originalPath!,
        '${(entry.size / 1024).toStringAsFixed(1)} KB',
      ].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: _busy ? null : () => _preview(entry),
    trailing: PopupMenuButton<String>(
      enabled: !_busy,
      tooltip: '操作',
      onSelected: (value) =>
          value == 'restore' ? _restore(entry) : _delete(entry),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'restore',
          child: ListTile(
            leading: Icon(Icons.restore),
            title: Text('恢复'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_forever_outlined),
            title: Text('永久删除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ),
  );

  Future<void> _preview(RecoveryEntry entry) async {
    try {
      final text = await RecoveryService.preview(entry);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(entry.name)),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(text),
            ),
          ),
        ),
      );
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _restore(RecoveryEntry entry) async {
    final root = await AppPaths.projectsRoot(create: true);
    if (!mounted) return;
    var defaultPath =
        entry.originalPath ?? (root == null ? '' : p.join(root, entry.name));
    if (widget.kind == RecoveryKind.projects) {
      if (entry.originalPath == null && root != null) {
        defaultPath = AppPaths.availableProjectPath(
          directory: AppPaths.languageProjectsRoot(
            root,
            type: entry.type,
            language: entry.language,
          ),
          name: entry.name,
        );
      } else if (entry.originalPath != null &&
          FileSystemEntity.typeSync(defaultPath, followLinks: false) !=
              FileSystemEntityType.notFound) {
        defaultPath = AppPaths.availableProjectPath(
          directory: p.dirname(defaultPath),
          name: entry.name,
        );
      }
    }
    final path = TextEditingController(text: defaultPath);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('恢复 ${entry.name}'),
        content: TextField(
          controller: path,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: '恢复位置',
            suffixIcon: IconButton(
              tooltip: '选择目录',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () async {
                try {
                  final chosen = await PickerService.pickDocument(folder: true);
                  if (context.mounted && chosen?.path != null) {
                    path.text = p.join(chosen!.path!, entry.name);
                  }
                } catch (error) {
                  if (context.mounted) _error(error);
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    final destination = path.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    path.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await RecoveryService.restore(entry, destination);
      if (widget.kind == RecoveryKind.projects &&
          await Directory(destination).exists()) {
        final result = await widget.store.addExisting(destination);
        if (result.error != null) {
          throw FileSystemException('文件已恢复，但项目登记失败：${result.error}');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复')));
        await _refresh();
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(RecoveryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除这条记录？'),
        content: Text(entry.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await RecoveryService.delete(entry);
      if (mounted) await _refresh();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
