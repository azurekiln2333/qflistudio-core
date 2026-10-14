import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/local_audit_service.dart';
import 'package:qfli_studio_core/services/local_stats_service.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';

/// Unit tests for the offline stats and audit stores.
///
/// Both are pure local state machines over a [LocalStoreBackend], so they are
/// exercised directly with an in-memory backend and a fake clock. No file IO and
/// no timers, which is what keeps the test process exiting promptly.
void main() {
  late LocalMemoryBackend statsBackend;
  late LocalMemoryBackend auditBackend;
  late DateTime now;

  setUp(() {
    statsBackend = LocalMemoryBackend();
    auditBackend = LocalMemoryBackend();
    now = DateTime(2026, 5, 10, 9);
  });

  LocalStatsService buildStats({Duration flushDelay = Duration.zero}) =>
      LocalStatsService(
        backend: statsBackend,
        clock: () => now,
        flushDelay: flushDelay,
      );

  LocalAuditService buildAudit({
    int maxEntries = 500,
    Duration flushDelay = Duration.zero,
  }) => LocalAuditService(
    backend: auditBackend,
    clock: () => now,
    maxEntries: maxEntries,
    flushDelay: flushDelay,
  );

  group('LocalStatsService counters', () {
    test('records saves and estimates the line delta', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordSave(
        project: 'demo',
        path: 'Main.java',
        previousLineCount: 10,
        newLineCount: 14,
      );
      await stats.recordSave(
        project: 'demo',
        path: 'Main.java',
        previousLineCount: 14,
        newLineCount: 11,
      );
      final summary = stats.summarise();
      expect(summary.totals.saves, 2);
      expect(summary.totals.filesEdited, 2);
      expect(summary.totals.linesAdded, 4);
      expect(summary.totals.linesRemoved, 3);
      stats.dispose();
    });

    test('records created, deleted and renamed files separately', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordFileCreated(project: 'demo', path: 'A.java');
      await stats.recordFileDeleted(project: 'demo', path: 'B.java');
      await stats.recordFileRenamed(project: 'demo', path: 'C.java');
      final totals = stats.summarise().totals;
      expect(totals.filesCreated, 1);
      expect(totals.filesDeleted, 1);
      expect(totals.filesRenamed, 1);
      stats.dispose();
    });

    test('separates successful and failed runs', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordRun(succeeded: true, project: 'demo');
      await stats.recordRun(succeeded: false, project: 'demo');
      await stats.recordRun(succeeded: false, project: 'demo');
      final totals = stats.summarise().totals;
      expect(totals.runsSucceeded, 1);
      expect(totals.runsFailed, 2);
      stats.dispose();
    });

    test('accumulates editing and usage time', () async {
      final stats = buildStats();
      await stats.load();
      await stats.addEditingTime(const Duration(minutes: 5));
      await stats.addEditingTime(const Duration(minutes: 3));
      await stats.addUsageTime(const Duration(minutes: 10));
      final summary = stats.summarise();
      expect(summary.totals.editingMillis, 8 * 60000);
      expect(summary.usageMillis, 10 * 60000);
      // Zero or negative durations are ignored rather than moving the clock.
      await stats.addEditingTime(Duration.zero);
      expect(stats.summarise().totals.editingMillis, 8 * 60000);
      stats.dispose();
    });

    test('counts terminal commands and project opens', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordTerminalCommand();
      await stats.recordTerminalCommand();
      await stats.recordProjectOpened(project: 'demo');
      final totals = stats.summarise().totals;
      expect(totals.terminalCommands, 2);
      expect(totals.projectOpens, 1);
      stats.dispose();
    });

    test('groups the extension distribution and top projects', () async {
      final stats = buildStats();
      await stats.load();
      for (var i = 0; i < 3; i++) {
        await stats.recordFileEdited(project: 'alpha', path: 'A.java');
      }
      await stats.recordFileEdited(project: 'beta', path: 'b.py');
      final summary = stats.summarise();
      expect(summary.languages.first.extension, '.java');
      expect(summary.languages.first.count, 3);
      expect(summary.topProjects().first.key, 'alpha');
      expect(summary.topProjects().first.value.score, 3);
      stats.dispose();
    });
  });

  group('LocalStatsService streaks', () {
    test('current streak counts back over consecutive days', () async {
      final stats = buildStats();
      await stats.load();
      // Three consecutive active days ending today.
      for (final offset in [2, 1, 0]) {
        now = DateTime(2026, 5, 10 - offset, 9);
        await stats.recordFileEdited(project: 'demo', path: 'A.java');
      }
      now = DateTime(2026, 5, 10, 21);
      expect(stats.currentStreak(), 3);
      stats.dispose();
    });

    test('a gap breaks the streak', () async {
      final stats = buildStats();
      await stats.load();
      now = DateTime(2026, 5, 10, 9);
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      // Skip the 9th entirely: yesterday is inactive, so the streak is just
      // today.
      expect(stats.currentStreak(), 1);
      stats.dispose();
    });

    test('an untouched day still counts if the day before was active', () async {
      final stats = buildStats();
      await stats.load();
      now = DateTime(2026, 5, 9, 9);
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      // Today has no activity yet, but yesterday does.
      now = DateTime(2026, 5, 10, 9);
      expect(stats.currentStreak(), 1);
      stats.dispose();
    });

    test('no activity at all means no streak', () async {
      final stats = buildStats();
      await stats.load();
      expect(stats.currentStreak(), 0);
      expect(stats.longestStreak(), 0);
      stats.dispose();
    });

    test('longest streak remembers a past run', () async {
      final stats = buildStats();
      await stats.load();
      // A four-day run in the past, then a gap, then today alone.
      for (final day in [1, 2, 3, 4]) {
        now = DateTime(2026, 4, day, 9);
        await stats.recordFileEdited(project: 'demo', path: 'A.java');
      }
      now = DateTime(2026, 5, 10, 9);
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      expect(stats.longestStreak(), 4);
      expect(stats.currentStreak(), 1);
      stats.dispose();
    });

    test('a day with only editing time counts towards the streak', () async {
      final stats = buildStats();
      await stats.load();
      await stats.addEditingTime(const Duration(minutes: 30));
      expect(stats.currentStreak(), 1);
      stats.dispose();
    });
  });

  group('LocalStatsService trends', () {
    test('trend returns one point per day, oldest first, with gaps as zero', () {
      final stats = buildStats();
      now = DateTime(2026, 5, 10, 9);
      final trend = stats.trend(7);
      expect(trend.length, 7);
      expect(trend.first.day, DateTime(2026, 5, 4));
      expect(trend.last.day, DateTime(2026, 5, 10));
      expect(trend.every((point) => point.value == 0), isTrue);
      stats.dispose();
    });

    test('trend reflects recorded activity and editing minutes', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      await stats.addEditingTime(const Duration(minutes: 4));
      final today = stats.trend(7).last;
      expect(today.value, 1 + 4); // one operation plus four editing minutes
      stats.dispose();
    });

    test('peakInLast reports the busiest bucket', () async {
      final stats = buildStats();
      await stats.load();
      now = DateTime(2026, 5, 9, 9);
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      await stats.recordFileEdited(project: 'demo', path: 'B.java');
      now = DateTime(2026, 5, 10, 9);
      await stats.recordFileEdited(project: 'demo', path: 'C.java');
      expect(stats.peakInLast(7), 2);
      stats.dispose();
    });
  });

  group('LocalStatsService persistence', () {
    test('writes are throttled: a non-zero delay defers the write', () async {
      final stats = buildStats(flushDelay: const Duration(seconds: 30));
      await stats.load();
      for (var i = 0; i < 20; i++) {
        await stats.recordFileEdited(project: 'demo', path: 'A.java');
      }
      // The throttle window has not elapsed, so nothing was written yet.
      expect(statsBackend.hasWrite, isFalse);
      // `settled` forces the pending write immediately.
      await stats.settled;
      expect(statsBackend.hasWrite, isTrue);
      stats.dispose();
    });

    test('a zero delay writes without leaving a timer behind', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      await stats.settled;
      expect(statsBackend.hasWrite, isTrue);
      // dispose must be safe and must not throw with no timer pending.
      expect(stats.dispose, returnsNormally);
    });

    test('a new instance reloads what was persisted', () async {
      final first = buildStats();
      await first.load();
      await first.recordFileCreated(project: 'demo', path: 'X.java');
      await first.settled;
      first.dispose();

      final second = buildStats();
      await second.load();
      expect(second.summarise().totals.filesCreated, 1);
      second.dispose();
    });

    test('a corrupt payload is ignored rather than thrown', () async {
      statsBackend = LocalMemoryBackend('{not json');
      final stats = buildStats();
      await stats.load();
      expect(stats.isLoaded, isTrue);
      expect(stats.summarise().totals.saves, 0);
      stats.dispose();
    });
  });

  group('LocalAuditService', () {
    test('records entries newest first', () async {
      final audit = buildAudit();
      await audit.load();
      now = DateTime(2026, 5, 10, 9);
      await audit.record(kind: LocalAuditKind.create, action: '创建项目 demo');
      now = DateTime(2026, 5, 10, 10);
      await audit.record(
        kind: LocalAuditKind.save,
        action: '保存 Main.java',
        project: 'demo',
        path: 'Main.java',
      );
      expect(audit.length, 2);
      expect(audit.entries.first.kind, LocalAuditKind.save);
      expect(audit.entries.first.at, DateTime(2026, 5, 10, 10));
      audit.dispose();
    });

    test('filters by kind, search text and time window', () async {
      final audit = buildAudit();
      await audit.load();
      now = DateTime(2026, 5, 1, 9);
      await audit.record(
        kind: LocalAuditKind.create,
        action: '创建项目 alpha',
        project: 'alpha',
      );
      now = DateTime(2026, 5, 5, 9);
      await audit.record(
        kind: LocalAuditKind.run,
        action: '运行 beta',
        project: 'beta',
      );
      now = DateTime(2026, 5, 9, 9);
      await audit.record(
        kind: LocalAuditKind.export,
        action: '导出 beta',
        project: 'beta',
      );

      expect(
        audit.filtered(
          const LocalAuditFilter(kinds: {LocalAuditKind.run}),
        ).single.action,
        '运行 beta',
      );
      expect(
        audit.filtered(const LocalAuditFilter(search: 'beta')).length,
        2,
      );
      expect(
        audit
            .filtered(
              LocalAuditFilter(since: DateTime(2026, 5, 5, 0)),
            )
            .length,
        2,
      );
      expect(
        audit
            .filtered(
              LocalAuditFilter(until: DateTime(2026, 5, 1, 23)),
            )
            .length,
        1,
      );
      // An empty filter returns everything.
      expect(
        audit.filtered(const LocalAuditFilter()).length,
        audit.length,
      );
      audit.dispose();
    });

    test('evicts the oldest entries past the cap', () async {
      final audit = buildAudit(maxEntries: 3);
      await audit.load();
      for (var i = 0; i < 5; i++) {
        now = DateTime(2026, 5, 10, 9, i);
        await audit.record(
          kind: LocalAuditKind.save,
          action: '保存 $i',
        );
      }
      expect(audit.length, 3);
      // The three newest survive, oldest first in insertion order.
      expect(audit.entries.first.action, '保存 4');
      expect(audit.entries.last.action, '保存 2');
      audit.dispose();
    });

    test('reports the distinct project names', () async {
      final audit = buildAudit();
      await audit.load();
      for (final name in ['beta', 'alpha', 'beta']) {
        await audit.record(
          kind: LocalAuditKind.save,
          action: '保存',
          project: name,
        );
      }
      expect(audit.projects, ['alpha', 'beta']);
      audit.dispose();
    });

    test('clear empties the log and persists that', () async {
      final audit = buildAudit();
      await audit.load();
      await audit.record(kind: LocalAuditKind.save, action: '保存');
      await audit.clear();
      expect(audit.length, 0);
      expect(auditBackend.hasWrite, isTrue);
      audit.dispose();
    });

    test('persists across instances', () async {
      final first = buildAudit();
      await first.load();
      await first.record(
        kind: LocalAuditKind.delete,
        action: '删除项目 demo',
        project: 'demo',
      );
      await first.settled;
      first.dispose();

      final second = buildAudit();
      await second.load();
      expect(second.length, 1);
      expect(second.entries.first.kind, LocalAuditKind.delete);
      second.dispose();
    });

    test('exportJson is parseable and carries the entries', () async {
      final audit = buildAudit();
      await audit.load();
      await audit.record(
        kind: LocalAuditKind.rename,
        action: '重命名 A.java',
        path: 'A.java',
      );
      final decoded = jsonDecode(audit.exportJson()) as Map<String, Object?>;
      expect(decoded['version'], 1);
      expect((decoded['entries'] as List).length, 1);
      audit.dispose();
    });

    test('an unknown kind key falls back instead of failing', () {
      final entry = LocalAuditEntry.fromJson({
        'id': 'x',
        'at': 1,
        'kind': 'something-removed',
        'action': 'a',
      });
      expect(entry.kind, LocalAuditKind.save);
    });
  });

  group('LocalStatsService export', () {
    test('exportJson round-trips through jsonDecode', () async {
      final stats = buildStats();
      await stats.load();
      await stats.recordFileEdited(project: 'demo', path: 'A.java');
      final decoded = jsonDecode(stats.exportJson()) as Map<String, Object?>;
      expect(decoded['version'], 1);
      expect(decoded['days'], isA<Map>());
      stats.dispose();
    });
  });
}
