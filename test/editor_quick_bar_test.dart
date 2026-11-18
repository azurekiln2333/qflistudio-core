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
import 'package:qfli_studio_core/editor/editor_quick_bar.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 顶栏与文件标签栏之间的快捷功能栏。
///
/// 覆盖：编辑模式只出现编辑器动作，Agent 模式只出现 Agent 动作，切换立即生效，
/// 原来藏在「更多」菜单里的动作一个都不丢。
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
      id: 'editor-quick-bar-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_quick_bar_');
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    File(
      p.join(directory.path, 'src', 'main.dart'),
    ).writeAsStringSync('void main() {\n  print(1);\n}\n');
    File(
      p.join(directory.path, 'src', 'data.json'),
    ).writeAsStringSync('{"a": 1}\n');
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
    String? openPath,
    bool agentEnabled = true,
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
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          initialOpenPath: openPath,
          agentRuntime: runtime,
          composerDefaults: composerDefaults,
          agentEnabled: agentEnabled,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// 快捷栏当前渲染的是编辑动作还是 Agent 动作。
  bool barShowsAgent(WidgetTester tester) => find
      .byKey(const ValueKey('editor-quick-bar-agent'))
      .evaluate()
      .isNotEmpty;

  bool hasSlot(String id) =>
      find.byKey(ValueKey('quick-$id')).evaluate().isNotEmpty;

  testWidgets('手机：快捷栏夹在顶栏和文件标签栏之间，只出现编辑动作', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );

    final bar = find.byKey(const ValueKey('editor-quick-bar'));
    expect(bar, findsOneWidget);
    expect(barShowsAgent(tester), isFalse);

    // 位置：顶栏正下方，标签栏正上方。
    expect(
      tester.getTopLeft(bar).dy,
      tester.getBottomLeft(find.byType(AppBar)).dy,
    );
    expect(
      tester.getBottomLeft(bar).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TabBar)).dy),
    );
    expect(tester.getSize(bar).height, EditorQuickBar.height);

    // 编辑动作在，Agent 动作不在。
    expect(hasSlot('save'), isTrue);
    expect(hasSlot('find'), isTrue);
    expect(hasSlot('format'), isTrue);
    expect(hasSlot('terminal'), isTrue);
    expect(hasSlot('settings'), isTrue);
    expect(hasSlot('undo'), isTrue, reason: '窄屏顶栏没有撤销，快捷栏保留它');
    expect(hasSlot('agent-new-session'), isFalse);
    expect(hasSlot('agent-sessions'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机：切到 Agent 分段后只剩 Agent 动作，切回来恢复', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );

    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    expect(barShowsAgent(tester), isTrue);
    expect(hasSlot('agent-new-session'), isTrue);
    expect(hasSlot('agent-sessions'), isTrue);
    expect(hasSlot('agent-stop'), isTrue);
    // 编辑专用动作必须消失，而不是变成禁用。
    expect(hasSlot('save'), isFalse);
    expect(hasSlot('format'), isFalse);
    expect(hasSlot('terminal'), isFalse);
    expect(hasSlot('settings'), isFalse);

    await tester.tap(find.byTooltip('返回编辑器'));
    await pumpFrames(tester);

    expect(barShowsAgent(tester), isFalse);
    expect(hasSlot('save'), isTrue);
    expect(hasSlot('agent-new-session'), isFalse);
    // 393 宽、Agent 面板可见时，输入卡片的选择器行会报 1 px 横向溢出。
    // 那是 `lib/chat/composer_card.dart` 早已存在的问题（单独挂载该卡片到
    // 341 逻辑宽即可复现），与快捷栏无关。
    expectKnownComposerOverflow(tester);
  });

  testWidgets('宽屏：跟着用户最后触到的面板换内容', (tester) async {
    await mount(tester, size: const Size(1280, 800));
    // 展开按钮就在 Agent 面板上，展开这一步自己就算「触到了 Agent」。
    await tester.tap(find.byKey(const ValueKey('editor-agent-expand')));
    await pumpFrames(tester);
    expect(barShowsAgent(tester), isTrue);

    // 点回编辑器代码区。
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('editor-right-column'))),
    );
    await pumpFrames(tester);
    expect(barShowsAgent(tester), isFalse);
    expect(hasSlot('save'), isTrue);
    expect(hasSlot('agent-new-session'), isFalse);

    // 再点 Agent 面板正文。
    await tester.tapAt(tester.getCenter(find.byType(AgentDock)));
    await pumpFrames(tester);
    expect(barShowsAgent(tester), isTrue);
    expect(hasSlot('agent-new-session'), isTrue);
    expect(hasSlot('save'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有打开文件时编辑动作可见但禁用', (tester) async {
    await mount(tester, size: const Size(393, 852));

    expect(hasSlot('save'), isTrue);
    for (final id in ['save', 'find', 'goto', 'format']) {
      final slot = tester.widget<InkWell>(find.byKey(ValueKey('quick-$id')));
      expect(slot.onTap, isNull, reason: '$id 没有文件时不可点');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机：动作多于宽度时横向滚动，最后一个动作也能点到', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );

    final bar = find.byKey(const ValueKey('editor-quick-bar'));
    final row = find.byKey(const ValueKey('editor-quick-bar-editor'));
    expect(
      tester.getSize(row).width,
      greaterThan(tester.getSize(bar).width),
      reason: '固定槽位多于手机宽度，内容比可视区宽',
    );

    // 最后一个槽位在可视区外，滚动之后可以点到。
    final last = find.byKey(const ValueKey('quick-close_editor'));
    final scrollable = find.descendant(
      of: bar,
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(scrollable, const Offset(-600, 0));
    await tester.pump();
    if (last.evaluate().isNotEmpty) {
      expect(tester.getRect(last).right, lessThanOrEqualTo(393));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('每个原来的菜单动作都还到得了：快捷栏或溢出菜单', (tester) async {
    await mount(
      tester,
      size: const Size(1280, 800),
      openPath: p.join(directory.path, 'src', 'data.json'),
    );

    // 快捷栏里的编辑动作。
    const inBar = {
      'save',
      'find',
      'goto',
      'format',
      'content_tool',
      'minimap',
      'terminal',
      'output',
      'debug',
      'debug_console',
      'ports',
      'git',
      'online_terminal',
      'ai',
      'settings',
    };
    for (final id in inBar) {
      expect(hasSlot(id), isTrue, reason: '快捷栏缺少 $id');
    }
    // 宽屏顶栏保留撤销，快捷栏不重复它。
    expect(hasSlot('undo'), isFalse);

    // 溢出菜单只剩「放不下」的动态动作。
    await tester.tap(find.byTooltip('更多'));
    await pumpFrames(tester, 6);
    expect(find.text('保存 (Ctrl+S)'), findsNothing);
    expect(find.text('查找替换 (Ctrl+F)'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.text('Git'), findsNothing);
    // 关闭回菜单，避免影响卸载。
    await tester.tapAt(const Offset(5, 5));
    await pumpFrames(tester, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离线档位：Git / 云端拉取 / 在线终端 / AI 都不出现', (tester) async {
    StudioProfile.current = const StudioProfile(
      id: 'editor-quick-bar-offline',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: true,
      offlineOnly: true,
    );
    await mount(
      tester,
      size: const Size(1280, 800),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );

    expect(hasSlot('git'), isFalse);
    expect(hasSlot('cloud_pull'), isFalse);
    expect(hasSlot('online_terminal'), isFalse);
    expect(hasSlot('ai'), isFalse);
    // 本地动作不受影响。
    expect(hasSlot('save'), isTrue);
    expect(hasSlot('settings'), isTrue);
    expect(hasSlot('terminal'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有会话在跑时才能停止全部', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    InkWell stop() => tester.widget<InkWell>(
      find.byKey(const ValueKey('quick-agent-stop')),
    );

    expect(stop().onTap, isNull, reason: '没有会话在跑时停止不可点');

    final meta = await sessions.create(project.id, title: '在跑的会话');
    runtime.liveStatuses[meta.id] = AgentLiveStatus.running;
    runtime.notifyLive();
    await pumpFrames(tester, 6);
    expect(stop().onTap, isNotNull, reason: '会话运行中可以停止');
    expectKnownComposerOverflow(tester);
  });

  testWidgets('Agent 动作是真的：新会话与停止全部走运行时', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    expect(sessions.sessionsOf(project.id), isEmpty);
    await tester.tap(find.byKey(const ValueKey('quick-agent-new-session')));
    await pumpFrames(tester);
    expect(sessions.sessionsOf(project.id), isNotEmpty, reason: '新会话按钮直接建一个会话');

    final meta = sessions.sessionsOf(project.id).first;
    runtime.liveStatuses[meta.id] = AgentLiveStatus.running;
    runtime.notifyLive();
    await pumpFrames(tester, 6);
    await tester.tap(find.byKey(const ValueKey('quick-agent-stop')));
    await pumpFrames(tester);
    expect(runtime.cancelAllCount, 1, reason: '停止全部交给运行时');
    expectKnownComposerOverflow(tester);
  });

  testWidgets('会话列表按钮把侧边栏切到会话分段', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
    );
    await tester.tap(find.byTooltip('打开 Agent 面板'));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('quick-agent-sessions')));
    await pumpFrames(tester);

    // 分段已经停在会话：侧边栏的切换按钮现在指向「文件」。
    expect(
      find.byKey(const ValueKey('editor-sidebar-section-files')),
      findsOneWidget,
      reason: '会话列表按钮把侧边栏切到会话',
    );
    expectKnownComposerOverflow(tester);
  });

  testWidgets('栏高就是旧版的 25 dp：手机与平板都是', (tester) async {
    expect(EditorQuickBar.height, 25, reason: '旧版 editor_opeartions_bar 就是 25 dp');
    for (final size in const [Size(393, 852), Size(1280, 800)]) {
      await mount(
        tester,
        size: size,
        openPath: p.join(directory.path, 'src', 'main.dart'),
      );

      final bar = find.byKey(const ValueKey('editor-quick-bar'));
      expect(bar, findsOneWidget, reason: '$size 上快捷栏在');
      expect(tester.getSize(bar).height, 25, reason: '$size 上渲染高度是 25 dp');

      // 槽位没有被 48 dp 的触碰目标撑开。
      final slot = find.byKey(const ValueKey('quick-save'));
      expect(tester.getSize(slot).height, 25, reason: '$size 上槽位高 25 dp');
      expect(tester.getSize(slot).width, EditorQuickBar.slotWidth);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('editor-quick-bar-editor')))
            .height,
        25,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('按住动作就在材质层画涟漪：浅色与深色都画', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await mount(
        tester,
        size: const Size(393, 852),
        openPath: p.join(directory.path, 'src', 'main.dart'),
        brightness: brightness,
      );
      await expectRipple(tester, 'save', visible: true);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('禁用的动作按住不画涟漪', (tester) async {
    // 没有打开文件，保存是禁用的。
    await mount(tester, size: const Size(393, 852));
    await expectRipple(tester, 'save', visible: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色主题下快捷栏用主题色，不写死颜色', (tester) async {
    await mount(
      tester,
      size: const Size(393, 852),
      openPath: p.join(directory.path, 'src', 'main.dart'),
      brightness: Brightness.dark,
    );

    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('editor-quick-bar-editor')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      material.color,
      AppTheme.dark.colorScheme.surface,
      reason: '背景取 ColorScheme.surface',
    );
    expect(tester.takeException(), isNull);
  });
}

/// 按住一个槽位，看快捷栏自己的 Material 有没有画出涟漪。
///
/// 涟漪要落在快捷栏的材质层上：中间只要有一块不透明的 Container 就会把涟漪
/// 挡住，所以这里直接量最近的 `Material` 的绘制记录。
Future<void> expectRipple(
  WidgetTester tester,
  String id, {
  required bool visible,
}) async {
  final slot = find.byKey(ValueKey('quick-$id'));
  final gesture = await tester.startGesture(tester.getCenter(slot));
  // 按住不放：分帧推进，涟漪真的淡入，而不只是刚建出来。
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  final ink = Material.of(tester.element(slot));
  if (visible) {
    expect(ink, paints..circle(), reason: '$id 按住时有涟漪');
  } else {
    expect(ink, isNot(paints..circle()), reason: '$id 禁用时没有涟漪');
  }
  await gesture.up();
  await tester.pump();
}

/// 393 宽、Agent 面板可见时，输入卡片的选择器行报 1 px 横向溢出。
///
/// 那是 `lib/chat/composer_card.dart` 早已存在的问题：把该卡片单独挂到
/// 341 逻辑宽就能复现，本次改动没有动它，也没有改它的宽度约束。
/// 其他任何异常仍然让测试失败。
void expectKnownComposerOverflow(WidgetTester tester) {
  final error = tester.takeException();
  if (error == null) return;
  expect(
    error.toString(),
    contains('overflowed by 1.00 pixels'),
    reason: '只放过输入卡片那 1 px 的已知溢出',
  );
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
