import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/external_folder_service.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';

const MethodChannel _channel = MethodChannel('qflistudio/platform');

/// 外部项目根上的 agent 文件工具：读写与列目录都要走协调通道，
/// 并且列目录要看得见 iCloud 占位文件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late String vault;

  setUp(() {
    ExternalFolderService.resetForTesting();
    ExternalFolderService.debugAssumeSupported = true;
    sandbox = Directory.systemTemp.createTempSync('qfli_external_agent_');
    vault = p.join(sandbox.path, 'Obsidian');
    Directory(vault).createSync();
  });

  tearDown(() {
    ExternalFolderService.resetForTesting();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  void mockChannel(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'resolveFolders') {
            return <Object?>[
              <String, Object?>{
                'id': 'vault',
                'name': 'Obsidian',
                'path': vault,
              },
            ];
          }
          return handler(call);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  }

  test('list 列出 iCloud 占位文件，占位文件大小记 0', () async {
    mockChannel((call) {
      if (call.method == 'folderList') {
        return <Object?>[
          <String, Object?>{
            'name': 'notes',
            'path': p.join(vault, 'notes'),
            'isDirectory': true,
            'size': 0,
            'downloaded': true,
          },
          <String, Object?>{
            'name': 'todo.md',
            'path': p.join(vault, 'todo.md'),
            'isDirectory': false,
            'size': 12,
            'downloaded': false,
          },
        ];
      }
      return null;
    });

    await ExternalFolderService.restore();
    final files = VibeProjectFiles(projectRoot: vault);
    final entries = await files.list();

    expect(entries.map((entry) => entry['path']), <String>['notes', 'todo.md']);
    // 占位文件在盘上不存在，长度按 0 计，不让整次列目录失败。
    expect(entries.last['bytes'], 0);
  });

  test('read 与 write 走协调通道', () async {
    final calls = <String>[];
    mockChannel((call) {
      calls.add(call.method);
      if (call.method == 'coordinatedRead') {
        // 原生送来的是 UTF-8 字节，不是 UTF-16 码元。
        return Uint8List.fromList(utf8.encode('远程正文'));
      }
      return null;
    });

    await ExternalFolderService.restore();
    final files = VibeProjectFiles(projectRoot: vault);

    expect(await files.read('todo.md'), '远程正文');
    await files.write('todo.md', '改过的正文');

    expect(calls, <String>['coordinatedRead', 'coordinatedWrite']);
    // 外部根不再直接落盘。
    expect(File(p.join(vault, 'todo.md')).existsSync(), isFalse);
  });
}
