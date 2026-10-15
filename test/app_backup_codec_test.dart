import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_backup_codec.dart';

void main() {
  late Directory temporary;
  late Directory storage;
  late Directory documents;
  late String output;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('qfli-codec-');
    storage = await Directory(p.join(temporary.path, 'files')).create();
    documents = await Directory(p.join(temporary.path, 'app_flutter')).create();
    output = p.join(temporary.path, 'export.qfliz');
  });

  tearDown(() async => temporary.delete(recursive: true));

  test(
    'streamed archive includes both roots and preserves binary files',
    () async {
      await File(p.join(storage.path, 'settings.json')).writeAsString('{}');
      final binary = List<int>.generate(256 * 1024, (index) => index % 256);
      await File(p.join(documents.path, 'resource.bin')).writeAsBytes(binary);
      await Directory(p.join(storage.path, 'empty')).create();
      await Directory(
        p.join(storage.path, 'projects', 'usr'),
      ).create(recursive: true);
      await File(
        p.join(storage.path, 'projects', 'usr', 'source.txt'),
      ).writeAsString('keep');
      await Directory(p.join(storage.path, '.qfli-app-restore')).create();
      await File(
        p.join(storage.path, '.qfli-app-restore', 'pending.json'),
      ).writeAsString('{}');

      final metadata = await AppBackupCodec.exportFile(
        roots: {'storage': storage.path, 'documents': documents.path},
        info: {'format': 'qfli-app-backup', 'productKey': 'jvmx'},
        destination: output,
      );
      final archive = ZipDecoder().decodeBytes(
        await File(output).readAsBytes(),
      );
      expect(archive.find('private_documents/resource.bin')!.content, binary);
      expect(archive.find('data/empty/')!.isDirectory, isTrue);
      expect(archive.find('data/projects/usr/source.txt'), isNotNull);
      expect(
        archive.files.any((file) => file.name.contains('pending.json')),
        isFalse,
      );
      expect(metadata['fileCount'], 3);
      expect(
        jsonDecode(utf8.decode(archive.find('app_info.json')!.content)),
        metadata,
      );
    },
  );

  test('refuses an archive destination in any input root', () async {
    await expectLater(
      AppBackupCodec.exportFile(
        roots: {'storage': storage.path},
        info: {},
        destination: p.join(storage.path, 'recursive.qfliz'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await File(p.join(storage.path, 'recursive.qfliz')).exists(),
      isFalse,
    );
  });

  test(
    'preserves executable mode and link payload without following link',
    () async {
      final executable = File(p.join(storage.path, 'run'));
      await executable.writeAsString('#!/bin/sh\n');
      await Process.run('chmod', ['750', executable.path]);
      await Link(
        p.join(storage.path, 'external'),
      ).create('/never-follow-this-path');
      await AppBackupCodec.exportFile(
        roots: {'storage': storage.path},
        info: {},
        destination: output,
      );
      final archive = ZipDecoder().decodeBytes(
        await File(output).readAsBytes(),
      );
      expect(archive.find('data/run')!.mode & 0x1ff, 0x1e8);
      expect(archive.find('data/external')!.mode & 0xf000, 0xa000);
      expect(
        utf8.decode(archive.find('data/external')!.content),
        '/never-follow-this-path',
      );
    },
    skip: Platform.isWindows
        ? 'Windows does not expose Unix chmod/link semantics'
        : false,
  );
}
