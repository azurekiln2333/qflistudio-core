@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/hub/agents_snapshot.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/home_agents_tab.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import '../support/fake_harness_host.dart';

/// 首页 Agents 标签：快照优先、内置会话索引、合并排序与点击回调。
void main() {
  late AuthStore auth;
  late ProjectStore store;
  late SettingsStore settings;
  late Directory sessionRoot;

  setUp(() async {
    auth = AuthStore();
    store = ProjectStore();
    settings = SettingsStore();
    sessionRoot = await Directory.systemTemp.createTemp('qfli_home_agents_');
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

  void writeStudioIndex(List<Map<String, Object?>> sessions) {
    File(
      '${sessionRoot.path}${Platform.pathSeparator}index.json',
    ).writeAsStringSync(jsonEncode({'version': 2, 'sessions': sessions}));
  }

  Future<HarnessHub> mount(
    WidgetTester tester, {
    required List<HarnessHost> hosts,
    AgentsSnapshotStore? snapshotStore,
    void Function(AgentsIndexRow row)? onOpenSession,
    HarnessDeviceInfo? deviceInfo,
  }) async {
    final hub = HarnessHub(hosts: hosts, desktop: true, ownsHosts: false);
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
            snapshotStore: snapshotStore,
            sessionRoot: sessionRoot,
            deviceInfo:
                deviceInfo ??
                const HarnessDeviceInfo(
                  hostName: '测试手机',
                  os: HarnessDeviceOs.android,
                  osVersion: '14',
                ),
            onOpenSession: onOpenSession,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    // 让真实文件读写跑完：内置会话索引是磁盘上的 index.json。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    // 走完快照的防抖窗口，免得测试结束时还挂着定时器。
    await tester.pump(const Duration(seconds: 3));
    return hub;
  }

  testWidgets('没有会话时给出空状态', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote]);

    expect(find.byKey(const ValueKey('agents-empty')), findsOneWidget);
    expect(find.text('还没有会话'), findsOneWidget);
  });

  testWidgets('首屏先画快照，主机报上新列表后替换', (tester) async {
    final snapshot = AgentsSnapshotStore(
      backend: LocalMemoryBackend(
        jsonEncode({
          'version': AgentsSnapshotStore.schemaVersion,
          'rows': [
            {
              'hostId': 'remote:1',
              'sessionId': 'old',
              'hostLabel': 'MacBook',
              'hostKind': 'remote',
              'title': '上次的会话',
              'status': 'idle',
            },
          ],
        }),
      ),
    );
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: const [],
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote], snapshotStore: snapshot);

    expect(find.text('上次的会话'), findsOneWidget, reason: '快照先顶上');

    remote.emitSessions([
      fakeSession(hostId: 'remote:1', id: 'fresh', title: '刚跑的会话'),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('刚跑的会话'), findsOneWidget);
    expect(find.text('上次的会话'), findsNothing);
  });

  testWidgets('内置会话从索引读出来，不需要主机', (tester) async {
    writeStudioIndex([
      {
        'id': 'built-in-1',
        'projectId': 'p-1',
        'title': '内置改登录',
        'updatedAt': '2026-11-23T09:58:00.000Z',
      },
    ]);
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote]);

    expect(find.text('内置改登录'), findsOneWidget);
    expect(find.textContaining('内置 Agent'), findsWidgets);
  });

  testWidgets('待确认排在前，空闲在后', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(
          hostId: 'remote:1',
          id: 'idle',
          title: '空闲的',
          status: HarnessSessionStatus.idle,
          updatedAt: DateTime.utc(2026, 11, 23, 10),
        ),
        fakeSession(
          hostId: 'remote:1',
          id: 'blocked',
          title: '等我确认',
          status: HarnessSessionStatus.blocked,
          updatedAt: DateTime.utc(2026, 11, 20),
        ),
      ],
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote], onOpenSession: (_) {});

    final blocked = tester.getTopLeft(find.text('等我确认')).dy;
    final idle = tester.getTopLeft(find.text('空闲的')).dy;
    expect(blocked, lessThan(idle));
  });

  testWidgets('点一行把行交给回调', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(hostId: 'remote:1', id: 's-1', title: '点我'),
      ],
    );
    addTearDown(remote.dispose);
    AgentsIndexRow? tapped;
    await mount(tester, hosts: [remote], onOpenSession: (row) => tapped = row);

    await tester.tap(find.text('点我'));
    await tester.pump();

    expect(tapped?.session.id, 's-1');
    expect(tapped?.hostKind, HarnessHostKind.remote);
  });

  testWidgets('状态圆点带行键', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(
          hostId: 'remote:1',
          id: 's-1',
          title: '待确认的会话',
          status: HarnessSessionStatus.blocked,
        ),
      ],
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote], onOpenSession: (_) {});

    expect(
      find.byKey(const ValueKey('agents-status-remote:1:s-1')),
      findsOneWidget,
    );
  });

  testWidgets('圆点不只靠颜色：带状态的文字标签', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(
          hostId: 'remote:1',
          id: 's-1',
          title: '待确认的会话',
          status: HarnessSessionStatus.blocked,
        ),
      ],
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote], onOpenSession: (_) {});

    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    expect(find.bySemanticsLabel('待确认'), findsWidgets);
  });

  testWidgets('刷新后读到新增的内置会话', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote]);
    expect(find.byKey(const ValueKey('agents-empty')), findsOneWidget);

    writeStudioIndex([
      {
        'id': 'built-in-2',
        'projectId': 'p-1',
        'title': '刷新后出现',
        'updatedAt': '2026-11-23T12:00:00.000Z',
      },
    ]);
    final state = tester.state<HomeAgentsTabState>(find.byType(HomeAgentsTab));
    await state.refresh();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('刷新后出现'), findsOneWidget);
  });

  testWidgets('快照在防抖后写回', (tester) async {
    final backend = LocalMemoryBackend();
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(hostId: 'remote:1', id: 's-1', title: '写进快照'),
      ],
    );
    addTearDown(remote.dispose);
    await mount(
      tester,
      hosts: [remote],
      snapshotStore: AgentsSnapshotStore(backend: backend),
      onOpenSession: (_) {},
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.hasWrite, isTrue);
    expect(backend.payload, contains('写进快照'));
  });
}
