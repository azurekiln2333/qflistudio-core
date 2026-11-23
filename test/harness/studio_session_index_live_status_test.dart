@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/studio_session_index.dart';

/// 内置会话索引：默认 idle，有运行时在跑时用真状态。
void main() {
  late Directory directory;
  late StudioSessionIndex index;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qfli_studio_index_');
    index = StudioSessionIndex(root: directory);
  });

  tearDown(() async {
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // 文件句柄可能还没释放。
    }
  });

  void writeIndex(List<Map<String, Object?>> sessions) {
    File(
      index.indexFile.path,
    ).writeAsStringSync(jsonEncode({'version': 2, 'sessions': sessions}));
  }

  Map<String, Object?> entry(String id) => {
    'id': id,
    'projectId': 'p-1',
    'title': '会话 $id',
    'createdAt': '2026-11-23T09:00:00.000Z',
    'updatedAt': '2026-11-23T09:58:00.000Z',
  };

  test('不传 statusOf 时一律 idle', () async {
    writeIndex([entry('s-1'), entry('s-2')]);

    final sessions = await index.read(hostId: 'studio', cwdOf: (_) => '/w');

    expect(sessions.map((session) => session.status).toList(), [
      HarnessSessionStatus.idle,
      HarnessSessionStatus.idle,
    ]);
  });

  test('传了 statusOf 时用运行时给的状态', () async {
    writeIndex([entry('s-working'), entry('s-blocked'), entry('s-done')]);
    const live = {
      's-working': HarnessSessionStatus.working,
      's-blocked': HarnessSessionStatus.blocked,
      's-done': HarnessSessionStatus.done,
    };

    final sessions = await index.read(
      hostId: 'studio',
      cwdOf: (_) => '/w',
      statusOf: (id) => live[id] ?? HarnessSessionStatus.idle,
    );

    final byId = {for (final session in sessions) session.id: session.status};
    expect(byId['s-working'], HarnessSessionStatus.working);
    expect(byId['s-blocked'], HarnessSessionStatus.blocked);
    expect(byId['s-done'], HarnessSessionStatus.done);
  });

  test('statusOf 只影响状态，其余字段照旧', () async {
    writeIndex([entry('s-1')]);

    final sessions = await index.read(
      hostId: 'studio',
      cwdOf: (_) => '/work/demo',
      statusOf: (_) => HarnessSessionStatus.working,
    );

    final session = sessions.single;
    expect(session.id, 's-1');
    expect(session.hostId, 'studio');
    expect(session.providerId, 'studio');
    expect(session.title, '会话 s-1');
    expect(session.cwd, '/work/demo');
    expect(session.sourceRef, 's-1');
    expect(session.capabilities, isNotEmpty);
  });

  test('statusOf 抛错时不吞错，交给调用方', () async {
    writeIndex([entry('s-1')]);

    await expectLater(
      index.read(
        hostId: 'studio',
        cwdOf: (_) => '/w',
        statusOf: (_) => throw StateError('运行时已释放'),
      ),
      throwsStateError,
    );
  });

  group('studioSessionWithStatus', () {
    final base = HarnessSessionInfo(
      id: 's-1',
      hostId: 'studio',
      providerId: 'studio',
      title: '改登录',
      status: HarnessSessionStatus.idle,
      capabilities: const {
        HarnessCapability.transcript,
        HarnessCapability.prompt,
      },
      cwd: '/work/demo',
      updatedAt: DateTime.utc(2026, 11, 23, 9, 58),
      sourceRef: 's-1',
    );

    test('只换状态，其余字段保持不变', () {
      final next = studioSessionWithStatus(base, HarnessSessionStatus.working);

      expect(next.status, HarnessSessionStatus.working);
      expect(next.id, base.id);
      expect(next.hostId, base.hostId);
      expect(next.providerId, base.providerId);
      expect(next.title, base.title);
      expect(next.capabilities, base.capabilities);
      expect(next.cwd, base.cwd);
      expect(next.updatedAt, base.updatedAt);
      expect(next.sourceRef, base.sourceRef);
    });

    test('原对象不变', () {
      studioSessionWithStatus(base, HarnessSessionStatus.done);
      expect(base.status, HarnessSessionStatus.idle);
    });
  });

  test('索引路径在会话目录下', () {
    expect(p.basename(index.indexFile.path), 'index.json');
  });
}
