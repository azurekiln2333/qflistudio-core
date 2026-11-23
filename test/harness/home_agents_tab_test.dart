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

  /// 真实 IO 的总等待上限。
  const readyDeadline = Duration(seconds: 10);

  HomeAgentsTabState tabState(WidgetTester tester) =>
      tester.state<HomeAgentsTabState>(find.byType(HomeAgentsTab));

  int studioRowCount(WidgetTester tester) => tabState(
    tester,
  ).rows.where((row) => row.hostKind == HarnessHostKind.studio).length;

  /// 在 `runAsync` 活动期间有界地等真实 IO 就位。
  Future<void> waitStudioRows(WidgetTester tester, int expected) async {
    final stopwatch = Stopwatch()..start();
    while (studioRowCount(tester) < expected &&
        stopwatch.elapsed < readyDeadline) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await tester.pump();
    }
  }

  /// 刷新动作自己也要等在 runAsync 里：假时钟下磁盘读写不会完成。
  Future<void> refreshTab(WidgetTester tester, {int expectedRows = 0}) async {
    final state = tabState(tester);
    await tester.runAsync(() async {
      await state.refresh();
      await waitStudioRows(tester, expectedRows);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(seconds: 3));
  }

  Future<HarnessHub> mount(
    WidgetTester tester, {
    required List<HarnessHost> hosts,
    AgentsSnapshotStore? snapshotStore,
    void Function(AgentsIndexRow row)? onOpenSession,
    void Function(AgentsIndexRow row)? onOpenDetails,
    HarnessDeviceInfo? deviceInfo,
    Future<HarnessHost?> Function()? remoteHostOpener,
    int expectedRows = 0,
  }) async {
    final hub = HarnessHub(hosts: hosts, desktop: true, ownsHosts: false);
    addTearDown(hub.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    // 启动本身包在 runAsync 里：它在首帧就开读磁盘上的内置会话索引，
    // 真实的文件回调只在 runAsync 活动期间才会完成。在假时钟里启动，
    // 后面再补 sleep 也等不到那些回调。
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeAgentsTab(
              auth: auth,
              store: store,
              settings: settings,
              harnessHub: hub,
              // 默认给内存快照：真实快照要问存储目录，会挂一个 2 秒探测。
              remoteHostOpener: remoteHostOpener ?? () async => null,
              snapshotStore:
                  snapshotStore ??
                  AgentsSnapshotStore(backend: LocalMemoryBackend()),
              sessionRoot: sessionRoot,
              deviceInfo:
                  deviceInfo ??
                  const HarnessDeviceInfo(
                    hostName: '测试手机',
                    os: HarnessDeviceOs.android,
                    osVersion: '14',
                  ),
              onOpenSession: onOpenSession,
              onOpenDetails: onOpenDetails,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      // 等内置会话的行真的出现，不猜时长。
      await waitStudioRows(tester, expectedRows);
    });
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
    // 主机设成「订阅时不报初始帧」：真实主机刚连上、还没说话的那段时间。
    //
    // 不能用「主机报一个空表」来制造这段窗口：空表是一份有效报告，
    // 按契约快照行必须当场让位（xcheck 记录的行为），那样快照永远画不出来。
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
      emitInitialSessions: false,
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
    await mount(tester, hosts: [remote], expectedRows: 1);

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

  testWidgets('点详情图标把行交给详情回调', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(hostId: 'remote:1', id: 's-1', title: '看详情'),
      ],
    );
    addTearDown(remote.dispose);
    AgentsIndexRow? detailed;
    await mount(
      tester,
      hosts: [remote],
      onOpenSession: (_) {},
      onOpenDetails: (row) => detailed = row,
    );

    await tester.tap(find.byKey(const ValueKey('agents-details-remote:1:s-1')));
    await tester.pump();

    expect(detailed?.session.id, 's-1');
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
    try {
      await tester.pump();
      expect(find.bySemanticsLabel('待确认'), findsWidgets);
    } finally {
      semantics.dispose();
    }
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
    await refreshTab(tester, expectedRows: 1);

    expect(find.text('刷新后出现'), findsOneWidget);
  });

  testWidgets('主机报来有效空表时，快照里的旧行让位', (tester) async {
    // 首个有效空列表也必须替换快照。
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
      emitInitialSessions: false,
    );
    addTearDown(remote.dispose);
    await mount(tester, hosts: [remote], snapshotStore: snapshot);

    expect(find.text('上次的会话'), findsOneWidget);
    remote.emitSessions(const []);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('上次的会话'), findsNothing, reason: '空表把快照行清掉');
    expect(find.byKey(const ValueKey('agents-empty')), findsOneWidget);
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

    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      while (!backend.hasWrite && watch.elapsed < readyDeadline) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(backend.hasWrite, isTrue);
    expect(backend.payload, contains('写进快照'));
  });

  testWidgets('主机报了会话后不留快照里的旧行', (tester) async {
    final snapshot = AgentsSnapshotStore(
      backend: LocalMemoryBackend(
        jsonEncode({
          'version': AgentsSnapshotStore.schemaVersion,
          'rows': [
            {
              'hostId': 'remote:1',
              'sessionId': 'gone',
              'hostLabel': 'MacBook',
              'hostKind': 'remote',
              'title': '已经结束的会话',
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

    expect(find.text('已经结束的会话'), findsNothing, reason: '主机报过列表就等于没这条');
    expect(find.byKey(const ValueKey('agents-empty')), findsOneWidget);
  });

  testWidgets('打开标签时接上已绑定的电脑', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(hostId: 'remote:1', id: 's-1', title: '电脑上的会话'),
      ],
    );
    addTearDown(remote.dispose);
    var opened = 0;
    final hub = await mount(
      tester,
      hosts: const [],
      onOpenSession: (_) {},
      remoteHostOpener: () async {
        opened++;
        return remote;
      },
    );

    expect(opened, 1);
    expect(hub.hostById('remote:1'), isNotNull);
    expect(find.text('电脑上的会话'), findsOneWidget);
    expect(find.byKey(const ValueKey('agents-empty')), findsNothing);
  });

  testWidgets('已经接了远程主机就不再开第二条连接', (tester) async {
    final existing = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
    );
    addTearDown(existing.dispose);
    var opened = 0;
    await mount(
      tester,
      hosts: [existing],
      remoteHostOpener: () async {
        opened++;
        return FakeHarnessHost(
          id: 'remote:2',
          label: '另一台',
          kind: HarnessHostKind.remote,
        );
      },
    );

    expect(opened, 0);
  });
}
