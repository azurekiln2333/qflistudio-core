@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/agent/editor_agent_host.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';
import 'package:re_editor/re_editor.dart';

import 'support/fake_agent.dart';

/// 从 agent 界面回到编辑器：点卡片、点文件树都要落在那一个文件上。
///
/// 覆盖 brief 第 3、4 条。宽屏右栏保持打开；窄屏切回「编辑器」分段。
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
      id: 'editor-agent-navigation-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_agent_nav_');
    File(
      p.join(directory.path, 'notes.txt'),
    ).writeAsStringSync('hello agent\n', flush: true);
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
      modelOptions: const [AgentModelOption(id: 'model-a', label: 'Model A')],
    );
    EditorAgentHost.resetRuntimeResolutions();
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    store.dispose();
    settings.dispose();
    auth.dispose();
    runtime.fileEvents.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 排队中的历史写入可能还握着句柄。
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    required Size size,
    String? initialOpenPath,
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
          initialOpenPath: initialOpenPath,
          agentRuntime: runtime,
          composerDefaults: composerDefaults,
          agentEnabled: true,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets('窄屏：文件树里点文件后切回编辑器', (tester) async {
    await mount(tester, size: const Size(500, 900));

    // 先到 Agent 分段。
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);
    expect(find.byType(WorkbenchAgentPane), findsOneWidget);

    // 抽屉里的文件树点开 notes.txt。
    await tester.tap(find.byTooltip('打开文件树'));
    await pumpFrames(tester);
    expect(find.byType(FileExplorer), findsOneWidget);
    await tester.tap(find.text('notes.txt').last);
    await pumpFrames(tester);

    expect(
      find.byType(WorkbenchAgentPane),
      findsNothing,
      reason: '窄屏点文件后要回到「编辑器」分段',
    );
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text,
      'hello agent\n',
    );
    expect(find.byTooltip('打开 Agent 面板'), findsOneWidget);
  });

  testWidgets('宽屏：文件树里点文件，Agent 右栏保持打开', (tester) async {
    await mount(tester, size: const Size(1280, 900));

    await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
    await pumpFrames(tester);
    expect(find.byType(WorkbenchAgentPane), findsOneWidget);

    final open = find.byTooltip('打开文件树');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
      await pumpFrames(tester);
    }
    await tester.tap(find.text('notes.txt').last);
    await pumpFrames(tester);

    expect(
      find.byType(WorkbenchAgentPane),
      findsOneWidget,
      reason: '宽屏右栏和编辑器并排，点文件不收起对话流',
    );
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text,
      'hello agent\n',
    );
  });

  testWidgets('窄屏：点对话流里的文件卡片，打开文件并切回编辑器', (tester) async {
    final meta = await sessions.create(project.id, title: '写一个文件');
    final facade = FakeAgentFacade(sessionId: meta.id);
    runtime.facades[meta.id] = facade;
    facade.seed([
      const AgentMessageView(
        id: 't1',
        role: 'tool',
        text: '已写入 notes.txt',
        toolName: 'write_file',
        changedPaths: ['notes.txt'],
      ),
    ]);
    await mount(tester, size: const Size(500, 900));

    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);
    // 展开侧边栏的会话分段，选中那个会话。
    await tester.tap(find.byTooltip('打开文件树'));
    await pumpFrames(tester);
    final switchToSessions = find.byKey(
      const ValueKey('editor-sidebar-section-sessions'),
    );
    if (switchToSessions.evaluate().isNotEmpty) {
      await tester.tap(switchToSessions);
      await pumpFrames(tester);
    }
    await tester.tap(find.text('写一个文件').first);
    await pumpFrames(tester);
    // 选中会话会切回 Agent 分段。
    expect(find.byType(WorkbenchAgentPane), findsOneWidget);

    final card = find.byKey(const ValueKey('chat-file-card-notes.txt'));
    expect(card, findsOneWidget, reason: '写入的文件要有卡片');
    await tester.tap(card);
    await pumpFrames(tester);

    expect(
      find.byType(WorkbenchAgentPane),
      findsNothing,
      reason: '点卡片后窄屏切回「编辑器」分段',
    );
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text,
      'hello agent\n',
    );
  });

  testWidgets('会话状态由窄屏切到编辑器时重新对一次磁盘', (tester) async {
    await mount(
      tester,
      size: const Size(500, 900),
      initialOpenPath: p.join(directory.path, 'notes.txt'),
    );
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text,
      'hello agent\n',
    );

    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    // 文件在 agent 分段期间被外部改写，但没有事件（模拟事件丢失）。
    File(
      p.join(directory.path, 'notes.txt'),
    ).writeAsStringSync('changed outside\n', flush: true);

    await tester.tap(find.byTooltip('返回编辑器'));
    await pumpFrames(tester);

    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text,
      'changed outside\n',
      reason: '回到编辑器时按磁盘对一次打开的标签页',
    );
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

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int frames = 200,
}) async {
  for (var i = 0; i < frames; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
  fail('condition not met');
}

/// 内存实现：测试里不碰文件系统，也不留目录探测定时器。
class _MemoryComposerDefaults implements ComposerDefaultsStore {
  final Map<String, ComposerDefaults> _byProject = {};

  @override
  Future<ComposerDefaults?> read(String projectId) async =>
      _byProject[projectId];

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) async {
    _byProject[projectId] = defaults;
  }
}