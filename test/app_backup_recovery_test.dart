import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_backup_service.dart';

void main() {
  late Directory primary;
  late Directory secondary;

  setUp(() async {
    primary = await Directory.systemTemp.createTemp('qfli-recovery-primary-');
    secondary = await Directory.systemTemp.createTemp('qfli-recovery-extra-');
    AppBackupService.rootOverride = primary.path;
  });

  tearDown(() async {
    AppBackupService.rootOverride = null;
    AppBackupService.rootsResolverOverride = null;
    AppBackupService.moveOverride = null;
    for (final directory in [primary, secondary]) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  String stagingPath() => p.join(primary.path, AppBackupService.stagingDirName);

  String backupPath(Directory root) =>
      p.join(root.path, AppBackupService.oldDirName);

  String originalPath(Directory root, String name) =>
      p.join(backupPath(root), AppBackupService.backupOriginalsDir, name);

  String journalPath() => p.join(
    backupPath(primary),
    AppBackupService.backupControlDir,
    AppBackupService.journalFileName,
  );

  String stagingJournalPath() =>
      p.join(stagingPath(), AppBackupService.journalFileName);

  Future<void> write(String path, String value) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  Future<void> journal({
    String state = 'installing',
    Map<String, String>? roots,
    Map<String, List<String>> origins = const {
      'storage': ['settings.json'],
    },
    Map<String, List<String>> incoming = const {
      'storage': ['settings.json'],
    },
    Map<String, List<String>> moved = const {
      'storage': ['settings.json'],
    },
    Map<String, List<String>> installed = const {
      'storage': ['settings.json'],
    },
  }) async {
    final text = jsonEncode({
      'version': 1,
      'state': state,
      'recordedRoots': roots ?? {'storage': primary.path},
      'plannedOrigins': origins,
      'plannedNew': incoming,
      'movedToBackup': moved,
      'installedNew': installed,
    });
    await write(journalPath(), text);
    await write(stagingJournalPath(), text);
  }

  Matcher rejectsWith(String fragment) => throwsA(
    isA<AppBackupException>().having(
      (error) => error.message,
      'message',
      contains(fragment),
    ),
  );

  test(
    'an unavailable transaction root preserves both recovery copies',
    () async {
      await write(originalPath(primary, 'settings.json'), 'PRIMARY ORIGINAL');
      await write(originalPath(secondary, 'document.bin'), 'DOCUMENT ORIGINAL');
      await write(p.join(primary.path, 'settings.json'), 'PRIMARY INCOMING');
      await write(p.join(secondary.path, 'document.bin'), 'DOCUMENT INCOMING');
      await journal(
        roots: {'storage': primary.path, 'documents': secondary.path},
        origins: {
          'storage': ['settings.json'],
          'documents': ['document.bin'],
        },
        incoming: {
          'storage': ['settings.json'],
          'documents': ['document.bin'],
        },
        moved: {
          'storage': ['settings.json'],
          'documents': ['document.bin'],
        },
        installed: {
          'storage': ['settings.json'],
          'documents': ['document.bin'],
        },
      );
      final originalJournal = await File(journalPath()).readAsString();
      AppBackupService.rootsResolverOverride = (_) async => {
        'storage': primary.path,
      };

      await expectLater(
        AppBackupService.applyPendingRestore(),
        rejectsWith('documents 当前不可用'),
      );

      expect(
        await File(originalPath(primary, 'settings.json')).readAsString(),
        'PRIMARY ORIGINAL',
      );
      expect(
        await File(originalPath(secondary, 'document.bin')).readAsString(),
        'DOCUMENT ORIGINAL',
      );
      expect(
        await File(p.join(primary.path, 'settings.json')).readAsString(),
        'PRIMARY INCOMING',
      );
      expect(
        await File(p.join(secondary.path, 'document.bin')).readAsString(),
        'DOCUMENT INCOMING',
      );
      expect(await File(journalPath()).readAsString(), originalJournal);
      expect(await File(stagingJournalPath()).readAsString(), originalJournal);
    },
  );

  for (final hasPayload in [false, true]) {
    test(
      'committed restore is consumed when payload exists=$hasPayload',
      () async {
        await write(p.join(primary.path, 'settings.json'), 'COMMITTED DATA');
        await write(originalPath(primary, 'settings.json'), 'OLD DATA');
        await journal(state: 'committed');
        await write(
          p.join(stagingPath(), AppBackupService.pendingFileName),
          jsonEncode(AppBackupService.currentInfo().toJson()),
        );
        if (hasPayload) {
          await Directory(p.join(stagingPath(), 'payload')).create();
        }

        final result = await AppBackupService.applyPendingRestore();

        expect(result, isNotNull);
        expect(
          await File(p.join(primary.path, 'settings.json')).readAsString(),
          'COMMITTED DATA',
        );
        expect(await Directory(stagingPath()).exists(), isFalse);
        expect(await Directory(backupPath(primary)).exists(), isFalse);
        expect(await AppBackupService.applyPendingRestore(), isNull);
      },
    );
  }

  for (final marker in <String?>[null, 'NOT VALID JSON']) {
    test(
      'transaction recovers despite ${marker == null ? 'missing' : 'corrupt'} '
      'pending marker and missing payload',
      () async {
        await write(originalPath(primary, 'settings.json'), 'ORIGINAL DATA');
        await write(p.join(primary.path, 'settings.json'), 'PARTLY INSTALLED');
        await journal();
        if (marker != null) {
          await write(
            p.join(stagingPath(), AppBackupService.pendingFileName),
            marker,
          );
        }

        final result = await AppBackupService.applyPendingRestore();

        expect(result, isNotNull);
        expect(
          await File(p.join(primary.path, 'settings.json')).readAsString(),
          'ORIGINAL DATA',
        );
        expect(await Directory(stagingPath()).exists(), isFalse);
        expect(await Directory(backupPath(primary)).exists(), isFalse);
        expect(await AppBackupService.applyPendingRestore(), isNull);
      },
    );
  }

  test(
    'two corrupt journals preserve originals and partially installed data',
    () async {
      await write(originalPath(primary, 'settings.json'), 'ORIGINAL DATA');
      await write(p.join(primary.path, 'settings.json'), 'PARTLY INSTALLED');
      await write(journalPath(), '{BROKEN PRIMARY');
      await write(stagingJournalPath(), '{BROKEN STAGING');

      await expectLater(
        AppBackupService.applyPendingRestore(),
        rejectsWith('损坏的恢复事务记录'),
      );

      expect(
        await File(originalPath(primary, 'settings.json')).readAsString(),
        'ORIGINAL DATA',
      );
      expect(
        await File(p.join(primary.path, 'settings.json')).readAsString(),
        'PARTLY INSTALLED',
      );
      expect(await File(journalPath()).readAsString(), '{BROKEN PRIMARY');
      expect(
        await File(stagingJournalPath()).readAsString(),
        '{BROKEN STAGING',
      );
    },
  );

  test('resuming a partial rollback keeps originals already moved back', () async {
    // settings.json was already returned by a rollback before the process died.
    // Its backup is gone, but the durable journal still lists it as installed.
    await write(p.join(primary.path, 'settings.json'), 'ALREADY RESTORED');
    await write(originalPath(primary, 'projects/demo/Main.java'), 'OLD SOURCE');
    await write(p.join(primary.path, 'projects/demo/Main.java'), 'NEW SOURCE');
    await write(p.join(primary.path, 'fresh.bin'), 'INCOMING ONLY');
    await journal(
      state: 'rolling-back',
      origins: {
        'storage': ['settings.json', 'projects'],
      },
      incoming: {
        'storage': ['settings.json', 'projects', 'fresh.bin'],
      },
      moved: {
        'storage': ['settings.json', 'projects'],
      },
      installed: {
        'storage': ['settings.json', 'projects', 'fresh.bin'],
      },
    );

    expect(await AppBackupService.applyPendingRestore(), isNotNull);
    expect(
      await File(p.join(primary.path, 'settings.json')).readAsString(),
      'ALREADY RESTORED',
    );
    expect(
      await File(
        p.join(primary.path, 'projects/demo/Main.java'),
      ).readAsString(),
      'OLD SOURCE',
    );
    expect(await File(p.join(primary.path, 'fresh.bin')).exists(), isFalse);
    expect(await Directory(backupPath(primary)).exists(), isFalse);

    expect(await AppBackupService.applyPendingRestore(), isNull);
    expect(
      await File(p.join(primary.path, 'settings.json')).readAsString(),
      'ALREADY RESTORED',
    );
    expect(
      await File(
        p.join(primary.path, 'projects/demo/Main.java'),
      ).readAsString(),
      'OLD SOURCE',
    );
  });

  test('history and recycle paths rebase without a project registry', () async {
    final metadataNames = [
      p.join('files_backup', 'demo', 'Main.java.metadata.json'),
      p.join('recyclebin', 'files_bin', 'Main.zip.metadata.json'),
      p.join('recyclebin', 'projects_bin', 'demo.zip.metadata.json'),
    ];
    final archivedOriginal = p.join(
      primary.path,
      'projects',
      'demo',
      'Main.java',
    );
    for (final name in metadataNames) {
      await write(
        p.join(primary.path, name),
        jsonEncode({'originalPath': archivedOriginal, 'name': 'Main.java'}),
      );
    }
    await write(
      p.join(primary.path, 'files_backup/demo/Main.java'),
      'OLD SOURCE',
    );
    expect(await File(p.join(primary.path, 'projects.json')).exists(), isFalse);
    final bundle = await AppBackupService.exportAll();
    AppBackupService.rootOverride = secondary.path;

    await AppBackupService.importAll(bundle.bytes);

    expect(
      await File(p.join(secondary.path, 'projects.json')).exists(),
      isFalse,
    );
    for (final name in metadataNames) {
      final metadata =
          jsonDecode(await File(p.join(secondary.path, name)).readAsString())
              as Map<String, dynamic>;
      expect(
        metadata['originalPath'],
        p.normalize(p.join(secondary.path, 'projects', 'demo', 'Main.java')),
      );
    }
    expect(
      await File(
        p.join(secondary.path, 'files_backup/demo/Main.java'),
      ).readAsString(),
      'OLD SOURCE',
    );
  });
}
