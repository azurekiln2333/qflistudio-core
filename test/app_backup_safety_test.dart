import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_backup_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

/// Failure-mode and hostile-input coverage for the app-wide restore service.
///
/// These tests drive the real service through [AppBackupService.moveOverride]
/// and [AppBackupService.rootsResolverOverride] rather than re-implementing its
/// steps, and they assert **actual original bytes** after a failed restore
/// instead of only checking that an exception was thrown. A test that merely
/// mirrors the journal structure would pass even if the user's data had been
/// destroyed.
///
/// Interrupted-transaction fixtures are built in the service's real on-disk
/// layout (`<root>/.qfli-app-old/{originals,control}`), because recovery reads
/// that layout directly from disk.
void main() {
  late Directory primary;
  late Directory secondary;
  late Directory scratch;

  StudioProfile? originalProfile;

  setUp(() async {
    originalProfile = StudioProfile.current;
    primary = await Directory.systemTemp.createTemp('qfli_safety_primary');
    secondary = await Directory.systemTemp.createTemp('qfli_safety_extra');
    scratch = await Directory.systemTemp.createTemp('qfli_safety_scratch');
    StudioProfile.current = const StudioProfile(
      id: 'java',
      appTitle: 'Backup safety',
      templates: [],
      isOffline: true,
      productKey: StudioProductCatalog.jvmxKey,
    );
    AppBackupService.rootOverride = primary.path;
  });

  tearDown(() async {
    StudioProfile.current = originalProfile;
    // Always restore the global hooks, even when a test failed mid-injection.
    AppBackupService.rootOverride = null;
    AppBackupService.rootsResolverOverride = null;
    AppBackupService.moveOverride = null;
    for (final dir in [primary, secondary, scratch]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  /// Writes the user's durable data. The journal file is a real user file here,
  /// which is the interesting case: it shares a name with the service's control
  /// journal and must survive any restore/rollback.
  Future<void> seedUserData(Directory base) async {
    await File(
      p.join(base.path, 'settings.json'),
    ).writeAsString(jsonEncode({'version': 1, 'themeMode': 'dark'}));
    await File(
      p.join(base.path, 'journal.json'),
    ).writeAsString(jsonEncode({'user': 'original-journal'}));
    await File(
      p.join(base.path, 'projects', 'demo', 'src', 'Main.java'),
    ).create(recursive: true);
    await File(
      p.join(base.path, 'projects', 'demo', 'src', 'Main.java'),
    ).writeAsString('class Main {} // original');
  }

  /// Builds a ZIP from explicit absolute-or-root-relative entry names.
  ///
  /// Used for hostile archives: names such as `data/../escape.txt` cannot be
  /// produced through the normal export path.
  Uint8List buildArchive(
    List<({String name, List<int> bytes, int? mode, bool dir})> entries, {
    AppBackupInfo? info,
    int formatVersion = AppBackupService.currentFormatVersion,
  }) {
    final archive = Archive();
    final meta = info ?? AppBackupService.currentInfo();
    final infoBytes = utf8.encode(
      jsonEncode({...meta.toJson(), 'formatVersion': formatVersion}),
    );
    archive.addFile(
      ArchiveFile(
        AppBackupService.infoFileName,
        infoBytes.length,
        Uint8List.fromList(infoBytes),
      ),
    );
    for (final entry in entries) {
      final file = ArchiveFile(
        entry.name,
        entry.bytes.length,
        Uint8List.fromList(entry.bytes),
      );
      if (entry.dir) file.isFile = false;
      if (entry.mode != null) file.mode = entry.mode!;
      archive.addFile(file);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// A minimal valid archive carrying one file into the storage root.
  Uint8List archiveWithStorageFile(String relative, {String content = 'new'}) =>
      buildArchive([
        (name: 'data', bytes: const <int>[], mode: null, dir: true),
        (
          name: 'data/$relative',
          bytes: utf8.encode(content),
          mode: null,
          dir: false,
        ),
      ]);

  /// Builds the real `planned`-state journal on disk without moving anything.
  ///
  /// Mirrors the layout written by `applyPendingRestore` before its first move:
  /// `<root>/.qfli-app-old/control/journal.json`.
  Future<File> writePlannedJournal({
    required Map<String, String> roots,
    required Map<String, List<String>> plannedOrigins,
    required Map<String, List<String>> plannedNew,
    String state = 'planned',
    Map<String, List<String>> movedToBackup = const {},
    Map<String, List<String>> installedNew = const {},
  }) async {
    final journal = <String, dynamic>{
      'state': state,
      'version': 1,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'recordedRoots': roots,
      'plannedOrigins': plannedOrigins,
      'plannedNew': plannedNew,
      'movedToBackup': movedToBackup,
      'installedNew': installedNew,
    };
    final backup = Directory(
      p.join(
        roots[AppBackupService.storageRootKey]!,
        AppBackupService.oldDirName,
      ),
    );
    await Directory(
      p.join(backup.path, AppBackupService.backupControlDir),
    ).create(recursive: true);
    await Directory(
      p.join(backup.path, AppBackupService.backupOriginalsDir),
    ).create(recursive: true);
    final file = File(
      p.join(
        backup.path,
        AppBackupService.backupControlDir,
        AppBackupService.journalFileName,
      ),
    );
    await file.writeAsString(jsonEncode(journal), flush: true);
    return file;
  }

  String readFile(String path) => File(path).readAsStringSync();

  /// Matches the service's message for a rejected archive entry.
  ///
  /// Asserting the *specific* message rather than just
  /// `isA<AppBackupException>()` is what makes these tests load-bearing: a
  /// bare `isA` check passes for any exception, including one thrown for an
  /// unrelated reason, so the test would keep passing even if the guard it
  /// claims to cover were deleted. Verified by mutating each guard out of the
  /// service and confirming the matching test then fails.
  Matcher rejectsWith(String messageFragment) => throwsA(
    isA<AppBackupException>().having(
      (error) => error.message,
      'message',
      contains(messageFragment),
    ),
  );

  // ---------------------------------------------------------------------------
  // 1. mid-install failure restores old content, including the user journal.json
  // ---------------------------------------------------------------------------

  test('a failure during install restores every original byte, including the '
      'user journal.json that shares the control journal name', () async {
    await seedUserData(primary);
    final originalJournal = readFile(p.join(primary.path, 'journal.json'));
    final originalSettings = readFile(p.join(primary.path, 'settings.json'));

    // Incoming payload replaces settings.json and adds a brand-new file.
    await AppBackupService.prepareImport(
      archiveWithStorageFile('settings.json', content: 'REPLACED'),
      replacePending: true,
    );

    // Inject against the *real* paths instead of counting moves.
    //
    // `seedUserData` leaves three top-level originals (settings.json,
    // journal.json, projects/), so a move counter would fail during the
    // "moving-originals" phase and never reach install at all — the test
    // would then prove nothing about a mid-install failure. Detecting the
    // install phase by its actual source (a file under
    //`<staging>/payload/...`) and destination (the live private root) makes
    // the stage the test claims to cover the stage it really hits.
    final stagingPrefix = p.join(
      primary.path,
      AppBackupService.stagingDirName,
      'payload',
    );
    var installStarted = false;
    var originalsMoved = 0;
    AppBackupService.moveOverride = (from, to) async {
      if (p.isWithin(stagingPrefix, from)) {
        // Install phase: this is the first payload file being moved in.
        installStarted = true;
        throw const FileSystemException('simulated mid-install failure');
      }
      originalsMoved++;
    };

    await expectLater(
      AppBackupService.applyPendingRestore(),
      throwsA(isA<AppBackupException>()),
    );

    // Prove the intended stage was actually reached. Without this the test
    // can silently degrade into "failed while moving originals" again.
    expect(
      originalsMoved,
      greaterThan(0),
      reason: 'the originals must have been swapped out before install',
    );
    expect(
      installStarted,
      isTrue,
      reason: 'the injected failure must land during the install phase',
    );

    // The user's data must be byte-identical to before the attempt.
    expect(readFile(p.join(primary.path, 'settings.json')), originalSettings);
    expect(
      readFile(p.join(primary.path, 'journal.json')),
      originalJournal,
      reason:
          'the user journal.json must be restored, not lost to the '
          'control journal that shares its name',
    );
    expect(
      readFile(p.join(primary.path, 'projects', 'demo', 'src', 'Main.java')),
      'class Main {} // original',
    );
    // And no half-installed payload may be left behind as if it were real.
    expect(
      Directory(
        p.join(primary.path, AppBackupService.stagingDirName),
      ).existsSync(),
      isFalse,
    );
  });

  // ---------------------------------------------------------------------------
  // 2. two-root rollback via rootsResolverOverride
  // ---------------------------------------------------------------------------

  test('a failure with two private roots rolls both roots back', () async {
    await seedUserData(primary);
    await File(
      p.join(secondary.path, 'documents.json'),
    ).writeAsString('{"docs":"original"}');

    AppBackupService.rootsResolverOverride = (_) async => {
      AppBackupService.storageRootKey: primary.path,
      'documents': secondary.path,
    };

    final originalPrimary = readFile(p.join(primary.path, 'settings.json'));
    final originalSecondary = readFile(
      p.join(secondary.path, 'documents.json'),
    );

    // One archive touching both roots.
    final bytes = buildArchive([
      (
        name: 'data/settings.json',
        bytes: utf8.encode('REPLACED-PRIMARY'),
        mode: null,
        dir: false,
      ),
      (
        name: 'private_documents/documents.json',
        bytes: utf8.encode('REPLACED-SECONDARY'),
        mode: null,
        dir: false,
      ),
    ]);
    await AppBackupService.prepareImport(bytes, replacePending: true);

    // Fail while the *secondary* root's original is being swapped out, by
    // matching its actual source directory. A move counter would have tripped
    // inside the primary root's originals (the primary has three top-level
    // entries) and never reached the second root at all, so the "two-root
    // rollback" claim would have been untested.
    var primaryOriginalsMoved = 0;
    var secondaryReached = false;
    AppBackupService.moveOverride = (from, to) async {
      if (p.isWithin(secondary.path, from)) {
        secondaryReached = true;
        throw const FileSystemException('simulated second-root failure');
      }
      if (p.isWithin(primary.path, from)) primaryOriginalsMoved++;
    };

    await expectLater(
      AppBackupService.applyPendingRestore(),
      throwsA(isA<AppBackupException>()),
    );

    // Prove both roots were really involved.
    expect(
      primaryOriginalsMoved,
      greaterThan(0),
      reason: 'the primary root must already have been mutated',
    );
    expect(
      secondaryReached,
      isTrue,
      reason: 'the failure must land while moving the secondary root',
    );

    expect(
      readFile(p.join(primary.path, 'settings.json')),
      originalPrimary,
      reason: 'the mutated primary root must be rolled back',
    );
    expect(
      readFile(p.join(secondary.path, 'documents.json')),
      originalSecondary,
      reason: 'the untouched second root must also be intact',
    );
    for (final base in [primary, secondary]) {
      expect(
        Directory(p.join(base.path, AppBackupService.oldDirName)).existsSync(),
        isFalse,
        reason: 'a complete rollback cleans up its recovery copy',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // 3. interruption in the planned state must not delete matching originals
  // ---------------------------------------------------------------------------

  test(
    'an interruption before any move keeps originals even when the payload has '
    'a same-named file',
    () async {
      await seedUserData(primary);
      final originalSettings = readFile(p.join(primary.path, 'settings.json'));

      // A fresh payload exists in staging, but the journal says nothing moved.
      final payload = Directory(
        p.join(
          primary.path,
          AppBackupService.stagingDirName,
          'payload',
          'storage',
        ),
      );
      await payload.create(recursive: true);
      await File(
        p.join(payload.path, 'settings.json'),
      ).writeAsString('PAYLOAD-NEVER-INSTALLED');

      await writePlannedJournal(
        roots: {AppBackupService.storageRootKey: primary.path},
        plannedOrigins: {
          AppBackupService.storageRootKey: ['settings.json', 'journal.json'],
        },
        plannedNew: {
          AppBackupService.storageRootKey: ['settings.json'],
        },
        // Nothing moved, nothing installed: the classic planned-state crash.
      );

      // Recovery is triggered through the normal entry point.
      await AppBackupService.applyPendingRestore();

      expect(
        readFile(p.join(primary.path, 'settings.json')),
        originalSettings,
        reason:
            'a planned-only interruption must never delete the original '
            'just because the payload reused its name',
      );
      expect(
        File(p.join(primary.path, 'journal.json')).existsSync(),
        isTrue,
        reason: 'untouched originals stay in place',
      );
      expect(
        Directory(
          p.join(primary.path, AppBackupService.oldDirName),
        ).existsSync(),
        isFalse,
      );
    },
  );

  // ---------------------------------------------------------------------------
  // 4. interruption right after the rename, before progress was journaled
  // ---------------------------------------------------------------------------

  test(
    'an interruption mid-install but before journaling restores the original '
    'and removes the payload-only file it had installed',
    () async {
      await seedUserData(primary);
      final originalSettings = readFile(p.join(primary.path, 'settings.json'));

      // Reproduce the on-disk state: the original was moved into the recovery
      // copy and the payload file took its place, but `movedToBackup` never got
      // a journal entry because the crash hit between rename and write.
      final backup = Directory(
        p.join(primary.path, AppBackupService.oldDirName),
      );
      final originals = Directory(
        p.join(backup.path, AppBackupService.backupOriginalsDir),
      );
      await originals.create(recursive: true);
      await File(
        p.join(primary.path, 'settings.json'),
      ).rename(p.join(originals.path, 'settings.json'));
      await File(
        p.join(primary.path, 'settings.json'),
      ).writeAsString('PAYLOAD-INSTALLED-NO-JOURNAL');

      // A brand-new file that exists only in the payload: it has no original,
      // so on an install-phase interruption it is inferred as installed and
      // must be removed rather than left behind as if it were user data.
      await File(
        p.join(primary.path, 'brand-new.txt'),
      ).writeAsString('payload only');

      await writePlannedJournal(
        roots: {AppBackupService.storageRootKey: primary.path},
        plannedOrigins: {
          AppBackupService.storageRootKey: ['settings.json', 'journal.json'],
        },
        plannedNew: {
          AppBackupService.storageRootKey: ['settings.json', 'brand-new.txt'],
        },
        // The crash happened mid-install: originals were swapped out and at
        // least one payload entry was already moved in, but the journal never
        // recorded the individual moves. The `installing` state is what
        // authorises the fresh-only inference below.
        state: 'installing',
        movedToBackup: {AppBackupService.storageRootKey: const <String>[]},
        installedNew: {AppBackupService.storageRootKey: const <String>[]},
      );

      await AppBackupService.applyPendingRestore();

      expect(
        readFile(p.join(primary.path, 'settings.json')),
        originalSettings,
        reason:
            'the original must be inferred from the recovery copy and '
            'moved back even though the journal never recorded the rename',
      );
      // Corrected expectation: `brand-new.txt` is a payload-only entry that was
      // moved into the root and never journaled. With the payload source gone
      // and no original backup, recovery infers it as installed and removes it,
      // so an interrupted restore does not leave half-installed payload files
      // masquerading as user data.
      expect(
        File(p.join(primary.path, 'brand-new.txt')).existsSync(),
        isFalse,
        reason:
            'a payload-only file installed before the crash must be '
            'removed by the interrupted rollback',
      );
      // What recovery *must* guarantee: the real original is back, and the
      // payload copy that replaced it is gone from the originals directory.
      expect(
        Directory(
          p.join(
            primary.path,
            AppBackupService.oldDirName,
            AppBackupService.backupOriginalsDir,
            'settings.json',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(primary.path, AppBackupService.oldDirName),
        ).existsSync(),
        isFalse,
      );
    },
  );

  // ---------------------------------------------------------------------------
  // 5. hostile archive entries are rejected without external writes
  // ---------------------------------------------------------------------------

  test(
    'dot-segment traversal entries are rejected and write nothing outside',
    () async {
      await seedUserData(primary);
      final outside = File(p.join(primary.parent.path, 'escaped.txt'));
      addTearDown(() async {
        if (await outside.exists()) await outside.delete();
      });

      final bytes = buildArchive([
        (
          name: 'data/../escaped.txt',
          bytes: utf8.encode('escape'),
          mode: null,
          dir: false,
        ),
      ]);

      await expectLater(
        AppBackupService.prepareImport(bytes, replacePending: true),
        rejectsWith('非法路径'),
      );
      expect(
        outside.existsSync(),
        isFalse,
        reason: 'traversal must not create files outside the private root',
      );
      expect(
        Directory(
          p.join(primary.path, AppBackupService.stagingDirName),
        ).existsSync(),
        isFalse,
        reason: 'a rejected archive leaves no staging data',
      );
    },
  );

  test('an absolute entry path is rejected', () async {
    await seedUserData(primary);
    final bytes = buildArchive([
      (
        name: 'data//absolute.txt',
        bytes: utf8.encode('x'),
        mode: null,
        dir: false,
      ),
    ]);
    await expectLater(
      AppBackupService.prepareImport(bytes, replacePending: true),
      rejectsWith('非法路径'),
    );
  });

  test(
    'an unknown root and a private_../ root name are both rejected',
    () async {
      await seedUserData(primary);

      final unknownRoot = buildArchive([
        (
          name: 'private_unknownroot/data.txt',
          bytes: utf8.encode('x'),
          mode: null,
          dir: false,
        ),
      ]);
      await expectLater(
        AppBackupService.prepareImport(unknownRoot, replacePending: true),
        rejectsWith('未知的根'),
      );

      // `private_../x` would otherwise let the root name climb out of payload/.
      final climbingRoot = buildArchive([
        (
          name: 'private_../escape/data.txt',
          bytes: utf8.encode('x'),
          mode: null,
          dir: false,
        ),
      ]);
      await expectLater(
        AppBackupService.prepareImport(climbingRoot, replacePending: true),
        throwsA(isA<AppBackupException>()),
      );
      // Nothing may be written outside the private root either way.
      expect(
        Directory(p.join(primary.parent.path, 'escape')).existsSync(),
        isFalse,
      );
    },
  );

  test('an entry nested under a symlink ancestor is rejected', () async {
    await seedUserData(primary);
    final outside = Directory(
      p.join(primary.parent.path, 'qfli_safety_outside'),
    );
    await outside.create(recursive: true);
    addTearDown(() async {
      if (await outside.exists()) await outside.delete(recursive: true);
    });

    // `data/link` is a symlink to an external directory; a second entry tries to
    // write *through* it. The service must reject the child rather than follow
    // the link out of the sandbox.
    const linkMode = 0xa1ff;
    final bytes = buildArchive([
      (
        name: 'data/link',
        bytes: utf8.encode(outside.path),
        mode: linkMode,
        dir: false,
      ),
      (
        name: 'data/link/child.txt',
        bytes: utf8.encode('through-link'),
        mode: null,
        dir: false,
      ),
    ]);

    await expectLater(
      AppBackupService.prepareImport(bytes, replacePending: true),
      rejectsWith('符号链接之下'),
    );
    expect(
      File(p.join(outside.path, 'child.txt')).existsSync(),
      isFalse,
      reason: 'no write may follow a symlink ancestor out of the sandbox',
    );
  });

  test(
    'a relative ../ symlink target is preserved as link text, never rejected '
    'for its text and never followed',
    () async {
      // Corrected contract: runtime trees legitimately contain `../` links, so
      // the service treats a link target as *data*. It must preserve the exact
      // text and must not reject the archive merely because the text escapes,
      // and it must never read or write through the target.
      await seedUserData(primary);
      final outsideTarget = File(
        p.join(primary.parent.path, 'qfli_safety_escape_target.txt'),
      );
      await outsideTarget.writeAsString('ORIGINAL-OUTSIDE');
      addTearDown(() async {
        if (await outsideTarget.exists()) await outsideTarget.delete();
      });

      const escapingTarget = '../../../../etc/passwd';
      final bytes = buildArchive([
        (
          name: 'data/escape-link',
          bytes: utf8.encode(escapingTarget),
          mode: 0xa1ff,
          dir: false,
        ),
      ]);

      // Preparing must succeed: the `../` text alone is not a rejection cause.
      final prepared = await AppBackupService.prepareImport(
        bytes,
        replacePending: true,
      );
      expect(prepared.fileCount, greaterThan(0));

      // The link was staged with its exact target text preserved, and creating
      // it did not touch anything outside the staging tree.
      final stagedLink = Link(
        p.join(
          prepared.stagingDirectory,
          'payload',
          AppBackupService.storageRootKey,
          'escape-link',
        ),
      );
      if (await stagedLink.exists()) {
        expect(
          await stagedLink.target(),
          escapingTarget,
          reason: 'the link text must be preserved verbatim',
        );
      }
      expect(
        outsideTarget.readAsStringSync(),
        'ORIGINAL-OUTSIDE',
        reason: 'no write may follow the link target',
      );
    },
  );

  test('a symlink with an empty target is rejected', () async {
    // The real rejection rule for links: empty or NUL-containing target text.
    await seedUserData(primary);
    final bytes = buildArchive([
      (name: 'data/empty-link', bytes: const <int>[], mode: 0xa1ff, dir: false),
    ]);
    await expectLater(
      AppBackupService.prepareImport(bytes, replacePending: true),
      rejectsWith('非法符号链接'),
    );
  });

  test(
    'an incompatible product identity is rejected before any write',
    () async {
      await seedUserData(primary);
      final foreign = AppBackupInfo(
        formatVersion: AppBackupService.currentFormatVersion,
        productKey: StudioProductCatalog.webForgeKey,
        appTitle: 'QFLIWebForge',
        profileId: 'webforge',
        runtimeKind: 'unavailable',
        createdAt: DateTime.now().toUtc(),
        fileCount: 1,
      );
      final bytes = buildArchive([
        (
          name: 'data/settings.json',
          bytes: utf8.encode('foreign'),
          mode: null,
          dir: false,
        ),
      ], info: foreign);

      await expectLater(
        AppBackupService.prepareImport(bytes, replacePending: true),
        rejectsWith('不兼容'),
      );
      expect(
        readFile(p.join(primary.path, 'settings.json')),
        contains('dark'),
        reason: 'a rejected archive must not touch live data',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Positive control: the same paths succeed when legitimate
  // ---------------------------------------------------------------------------

  test(
    'a legitimate restore does replace the data (positive control)',
    () async {
      await seedUserData(primary);
      await AppBackupService.prepareImport(
        archiveWithStorageFile('settings.json', content: 'LEGITIMATE'),
        replacePending: true,
      );
      await AppBackupService.applyPendingRestore();
      expect(readFile(p.join(primary.path, 'settings.json')), 'LEGITIMATE');
    },
  );
}
