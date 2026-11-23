@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/device_git_pull.dart';
import 'package:qfli_studio_core/sync/device_sync.dart';
import 'package:qfli_studio_core/sync/device_sync_dialog.dart';
import 'package:qfli_studio_core/sync/sync_ignore.dart';

/// A computer whose reads fail the way a dropped relay does.
class _DroppingPort implements DeviceFilePort {
  _DroppingPort(this.files, {this.failAfter = 0});

  final Map<String, String> files;

  /// Bytes of the first file are handed out, then the link dies.
  final int failAfter;

  var _reads = 0;

  @override
  Future<GitProjectInfo> gitInfo(String root) async =>
      GitProjectInfo(root: root, supported: false);

  @override
  Future<FsManifest> manifest(String root) async => FsManifest(
    root: root,
    ignoreVersion: kSyncIgnoreVersion,
    truncated: false,
    entries: <FsEntry>[
      for (final entry in files.entries)
        FsEntry(
          path: entry.key,
          kind: 'file',
          size: utf8.encode(entry.value).length,
          hash: sha256.convert(utf8.encode(entry.value)).toString(),
        ),
    ],
  );

  @override
  Future<FsChunk> read(String path, {required int offset, int? length}) async {
    if (_reads++ >= failAfter) {
      throw StateError('与服务器的连接已断开');
    }
    final all = utf8.encode(files[path] ?? '');
    return FsChunk(path: path, offset: 0, bytes: all, eof: true);
  }
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 同步中断时不能把用户留在进度框里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli-sync-drop-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('端口抛错时关掉进度框并说明原因', (tester) async {
    final localRoot = p.join(root.path, 'copy');
    final port = _DroppingPort(<String, String>{'a.txt': 'one'});

    late Future<bool> pending;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              pending = runDeviceSync(
                context,
                port: port,
                remoteRoot: r'C:\work\proj',
                localRoot: localRoot,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始同步'));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    // 进度框已经关掉，换成一句能读的说明。
    expect(find.text('正在同步'), findsNothing);
    expect(find.text('同步未完成'), findsOneWidget);
    expect(find.textContaining('连接已断开'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('同步未完成'), findsNothing);
  });

  testWidgets('传输失败后旧文件仍然可用', (tester) async {
    final localRoot = p.join(root.path, 'copy2');
    await tester.runAsync(() async {
      final service = DeviceSyncService(
        port: _DroppingPort(<String, String>{'a.txt': 'one'}, failAfter: 9),
      );
      final plan = await service.plan(
        remoteRoot: r'C:\work\proj',
        localRoot: localRoot,
      );
      await service.apply(plan);
    });
    expect(
      await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
      'one',
    );

    final failing = _DroppingPort(<String, String>{'a.txt': 'two'});
    late Future<bool> pending;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              pending = runDeviceSync(
                context,
                port: failing,
                remoteRoot: r'C:\work\proj',
                localRoot: localRoot,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始同步'));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    expect(
      await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
      'one',
    );
  });

  group('git 决策', () {
    test('可克隆的仓库直接走 git', () {
      const pull = DeviceGitPull();
      final report = pull.decide(
        const GitProjectInfo(
          root: r'C:\work\proj',
          supported: true,
          remote: 'https://example.com/a.git',
          branch: 'main',
          gitBytes: 1024,
        ),
      );
      expect(report.outcome, GitPullOutcome.cloned);
      expect(report.needsUserConfirm, isFalse);
    });

    test('超过阈值先问用户', () {
      const pull = DeviceGitPull();
      final report = pull.decide(
        const GitProjectInfo(
          root: r'C:\work\proj',
          supported: true,
          remote: 'https://example.com/a.git',
          gitBytes: 300 * 1024 * 1024,
        ),
      );
      expect(report.outcome, GitPullOutcome.needsConfirm);
      expect(report.gitBytes, 300 * 1024 * 1024);
    });

    test('没有 origin 时退回文件同步', () {
      const pull = DeviceGitPull();
      expect(
        pull
            .decide(
              const GitProjectInfo(root: r'C:\work\proj', supported: true),
            )
            .outcome,
        GitPullOutcome.fallbackToFiles,
      );
    });
  });

  test('拉完文件后项目指向副本，占位标记清掉', () {
    final project = Project.create(name: '电脑会话', path: '/tmp/placeholder')
      ..deviceHostId = 'agent-42'
      ..deviceSessionId = 's-1'
      ..placeholder = true;
    final copy = p.join(root.path, 'deviceProjects', 'h', 'p', 'files');

    project
      ..filesPulled = true
      ..placeholder = false
      ..path = copy;

    expect(project.path, copy);
    expect(project.placeholder, isFalse);
    expect(project.isDevice, isTrue);
  });
}
