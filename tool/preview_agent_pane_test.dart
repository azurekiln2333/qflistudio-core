import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/shell/login_gate.dart';
import 'package:qfli_studio_core/shell/workbench_agent_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import '../test/support/fake_agent.dart';

// 导出 Agent 面板的预览截图（briefs/rework-pi-C.md 的「预览截图」）。
//
//   flutter test --no-pub tool/preview_agent_pane_test.dart
//
// 输出到任务目录的 check/screens/pi-c/。可用 --dart-define=UI_FONT_PATH=...
// 指定含中文字形的本地字体。
const String _outDir =
    'D:/MyNewProjects/qflistudio/.trellis/tasks/11-12-agents-workbench/'
    'check/screens/pi-c';

void main() {
  const fontPath = String.fromEnvironment(
    'UI_FONT_PATH',
    defaultValue: 'C:/Windows/Fonts/msyh.ttc',
  );

  Project project() => Project(
    id: 'p1',
    name: 'Demo',
    path: 'demo',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  Future<AuthStore> loggedIn() async {
    final auth = AuthStore();
    await auth.signIn(
      'preview-only',
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
    return auth;
  }

  Future<void> loadFonts(WidgetTester tester) async {
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      if (await File(fontPath).exists()) {
        final bytes = await File(fontPath).readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
  }

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Size size,
    required Brightness brightness,
    required Widget child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: brightness == Brightness.dark
              ? AppTheme.dark
              : AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // 进度条是不确定动画，t=0 时片段宽度为零、拍不到，推近半秒。
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    // 卸下窗口，取消等待计时器。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  Widget pane({
    required AuthStore auth,
    required FakeAgentRuntime runtime,
    String? sessionId,
  }) => LoginGateScope(
    auth: auth,
    child: WorkbenchAgentPane(
      project: project(),
      runtime: runtime,
      auth: auth,
      settings: SettingsStore(),
      sessionId: sessionId,
    ),
  );

  testWidgets('导出 Agent 面板的预览截图', (tester) async {
    await loadFonts(tester);
    final auth = await loggedIn();

    for (final size in const [Size(390, 780), Size(900, 780)]) {
      final tag = size.width < 500 ? '390' : '900';
      for (final brightness in Brightness.values) {
        final mode = brightness == Brightness.dark ? 'dark' : 'light';

        // 1. 空会话：面板里有输入卡片。
        final emptyStore = MemoryAgentSessionStore();
        await capture(
          tester,
          name: 'empty-$tag-$mode',
          size: size,
          brightness: brightness,
          child: pane(
            auth: auth,
            runtime: FakeAgentRuntime(sessions: emptyStore),
          ),
        );

        // 2. 运行中：进度条、状态行、工具转圈。
        final runningStore = MemoryAgentSessionStore();
        final runningMeta = await runningStore.create('p1', title: '改一下输出');
        final runningRuntime = FakeAgentRuntime(sessions: runningStore);
        final running = FakeAgentFacade(sessionId: runningMeta.id)
          ..seed([
            const AgentMessageView(
              id: 'm0',
              role: 'user',
              text: '把输出改成大写，并补一个测试。',
            ),
            const AgentMessageView(
              id: 'm1',
              role: 'assistant',
              text: '先看一下现在的实现。',
              aiGenerated: true,
            ),
            const AgentMessageView(
              id: 'm2',
              role: 'tool',
              text: '',
              toolName: 'read_file',
              pending: true,
            ),
          ])
          ..activity = '正在读取 lib/main.dart'
          ..state = AgentRunState.running;
        runningRuntime.facades[runningMeta.id] = running;
        await capture(
          tester,
          name: 'running-$tag-$mode',
          size: size,
          brightness: brightness,
          child: pane(
            auth: auth,
            runtime: runningRuntime,
            sessionId: runningMeta.id,
          ),
        );

        // 3. 失败：文案、重试、折叠的详情。
        final failedStore = MemoryAgentSessionStore();
        final failedMeta = await failedStore.create('p1', title: '跑一下测试');
        final failedRuntime = FakeAgentRuntime(sessions: failedStore);
        final failed = FakeAgentFacade(sessionId: failedMeta.id)
          ..seed([
            const AgentMessageView(
              id: 'm0',
              role: 'user',
              text: '跑一下测试。',
            ),
          ])
          ..lastError = 'AI 服务未配置'
          ..lastErrorInfo = const AgentErrorInfo(
            kind: AgentErrorKind.notConfigured,
            statusCode: 503,
            detail: 'upstream: QFLI_AI_BASE_URL is not set',
          )
          ..state = AgentRunState.failed;
        failedRuntime.facades[failedMeta.id] = failed;
        await capture(
          tester,
          name: 'failed-$tag-$mode',
          size: size,
          brightness: brightness,
          child: pane(
            auth: auth,
            runtime: failedRuntime,
            sessionId: failedMeta.id,
          ),
        );

        // 4. 长对话：只建可见条目。
        final longStore = MemoryAgentSessionStore();
        final longMeta = await longStore.create('p1', title: '长对话');
        final longRuntime = FakeAgentRuntime(sessions: longStore);
        final long = FakeAgentFacade(sessionId: longMeta.id)
          ..seed([
            for (var index = 0; index < 60; index++)
              AgentMessageView(
                id: 'm$index',
                role: index.isEven ? 'user' : 'assistant',
                text: index.isEven
                    ? '第 ${index ~/ 2 + 1} 个问题：把第 ${index ~/ 2 + 1} 段逻辑改清楚。'
                    : '好的，我先读一下相关文件，再给出改动。',
                aiGenerated: index.isOdd,
              ),
          ]);
        longRuntime.facades[longMeta.id] = long;
        await capture(
          tester,
          name: 'long-$tag-$mode',
          size: size,
          brightness: brightness,
          child: pane(
            auth: auth,
            runtime: longRuntime,
            sessionId: longMeta.id,
          ),
        );
      }
    }
  });
}
