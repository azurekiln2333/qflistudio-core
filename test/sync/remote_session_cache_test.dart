import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/remote_session_cache.dart';
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

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-device-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('Project device fields', () {
    test('a plain project is not a device project', () {
      final project = Project.create(name: 'demo', path: root.path);
      expect(project.isDevice, isFalse);
      expect(project.placeholder, isFalse);
      expect(project.filesPulled, isFalse);
      expect(project.deviceHostId, isNull);
    });

    test('device fields survive a JSON round trip', () {
      final project = Project.create(name: 'demo', path: root.path)
        ..deviceHostId = 'agent-42'
        ..deviceSessionId = 'sess-1'
        ..deviceRoot = r'C:\work\proj'
        ..placeholder = true;

      final restored = Project.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
      );
      expect(restored.isDevice, isTrue);
      expect(restored.deviceHostId, 'agent-42');
      expect(restored.deviceSessionId, 'sess-1');
      expect(restored.deviceRoot, r'C:\work\proj');
      expect(restored.placeholder, isTrue);
      expect(restored.filesPulled, isFalse);
    });

    test('an old registry row without the fields still loads', () {
      final restored = Project.fromJson(<String, dynamic>{
        'id': 'x',
        'name': 'old',
        'path': root.path,
      });
      expect(restored.isDevice, isFalse);
      expect(restored.placeholder, isFalse);
    });

    test('the fields stay out of JSON when unset', () {
      final project = Project.create(name: 'demo', path: root.path);
      final json = project.toJson();
      expect(json.containsKey('deviceHostId'), isFalse);
      expect(json.containsKey('placeholder'), isFalse);
    });
  });

  group('RemoteSessionCache', () {
    late String dir;

    setUp(() async {
      dir = p.join(root.path, 'session');
      await Directory(dir).create(recursive: true);
    });

    test('appends and reads back events in order', () async {
      final cache = RemoteSessionCache(directory: dir);
      await cache.append(<String, dynamic>{
        'id': '1',
        'role': 'user',
        'text': 'hi',
      });
      await cache.append(<String, dynamic>{
        'id': '2',
        'role': 'assistant',
        'text': 'ok',
      });

      final events = await cache.read();
      expect(events.map((e) => e['id']), ['1', '2']);
      expect(events.last['text'], 'ok');
    });

    test('a missing file reads as empty', () async {
      final cache = RemoteSessionCache(directory: p.join(root.path, 'nothing'));
      expect(await cache.read(), isEmpty);
    });

    test('keeps only the newest lines beyond the event cap', () async {
      final cache = RemoteSessionCache(directory: dir, maxEvents: 3);
      for (var i = 0; i < 6; i++) {
        await cache.append(<String, dynamic>{'id': '$i', 'text': 'x'});
      }
      final events = await cache.read();
      expect(events.map((e) => e['id']), ['3', '4', '5']);
    });

    test('keeps only the newest bytes beyond the byte cap', () async {
      final cache = RemoteSessionCache(directory: dir, maxBytes: 40);
      for (var i = 0; i < 5; i++) {
        await cache.append(<String, dynamic>{'id': '$i', 'text': 'y' * 10});
      }
      final events = await cache.read();
      expect(events, isNotEmpty);
      expect(events.last['id'], '4');
      final size = await File(p.join(dir, 'stream.jsonl')).length();
      expect(size, lessThanOrEqualTo(40 + 64));
    });

    test('a corrupt line is skipped', () async {
      final file = File(p.join(dir, 'stream.jsonl'));
      await file.writeAsString('{"id":"1"}\nnot json\n{"id":"2"}\n');
      final cache = RemoteSessionCache(directory: dir);
      expect((await cache.read()).map((e) => e['id']), ['1', '2']);
    });

    test('clear removes the file', () async {
      final cache = RemoteSessionCache(directory: dir);
      await cache.append(<String, dynamic>{'id': '1'});
      await cache.clear();
      expect(await cache.read(), isEmpty);
    });
  });
}
