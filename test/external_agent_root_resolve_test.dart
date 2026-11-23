@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/external_folder_service.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';

const MethodChannel _channel = MethodChannel('qflistudio/platform');

/// 外部根就是这次会话的工作根：工具给的是相对路径，解析后必须落在外部根里。
///
/// 以前 `resolve` 只认 [VibeProjectFiles.projectRoot]，外部项目上的
/// `src/main.dart` 被拼成项目内的路径，读取走普通文件分支，
/// 协调读取一次也不发生。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late String vault;

  setUp(() {
    ExternalFolderService.resetForTesting();
    ExternalFolderService.debugAssumeSupported = true;
    sandbox = Directory.systemTemp.createTempSync('qfli_external_resolve_');
    vault = p.join(sandbox.path, 'Obsidian');
    Directory(p.join(vault, 'src')).createSync(recursive: true);
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

  test('相对路径拼在外部根下，不走项目根', () async {
    mockChannel((_) => null);
    await ExternalFolderService.restore();
    final files = VibeProjectFiles(projectRoot: vault);

    final resolved = files.resolve('src/main.dart');

    expect(resolved, p.join(vault, 'src', 'main.dart'));
    expect(ExternalFolderService.isExternal(resolved), isTrue);
  });

  test('外部根上的读取走协调读取', () async {
    final calls = <String>[];
    mockChannel((call) {
      calls.add(call.method);
      if (call.method == 'coordinatedRead') {
        return Uint8List.fromList(utf8.encode('占位文件正文'));
      }
      return null;
    });
    await ExternalFolderService.restore();
    final files = VibeProjectFiles(projectRoot: vault);

    expect(await files.read('src/main.dart'), '占位文件正文');
    expect(calls, <String>['coordinatedRead']);
  });

  test('普通本地项目仍按项目根拼路径', () async {
    final local = Directory(p.join(sandbox.path, 'plain'))..createSync();
    File(p.join(local.path, 'a.txt')).writeAsStringSync('本地');

    final files = VibeProjectFiles(projectRoot: local.path);

    expect(files.resolve('a.txt'), p.join(local.path, 'a.txt'));
    expect(await files.read('a.txt'), '本地');
  });

  test('外部根之外仍拒绝', () async {
    mockChannel((_) => null);
    await ExternalFolderService.restore();
    final other = p.join(sandbox.path, 'Other');
    final files = VibeProjectFiles(projectRoot: other);

    // 另一个目录不是外部根，绝对路径照旧拒收。
    expect(
      () => files.resolve(p.join(vault, 'src', 'main.dart')),
      throwsA(isA<VibeToolException>()),
    );
  });
}
