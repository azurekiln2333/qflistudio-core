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

/// 窄屏顶栏不再重复放机器人图标，标题不被挤扁。
///
/// 覆盖第四轮 brief 的 pi-A 第 1-5 条：
/// 424 逻辑宽下开关开、关两种情况的标题渲染宽度相同；
/// 分段条不溢出，触摸目标不小于 44；
/// 宽屏的顶栏图标与角标照旧。
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
      findsNothing,
      reason: '窄屏顶栏不再放机器人图标，它和分段条重复',
    );
    expect(
      find.byKey(const ValueKey('editor-main-pane-switch')),
      findsOneWidget,
    );

    await mount(tester, size: size, agentEnabled: false);
    final withoutAgent = titleWidth(tester);
    expect(
      withoutAgent,
      withAgent,
      reason: '顶栏少了机器人图标，开关开和关的标题必须一样宽',
    );
    expect(withoutAgent, greaterThan(0));
    expect(
      titleTruncated(tester),
      isFalse,
      reason: '去掉重复的机器人图标后，项目名不该再被挤成「Ba…」',
    );
    expect(tester.takeException(), isNull, reason: '424 宽不应有溢出');
  });

  testWidgets('424 宽：分段条不溢出，触摸目标不小于 44', (tester) async {
    await mount(tester, size: const Size(424, 900));

    final bar = find.byKey(const ValueKey('editor-main-pane-switch'));
    expect(bar, findsOneWidget);
    expect(tester.takeException(), isNull, reason: '分段条不应溢出');

    final barRect = tester.getRect(bar);
    expect(barRect.right, lessThanOrEqualTo(424));
    expect(barRect.height, greaterThanOrEqualTo(44), reason: '触摸目标不能低于 44');

    // 每一段单独都不小于 44 宽。
    final editorSegment = find.text('编辑器');
    final agentSegment = find.text('Agent');
    expect(tester.getSize(editorSegment).width, greaterThanOrEqualTo(24));
    expect(tester.getSize(agentSegment).width, greaterThanOrEqualTo(24));
    for (final segment in [editorSegment, agentSegment]) {
      final center = tester.getCenter(segment);
      expect(barRect.contains(center), isTrue);
    }
  });

  testWidgets('424 宽：角标挂在分段条的 Agent 段上', (tester) async {
    final waiting = await sessions.create(project.id, title: '等确认的');
    runtime.liveStatuses[waiting.id] = AgentLiveStatus.awaitingApproval;

    await mount(tester, size: const Size(424, 900));
    // 打开 Agent 分段才会解析运行时，角标随之出现。
    await tester.tap(find.text('Agent'));
    await pumpFrames(tester);

    expect(find.byKey(const ValueKey('editor-main-pane-switch')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-agent-badge')),
      findsOneWidget,
      reason: '窄屏的角标挂在分段条上，不是顶栏',
    );
    expect(find.byKey(const ValueKey('editor-agent-toggle')), findsNothing);
  });

  testWidgets('中屏 900 宽也没有顶栏机器人图标', (tester) async {
    await mount(tester, size: const Size(900, 900));

    expect(
      find.byKey(const ValueKey('editor-agent-toggle')),
      findsNothing,
      reason: '中屏仍是分段布局，没有并排右栏',
    );
    expect(
      find.byKey(const ValueKey('editor-main-pane-switch')),
      findsOneWidget,
    );
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
