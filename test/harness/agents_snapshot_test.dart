@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/hub/agents_snapshot.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';

import '../support/fake_harness_host.dart';

/// 快照：首屏能画、坏数据不炸、写入防抖。
void main() {
  AgentsIndexRow row({
    String hostId = 'remote:1',
    String sessionId = 's-1',
    String title = '改登录',
    HarnessSessionStatus status = HarnessSessionStatus.blocked,
    String? cwd = '/work/demo',
    DateTime? updatedAt,
    HarnessDeviceInfo? device,
    HarnessHostKind hostKind = HarnessHostKind.remote,
  }) => AgentsIndexRow(
    session: fakeSession(
      hostId: hostId,
      id: sessionId,
      title: title,
      status: status,
      cwd: cwd,
      updatedAt: updatedAt ?? DateTime.utc(2026, 11, 23, 9, 58),
    ),
    hostLabel: 'MacBook',
    hostKind: hostKind,
    device: device,
  );

  test('没有写过时读回空表', () async {
    final store = AgentsSnapshotStore(backend: LocalMemoryBackend());
    expect(await store.load(), isEmpty);
  });

  test('写进去能原样读回', () async {
    final backend = LocalMemoryBackend();
    final store = AgentsSnapshotStore(backend: backend);
    const device = HarnessDeviceInfo(
      hostName: 'MacBook Pro',
      os: HarnessDeviceOs.macos,
      osVersion: '14.5',
    );
    final source = [
      row(device: device),
      row(sessionId: 's-2', status: HarnessSessionStatus.working),
    ];

    await store.save(source);
    final loaded = await store.load();

    expect(loaded.length, 2);
    expect(loaded.first.session.id, 's-1');
    expect(loaded.first.session.title, '改登录');
    expect(loaded.first.session.status, HarnessSessionStatus.blocked);
    expect(loaded.first.session.cwd, '/work/demo');
    expect(loaded.first.session.updatedAt, DateTime.utc(2026, 11, 23, 9, 58));
    expect(loaded.first.hostLabel, 'MacBook');
    expect(loaded.first.hostKind, HarnessHostKind.remote);
    expect(loaded.first.device?.hostName, 'MacBook Pro');
    expect(loaded.first.device?.os, HarnessDeviceOs.macos);
    expect(loaded.first.device?.osVersion, '14.5');
    expect(loaded.last.session.status, HarnessSessionStatus.working);
  });

  test('坏 JSON 读回空表', () async {
    final store = AgentsSnapshotStore(backend: LocalMemoryBackend('{ 不是 json'));
    expect(await store.load(), isEmpty);
  });

  test('版本不对读回空表', () async {
    final payload = jsonEncode({
      'version': 99,
      'rows': [
        {'hostId': 'remote:1', 'sessionId': 's-1', 'hostKind': 'remote'},
      ],
    });
    final store = AgentsSnapshotStore(backend: LocalMemoryBackend(payload));
    expect(await store.load(), isEmpty);
  });

  test('缺字段的行丢掉，其余照常读回', () async {
    final payload = jsonEncode({
      'version': AgentsSnapshotStore.schemaVersion,
      'rows': [
        {'hostId': 'remote:1'},
        {'sessionId': 's-2', 'hostKind': 'remote'},
        {'hostId': 'remote:1', 'sessionId': 'ok', 'hostKind': 'remote'},
        {'hostId': 'remote:1', 'sessionId': 'bad-kind', 'hostKind': '???'},
      ],
    });
    final store = AgentsSnapshotStore(backend: LocalMemoryBackend(payload));
    final loaded = await store.load();
    expect(loaded.map((row) => row.session.id).toList(), ['ok']);
    expect(loaded.single.session.status, HarnessSessionStatus.unknown);
  });

  test('超过上限时截断', () async {
    final backend = LocalMemoryBackend();
    final store = AgentsSnapshotStore(backend: backend);
    await store.save([
      for (var i = 0; i < AgentsSnapshotStore.maxRows + 20; i++)
        row(sessionId: 's-$i'),
    ]);

    final loaded = await store.load();
    expect(loaded.length, AgentsSnapshotStore.maxRows);
    expect(loaded.first.session.id, 's-0');
  });

  test('空设备信息不写进快照', () async {
    final backend = LocalMemoryBackend();
    final store = AgentsSnapshotStore(backend: backend);
    await store.save([row(device: const HarnessDeviceInfo())]);

    final payload = backend.payload!;
    expect(payload.contains('"device":null'), isTrue);
    expect((await store.load()).single.device, isNull);
  });

  test('写失败不抛给调用方', () async {
    final store = AgentsSnapshotStore(backend: _FailingBackend());
    await store.save([row()]);
  });

  group('AgentsSnapshotWriter', () {
    test('防抖：连续排多次只写最后一次', () {
      final backend = LocalMemoryBackend();
      final store = AgentsSnapshotStore(backend: backend);
      final writer = AgentsSnapshotWriter(
        store: store,
        delay: const Duration(milliseconds: 10),
      );
      addTearDown(writer.dispose);

      writer.schedule([row(sessionId: 'first')]);
      writer.schedule([row(sessionId: 'second')]);

      // 等防抖窗口过去，让定时器自己写一次。
      return Future<void>.delayed(const Duration(milliseconds: 60), () async {
        expect(backend.hasWrite, isTrue);
        final loaded = await store.load();
        expect(loaded.single.session.id, 'second');
      });
    });

    test('flush 立刻写掉排着的行', () async {
      final backend = LocalMemoryBackend();
      final store = AgentsSnapshotStore(backend: backend);
      final writer = AgentsSnapshotWriter(
        store: store,
        delay: const Duration(seconds: 30),
      );
      addTearDown(writer.dispose);

      writer.schedule([row(sessionId: 'now')]);
      await writer.flush();

      expect((await store.load()).single.session.id, 'now');
    });

    test('没有排着的行时 flush 不写', () async {
      final backend = LocalMemoryBackend();
      final writer = AgentsSnapshotWriter(
        store: AgentsSnapshotStore(backend: backend),
      );
      addTearDown(writer.dispose);

      await writer.flush();
      expect(backend.hasWrite, isFalse);
    });
  });
}

/// 写入总是失败的后端。
class _FailingBackend implements LocalStoreBackend {
  @override
  bool get isReady => true;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String payload) async {
    throw const FileSystemException('盘满了');
  }
}
