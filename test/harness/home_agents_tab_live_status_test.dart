@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/home_agents_tab.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import '../support/fake_agent.dart';

/// 首页 Agents 的内置会话状态：有运行时用真状态，没运行时保持 idle。
void main() {
  late AuthStore auth;
  late ProjectStore store;
  late SettingsStore settings;
  late Directory sessionRoot;

  setUp(() async {
    auth = AuthStore();
    store = ProjectStore();
    settings = SettingsStore();
    sessionRoot = await Directory.systemTemp.createTemp('qfli_agents_live_');
  });

  tearDown(() async {
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      sessionRoot.deleteSync(recursive: true);
    } on FileSystemException {
      // 文件句柄可能还没释放。
    }
  });

  void writeStudioIndex(List<String> ids) {
    File(
      '${sessionRoot.path}${Platform.pathSeparator}index.json',
    ).writeAsStringSync(
      jsonEncode({
        'version': 2,
        'sessions': [
          for (final id in ids)
            {
              'id': id,
              'projectId': 'p-1',
              'title': '会话 $id',
              'createdAt': '2026-11-23T09:00:00.000Z',
              'updatedAt': '2026-11-23T09:58:00.000Z',
            },
        ],
      }),
    );
  }

  Future<List<HarnessSessionStatus>> mountStatuses(
    WidgetTester tester, {
    required List<String> ids,
    AgentRuntime? runtime,
  }) async {
    final hub = HarnessHub(hosts: const [], desktop: true, ownsHosts: false);
    addTearDown(hub.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAgentsTab(
            auth: auth,
            store: store,
            settings: settings,
            harnessHub: hub,
            sessionRoot: sessionRoot,
            runtime: runtime,
            deviceInfo: const HarnessDeviceInfo(
              hostName: '测试手机',
              os: HarnessDeviceOs.android,
              osVersion: '14',
            ),
            onOpenSession: (_) {},
            onOpenDetails: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final state = tester.state<HomeAgentsTabState>(find.byType(HomeAgentsTab));
    return [
      for (final row in state.rows)
        if (row.hostKind == HarnessHostKind.studio) row.session.status,
    ];
  }

  testWidgets('没有运行时可报时，内置会话保持 idle', (tester) async {
    writeStudioIndex(['s-1', 's-2']);

    final statuses = await mountStatuses(tester, ids: ['s-1', 's-2']);

    expect(statuses, [HarnessSessionStatus.idle, HarnessSessionStatus.idle]);
  });

  testWidgets('运行时在跑时显示真状态', (tester) async {
    writeStudioIndex(['s-working', 's-blocked', 's-done', 's-idle']);
    final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore())
      ..liveStatuses['s-working'] = AgentLiveStatus.running
      ..liveStatuses['s-blocked'] = AgentLiveStatus.awaitingApproval
      ..liveStatuses['s-done'] = AgentLiveStatus.finishedUnread;

    final statuses = await mountStatuses(
      tester,
      ids: ['s-working', 's-blocked', 's-done', 's-idle'],
      runtime: runtime,
    );

    expect(statuses.toSet(), {
      HarnessSessionStatus.working,
      HarnessSessionStatus.blocked,
      HarnessSessionStatus.done,
      HarnessSessionStatus.idle,
    });
    expect(statuses.length, 4);
  });

  testWidgets('运行时状态变了，列表跟着改，不重读磁盘', (tester) async {
    writeStudioIndex(['s-1']);
    final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore())
      ..liveStatuses['s-1'] = AgentLiveStatus.running;

    final before = await mountStatuses(tester, ids: ['s-1'], runtime: runtime);
    expect(before, [HarnessSessionStatus.working]);

    // 把索引文件删掉：真重读磁盘的话，会话会消失。
    File('${sessionRoot.path}${Platform.pathSeparator}index.json').deleteSync();

    runtime.liveStatuses['s-1'] = AgentLiveStatus.finishedUnread;
    runtime.notifyLive();
    await tester.pump();

    final state = tester.state<HomeAgentsTabState>(find.byType(HomeAgentsTab));
    expect(
      state.rows.single.session.status,
      HarnessSessionStatus.done,
      reason: '状态跟着运行时走，索引没重读',
    );
  });

  testWidgets('排队中也算运行中', (tester) async {
    writeStudioIndex(['s-queued']);
    final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore())
      ..liveStatuses['s-queued'] = AgentLiveStatus.queued;

    final statuses = await mountStatuses(
      tester,
      ids: ['s-queued'],
      runtime: runtime,
    );

    expect(statuses, [HarnessSessionStatus.working]);
  });

  testWidgets('运行时没见过的会话仍是 idle', (tester) async {
    writeStudioIndex(['s-known', 's-unknown']);
    final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore())
      ..liveStatuses['s-known'] = AgentLiveStatus.running;

    final statuses = await mountStatuses(
      tester,
      ids: ['s-known', 's-unknown'],
      runtime: runtime,
    );

    expect(statuses, [HarnessSessionStatus.working, HarnessSessionStatus.idle]);
  });

  testWidgets('内置会话行仍然按状态排序', (tester) async {
    writeStudioIndex(['s-done', 's-blocked', 's-idle']);
    final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore())
      ..liveStatuses['s-blocked'] = AgentLiveStatus.awaitingApproval
      ..liveStatuses['s-done'] = AgentLiveStatus.finishedUnread;

    final statuses = await mountStatuses(
      tester,
      ids: ['s-done', 's-blocked', 's-idle'],
      runtime: runtime,
    );

    expect(statuses, [
      HarnessSessionStatus.blocked,
      HarnessSessionStatus.idle,
      HarnessSessionStatus.done,
    ]);
  });
}
