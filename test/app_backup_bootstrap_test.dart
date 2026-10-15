import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_backup_service.dart';
import 'package:qfli_studio_core/services/app_restore_gate.dart';
import 'package:qfli_studio_core/splash_screen.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

class _Projects extends ProjectStore {
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

class _Auth extends AuthStore {
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

class _Settings extends SettingsStore {
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Projects projects;
  late _Auth auth;
  late _Settings settings;
  late ValueNotifier<bool> ready;
  final progress = <double>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-bootstrap-restore-');
    AppBackupService.rootOverride = root.path;
    projects = _Projects();
    auth = _Auth();
    settings = _Settings();
    ready = ValueNotifier(false);
    progress.clear();
  });

  tearDown(() async {
    AppRestoreGate.status.value = null;
    AppBackupService.rootOverride = null;
    AppBackupService.rootsResolverOverride = null;
    projects.dispose();
    auth.dispose();
    settings.dispose();
    ready.dispose();
    await root.delete(recursive: true);
  });

  Future<void> boot() => AppBootstrap.run(
    store: projects,
    auth: auth,
    settings: settings,
    ready: ready,
    onProgress: progress.add,
  );

  test('ordinary startup loads all stores with no restore gate', () async {
    await boot();
    expect([projects.loads, auth.loads, settings.loads], [1, 1, 1]);
    expect(ready.value, isTrue);
    expect(AppRestoreGate.status.value, isNull);
  });

  test('no restore traces skips strict private-root discovery', () async {
    var resolutions = 0;
    AppBackupService.rootsResolverOverride = (_) async {
      resolutions++;
      throw StateError('private provider unavailable');
    };

    await boot();

    expect(resolutions, 0);
    expect([projects.loads, auth.loads, settings.loads], [1, 1, 1]);
    expect(ready.value, isTrue);
    expect(AppRestoreGate.status.value, isNull);
  });

  test(
    'pending restore applies before stores and requires a fresh process',
    () async {
      await File(
        p.join(root.path, 'settings.json'),
      ).writeAsString('{"themeMode":"dark"}');
      final bundle = await AppBackupService.exportAll();
      await File(
        p.join(root.path, 'settings.json'),
      ).writeAsString('{"themeMode":"light"}');
      await AppBackupService.prepareImport(bundle.bytes);

      await boot();

      expect(
        await File(p.join(root.path, 'settings.json')).readAsString(),
        '{"themeMode":"dark"}',
      );
      expect([projects.loads, auth.loads, settings.loads], [0, 0, 0]);
      expect(ready.value, isTrue);
      expect(progress, [1.0]);
      expect(AppRestoreGate.status.value, AppRestoreStatus.completed);
      expect(await AppBackupService.hasPendingRestore(), isFalse);

      // A fresh process resets this in-memory gate. With the restore consumed,
      // normal startup can load the restored stores instead of gating forever.
      AppRestoreGate.status.value = null;
      ready.value = false;
      progress.clear();
      await boot();
      expect([projects.loads, auth.loads, settings.loads], [1, 1, 1]);
      expect(ready.value, isTrue);
      expect(AppRestoreGate.status.value, isNull);
      expect(
        await File(p.join(root.path, 'settings.json')).readAsString(),
        '{"themeMode":"dark"}',
      );
    },
  );

  test('failed restore never loads potentially partial stores', () async {
    final staging = await Directory(
      p.join(root.path, AppBackupService.stagingDirName),
    ).create();
    await Directory(p.join(staging.path, 'payload')).create();
    await File(
      p.join(staging.path, AppBackupService.pendingFileName),
    ).writeAsString('invalid');

    await boot();

    expect([projects.loads, auth.loads, settings.loads], [0, 0, 0]);
    expect(AppRestoreGate.status.value, AppRestoreStatus.needsRecovery);
    expect(ready.value, isTrue);
    expect(progress, [1.0]);
  });
}
