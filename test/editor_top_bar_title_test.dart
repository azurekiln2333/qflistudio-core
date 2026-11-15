@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/agent/editor_agent_host.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 面板切换并入顶栏，保留标题宽度和后台角标。
///
/// 424 逻辑宽下开关开、关两种情况的标题渲染宽度相同。
/// 切换按钮的触摸目标不小于 44。
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
      id: 'editor-top-bar-title-test',
      appTitle: 'QFLIStudio+',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_top_bar_');
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
    bool agentEnabled = true,
    double textScale = 1,
    Brightness brightness = Brightness.light,
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
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          agentRuntime: runtime,
          composerDefaults: composerDefaults,
          agentEnabled: agentEnabled,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// 顶栏项目名的实际渲染宽度。
  double titleWidth(WidgetTester tester) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(project.name),
    );
    return paragraph.size.width;
  }

  /// 顶栏项目名是否被省略号截断。
  bool titleTruncated(WidgetTester tester) => tester
      .renderObject<RenderParagraph>(find.text(project.name))
      .didExceedMaxLines;

  testWidgets('424 宽：agent 开关不影响标题宽度', (tester) async {
    const size = Size(424, 900);

    await mount(tester, size: size, agentEnabled: true);
    final withAgent = titleWidth(tester);
    expect(
      find.byKey(const ValueKey('editor-agent-toggle')),
      findsOneWidget,
      reason: '面板切换并入顶栏',
    );
    expect(find.byKey(const ValueKey('editor-main-pane-switch')), findsNothing);

    await mount(tester, size: size, agentEnabled: false);
    final withoutAgent = titleWidth(tester);
    expect(withoutAgent, withAgent, reason: '切换按钮复用撤销的位置，标题宽度不变');
    expect(withoutAgent, greaterThan(0));
    expect(titleTruncated(tester), isFalse, reason: '项目名不应被切换按钮挤压');
    expect(tester.takeException(), isNull, reason: '424 宽不应有溢出');
  });

  testWidgets('手机顶栏适配浅深主题与大字，触摸目标不小于 44', (tester) async {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 360.0, 424.0]) {
        await mount(
          tester,
          size: Size(width, 900),
          textScale: 1.3,
          brightness: brightness,
        );
        final toggle = find.byKey(const ValueKey('editor-agent-toggle'));
        final toolbar = find.byType(AppBar);
        expect(find.ancestor(of: toggle, matching: toolbar), findsOneWidget);
        final rect = tester.getRect(toggle);
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('editor-pane-editor')))
              .dy,
          tester.getBottomLeft(toolbar).dy,
          reason: '内容区紧接顶栏，不再预留切换行',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('424 宽：后台角标显示在顶栏', (tester) async {
    final waiting = await sessions.create(project.id, title: '等确认的');
    runtime.liveStatuses[waiting.id] = AgentLiveStatus.awaitingApproval;

    await mount(tester, size: const Size(424, 900));
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    expect(find.byKey(const ValueKey('editor-main-pane-switch')), findsNothing);
    expect(
      find.byKey(const ValueKey('editor-agent-badge')),
      findsOneWidget,
      reason: '窄屏顶栏保留后台会话角标',
    );
    expect(find.byTooltip('返回编辑器'), findsOneWidget);
  });

  testWidgets('中屏 900 宽使用顶栏入口', (tester) async {
    await mount(tester, size: const Size(900, 900));

    expect(find.byKey(const ValueKey('editor-agent-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-main-pane-switch')), findsNothing);
  });

  testWidgets('1280 宽保留顶栏图标与角标', (tester) async {
    final waiting = await sessions.create(project.id, title: '等确认的');
    runtime.liveStatuses[waiting.id] = AgentLiveStatus.awaitingApproval;

    await mount(tester, size: const Size(1280, 900));

    expect(find.byKey(const ValueKey('editor-agent-toggle')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-main-pane-switch')),
      findsNothing,
      reason: '宽屏并排右栏，没有分段条',
    );

    // 展开右栏才会解析运行时，角标随之出现在顶栏图标上。
    await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
    await pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('editor-agent-badge')),
      findsOneWidget,
      reason: '宽屏的角标仍在顶栏图标上',
    );
    await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('editor-agent-expand')), findsOneWidget);
  });

  testWidgets('当前会话失败时，切回编辑器才显示角标', (tester) async {
    final meta = await sessions.create(project.id, title: '当前会话');
    final facade = FakeAgentFacade(sessionId: meta.id);
    runtime.facades[meta.id] = facade;

    await mount(tester, size: const Size(424, 900));
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    // 侧边栏打开刚创建的唯一会话，让它成为前台正在看的会话。
    await tester.tap(find.byTooltip('打开文件树'));
    await pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey('editor-sidebar-section-sessions')),
    );
    await pumpFrames(tester);
    await tester.tap(find.byKey(ValueKey('session-${meta.id}')));
    await pumpFrames(tester);

    // 用户正在看当前会话，不显示它的失败角标。
    runtime.liveStatuses[meta.id] = AgentLiveStatus.failed;
    runtime.notifyLive();
    await pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('editor-agent-badge')),
      findsNothing,
      reason: '当前会话的错误不计入后台角标',
    );

    // 返回编辑器后，该会话计入后台角标。
    await tester.tap(find.byTooltip('返回编辑器'));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('editor-agent-badge')), findsOneWidget);

    // 会话恢复空闲后，顶栏清除角标。
    runtime.liveStatuses[meta.id] = AgentLiveStatus.idle;
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('editor-agent-badge')), findsNothing);
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
  Future<ComposerDefaults?> read(String projectId) async =>
      _byProject[projectId];

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) async {
    _byProject[projectId] = defaults;
  }
}
