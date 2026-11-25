// Agents 界面的 widget 测试：主机切换、会话分组与状态标签、结束会话前的
// 确认、关闭视图只 detach、手机端按键栏。
//
// 本地不执行测试（brief 规定），这些用例交给云端 CI。
//
// 全文件不用 `pumpAndSettle()`：界面里有不确定进度的转圈（会话状态
// 「运行中」、会话打开中、输入卡片发送中），它们一直请求下一帧，
// `pumpAndSettle()` 永远等不到静止，只能耗满 10 分钟超时才报错。统一用
// [_settle] 推进固定帧数，足够走完对话框这类有限动画。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/agent/agent_dock.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/hub_agents_surface.dart';
import 'package:qfli_studio_core/harness/ui/hub_chat_view.dart';
import 'package:qfli_studio_core/harness/ui/hub_host_switcher.dart';
import 'package:qfli_studio_core/harness/ui/hub_session_list.dart';
import 'package:qfli_studio_core/harness/ui/hub_session_view.dart';
import 'package:qfli_studio_core/harness/ui/hub_terminal_key_bar.dart';
import 'package:qfli_studio_core/harness/ui/hub_terminal_view.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/shortcut_label.dart';
import 'package:qfli_studio_core/shell/workbench_state.dart';
import 'package:qfli_studio_core/shell/workbench_theme.dart';
import 'package:xterm/xterm.dart';

import '../support/fake_agent.dart';
import '../support/fake_harness_host.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(body: child),
);

