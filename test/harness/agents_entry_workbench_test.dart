@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/agents_entry.dart';
import 'package:qfli_studio_core/harness/ui/hub_chat_view.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';
import 'package:qfli_studio_core/shell/workbench_session_view.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import '../support/fake_harness_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  Future<void>? pendingOpen;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workbench_agents_entry_');
    store = ProjectStore(storageFile: File(p.join(temp.path, 'projects.json')));
    await store.load();
    auth = AuthStore();
    settings = SettingsStore();
    pendingOpen = null;
  });

  tearDown(() async {
    store.dispose();
    auth.dispose();
    settings.dispose();
    await temp.delete(recursive: true);
  });

  AgentsIndexRow row({
    String hostId = 'local',
    HarnessHostKind kind = HarnessHostKind.local,
    String? cwd,
  }) => AgentsIndexRow(
    session: fakeSession(hostId: hostId, id: 'session-1', cwd: cwd),
    hostLabel: 'Test host',
    hostKind: kind,
  );

  Future<Project> addProject(String name) async {
    final dir = Directory(p.join(temp.path, name))..createSync(recursive: true);
    final result = await store.addExisting(dir.path);
    return result.project!;
  }

  test(
    'workbench registers the original local directory and reuses it',
    () async {
      final dir = Directory(p.join(temp.path, 'unregistered'))..createSync();
      final source = File(p.join(dir.path, 'keep.txt'))
        ..writeAsStringSync('keep');
      final session = row(cwd: dir.path);

      final first = await resolveSessionProject(
        store,
        session,
        workbench: true,
      );
      final again = await resolveSessionProject(
        store,
        session,
        workbench: true,
      );

      expect(first, isNotNull);
      expect(p.equals(first!.path, dir.path), isTrue);
      expect(again?.id, first.id);
      expect(store.projects, hasLength(1));
      expect(source.readAsStringSync(), 'keep');
      final reloaded = ProjectStore(
        storageFile: File(p.join(temp.path, 'projects.json')),
      );
      await reloaded.load();
      expect(reloaded.projects.single.id, first.id);
      reloaded.dispose();
    },
  );

  test('workbench reuses the exact registered local project', () async {
    final project = await addProject('matched');
    await addProject('unrelated');
    final picked = await resolveSessionProject(
      store,
      row(cwd: p.join(project.path, '.', 'nested', '..')),
      workbench: true,
    );
    expect(picked?.id, project.id);
    expect(store.projects, hasLength(2));
  });

  test('missing cwd never falls back to another local project', () async {
    await addProject('unrelated');
    final picked = await resolveSessionProject(
      store,
      row(cwd: p.join(temp.path, 'missing')),
      workbench: true,
    );
    expect(picked, isNull);
    expect(store.projects, hasLength(1));
  });

  test('registered but deleted directory cannot open an editor', () async {
    final project = await addProject('deleted');
    await Directory(project.path).delete(recursive: true);
    final picked = await resolveSessionProject(
      store,
      row(cwd: project.path),
      workbench: true,
    );
    expect(picked, isNull);
    expect(store.projects.single.id, project.id);
  });

  test(
    'null, blank, relative and file cwd do not register a project',
    () async {
      final file = File(p.join(temp.path, 'not-a-directory'))
        ..writeAsStringSync('x');
      for (final cwd in <String?>[null, '', ' ', 'relative/path', file.path]) {
        expect(
          await resolveSessionProject(store, row(cwd: cwd), workbench: true),
          isNull,
        );
      }
      expect(store.projects, isEmpty);
    },
  );

  test('failed registration leaves the existing directory intact', () async {
    final directory = Directory(p.join(temp.path, 'cannot-register'))
      ..createSync();
    final source = File(p.join(directory.path, 'keep.txt'))
      ..writeAsStringSync('keep');
    final blocked = _RejectingProjectStore();
    final picked = await resolveSessionProject(
      blocked,
      row(cwd: directory.path),
      workbench: true,
    );
    expect(picked, isNull);
    expect(blocked.projects, isEmpty);
    expect(source.readAsStringSync(), 'keep');
    blocked.dispose();
  });

  for (final kind in [HarnessHostKind.remote, HarnessHostKind.studio]) {
    test(
      '$kind never resolves a matching path to an unrelated local project',
      () async {
        final local = await addProject('local');
        final hostId = kind == HarnessHostKind.studio ? 'studio' : 'remote:pc';
        final placeholder = Project(
          id: 'placeholder',
          name: 'Session',
          path: p.join(temp.path, 'session-cache'),
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
          deviceHostId: hostId,
          deviceSessionId: 'session-1',
          placeholder: true,
        );
        await store.registerDeviceProject(placeholder);
        final picked = await resolveSessionProject(
          store,
          row(hostId: hostId, kind: kind, cwd: local.path),
          workbench: true,
        );
        expect(picked?.id, placeholder.id);
        expect(picked?.id, isNot(local.id));
        expect(store.projects, hasLength(2));
      },
    );
  }

  test('phone resolver keeps its existing fallback by default', () async {
    final recent = await addProject('phone-project');
    final picked = await resolveSessionProject(
      store,
      row(cwd: p.join(temp.path, 'missing')),
    );
    expect(picked?.id, recent.id);
  });

  Future<void> pumpEntry(
    WidgetTester tester, {
    required AgentsIndexRow session,
    required LargeScreenController layout,
    required HarnessHub hub,
    required RetainedEditorController editors,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LargeScreenScope(
          controller: layout,
          child: RetainedEditorScope(
            controller: editors,
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () {
                        pendingOpen = openAgentSession(
                          context,
                          row: session,
                          auth: auth,
                          store: store,
                          settings: settings,
                          harnessHub: hub,
                        );
                      },
                      child: const Text('Open session'),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: layout,
                        builder: (context, _) {
                          final overlay = layout.centerOverlay;
                          return overlay == null
                              ? const Text('Original center')
                              : Builder(builder: overlay);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'missing project opens center chat and leaves navigation available',
    (tester) async {
      final unrelated = await tester.runAsync(() => addProject('unrelated'));
      final session = row(cwd: p.join(temp.path, 'missing'));
      final host = FakeHarnessHost(
        id: 'local',
        label: 'Local',
        kind: HarnessHostKind.local,
        initialSessions: [session.session],
      );
      final hub = HarnessHub(hosts: [host], desktop: true);
      final layout = LargeScreenController();
      final editors = RetainedEditorController();
      editors.setRootBackHandling(false);
      editors.open(
        project: unrelated!,
        auth: auth,
        store: store,
        settings: settings,
      );
      final activeEditor = editors.activeSessionKey;
      await pumpEntry(
        tester,
        session: session,
        layout: layout,
        hub: hub,
        editors: editors,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Open session'));
        await pendingOpen;
      });
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorkbenchSessionView), findsOneWidget);
      expect(find.byType(HubChatView), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('先打开一个项目'), findsNothing);
      expect(host.opened, ['session-1']);
      expect(editors.activeSessionKey, activeEditor);
      expect(store.projects.single.id, unrelated.id);
      expect(find.text('Open session'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('workbench-session-close')));
      await tester.pump();
      expect(layout.centerOverlay, isNull);
      expect(find.text('Original center'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      editors.dispose();
      layout.dispose();
      await hub.shutdown();
    },
  );

  testWidgets(
    'desktop local session registers directory and opens retained editor',
    (tester) async {
      final directory = Directory(p.join(temp.path, 'desktop-local'))
        ..createSync();
      final session = row(cwd: directory.path);
      final layout = LargeScreenController();
      final editors = RetainedEditorController()..setRootBackHandling(false);
      final hub = HarnessHub(hosts: const [], desktop: true);
      layout.showCenterOverlay((_) => const Text('Old overlay'));
      await pumpEntry(
        tester,
        session: session,
        layout: layout,
        hub: hub,
        editors: editors,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Open session'));
        await pendingOpen;
      });
      await tester.pump();
      expect(store.projects, hasLength(1));
      expect(editors.activeProject?.id, store.projects.single.id);
      expect(p.equals(editors.activeProject!.path, directory.path), isTrue);
      expect(layout.centerOverlay, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      editors.dispose();
      layout.dispose();
      await hub.shutdown();
    },
  );

  testWidgets('registration exception opens chat without opening an editor', (
    tester,
  ) async {
    final directory = Directory(p.join(temp.path, 'denied'))..createSync();
    final originalStore = store;
    store = _RejectingProjectStore(throwsOnRegistration: true);
    final session = row(cwd: directory.path);
    final host = FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session.session],
    );
    final hub = HarnessHub(hosts: [host], desktop: true);
    final layout = LargeScreenController();
    final editors = RetainedEditorController()..setRootBackHandling(false);
    await pumpEntry(
      tester,
      session: session,
      layout: layout,
      hub: hub,
      editors: editors,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Open session'));
      await pendingOpen;
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(HubChatView), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(editors.activeProject, isNull);
    expect(directory.existsSync(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    editors.dispose();
    layout.dispose();
    await hub.shutdown();
    store.dispose();
    store = originalStore;
  });

  testWidgets(
    'legacy Agents surface without projects selects workbench Agents',
    (tester) async {
      final layout = LargeScreenController();
      await tester.pumpWidget(
        MaterialApp(
          home: LargeScreenScope(
            controller: layout,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openAgentsSurface(
                    context,
                    auth: auth,
                    store: store,
                    settings: settings,
                  ),
                  child: const Text('Agents'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Agents'));
      await tester.pump();
      expect(layout.activity, WorkbenchActivity.agents);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      layout.dispose();
    },
  );
}

class _RejectingProjectStore extends ProjectStore {
  _RejectingProjectStore({this.throwsOnRegistration = false});

  final bool throwsOnRegistration;

  @override
  Future<ProjectResult> addExisting(String rawPath) async {
    if (throwsOnRegistration) {
      throw const FileSystemException('Permission denied');
    }
    return (error: 'Permission denied', project: null);
  }
}
