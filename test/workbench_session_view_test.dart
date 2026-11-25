import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/agents_entry.dart';
import 'package:qfli_studio_core/harness/ui/hub_chat_view.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/workbench_session_view.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import 'support/fake_harness_host.dart';

void main() {
  final session = fakeSession(hostId: 'local', id: 'a', title: 'Session A');
  final row = AgentsIndexRow(
    session: session,
    hostLabel: 'Test computer',
    hostKind: HarnessHostKind.local,
  );

  Future<void> mount(
    WidgetTester tester,
    HarnessHub hub, {
    VoidCallback? onClose,
    AgentsIndexRow? selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkbenchSessionView(
            row: selected ?? row,
            hub: hub,
            onClose: onClose ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows title, host and real chat handle without an editor', (
    tester,
  ) async {
    final handle = FakeSessionHandle(info: session);
    final host = FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session],
      openHandler: (_) async => handle,
    );
    final hub = HarnessHub(hosts: [host], desktop: true);
    var closes = 0;
    await mount(tester, hub, onClose: () => closes++);
    expect(find.text('Session A'), findsOneWidget);
    expect(find.text('Test computer'), findsOneWidget);
    expect(
      tester.widget<HubChatView>(find.byType(HubChatView)).handle,
      same(handle),
    );

    handle.addEvent(
      const TranscriptEvent(
        id: 'event-1',
        role: TranscriptRole.assistant,
        text: 'Real transcript',
      ),
    );
    // The async transcript stream schedules its rebuild during the first pump.
    // Draw that frame before checking the rendered selectable message.
    await tester.pump();
    await tester.pump();
    expect(find.text('Real transcript'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workbench-session-close')));
    await tester.pump();
    expect(closes, 1);
    expect(handle.detachCount, 1);
    expect(handle.stopCount, 0);
    expect(host.disposeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(handle.detachCount, 1);
    await hub.shutdown();
  });

  testWidgets('failed handle shows reason and retry reconnects', (
    tester,
  ) async {
    var attempts = 0;
    final handle = FakeSessionHandle(info: session);
    final host = FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session],
      openHandler: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('Host is offline');
        return handle;
      },
    );
    final hub = HarnessHub(hosts: [host], desktop: true);
    await mount(tester, hub);
    expect(find.textContaining('Host is offline'), findsOneWidget);
    expect(find.byType(HubChatView), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workbench-session-retry')));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(HubChatView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(handle.detachCount, 1);
    expect(handle.stopCount, 0);
    await hub.shutdown();
  });

  testWidgets(
    'missing host gives actionable failure rather than a project dialog',
    (tester) async {
      final hub = HarnessHub(hosts: const [], desktop: true);
      await mount(tester, hub);
      expect(find.textContaining('找不到主机'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench-session-retry')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await hub.shutdown();
    },
  );

  testWidgets('center overlay follows a replacement shared hub', (
    tester,
  ) async {
    final firstHandle = FakeSessionHandle(info: session);
    final secondHandle = FakeSessionHandle(info: session);
    FakeHarnessHost hostFor(FakeSessionHandle handle) => FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session],
      openHandler: (_) async => handle,
    );
    final firstHub = HarnessHub(hosts: [hostFor(firstHandle)], desktop: true);
    final secondHub = HarnessHub(hosts: [hostFor(secondHandle)], desktop: true);
    final layout = LargeScreenController();
    final auth = AuthStore();
    final store = ProjectStore();
    final settings = SettingsStore();
    var selectedHub = firstHub;
    Future<void>? pending;
    await tester.pumpWidget(
      MaterialApp(
        home: LargeScreenScope(
          controller: layout,
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () {
                      pending = openAgentSession(
                        context,
                        row: AgentsIndexRow(
                          session: session,
                          hostLabel: 'Local',
                          hostKind: HarnessHostKind.local,
                        ),
                        auth: auth,
                        store: store,
                        settings: settings,
                        harnessHub: selectedHub,
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
                            ? const SizedBox.shrink()
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
    );

    Future<void> openSelectedHub() async {
      await tester.runAsync(() async {
        await tester.tap(find.text('Open session'));
        await pending;
      });
      await tester.pump();
      await tester.pump();
    }

    await openSelectedHub();
    expect(firstHub.activeHandle, same(firstHandle));
    selectedHub = secondHub;
    await openSelectedHub();

    expect(firstHandle.detachCount, 1);
    expect(firstHub.activeHandle, isNull);
    expect(secondHub.activeHandle, same(secondHandle));
    expect(find.byType(HubChatView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    layout.dispose();
    store.dispose();
    auth.dispose();
    settings.dispose();
    await firstHub.shutdown();
    await secondHub.shutdown();
  });

  testWidgets('removing overlay does not close a newer shared-hub session', (
    tester,
  ) async {
    final other = fakeSession(hostId: 'local', id: 'b', title: 'Session B');
    final first = FakeSessionHandle(info: session);
    final second = FakeSessionHandle(info: other);
    final host = FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session, other],
      openHandler: (id) async => id == session.id ? first : second,
    );
    final hub = HarnessHub(hosts: [host], desktop: true);
    await mount(tester, hub);
    await hub.openSession(other);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(hub.activeHandle, same(second));
    expect(first.detachCount, 1);
    expect(second.detachCount, 0);
    await hub.shutdown();
  });

  testWidgets('an open completing after disposal detaches without stopping', (
    tester,
  ) async {
    final opening = Completer<HarnessSessionHandle>();
    final handle = FakeSessionHandle(info: session);
    final host = FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session],
      openHandler: (_) => opening.future,
    );
    final hub = HarnessHub(hosts: [host], desktop: true);
    await mount(tester, hub);
    expect(
      find.byKey(const ValueKey('workbench-session-loading')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    opening.complete(handle);
    await tester.pump();
    await tester.pump();
    expect(handle.detachCount, 1);
    expect(handle.stopCount, 0);
    expect(hub.activeHandle, isNull);
    expect(tester.takeException(), isNull);
    await hub.shutdown();
  });

  testWidgets('close during opening returns immediately and later detaches', (
    tester,
  ) async {
    final opening = Completer<HarnessSessionHandle>();
    final handle = FakeSessionHandle(info: session);
    final host = FakeHarnessHost(
      id: 'local',
      label: 'Local',
      kind: HarnessHostKind.local,
      initialSessions: [session],
      openHandler: (_) => opening.future,
    );
    final hub = HarnessHub(hosts: [host], desktop: true);
    var closes = 0;
    await mount(tester, hub, onClose: () => closes++);
    await tester.tap(find.byKey(const ValueKey('workbench-session-close')));
    expect(closes, 1);
    opening.complete(handle);
    await tester.pump();
    await tester.pump();
    expect(handle.detachCount, 1);
    expect(handle.stopCount, 0);
    expect(hub.activeHandle, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await hub.shutdown();
  });

  testWidgets(
    'switch during opening waits for the previous open and selects the new session',
    (tester) async {
      final opening = Completer<HarnessSessionHandle>();
      final other = fakeSession(hostId: 'local', id: 'b', title: 'Session B');
      final first = FakeSessionHandle(info: session);
      final second = FakeSessionHandle(info: other);
      final host = FakeHarnessHost(
        id: 'local',
        label: 'Local',
        kind: HarnessHostKind.local,
        initialSessions: [session, other],
        openHandler: (id) =>
            id == session.id ? opening.future : Future.value(second),
      );
      final hub = HarnessHub(hosts: [host], desktop: true);
      await mount(tester, hub);
      await mount(
        tester,
        hub,
        selected: AgentsIndexRow(
          session: other,
          hostLabel: 'Test computer',
          hostKind: HarnessHostKind.local,
        ),
      );
      opening.complete(first);
      await tester.pump();
      await tester.pump();
      expect(host.opened, ['a', 'b']);
      expect(find.byType(HubChatView), findsOneWidget);
      expect(
        tester.widget<HubChatView>(find.byType(HubChatView)).handle,
        same(second),
      );
      expect(first.detachCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await hub.shutdown();
    },
  );

  testWidgets(
    'changing sessions rebinds chat and clears the previous transcript',
    (tester) async {
      final other = fakeSession(hostId: 'local', id: 'b', title: 'Session B');
      final first = FakeSessionHandle(info: session);
      final second = FakeSessionHandle(info: other);
      final host = FakeHarnessHost(
        id: 'local',
        label: 'Local',
        kind: HarnessHostKind.local,
        initialSessions: [session, other],
        openHandler: (id) async => id == session.id ? first : second,
      );
      final hub = HarnessHub(hosts: [host], desktop: true);
      await mount(tester, hub);
      first.addEvent(
        const TranscriptEvent(
          id: 'old',
          role: TranscriptRole.assistant,
          text: 'Previous transcript',
        ),
      );
      // Deliver the async stream event, then draw its scheduled chat frame.
      await tester.pump();
      await tester.pump();
      expect(find.text('Previous transcript'), findsOneWidget);
      await mount(
        tester,
        hub,
        selected: AgentsIndexRow(
          session: other,
          hostLabel: 'Test computer',
          hostKind: HarnessHostKind.local,
        ),
      );
      expect(find.text('Session B'), findsOneWidget);
      expect(find.text('Previous transcript'), findsNothing);
      expect(
        tester.widget<HubChatView>(find.byType(HubChatView)).handle,
        same(second),
      );
      expect(first.detachCount, 1);
      second.addEvent(
        const TranscriptEvent(
          id: 'new',
          role: TranscriptRole.assistant,
          text: 'Replacement transcript',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Replacement transcript'), findsOneWidget);
      expect(find.text('Previous transcript'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await hub.shutdown();
    },
  );
}
