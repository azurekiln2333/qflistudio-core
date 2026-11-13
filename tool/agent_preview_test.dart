// Agent 面板的截图导出工具。
//
// 用法：
//   flutter test --no-pub tool/agent_preview_test.dart
//
// 可选 --dart-define：
//   PREVIEW_OUT=<目录>        默认写到任务目录的 check/screens/pi-d/preview-baseline
//   PREVIEW_SCENES=empty,failed  只导出部分场景
//   PREVIEW_SIZES=390x844,1280x900
//   PREVIEW_THEMES=light,dark
//   PREVIEW_SCALE=2            出图倍率，默认 2
//   UI_FONT_PATH=<含中文的字体> 默认 C:/Windows/Fonts/msyh.ttc
//
// 输入是「场景名 → widget」的映射，加上尺寸列表和主题列表；输出是 PNG。
// 阶段 2 用它给编辑器页出完整截图：新增场景后复用 [runAgentPreview]。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import '../test/support/fake_agent.dart';

/// 一个待导出的场景。[build] 每次调用都要返回一棵新的 widget 树。
typedef AgentPreviewSceneBuilder = Future<Widget> Function();

class AgentPreviewScene {
  const AgentPreviewScene({required this.name, required this.build});

  /// 文件名前缀，只用小写字母、数字和连字符。
  final String name;
  final AgentPreviewSceneBuilder build;
}

/// 一次导出请求。
class AgentPreviewRequest {
  const AgentPreviewRequest({
    required this.outputDir,
    this.sizes = defaultSizes,
    this.themes = defaultThemes,
    this.pixelRatio = 2,
  });

  static const List<Size> defaultSizes = <Size>[
    Size(390, 844),
    Size(600, 1000),
    Size(900, 1000),
    Size(1280, 900),
  ];

  static const List<String> defaultThemes = <String>['light', 'dark'];

  final Directory outputDir;
  final List<Size> sizes;
  final List<String> themes;
  final double pixelRatio;
}

/// 依次渲染每个场景 × 尺寸 × 主题，写出 PNG，返回写出的文件列表。
///
/// 只调用 pump，不调用 pumpAndSettle：加载态里有一直转的进度圈，
/// pumpAndSettle 会一直等到超时。
Future<List<File>> runAgentPreview(
  WidgetTester tester, {
  required List<AgentPreviewScene> scenes,
  required AgentPreviewRequest request,
}) async {
  assert(scenes.isNotEmpty, '至少要有一个场景');
  // 字体和目录都是真实 I/O，必须放在 runAsync 里，否则 fake async 会一直等。
  await tester.runAsync(_loadFonts);
  await tester.runAsync(() => request.outputDir.create(recursive: true));

  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final written = <File>[];
  for (final scene in scenes) {
    for (final size in request.sizes) {
      for (final themeName in request.themes) {
        final theme = themeName == 'dark' ? AppTheme.dark : AppTheme.light;
        final boundaryKey = GlobalKey();
        tester.view.physicalSize = size;
        final body = await tester.runAsync(scene.build);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const <Locale>[Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(body: body ?? const SizedBox.shrink()),
            ),
          ),
        );
        await _settleBootstrap(tester);
        final failure = tester.takeException();
        if (failure != null) {
          throw StateError('场景 ${scene.name} 在 $size / $themeName 渲染失败：$failure');
        }
        final file = File(
          '${request.outputDir.path}'
          '/${scene.name}-${size.width.toInt()}x${size.height.toInt()}'
          '-$themeName.png',
        );
        await _capture(tester, boundaryKey, file, request.pixelRatio);
        written.add(file);
      }
    }
  }
  await tester.pumpWidget(const SizedBox.shrink());
  return written;
}

