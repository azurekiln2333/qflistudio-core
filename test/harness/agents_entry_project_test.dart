@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/ui/agents_entry.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/store/project_store.dart';

import '../support/fake_harness_host.dart';

/// 首页一行落到哪个项目：本机会话退回最近的项目，别的主机用自己的占位项目。
void main() {
  late Directory temp;
  late ProjectStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qfli_agents_entry_');
    store = ProjectStore(storageFile: File('${temp.path}/projects.json'));
    await store.load();
  });

  tearDown(() async {
    store.dispose();
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // 句柄可能还没释放。
    }
  });

  Future<Project> addProject(String name) async {
    final dir = Directory('${temp.path}/$name')..createSync(recursive: true);
    final result = await store.addExisting(dir.path);
    final project = result.project;
    if (project == null) throw StateError('建项目失败：${result.error}');
    return project;
  }

  AgentsIndexRow row({
    required String hostId,
    required HarnessHostKind kind,
    String? cwd,
    String title = '会话',
  }) => AgentsIndexRow(
    session: fakeSession(hostId: hostId, id: 's-1', title: title, cwd: cwd),
    hostLabel: '端',
    hostKind: kind,
  );

  test('本机会话的目录对上项目时直接用那个项目', () async {
    final matched = await addProject('甲');
    await addProject('乙');
    final picked = await resolveSessionProject(
      store,
      row(hostId: 'local', kind: HarnessHostKind.local, cwd: matched.path),
    );
    expect(picked?.id, matched.id);
  });

  test('本机会话的项目已删除时退回最近的项目', () async {
    final recent = await addProject('最近的');
    final picked = await resolveSessionProject(
      store,
      row(
        hostId: 'local',
        kind: HarnessHostKind.local,
        cwd: '${temp.path}/不存在的项目',
      ),
    );
    expect(picked?.id, recent.id);
  });

  test('本机会话没有任何项目时给 null', () async {
    final picked = await resolveSessionProject(
      store,
      row(hostId: 'local', kind: HarnessHostKind.local, cwd: '/nowhere'),
    );
    expect(picked, isNull);
  });

  test('内置会话不占本机项目', () async {
    final local = await addProject('本机项目');
    final picked = await resolveSessionProject(
      store,
      row(hostId: 'studio', kind: HarnessHostKind.studio, cwd: '/nowhere'),
    );
    expect(picked, isNotNull);
    expect(picked!.placeholder, isTrue);
    expect(picked.deviceHostId, 'studio');
    expect(picked.deviceSessionId, 's-1');
    expect(picked.path, isNot(local.path));
  });

  test('同一个会话再点一次复用同一个占位项目', () async {
    final first = await resolveSessionProject(
      store,
      row(hostId: 'studio', kind: HarnessHostKind.studio),
    );
    final second = await resolveSessionProject(
      store,
      row(hostId: 'studio', kind: HarnessHostKind.studio),
    );
    expect(second?.id, first?.id);
    expect(store.projects.where((p) => p.isDevice).length, 1);
  });
}
