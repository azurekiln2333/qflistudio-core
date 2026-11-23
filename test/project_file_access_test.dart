import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/external_folder_service.dart';
import 'package:qfli_studio_core/services/project_file_access.dart';

const MethodChannel _channel = MethodChannel('qflistudio/platform');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUp(() {
    ExternalFolderService.resetForTesting();
    sandbox = Directory.systemTemp.createTempSync('qfli_file_access_');
  });

  tearDown(() {
    ExternalFolderService.resetForTesting();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('internal paths stay on dart:io', () async {
    final file = File(p.join(sandbox.path, 'note.md'));
    await ProjectFileAccess.writeString(file.path, '本地内容');
    expect(file.readAsStringSync(), '本地内容');
    expect(await ProjectFileAccess.readString(file.path), '本地内容');
    expect(ProjectFileAccess.isExternal(file.path), isFalse);
  });

  test('internal delete still works', () async {
    final file = File(p.join(sandbox.path, 'gone.md'));
    file.writeAsStringSync('x');
    await ProjectFileAccess.delete(file.path);
    expect(file.existsSync(), isFalse);
  });

  test('external paths route through the coordinated channel', () async {
    ExternalFolderService.debugAssumeSupported = true;
    const root = '/private/var/mobile/Obsidian';
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'resolveFolders':
              return <Object?>[
                <String, Object?>{
                  'id': 'vault',
                  'name': 'Obsidian',
                  'path': root,
                },
              ];
            case 'coordinatedRead':
              return Uint8List.fromList('远程内容'.codeUnits);
            case 'coordinatedWrite':
              return null;
            case 'folderList':
              return <Object?>[
                <String, Object?>{
                  'name': 'todo.md',
                  'path': '$root/todo.md',
                  'isDirectory': false,
                  'size': 4,
                  'downloaded': false,
                },
              ];
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    await ExternalFolderService.restore();
    final target = '$root/Notes/a.md';

    expect(ProjectFileAccess.isExternal(target), isTrue);
    expect(await ProjectFileAccess.readString(target), isNotNull);

    await ProjectFileAccess.writeString(target, 'hello');

    final entries = await ProjectFileAccess.listEntries(root);
    expect(entries.single.downloaded, isFalse);

    expect(
      calls.map((call) => call.method),
      containsAll(<String>[
        'resolveFolders',
        'coordinatedRead',
        'coordinatedWrite',
        'folderList',
      ]),
    );
    // 外部根不再直接碰 dart:io 的写盘。
    expect(File(target).existsSync(), isFalse);
  });

  test('external delete is refused instead of touching the vault', () async {
    ExternalFolderService.debugAssumeSupported = true;
    const root = '/private/var/mobile/Obsidian';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'resolveFolders') {
            return <Object?>[
              <String, Object?>{
                'id': 'vault',
                'name': 'Obsidian',
                'path': root,
              },
            ];
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    await ExternalFolderService.restore();

    await expectLater(
      ProjectFileAccess.delete('$root/todo.md'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
