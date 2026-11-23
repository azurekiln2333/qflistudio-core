import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/placeholder_project.dart';
import 'package:qfli_studio_core/sync/sync_ignore.dart';

class FakePort implements DeviceFilePort {
  FakePort(this.files);

  final Map<String, String> files;

  @override
  Future<GitProjectInfo> gitInfo(String root) async =>
      GitProjectInfo(root: root, supported: false);

  @override
  Future<FsManifest> manifest(String root) async => FsManifest(
    root: root,
    ignoreVersion: kSyncIgnoreVersion,
    truncated: false,
    entries: <FsEntry>[
      for (final entry in files.entries)
        FsEntry(
          path: entry.key,
          kind: 'file',
          size: utf8.encode(entry.value).length,
          hash: sha256.convert(utf8.encode(entry.value)).toString(),
        ),
    ],
  );

  @override
  Future<FsChunk> read(String path, {required int offset, int? length}) async {
    final all = utf8.encode(files[path] ?? '');
    final end = (offset + (length ?? all.length)) > all.length
        ? all.length
        : offset + (length ?? all.length);
    return FsChunk(
      path: path,
      offset: offset,
      bytes: all.sublist(offset, end),
      eof: end >= all.length,
    );
  }
}

void main() {
  late Directory root;
  const placeholders = PlaceholderProjects();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-placeholder-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Project deviceProject({bool placeholder = true, bool filesPulled = false}) =>
      Project.create(name: '会话', path: p.join(root.path, 'proj'))
        ..deviceHostId = 'agent-42'
        ..deviceSessionId = 'sess-1'
        ..deviceRoot = r'C:\work\proj'
        ..placeholder = placeholder
        ..filesPulled = filesPulled;

  group('hostKey', () {
    test('is stable and short', () {
      final key = PlaceholderProjects.hostKey('agent-42');
      expect(key, PlaceholderProjects.hostKey('agent-42'));
      expect(key, hasLength(16));
    });

    test('differs between computers', () {
      expect(
        PlaceholderProjects.hostKey('a'),
        isNot(PlaceholderProjects.hostKey('b')),
      );
    });

    test('never contains a path separator', () {
      final key = PlaceholderProjects.hostKey(r'PC\office/1');
      expect(key.contains('/'), isFalse);
      expect(key.contains(r'\'), isFalse);
    });
  });

  group('discardIfUnused', () {
    test('a placeholder with no files is removed with its directory', () async {
      final project = deviceProject();
      final dir = Directory(project.path)..createSync(recursive: true);
      await File(p.join(dir.path, 'marker')).writeAsString('x');

      expect(await placeholders.discardIfUnused(project), isTrue);
      expect(await dir.exists(), isFalse);
    });

    test('a project the user pulled files into is kept', () async {
      final project = deviceProject(placeholder: false, filesPulled: true);
      final dir = Directory(project.path)..createSync(recursive: true);
      await File(p.join(dir.path, 'main.dart')).writeAsString('void main() {}');

      expect(await placeholders.discardIfUnused(project), isFalse);
      expect(await dir.exists(), isTrue);
    });

    test('a placeholder that already pulled files is kept', () async {
      final project = deviceProject(filesPulled: true);
      final dir = Directory(project.path)..createSync(recursive: true);
      expect(await placeholders.discardIfUnused(project), isFalse);
      expect(await dir.exists(), isTrue);
    });

    test('a plain local project is never removed', () async {
      final project = Project.create(
        name: 'mine',
        path: p.join(root.path, 'x'),
      );
      final dir = Directory(project.path)..createSync(recursive: true);
      expect(await placeholders.discardIfUnused(project), isFalse);
      expect(await dir.exists(), isTrue);
    });
  });

  group('pullFiles', () {
    test('refuses a project without a device root', () async {
      final project = deviceProject()..deviceRoot = null;
      final report = await placeholders.pullFiles(
        project,
        port: FakePort(<String, String>{'a.txt': 'one'}),
      );
      expect(report?.completed, isFalse);
      expect(report?.failure, contains('项目路径'));
    });
  });
}
