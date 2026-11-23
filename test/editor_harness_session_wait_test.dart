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

/// 首帧选会话若在等待中被打断，不能把定时器留在页面之外。
///
/// 这里专门在「会话还没出现」时立刻拆掉页面。以前 15 秒超时定时器只在
/// `_awaitHubSession` 自己的 `finally` 里取消，页面先销毁时它继续挂在
/// 测试的假时钟上，整条用例以「A Timer is still pending」失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      id: 'editor-harness-wait-dispose',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_harness_wait_');
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    File(
      p.join(directory.path, 'src', 'main.dart'),
    ).writeAsStringSync('void main() {}\n');
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

  testWidgets('等待中的会话在页面销毁时不再挂定时器', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: const [],
    );
    addTearDown(remote.dispose);
    final hub = HarnessHub(hosts: [remote], desktop: true, ownsHosts: false);
    addTearDown(hub.dispose);

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
          // 会话永远不会出现在这个空主机上：页面停在等待里。
          initialHarnessSession: const HarnessSessionTarget(
            hostId: 'remote:1',
            sessionId: 's-missing',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 等待进行中拆页面。定时器必须随 dispose 一起取消。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(remote.opened, isEmpty);
  });

  testWidgets('等满超时后给出提示，且不残留定时器', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final remote = FakeHarnessHost(
      id: 'remote:1',
      label: 'MacBook',
      kind: HarnessHostKind.remote,
      initialSessions: const [],
    );
    addTearDown(remote.dispose);
    final hub = HarnessHub(hosts: [remote], desktop: true, ownsHosts: false);
    addTearDown(hub.dispose);

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
          initialHarnessSession: const HarnessSessionTarget(
            hostId: 'remote:1',
            sessionId: 's-late',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 等到超时那一刻：定时器自己触发并释放。
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(find.textContaining('等待超时'), findsWidgets);
    expect(remote.opened, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
