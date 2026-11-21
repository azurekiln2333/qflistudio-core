import 'package:flutter/material.dart';

import '../git/git_clone_progress.dart';

/// One active clone row in the Home task list.
class HomeGitCloneTask {
  const HomeGitCloneTask({
    required this.id,
    required this.name,
    required this.progress,
    required this.onCancel,
    this.cancelling = false,
  });

  final int id;
  final String name;
  final GitCloneProgress progress;
  final VoidCallback onCancel;
  final bool cancelling;
}

/// Compact, bounded progress display for independently cancellable clones.
class HomeGitCloneTasks extends StatelessWidget {
  const HomeGitCloneTasks({
    super.key,
    required this.tasks,
    this.maxHeight = defaultMaxHeight,
  });

  static const double defaultMaxHeight = 190;
  final double maxHeight;
  final List<HomeGitCloneTask> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      key: const ValueKey('home-git-clone-tasks'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.builder(
        itemCount: tasks.length,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _CloneTaskRow(task: tasks[index]),
        ),
      ),
    );
  }
}

class _CloneTaskRow extends StatelessWidget {
  const _CloneTaskRow({required this.task});

  final HomeGitCloneTask task;

  @override
  Widget build(BuildContext context) {
    final progress = task.progress;
    final fraction = progress.fraction;
    final details = StringBuffer(_stageLabel(progress.stage));
    if (fraction != null) {
      details.write(' · ${(fraction * 100).round()}%');
    } else if (progress.receivedBytes > 0) {
      details.write(' · ${_formatBytes(progress.receivedBytes)}');
    }

    return Row(
      key: ValueKey('home-git-clone-task-${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      details.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          key: ValueKey('home-git-clone-cancel-${task.id}'),
          onPressed:
              task.cancelling || progress.stage == GitCloneStage.registering
              ? null
              : task.onCancel,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(48, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            task.cancelling
                ? '取消中…'
                : progress.stage == GitCloneStage.registering
                ? '登记中…'
                : '取消',
          ),
        ),
      ],
    );
  }

  static String _stageLabel(GitCloneStage stage) => switch (stage) {
    GitCloneStage.preparing => '准备中',
    GitCloneStage.connecting => '连接中',
    GitCloneStage.receiving => '接收对象',
    GitCloneStage.resolving => '解析对象',
    GitCloneStage.checkout => '检出文件',
    GitCloneStage.registering => '登记项目',
  };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
