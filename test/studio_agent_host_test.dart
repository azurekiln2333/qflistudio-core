import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/studio/studio_agent_host.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

import 'support/fake_agent.dart';

void main() {
  late FakeAgentRuntime runtime;
  late MemoryAgentSessionStore store;
  late StudioAgentHost host;

  setUp(() async {
    store = MemoryAgentSessionStore();
    runtime = FakeAgentRuntime(sessions: store);
    host = StudioAgentHost(
      runtime: runtime,
      projectId: 'p1',
      projectRoot: '/tmp/project',
    );
  });

  tearDown(() async {
    await host.dispose();
  });

  Future<HarnessSessionInfo> seedSession({String title = '会话一'}) async {
    final meta = await store.create('p1', title: title);
    return HarnessSessionInfo(
      id: meta.id,
      hostId: host.id,
      providerId: kStudioProviderId,
      title: meta.title,
      status: HarnessSessionStatus.idle,
      capabilities: const {},
    );
  }

  group('host identity', () {
    test('is the studio host with one built-in provider', () async {
      expect(host.id, kStudioHostId);
      expect(host.kind, HarnessHostKind.studio);
      expect(host.state.value, HarnessHostState.online);
      final providers = await host.providers();
      expect(providers.single.id, kStudioProviderId);
      expect(providers.single.available, isTrue);
    });
  });

  group('session list', () {
    test('lists this project sessions with status and cwd', () async {
      await seedSession(title: '甲');
      runtime.liveStatuses['session-0'] = AgentLiveStatus.running;
      final first = await host.watchSessions().first;
      expect(first, hasLength(1));
      expect(first.single.title, '甲');
      expect(first.single.hostId, kStudioHostId);
      expect(first.single.cwd, '/tmp/project');
      expect(first.single.status, HarnessSessionStatus.working);
      expect(first.single.capabilities, {
        HarnessCapability.transcript,
        HarnessCapability.prompt,
        HarnessCapability.approve,
        HarnessCapability.stop,
      });
    });

    test('never mixes in another project', () async {
      await store.create('p1', title: '本项目');
      await store.create('p2', title: '别的项目');
      final list = await host.watchSessions().first;
      expect(list.map((session) => session.title), ['本项目']);
    });

    test('pushes a new list when a session appears', () async {
      final events = <List<HarnessSessionInfo>>[];
      final subscription = host.watchSessions().listen(events.add);
      await pumpEventQueue();
      await store.create('p1', title: '新会话');
      await pumpEventQueue();
      expect(events, isNotEmpty);
      expect(events.last.map((session) => session.title), contains('新会话'));
      await subscription.cancel();
    });
  });

  group('status mapping', () {
    test('maps every runtime status without inventing progress', () async {
      await seedSession();
      final expected = {
        AgentLiveStatus.idle: HarnessSessionStatus.idle,
        AgentLiveStatus.queued: HarnessSessionStatus.working,
        AgentLiveStatus.running: HarnessSessionStatus.working,
        AgentLiveStatus.awaitingApproval: HarnessSessionStatus.blocked,
        AgentLiveStatus.finishedUnread: HarnessSessionStatus.done,
        AgentLiveStatus.failed: HarnessSessionStatus.unknown,
      };
      for (final entry in expected.entries) {
        runtime.liveStatuses['session-0'] = entry.key;
        final list = host.snapshot();
        expect(list.single.status, entry.value, reason: entry.key.name);
      }
    });
  });

  group('open and view', () {
    test('exposes the transcript, prompt and stop', () async {
      await seedSession();
      final handle = await host.open('session-0');
      expect(handle.terminal, isNull);
      expect(handle.transcript, isNotNull);
      expect(handle.info.title, '会话一');
      expect(runtime.openedSessions, ['session-0']);

      final events = <TranscriptEvent>[];
      final subscription = handle.transcript!.listen(events.add);
      await pumpEventQueue();

      await handle.sendPrompt('写一个页面');
      await pumpEventQueue();
      expect(events.map((event) => event.text), contains('写一个页面'));

      await handle.stop();
      expect(runtime.facades['session-0']!.cancelCount, 1);
      await subscription.cancel();
      await handle.detach();
    });

    test('emits an approval entry and resolves it by reply', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      final events = <TranscriptEvent>[];
      final subscription = handle.transcript!.listen(events.add);
      await pumpEventQueue();

      facade.pendingApproval = const AgentWriteApproval(
        path: 'lib/main.dart',
        summary: '写入 20 B',
      );
      await pumpEventQueue();
      final approval = events.where((e) => e.requestId != null).last;
      expect(approval.options, ['allow', 'deny']);

      await handle.reply(
        HarnessReply(requestId: approval.requestId!, choice: 'allow'),
      );
      expect(facade.approvals, [true]);

      await subscription.cancel();
      await handle.detach();
    });

    test('deny resolves the approval as a rejection', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      final events = <TranscriptEvent>[];
      final subscription = handle.transcript!.listen(events.add);
      await pumpEventQueue();
      facade.pendingApproval = const AgentWriteApproval(
        path: 'a.txt',
        summary: '写入 1 B',
      );
      await pumpEventQueue();
      final approval = events.where((e) => e.requestId != null).last;

      await handle.reply(
        HarnessReply(requestId: approval.requestId!, choice: 'deny'),
      );
      expect(facade.approvals, [false]);
      await subscription.cancel();
      await handle.detach();
    });

    test('ignores a reply with a stale request id', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      facade.pendingApproval = const AgentWriteApproval(
        path: 'b.txt',
        summary: '写入 2 B',
      );
      await pumpEventQueue();

      await handle.reply(
        const HarnessReply(requestId: 'approval:old-key', choice: 'allow'),
      );

      expect(facade.approvals, isEmpty);
      expect(facade.pendingApproval, isNotNull);
      await handle.detach();
    });

    test('rejects an unknown choice instead of silently denying', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      final events = <TranscriptEvent>[];
      final subscription = handle.transcript!.listen(events.add);
      await pumpEventQueue();
      facade.pendingApproval = const AgentWriteApproval(
        path: 'c.txt',
        summary: '写入 3 B',
      );
      await pumpEventQueue();
      final approval = events.where((e) => e.requestId != null).last;

      await expectLater(
        handle.reply(
          HarnessReply(requestId: approval.requestId!, choice: 'maybe'),
        ),
        throwsArgumentError,
      );
      expect(facade.approvals, isEmpty);
      await subscription.cancel();
      await handle.detach();
    });

    test('refuses to send a prompt while the session is busy', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      facade.state = AgentRunState.running;

      await expectLater(handle.sendPrompt('再来一次'), throwsStateError);
      expect(facade.sentTexts, isEmpty);
      await handle.detach();
    });

    test('detach releases the view without cancelling the session', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      await handle.detach();
      expect(facade.cancelCount, 0);
      expect(handle.transcript, isNull);
      // 再 detach 一次不报错。
      await handle.detach();
    });

    test(
      'status follows the runtime even without a facade notification',
      () async {
        await seedSession();
        final handle = await host.open('session-0');
        // 只发运行时通知：排队进出与“完成/失败未读”只在这一侧变化。
        runtime.liveStatuses['session-0'] = AgentLiveStatus.awaitingApproval;
        runtime.notifyLive();
        expect(handle.status.value, HarnessSessionStatus.blocked);

        runtime.liveStatuses['session-0'] = AgentLiveStatus.finishedUnread;
        runtime.notifyLive();
        expect(handle.status.value, HarnessSessionStatus.done);
        await handle.detach();
      },
    );

    test('publishes a system entry when the run fails', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final facade = runtime.facades['session-0']!;
      final events = <TranscriptEvent>[];
      final subscription = handle.transcript!.listen(events.add);
      await pumpEventQueue();

      runtime.liveStatuses['session-0'] = AgentLiveStatus.failed;
      facade.seedError(message: '余额不足');
      // 流是异步投递的：通知发出去以后要等微任务队列，否则读到的还是空列表。
      await pumpEventQueue();

      final failure = events.where((e) => e.text == '余额不足').single;
      expect(failure.role, TranscriptRole.system);
      expect(handle.status.value, HarnessSessionStatus.unknown);
      await subscription.cancel();
      await handle.detach();
    });
  });

  group('launch', () {
    test('creates a new session and opens it', () async {
      final handle = await host.launch(
        const HarnessLaunchRequest(
          providerId: kStudioProviderId,
          cwd: '/tmp/project',
          title: '新任务',
        ),
      );
      expect(handle.info.title, '新任务');
      expect(runtime.openedSessions, hasLength(1));
      expect(host.snapshot().single.title, '新任务');
      await handle.detach();
    });

    test('refuses a provider that is not the built-in agent', () async {
      await expectLater(
        host.launch(
          const HarnessLaunchRequest(providerId: 'claude', cwd: '/tmp/x'),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a working directory outside the project', () async {
      await expectLater(
        host.launch(
          const HarnessLaunchRequest(
            providerId: kStudioProviderId,
            cwd: '/tmp/other-project',
          ),
        ),
        throwsUnsupportedError,
      );
      expect(host.snapshot(), isEmpty);
    });

    test('refuses launch arguments instead of ignoring them', () async {
      await expectLater(
        host.launch(
          const HarnessLaunchRequest(
            providerId: kStudioProviderId,
            cwd: '/tmp/project',
            args: ['--model', 'x'],
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('leaves no session record when the agent is signed out', () async {
      final signedOut = FakeAgentRuntime(sessions: store, loginRequired: true);
      final other = StudioAgentHost(
        runtime: signedOut,
        projectId: 'p1',
        projectRoot: '/tmp/project',
      );
      addTearDown(other.dispose);

      await expectLater(
        other.launch(
          const HarnessLaunchRequest(
            providerId: kStudioProviderId,
            cwd: '/tmp/project',
          ),
        ),
        throwsA(isA<AgentLoginRequired>()),
      );
      expect(other.snapshot(), isEmpty);
      expect(store.sessionsOf('p1'), isEmpty);
    });

    test('reports the provider as unavailable when signed out', () async {
      final signedOut = StudioAgentHost(
        runtime: FakeAgentRuntime(sessions: store, loginRequired: true),
        projectId: 'p1',
        projectRoot: '/tmp/project',
        signedIn: () => false,
      );
      addTearDown(signedOut.dispose);

      final providers = await signedOut.providers();
      expect(providers.single.available, isFalse);
    });
  });

  group('project boundary', () {
    test('refuses to open a session of another project', () async {
      final foreign = await store.create('p2', title: '别的项目');

      await expectLater(host.open(foreign.id), throwsArgumentError);
      expect(runtime.openedSessions, isEmpty);
    });

    test('refuses an unknown session id', () async {
      await expectLater(host.open('missing'), throwsArgumentError);
    });
  });

  group('dispose', () {
    test('closes watchers and detaches open views', () async {
      await seedSession();
      final handle = await host.open('session-0');
      final events = <List<HarnessSessionInfo>>[];
      final subscription = host.watchSessions().listen(events.add);
      await pumpEventQueue();
      await host.dispose();
      await subscription.cancel();
      expect(handle.transcript, isNull);
      expect(host.snapshot(), isEmpty);
    });
  });
}
