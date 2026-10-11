import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/task_activity_service.dart';
import '../store/auth_store.dart';

class CheckinCalendarPage extends StatefulWidget {
  const CheckinCalendarPage({super.key, required this.auth});

  final AuthStore auth;

  @override
  State<CheckinCalendarPage> createState() => _CheckinCalendarPageState();
}

class _CheckinCalendarPageState extends State<CheckinCalendarPage> {
  final TaskActivityService _activity = TaskActivityService.instance;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _activity.initialize();
      if (mounted) setState(() {});
      unawaited(_refresh());
    });
  }

  Future<void> _refresh({bool force = false}) async {
    final month = _month;
    try {
      await _activity.refreshCalendarIfDue(widget.auth, month, force: force);
      if (mounted && _month == month) setState(() => _error = null);
    } on ApiException catch (error) {
      if (mounted && _month == month) setState(() => _error = error.message);
    }
  }

  void _changeMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('签到日历'),
      actions: [
        IconButton(
          tooltip: '刷新日历',
          icon: const Icon(Icons.refresh),
          onPressed: () => _refresh(force: true),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_activity, widget.auth]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final current = _month.year == now.year && _month.month == now.month;
        final first = DateTime(_month.year, _month.month);
        final dayCount = DateTime(_month.year, _month.month + 1, 0).day;
        final cells = first.weekday - 1 + dayCount;
        final checked = _activity
            .cachedCalendar(widget.auth, _month)
            .map((date) => date.day)
            .toSet();
        return RefreshIndicator(
          onRefresh: () => _refresh(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '连续签到',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${widget.auth.user?.checkinStreak ?? 0} 天',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_month.year} 年 ${_month.month} 月',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '上个月',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: current ? null : () => _changeMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: ((cells + 6) ~/ 7) * 7,
                itemBuilder: (context, index) {
                  final day = index - first.weekday + 2;
                  if (day < 1 || day > dayCount) return const SizedBox.shrink();
                  final signed = checked.contains(day);
                  final isToday = current && day == now.day;
                  return Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: signed ? scheme.primary : null,
                        border: isToday
                            ? Border.all(color: scheme.primary, width: 2)
                            : null,
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: signed ? scheme.onPrimary : scheme.onSurface,
                          fontWeight: signed || isToday
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
            ],
          ),
        );
      },
    ),
  );
}
