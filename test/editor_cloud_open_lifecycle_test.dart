// Regression sources for cloud CI. No network or native service is needed.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/config/api_config.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/models/cloud_project.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/cloud_cache_service.dart';
import 'package:qfli_studio_core/services/cloud_sync_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late CloudCacheService cache;
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late Project project;
  late CloudProjectScope scope;
  StudioProfile? previous;

  setUp(() async {
    previous = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'cloud-open-lifecycle',
      appTitle: 'Studio',
      templates: [],
      isOffline: false,
      productKey: StudioProductCatalog.qfliStudioKey,
    );
    root = await Directory.systemTemp.createTemp('editor-cloud-open-');
    cache = CloudCacheService(projectsRootOverride: root.path);
    scope = CloudProjectScope(
      origin: ApiConfig.origin,
      accountId: 'lifecycle-user',
    );
    project = Project.create(
      name: 'cloud',
      path: p.join(
        await cache.projectRoot(scope, 'proj_lifecycle'),
        'workspace',
      ),
      cloudId: 'proj_lifecycle',
      cloudOrigin: scope.origin,
      cloudAccountId: scope.accountId,
    );
    store = ProjectStore(storageFile: File(p.join(root.path, 'projects.json')));
    auth = AuthStore();
    settings = SettingsStore();
  });
  tearDown(() async {
    StudioProfile.current = previous;
    settings.dispose();
    store.dispose();
    auth.dispose();
    cache.dispose();
    // Drain the editor's queued session write before removing its owned fixture.
    await ProjectHistory.load(project.path);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Future<CloudSyncService> Function(Project) opener,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: project,
          auth: auth,
          store: store,
          settings: settings,
          cloudSyncOpener: opener,
        ),
      ),
    );
  }

  testWidgets('late cloud open after editor disposal releases activity lease', (
    tester,
  ) async {
    final gate = Completer<CloudSyncService>();
    final key = CloudWorkspaceActivity.key(scope, project.cloudId!);
    final service = await tester.runAsync(
      () => CloudSyncService.open(
        cloudId: project.cloudId!,
        name: project.name,
        scope: scope,
        session: CloudSession(
          scope: scope,
          token: 'test-only',
          isCurrent: () => true,
        ),
        cache: cache,
      ),
    );
    addTearDown(() => service?.dispose());
    expect(CloudWorkspaceActivity.active(key), isTrue);
    await mount(tester, (_) => gate.future);
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(service!);
    await tester.pump();
    expect(
      CloudWorkspaceActivity.active(key),
      isFalse,
      reason: 'A service returned after unmount never reaches page.dispose.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'asynchronous open failure is consumed without an activity lease',
    (tester) async {
      final gate = Completer<CloudSyncService>();
      await mount(tester, (_) => gate.future);
      gate.completeError(const FileSystemException('test open failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        CloudWorkspaceActivity.active(
          CloudWorkspaceActivity.key(scope, project.cloudId!),
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('synchronous opener failure does not escape initialization', (
    tester,
  ) async {
    await mount(
      tester,
      (_) => throw const FileSystemException('sync open failure'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'open failure after unmount neither sets state nor escapes Future',
    (tester) async {
      final gate = Completer<CloudSyncService>();
      await mount(tester, (_) => gate.future);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.completeError(const FileSystemException('late open failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        CloudWorkspaceActivity.active(
          CloudWorkspaceActivity.key(scope, project.cloudId!),
        ),
        isFalse,
      );
    },
  );
}
