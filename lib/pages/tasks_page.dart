import 'dart:async';

import 'package:flutter/material.dart';

import '../community/models.dart';
import '../services/api_client.dart';
import '../services/task_activity_service.dart';
import '../store/auth_store.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.auth});

  final AuthStore auth;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final TaskActivityService _activity = TaskActivityService.instance;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _activity.initialize();
      if (mounted) setState(() {});
      unawaited(_activity.refreshIfDue(widget.auth));
    });
  }

  Future<void> _checkin() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await _activity.checkin(widget.auth);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyChecked
                ? '今天已签到'
                : '签到成功，获得 ${result.reward} 积分，已连续 ${result.streak} 天',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('每日任务'),
      actions: [
        IconButton(
          tooltip: '刷新任务',
          icon: const Icon(Icons.refresh),
          onPressed: () => _activity.refreshIfDue(widget.auth, force: true),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_activity, widget.auth]),
      builder: (context, _) {
        final snapshot = _activity.snapshotFor(widget.auth);
        final tasks = _activity.visibleTasks(widget.auth);
        final pending = _activity.pendingCount(widget.auth);
        final scheme = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: () => _activity.refreshIfDue(widget.auth, force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              Card.filled(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.stars_rounded,
                        size: 32,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 14),
                      const Expanded(child: Text('可用积分')),
                      Text(
                        '${widget.auth.user?.points ?? snapshot?.points ?? 0}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (pending > 0 || _activity.lastError != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _activity.lastError ?? '$pending 次操作待同步',
                        style: TextStyle(
                          color: _activity.lastError == null
                              ? scheme.onSurfaceVariant
                              : scheme.error,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '重试同步',
                      icon: const Icon(Icons.sync),
                      onPressed: () =>
                          _activity.refreshIfDue(widget.auth, force: true),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text('今日进度', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (snapshot == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('今天暂无任务')),
                )
              else
                for (final task in tasks) _taskRow(task, scheme),
            ],
          ),
        );
      },
    ),
  );

  Widget _taskRow(TaskInfo task, ColorScheme scheme) {
    final progress = task.progress.clamp(0, task.target);
    final isCheckin = task.eventKey == 'checkin';
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            task.done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: task.done ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(task.label),
          subtitle: Text('+${task.reward} 积分'),
          trailing: isCheckin && !task.done
              ? FilledButton(
                  onPressed: _checking ? null : _checkin,
                  child: const Text('签到'),
                )
              : Text(
                  '${task.progress}/${task.target}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
        ),
        LinearProgressIndicator(
          value: progress / task.target,
          minHeight: 3,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
