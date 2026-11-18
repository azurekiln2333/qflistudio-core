@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 场景截图：把编辑器页按真实尺寸画出来，写成 PNG。
///
/// 只在设置了 `PI2_SHOT_DIR` 时运行，避免常规 `flutter test` 往仓库外写文件：
///
/// ```
/// PI2_SHOT_DIR=../_wt/round5/reports/shots/pi2 PI2_SHOT_PREFIX=before \
///   flutter test test/editor_sidebar_shots_test.dart
/// ```
final String _shotDir = Platform.environment['PI2_SHOT_DIR'] ?? '';
final String _shotPrefix = Platform.environment['PI2_SHOT_PREFIX'] ?? 'shot';
final bool _shotsEnabled = _shotDir.trim().isNotEmpty;

/// 场景名、尺寸、亮度和要展示的面。
typedef _Scene = ({
  String name,
  Size size,
  Brightness brightness,
  bool sessions,
  bool agent,
  bool sidebar,
  bool terminal,
  double bottomInset,
});

const List<_Scene> _scenes = [
  (
    name: 'phone-light-files',
    size: Size(393, 852),
    brightness: Brightness.light,
    sessions: false,
    agent: false,
    sidebar: true,
    terminal: false,
    bottomInset: 48,
  ),
  (
    name: 'phone-light-terminal',
    size: Size(393, 852),
    brightness: Brightness.light,
    sessions: false,
    agent: false,
    sidebar: false,
    terminal: true,
    bottomInset: 48,
  ),
  (
    name: 'phone-light-sessions',
    size: Size(393, 852),
    brightness: Brightness.light,
    sessions: true,
    agent: false,
    sidebar: true,
    terminal: false,
    bottomInset: 48,
  ),
  (
    name: 'phone-dark-sessions',
    size: Size(393, 852),
    brightness: Brightness.dark,
    sessions: true,
    agent: false,
    sidebar: true,
    terminal: false,
    bottomInset: 48,
  ),
  (
    name: 'phone-light-agent',
    size: Size(393, 852),
    brightness: Brightness.light,
    sessions: false,
    agent: true,
    sidebar: false,
    terminal: false,
    bottomInset: 48,
  ),
  (
    name: 'phone-dark-agent',
    size: Size(393, 852),
    brightness: Brightness.dark,
    sessions: false,
    agent: true,
    sidebar: false,
    terminal: false,
    bottomInset: 48,
  ),
  (
    name: 'tablet-light-files',
    size: Size(1280, 800),
    brightness: Brightness.light,
    sessions: false,
    agent: true,
    sidebar: true,
    terminal: false,
    bottomInset: 0,
  ),
  (
    name: 'tablet-light-sessions',
    size: Size(1280, 800),
    brightness: Brightness.light,
    sessions: true,
    agent: true,
    sidebar: true,
    terminal: false,
    bottomInset: 0,
  ),
  (
    name: 'tablet-dark-sessions',
    size: Size(1280, 800),
    brightness: Brightness.dark,
    sessions: true,
    agent: true,
    sidebar: true,
    terminal: false,
    bottomInset: 0,
  ),
];

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
      id: 'editor-sidebar-shots',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_sidebar_shots_');
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    Directory(p.join(directory.path, 'src', 'components')).createSync();
    Directory(p.join(directory.path, 'docs')).createSync(recursive: true);
    File(
      p.join(directory.path, 'src', 'main.dart'),
    ).writeAsStringSync('void main() {\n  print(1);\n}\n');
    File(
      p.join(directory.path, 'src', 'components', 'sidebar_panel.dart'),
    ).writeAsStringSync('class SidebarPanel {}\n');
    File(
      p.join(directory.path, 'docs', 'README.md'),
    ).writeAsStringSync('# demo\n');
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
    store.dispose();
    settings.dispose();
    auth.dispose();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 排队中的历史写入可能还握着句柄。
    }
  });

  for (final scene in _scenes) {
    testWidgets('场景 ${scene.name}', (tester) async {
      tester.view.physicalSize = scene.size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = FakeViewPadding(bottom: scene.bottomInset);
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      // 有内容的会话列表：三种状态各一条。
      final running = await sessions.create(project.id, title: '补齐文件树状态');
      final waiting = await sessions.create(project.id, title: '等确认的改动');
      await sessions.create(project.id, title: '重构离线编辑器入口');
      runtime.liveStatuses[running.id] = AgentLiveStatus.running;
      runtime.liveStatuses[waiting.id] = AgentLiveStatus.awaitingApproval;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: scene.brightness == Brightness.light
              ? AppTheme.light
              : AppTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewPadding: EdgeInsets.only(bottom: scene.bottomInset),
                padding: EdgeInsets.only(bottom: scene.bottomInset),
              ),
              child: _SceneFrame(
                size: scene.size,
                navBarHeight: scene.bottomInset,
                child: EditorPage(
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
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      if (scene.agent) {
        // 宽屏是右侧面板的展开键，窄屏是顶栏的编辑器/Agent 切换键。
        for (final key in const [
          ValueKey('editor-agent-expand'),
          ValueKey('editor-agent-toggle'),
        ]) {
          final button = find.byKey(key);
          if (button.evaluate().isEmpty) continue;
          await tester.tap(button.first);
          await _pumpFrames(tester);
          break;
        }
      }

      if (scene.terminal) {
        // 打开终端面板：它的输入行是页面最下面的一条控件。
        // 快捷栏可见时直接点 quick-terminal；矮窗口退回 ⋮ 菜单。
        final quick = find.byKey(const ValueKey('quick-terminal'));
        if (quick.evaluate().isNotEmpty) {
          await tester.tap(quick.first);
        } else {
          await tester.tap(find.byTooltip('更多').first);
          final entry = find.widgetWithText(PopupMenuItem<String>, '打开终端');
          await _pumpUntil(tester, () => entry.evaluate().isNotEmpty);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(entry.first);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpFrames(tester);
      }

      // 侧边栏：宽屏是常驻栏，窄屏是抽屉。抽屉只在要展示侧边栏时打开。
      if (scene.sidebar) {
        final openTree = find.byTooltip('打开文件树');
        if (openTree.evaluate().isNotEmpty) {
          await tester.tap(openTree);
          await _pumpFrames(tester);
        }
      }
      if (scene.sessions) {
        final toggle = find.byKey(
          const ValueKey('editor-sidebar-section-switch'),
        );
        if (toggle.evaluate().isNotEmpty) {
          await tester.tap(toggle.first);
          await _pumpFrames(tester);
        }
      }

      final file = File(
        p.join(_shotDirAbs(), '$_shotPrefix-${scene.name}.png'),
      );
      file.parent.createSync(recursive: true);
      await _capture(tester, file);
      expect(file.existsSync(), isTrue);
    }, skip: !_shotsEnabled);
  }
}

/// 截图目录：相对路径按仓库根解析，方便从任意工作目录运行。
String _shotDirAbs() {
  if (p.isAbsolute(_shotDir)) return _shotDir;
  final cwd = Directory.current.path;
  return p.normalize(p.join(cwd, _shotDir));
}

/// 把整棵树画成 PNG。`captureImage` 会沿祖先找到最近的绘制边界。
Future<void> _capture(WidgetTester tester, File file) async {
  // 测试字体（Ahem）比真实字体宽，输入卡片的工具行在 393 宽会溢出 1px。
  // 这是截图字体的产物，不是界面问题：清掉它，截图照常保存。
  while (tester.takeException() != null) {}
  final element = find.byType(MaterialApp).evaluate().first;
  final image = await tester.runAsync(() => captureImage(element));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}

/// 让真实的文件 I/O 跑完。
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
}

/// 场景外框：把页面限制在给定尺寸内，并在底部画出系统导航条的位置。
///
/// 截图里的深色条不是应用界面，而是测试替身画出来的系统栏，用来看清
/// 内容是否让开了它。
class _SceneFrame extends StatelessWidget {
  const _SceneFrame({
    required this.size,
    required this.navBarHeight,
    required this.child,
  });

  final Size size;
  final double navBarHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Positioned.fill(child: child),
            if (navBarHeight > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: navBarHeight,
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xCC202124),
                    alignment: Alignment.center,
                    child: const Text(
                      'system navigation bar',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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

