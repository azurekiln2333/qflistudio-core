@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/studio_session_index.dart';

/// 内置会话索引：只读元数据，坏数据不掉页面。
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

  void writeIndex(Object? payload) {
    File(
      index.indexFile.path,
    ).writeAsStringSync(payload is String ? payload : jsonEncode(payload));
  }

  Map<String, Object?> entry({
    required String id,
    String projectId = 'p-1',
    String title = '改登录',
    String updatedAt = '2026-11-23T09:58:00.000Z',
  }) => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'createdAt': '2026-11-23T09:00:00.000Z',
    'updatedAt': updatedAt,
    'messageCount': 12,
    'preview': '先看这个函数',
  };

  test('索引缺失时返回空表', () async {
    final sessions = await index.read(hostId: 'studio', cwdOf: (_) => '/w');
    expect(sessions, isEmpty);
  });

  test('读出会话、映射工作目录与固定字段', () async {
    writeIndex({
      'version': 2,
      'sessions': [entry(id: 's-1')],
    });

    final sessions = await index.read(
      hostId: 'studio',
      cwdOf: (projectId) => projectId == 'p-1' ? '/work/demo' : '',
    );

    expect(sessions.length, 1);
    final session = sessions.single;
    expect(session.id, 's-1');
    expect(session.hostId, 'studio');
    expect(session.providerId, 'studio');
    expect(session.title, '改登录');
    expect(session.status, HarnessSessionStatus.idle);
    expect(session.cwd, '/work/demo');
    expect(session.updatedAt, DateTime.utc(2026, 11, 23, 9, 58));
    expect(session.sourceRef, 's-1');
    expect(session.capabilities, contains(HarnessCapability.transcript));
    expect(
      session.capabilities,
      isNot(contains(HarnessCapability.terminal)),
      reason: '内置会话没有终端',
    );
  });

  test('按更新时间倒序', () async {
    writeIndex({
      'version': 2,
      'sessions': [
        entry(id: 'old', updatedAt: '2026-11-22T09:00:00.000Z'),
        entry(id: 'new', updatedAt: '2026-11-23T09:00:00.000Z'),
      ],
    });

    final sessions = await index.read(hostId: 'studio', cwdOf: (_) => '/w');
    expect(sessions.map((session) => session.id).toList(), ['new', 'old']);
  });

  test('坏条目跳过，好条目照常出现', () async {
    writeIndex({
      'version': 2,
      'sessions': [
        entry(id: ''),
        {'title': '没有 id'},
        {'id': 'no-time'},
        entry(id: 'good'),
        '不是对象',
      ],
    });

    final sessions = await index.read(hostId: 'studio', cwdOf: (_) => '/w');
    expect(sessions.map((session) => session.id).toList(), ['good']);
  });

  test('文件内容不是 JSON 时返回空表', () async {
    writeIndex('{ 这不是 json');
    expect(await index.read(hostId: 'studio', cwdOf: (_) => '/w'), isEmpty);
  });

  test('缺少 sessions 字段时返回空表', () async {
    writeIndex({'version': 2});
    expect(await index.read(hostId: 'studio', cwdOf: (_) => '/w'), isEmpty);
  });

  test('项目已删时工作目录为空串', () async {
    writeIndex({
      'version': 2,
      'sessions': [entry(id: 's-1', projectId: 'gone')],
    });

    final sessions = await index.read(hostId: 'studio', cwdOf: (_) => '');
    expect(sessions.single.cwd, '');
  });

  test('标题缺失时用默认标题', () async {
    writeIndex({
      'version': 2,
      'sessions': [
        {...entry(id: 's-1'), 'title': null},
      ],
    });

    final sessions = await index.read(hostId: 'studio', cwdOf: (_) => '/w');
    expect(sessions.single.title, '新会话');
  });

  test('不写回索引文件', () async {
    writeIndex({
      'version': 2,
      'sessions': [entry(id: 's-1')],
    });
    final before = File(index.indexFile.path).readAsStringSync();

    await index.read(hostId: 'studio', cwdOf: (_) => '/w');

    expect(File(index.indexFile.path).readAsStringSync(), before);
  });

  test('索引路径在会话目录下', () {
    expect(p.basename(index.indexFile.path), 'index.json');
  });
}
