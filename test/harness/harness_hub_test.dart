// HarnessHub 的状态测试：主机注册、平台过滤、当前主机、合并会话列表、
// 启动菜单、打开/释放视图与刷新。
//
// 本地不跑测试（brief 规定），这些用例交给云端 CI。

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';

import '../support/fake_harness_host.dart';

void main() {
  late FakeHarnessHost local;
  late FakeHarnessHost herdr;
  late FakeHarnessHost remote;
  late FakeHarnessHost studio;

  setUp(() {
    local = FakeHarnessHost(
      id: 'local',
      label: '本机',
      kind: HarnessHostKind.local,
      initialSessions: [
        fakeSession(
          hostId: 'local',
          id: 'l1',
          providerId: 'claude',
          title: 'Claude 会话',
        ),
        fakeSession(
          hostId: 'local',
          id: 'l2',
          providerId: 'codex',
          title: 'Codex 会话',
        ),
      ],
      providerList: const [
        HarnessProviderInfo(
          id: 'claude',
          label: 'Claude Code',
          available: true,
        ),
        HarnessProviderInfo(id: 'codex', label: 'Codex', available: false),
      ],
    );
    herdr = FakeHarnessHost(
      id: 'herdr',
      label: 'Herdr',
      kind: HarnessHostKind.local,
      initialSessions: [
        fakeSession(
          hostId: 'herdr',
          id: 'h1',
          providerId: 'herdr',
          title: '窗格 1',
        ),
      ],
      initialState: HarnessHostState.unsupported,
      hint: '未检测到 Herdr，请先安装。',
    );
    remote = FakeHarnessHost(
      id: 'remote-pc',
      label: '我的电脑',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(
          hostId: 'remote-pc',
          id: 'r1',
          providerId: 'claude',
          title: '远程 Claude',
        ),
      ],
    );
    studio = FakeHarnessHost(
      id: 'studio',
      label: '内置 Agent',
      kind: HarnessHostKind.studio,
    );
  });

  tearDown(() async {
    await local.dispose();
    await herdr.dispose();
    await remote.dispose();
    await studio.dispose();
  });

  HarnessHub buildHub({bool desktop = true, String? initialHostId}) =>
      HarnessHub(
        hosts: [studio, local, herdr, remote],
        desktop: desktop,
        initialHostId: initialHostId,
      );

  test('desktop keeps every host and opens on the studio one', () async {
    final hub = buildHub();
    await pumpEventQueue();

    expect(hub.hosts.map((host) => host.id), [
      'studio',
      'local',
      'herdr',
      'remote-pc',
    ]);
    // 面板默认展示内置 Agent 的对话，外部主机是加在旁边的。
    expect(hub.currentHostId, 'studio');
    expect(hub.isDesktop, isTrue);
    hub.dispose();
  });

  test('a hub without a studio host falls back to the local one', () async {
    final hub = HarnessHub(
      hosts: [
        FakeHarnessHost(id: 'local', label: '本机', kind: HarnessHostKind.local),
        FakeHarnessHost(
          id: 'herdr',
          label: 'Herdr',
          kind: HarnessHostKind.local,
        ),
      ],
      desktop: true,
    );
    await pumpEventQueue();

    expect(hub.currentHostId, 'local');
    hub.dispose();
  });

  test('mobile hides local and herdr hosts', () async {
    final hub = buildHub(desktop: false);
    await pumpEventQueue();

    expect(hub.hosts.map((host) => host.id), ['studio', 'remote-pc']);
    expect(hub.currentHostId, 'remote-pc');
    hub.dispose();
  });

  test('only the current host is subscribed until the user switches', () async {
    final hub = buildHub();
    await pumpEventQueue();

    // 打开面板只需要内置 Agent 的列表：其余主机不该跟着起后台轮询。
    expect(hub.isListening('studio'), isTrue);
    expect(hub.isListening('local'), isFalse);
    expect(hub.isListening('herdr'), isFalse);
    expect(hub.isListening('remote-pc'), isFalse);
    expect(hub.sessionsOf('local'), isEmpty);

    await openHost(hub, 'local');

    expect(hub.isListening('local'), isTrue);
    expect(hub.sessionsOf('local').map((session) => session.id), ['l1', 'l2']);
    // 已经订阅的不取消：来回切不该反复重拉历史。
    expect(hub.isListening('studio'), isTrue);
    hub.dispose();
  });

  test('refresh does not wake hosts that were never visited', () async {
    final hub = buildHub();
    await pumpEventQueue();

    await hub.refresh();
    await pumpEventQueue();

    expect(hub.isListening('studio'), isTrue);
    expect(hub.isListening('herdr'), isFalse);
    expect(hub.isListening('remote-pc'), isFalse);
    hub.dispose();
  });

  test(
    'merged sessions come from every visited host with their host id',
    () async {
      final hub = buildHub();
      await pumpEventQueue();

      // 订阅按需建立：切一台拉一台。
      for (final id in ['local', 'herdr', 'remote-pc']) {
        await openHost(hub, id);
      }

      expect(hub.allSessions.map((session) => session.id), [
        'l1',
        'l2',
        'h1',
        'r1',
      ]);
      expect(hub.currentSessions.map((session) => session.id), ['r1']);
      expect(hub.sessionsOf('remote-pc').single.hostId, 'remote-pc');
      hub.dispose();
    },
  );

  test(
    'current groups label providers and sort sessions by update time',
    () async {
      local.emitSessions([
        fakeSession(
          hostId: 'local',
          id: 'old',
          providerId: 'claude',
          updatedAt: DateTime(2026, 1, 1),
        ),
        fakeSession(
          hostId: 'local',
          id: 'new',
          providerId: 'claude',
          updatedAt: DateTime(2026, 2, 1),
        ),
        fakeSession(hostId: 'local', id: 'codex-1', providerId: 'codex'),
      ]);
      final hub = buildHub();
      await pumpEventQueue();
      await openHost(hub, 'local');
      await hub.providersOf('local');
      await pumpEventQueue();

      final groups = hub.currentGroups;
      expect(groups.map((group) => group.providerId), ['claude', 'codex']);
      expect(groups.first.label, 'Claude Code');
      expect(groups.first.sessions.map((session) => session.id), [
        'new',
        'old',
      ]);
      hub.dispose();
    },
  );

  test('launch menu comes from the current host providers', () async {
    final hub = buildHub();
    await pumpEventQueue();
    // 内置 Agent 没有可启动的外部 harness：启动菜单看的是外部主机。
    await openHost(hub, 'local');

    final menu = await hub.launchMenu();
    expect(menu.map((provider) => provider.id), ['claude', 'codex']);
    expect(menu.last.available, isFalse);
    hub.dispose();
  });

  test('host state and install hint are exposed to the UI', () async {
    final hub = buildHub();
    await pumpEventQueue();

    expect(hub.stateOf('herdr'), HarnessHostState.unsupported);
    expect(hub.hintOf('herdr'), contains('Herdr'));
    herdr.setState(HarnessHostState.online);
    await pumpEventQueue();
    expect(hub.stateOf('herdr'), HarnessHostState.online);
    expect(hub.hintOf('local'), isNull);
    hub.dispose();
  });

  test('install hints accept strings, maps and structured objects', () {
    // 主机可以给纯文本，也可以给自己定义的对象；两种都要能变成一句话。
    expect(harnessHintText('未检测到 Herdr'), '未检测到 Herdr');
    expect(harnessHintText('   '), isNull);
    expect(harnessHintText(null), isNull);
    expect(harnessHintText({'title': 'Herdr', 'message': '服务未运行'}), '服务未运行');
    expect(harnessHintText(const _StructuredHint('需要安装 Herdr')), '需要安装 Herdr');
    // 拿不到文字的默认 toString 不算说明。
    expect(harnessHintText(const _OpaqueHint()), isNull);
  });

  test('the hub reads a structured hint from a host', () async {
    final host = _StructuredHintHost();
    final hub = HarnessHub(hosts: [host], desktop: true);
    await pumpEventQueue();
    expect(hub.hintOf('herdr'), '服务未运行，请重启 Herdr');
    hub.dispose();
  });

  test(
    'selecting a host switches its session list and releases the view',
    () async {
      final hub = buildHub();
      await pumpEventQueue();
      await openHost(hub, 'local');
      final session = hub.sessionsOf('local').first;
      final handle = await hub.openSession(session);
      expect(hub.activeSession?.id, 'l1');

      hub.selectHost('remote-pc');
      await pumpEventQueue();

      expect(hub.currentHostId, 'remote-pc');
      expect(hub.activeSession, isNull);
      expect((handle as FakeSessionHandle).detachCount, 1);
      hub.dispose();
    },
  );

  test('opening the same session twice reuses one handle', () async {
    final hub = buildHub();
    await pumpEventQueue();
    await openHost(hub, 'local');
    final session = hub.sessionsOf('local').first;

    final first = await hub.openSession(session);
    final second = await hub.openSession(session);

    expect(identical(first, second), isTrue);
    expect(local.opened, ['l1']);
    hub.dispose();
  });

  test('closing the view detaches without stopping the session', () async {
    final hub = buildHub();
    await pumpEventQueue();
    await openHost(hub, 'local');
    final handle = await hub.openSession(hub.sessionsOf('local').first);

    await hub.closeActiveSession();

    expect(hub.activeSession, isNull);
    expect(hub.activeHandle, isNull);
    expect((handle as FakeSessionHandle).detachCount, 1);
    expect(handle.stopCount, 0);
    hub.dispose();
  });

  test('a session removed by the host closes its view', () async {
    final hub = buildHub();
    await pumpEventQueue();
    await openHost(hub, 'local');
    final handle = await hub.openSession(hub.sessionsOf('local').first);

    local.emitSessions([
      fakeSession(hostId: 'local', id: 'l2', providerId: 'codex'),
    ]);
    await pumpEventQueue();

    expect(hub.activeSession, isNull);
    expect((handle as FakeSessionHandle).detachCount, 1);
    hub.dispose();
  });

  test('launch adds the new session and selects it', () async {
    final hub = buildHub();
    await pumpEventQueue();
    await openHost(hub, 'local');

    final handle = await hub.launch(
      const HarnessLaunchRequest(providerId: 'claude', cwd: '/tmp/project'),
    );
    await pumpEventQueue();

    expect(handle.info.providerId, 'claude');
    expect(hub.activeSession?.id, handle.info.id);
    expect(
      hub.sessionsOf('local').map((session) => session.id),
      contains(handle.info.id),
    );
    hub.dispose();
  });

  test('launching on another host switches to that host', () async {
    final hub = buildHub();
    await pumpEventQueue();
    expect(hub.currentHostId, 'studio');

    final handle = await hub.launch(
      const HarnessLaunchRequest(providerId: 'claude', cwd: '/tmp/project'),
      hostId: 'remote-pc',
    );
    await pumpEventQueue();

    // 新会话在远程主机上：顶栏、侧边栏都会按新主机画，不能还停在本机。
    expect(hub.currentHostId, 'remote-pc');
    expect(hub.activeSession?.hostId, 'remote-pc');
    expect(
      hub.currentSessions.map((session) => session.id),
      contains(handle.info.id),
    );
    hub.dispose();
  });

  test('launching without a host reports a readable error', () async {
    final hub = HarnessHub(hosts: const [], desktop: true);
    await pumpEventQueue();

    expect(hub.currentHost, isNull);
    expect(hub.launchMenu(), completion(isEmpty));
    await expectLater(
      hub.launch(const HarnessLaunchRequest(providerId: 'claude', cwd: '/tmp')),
      throwsA(isA<HarnessHubException>()),
    );
    hub.dispose();
  });

  test('refresh re-subscribes and picks up new sessions', () async {
    final hub = buildHub();
    await pumpEventQueue();
    await openHost(hub, 'local');
    expect(hub.currentSessions, hasLength(2));

    local.emitSessions([
      fakeSession(hostId: 'local', id: 'l3', providerId: 'pi', title: 'Pi'),
    ]);
    await hub.refresh();
    await pumpEventQueue();

    expect(hub.currentSessions.map((session) => session.id), ['l3']);
    hub.dispose();
  });

  test('dispose detaches the view and disposes every host once', () async {
    final hub = buildHub();
    await pumpEventQueue();
    await openHost(hub, 'local');
    final handle = await hub.openSession(hub.sessionsOf('local').first);

    hub.dispose();
    await pumpEventQueue();

    expect((handle as FakeSessionHandle).detachCount, 1);
    expect(local.disposeCount, 1);
    expect(remote.disposeCount, 1);
  });

  test('a hub that does not own its hosts leaves them running', () async {
    // 共享主机（应用级单例）的形态：关闭编辑页只摘监听，不释放主机。
    final hub = HarnessHub(
      hosts: [local, remote],
      desktop: true,
      ownsHosts: false,
    );
    await pumpEventQueue();
    hub.dispose();
    await pumpEventQueue();

    expect(local.disposeCount, 0);
    expect(remote.disposeCount, 0);

    // 主机仍然可用：再建一个 hub 仍能读到会话。
    final again = HarnessHub(hosts: [local, remote], desktop: true);
    await pumpEventQueue();
    expect(again.currentSessions, isNotEmpty);
    again.dispose();
  });

  test('groupSessionsByProvider keeps unknown providers under their id', () {
    final groups = groupSessionsByProvider(
      [
        fakeSession(hostId: 'x', id: 'a', providerId: 'mystery'),
        fakeSession(hostId: 'x', id: 'b', providerId: 'claude'),
      ],
      labels: const {'claude': 'Claude Code'},
    );

    expect(groups.map((group) => group.label), ['Claude Code', 'mystery']);
  });
}

/// 切到某台主机并等一次事件队列。
///
/// 会话订阅是按需建立的：切过去才会拉那台主机的列表。
Future<void> openHost(HarnessHub hub, String id) async {
  hub.selectHost(id);
  await pumpEventQueue();
}

/// 主机自定义的结构化安装说明（对应 Pi-B 的 `HerdrInstallHint`）。
class _StructuredHint {
  const _StructuredHint(this.message);

  final String message;
  final String title = 'Herdr';
  final String? url = null;
}

/// 只带默认 `toString` 的对象：拿不到文字。
class _OpaqueHint {
  const _OpaqueHint();
}

/// 给结构化提示的主机：不需要实现全部行为，只要能被 hub 读提示。
class _StructuredHintHost extends FakeHarnessHost {
  _StructuredHintHost()
    : super(
        id: 'herdr',
        label: 'Herdr',
        kind: HarnessHostKind.local,
        initialState: HarnessHostState.unsupported,
      );

  @override
  Object? get installHint => const _StructuredHint('服务未运行，请重启 Herdr');
}
