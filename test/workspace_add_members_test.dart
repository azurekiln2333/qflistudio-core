import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

void main() {
  late Directory root;
  late WorkspaceStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli_ws_add_');
    store = WorkspaceStore(root: Directory(p.join(root.path, 'ws')));
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // 句柄可能还没释放。
    }
  });

  test('addMembers 只追加：保留成员顺序、缺失成员与会话', () async {
    final a = Project.create(name: 'A', path: p.join(root.path, 'a'));
    final b = Project.create(name: 'B', path: p.join(root.path, 'b'));
    final c = Project.create(name: 'C', path: p.join(root.path, 'c'));

    final created = await store.save(name: '工作区', members: [a, b], primary: a);
    final saved = created.workspace!;

    // 模拟“注册表里已找不到的成员”与历史会话：直接改写落盘记录。
    final ghost = WorkspaceMember(
      projectId: 'ghost-id',
      name: 'Ghost',
      path: p.join(root.path, 'ghost'),
      primary: false,
    );
    final stored = saved.copyWith(
      members: [...saved.members, ghost],
      session: const WorkspaceSessionSnapshot(
        primaryPath: '/keep/me.dart',
        expandedDirs: {
          '/keep': ['me'],
        },
      ),
    );
    final file = Directory(p.join(root.path, 'ws'))
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => p.basename(f.path).contains(saved.id));
    file.writeAsStringSync(jsonEncode(stored.toJson()));
    store = WorkspaceStore(root: Directory(p.join(root.path, 'ws')));

    final updated = await store.addMembers(saved.id, [c]);
    expect(updated, isNotNull);

    // 原有顺序保留，缺失成员保留，新成员追加在末尾。
    expect(updated!.members.map((m) => m.name).toList(), [
      'A',
      'B',
      'Ghost',
      'C',
    ]);
    expect(updated.id, saved.id);
    expect(updated.name, saved.name);
    // 会话未被清掉。
    expect(updated.session.primaryPath, '/keep/me.dart');
    expect(updated.session.expandedDirs['/keep'], ['me']);
  });

  test('addMembers 对已在工作区里的项目不重复追加', () async {
    final a = Project.create(name: 'A', path: p.join(root.path, 'a'));
    final b = Project.create(name: 'B', path: p.join(root.path, 'b'));
    final saved = (await store.save(
      name: 'W',
      members: [a, b],
      primary: a,
    )).workspace!;

    final updated = await store.addMembers(saved.id, [a, b]);
    expect(updated, isNotNull);
    expect(updated!.members.length, 2);
  });

  test('addMembers 对参数的重复路径只算一个成员', () async {
    final a = Project.create(name: 'A', path: p.join(root.path, 'a'));
    final b = Project.create(name: 'B', path: p.join(root.path, 'b'));
    final saved = (await store.save(
      name: 'W',
      members: [a],
      primary: a,
    )).workspace!;

    // 同一路径（大小写/分隔符变体）传两次。
    final duplicate = Project.create(
      name: 'B-again',
      path: p.join(root.path, '.', 'b'),
    );
    final updated = await store.addMembers(saved.id, [b, duplicate]);
    expect(updated!.members.map((m) => m.name).toList(), ['A', 'B']);
  });

  test('addMembers 在写入前快照参数，调用方事后修改不影响结果', () async {
    final a = Project.create(name: 'A', path: p.join(root.path, 'a'));
    final b = Project.create(name: 'B', path: p.join(root.path, 'b'));
    final c = Project.create(name: 'C', path: p.join(root.path, 'c'));
    final saved = (await store.save(
      name: 'W',
      members: [a],
      primary: a,
    )).workspace!;

    final mutable = <Project>[b];
    final future = store.addMembers(saved.id, mutable);
    // 入队后立刻改掉传进去的列表。
    mutable
      ..clear()
      ..add(c);
    final updated = await future;

    expect(updated!.members.map((m) => m.name).toList(), ['A', 'B']);
  });

  test('addMembers 与并发 saveSession 不会丢掉会话', () async {
    final a = Project.create(name: 'A', path: p.join(root.path, 'a'));
    final b = Project.create(name: 'B', path: p.join(root.path, 'b'));
    final saved = (await store.save(
      name: 'W',
      members: [a],
      primary: a,
    )).workspace!;

    await store.load(force: true);
    final addFuture = store.addMembers(saved.id, [b]);
    final sessionFuture = store.saveSession(
      saved,
      const WorkspaceSessionSnapshot(
        primaryPath: '/p/main.dart',
        expandedDirs: {
          '/p': ['main'],
        },
      ),
    );
    final updated = await addFuture;
    await sessionFuture;
    expect(updated, isNotNull);

    // 两者都串行落盘，最后读回来的记录同时有新成员与会话。
    final reloaded = WorkspaceStore(root: Directory(p.join(root.path, 'ws')));
    await reloaded.load(force: true);
    final finalRecord = reloaded.workspaces.firstWhere((w) => w.id == saved.id);
    expect(finalRecord.members.map((m) => m.name).toList(), ['A', 'B']);
    expect(finalRecord.session.primaryPath, '/p/main.dart');
  });

  test('addMembers 对已删除的工作区返回 null', () async {
    final a = Project.create(name: 'A', path: p.join(root.path, 'a'));
    final saved = (await store.save(
      name: 'W',
      members: [a],
      primary: a,
    )).workspace!;
    await store.load(force: true);

    final deleted = await store.addMembers('missing-id', [
      Project.create(name: 'X', path: p.join(root.path, 'x')),
    ]);
    expect(deleted, isNull);
    // 原记录不受影响。
    expect(
      store.workspaces.firstWhere((w) => w.id == saved.id).members.length,
      1,
    );
  });
}
