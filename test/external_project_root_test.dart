import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/external_folder_service.dart';
import 'package:qfli_studio_core/store/project_store.dart';

const MethodChannel _channel = MethodChannel('qflistudio/platform');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late String storage;

  setUp(() {
    ExternalFolderService.resetForTesting();
    sandbox = Directory.systemTemp.createTempSync('qfli_external_project_');
    storage = p.join(sandbox.path, 'storage');
    Directory(storage).createSync(recursive: true);
  });

  tearDown(() {
    ExternalFolderService.resetForTesting();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  ProjectStore newStore() =>
      ProjectStore(storageFile: File(p.join(storage, 'projects.json')));

  test(
    'external project keeps metadata in the registry, not in .qfli',
    () async {
      ExternalFolderService.debugAssumeSupported = true;
      final vault = Directory(p.join(sandbox.path, 'Obsidian'))..createSync();
      File(p.join(vault.path, 'note.md')).writeAsStringSync('# 笔记');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'resolveFolders') {
              return <Object?>[
                <String, Object?>{
                  'id': 'vault',
                  'name': 'Obsidian',
                  'path': vault.path,
                },
              ];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );
      ExternalFolderService.adopt(
        ExternalFolder(id: 'vault', name: 'Obsidian', path: vault.path),
      );

      final store = newStore();
      await store.load();
      final result = await store.addExistingExternal(
        vault.path,
        folderId: 'vault',
      );

      expect(result.error, isNull);
      expect(result.project?.externalFolderId, 'vault');
      expect(result.project?.isExternalFolder, isTrue);
      // R5：外部目录不写 .qfli。
      expect(Directory(p.join(vault.path, '.qfli')).existsSync(), isFalse);

      // 注册表里留下书签 id，重启后按 id 重新解析。
      final registry =
          jsonDecode(File(p.join(storage, 'projects.json')).readAsStringSync())
              as Map<String, dynamic>;
      final projects = registry['projects'] as List;
      expect(projects.single['externalFolderId'], 'vault');
      expect(projects.single['name'], 'Obsidian');
    },
  );

  test(
    'reload rewrites the path when the bookmark resolves elsewhere',
    () async {
      ExternalFolderService.debugAssumeSupported = true;
      final oldVault = Directory(p.join(sandbox.path, 'old'))..createSync();
      final newVault = Directory(p.join(sandbox.path, 'new'))..createSync();
      File(p.join(storage, 'projects.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'deletedCloud': <String>[],
          'projects': <Object?>[
            <String, Object?>{
              'id': 'p1',
              'name': 'Obsidian',
              'path': oldVault.path,
              'createdAt': DateTime(2026, 1, 1).toIso8601String(),
              'lastOpenedAt': DateTime(2026, 1, 1).toIso8601String(),
              'favorite': false,
              'language': 'Markdown',
              'type': '',
              'externalFolderId': 'vault',
            },
          ],
        }),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'resolveFolders') {
              return <Object?>[
                <String, Object?>{
                  'id': 'vault',
                  'name': 'Obsidian',
                  'path': newVault.path,
                  'stale': true,
                },
              ];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );

      final store = newStore();
      await store.load();

      expect(store.projects.single.path, newVault.path);
      final persisted =
          jsonDecode(File(p.join(storage, 'projects.json')).readAsStringSync())
              as Map<String, dynamic>;
      expect((persisted['projects'] as List).single['path'], newVault.path);
    },
  );

  test('deleting an external project keeps the user folder', () async {
    ExternalFolderService.debugAssumeSupported = true;
    final vault = Directory(p.join(sandbox.path, 'Obsidian'))..createSync();
    final note = File(p.join(vault.path, 'note.md'))..writeAsStringSync('# 笔记');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'resolveFolders') {
            return <Object?>[
              <String, Object?>{
                'id': 'vault',
                'name': 'Obsidian',
                'path': vault.path,
              },
            ];
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
    ExternalFolderService.adopt(
      ExternalFolder(id: 'vault', name: 'Obsidian', path: vault.path),
    );

    final store = newStore();
    await store.load();
    final added = await store.addExistingExternal(
      vault.path,
      folderId: 'vault',
    );

    final error = await store.deleteProject(added.project!);

    expect(error, isNull);
    expect(store.projects, isEmpty);
    // R6：目录与文件都还在，书签被释放。
    expect(vault.existsSync(), isTrue);
    expect(note.existsSync(), isTrue);
    expect(calls.map((call) => call.method), contains('releaseFolder'));
  });

  test('projects without a folder id stay on the app-owned path', () async {
    final local = Directory(p.join(sandbox.path, 'local'))..createSync();
    final store = newStore();
    await store.load();

    final result = await store.addExisting(local.path);

    expect(result.error, isNull);
    expect(result.project?.isExternalFolder, isFalse);
    // 普通项目照旧写入 .qfli/project.json。
    expect(Directory(p.join(local.path, '.qfli')).existsSync(), isTrue);
  });
}
