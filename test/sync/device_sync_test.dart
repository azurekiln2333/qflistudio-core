import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/device_sync.dart';
import 'package:qfli_studio_core/sync/sync_cache.dart';
import 'package:qfli_studio_core/sync/sync_ignore.dart';
import 'package:qfli_studio_core/sync/sync_limits.dart';

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

FsEntry _file(String path, String content) => FsEntry(
  path: path,
  kind: 'file',
  size: utf8.encode(content).length,
  hash: _sha(content),
);

FsEntry _dir(String path) =>
    FsEntry(path: path, kind: 'dir', size: 0, hash: '');

/// A computer whose files live in memory.
class FakeDevicePort implements DeviceFilePort {
  FakeDevicePort({
    required this.files,
    this.ignoreVersion = kSyncIgnoreVersion,
    this.truncated = false,
    this.chunkBytes = kSyncChunkBytes,
    this.corrupt = const <String>{},
  });

  final Map<String, String> files;
  final int ignoreVersion;
  final bool truncated;
  final int chunkBytes;

  /// Paths whose bytes come back altered, to exercise the hash check.
  final Set<String> corrupt;

  final List<String> reads = <String>[];

  @override
  Future<GitProjectInfo> gitInfo(String root) async =>
      GitProjectInfo(root: root, supported: false);

  @override
  Future<FsManifest> manifest(String root) async => FsManifest(
    root: root,
    ignoreVersion: ignoreVersion,
    truncated: truncated,
    entries: <FsEntry>[
      for (final entry in files.entries)
        if (entry.key.endsWith('/'))
          _dir(entry.key.substring(0, entry.key.length - 1))
        else
          _file(entry.key, entry.value),
    ],
  );

  @override
  Future<FsChunk> read(String path, {required int offset, int? length}) async {
    reads.add(path);
    final text = files[path] ?? '';
    final all = utf8.encode(text);
    final wanted = length ?? chunkBytes;
    final end = (offset + wanted) > all.length ? all.length : offset + wanted;
    final slice = all.sublist(offset, end);
    if (corrupt.contains(path) && offset == 0) {
      return FsChunk(
        path: path,
        offset: offset,
        bytes: <int>[0, ...slice.skip(1)],
        eof: end >= all.length,
      );
    }
    return FsChunk(
      path: path,
      offset: offset,
      bytes: slice,
      eof: end >= all.length,
    );
  }
}

