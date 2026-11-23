@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/sync/device_sync_launcher.dart';
import 'package:qfli_studio_core/sync/placeholder_project.dart';

Project _deviceProject({bool placeholder = true, bool pulled = false}) =>
    Project.create(name: '电脑会话', path: '/tmp/unused')
      ..deviceHostId = 'agent-42'
      ..deviceSessionId = 'session-1'
      ..deviceRoot = r'C:\work\proj'
      ..placeholder = placeholder
      ..filesPulled = pulled;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceSyncLauncher.canSync', () {
    test('a paired-computer project can sync', () {
      expect(DeviceSyncLauncher.canSync(_deviceProject()), isTrue);
    });

    test('a plain local project cannot sync', () {
      final project = Project.create(name: 'mine', path: '/tmp/x');
      expect(DeviceSyncLauncher.canSync(project), isFalse);
    });

    test('a cloud project cannot sync', () {
      final project = Project.create(
        name: 'cloud',
        path: '/tmp/y',
        cloudId: 'proj_1',
      );
      expect(DeviceSyncLauncher.canSync(project), isFalse);
    });

    test('a project without a host id cannot sync', () {
      final project = _deviceProject()..deviceHostId = null;
      expect(DeviceSyncLauncher.canSync(project), isFalse);
    });
  });

  group('device sync product gate', () {
    late StudioProfile? previous;

    setUp(() => previous = StudioProfile.current);
    tearDown(() => StudioProfile.current = previous);

    test('the offline product default is off', () {
      StudioProfile.current = const StudioProfile(
        id: 'c',
        appTitle: 'QFLIForge',
        templates: [],
        isOffline: true,
      );
      expect(StudioProfile.current!.deviceSyncEnabled, isFalse);
    });

    test('the main app enables the entry', () {
      StudioProfile.current = const StudioProfile(
        id: 'qflistudio',
        appTitle: 'QFLIStudioN',
        templates: [],
        isOffline: false,
        deviceSyncEnabled: true,
      );
      expect(StudioProfile.current!.deviceSyncEnabled, isTrue);
    });
  });

  group('placeholder reuse', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('qfli_wire_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('the same host and session map to one directory', () {
      final a = PlaceholderProjects.hostKey('agent-42');
      final b = PlaceholderProjects.hostKey('agent-42');
      expect(a, b);
    });

    test('discard keeps a project the user pulled files into', () async {
      final project = _deviceProject(placeholder: false, pulled: true);
      final dir = Directory(project.path)..createSync(recursive: true);
      await File('${dir.path}/main.dart').writeAsString('void main() {}');

      expect(
        await const PlaceholderProjects().discardIfUnused(project),
        isFalse,
      );
      expect(await dir.exists(), isTrue);
    });
  });

  group('AgentsIndexRow for a remote session', () {
    test('a remote row carries the host kind used by the fallback', () {
      const row = AgentsIndexRow(
        session: HarnessSessionInfo(
          id: 'session-1',
          hostId: 'agent-42',
          providerId: 'claude',
          title: '修复登录',
          status: HarnessSessionStatus.working,
          capabilities: <HarnessCapability>{HarnessCapability.transcript},
          cwd: r'C:\work\proj',
        ),
        hostLabel: '办公室电脑',
        hostKind: HarnessHostKind.remote,
      );
      expect(row.hostKind, HarnessHostKind.remote);
      expect(row.session.cwd, r'C:\work\proj');
    });
  });

  group('ProjectStore device lookup', () {
    test('a store with no device project returns null', () {
      final store = ProjectStore();
      addTearDown(store.dispose);
      expect(
        store.deviceProjectFor(hostId: 'agent-42', sessionId: 'session-1'),
        isNull,
      );
    });
  });
}
