import 'dart:async';

import 'package:flutter/material.dart';

import '../services/local_audit_service.dart';
import '../services/local_stats_service.dart';
import '../widgets/settings_section.dart';

/// Local activity statistics, shown for every product.
///
/// Reads only [LocalStatsService], which is offline by construction, so this
/// page works identically for an offline language app and for qflistudio. The
/// server-backed `activity_stats_page.dart` is untouched and remains the place
/// for points/check-in data.
class LocalStatsPage extends StatefulWidget {
  const LocalStatsPage({super.key, LocalStatsService? service})
    : serviceOverride = service;

  /// Injected by tests; production uses the singleton.
  final LocalStatsService? serviceOverride;

  @override
  State<LocalStatsPage> createState() => _LocalStatsPageState();
}

class _LocalStatsPageState extends State<LocalStatsPage> {
  LocalStatsService get _stats =>
      widget.serviceOverride ?? LocalStatsService.instance;

  bool _loaded = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_stats.isLoaded) await _stats.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地统计'),
        actions: [
          IconButton(
            tooltip: '导出为 JSON',
            onPressed: _loaded ? _export : null,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '清空统计',
            onPressed: _loaded ? _confirmClear : null,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _stats,
              builder: (context, _) => _body(context, _stats.summarise()),
            ),
    );
  }

  /// Copies the export payload to the clipboard and shows it, because the app
  /// has no guaranteed writable location on every platform.
  Future<void> _export() async {
    final payload = _stats.exportJson();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本地统计 JSON'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              payload,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空本地统计？'),
        content: const Text('所有本机统计将被删除，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stats.clear();
    if (!mounted) return;
    setState(() => _message = '已清空本地统计');
  }

  Widget _body(BuildContext context, LocalStatsSummary summary) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = summary.totals;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_message!, style: TextStyle(color: scheme.primary)),
          ),
        _Card(
          title: '概览',
          child: Column(
            children: [
              _StatGrid(
                entries: [
                  ('文件编辑', '${totals.filesEdited}'),
                  ('项目编辑', '${totals.projectsEdited}'),
                  ('保存次数', '${totals.saves}'),
                  ('项目打开', '${totals.projectOpens}'),
                  ('新建文件', '${totals.filesCreated}'),
                  ('删除文件', '${totals.filesDeleted}'),
                  ('重命名', '${totals.filesRenamed}'),
                  ('终端命令', '${totals.terminalCommands}'),
                ],
              ),
              const Divider(height: 24),
              _StatGrid(
                entries: [
                  ('运行成功', '${totals.runsSucceeded}'),
                  ('运行失败', '${totals.runsFailed}'),
                  ('新增行（估）', '+${totals.linesAdded}'),
                  ('删除行（估）', '-${totals.linesRemoved}'),
                  ('编辑时长', _duration(totals.editingMillis)),
                  ('使用时长', _duration(summary.usageMillis)),
                ],
              ),
            ],
          ),
        ),
        _Card(
          title: '连续天数',
          child: Row(
            children: [
              Expanded(
                child: _BigNumber(
                  value: '${summary.currentStreak}',
                  label: '当前连续',
                  unit: '天',
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: _BigNumber(
                  value: '${summary.longestStreak}',
                  label: '最长连续',
                  unit: '天',
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
        ),
        _Card(
          title: '近 7 天',
          child: _TrendChart(
            points: summary.last7,
            peak: _peak(summary.last7),
            showLabels: true,
          ),
        ),
        _Card(
          title: '近 30 天',
          child: _TrendChart(points: summary.last30, peak: _peak(summary.last30)),
        ),
        _Card(
          title: '活动热力图',
          child: _Heatmap(days: summary.days, today: DateTime.now()),
        ),
        _Card(
          title: '语言分布',
          child: summary.languages.isEmpty
              ? const _Empty('还没有编辑记录')
              : Column(
                  children: [
                    for (final language in summary.languages.take(8))
                      _BarRow(
                        label: language.extension,
                        value: language.count,
                        max: summary.languages.first.count,
                      ),
                  ],
                ),
        ),
        _Card(
          title: '常用项目',
          child: summary.projects.isEmpty
              ? const _Empty('还没有项目记录')
              : Column(
                  children: [
                    for (final entry in summary.topProjects())
                      _BarRow(
                        label: entry.key,
                        value: entry.value.score,
                        max: summary.topProjects().first.value.score,
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '全部统计仅保存在本机，不会上传。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static int _peak(List<LocalTrendPoint> points) {
    var peak = 0;
    for (final point in points) {
      if (point.value > peak) peak = point.value;
    }
    return peak;
  }

  static String _duration(int millis) {
    if (millis <= 0) return '0 分钟';
    final minutes = millis ~/ 60000;
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final remain = minutes % 60;
    return remain == 0 ? '$hours 小时' : '$hours 小时 $remain 分';
  }
}

/// The local audit log, shown for every product.
///
/// Offline by construction; the server-side admin log in `audit_page.dart` is
/// untouched and still used by qflistudio.
class LocalAuditPage extends StatefulWidget {
  const LocalAuditPage({super.key, LocalAuditService? service})
    : serviceOverride = service;

  final LocalAuditService? serviceOverride;

  @override
  State<LocalAuditPage> createState() => _LocalAuditPageState();
}

class _LocalAuditPageState extends State<LocalAuditPage> {
  LocalAuditService get _audit =>
      widget.serviceOverride ?? LocalAuditService.instance;

  final _search = TextEditingController();
  final Set<LocalAuditKind> _kinds = {};
  LocalAuditRange _range = LocalAuditRange.all;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_audit.isLoaded) await _audit.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  LocalAuditFilter get _filter => LocalAuditFilter(
    kinds: _kinds,
    search: _search.text,
    since: _range.since(DateTime.now()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地审计'),
        actions: [
          IconButton(
            tooltip: '导出为 JSON',
            onPressed: _loaded ? _export : null,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '清空记录',
            onPressed: _loaded ? _confirmClear : null,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _audit,
              builder: (context, _) => Column(
                children: [
                  _filters(context),
                  const Divider(height: 1),
                  Expanded(child: _list(context)),
                ],
              ),
            ),
    );
  }

  Widget _filters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索操作、项目或路径',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final kind in LocalAuditKind.values) ...[
                  FilterChip(
                    label: Text(kind.label),
                    selected: _kinds.contains(kind),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _kinds.add(kind);
                      } else {
                        _kinds.remove(kind);
                      }
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<LocalAuditRange>(
            segments: [
              for (final range in LocalAuditRange.values)
                ButtonSegment(value: range, label: Text(range.label)),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _range = values.first),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final entries = _audit.filtered(_filter);
    if (entries.isEmpty) {
      return const _Empty('没有符合条件的记录');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: entries.length,
      separatorBuilder: (context, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final theme = Theme.of(context);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(_kindIcon(entry.kind), size: 20),
          title: Text(entry.action),
          subtitle: Text(
            [
              _timestamp(entry.at),
              if (entry.project != null) entry.project!,
              if (entry.path != null) entry.path!,
              if (entry.detail != null) entry.detail!,
            ].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            entry.kind.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }

  static String _timestamp(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static IconData _kindIcon(LocalAuditKind kind) => switch (kind) {
    LocalAuditKind.create => Icons.add_box_outlined,
    LocalAuditKind.open => Icons.folder_open_outlined,
    LocalAuditKind.delete => Icons.delete_outline,
    LocalAuditKind.rename => Icons.drive_file_rename_outline,
    LocalAuditKind.save => Icons.save_outlined,
    LocalAuditKind.run => Icons.play_arrow_outlined,
    LocalAuditKind.import => Icons.file_download_outlined,
    LocalAuditKind.export => Icons.file_upload_outlined,
    LocalAuditKind.restore => Icons.restore_outlined,
    LocalAuditKind.terminal => Icons.terminal,
  };

  Future<void> _export() async {
    final payload = _audit.exportJson();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本地审计 JSON'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              payload,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空本地审计记录？'),
        content: const Text('所有本机记录将被删除，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _audit.clear();
  }
}

/// Time window presets for the audit filter.
enum LocalAuditRange {
  all('全部'),
  today('今天'),
  week('近 7 天'),
  month('近 30 天');

  const LocalAuditRange(this.label);

  final String label;

  /// Lower bound for this range, or null for [all].
  DateTime? since(DateTime now) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    return switch (this) {
      LocalAuditRange.all => null,
      LocalAuditRange.today => startOfDay,
      LocalAuditRange.week => startOfDay.subtract(const Duration(days: 6)),
      LocalAuditRange.month => startOfDay.subtract(const Duration(days: 29)),
    };
  }
}

// ---------------------------------------------------------------------------
// Shared presentation pieces
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SettingsSection(
      title: title,
      cardShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: child,
        ),
      ],
    ),
  );
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in entries)
          SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$2,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  entry.$1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({
    required this.value,
    required this.label,
    required this.unit,
    required this.color,
  });

  final String value;
  final String label;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Text(unit, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
  });

  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max <= 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact bar chart. Deliberately not a charting dependency: a row of
/// proportional bars conveys the same trend and ships no new package.
class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.points,
    required this.peak,
    this.showLabels = false,
  });

  final List<LocalTrendPoint> points;
  final int peak;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Tooltip(
                      message:
                          '${LocalStatsService.dayKey(point.day)}：${point.value}',
                      child: Container(
                        height: peak <= 0
                            ? 3
                            : (96 * point.value / peak).clamp(3, 96).toDouble(),
                        decoration: BoxDecoration(
                          color: point.value == 0
                              ? scheme.surfaceContainerHighest
                              : scheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              for (final point in points)
                Expanded(
                  child: Text(
                    '${point.day.day}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A GitHub-style contribution grid for the last weeks.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.days, required this.today});

  final Map<DateTime, LocalDayStats> days;
  final DateTime today;

  static const int _weeks = 18;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: _weeks * 7 - 1));
    // Align the first column to its week start so rows are weekdays.
    final offset = start.weekday % 7;
    final columns = <Widget>[];
    for (var week = 0; week < _weeks; week++) {
      final column = <Widget>[];
      for (var weekday = 0; weekday < 7; weekday++) {
        final index = week * 7 + weekday - offset;
        final date = DateTime(
          start.year,
          start.month,
          start.day + index,
        );
        final isFuture = date.isAfter(today);
        final count = days[date]?.activityCount ?? 0;
        column.add(
          Padding(
            padding: const EdgeInsets.all(1),
            child: Tooltip(
              message: '${LocalStatsService.dayKey(date)}：$count',
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isFuture
                      ? Colors.transparent
                      : _shade(scheme, count),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }
      columns.add(Column(children: column));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: columns),
    );
  }

  /// Four intensity steps from the scheme, so it works in light and dark.
  static Color _shade(ColorScheme scheme, int count) {
    if (count == 0) return scheme.surfaceContainerHighest;
    if (count <= 2) return scheme.primary.withValues(alpha: 0.30);
    if (count <= 6) return scheme.primary.withValues(alpha: 0.55);
    if (count <= 14) return scheme.primary.withValues(alpha: 0.78);
    return scheme.primary;
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
