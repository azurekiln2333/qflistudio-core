// UI regressions for cloud CI. Do not execute tests locally.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/models/cloud_project.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';
import 'package:qfli_studio_core/widgets/project_dialogs.dart';

void main() {
  Project cloud() => Project.create(
    name: 'Cloud repository',
    path: '/cache/workspace',
    cloudId: 'proj_cloud',
    cloudOrigin: 'https://qfli.suanxiwanjie.cn',
    cloudAccountId: 'account-a',
  );

  Future<void> mount(
    WidgetTester tester,
    CloudCacheStatus status, {
    bool busy = false,
    VoidCallback? share,
    VoidCallback? cache,
    VoidCallback? clear,
    VoidCallback? remove,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: ProjectCard(
              project: cloud(),
              onOpen: () {},
              onRemove: remove ?? () {},
              cacheStatus: status,
              cloudBusy: busy,
              onShare: share ?? () {},
              onCache: cache ?? () {},
              onClearCache: clear ?? () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('R8 renders all four cache states and snapshot metadata', (
    tester,
  ) async {
    for (final entry in <(CloudCachePhase, String)>[
      (CloudCachePhase.notCached, '未缓存'),
      (CloudCachePhase.caching, '缓存中'),
      (CloudCachePhase.cached, '已缓存'),
      (CloudCachePhase.failed, '同步失败'),
    ]) {
      await mount(
        tester,
        CloudCacheStatus(
          phase: entry.$1,
          fileCount: 7,
          bytes: 2048,
          completedFiles: 2,
          totalFiles: 8,
          downloadedBytes: 1024,
          cachedAt: DateTime.utc(2026, 11, 21),
        ),
      );
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('cloud-cache-status')))
          .data!;
      expect(label, contains(entry.$2));
      expect(
        label,
        contains(entry.$1 == CloudCachePhase.caching ? '2 / 8' : '7 个文件'),
      );
      expect(
        label,
        contains(entry.$1 == CloudCachePhase.caching ? '1.0 KiB' : '2.0 KiB'),
      );
      expect(find.byKey(const ValueKey('cloud-cache-time')), findsOneWidget);
      if (entry.$1 == CloudCachePhase.caching) {
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          0.25,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('R6 cloud cards offer ZIP sharing without a local directory', (
    tester,
  ) async {
    var shared = 0;
    await mount(tester, const CloudCacheStatus(), share: () => shared++);
    await tester.tap(find.byType(PopupMenuButton<ProjectCardAction>));
    await tester.pumpAndSettle();
    expect(find.text('导出并分享 ZIP'), findsOneWidget);
    // Existing qsz export stays local-only.
    expect(find.text('压缩导出项目'), findsNothing);
    await tester.tap(find.text('导出并分享 ZIP'));
    await tester.pumpAndSettle();
    expect(shared, 1);
  });

  testWidgets('R8 update and clear invoke distinct callbacks', (tester) async {
    var updates = 0;
    var clears = 0;
    var deletes = 0;
    await mount(
      tester,
      CloudCacheStatus(
        phase: CloudCachePhase.cached,
        cachedAt: DateTime.utc(2026),
        fileCount: 1,
        bytes: 4,
      ),
      cache: () => updates++,
      clear: () => clears++,
      remove: () => deletes++,
    );
    await tester.tap(find.byType(PopupMenuButton<ProjectCardAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新缓存'));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(clears, 0);
    expect(deletes, 0);
    await tester.tap(find.byType(PopupMenuButton<ProjectCardAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理缓存'));
    await tester.pumpAndSettle();
    expect(clears, 1);
    expect(deletes, 0);
  });

  testWidgets(
    'R3/R8 busy cloud operations cannot duplicate destructive actions',
    (tester) async {
      await mount(
        tester,
        const CloudCacheStatus(phase: CloudCachePhase.caching),
        busy: true,
      );
      await tester.tap(find.byType(PopupMenuButton<ProjectCardAction>));
      // Caching before the remote tree arrives has no file totals, so the
      // progress bar is indeterminate and never settles. Advance the menu
      // route with explicit pumps instead of waiting for a still frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final action in [
        ProjectCardAction.remove,
        ProjectCardAction.cache,
        ProjectCardAction.clearCache,
        ProjectCardAction.share,
      ]) {
        final item = tester
            .widgetList<PopupMenuItem<ProjectCardAction>>(
              find.byType(PopupMenuItem<ProjectCardAction>),
            )
            .singleWhere((item) => item.value == action);
        expect(item.enabled, isFalse);
      }
    },
  );

  testWidgets(
    'R3 server delete and R8 cache clear have distinct confirmations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        showDeleteCloudProjectConfirm(context, cloud()),
                    child: const Text('delete'),
                  ),
                  TextButton(
                    onPressed: () =>
                        showClearCloudCacheConfirm(context, cloud()),
                    child: const Text('clear'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cloud-project-delete-confirm')),
        findsOneWidget,
      );
      expect(find.textContaining('无法从本地回收站恢复'), findsOneWidget);
      expect(find.text('永久删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('clear'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cloud-project-cache-clear-confirm')),
        findsOneWidget,
      );
      expect(find.textContaining('不删除云端项目'), findsOneWidget);
      expect(find.text('永久删除'), findsNothing);
    },
  );
}
