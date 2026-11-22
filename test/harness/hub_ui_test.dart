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
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/harness/ui/hub_agents_surface.dart';
import 'package:qfli_studio_core/harness/ui/hub_chat_view.dart';
import 'package:qfli_studio_core/harness/ui/hub_host_switcher.dart';
import 'package:qfli_studio_core/harness/ui/hub_session_list.dart';
import 'package:qfli_studio_core/harness/ui/hub_session_view.dart';
import 'package:qfli_studio_core/harness/ui/hub_terminal_key_bar.dart';
import 'package:qfli_studio_core/harness/ui/hub_terminal_view.dart';
import 'package:xterm/xterm.dart';

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
    hub.dispose();
  });

  testWidgets('closing the view detaches and keeps the session running', (
    tester,
  ) async {
    final hub = buildHub();
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
    hub.dispose();
  });

  testWidgets('chat tab sends prompts through the handle', (tester) async {
    final hub = buildHub();
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
    hub.dispose();
  });

  testWidgets('approval options reply with the request id', (tester) async {
    final hub = buildHub();
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
    hub.dispose();
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

      await tester.tap(find.text('本机'));
      await tester.pump();

      expect(find.text('STUDIO-PANE'), findsNothing);
      expect(find.text('选择一个会话'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('hub-session-local-l1')));
      await _settle(tester);

      expect(find.text('Claude 会话'), findsOneWidget);
      expect(find.byKey(const ValueKey('hub-tab-0')), findsOneWidget);

      hub.dispose();
      await studio.dispose();
    },
  );

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
