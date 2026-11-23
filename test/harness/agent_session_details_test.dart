@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/ui/agent_session_details_page.dart';

import '../support/fake_harness_host.dart';

/// 会话详情页：字段齐全、缺值显示未知、路径可复制。
void main() {
  AgentsIndexRow row({
    HarnessDeviceInfo? device,
    String? cwd = '/work/demo',
    HarnessHostKind hostKind = HarnessHostKind.remote,
  }) => AgentsIndexRow(
    session: fakeSession(
      hostId: 'remote:1',
      id: 's-1',
      title: '改登录',
      status: HarnessSessionStatus.blocked,
      cwd: cwd,
    ),
    hostLabel: 'MacBook',
    hostKind: hostKind,
    device: device,
  );

  Future<void> mount(WidgetTester tester, AgentsIndexRow row) async {
    await tester.pumpWidget(
      MaterialApp(home: AgentSessionDetailsPage(row: row)),
    );
    await tester.pump();
  }

  testWidgets('五个字段都在，值来自设备信息', (tester) async {
    await mount(
      tester,
      row(
        device: const HarnessDeviceInfo(
          hostName: 'MacBook Pro',
          os: HarnessDeviceOs.macos,
          osVersion: '14.5',
        ),
      ),
    );

    expect(find.text('会话详情'), findsOneWidget);
    expect(find.text('改登录'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('设备名'), findsOneWidget);
    expect(find.text('MacBook Pro'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    expect(find.text('macOS'), findsOneWidget);
    expect(find.text('系统版本'), findsOneWidget);
    expect(find.text('14.5'), findsOneWidget);
    expect(find.text('主机类型'), findsOneWidget);
    expect(find.text('已绑定的电脑'), findsOneWidget);
    expect(find.text('会话路径'), findsOneWidget);
    expect(find.text('/work/demo'), findsOneWidget);
  });

  testWidgets('设备信息缺失时四处显示未知', (tester) async {
    await mount(tester, row());

    expect(find.text('未知'), findsWidgets);
    expect(find.text('设备名'), findsOneWidget);
    expect(find.text('系统版本'), findsOneWidget);
  });

  testWidgets('路径为空时也显示未知', (tester) async {
    await mount(tester, row(cwd: null));

    expect(find.text('会话路径'), findsOneWidget);
    expect(find.text('未知'), findsWidgets);
  });

  testWidgets('内置会话的主机类型是内置 Agent', (tester) async {
    await mount(
      tester,
      row(
        hostKind: HarnessHostKind.studio,
        device: const HarnessDeviceInfo(
          hostName: '我的手机',
          os: HarnessDeviceOs.android,
          osVersion: 'Android 14',
        ),
      ),
    );

    expect(find.text('内置 Agent'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('我的手机'), findsOneWidget);
  });

  testWidgets('路径可以选中复制', (tester) async {
    await mount(tester, row());

    final path = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '/work/demo',
      ),
    );
    expect(path.data, '/work/demo');
  });
}
