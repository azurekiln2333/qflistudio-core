import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/project_zip_service.dart';
import 'package:qfli_studio_core/store/project_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  late Directory fixture;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('qfli_project_zip_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(storage.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
  });

  setUp(() async {
    fixture = await storage.createTemp('case_');
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    await storage.delete(recursive: true);
  });

  Future<ProjectStore> store({bool blocked = false}) async {
    final registry = p.join(fixture.path, 'projects.json');
    if (blocked) await Directory(registry).create();
    final result = ProjectStore(storageFile: File(registry));
    await result.load();
    addTearDown(result.dispose);
    return result;
  }

  Future<void> write(String relative, List<int> contents) async {
    final file = File(p.join(fixture.path, 'source', relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(contents);
  }

  Project sourceProject() => Project.create(
    name: '中文工程',
    path: p.join(fixture.path, 'source'),
    language: 'Java',
    type: 'java',
    cloudId: 'old-cloud-id',
  );

  test(
    'real ZIP round trip preserves all files, empty directories and metadata',
    () async {
      await write('src/中文.java', utf8.encode('class Main {}'));
      await write('assets/binary.bin', [0, 1, 128, 255, 0]);
      await write('.hidden', [9]);
      await write('.git/config', utf8.encode('[core]'));
      await write('build/output.bin', [5, 4, 3]);
      await Directory(p.join(fixture.path, 'source', '空目录')).create();
      await write(
        '.qfli/project.json',
        utf8.encode(
          jsonEncode({
            'version': 1,
            'name': '配置中的中文显示名',
            'language': 'Java',
            'type': 'java',
            'id': 'machine-local-id',
            'path': 'C:/old/machine/project',
            'cloudId': 'old-cloud-id',
            'cloudOrigin': 'https://old-server.example',
            'entryFile': 'src/中文.java',
            'custom': {'keep': true},
          }),
        ),
      );
      final source = sourceProject();
      final bytes = await ProjectZipService.exportProject(source);
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.find('assets/binary.bin')!.content, [0, 1, 128, 255, 0]);
      expect(zip.find('空目录/')!.isDirectory, isTrue);
      expect(zip.find('app_info.json'), isNull);

      final projects = await store();
      final result = await projects.importProjectArchive(bytes);
      expect(result.error, isNull);
      final imported = result.project!;
      expect(imported.name, '配置中的中文显示名');
      expect(imported.language, 'Java');
      expect(imported.type, 'java');
      expect(imported.id, isNot(source.id));
      expect(imported.isCloud, isFalse);
      expect(imported.path, isNot(source.path));
      expect(
        p.isWithin((await AppPaths.projectsRoot())!, imported.path),
        isTrue,
      );
      for (final relative in [
        'src/中文.java',
        'assets/binary.bin',
        '.hidden',
        '.git/config',
        'build/output.bin',
      ]) {
        expect(
          await File(p.join(imported.path, relative)).readAsBytes(),
          await File(p.join(source.path, relative)).readAsBytes(),
        );
      }
      expect(Directory(p.join(imported.path, '空目录')).existsSync(), isTrue);
      final config = ProjectConfig.read(imported.path)!;
      expect(config['custom'], {'keep': true});
      expect(config['entryFile'], 'src/中文.java');
      for (final key in ['id', 'path', 'cloudId', 'cloudOrigin']) {
        expect(config.containsKey(key), isFalse);
      }
      final reloaded = ProjectStore(
        storageFile: File(p.join(fixture.path, 'projects.json')),
      );
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.projects.single.id, imported.id);
    },
  );

  test(
    'export without config includes portable project display metadata',
    () async {
      await write('src/Main.java', utf8.encode('class Main {}'));
      final source = sourceProject();
      final bytes = await ProjectZipService.exportProject(source);
      final projects = await store();
      final result = await projects.importProjectArchive(bytes);
      expect(result.error, isNull);
      expect(result.project!.name, source.name);
      expect(result.project!.language, 'Java');
      expect(result.project!.type, 'java');
      expect(File(ProjectConfig.configPath(source.path)).existsSync(), isFalse);
    },
  );

  test('ordinary ZIP renamed qsz imports without a manifest', () async {
    final projects = await store();
    final result = await projects.importProjectArchive(
      _zip([ArchiveFile.string('src/Main.java', 'class Main {}')]),
    );
    expect(result.error, isNull);
    expect(result.project!.name, '导入项目');
    expect(result.project!.language, 'Java');
    expect(result.project!.type, 'java');
  });

  test(
    'repeated and concurrent imports never overwrite existing projects',
    () async {
      await write('src/Main.java', utf8.encode('original'));
      final projects = await store();
      final existing = await projects.addExisting(sourceProject().path);
      final bytes = await ProjectZipService.exportProject(sourceProject());
      final results = await Future.wait([
        projects.importProjectArchive(bytes),
        projects.importProjectArchive(bytes),
      ]);
      expect(results.every((item) => item.error == null), isTrue);
      expect(projects.projects, hasLength(3));
      expect(projects.projects.map((item) => item.id).toSet(), hasLength(3));
      expect(projects.projects.map((item) => item.path).toSet(), hasLength(3));
      expect(projects.projectById(existing.project!.id), existing.project);
      await File(
        p.join(results.first.project!.path, 'src/Main.java'),
      ).writeAsString('changed');
      expect(
        await File(
          p.join(sourceProject().path, 'src/Main.java'),
        ).readAsString(),
        'original',
      );
      expect(
        await File(
          p.join(results.last.project!.path, 'src/Main.java'),
        ).readAsString(),
        'original',
      );
    },
  );

  test(
    'export to a project-local destination cannot include its own output',
    () async {
      await write('src/Main.java', utf8.encode('class Main {}'));
      final destination = p.join(sourceProject().path, 'export.qsz');
      await File(destination).writeAsString('previous archive');
      await ProjectZipService.exportToFile(sourceProject(), destination);
      final zip = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      expect(zip.find('src/Main.java'), isNotNull);
      expect(zip.find('export.qsz'), isNull);
      expect(
        zip.any((entry) => entry.name.contains('.qfli-qsz-export-')),
        isFalse,
      );
      expect(
        await File(
          p.join(sourceProject().path, 'src/Main.java'),
        ).readAsString(),
        'class Main {}',
      );
    },
  );

  test(
    'registry persistence failure removes only the new import directory',
    () async {
      final projects = await store(blocked: true);
      final root = Directory((await AppPaths.projectsRoot())!);
      final before = root.listSync().map((item) => item.path).toSet();
      final result = await projects.importProjectArchive(
        _zip([ArchiveFile.string('src/Main.java', 'class Main {}')]),
      );
      expect(result.error, isNotNull);
      expect(result.project, isNull);
      expect(projects.projects, isEmpty);
      expect(root.listSync().map((item) => item.path).toSet(), before);
      expect(
        Directory(p.join(fixture.path, 'projects.json')).existsSync(),
        isTrue,
      );
    },
  );

  final unsafePaths = [
    '../escape',
    'src/../../escape',
    '/absolute',
    r'C:\escape',
    'C:escape',
    r'\\server\share\escape',
    'src/./entry',
    'src//entry',
    'src/entry:stream',
    'src/NUL.txt',
    'src/entry.',
  ];
  for (final path in unsafePaths) {
    test('rejects unsafe member $path before creating any project', () async {
      final projects = await store();
      final root = Directory((await AppPaths.projectsRoot())!);
      final before = root.listSync().map((item) => item.path).toSet();
      final result = await projects.importProjectArchive(
        _zip([ArchiveFile.string(path, 'unsafe')]),
      );
      expect(result.error, isNotNull);
      expect(projects.projects, isEmpty);
      expect(root.listSync().map((item) => item.path).toSet(), before);
    });
  }

  final collisions = <List<ArchiveFile>>[
    [ArchiveFile.string('same', 'a'), ArchiveFile.string('same', 'b')],
    [ArchiveFile.string('Readme', 'a'), ArchiveFile.string('README', 'b')],
    [ArchiveFile.string('a', 'file'), ArchiveFile.string('a/child', 'child')],
    [ArchiveFile.string('a/child', 'child'), ArchiveFile.string('a', 'file')],
    [ArchiveFile.directory('a/'), ArchiveFile.string('a', 'file')],
    [ArchiveFile.string('Dir/a', 'a'), ArchiveFile.string('dir/b', 'b')],
    [ArchiveFile.string('dir/child', 'x'), ArchiveFile.directory('Dir/')],
  ];
  for (var index = 0; index < collisions.length; index++) {
    test('rejects duplicate/case/file-directory conflict $index', () async {
      final projects = await store();
      final result = await projects.importProjectArchive(
        _zip(collisions[index]),
      );
      expect(result.error, isNotNull);
      expect(projects.projects, isEmpty);
    });
  }

  test(
    'rejects UNIX and DOS creator link modes including ancestor links',
    () async {
      final projects = await store();
      final bytes = _zip([
        ArchiveFile.string('link', '../outside')..mode = 0xa1ff,
        ArchiveFile.string('link/child', 'escape'),
      ]);
      expect((await projects.importProjectArchive(bytes)).error, isNotNull);
      // Link type bits remain unsafe even when the creator OS claims DOS.
      final dos = Uint8List.fromList(bytes);
      for (var index = 0; index < dos.length - 5; index++) {
        if (dos[index] == 0x50 &&
            dos[index + 1] == 0x4b &&
            dos[index + 2] == 0x01 &&
            dos[index + 3] == 0x02) {
          dos[index + 5] = 0;
        }
      }
      expect((await projects.importProjectArchive(dos)).error, isNotNull);
      expect(projects.projects, isEmpty);
    },
  );

  test(
    'rejects corrupt, truncated and non-ZIP bytes without filesystem changes',
    () async {
      final projects = await store();
      final valid = _zip([ArchiveFile.string('data.bin', 'payload')], level: 0);
      final corrupt = Uint8List.fromList(valid);
      final data = ByteData.sublistView(corrupt);
      final offset =
          30 +
          data.getUint16(26, Endian.little) +
          data.getUint16(28, Endian.little);
      corrupt[offset] ^= 0xff;
      final root = Directory((await AppPaths.projectsRoot())!);
      final before = root.listSync().map((item) => item.path).toSet();
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList(utf8.encode('{"files":[]}')),
        valid.sublist(0, valid.length - 3),
        corrupt,
      ]) {
        final result = await projects.importProjectArchive(bytes);
        expect(result.error, isNotNull);
        expect(result.project, isNull);
        expect(root.listSync().map((item) => item.path).toSet(), before);
      }
      expect(projects.projects, isEmpty);
    },
  );

  test(
    'unsafe metadata entry path cannot escape the imported project',
    () async {
      final projects = await store();
      final result = await projects.importProjectArchive(
        _zip([
          ArchiveFile.string(
            '.qfli/project.json',
            jsonEncode({'name': 'Bad entry', 'entryFile': '../outside.java'}),
          ),
          ArchiveFile.string('src/Main.java', 'class Main {}'),
        ]),
      );
      expect(result.error, isNotNull);
      expect(projects.projects, isEmpty);
    },
  );

  test(
    'export refuses links instead of following or silently dropping them',
    () async {
      await write('src/Main.java', utf8.encode('class Main {}'));
      final outside = File(p.join(fixture.path, 'outside.txt'))
        ..writeAsStringSync('private outside data');
      await Link(p.join(sourceProject().path, 'escape')).create(outside.path);
      final destination = File(p.join(fixture.path, 'existing.qsz'))
        ..writeAsStringSync('keep on export failure');
      await expectLater(
        ProjectZipService.exportToFile(sourceProject(), destination.path),
        throwsA(isA<ProjectZipException>()),
      );
      expect(await destination.readAsString(), 'keep on export failure');
      expect(await outside.readAsString(), 'private outside data');
    },
    skip: Platform.isWindows
        ? 'Windows symlink creation needs privileges'
        : false,
  );
}

Uint8List _zip(List<ArchiveFile> files, {int level = 6}) {
  // Do not use Archive.add: it replaces duplicate paths before ZIP encoding.
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output, level: level);
  for (final file in files) {
    encoder.add(file);
  }
  encoder.endEncode();
  return output.getBytes();
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
