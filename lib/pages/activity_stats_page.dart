import 'dart:async';

import 'package:flutter/material.dart';

import '../services/task_activity_service.dart';
import '../store/auth_store.dart';

class ActivityStatsPage extends StatefulWidget {
  const ActivityStatsPage({super.key, required this.auth});

  final AuthStore auth;

  @override
  State<ActivityStatsPage> createState() => _ActivityStatsPageState();
}

class _ActivityStatsPageState extends State<ActivityStatsPage> {
  final TaskActivityService _activity = TaskActivityService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _activity.initialize();
      if (mounted) setState(() {});
      unawaited(_activity.refreshIfDue(widget.auth));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('统计'),
      actions: [
        IconButton(
          tooltip: '刷新统计',
          icon: const Icon(Icons.refresh),
          onPressed: () => _activity.refreshIfDue(widget.auth, force: true),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_activity, widget.auth]),
      builder: (context, _) {
        final user = widget.auth.user;
        final scheme = Theme.of(context).colorScheme;
        final tasks = _activity
            .visibleTasks(widget.auth)
            .where((task) => task.eventKey != 'checkin')
            .toList();
        final pending = _activity.pendingCount(widget.auth);
        return RefreshIndicator(
          onRefresh: () => _activity.refreshIfDue(widget.auth, force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(child: _summary('可用积分', '${user?.points ?? 0}')),
                  Expanded(
                    child: _summary('累计经验', '${user?.growth.experience ?? 0}'),
                  ),
                  Expanded(
                    child: _summary('连续签到', '${user?.checkinStreak ?? 0} 天'),
                  ),
                ],
              ),
              if (pending > 0 || _activity.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(
                    _activity.lastError ?? '$pending 次本机操作待同步',
                    style: TextStyle(
                      color: _activity.lastError == null
                          ? scheme.onSurfaceVariant
                          : scheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              Text('本机操作', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(flex: 3, child: SizedBox.shrink()),
                  for (final title in const ['今日', '近 7 天', '累计'])
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          title,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(),
              _countRow('创建项目', 'create_project'),
              _countRow('打开项目', 'open_project'),
              _countRow('修改文件', 'save_file'),
              const SizedBox(height: 26),
              Text('今日任务进度', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('暂无任务数据'),
                )
              else
                for (final task in tasks)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(task.label),
                    subtitle: Text('+${task.reward} 积分'),
                    trailing: Text('${task.progress}/${task.target}'),
                  ),
            ],
          ),
        );
      },
    ),
  );

  Widget _summary(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );

  Widget _countRow(String label, String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text(label)),
        Expanded(
          flex: 2,
          child: Center(
            child: Text('${_activity.countToday(widget.auth, key)}'),
          ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: Text('${_activity.countLast7Days(widget.auth, key)}'),
          ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: Text('${_activity.countAllTime(widget.auth, key)}'),
          ),
        ),
      ],
    ),
  );
}
