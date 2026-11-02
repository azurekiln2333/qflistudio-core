import 'dart:async';

import 'package:flutter/material.dart';

import '../community/models.dart';
import '../services/api_client.dart';
import '../services/task_activity_service.dart';
import '../store/auth_store.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.auth, this.activity});

  /// 任务活动服务；为空时使用线上单例。测试可注入隔离实例。
  final TaskActivityService? activity;

  final AuthStore auth;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  TaskActivityService get _activity =>
      widget.activity ?? TaskActivityService.instance;
  bool _checking = false;

  /// 签到成功文案；成功时在签到行内显示。
  String? _checkinSuccess;

  /// 上次签到是否失败：失败才给“重试”按钮。
  bool _checkinFailed = false;

  /// 服务端结果未知（本地写盘失败）：只给“刷新确认”，不给“重试”。
  ///
  /// 按“账号+ 今日”记忆：换账号不能继承别人待确认，切回来要能恢复。
  final Map<String, bool> _uncertainByScope = {};

  String get _scopeKey {
    final user = widget.auth.user;
    return '${user?.id ?? ''}@$_todayKey';
  }

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  bool get _checkinUncertain =>
      _uncertainByScope[_scopeKey] == true;

  /// 不确定状态记在哪个令牌下：同账号重新登录换了令牌就不能当作已确认。
  final Map<String, String> _uncertainTokenByScope = {};

  /// 上一次签到的错误文案；失败时显示在顶部错误行。
  String? _lastCheckinError;

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
    final token = widget.auth.token;
    setState(() {
      _checking = true;
      _checkinSuccess = null;
      _checkinFailed = false;
      _uncertainByScope.remove(_scopeKey);
      _lastCheckinError = null;
    });
    try {
      final result = await _activity.checkin(widget.auth);
      // 请求在途时可能换了账号：旧账号的签到结果不能写到新账号上。
      if (!mounted || widget.auth.token != token) return;
      setState(() {
        _checkinSuccess = result.alreadyChecked
            ? '今天已签到'
            : '签到成功，获得 ${result.reward} 积分，已连续 ${result.streak} 天';
        _checkinFailed = false;
        _uncertainByScope.remove(_scopeKey);
      });
    } on ApiException catch (error) {
      if (!mounted || widget.auth.token != token) return;
      setState(() {
        _checkinSuccess = null;
        _checkinFailed = true;
        _uncertainByScope.remove(_scopeKey);
        _lastCheckinError = error.message;
      });
      _toast(error.message);
    } on Object {
      // 本地写盘失败：服务端可能已经签到成功，重试会造成重复签到。
      // 只提示用户去刷新确认，不提供直接重试。
      if (!mounted || widget.auth.token != token) return;
      setState(() {
        _checkinSuccess = null;
        _checkinFailed = false;
        _uncertainByScope[_scopeKey] = true;
        _uncertainTokenByScope[_scopeKey] = token ?? '';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }  }

  /// 顶部提示；页面内联提示与它并存：内联可重试，SnackBar 负责吸引注意。
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              if (pending > 0 ||
                  _activity.lastError != null ||
                  _checkinFailed ||
                  _checkinUncertain) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _activity.lastError ??
                            (_checkinUncertain
                                ? '签到结果未知，请刷新任务确认，避免重复签到'
                                : _checkinFailed
                                ? _lastCheckinError!
                                : '$pending 次操作待同步'),
                        style: TextStyle(
                          color:
                              _activity.lastError == null &&
                                  !_checkinFailed &&
                                  !_checkinUncertain
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

  /// 签到按钮的三个状态：待签到、进行中（占位进度条）、失败可重试。
  Widget _checkinAction(ColorScheme scheme) => _checking
      ? SizedBox(
          width: 88,
          child: LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        )
      : FilledButton(
          // 结果未知时禁用：服务端可能已经签到，重复提交会重复计分。
          onPressed: _checkinUncertain ? null : _checkin,
          child: const Text('签到'),
        );

  /// 刷新确认：由服务端快照决定签到是否已生效。
  Future<void> _refreshConfirm() async {
    // 点击时的令牌与归属必须在请求前定下：请求在途时可能已经轮换，
    // 那时完成的是旧令牌的请求，不能用来确认新令牌。
    final tokenBefore = widget.auth.token ?? '';
    final owner = _uncertainTokenByScope[_scopeKey];
    await _activity.refreshIfDue(widget.auth, force: true);
    if (!mounted) return;
    setState(() {
      _checkinSuccess = null;
      if (widget.auth.token != tokenBefore) {
        // 令牌在请求期间轮换了：快照来自旧令牌，保留待确认。
        _uncertainTokenByScope[_scopeKey] = widget.auth.token ?? '';
        return;
      }
      if (owner != null && owner != tokenBefore) {
        _uncertainTokenByScope[_scopeKey] = tokenBefore;
        return;
      }
      _uncertainByScope.remove(_scopeKey);
      _uncertainTokenByScope.remove(_scopeKey);
    });
  }

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
              ? _checkinAction(scheme)
              : Text(
                  '${task.progress}/${task.target}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
        ),
        if (isCheckin && _checkinSuccess != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _checkinSuccess!,
              style: TextStyle(color: scheme.primary),
            ),
          ),
        if (isCheckin && (_checkinFailed || _checkinUncertain))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                // 失败/未知的文案在顶部错误行显示；这里只放动作，
                // 否则同一句话会在页面上出现两次。
                const Spacer(),
                if (_checkinFailed)
                  TextButton(
                    onPressed: _checking ? null : _checkin,
                    child: const Text('重试'),
                  ),
                if (_checkinUncertain)
                  TextButton(
                    onPressed: _refreshConfirm,
                    child: const Text('刷新确认'),
                  ),
              ],
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
