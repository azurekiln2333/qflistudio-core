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

/// 外部项目根的文件树：不提供删除，新建文件走协调写入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StudioProfile? previous;
  late Directory sandbox;
  late String vault;
  late ProjectStore store;
  late Project project;
  late EditorController editor;
  final List<String> calls = <String>[];

  setUp(() async {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'external-explorer-test',
      appTitle: 'Explorer',
      templates: [],
      isOffline: true,
      offlineOnly: true,
      productKey: StudioProductCatalog.forgeKey,
      supportsSavedWorkspaces: false,
    );
    ExternalFolderService.resetForTesting();
    ExternalFolderService.debugAssumeSupported = true;
    calls.clear();
    sandbox = Directory.systemTemp.createTempSync('qfli_external_explorer_');
    vault = p.join(sandbox.path, 'Obsidian');
    Directory(vault).createSync();
    File(p.join(vault, 'note.md')).writeAsStringSync('# 笔记');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
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

  Future<void> mount(WidgetTester tester) async {
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('外部根条目不提供删除', (tester) async {
    await mount(tester);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('note.md'));
    await tester.pumpAndSettle();

    expect(find.text('打开'), findsOneWidget);
    expect(find.text('删除'), findsNothing);
    expect(Directory(p.join(vault, 'note.md')).existsSync(), isFalse);
  });
}
