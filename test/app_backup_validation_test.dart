import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_backup_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-validation-');
    AppBackupService.rootOverride = root.path;
    await File(p.join(root.path, 'original.txt')).writeAsString('keep');
  });

  tearDown(() async {
    AppBackupService.rootOverride = null;
    await root.delete(recursive: true);
  });

  Uint8List backup(String name, String value) {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'app_info.json',
          jsonEncode(AppBackupService.currentInfo().toJson()),
        ),
      )
      ..addFile(ArchiveFile.noCompress(name, value.length, utf8.encode(value)));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('corrupt member CRC is rejected without touching live data', () async {
    const payload = 'unique-payload-with-a-valid-original-checksum';
    final bytes = backup('data/payload.txt', payload);
    final signature = utf8.encode(payload);
    var offset = -1;
    for (var i = 0; i <= bytes.length - signature.length; i++) {
      if (List.generate(
        signature.length,
        (j) => bytes[i + j],
      ).asMap().entries.every((entry) => entry.value == signature[entry.key])) {
        offset = i;
        break;
      }
    }
    expect(offset, greaterThanOrEqualTo(0));
    bytes[offset] ^= 1;
    await expectLater(
      AppBackupService.prepareImport(bytes),
      throwsA(
        isA<AppBackupException>().having(
          (e) => e.message,
          'message',
          contains('CRC'),
        ),
      ),
    );
    expect(
      await File(p.join(root.path, 'original.txt')).readAsString(),
      'keep',
    );
    expect(await AppBackupService.hasPendingRestore(), isFalse);
    expect(
      await Directory(
        p.join(root.path, AppBackupService.stagingDirName),
      ).exists(),
      isFalse,
    );
  });

  test(
    'archive cannot replace the backup mechanism control directories',
    () async {
      for (final name in [
        'data/.qfli-app-restore/pending.json',
        'data/.qfli-app-old/control/journal.json',
        'data/.qfli-restore-temporary/value',
      ]) {
        await expectLater(
          AppBackupService.prepareImport(backup(name, 'forged')),
          throwsA(isA<AppBackupException>()),
        );
      }
      expect(
        await File(p.join(root.path, 'original.txt')).readAsString(),
        'keep',
      );
      expect(await AppBackupService.hasPendingRestore(), isFalse);
    },
  );

  test('a file cannot impersonate an empty root marker', () async {
    await expectLater(
      AppBackupService.prepareImport(backup('data', 'not-a-directory')),
      throwsA(isA<AppBackupException>()),
    );
    expect(
      await File(p.join(root.path, 'original.txt')).readAsString(),
      'keep',
    );
  });
}