/// 推进固定帧数，代替会一直转圈的 `pumpAndSettle()`。
///
/// 600 毫秒足以走完对话框、指示器切换这类有限动画；再多的等待要靠
/// `expect` 断言界面状态，而不是等动画静止。
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late FakeHarnessHost local;
  late FakeHarnessHost remote;

  setUp(() {
    local = FakeHarnessHost(
      id: 'local',
      label: '本机',
      kind: HarnessHostKind.local,
      initialSessions: [
        fakeSession(
          hostId: 'local',
          id: 'l1',
          providerId: 'claude',
          title: 'Claude 会话',
          status: HarnessSessionStatus.working,
          cwd: 'D:/proj/alpha',
          updatedAt: DateTime(2026, 11, 22, 10),
        ),
        fakeSession(
          hostId: 'local',
          id: 'l2',
          providerId: 'codex',
          title: 'Codex 会话',
          status: HarnessSessionStatus.blocked,
          cwd: 'D:/proj/beta',
        ),
      ],
      providerList: const [
        HarnessProviderInfo(
          id: 'claude',
          label: 'Claude Code',
          available: true,
        ),
        HarnessProviderInfo(id: 'codex', label: 'Codex', available: true),
      ],
    );
    remote = FakeHarnessHost(
      id: 'remote-pc',
      label: '我的电脑',
      kind: HarnessHostKind.remote,
      initialState: HarnessHostState.offline,
      initialSessions: [
        fakeSession(hostId: 'remote-pc', id: 'r1', title: '远程会话'),
      ],
    );
  });

  tearDown(() async {
    await local.dispose();
    await remote.dispose();
  });

  HarnessHub buildHub({String? initialHostId}) => HarnessHub(
    hosts: [local, remote],
    desktop: true,
    initialHostId: initialHostId,
  );

  /// 等 hub 收到主机的第一份会话列表。
  ///
  /// [HarnessHost.watchSessions] 的首次快照是异步送来的，`buildHub()`
  /// 之后立刻读 `sessionsOf()` 只会拿到空列表，`.first` 会抛
  /// `Bad state: No element`。
  Future<void> awaitSessions(WidgetTester tester) async {
    await tester.pump();
  }

  testWidgets('host switcher lists hosts, shows the online dot and switches', (
    tester,
  ) async {
    final hub = buildHub();
    await tester.pumpWidget(_wrap(HubHostSwitcher(hub: hub)));
    await tester.pump();

    expect(find.text('本机'), findsOneWidget);
    expect(find.text('我的电脑'), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-host-dot-online')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-host-dot-offline')), findsOneWidget);

    await tester.tap(find.text('我的电脑'));
    await tester.pump();

    expect(hub.currentHostId, 'remote-pc');
    hub.dispose();
  });

  testWidgets('add computer entry calls back', (tester) async {
    final hub = buildHub();
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(HubHostSwitcher(hub: hub, onAddComputer: () => tapped++)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('hub-add-computer')));
    await tester.pump();

    expect(tapped, 1);
    hub.dispose();
  });

  testWidgets('session list groups by provider and shows status and cwd', (
    tester,
  ) async {
    final hub = buildHub();
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: HubSessionGroups(hub: hub, hostId: 'local'),
        ),
      ),
    );
    await tester.pump();
    await hub.providersOf('local');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('hub-provider-group-claude')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hub-provider-group-codex')),
      findsOneWidget,
    );
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('D:/proj/alpha'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    hub.dispose();
  });

  testWidgets('tapping a session row opens it through the hub', (tester) async {
    final hub = buildHub();
    HarnessSessionInfo? selected;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: HubSessionGroups(
            hub: hub,
            hostId: 'local',
            onSelect: (session) => selected = session,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('hub-session-local-l2')));
    await tester.pump();

    expect(selected?.id, 'l2');
    hub.dispose();
  });

  testWidgets('stopping a session asks for confirmation first', (tester) async {
    final hub = buildHub();
    // hub 要活到控件树拆完：在用例体内释放会让还在挂载的视图拿着一台已释放的
    // ChangeNotifier，拆卸阶段一碰就报错。
    addTearDown(hub.dispose);
    await awaitSessions(tester);
    final handle = await hub.openSession(hub.sessionsOf('local').first);
    await tester.pumpWidget(
      _wrap(HubSessionView(hub: hub, session: handle.info)),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('hub-session-stop')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('hub-stop-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hub-stop-cancel')));
    await _settle(tester);
    expect((handle as FakeSessionHandle).stopCount, 0);

    await tester.tap(find.byKey(const ValueKey('hub-session-stop')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('hub-stop-confirm')));
    await _settle(tester);

    expect(handle.stopCount, 1);
  });

  testWidgets('closing the view detaches and keeps the session running', (
    tester,
  ) async {
    final hub = buildHub();
    addTearDown(hub.dispose);
    await awaitSessions(tester);
    final handle = await hub.openSession(hub.sessionsOf('local').first);
    var closed = 0;
    await tester.pumpWidget(
      _wrap(
        HubSessionView(hub: hub, session: handle.info, onClose: () => closed++),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('hub-session-close')));
    await _settle(tester);

    expect(closed, 1);
    expect((handle as FakeSessionHandle).detachCount, 1);
    expect(handle.stopCount, 0);
    expect(hub.activeSession, isNull);
  });

  testWidgets('chat tab sends prompts through the handle', (tester) async {
    final hub = buildHub();
    addTearDown(hub.dispose);
    await awaitSessions(tester);
    final handle =
        await hub.openSession(hub.sessionsOf('local').first)
            as FakeSessionHandle;
    await tester.pumpWidget(
      _wrap(HubSessionView(hub: hub, session: handle.info)),
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('hub-composer-input')),
      '跑一下测试',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hub-composer-send')));
    await _settle(tester);

    expect(handle.prompts, ['跑一下测试']);
  });

  testWidgets('approval options reply with the request id', (tester) async {
    final hub = buildHub();
    addTearDown(hub.dispose);
    await awaitSessions(tester);
    final handle =
        await hub.openSession(hub.sessionsOf('local').first)
            as FakeSessionHandle;
    await tester.pumpWidget(
      _wrap(HubSessionView(hub: hub, session: handle.info)),
    );
    await _settle(tester);

    handle.addEvent(
      const TranscriptEvent(
        id: 'e1',
        role: TranscriptRole.assistant,
        text: '要执行 rm -rf build 吗？',
        requestId: 'req-1',
        options: ['允许', '拒绝'],
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('允许'));
    await _settle(tester);

    expect(handle.replies.single.requestId, 'req-1');
    expect(handle.replies.single.choice, '允许');
  });

  testWidgets(
    'agents surface keeps the studio pane until an external host is chosen',
    (tester) async {
      final studio = FakeHarnessHost(
        id: 'studio',
        label: '内置 Agent',
        kind: HarnessHostKind.studio,
      );
      final hub = HarnessHub(
        hosts: [studio, local, remote],
        desktop: true,
        initialHostId: 'studio',
      );
      addTearDown(hub.dispose);
      addTearDown(studio.dispose);
      await tester.pumpWidget(
        _wrap(
          HubAgentsSurface(
            hub: hub,
            studioPane: const Center(child: Text('STUDIO-PANE')),
            projectRoot: 'D:/proj/alpha',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('STUDIO-PANE'), findsOneWidget);

      // 切主机要等会话列表和供应商列表都落到 hub 上，单帧不够。
      await tester.tap(find.text('本机'));
      await _settle(tester);

      expect(find.text('STUDIO-PANE'), findsNothing);
      expect(find.text('选择一个会话'), findsOneWidget);

      // 会话列表是面板的兄弟组件（编辑器侧边栏里的 HubSessionList），
      // 不在面板内部；面板只负责详情。这里直接通过 hub 打开，
      // 验证面板自己会从空态切成会话视图。
      await hub.openSession(hub.sessionsOf('local').first);
      await _settle(tester);

      expect(find.text('Claude 会话'), findsOneWidget);
      expect(find.byKey(const ValueKey('hub-tab-0')), findsOneWidget);
    },
  );

  for (final viewport in [
    (
      formFactor: AppFormFactor.desktop,
      size: const Size(1440, 900),
      paneWidth: 400.0,
    ),
    (
      formFactor: AppFormFactor.desktop,
      size: const Size(1024, 768),
      paneWidth: 944.0,
    ),
    (
      formFactor: AppFormFactor.tablet,
      size: const Size(1180, 820),
      paneWidth: 400.0,
    ),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'workbench Agent header has one surface/action: ${viewport.size}, $brightness',
        (tester) async {
          final formFactor = viewport.formFactor;
          final desktop = formFactor == AppFormFactor.desktop;
          final expectedHeight = desktop ? 40.0 : 48.0;
          final actionSize = desktop ? 32.0 : 48.0;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final host = FakeHarnessHost(
            id: 'local',
            label: '本机',
            kind: HarnessHostKind.local,
            initialSessions: [
              fakeSession(hostId: 'local', id: 'idle', title: '未选择的会话'),
            ],
            providerList: const [
              HarnessProviderInfo(
                id: 'claude',
                label: 'Claude Code',
                available: true,
              ),
            ],
          );
          final hub = HarnessHub(hosts: [host], desktop: true);
          final layout = LargeScreenController();
          final state = WorkbenchState(projectId: 'project');
          final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore());
          addTearDown(hub.dispose);
          addTearDown(layout.dispose);
          addTearDown(state.dispose);
          addTearDown(runtime.sessions.dispose);
          addTearDown(runtime.fileEvents.close);
          await tester.pumpWidget(
            MaterialApp(
              theme: WorkbenchTheme.from(
                ThemeData(useMaterial3: true, brightness: brightness),
                formFactor: formFactor,
              ),
              home: LargeScreenScope(
                controller: layout,
                formFactor: formFactor,
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: viewport.paneWidth,
                      height: 720,
                      child: AgentDock(
                        runtime: runtime,
                        state: state,
                        onCollapse: () {},
                        onCreateSession: () async {},
                        child: HubAgentsSurface(
                          hub: hub,
                          studioPane: const SizedBox.shrink(),
                          projectRoot: 'D:/project',
                          onAddComputer: () {},
                          openRemoteHost: () async => null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          final header = find.byKey(const ValueKey('hub-agents-header'));
          final surface = find.byKey(
            const ValueKey('hub-agents-header-surface'),
          );
          expect(tester.getSize(header).height, expectedHeight);
          expect(tester.getSize(surface).width, viewport.paneWidth);
          final scheme = Theme.of(tester.element(surface)).colorScheme;
          expect(
            tester.widget<Material>(surface).color,
            scheme.surfaceContainerLow,
          );
          expect(
            find.byKey(const ValueKey('hub-host-switcher')),
            findsNothing,
            reason: 'The host chips must not paint a second surface block.',
          );
          expect(
            find.ancestor(
              of: find.byKey(const ValueKey('hub-sessions-refresh')),
              matching: surface,
            ),
            findsOneWidget,
          );
          expect(
            find.ancestor(
              of: find.byKey(const ValueKey('hub-host-local')),
              matching: surface,
            ),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('hub-new-session')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('editor-agent-new-session')),
            findsNothing,
            reason: 'The host-row action replaces the legacy title-row action.',
          );
          expect(find.text('Agent 面板'), findsNothing);
          expect(
            find.byKey(const ValueKey('editor-agent-collapse')),
            findsNothing,
          );
          for (final key in ['hub-sessions-refresh', 'hub-new-session']) {
            final action = find.byKey(ValueKey(key));
            expect(tester.getSize(action), Size.square(actionSize));
            expect(
              tester.getRect(surface).contains(tester.getCenter(action)),
              isTrue,
            );
          }
          final chipTapTargets = [
            find.descendant(
              of: find.byKey(const ValueKey('hub-host-local')),
              matching: find.byType(InkWell),
            ),
            find.byKey(const ValueKey('hub-host-pending-remote')),
            find.byKey(const ValueKey('hub-add-computer')),
          ];
          for (final chip in chipTapTargets) {
            expect(
              tester.getSize(chip).height,
              desktop ? lessThanOrEqualTo(expectedHeight) : expectedHeight,
            );
            // Narrow panes intentionally scroll host chips, not header actions.
            await tester.ensureVisible(chip);
            await tester.pump();
            expect(
              tester.getRect(surface).contains(tester.getCenter(chip)),
              isTrue,
            );
          }
          expect(
            find.text('从左侧 Agents 入口选择会话（${shortcutLabel('Ctrl+Shift+A')}）。'),
            findsOneWidget,
          );
          expect(find.text('从左侧会话列表选一个，或新建会话。'), findsNothing);
          expect(find.byType(HubNewSessionButton), findsOneWidget);
          final newSession = find.byKey(const ValueKey('hub-new-session'));
          expect(
            tester.widget<PopupMenuButton<String>>(newSession).constraints,
            isNull,
          );
          await tester.tap(newSession);
          await _settle(tester);
          final provider = find.widgetWithText(
            PopupMenuItem<String>,
            'Claude Code',
          );
          expect(provider, findsOneWidget);
          expect(tester.getSize(provider).width, greaterThan(actionSize));
          expect(
            tester.widget<PopupMenuItem<String>>(provider).height,
            actionSize,
          );
          if (!desktop) {
            expect(tester.getSize(provider).height, greaterThanOrEqualTo(48));
          }
          await tester.tap(find.text('Claude Code'));
          await _settle(tester);
          expect(hub.activeSession?.providerId, 'claude');
          expect(hub.activeSession?.cwd, 'D:/project');
          final close = find.byKey(const ValueKey('hub-session-close'));
          expect(close, findsOneWidget);
          expect(
            tester.getTopLeft(close).dy,
            greaterThanOrEqualTo(tester.getBottomLeft(header).dy),
          );
          expect(tester.getSize(header).height, expectedHeight);
          expect(find.byType(HubNewSessionButton), findsOneWidget);
          expect(
            find.byKey(const ValueKey('editor-agent-new-session')),
            findsNothing,
          );

          await tester.tap(close);
          await _settle(tester);
          host.emitSessions([]);
          await _settle(tester);
          expect(find.text('本机 还没有会话'), findsOneWidget);
          expect(
            find.text(
              '从左侧 Agents 查看会话（${shortcutLabel('Ctrl+Shift+A')}）。\n点击顶部按钮新建会话。',
            ),
            findsOneWidget,
          );
          expect(find.byType(HubNewSessionButton), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('phone host header keeps its existing new-session entry', (
    tester,
  ) async {
    final hub = buildHub();
    final state = WorkbenchState(projectId: 'project');
    final runtime = FakeAgentRuntime(sessions: MemoryAgentSessionStore());
    addTearDown(hub.dispose);
    addTearDown(state.dispose);
    addTearDown(runtime.sessions.dispose);
    addTearDown(runtime.fileEvents.close);
    await awaitSessions(tester);
    await tester.pumpWidget(
      _wrap(
        AgentDock(
          runtime: runtime,
          state: state,
          onCollapse: () {},
          onCreateSession: () async {},
          child: HubAgentsSurface(
            hub: hub,
            studioPane: const Center(child: Text('STUDIO-PANE')),
            projectRoot: 'D:/proj/alpha',
          ),
        ),
      ),
    );
    await tester.pump();

    // Phone still keeps both historical launch affordances; only workbench R5
    // removes the empty-state button in favor of its Agents rail guidance.
    expect(find.byType(HubNewSessionButton), findsNWidgets(2));
    expect(find.text('Agent 面板'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-agent-new-session')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-agent-collapse')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-host-switcher')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-agents-header')), findsNothing);
    expect(find.text('从左侧会话列表选一个，或新建会话。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final formFactor in [AppFormFactor.desktop, AppFormFactor.tablet]) {
    testWidgets(
      'workbench keeps its host header before hosts arrive: $formFactor',
      (tester) async {
        final hub = HarnessHub(hosts: const [], desktop: true);
        final layout = LargeScreenController();
        addTearDown(hub.dispose);
        addTearDown(layout.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkbenchTheme.from(
              ThemeData(useMaterial3: true),
              formFactor: formFactor,
            ),
            home: LargeScreenScope(
              controller: layout,
              formFactor: formFactor,
              child: Scaffold(
                body: HubAgentsSurface(
                  hub: hub,
                  studioPane: const Text('STUDIO-PANE'),
                  projectRoot: 'D:/project',
                  onAddComputer: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('hub-agents-header')))
              .height,
          formFactor == AppFormFactor.desktop ? 40 : 48,
        );
        expect(
          find.byKey(const ValueKey('hub-agents-header-surface')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('hub-new-session')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('hub-sessions-refresh')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('hub-add-computer')), findsOneWidget);
        expect(find.text('STUDIO-PANE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('the paired computer is only opened when the user asks for it', (
    tester,
  ) async {
    final studio = FakeHarnessHost(
      id: 'studio',
      label: '内置 Agent',
      kind: HarnessHostKind.studio,
    );
    final paired = FakeHarnessHost(
      id: 'remote-pc2',
      label: '书房的电脑',
      kind: HarnessHostKind.remote,
      initialSessions: [
        fakeSession(hostId: 'remote-pc2', id: 'r9', title: '远程会话'),
      ],
    );
    final hub = HarnessHub(
      hosts: [studio],
      desktop: true,
      initialHostId: 'studio',
      ownsHosts: false,
    );
    final gate = Completer<HarnessHost?>();
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        HubAgentsSurface(
          hub: hub,
          studioPane: const Center(child: Text('STUDIO-PANE')),
          projectRoot: 'D:/proj/alpha',
          openRemoteHost: () {
            opened++;
            return gate.future;
          },
        ),
      ),
    );
    await tester.pump();

    // 挂载不等于连接：面板在编辑器页里是常挂的，这时不该去开远程。
    expect(opened, 0);
    expect(
      find.byKey(const ValueKey('hub-host-pending-remote')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('hub-host-pending-remote')));
    await tester.pump();

    // 第一次点击：进入连接中，占位芯片不能重复点。
    expect(opened, 1);
    expect(find.byKey(const ValueKey('hub-remote-connecting')), findsOneWidget);

    gate.complete(paired);
    await _settle(tester);

    // 连上之后主机入列、切过去，占位芯片让位给真正的主机芯片。
    expect(hub.currentHostId, 'remote-pc2');
    expect(hub.isListening('remote-pc2'), isTrue);
    expect(find.byKey(const ValueKey('hub-host-remote-pc2')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-host-pending-remote')), findsNothing);

    hub.dispose();
    await studio.dispose();
    await paired.dispose();
  });

  testWidgets('a failed remote open sends the user to pairing', (tester) async {
    final studio = FakeHarnessHost(
      id: 'studio',
      label: '内置 Agent',
      kind: HarnessHostKind.studio,
    );
    final hub = HarnessHub(
      hosts: [studio],
      desktop: true,
      initialHostId: 'studio',
      ownsHosts: false,
    );
    var pairingTaps = 0;
    await tester.pumpWidget(
      _wrap(
        HubAgentsSurface(
          hub: hub,
          studioPane: const Center(child: Text('STUDIO-PANE')),
          projectRoot: 'D:/proj/alpha',
          openRemoteHost: () async => null,
          onAddComputer: () => pairingTaps++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('hub-host-pending-remote')));
    await _settle(tester);

    // 没配对：主机数不变，入口还在，再点时带去配对而不是又空转一次。
    expect(hub.hosts, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('hub-host-pending-remote')));
    await tester.pump();
    expect(pairingTaps, 1);

    hub.dispose();
    await studio.dispose();
  });

  testWidgets('the composer stop button asks for confirmation too', (
    tester,
  ) async {
    final hub = buildHub();
    await awaitSessions(tester);
    final handle =
        await hub.openSession(hub.sessionsOf('local').first)
            as FakeSessionHandle;
    // 卡住这次发送，让输入卡片进入“发送中”，才会出现停止按钮。
    handle.sendGate = Completer<void>();
    await tester.pumpWidget(
      _wrap(HubSessionView(hub: hub, session: handle.info)),
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('hub-composer-input')),
      '跑一下测试',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hub-composer-send')));
    await tester.pump();

    // 点停止：先弹确认，会话还没结束。
    await tester.tap(find.byKey(const ValueKey('hub-composer-stop')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('hub-stop-dialog')), findsOneWidget);
    expect(handle.stopCount, 0);

    await tester.tap(find.byKey(const ValueKey('hub-stop-cancel')));
    await _settle(tester);
    expect(handle.stopCount, 0);

    handle.sendGate!.complete();
    await _settle(tester);
    hub.dispose();
  });

  testWidgets('chat view rebinds when the handle changes', (tester) async {
    final hub = buildHub();
    await awaitSessions(tester);
    final first =
        await hub.openSession(hub.sessionsOf('local').first)
            as FakeSessionHandle;
    await tester.pumpWidget(_wrap(HubChatView(handle: first)));
    await _settle(tester);

    first.addEvent(
      const TranscriptEvent(
        id: 'a1',
        role: TranscriptRole.assistant,
        text: '第一个会话的话',
      ),
    );
    await _settle(tester);
    expect(find.text('第一个会话的话'), findsOneWidget);

    // 同一个 State 换句柄：旧会话的事件不能留着。
    final second = FakeSessionHandle(
      info: fakeSession(hostId: 'local', id: 'l9', title: '第二个会话'),
    );
    await tester.pumpWidget(_wrap(HubChatView(handle: second)));
    await _settle(tester);
    expect(find.text('第一个会话的话'), findsNothing);

    second.addEvent(
      const TranscriptEvent(
        id: 'b1',
        role: TranscriptRole.assistant,
        text: '第二个会话的话',
      ),
    );
    await _settle(tester);
    expect(find.text('第二个会话的话'), findsOneWidget);
    hub.dispose();
  });

  testWidgets('the session list section stays out of the studio host', (
    tester,
  ) async {
    final studio = FakeHarnessHost(
      id: 'studio',
      label: '内置 Agent',
      kind: HarnessHostKind.studio,
      initialSessions: [fakeSession(hostId: 'studio', id: 's1', title: '内置')],
    );
    final hub = HarnessHub(
      hosts: [studio],
      desktop: true,
      initialHostId: 'studio',
    );
    await tester.pumpWidget(
      _wrap(HubSessionListSection(hub: hub, cwd: 'D:/proj/alpha')),
    );
    await tester.pump();

    // 内置会话由编辑器原有的列表画，这里不能再列一遍。
    expect(
      find.byKey(const ValueKey('hub-session-section-title')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('hub-session-studio-s1')), findsNothing);

    hub.dispose();
    await studio.dispose();
  });

  testWidgets(
    'terminal view joins a multi-byte character split in two chunks',
    (tester) async {
      final channel = FakeTerminalChannel();
      await tester.pumpWidget(_wrap(HubTerminalView(channel: channel)));
      await tester.pump();

      // 「你」的 UTF-8 是 E4 BD A0，故意拆成两块送进来。
      channel.emitBytes(const [0xE4, 0xBD]);
      await tester.pump();
      channel.emitBytes(const [0xA0]);
      await tester.pump();

      final terminal = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal;
      expect(terminal.buffer.getText(), contains('你'));
      // 拆包不能变成替换字符。
      expect(terminal.buffer.getText(), isNot(contains('\uFFFD')));

      await channel.close();
      await _settle(tester);
    },
  );

  testWidgets('terminal key bar sends control keys with modifiers', (
    tester,
  ) async {
    final sent = <(TerminalKey, bool, bool)>[];
    final pasted = <String>[];
    await tester.pumpWidget(
      _wrap(
        HubTerminalKeyBar(
          onKey: (key, {required ctrl, required alt}) =>
              sent.add((key, ctrl, alt)),
          onPaste: pasted.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('hub-key-esc')));
    await tester.tap(find.byKey(const ValueKey('hub-key-tab')));
    await tester.tap(find.byKey(const ValueKey('hub-key-right')));
    await tester.pump();

    expect(sent.map((entry) => entry.$1), [
      TerminalKey.escape,
      TerminalKey.tab,
      TerminalKey.arrowRight,
    ]);
    expect(sent.every((entry) => !entry.$2 && !entry.$3), isTrue);

    // Ctrl 是粘滞开关：打开后方向键带 ctrl 一起发。
    await tester.tap(find.byKey(const ValueKey('hub-key-ctrl')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hub-key-left')));
    await tester.pump();

    expect(sent.last.$1, TerminalKey.arrowLeft);
    expect(sent.last.$2, isTrue);
    expect(sent.last.$3, isFalse);

    await tester.tap(find.byKey(const ValueKey('hub-key-ctrl')));
    await tester.tap(find.byKey(const ValueKey('hub-key-alt')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hub-key-up')));
    await tester.pump();

    expect(sent.last.$2, isFalse);
    expect(sent.last.$3, isTrue);
  });

  testWidgets('terminal key bar pastes clipboard text', (tester) async {
    final pasted = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'ls -la'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        HubTerminalKeyBar(
          onKey: (key, {required ctrl, required alt}) {},
          onPaste: pasted.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('hub-key-paste')));
    await _settle(tester);

    expect(pasted, ['ls -la']);
  });
}
