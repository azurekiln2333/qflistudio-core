import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_backup_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  late Directory root;
  late Directory sourceRoot;

  StudioProfile? originalProfile;

  setUp(() async {
    originalProfile = StudioProfile.current;
    root = await Directory.systemTemp.createTemp('qfli_backup_root');
    sourceRoot = await Directory.systemTemp.createTemp('qfli_backup_source');
    AppBackupService.rootOverride = root.path;
  });

  tearDown(() async {
    StudioProfile.current = originalProfile;
    AppBackupService.rootOverride = null;
    for (final dir in [root, sourceRoot]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  Future<void> seed(Directory base) async {
    await File(
      p.join(base.path, 'settings.json'),
    ).writeAsString(jsonEncode({'version': 1, 'themeMode': 'dark'}));
    await File(p.join(base.path, 'projects.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'projects': [
          {'id': 'a', 'name': 'Local', 'path': '${base.path}/projects/demo'},
          {'id': 'b', 'name': 'External', 'path': '/elsewhere/keepme'},
        ],
      }),
    );
    await File(
      p.join(base.path, 'projects', 'demo', 'src', 'Main.java'),
    ).create(recursive: true);
    await File(
      p.join(base.path, 'projects', 'demo', 'src', 'Main.java'),
    ).writeAsString('class Main {}');
    // Binary asset that must survive byte-for-byte.
    await File(
      p.join(base.path, 'projects', 'demo', 'assets', 'icon.bin'),
    ).create(recursive: true);
    await File(
      p.join(base.path, 'projects', 'demo', 'assets', 'icon.bin'),
    ).writeAsBytes(const [0, 1, 2, 255, 254, 128]);
    // Empty directory must be preserved.
    await Directory(
      p.join(base.path, 'projects', 'demo', 'empty'),
    ).create(recursive: true);
    // Nested durable root.
    await File(
      p.join(base.path, 'files_backup', 'demo', 'Main-1.java'),
    ).create(recursive: true);
    await File(
      p.join(base.path, 'files_backup', 'demo', 'Main-1.java'),
    ).writeAsString('class Main {} // old');
    // Interrupted staging/probe leftovers must never be captured.
    await File(p.join(base.path, '.qfli_write_probe1')).writeAsString('x');
    await Directory(p.join(base.path, '.qfli-app-restore')).create();
  }

  test(
    'export captures metadata and full durable tree, excluding staging',
    () async {
      await seed(root);
      final bundle = await AppBackupService.exportAll();

      expect(bundle.info.formatVersion, AppBackupService.currentFormatVersion);
      expect(bundle.info.productKey, StudioProductCatalog.qfliStudioKey);
      expect(bundle.info.recordedRootPath, isNotNull);

      final info = AppBackupService.readInfo(bundle.bytes);
      expect(info.fileCount, bundle.info.fileCount);

      final names = _entryNames(bundle.bytes);
      expect(names, contains('app_info.json'));
      expect(names, contains('data/settings.json'));
      expect(names, contains('data/projects/demo/assets/icon.bin'));
      expect(names, contains('data/files_backup/demo/Main-1.java'));
      expect(names.any((n) => n.startsWith('data/.qfli-app-restore')), isFalse);
      expect(names.any((n) => n.contains('.qfli_write_probe')), isFalse);
    },
  );

  test('a root directory marker entry restores as a zero-file root', () async {
    // 导出的归档包含 `data/` 根目录标记；导入必须接受它并成功完成零文件恢复。
    final bytes = _zipWithRaw([
      ('app_info.json', Uint8List.fromList(utf8.encode(_infoJson()))),
      ('data/', Uint8List(0)),
    ]);
    final prepared = await AppBackupService.prepareImport(bytes);
    expect(prepared.fileCount, 0);
    final result = await AppBackupService.applyPendingRestore();
    expect(result, isNotNull);
  });

  test('binary content round-trips byte-for-byte', () async {
    await seed(root);
    final bundle = await AppBackupService.exportAll();

    final target = await Directory(
      p.join(sourceRoot.path, 'restored'),
    ).create(recursive: true);
    final previous = AppBackupService.rootOverride;
    AppBackupService.rootOverride = target.path;
    try {
      await AppBackupService.prepareImport(bundle.bytes);
      final result = await AppBackupService.applyPendingRestore();
      expect(result, isNotNull);
      expect(result!.restoredFiles, greaterThan(0));
    } finally {
      AppBackupService.rootOverride = previous;
    }

    expect(
      await File(
        p.join(target.path, 'projects', 'demo', 'assets', 'icon.bin'),
      ).readAsBytes(),
      const [0, 1, 2, 255, 254, 128],
    );
    expect(
      await File(p.join(target.path, 'settings.json')).readAsString(),
      jsonEncode({'version': 1, 'themeMode': 'dark'}),
    );
  });

  test(
    'restore preserves empty directories and rebases registry paths',
    () async {
      await seed(root);
      final bundle = await AppBackupService.exportAll();

      final target = await Directory(
        p.join(sourceRoot.path, 'restored'),
      ).create(recursive: true);
      final previous = AppBackupService.rootOverride;
      AppBackupService.rootOverride = target.path;
      try {
        await AppBackupService.importAll(bundle.bytes);
      } finally {
        AppBackupService.rootOverride = previous;
      }

      expect(
        await Directory(
          p.join(target.path, 'projects', 'demo', 'empty'),
        ).exists(),
        isTrue,
      );

      final registry =
          jsonDecode(
                await File(p.join(target.path, 'projects.json')).readAsString(),
              )
              as Map<String, dynamic>;
      final projects = (registry['projects'] as List).cast<Map>();
      final local = projects.firstWhere((item) => item['id'] == 'a');
      final external = projects.firstWhere((item) => item['id'] == 'b');
      // Path that lived under the archived root is rebased to the new root.
      expect(
        local['path'],
        p.normalize(p.join(target.path, 'projects', 'demo')),
      );
      // External reference is left untouched.
      expect(external['path'], '/elsewhere/keepme');
    },
  );

  test('identity compatibility allows same product cross-platform', () {
    final mine = AppBackupInfo(
      formatVersion: 1,
      productKey: 'jvmx',
      appTitle: 'QFLIJVMX',
      profileId: 'java',
      runtimeKind: 'ohos',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      fileCount: 0,
    );
    final sameProductOtherOs = AppBackupInfo(
      formatVersion: 1,
      productKey: 'jvmx',
      appTitle: 'QFLIJVMX',
      profileId: 'java',
      runtimeKind: 'android',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      fileCount: 0,
    );
    final otherProduct = AppBackupInfo(
      formatVersion: 1,
      productKey: 'pyflow',
      appTitle: 'QFLIPyFlow',
      profileId: 'python',
      runtimeKind: 'ohos',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      fileCount: 0,
    );
    final generic = AppBackupInfo(
      formatVersion: 1,
      productKey: 'qflistudio',
      appTitle: 'QFLIStudio+',
      profileId: '',
      runtimeKind: 'unavailable',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      fileCount: 0,
    );
    expect(
      () =>
          AppBackupService.assertCompatible(sameProductOtherOs, current: mine),
      returnsNormally,
    );
    expect(
      () => AppBackupService.assertCompatible(otherProduct, current: mine),
      throwsA(isA<AppBackupException>()),
    );
    expect(
      () => AppBackupService.assertCompatible(generic, current: mine),
      returnsNormally,
    );
  });

  test('rejects a newer format version', () {
    final future = AppBackupInfo(
      formatVersion: 99,
      productKey: 'qflistudio',
      appTitle: 'x',
      profileId: '',
      runtimeKind: 'unavailable',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      fileCount: 0,
    );
    expect(
      () => AppBackupService.assertCompatible(future),
      throwsA(isA<AppBackupException>()),
    );
  });

  group('malicious and corrupt archives', () {
    test('rejects traversal, absolute and duplicate paths', () async {
      final bytes = _zipWith({
        'app_info.json': _infoJson(),
        'data/../escape.txt': 'x',
      });
      await expectLater(
        AppBackupService.prepareImport(bytes),
        throwsA(isA<AppBackupException>()),
      );

      final absolute = _zipWith({
        'app_info.json': _infoJson(),
        'data//etc/passwd': 'x',
      });
      await expectLater(
        AppBackupService.prepareImport(absolute),
        throwsA(isA<AppBackupException>()),
      );

      // dot 组件不得绕过校验（否则 data/link/./child 可绕过链接祖先检查）。
      final dot = _zipWith({
        'app_info.json': _infoJson(),
        'data/./evil.txt': 'x',
      });
      await expectLater(
        AppBackupService.prepareImport(dot),
        throwsA(isA<AppBackupException>()),
      );

      // 盘符 / 冒号路径在所有宿主上均被拒绝。
      final drive = _zipWith({
        'app_info.json': _infoJson(),
        'data/C:/evil.txt': 'x',
      });
      await expectLater(
        AppBackupService.prepareImport(drive),
        throwsA(isA<AppBackupException>()),
      );

      final duplicate = _zipWithRaw([
        ('app_info.json', Uint8List.fromList(utf8.encode(_infoJson()))),
        // 两个名字反斜杠规范化后相同：包不会合并它们，原始重复检测必须拒绝。
        ('data/a.txt', Uint8List.fromList(utf8.encode('1'))),
        ('data\\a.txt', Uint8List.fromList(utf8.encode('2'))),
      ]);
      await expectLater(
        AppBackupService.prepareImport(duplicate),
        throwsA(
          isA<AppBackupException>().having(
            (e) => e.message,
            'message',
            contains('重复路径'),
          ),
        ),
      );
    });

    test('rejects unknown root entries and missing info', () async {
      final extra = _zipWith({'app_info.json': _infoJson(), 'sneaky.txt': 'x'});
      await expectLater(
        AppBackupService.prepareImport(extra),
        throwsA(isA<AppBackupException>()),
      );

      final noInfo = _zipWith({'data/a.txt': 'x'});
      expect(
        () => AppBackupService.readInfo(noInfo),
        throwsA(isA<AppBackupException>()),
      );
    });

    test('rejects non-zip bytes and empty input', () {
      expect(
        () =>
            AppBackupService.readInfo(Uint8List.fromList(utf8.encode('nope'))),
        throwsA(isA<AppBackupException>()),
      );
      expect(
        () => AppBackupService.readInfo(Uint8List(0)),
        throwsA(isA<AppBackupException>()),
      );
    });
  });

  test('prepare does not touch live data until applied', () async {
    await seed(root);
    final bundle = await AppBackupService.exportAll();

    final liveSettings = await File(
      p.join(root.path, 'settings.json'),
    ).readAsString();

    await AppBackupService.prepareImport(bundle.bytes);

    // Live data untouched, pending flag set.
    expect(
      await File(p.join(root.path, 'settings.json')).readAsString(),
      liveSettings,
    );
    expect(await AppBackupService.hasPendingRestore(), isTrue);
    expect(await AppBackupService.pendingRestoreInfo(), isNotNull);

    // A second prepare while pending is refused unless explicitly replacing.
    await expectLater(
      AppBackupService.prepareImport(bundle.bytes),
      throwsA(isA<AppBackupException>()),
    );
  });

  test('apply swaps staged data in and clears staging', () async {
    await seed(root);
    final bundle = await AppBackupService.exportAll();

    // Mutate live data to prove the restore actually replaces it.
    await File(
      p.join(root.path, 'settings.json'),
    ).writeAsString(jsonEncode({'version': 1, 'themeMode': 'light'}));

    await AppBackupService.prepareImport(bundle.bytes);
    final result = await AppBackupService.applyPendingRestore();
    expect(result, isNotNull);

    expect(
      jsonDecode(await File(p.join(root.path, 'settings.json')).readAsString()),
      {'version': 1, 'themeMode': 'dark'},
    );
    expect(await AppBackupService.hasPendingRestore(), isFalse);
    expect(
      await Directory(
        p.join(root.path, AppBackupService.stagingDirName),
      ).exists(),
      isFalse,
    );
  });

  test('cancelPendingRestore discards staged data without applying', () async {
    await seed(root);
    final bundle = await AppBackupService.exportAll();
    await AppBackupService.prepareImport(bundle.bytes);
    await AppBackupService.cancelPendingRestore();
    expect(await AppBackupService.hasPendingRestore(), isFalse);
    expect(await AppBackupService.applyPendingRestore(), isNull);
  });

  test('applyPendingRestore returns null when nothing is pending', () async {
    await seed(root);
    expect(await AppBackupService.applyPendingRestore(), isNull);
  });

  test('runtime tree is included in the archive and restored', () async {
    await seed(root);
    // JDK 运行树含可执行文件；用户要求“整个私有数据目录”，必须完整纳入。
    final usr = Directory(p.join(root.path, 'usr', 'lib'));
    await usr.create(recursive: true);
    final tool = File(p.join(usr.path, 'tool'));
    await tool.writeAsString('binary');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', tool.path]);
    }

    final bundle = await AppBackupService.exportAll();
    final names = _entryNames(bundle.bytes);
    expect(names, contains('data/usr/lib/tool'));

    final target = await Directory(
      p.join(sourceRoot.path, 'restored'),
    ).create(recursive: true);
    final previous = AppBackupService.rootOverride;
    AppBackupService.rootOverride = target.path;
    try {
      await AppBackupService.importAll(bundle.bytes);
    } finally {
      AppBackupService.rootOverride = previous;
    }
    expect(
      await File(p.join(target.path, 'usr', 'lib', 'tool')).readAsString(),
      'binary',
    );
  });

  test('a project directory literally named usr is never dropped', () async {
    await seed(root);
    final fake = File(p.join(root.path, 'projects', 'demo', 'usr', 'note.txt'));
    await fake.create(recursive: true);
    await fake.writeAsString('user data');

    final bundle = await AppBackupService.exportAll();
    expect(
      _entryNames(bundle.bytes),
      contains('data/projects/demo/usr/note.txt'),
    );
  });

  test('export and restore cover a second private root', () async {
    final extra = await Directory.systemTemp.createTemp('qfli_backup_docs');
    addTearDown(() async {
      if (await extra.exists()) await extra.delete(recursive: true);
    });
    await File(p.join(extra.path, 'note.txt')).writeAsString('docs');
    AppBackupService.rootsResolverOverride = (storagePath) async => {
      'storage': p.normalize(p.absolute(storagePath)),
      'documents': p.normalize(p.absolute(extra.path)),
    };
    addTearDown(() => AppBackupService.rootsResolverOverride = null);

    await seed(root);
    final bundle = await AppBackupService.exportAll();
    expect(
      bundle.info.recordedRoots.keys,
      containsAll(['storage', 'documents']),
    );
    expect(_entryNames(bundle.bytes), contains('private_documents/note.txt'));

    final newStorage = await Directory.systemTemp.createTemp('qfli_restore_s');
    final newDocs = await Directory.systemTemp.createTemp('qfli_restore_d');
    addTearDown(() async {
      for (final dir in [newStorage, newDocs]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
    final previousOverride = AppBackupService.rootOverride;
    AppBackupService.rootOverride = newStorage.path;
    AppBackupService.rootsResolverOverride = (storagePath) async => {
      'storage': p.normalize(p.absolute(newStorage.path)),
      'documents': p.normalize(p.absolute(newDocs.path)),
    };
    try {
      await AppBackupService.importAll(bundle.bytes);
    } finally {
      AppBackupService.rootOverride = previousOverride;
      AppBackupService.rootsResolverOverride = null;
    }
    expect(
      await File(p.join(newStorage.path, 'settings.json')).readAsString(),
      jsonEncode({'version': 1, 'themeMode': 'dark'}),
    );
    expect(await File(p.join(newDocs.path, 'note.txt')).readAsString(), 'docs');
  });

  test('rebase rewrites file history metadata originalPath', () async {
    await seed(root);
    final metadataDir = Directory(p.join(root.path, 'files_backup', 'demo'));
    await metadataDir.create(recursive: true);
    final original = p.normalize(
      p.join(root.path, 'projects', 'demo', 'src', 'Main.java'),
    );
    await File(
      p.join(metadataDir.path, 'Main-1.java.metadata.json'),
    ).writeAsString(
      jsonEncode({
        'originalPath': original,
        'projectName': 'demo',
        'name': 'Main.java',
      }),
    );

    final bundle = await AppBackupService.exportAll();
    final target = await Directory(
      p.join(sourceRoot.path, 'restored'),
    ).create(recursive: true);
    final previous = AppBackupService.rootOverride;
    AppBackupService.rootOverride = target.path;
    try {
      await AppBackupService.importAll(bundle.bytes);
    } finally {
      AppBackupService.rootOverride = previous;
    }

    final metadata =
        jsonDecode(
              await File(
                p.join(
                  target.path,
                  'files_backup',
                  'demo',
                  'Main-1.java.metadata.json',
                ),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(
      metadata['originalPath'],
      p.normalize(p.join(target.path, 'projects', 'demo', 'src', 'Main.java')),
    );
  });
}

String _infoJson({int formatVersion = 1}) => jsonEncode({
  'format': 'qfli-app-backup',
  'formatVersion': formatVersion,
  'productKey': StudioProductCatalog.qfliStudioKey,
  'appTitle': StudioProductCatalog.qfliStudio,
  'profileId': '',
  'runtimeKind': 'unavailable',
  'appVersion': '1.0.0',
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'fileCount': 1,
});

List<String> _entryNames(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return [for (final entry in archive.files) entry.name];
}

Uint8List _zipWith(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.add(
      ArchiveFile.bytes(name, Uint8List.fromList(utf8.encode(content))),
    );
  });
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _zipWithRaw(List<(String, Uint8List)> files) {
  final archive = Archive();
  for (final (name, content) in files) {
    archive.add(ArchiveFile.bytes(name, content));
  }
  return ZipEncoder().encodeBytes(archive);
}
