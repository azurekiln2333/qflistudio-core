@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
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
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

/// 场景截图：把带快捷栏的编辑器页按真实尺寸画出来，写成 PNG。
///
/// 只在设置了 `PI3_SHOT_DIR` 时运行，避免常规 `flutter test` 往仓库外写文件：
///
/// ```
/// PI3_SHOT_DIR=../reports/shots/pi3 PI3_SHOT_PREFIX=after \
///   flutter test test/editor_quick_bar_shots_test.dart
/// ```
final String _shotDir = Platform.environment['PI3_SHOT_DIR'] ?? '';
final String _shotPrefix = Platform.environment['PI3_SHOT_PREFIX'] ?? 'shot';
final bool _shotsEnabled = _shotDir.trim().isNotEmpty;

typedef _Scene = ({String name, Size size, Brightness brightness, bool agent});

const List<_Scene> _scenes = [
  (
    name: 'phone-light-editor',
    size: Size(393, 852),
    brightness: Brightness.light,
    agent: false,
  ),
  (
    name: 'phone-dark-editor',
    size: Size(393, 852),
    brightness: Brightness.dark,
    agent: false,
  ),
  (
    name: 'phone-light-agent',
    size: Size(393, 852),
    brightness: Brightness.light,
    agent: true,
  ),
  (
    name: 'phone-dark-agent',
    size: Size(393, 852),
    brightness: Brightness.dark,
    agent: true,
  ),
  (
    name: 'tablet-light-editor',
    size: Size(1280, 800),
    brightness: Brightness.light,
    agent: false,
  ),
  (
    name: 'tablet-dark-editor',
    size: Size(1280, 800),
    brightness: Brightness.dark,
    agent: false,
  ),
  (
    name: 'tablet-light-agent',
    size: Size(1280, 800),
    brightness: Brightness.light,
    agent: true,
  ),
  (
    name: 'tablet-dark-agent',
    size: Size(1280, 800),
    brightness: Brightness.dark,
    agent: true,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_shotsEnabled) await _loadFonts();
  });

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
      id: 'editor-quick-bar-shots',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_quick_bar_shots_');
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

  /// 把带快捷栏的编辑器页挂起来：真实尺寸、真实主题。
  Future<void> mountScene(
    WidgetTester tester,
    Size size,
    Brightness brightness,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    final running = await sessions.create(project.id, title: '补齐快捷栏动作');
    runtime.liveStatuses[running.id] = AgentLiveStatus.running;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
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
    );
    await _pumpFrames(tester);
  }

  for (final scene in _scenes) {
    testWidgets('场景 ${scene.name}', (tester) async {
      await mountScene(tester, scene.size, scene.brightness);

      if (scene.agent) {
        // 宽屏先展开右栏；窄屏直接切分段。
        final expand = find.byKey(const ValueKey('editor-agent-expand'));
        if (expand.evaluate().isNotEmpty) {
          await tester.tap(expand);
          await _pumpFrames(tester);
        } else {
          await tester.tap(find.byTooltip('打开 Agent 面板'));
          await _pumpFrames(tester);
        }
      }

      final file = File(
        p.join(_shotDirAbs(), '$_shotPrefix-${scene.name}.png'),
      );
      file.parent.createSync(recursive: true);
      await _capture(tester, file);
      expect(file.existsSync(), isTrue);
      // 输入卡片在 393 宽下有 1 px 的已知溢出，与快捷栏无关。
      tester.takeException();
    }, skip: !_shotsEnabled);
  }

  // 按住一个动作时的涟漪：浅色与深色各一张，25 dp 的槽位里也要看得见。
  for (final brightness in const [Brightness.light, Brightness.dark]) {
    testWidgets('按压涟漪 ${brightness.name}', (tester) async {
      await mountScene(tester, const Size(393, 852), brightness);
      final slot = find.byKey(const ValueKey('quick-save'));
      final gesture = await tester.startGesture(tester.getCenter(slot));
      // 分帧推进：涟漪的淡入要真的跑完，截到的是可见的一帧。
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final file = File(
        p.join(_shotDirAbs(), '$_shotPrefix-press-${brightness.name}.png'),
      );
      file.parent.createSync(recursive: true);
      await _capture(tester, file);
      expect(file.existsSync(), isTrue);

      await gesture.up();
      await tester.pump();
      tester.takeException();
    }, skip: !_shotsEnabled);
  }
}

/// 加载真实字体，截图里的汉字与图标才不是方块。
///
/// 测试环境默认只有 Ahem；截图要给人看，所以从 SDK 与系统字体目录取。
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('MaterialIcons', _materialIconsPath());
  // 默认字体族在测试里是 Roboto；用系统里的黑体顶上去。
  const cjk = 'C:/Windows/Fonts/simhei.ttf';
  await load('Roboto', cjk);
  await load('.SF UI Text', cjk);
}

/// 工具链里的 MaterialIcons 字体。
///
/// 测试进程是 `flutter_tester`，从它的路径向上找带 `cache/artifacts` 的目录。
String _materialIconsPath() {
  const relative = 'cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  Directory? candidate = File(Platform.resolvedExecutable).parent;
  while (candidate != null) {
    final file = File(p.join(candidate.path, relative));
    if (file.existsSync()) return file.path;
    if (candidate.parent.path == candidate.path) break;
    candidate = candidate.parent;
  }
  return '';
}

/// 截图目录：相对路径按仓库根解析。
String _shotDirAbs() {
  if (p.isAbsolute(_shotDir)) return _shotDir;
  return p.normalize(p.join(Directory.current.path, _shotDir));
}

/// 把整棵树画成 PNG。
Future<void> _capture(WidgetTester tester, File file) async {
  final element = find.byType(MaterialApp).evaluate().first;
  final image = await tester.runAsync(() => captureImage(element));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
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
