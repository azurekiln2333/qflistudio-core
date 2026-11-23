@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';

import '../support/fake_harness_host.dart';

/// 索引模型：状态权重、端标注、合并与排序。
void main() {
  group('harnessStatusRank', () {
    test('待确认排最前，未知排最后', () {
      final ranks = [
        for (final status in HarnessSessionStatus.values)
          harnessStatusRank(status),
      ];
      expect(harnessStatusRank(HarnessSessionStatus.blocked), 0);
      expect(harnessStatusRank(HarnessSessionStatus.unknown), 5);
      expect(
        ranks.toSet().length,
        HarnessSessionStatus.values.length,
        reason: '六个状态权重各不相同',
      );
    });

    test('顺序是待确认、运行中、空闲、已完成、已结束、未知', () {
      const expected = [
        HarnessSessionStatus.blocked,
        HarnessSessionStatus.working,
        HarnessSessionStatus.idle,
        HarnessSessionStatus.done,
        HarnessSessionStatus.exited,
        HarnessSessionStatus.unknown,
      ];
      final sorted = List<HarnessSessionStatus>.of(expected)
        ..sort((a, b) => harnessStatusRank(a).compareTo(harnessStatusRank(b)));
      expect(sorted, expected);
    });
  });

  group('agentsHostLabel', () {
    test('本机与 Herdr 用主机自己的名字，内置 Agent 用固定说法', () {
      expect(
        agentsHostLabel(kind: HarnessHostKind.local, hostLabel: '本机'),
        '本机',
      );
      expect(
        agentsHostLabel(kind: HarnessHostKind.local, hostLabel: 'Herdr'),
        'Herdr',
        reason: '需求 10.5 要求 Herdr 与本机分开标',
      );
      expect(
        agentsHostLabel(kind: HarnessHostKind.local, hostLabel: '  '),
        '本机',
        reason: '主机没给名字时退回默认说法',
      );
      expect(
        agentsHostLabel(kind: HarnessHostKind.studio, hostLabel: '随便'),
        '内置 Agent',
      );
    });

    test('已绑定电脑优先用设备名', () {
      expect(
        agentsHostLabel(
          kind: HarnessHostKind.remote,
          hostLabel: 'MacBook',
          device: const HarnessDeviceInfo(hostName: '小明的 Mac'),
        ),
        '小明的 Mac',
      );
    });

    test('设备名缺失时退回主机名，再退回默认说法', () {
      expect(
        agentsHostLabel(kind: HarnessHostKind.remote, hostLabel: ' MacBook '),
        'MacBook',
      );
      expect(
        agentsHostLabel(
          kind: HarnessHostKind.remote,
          hostLabel: '   ',
          device: const HarnessDeviceInfo(hostName: '  '),
        ),
        '已绑定的电脑',
      );
    });
  });

  group('buildAgentsIndex', () {
    test('主机不存在的会话被丢弃', () {
      final host = FakeHarnessHost(
        id: 'remote:1',
        label: 'MacBook',
        kind: HarnessHostKind.remote,
      );
      addTearDown(host.dispose);
      final rows = buildAgentsIndex(
        hosts: [host],
        sessions: [
          fakeSession(hostId: 'remote:1', id: 's-1'),
          fakeSession(hostId: 'remote:gone', id: 's-2'),
        ],
        deviceOf: (_) => null,
      );
      expect(rows.length, 1);
      expect(rows.single.session.id, 's-1');
      expect(rows.single.hostLabel, 'MacBook');
    });

    test('按状态排序，同状态按更新时间倒序', () {
      final host = FakeHarnessHost(
        id: 'remote:1',
        label: 'MacBook',
        kind: HarnessHostKind.remote,
      );
      addTearDown(host.dispose);
      final now = DateTime.utc(2026, 11, 23, 10);
      final rows = buildAgentsIndex(
        hosts: [host],
        sessions: [
          fakeSession(
            hostId: 'remote:1',
            id: 'idle-old',
            status: HarnessSessionStatus.idle,
            updatedAt: now.subtract(const Duration(hours: 2)),
          ),
          fakeSession(
            hostId: 'remote:1',
            id: 'blocked',
            status: HarnessSessionStatus.blocked,
            updatedAt: now.subtract(const Duration(days: 3)),
          ),
          fakeSession(
            hostId: 'remote:1',
            id: 'idle-new',
            status: HarnessSessionStatus.idle,
            updatedAt: now,
          ),
        ],
        deviceOf: (_) => null,
      );
      expect(rows.map((row) => row.session.id).toList(), [
        'blocked',
        'idle-new',
        'idle-old',
      ]);
    });

    test('没有更新时间的排在同状态之后', () {
      final host = FakeHarnessHost(
        id: 'remote:1',
        label: 'MacBook',
        kind: HarnessHostKind.remote,
      );
      addTearDown(host.dispose);
      final rows = buildAgentsIndex(
        hosts: [host],
        sessions: [
          fakeSession(
            hostId: 'remote:1',
            id: 'no-time',
            status: HarnessSessionStatus.done,
          ),
          fakeSession(
            hostId: 'remote:1',
            id: 'has-time',
            status: HarnessSessionStatus.done,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        deviceOf: (_) => null,
      );
      expect(rows.map((row) => row.session.id).toList(), [
        'has-time',
        'no-time',
      ]);
    });

    test('设备信息进到行里，端标注跟着走', () {
      final host = FakeHarnessHost(
        id: 'remote:1',
        label: 'mac-mini',
        kind: HarnessHostKind.remote,
      );
      addTearDown(host.dispose);
      const device = HarnessDeviceInfo(
        hostName: '工作机',
        os: HarnessDeviceOs.macos,
        osVersion: '14.5',
      );
      final rows = buildAgentsIndex(
        hosts: [host],
        sessions: [fakeSession(hostId: 'remote:1', id: 's-1')],
        deviceOf: (_) => device,
      );
      expect(rows.single.hostLabel, '工作机');
      expect(rows.single.device, device);
      expect(rows.single.hostKind, HarnessHostKind.remote);
    });
  });

  group('sortAgentsRows 与 dedupeAgentsRows', () {
    test('按 rowKey 去重，先出现的优先', () {
      final first = AgentsIndexRow(
        session: fakeSession(
          hostId: 'studio',
          id: 's-1',
          status: HarnessSessionStatus.working,
        ),
        hostLabel: '内置 Agent',
        hostKind: HarnessHostKind.studio,
      );
      final second = AgentsIndexRow(
        session: fakeSession(
          hostId: 'studio',
          id: 's-1',
          status: HarnessSessionStatus.idle,
        ),
        hostLabel: '内置 Agent',
        hostKind: HarnessHostKind.studio,
      );
      final kept = dedupeAgentsRows([first, second]);
      expect(kept.length, 1);
      expect(kept.single.session.status, HarnessSessionStatus.working);
    });

    test('排序输入顺序不影响输出', () {
      final a = AgentsIndexRow(
        session: fakeSession(
          hostId: 'studio',
          id: 'a',
          status: HarnessSessionStatus.idle,
        ),
        hostLabel: '内置 Agent',
        hostKind: HarnessHostKind.studio,
      );
      final b = AgentsIndexRow(
        session: fakeSession(
          hostId: 'studio',
          id: 'b',
          status: HarnessSessionStatus.blocked,
        ),
        hostLabel: '内置 Agent',
        hostKind: HarnessHostKind.studio,
      );
      expect(sortAgentsRows([a, b]).map((row) => row.session.id), ['b', 'a']);
      expect(sortAgentsRows([b, a]).map((row) => row.session.id), ['b', 'a']);
    });

    test('标题相同时按 rowKey 稳定收尾', () {
      final rows = [
        AgentsIndexRow(
          session: fakeSession(
            hostId: 'remote:2',
            id: 's-1',
            status: HarnessSessionStatus.idle,
          ),
          hostLabel: 'B',
          hostKind: HarnessHostKind.remote,
        ),
        AgentsIndexRow(
          session: fakeSession(
            hostId: 'remote:1',
            id: 's-1',
            status: HarnessSessionStatus.idle,
          ),
          hostLabel: 'A',
          hostKind: HarnessHostKind.remote,
        ),
      ];
      expect(sortAgentsRows(rows).map((row) => row.rowKey).toList(), [
        'remote:1:s-1',
        'remote:2:s-1',
      ]);
    });
  });
}