/// 让面板的异步 bootstrap（模型、技能、会话）跑完。
Future<void> _settleBootstrap(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  File file,
  double pixelRatio,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadFonts() async {
  const fontPath = String.fromEnvironment(
    'UI_FONT_PATH',
    defaultValue: 'C:/Windows/Fonts/msyh.ttc',
  );
  await AppPaths.storageDirectory();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  final file = File(fontPath);
  if (await file.exists()) {
    final bytes = await file.readAsBytes();
    // 测试环境没有系统字体回退：等宽族里的中文会变成方块。
    // 把同一份中文字体也注册到 Roboto 和 monospace，截图才可读。
    for (final family in const <String>['Roboto', 'monospace']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  } else {
    stderr.writeln('警告：没找到中文字体 $fontPath，图里的中文会显示成方块。');
  }
}

// ---- 基线场景：只用基线里已有的 WorkbenchAgentPane 和 FakeAgentRuntime ----

/// 三个基线场景：空状态、有对话、失败待重试。
List<AgentPreviewScene> baselineAgentScenes() => <AgentPreviewScene>[
  AgentPreviewScene(name: 'empty', build: () => _pane()),
  AgentPreviewScene(
    name: 'conversation',
    build: () => _pane(
      sessionId: 'preview-conversation',
      messages: const <AgentMessageView>[
        AgentMessageView(
          id: 'm1',
          role: 'user',
          text: '把 main.dart 的标题改成计算器，再补一个求和函数。',
        ),
        AgentMessageView(
          id: 'm2',
          role: 'assistant',
          text: '先看一下项目结构。',
          aiGenerated: true,
        ),
        AgentMessageView(
          id: 'm3',
          role: 'tool',
          text: '读取 3 个文件',
          toolName: 'read_file',
        ),
        AgentMessageView(
          id: 'm4',
          role: 'assistant',
          text: '已改好标题，并新增 sum(int a, int b)。可以点运行确认。',
          changedPaths: <String>['lib/main.dart'],
          aiGenerated: true,
        ),
      ],
    ),
  ),
  AgentPreviewScene(
    name: 'failed',
    build: () => _pane(
      sessionId: 'preview-failed',
      messages: const <AgentMessageView>[
        AgentMessageView(id: 'm1', role: 'user', text: '帮我把 README 补一节运行说明。'),
        AgentMessageView(
          id: 'm2',
          role: 'assistant',
          text: '正在读取 README.md',
          aiGenerated: true,
        ),
      ],
      lastError: '网络不可用，检查网络后重试',
      state: AgentRunState.failed,
    ),
  ),
];

Future<Widget> _pane({
  String? sessionId,
  List<AgentMessageView> messages = const <AgentMessageView>[],
  String? lastError,
  AgentRunState state = AgentRunState.idle,
}) async {
  final auth = AuthStore();
  await auth.signIn(
    'preview-only',
    const CommunityUser(
      id: '1',
      username: 'qfli_dev',
      nickname: '清风',
      bio: '写一点代码，记录一点想法。',
      avatarColor: '#4D6994',
      points: 1280,
      checkinStreak: 7,
      provider: 'local',
    ),
  );
  final facade = FakeAgentFacade(sessionId: sessionId ?? 'preview-idle');
  if (messages.isNotEmpty) facade.seed(messages);
  facade.lastError = lastError;
  facade.state = state;
  facade.permission = AgentPermissionMode.askEveryWrite;
  final runtime = FakeAgentRuntime(
    sessions: MemoryAgentSessionStore(),
    modelOptions: const <AgentModelOption>[
      AgentModelOption(
        id: 'deepseek-v4.1-flash',
        label: 'DeepSeek V4.1 Flash',
        reasoningEfforts: <String>['low', 'medium', 'high'],
      ),
      AgentModelOption(id: 'deepseek-v4.1-pro', label: 'DeepSeek V4.1 Pro'),
    ],
    skillRefs: const <AgentSkillRef>[
      AgentSkillRef(name: 'dart-format', description: '按项目规则格式化 Dart'),
      AgentSkillRef(name: 'run-tests', description: '跑一遍测试并汇总失败'),
    ],
  );
  runtime.facade = facade;
  return WorkbenchAgentPane(
    project: Project(
      id: 'preview-project',
      name: '计算器练习',
      path: Directory.systemTemp.path,
      createdAt: DateTime(2026, 11, 1),
      lastOpenedAt: DateTime(2026, 11, 14),
      language: 'dart',
    ),
    runtime: runtime,
    auth: auth,
    settings: SettingsStore(),
    sessionId: sessionId,
  );
}

// ---- 命令行入口 ----

const String _defaultOutput =
    'D:/MyNewProjects/qflistudio/.trellis/tasks/11-12-agents-workbench'
    '/check/screens/pi-d/preview-baseline';

List<String> _split(String raw, List<String> fallback) {
  if (raw.trim().isEmpty) return fallback;
  return raw
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

List<Size> _parseSizes(String raw) {
  final parts = _split(raw, const <String>[]);
  if (parts.isEmpty) return AgentPreviewRequest.defaultSizes;
  return parts.map((part) {
    final bits = part.toLowerCase().split('x');
    if (bits.length != 2) throw FormatException('尺寸要写成 390x844：$part');
    return Size(double.parse(bits[0]), double.parse(bits[1]));
  }).toList();
}

void main() {
  const outDir = String.fromEnvironment(
    'PREVIEW_OUT',
    defaultValue: _defaultOutput,
  );
  const scenesArg = String.fromEnvironment('PREVIEW_SCENES');
  const sizesArg = String.fromEnvironment('PREVIEW_SIZES');
  const themesArg = String.fromEnvironment('PREVIEW_THEMES');
  const scaleArg = String.fromEnvironment('PREVIEW_SCALE', defaultValue: '2');

  testWidgets('导出 agent 面板场景截图', (tester) async {
    final wanted = _split(scenesArg, const <String>[]);
    final scenes = baselineAgentScenes()
        .where((scene) => wanted.isEmpty || wanted.contains(scene.name))
        .toList();
    expect(scenes, isNotEmpty, reason: 'PREVIEW_SCENES 没有匹配到场景');
    final written = await runAgentPreview(
      tester,
      scenes: scenes,
      request: AgentPreviewRequest(
        outputDir: Directory(outDir),
        sizes: _parseSizes(sizesArg),
        themes: _split(themesArg, AgentPreviewRequest.defaultThemes),
        pixelRatio: double.parse(scaleArg),
      ),
    );
    // ignore: avoid_print
    print('导出 ${written.length} 张截图到 $outDir');
    for (final file in written) {
      // ignore: avoid_print
      print('  ${file.path} (${file.lengthSync()} 字节)');
    }
  });
}
