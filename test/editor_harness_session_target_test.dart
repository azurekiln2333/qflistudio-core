@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/harness_session_target.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import 'support/fake_agent.dart';
import 'support/fake_harness_host.dart';
import 'support/memory_composer_defaults.dart';

/// 首帧选中会话：目标值本身、外来 hub 的接线与两条打开路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HarnessSessionTarget', () {
    test('同主机同会话相等', () {
      const a = HarnessSessionTarget(hostId: 'remote:1', sessionId: 's-1');
      const b = HarnessSessionTarget(hostId: 'remote:1', sessionId: 's-1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('主机或会话不同即不等', () {
      const base = HarnessSessionTarget(hostId: 'remote:1', sessionId: 's-1');
      expect(
        base,
        isNot(const HarnessSessionTarget(hostId: 'remote:2', sessionId: 's-1')),
      );
      expect(
        base,
        isNot(const HarnessSessionTarget(hostId: 'remote:1', sessionId: 's-2')),
      );
    });

    test('toString 带两个 id，便于日志定位', () {
      expect(
        const HarnessSessionTarget(
          hostId: 'remote:1',
          sessionId: 's-1',
        ).toString(),
        contains('s-1'),
      );
    });
  });

  late Directory directory;
  late Project project;
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late FakeAgentRuntime runtime;
  StudioProfile? previousProfile;

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'editor-harness-session-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_harness_target_');
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    File(
      p.join(directory.path, 'src', 'main.dart'),
    ).writeAsStringSync('void main() {\n  print(1);\n}\n');
    project = Project.create(name: 'Demo', path: directory.path);
    store = ProjectStore();
    settings = SettingsStore();
    auth = AuthStore();
    await auth.signIn(
      'token',
      const CommunityUser(
        id: 'u1',
        username: 'demo',
        nickname: 'Demo',
        bio: '',
        avatarColor: '#000000',
        points: 0,
        checkinStreak: 0,
        provider: 'local',
      ),
    );
    runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore());
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 后台历史写入可能还握着句柄。
    }
  });

  /// 挂载编辑器，注入首页那一份 hub。
  ///
  /// 输入卡片的选择记忆换成内存实现：文件实现要问存储目录（`AppPaths`），
  /// 而路径探测会挂一个 2 秒的可写性定时器。widget 测试里这些平台通道不会
  /// 回应，定时器就留到用例结束，整条用例以「A Timer is still pending」失败。
  /// 同目录下几份编辑器用例一直这么写，这里补上。
  Future<void> mount(
    WidgetTester tester, {
    required HarnessHub hub,
    HarnessSessionTarget? target,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          agentRuntime: runtime,
          agentEnabled: true,
          harnessHub: hub,
          ownsHarnessHub: false,
          composerDefaults: MemoryComposerDefaults(),
          initialHarnessSession: target,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  HarnessHub hubWith(List<HarnessHost> hosts) {
    final hub = HarnessHub(hosts: hosts, desktop: true, ownsHosts: false);
    addTearDown(hub.dispose);
    return hub;
  }

  testWidgets('目标主机是已绑定电脑：首帧交给 hub 打开该会话', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(hostId: 'remote:1', id: 's-1', title: '改登录'),
        fakeSession(hostId: 'remote:1', id: 's-2', title: '改注册'),
      ],
    );
    addTearDown(remote.dispose);
    await mount(
      tester,
      hub: hubWith([remote]),
      target: const HarnessSessionTarget(hostId: 'remote:1', sessionId: 's-2'),
    );

    expect(remote.opened, ['s-2'], reason: '只开目标会话，不碰别的');
  });

  testWidgets('内置 Agent 的会话不进 hub，直接选中会话 id', (tester) async {
    final studio = FakeHarnessHost(
      id: 'studio',
      label: '内置 Agent',
      kind: HarnessHostKind.studio,
      initialSessions: [fakeSession(hostId: 'studio', id: 'built-in-1')],
    );
    addTearDown(studio.dispose);
    await mount(
      tester,
      hub: hubWith([studio]),
      target: const HarnessSessionTarget(
        hostId: 'studio',
        sessionId: 'built-in-1',
      ),
    );

    expect(studio.opened, isEmpty, reason: '内置面板自己渲染会话，不走 hub.open');
  });

  testWidgets('主机不在线时给出提示，不抛异常', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
    );
    addTearDown(remote.dispose);
    await mount(
      tester,
      hub: hubWith([remote]),
      target: const HarnessSessionTarget(
        hostId: 'remote:gone',
        sessionId: 's-1',
      ),
    );

    expect(find.textContaining('打不开这个会话'), findsWidgets);
  });

  testWidgets('会话迟迟不出现时超时提示', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: const [],
    );
    addTearDown(remote.dispose);
    await mount(
      tester,
      hub: hubWith([remote]),
      target: const HarnessSessionTarget(hostId: 'remote:1', sessionId: 's-9'),
    );

    await tester.pump(const Duration(seconds: 16));
    await tester.pump();

    expect(find.textContaining('等待超时'), findsWidgets);
    expect(remote.opened, isEmpty);
  });

  testWidgets('不传目标时什么都不开', (tester) async {
    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: [fakeSession(hostId: 'remote:1', id: 's-1')],
    );
    addTearDown(remote.dispose);
    await mount(tester, hub: hubWith([remote]));

    expect(remote.opened, isEmpty);
  });
}
