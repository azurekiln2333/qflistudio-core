@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/agent/agent_dock.dart';
import 'package:qfli_studio_core/editor/agent/editor_agent_host.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/layout/breakpoints.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 宽屏右栏的宽度与 1100 宽下的编辑器列。
///
/// 覆盖第三轮 brief 的 pi-A 第 1-4 条：
/// 右栏 400 宽时输入卡片能放下权限文案；
/// 1100 宽、侧边栏展开时编辑器列仍可用，没有溢出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Project project;
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late MemoryAgentSessionStore sessions;
  late FakeAgentRuntime runtime;
  late _MemoryComposerDefaults composerDefaults;
  StudioProfile? previousProfile;

  setUp(() async {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'editor-wide-agent-pane-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_wide_pane_');
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
    sessions = MemoryAgentSessionStore();
    composerDefaults = _MemoryComposerDefaults();
    runtime = FakeAgentRuntime(
      sessions: sessions,
      modelOptions: const [
        AgentModelOption(
          id: 'model-a',
          label: 'Model A',
          reasoningEfforts: ['low', 'medium', 'high'],
        ),
      ],
    );
    EditorAgentHost.resetRuntimeResolutions();
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 排队中的历史写入可能还握着句柄。
    }
  });

  /// 挂载真实的编辑器页并把右栏展开。侧边栏按需展开。
  Future<void> mount(
    WidgetTester tester, {
    required Size size,
    bool openSidebar = false,
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
          composerDefaults: composerDefaults,
          agentEnabled: true,
        ),
      ),
    );
    await pumpFrames(tester);
    if (openSidebar) {
      final open = find.byTooltip('打开文件树');
      if (open.evaluate().isNotEmpty) {
        await tester.tap(open);
        await pumpFrames(tester);
      }
    }
    await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
    await pumpFrames(tester);
  }

  testWidgets('宽屏右栏宽 400，权限文案看得见', (tester) async {
    await mount(tester, size: const Size(1280, 900));

    expect(find.byType(AgentDock), findsOneWidget);
    expect(
      tester.getSize(find.byType(AgentDock)).width,
      Breakpoints.agentPaneWidth,
      reason: '右栏宽度只从 Breakpoints.agentPaneWidth 取',
    );
    expect(Breakpoints.agentPaneWidth, 400, reason: '360 时权限与推理只剩图标');

    // 权限按钮带文案，不是只剩一个图标。
    expect(find.text('每次询问'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1100 宽、侧边栏展开：编辑器列仍可用，没有溢出', (tester) async {
    await mount(tester, size: const Size(1100, 900), openSidebar: true);

    expect(find.byKey(const ValueKey('editor-sidebar-slot')), findsOneWidget);
    expect(find.byType(AgentDock), findsOneWidget);

    final editorColumn = tester.getSize(
      find.byKey(const ValueKey('editor-right-column')),
    );
    // 1100 - 侧边栏 280 - 卡片边距 24 - 右栏 400 = 396。
    expect(
      editorColumn.width,
      greaterThanOrEqualTo(300),
      reason: '编辑器列不能被右栏挤到不可用',
    );
    expect(tester.takeException(), isNull, reason: '1100 宽不应有溢出');
  });

  testWidgets('1100 宽、侧边栏收起：编辑器列仍可用，没有溢出', (tester) async {
    await mount(tester, size: const Size(1100, 900));

    expect(find.byKey(const ValueKey('editor-sidebar-slot')), findsOneWidget);
    final editorColumn = tester.getSize(
      find.byKey(const ValueKey('editor-right-column')),
    );
    // 1100 - 右栏 400 = 700，侧边栏收起时全给编辑器列。
    expect(editorColumn.width, greaterThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });
}

/// 让真实的文件 I/O 和定时器跑完。
Future<void> pumpFrames(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

/// 内存实现：测试里不碰文件系统，也不留目录探测定时器。
class _MemoryComposerDefaults implements ComposerDefaultsStore {
  final Map<String, ComposerDefaults> _byProject = {};

  @override
  Future<ComposerDefaults?> read(String projectId) async => _byProject[projectId];

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) async {
    _byProject[projectId] = defaults;
  }
}
