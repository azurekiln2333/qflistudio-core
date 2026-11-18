@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/composer_card.dart';
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/editor/editor_bottom_inset.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// Android 的系统导航条（手势条或三键栏）不能压住编辑器页的内容。
///
/// 编辑器页的 Scaffold 没有底部导航栏，body 直接铺到屏幕底边。这里用假的
/// 底部 `viewPadding` 复核：最后一行、终端输入和 agent 输入卡片都在导航条
/// 上方，键盘顶起时不重复留白，其他平台保持原样。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double height = 900;
  const double width = 412;
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
      id: 'editor-bottom-inset-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_bottom_inset_');
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
  });

  tearDown(() async {
    StudioProfile.current = previousProfile;
    debugDefaultTargetPlatformOverride = null;
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 排队中的历史写入可能还握着句柄。
    }
  });

  /// 挂载真实编辑器页，底部系统栏由假数据给定。
  Future<void> mount(
    WidgetTester tester, {
    double bottomInset = 0,
    double keyboardInset = 0,
    Size size = const Size(width, height),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    // 真实引擎里 padding 已经减掉键盘高度；假视图不替我们算。
    tester.view.padding = FakeViewPadding(
      bottom: keyboardInset > 0 ? 0 : bottomInset,
    );
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
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

  Rect bodyRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('editor-body-wide')).first);

  group('Android 底部导航条', () {
    testWidgets('页面主体整体让开 48 的导航条', (tester) async {
      await mount(tester, bottomInset: navBar);

      // Scaffold 没有底部导航栏，body 原来铺到 852；现在停在导航条上方。
      expect(bodyRect(tester).bottom, closeTo(height - navBar, 0.5));
      expect(
        bodyRect(tester).height,
        closeTo(height - kToolbarHeight - navBar, 1),
      );
    });

    testWidgets('agent 输入卡片在导航条上方', (tester) async {
      await mount(tester, bottomInset: navBar);
      // 先量主体：切到 Agent 后编辑器那一侧会被藏起来。
      final body = bodyRect(tester);

      // 窄屏用顶栏切到 Agent，输入卡片是页面最下方的一块。
      await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
      await _pumpFrames(tester);
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('composer-input')).evaluate().isNotEmpty,
      );

      final composer = tester.getRect(find.byType(ComposerCard));
      expect(
        composer.bottom,
        lessThanOrEqualTo(height - navBar),
        reason: '输入卡片不能被系统导航条盖住',
      );
      // 卡片自己的 8 内边距还在：它贴着 body 底部，只是让开了导航条。
      expect(composer.bottom, greaterThan(body.bottom - 24));
    });

    testWidgets('终端面板底边也在导航条上方', (tester) async {
      await mount(tester, bottomInset: navBar);

      // 打开终端：它是页面最下面的一条面板，底边必须停在导航条上方。
      await tester.tap(find.byTooltip('更多').first);
      final entry = find.widgetWithText(PopupMenuItem<String>, '打开终端');
      await _pumpUntil(tester, () => entry.evaluate().isNotEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(entry.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpFrames(tester);

      final terminal = tester.getRect(find.byType(TerminalPane));
      expect(
        terminal.bottom,
        lessThanOrEqualTo(height - navBar),
        reason: '终端面板不能被系统导航条盖住',
      );
      expect(
        terminal.bottom,
        closeTo(bodyRect(tester).bottom, 0.5),
        reason: '终端面板贴着 body 底部，只是让开了导航条',
      );
    });

    testWidgets('没有导航条时不额外留白', (tester) async {
      // 手势条宽度为 0 的设备（或全屏沉浸）：行为与基线一致。
      await mount(tester);
      expect(bodyRect(tester).bottom, closeTo(height, 0.5));
    });

    testWidgets('键盘顶起时不叠加导航条留白', (tester) async {
      await mount(tester, bottomInset: navBar, keyboardInset: 300);

      // Scaffold 已经按键盘缩过 body，导航条让位应为 0。
      final body = bodyRect(tester);
      expect(body.bottom, closeTo(height - 300, 0.5));

      await tester.tap(find.byKey(const ValueKey('editor-agent-toggle')));
      await _pumpFrames(tester);
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('composer-input')).evaluate().isNotEmpty,
      );
      final composer = tester.getRect(find.byType(ComposerCard));
      expect(
        composer.bottom,
        lessThanOrEqualTo(height - 300),
        reason: '键盘上方不该再空出一条导航条',
      );
      expect(composer.bottom, greaterThan(body.bottom - 24));
    });

    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('$platform 不自己让位，交给宿主', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await mount(tester, bottomInset: navBar);

          // 其他平台由窗口或宿主避让；这里再加一层就是多出来的空带。
          expect(bodyRect(tester).bottom, closeTo(height, 0.5));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('编辑器自己让位只发生在 Android', (tester) async {
      try {
        expect(EditorBottomInset.ownsBottomBar, isTrue);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(EditorBottomInset.ownsBottomBar, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('insetOf 读 viewPadding 并减掉键盘', (tester) async {
      double? inset;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(width, height),
              viewPadding: EdgeInsets.only(bottom: navBar),
            ),
            child: Builder(
              builder: (context) {
                inset = EditorBottomInset.insetOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(inset, navBar);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(width, height),
              viewPadding: EdgeInsets.only(bottom: navBar),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: Builder(
              builder: (context) {
                inset = EditorBottomInset.insetOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(inset, 0, reason: '键盘盖住导航条时不再留白');
    });
  });
}

/// 让真实的文件 I/O 和定时器跑完。
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

/// 内存实现：测试里不碰文件系统。
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
