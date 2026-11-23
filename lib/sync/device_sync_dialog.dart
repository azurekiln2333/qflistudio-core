import 'dart:async';

import 'package:flutter/material.dart';

import 'device_file_port.dart';
import 'device_sync.dart';
import 'sync_cache.dart';

/// Ask the user before a transfer whose size is worth mentioning.
///
/// The number comes from the manifest, so it is what the phone will download,
/// not the size of the copy on disk.
Future<bool> confirmDeviceSync(
  BuildContext context, {
  required int bytes,
  required int files,
}) async {
  final size = _formatBytes(bytes);
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('从电脑同步这个项目'),
      content: Text('将下载 $files 个文件，约 $size。\n只传输变化的文件，未变化的内容不会重复下载。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('开始同步'),
        ),
      ],
    ),
  );
  return answer == true;
}

/// Run one device sync and report what happened.
///
/// The caller owns the port and the local directory: this dialog only asks the
/// user to confirm, runs [DeviceSyncService], and shows progress. Returning
/// false means the user cancelled before any byte was transferred.
Future<bool> runDeviceSync(
  BuildContext context, {
  required DeviceFilePort port,
  required String remoteRoot,
  required String localRoot,
  String cacheKey = '',
  SyncCache? cache,
  bool confirmBeforeDownload = true,
}) async {
  final service = DeviceSyncService(port: port, cache: cache);
  final SyncPlan plan;
  try {
    plan = await service.plan(
      remoteRoot: remoteRoot,
      localRoot: localRoot,
      cacheKey: cacheKey,
    );
  } on DeviceSyncException catch (error) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法同步'),
          content: Text(error.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
    return false;
  }

  if (plan.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这个项目已经是最新的')));
    }
    return true;
  }
  if (confirmBeforeDownload && plan.bytes > 0) {
    if (!context.mounted) return false;
    final confirmed = await confirmDeviceSync(
      context,
      bytes: plan.bytes,
      files: plan.downloads.length,
    );
    if (!confirmed) return false;
  }

  final progress = ValueNotifier<SyncProgress>(
    SyncProgress(
      doneFiles: 0,
      totalFiles: plan.downloads.length,
      doneBytes: 0,
      totalBytes: plan.bytes,
    ),
  );
  try {
    if (context.mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _SyncProgressDialog(progress: progress),
        ),
      );
    }
    final report = await service.apply(
      plan,
      onProgress: (value) {
        progress.value = value;
      },
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(report.completed ? '同步完成' : '同步未完成'),
          content: Text(
            report.completed
                ? '写入 ${report.writtenFiles} 个文件，删除 ${report.deletedEntries} 项，'
                      '共 ${_formatBytes(report.bytes)}。'
                : '${report.failure ?? '同步中断'}。已完成写入的文件保持原样，下次同步会继续。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
    return report.completed;
  } finally {
    progress.dispose();
  }
}

class _SyncProgressDialog extends StatelessWidget {
  const _SyncProgressDialog({required this.progress});

  final ValueNotifier<SyncProgress> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在同步'),
      content: ValueListenableBuilder<SyncProgress>(
        valueListenable: progress,
        builder: (context, value, _) {
          final total = value.totalFiles == 0 ? 1 : value.totalFiles;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LinearProgressIndicator(value: value.doneFiles / total),
              const SizedBox(height: 12),
              Text('${value.doneFiles} / ${value.totalFiles} 个文件'),
              if (value.path.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  value.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
