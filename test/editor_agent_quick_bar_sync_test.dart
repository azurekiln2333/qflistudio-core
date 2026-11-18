@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/agent/editor_agent_host.dart';
import 'package:qfli_studio_core/editor/editor_bottom_inset.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_quick_bar.dart';
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

/// 三个分支都改过 `editor_page.dart`，这一组测试钉住合并后的联合行为：
///
/// - 快捷栏（r5/pi3）夹在顶栏与文件标签栏之间，宽广两种布局都在；
/// - Android 底部让位（r5/pi2）作用在快捷栏下方的全部内容上；
/// - agent 与编辑器的同步（r5/pi1）驱动快捷栏与主体分段。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double navBar = 48;

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
      id: 'editor-agent-quick-bar-sync-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_bar_sync_');
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    File(
      p.join(directory.path, 'src', 'main.dart'),
    ).writeAsStringSync('void main() {\n  print(1);\n}\n');
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
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 排队中的历史写入可能还握着句柄。
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    required Size size,
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
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
          initialOpenPath: p.join(directory.path, 'src', 'main.dart'),
          agentRuntime: runtime,
          composerDefaults: composerDefaults,
          agentEnabled: true,
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  final bar = find.byKey(const ValueKey('editor-quick-bar'));

  bool barShowsAgent(WidgetTester tester) => find
      .byKey(const ValueKey('editor-quick-bar-agent'))
      .evaluate()
      .isNotEmpty;

  bool hasSlot(String id) =>
      find.byKey(ValueKey('quick-$id')).evaluate().isNotEmpty;

  testWidgets('手机：快捷栏在顶栏下方、标签栏上方，底部让位仍生效', (tester) async {
    // 让位只在 Android 生效，测试体内的 try/finally 恢复，框架的调试变量
    // 不变检查在 tearDown 之前跑。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await mount(
        tester,
        size: const Size(412, 900),
        bottomInset: navBar,
      );

      expect(bar, findsOneWidget);
      expect(barShowsAgent(tester), isFalse);
      expect(
        tester.getTopLeft(bar).dy,
        tester.getBottomLeft(find.byType(AppBar)).dy,
        reason: '快捷栏紧贴顶栏下方',
      );
      expect(
        tester.getBottomLeft(bar).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TabBar)).dy),
        reason: '快捷栏在文件标签栏上方',
      );
      expect(tester.getSize(bar).height, EditorQuickBar.height);

      // 整块主体（含快捷栏）停在导航条上方。
      final body = tester.getRect(
        find.byKey(const ValueKey('editor-body-wide')).first,
      );
      expect(body.bottom, closeTo(900 - navBar, 0.5));
      expect(tester.getRect(bar).bottom, lessThanOrEqualTo(body.bottom));
      expect(EditorBottomInset.ownsBottomBar, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('手机：分段切换同时驱动快捷栏与主体', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await mount(
        tester,
        size: const Size(412, 900),
        bottomInset: navBar,
      );

      await tester.tap(find.byTooltip('打开 Agent 面板'));
      await _pumpFrames(tester);
      expect(find.byType(WorkbenchAgentPane), findsOneWidget);
      expect(barShowsAgent(tester), isTrue);
      expect(hasSlot('agent-new-session'), isTrue);
      expect(hasSlot('save'), isFalse, reason: 'Agent 分段里不出现编辑器动作');

      await tester.tap(find.byTooltip('返回编辑器'));
      await _pumpFrames(tester);
      expect(find.byType(WorkbenchAgentPane), findsNothing);
      expect(barShowsAgent(tester), isFalse);
      expect(hasSlot('save'), isTrue);
      expect(hasSlot('agent-new-session'), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('窄屏：从会话文件卡片回到编辑器后快捷栏是编辑动作', (tester) async {
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
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('打开文件树'));
    await _pumpFrames(tester);
    final switchToSessions = find.byKey(
      const ValueKey('editor-sidebar-section-sessions'),
    );
    if (switchToSessions.evaluate().isNotEmpty) {
      await tester.tap(switchToSessions);
      await _pumpFrames(tester);
    }
    await tester.tap(find.text('写一个文件').first);
    await _pumpFrames(tester);
    expect(barShowsAgent(tester), isTrue);

    final card = find.byKey(const ValueKey('chat-file-card-notes.txt'));
    expect(card, findsOneWidget);
    await tester.tap(card);
    await _pumpFrames(tester);
    await _pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );

    expect(find.byType(WorkbenchAgentPane), findsNothing);
    expect(
      barShowsAgent(tester),
      isFalse,
      reason: '回到编辑器后快捷栏跟着换成编辑动作',
    );
    expect(hasSlot('save'), isTrue);
  });

  testWidgets('宽屏：文件树开文件后快捷栏回到编辑动作，右栏不收起', (tester) async {
    await mount(tester, size: const Size(1280, 800));

    await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
    await _pumpFrames(tester);
    expect(find.byType(WorkbenchAgentPane), findsOneWidget);
    expect(barShowsAgent(tester), isTrue);

    final open = find.byTooltip('打开文件树');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
      await _pumpFrames(tester);
    }
    await tester.tap(find.text('notes.txt').last);
    await _pumpFrames(tester);

    expect(
      find.byType(WorkbenchAgentPane),
      findsOneWidget,
      reason: '宽屏右栏和编辑器并排，点文件不收起对话流',
    );
    expect(
      barShowsAgent(tester),
      isFalse,
      reason: '用户在编辑器里开了文件，快捷栏换成编辑动作',
    );
    expect(hasSlot('save'), isTrue);
    expect(hasSlot('agent-new-session'), isFalse);
  });

  testWidgets('矮窗口：快捷栏让位，动作回到「更多」菜单', (tester) async {
    await mount(tester, size: const Size(1100, 175));

    expect(bar, findsNothing, reason: '高度不够时快捷栏整个不画');
    await tester.tap(find.byTooltip('更多').first);
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('quick-save')),
      findsNothing,
      reason: '菜单里是 quick:<id> 条目，不是快捷栏',
    );
    expect(find.text('保存 (Ctrl+S)'), findsOneWidget);
  });

  testWidgets('桌面：没有导航条让位，快捷栏仍夹在顶栏与标签栏之间', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await mount(
        tester,
        size: const Size(1280, 800),
        bottomInset: navBar,
      );

      expect(EditorBottomInset.ownsBottomBar, isFalse);
      final body = tester.getRect(
        find.byKey(const ValueKey('editor-body-wide')).first,
      );
      expect(body.bottom, closeTo(800, 0.5), reason: '其他平台由宿主避让');
      expect(
        tester.getTopLeft(bar).dy,
        tester.getBottomLeft(find.byType(AppBar)).dy,
      );
      expect(find.byType(FileExplorer), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int frames = 300,
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: '等待的条件没有达成');
}

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