void main() {
  late Directory root;
  late String localRoot;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-sync-test-');
    localRoot = p.join(root.path, 'copy');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('plan', () {
    test('a first sync downloads every file', () async {
      final port = FakeDevicePort(
        files: <String, String>{'a.txt': 'one', 'lib/b.txt': 'two'},
      );
      final service = DeviceSyncService(port: port);

      final plan = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );

      expect(plan.downloads.map((e) => e.path), ['a.txt', 'lib/b.txt']);
      expect(plan.deletes, isEmpty);
      expect(plan.bytes, 6);
      expect(plan.isEmpty, isFalse);
    });

    test('unchanged files are skipped', () async {
      final port = FakeDevicePort(files: <String, String>{'a.txt': 'one'});
      final service = DeviceSyncService(port: port);
      final plan = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      expect(await service.apply(plan), isA<SyncReport>());

      final second = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      expect(second.downloads, isEmpty);
      expect(second.deletes, isEmpty);
      expect(second.isEmpty, isTrue);
    });

    test('a changed file is downloaded again', () async {
      final first = FakeDevicePort(files: <String, String>{'a.txt': 'one'});
      final service = DeviceSyncService(port: first);
      await service.apply(
        await service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      final second = DeviceSyncService(
        port: FakeDevicePort(files: <String, String>{'a.txt': 'changed'}),
      );
      final plan = await second.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      expect(plan.downloads.map((e) => e.path), ['a.txt']);
    });

    test('a file the computer no longer has is marked for deletion', () async {
      final first = FakeDevicePort(
        files: <String, String>{'a.txt': 'one', 'gone.txt': 'bye'},
      );
      final service = DeviceSyncService(port: first);
      await service.apply(
        await service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      final second = DeviceSyncService(
        port: FakeDevicePort(files: <String, String>{'a.txt': 'one'}),
      );
      final plan = await second.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      expect(plan.deletes, ['gone.txt']);
      expect(plan.downloads, isEmpty);
    });

    test(
      'a truncated manifest is refused instead of read as deletions',
      () async {
        final service = DeviceSyncService(
          port: FakeDevicePort(
            files: <String, String>{'a.txt': 'one'},
            truncated: true,
          ),
        );
        await expectLater(
          service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
          throwsA(
            isA<DeviceSyncException>().having(
              (e) => e.kind,
              'kind',
              'truncated',
            ),
          ),
        );
      },
    );

    test('an ignore table mismatch is refused', () async {
      final service = DeviceSyncService(
        port: FakeDevicePort(files: <String, String>{}, ignoreVersion: 2),
      );
      await expectLater(
        service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
        throwsA(
          isA<DeviceSyncException>().having((e) => e.kind, 'kind', 'mismatch'),
        ),
      );
    });
  });

  group('apply', () {
    test('writes the files and records the manifest', () async {
      final port = FakeDevicePort(
        files: <String, String>{'a.txt': 'one', 'lib/b.txt': 'two'},
      );
      final service = DeviceSyncService(port: port);
      final plan = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      final report = await service.apply(plan);

      expect(report.completed, isTrue);
      expect(report.writtenFiles, 2);
      expect(report.bytes, 6);
      expect(
        await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
        'one',
      );
      expect(
        await File(p.join(localRoot, 'files', 'lib', 'b.txt')).readAsString(),
        'two',
      );
      expect(await File(p.join(localRoot, 'manifest.json')).exists(), isTrue);
      expect(await File(p.join(localRoot, 'sync.json')).exists(), isTrue);
    });

    test('leaves no staging file behind', () async {
      final service = DeviceSyncService(
        port: FakeDevicePort(files: <String, String>{'a.txt': 'one'}),
      );
      await service.apply(
        await service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );
      final staging = Directory(p.join(localRoot, '.incoming'));
      expect(await staging.list().isEmpty, isTrue);
    });

    test('reads a large file in chunks', () async {
      final big = 'x' * (kSyncChunkBytes + 10);
      final port = FakeDevicePort(
        files: <String, String>{'big.bin': big},
        chunkBytes: kSyncChunkBytes,
      );
      final service = DeviceSyncService(port: port);
      final plan = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      final report = await service.apply(plan);

      expect(report.completed, isTrue);
      expect(port.reads.length, 2);
      expect(
        await File(p.join(localRoot, 'files', 'big.bin')).length(),
        utf8.encode(big).length,
      );
    });

    test('a bad hash keeps the old file and reports the failure', () async {
      final first = DeviceSyncService(
        port: FakeDevicePort(files: <String, String>{'a.txt': 'one'}),
      );
      await first.apply(
        await first.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      final second = DeviceSyncService(
        port: FakeDevicePort(
          files: <String, String>{'a.txt': 'changed'},
          corrupt: <String>{'a.txt'},
        ),
      );
      final report = await second.apply(
        await second.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      expect(report.completed, isFalse);
      expect(report.failure, contains('校验'));
      expect(
        await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
        'one',
      );
    });

    test(
      'a bad hash leaves no half-written file in the staging area',
      () async {
        final port = FakeDevicePort(
          files: <String, String>{'a.txt': 'changed'},
          corrupt: <String>{'a.txt'},
        );
        final service = DeviceSyncService(port: port);
        final report = await service.apply(
          await service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
        );

        expect(report.completed, isFalse);
        final staging = Directory(p.join(localRoot, '.incoming'));
        expect(await staging.exists(), isTrue);
        expect(await staging.list().isEmpty, isTrue, reason: '校验失败的分片不能留在暂存区');
        expect(
          await File(p.join(localRoot, 'files', 'a.txt')).exists(),
          isFalse,
        );
      },
    );

    test('streams a large file chunk by chunk while hashing it', () async {
      // 三块：分块写入与一次性写入在磁盘上必须是同一个文件。
      final big = 'y' * (kSyncChunkBytes * 2 + 7);
      final port = FakeDevicePort(
        files: <String, String>{'big.bin': big},
        chunkBytes: kSyncChunkBytes,
      );
      final service = DeviceSyncService(port: port);
      final report = await service.apply(
        await service.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      expect(report.completed, isTrue);
      expect(report.writtenFiles, 1);
      expect(report.bytes, utf8.encode(big).length);
      expect(port.reads.length, 3);
      expect(
        await File(p.join(localRoot, 'files', 'big.bin')).readAsString(),
        big,
      );
    });

    test(
      'a file shorter than its manifest entry fails without a rename',
      () async {
        final port = FakeDevicePort(
          files: <String, String>{'short.txt': 'abc'},
        );
        final service = DeviceSyncService(port: port);
        final plan = await service.plan(
          remoteRoot: r'C:\work\proj',
          localRoot: localRoot,
        );
        // 清单说 10 字节，电脑只交了 3 字节又宣布结束。
        final tampered = SyncPlan(
          remoteRoot: plan.remoteRoot,
          localRoot: plan.localRoot,
          manifest: FsManifest(
            root: plan.manifest.root,
            ignoreVersion: plan.manifest.ignoreVersion,
            truncated: false,
            entries: <FsEntry>[
              FsEntry(
                path: 'short.txt',
                kind: 'file',
                size: 10,
                hash: plan.manifest.entries.single.hash,
              ),
            ],
          ),
          downloads: <FsEntry>[
            FsEntry(
              path: 'short.txt',
              kind: 'file',
              size: 10,
              hash: plan.manifest.entries.single.hash,
            ),
          ],
          deletes: const <String>[],
          bytes: 10,
        );

        final report = await service.apply(tampered);

        expect(report.completed, isFalse);
        expect(report.failure, contains('长度'));
        expect(
          await File(p.join(localRoot, 'files', 'short.txt')).exists(),
          isFalse,
        );
      },
    );

    test('deletes stale files and prunes empty directories', () async {
      final first = DeviceSyncService(
        port: FakeDevicePort(
          files: <String, String>{'keep.txt': 'k', 'old/gone.txt': 'g'},
        ),
      );
      await first.apply(
        await first.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      final second = DeviceSyncService(
        port: FakeDevicePort(files: <String, String>{'keep.txt': 'k'}),
      );
      final report = await second.apply(
        await second.plan(remoteRoot: r'C:\work\proj', localRoot: localRoot),
      );

      expect(report.completed, isTrue);
      expect(report.deletedEntries, greaterThan(0));
      expect(
        await File(p.join(localRoot, 'files', 'old', 'gone.txt')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(localRoot, 'files', 'old')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(localRoot, 'files', 'keep.txt')).exists(),
        isTrue,
      );
    });

    test('reports progress once per file', () async {
      final service = DeviceSyncService(
        port: FakeDevicePort(
          files: <String, String>{'a.txt': 'one', 'b.txt': 'two'},
        ),
      );
      final plan = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      final seen = <SyncProgress>[];
      await service.apply(plan, onProgress: seen.add);

      expect(seen, hasLength(2));
      expect(seen.last.doneFiles, 2);
      expect(seen.last.totalBytes, 6);
    });
  });

  group('evict', () {
    test('removes the least recently used copy', () async {
      final cacheDir = Directory(p.join(root.path, 'cache'));
      final first = Directory(p.join(cacheDir.path, 'one'))
        ..createSync(recursive: true);
      final second = Directory(p.join(cacheDir.path, 'two'))
        ..createSync(recursive: true);
      await File(p.join(first.path, 'f')).writeAsString('x' * 100);
      await File(p.join(second.path, 'f')).writeAsString('x' * 100);

      final cache = SyncCache(
        indexFile: p.join(root.path, 'index.json'),
        // Two 100-byte copies need 100 more bytes of room in a 250-byte
        // budget: evicting the oldest leaves 200, which fits. With 150 the
        // request could not be satisfied by removing one copy, so the
        // documented policy would have to remove both.
        budgetBytes: 250,
      );
      await cache.touch(
        'h/one',
        directory: first.path,
        bytes: 100,
        at: DateTime(2024),
      );
      await cache.touch(
        'h/two',
        directory: second.path,
        bytes: 100,
        at: DateTime(2025),
      );

      final service = DeviceSyncService(
        port: FakeDevicePort(files: const <String, String>{}),
        cache: cache,
      );
      final removed = await service.evict(needBytes: 100);

      expect(removed, 1);
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isTrue);
      expect(cache.entryFor('h/one'), isNull);
    });

    test('keeps the project the user has open', () async {
      final cacheDir = Directory(p.join(root.path, 'cache2'));
      final open = Directory(p.join(cacheDir.path, 'open'))
        ..createSync(recursive: true);
      await File(p.join(open.path, 'f')).writeAsString('x' * 100);

      final cache = SyncCache(
        indexFile: p.join(root.path, 'index2.json'),
        budgetBytes: 10,
      );
      await cache.touch('h/open', directory: open.path, bytes: 100);

      final service = DeviceSyncService(
        port: FakeDevicePort(files: const <String, String>{}),
        cache: cache,
      );
      expect(await service.evict(needBytes: 100, keep: {'h/open'}), 0);
      expect(await open.exists(), isTrue);
    });
  });
}
