@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/external_folder_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

const MethodChannel _channel = MethodChannel('qflistudio/platform');

/// 外部根的列表读失败时，文件树不能把失败吞成空目录。
///
/// 契约：同一棵树内刷新失败要保留已显示的节点，并把访问错误报一次；
/// 之后恢复成功再失败，要能重新报，不能永久哑掉。
///
/// 刷新走 `refreshSignal`：它让同一个 State 重读目录，
/// 不会重建组件、也不会清掉 `_children` 缓存。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StudioProfile? previous;
  late Directory sandbox;
  late String vault;
  late ProjectStore store;
  late Project project;
  late EditorController editor;

  /// 为 true 时原生 `folderList` 报 PlatformException（权限被收回）。
  var listingFails = false;

  setUp(() async {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'external-explorer-failure-test',
      appTitle: 'Explorer',
      templates: [],
      isOffline: true,
      offlineOnly: true,
      productKey: StudioProductCatalog.forgeKey,
      supportsSavedWorkspaces: false,
    );
    ExternalFolderService.resetForTesting();
    ExternalFolderService.debugAssumeSupported = true;
    listingFails = false;
    sandbox = Directory.systemTemp.createTempSync('qfli_external_fail_');
    vault = p.join(sandbox.path, 'Obsidian');
    Directory(vault).createSync();
    File(p.join(vault, 'note.md')).writeAsStringSync('# 笔记');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'resolveFolders':
              return <Object?>[
                <String, Object?>{
                  'id': 'vault',
                  'name': 'Obsidian',
                  'path': vault,
                },
              ];
            case 'folderList':
              if (listingFails) {
                throw PlatformException(
                  code: 'NO_SCOPE',
                  message: 'The folder is outside the granted roots.',
                );
              }
              return <Object?>[
                <String, Object?>{
                  'name': 'note.md',
                  'path': p.join(vault, 'note.md'),
                  'isDirectory': false,
                  'size': 6,
                  'downloaded': true,
                },
              ];
          }
          return null;
        });
    store = ProjectStore(
      storageFile: File(p.join(sandbox.path, 'registry.json')),
    );
    await store.load();
    await store.addExistingExternal(vault, folderId: 'vault');
    project = store.projects.single;
    editor = EditorController(project: project);
  });

  tearDown(() {
    editor.dispose();
    ExternalFolderService.resetForTesting();
    StudioProfile.current = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  /// 挂载一次文件树，返回驱动同一 State 刷新的信号。
  ///
  /// 全程只用这一个 State：换 key 会连 `_children` 一起丢掉，
  /// 那样「失败时保留旧节点」就无从验证。
  Future<ValueNotifier<int>> mount(WidgetTester tester) async {
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 700,
              child: FileExplorer(
                project: project,
                editor: editor,
                store: store,
                settings: SettingsStore(),
                refreshSignal: signal,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return signal;
  }

  Future<void> refresh(WidgetTester tester, ValueNotifier<int> signal) async {
    signal.value = signal.value + 1;
    await tester.pumpAndSettle();
  }

  testWidgets('注册外部根后条目出现在文件树', (tester) async {
    await mount(tester);

    // 回归：`addExistingExternal` 必须让 `isExternal` 成立，
    // 否则这里走普通目录分支，原生列表永远不被调用。
    expect(ExternalFolderService.isExternal(vault), isTrue);
    expect(find.text('note.md'), findsOneWidget);
  });

  testWidgets('同一棵树刷新失败保留节点并报错，恢复后再次失败能再报', (tester) async {
    final signal = await mount(tester);
    expect(find.text('note.md'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // 1. 同一 State 刷新，原生报错：已显示的节点必须留着。
    listingFails = true;
    await refresh(tester, signal);
    expect(find.text('note.md'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);

    // 2. 再次失败不能重复弹提示（额度已用掉）。
    await refresh(tester, signal);
    expect(find.text('note.md'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);

    // 等当前提示正常结束。重复失败不能排队再弹一条。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // 3. 原生恢复：读成功并清掉提示额度。
    listingFails = false;
    await refresh(tester, signal);
    expect(find.text('note.md'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // 4. 恢复之后再失败，必须能重新报，说明额度真的重置了。
    listingFails = true;
    await refresh(tester, signal);
    expect(find.text('note.md'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
