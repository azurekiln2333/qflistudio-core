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
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';
import 'package:re_editor/re_editor.dart';

import 'support/fake_agent.dart';

/// Agent 写盘后编辑器必须看得见。
///
/// 覆盖 brief 第 1 条：干净的标签页静默重读；有未保存修改的标签页先问用户；
/// 新建的文件进文件树。
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
      id: 'editor-agent-file-sync-test',
      appTitle: 'QFLIStudioN',
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
      isOffline: false,
    );
    directory = await Directory.systemTemp.createTemp('qfli_agent_sync_');
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
    Size size = const Size(1280, 900),
    String? initialOpenPath,
    bool openSidebar = false,
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
    if (openSidebar) {
      final open = find.byTooltip('打开文件树');
      if (open.evaluate().isNotEmpty) {
        await tester.tap(open);
        await pumpFrames(tester);
      }
    }
  }

  /// 代码编辑器里现在显示的正文。
  String editorText(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text;

  /// 让缓冲变脏：直接改编辑器控制器的正文。
  Future<void> typeIntoEditor(WidgetTester tester, String text) async {
    tester.widget<CodeEditor>(find.byType(CodeEditor).first).controller!.text =
        text;
    await tester.pump();
    await pumpFrames(tester, 5);
  }

  testWidgets('agent 写入后，干净的标签页从磁盘重新读取', (tester) async {
    final file = File(p.join(directory.path, 'main.py'))
      ..writeAsStringSync('print(1)\n', flush: true);
    await mount(tester, initialOpenPath: file.path);
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(editorText(tester), 'print(1)\n');

    // agent 在磁盘上改写同一个文件。
    file.writeAsStringSync('print(2)\n', flush: true);
    runtime.emitFileChange(directory.path, 'main.py');
    await pumpFrames(tester);

    expect(editorText(tester), 'print(2)\n');
    expect(find.byKey(const ValueKey('editor-disk-conflict')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有未保存修改时先问用户：保留我的修改', (tester) async {
    final file = File(p.join(directory.path, 'main.py'))
      ..writeAsStringSync('print(1)\n', flush: true);
    await mount(tester, initialOpenPath: file.path);
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );

    await typeIntoEditor(tester, 'print("mine")\n');
    file.writeAsStringSync('print("agent")\n', flush: true);
    runtime.emitFileChange(directory.path, 'main.py');
    await pumpFrames(tester);

    expect(
      find.byKey(const ValueKey('editor-disk-conflict')),
      findsOneWidget,
      reason: '有未保存修改时必须问，不能静默覆盖',
    );
    await tester.tap(find.byKey(const ValueKey('editor-disk-keep-mine')));
    await pumpFrames(tester);

    expect(editorText(tester), 'print("mine")\n', reason: '用户的选择优先');
    expect(find.byKey(const ValueKey('editor-disk-conflict')), findsNothing);
  });

  testWidgets('有未保存修改时先问用户：载入 Agent 的版本', (tester) async {
    final file = File(p.join(directory.path, 'main.py'))
      ..writeAsStringSync('print(1)\n', flush: true);
    await mount(tester, initialOpenPath: file.path);
    await pumpUntil(
      tester,
      () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );

    await typeIntoEditor(tester, 'print("mine")\n');
    file.writeAsStringSync('print("agent")\n', flush: true);
    runtime.emitFileChange(directory.path, 'main.py');
    await pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('editor-disk-take-agent')));
    await pumpFrames(tester);

    expect(editorText(tester), 'print("agent")\n');
  });

  testWidgets('agent 新建的文件出现在文件树里', (tester) async {
    Directory(p.join(directory.path, 'src')).createSync(recursive: true);
    await mount(tester, openSidebar: true);
    expect(find.byType(FileExplorer), findsOneWidget);
    expect(find.text('generated.dart'), findsNothing);

    File(
      p.join(directory.path, 'generated.dart'),
    ).writeAsStringSync('void main() {}\n', flush: true);
    runtime.emitFileChange(directory.path, 'generated.dart');
    await pumpFrames(tester);

    expect(find.text('generated.dart'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

/// 等条件成立，期间让真实 I/O 继续。
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