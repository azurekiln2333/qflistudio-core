@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/agent/session_list_view.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/store/project_store.dart';

/// 删会话时一并清掉它的占位项目（需求 12 的收尾）。
///
/// 直接调 [SessionListView] 的清理入口，不铺界面：删除确认框与菜单手势
/// 由现有嵌入测试覆盖，这里只看项目列表与磁盘。
void main() {
  late Directory root;
  late ProjectStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-session-discard-');
    store = ProjectStore(storageFile: File(p.join(root.path, 'p.json')));
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Project deviceProject({
    required String sessionId,
    bool placeholder = true,
    bool filesPulled = false,
  }) => Project.create(name: '会话', path: p.join(root.path, 'proj-$sessionId'))
    ..deviceHostId = 'agent-42'
    ..deviceSessionId = sessionId
    ..deviceRoot = r'C:\work\proj'
    ..placeholder = placeholder
    ..filesPulled = filesPulled;

  test('删会话后没拉过文件的占位项目一起消失', () async {
    final project = deviceProject(sessionId: 'sess-1');
    Directory(project.path).createSync(recursive: true);
    await store.registerDeviceProject(project);

    await discardSessionPlaceholders(store, 'sess-1');

    expect(await Directory(project.path).exists(), isFalse);
    expect(store.projects, isEmpty);
  });

  test('拉过文件的项目留着', () async {
    final project = deviceProject(
      sessionId: 'sess-1',
      placeholder: false,
      filesPulled: true,
    );
    Directory(project.path).createSync(recursive: true);
    await store.registerDeviceProject(project);

    await discardSessionPlaceholders(store, 'sess-1');

    expect(await Directory(project.path).exists(), isTrue);
    expect(store.projects.length, 1);
  });

  test('只动这一个会话的项目', () async {
    final kept = deviceProject(sessionId: 'sess-2');
    final removed = deviceProject(sessionId: 'sess-1');
    for (final project in [kept, removed]) {
      Directory(project.path).createSync(recursive: true);
      await store.registerDeviceProject(project);
    }

    await discardSessionPlaceholders(store, 'sess-1');

    expect(store.projects.map((p) => p.deviceSessionId), ['sess-2']);
    expect(await Directory(kept.path).exists(), isTrue);
    expect(await Directory(removed.path).exists(), isFalse);
  });

  test('没有项目仓库时什么也不做', () async {
    // 骨架页不传 store：清理入口必须容忍，不能抛出去打断删除会话。
    await discardSessionPlaceholders(null, 'sess-1');
  });
}
