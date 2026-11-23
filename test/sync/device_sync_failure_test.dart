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

/// Pump until [finder] matches, letting real disk IO run.
///
/// `runDeviceSync` reads and writes through `dart:io`. Those futures never
/// complete inside the fake async zone `testWidgets` installs, so the work
/// must be *started* inside [WidgetTester.runAsync] too: a future created in
/// the fake zone keeps waiting on a clock that never lets real IO finish.
///
/// The wait is bounded by a real [Stopwatch] so a broken flow fails the test
/// instead of hanging CI. Each round yields to the event loop for real and
/// pumps 50 ms of frame time.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration limit = const Duration(seconds: 10),
}) async {
  final watch = Stopwatch()..start();
  await tester.runAsync(() async {
    while (finder.evaluate().isEmpty) {
      if (watch.elapsed > limit) {
        throw TestFailure(
          '等待超时（${limit.inSeconds} 秒）：${finder.describeMatch(Plurality.one)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
  // 弹框已经在树里，把入场动画推完再点，避免点到动画途中的位置。
  await tester.pumpAndSettle();
}

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

    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await tester.pump();
    });
    // `plan()` reads the local tree through `dart:io`; the confirmation dialog
    // appears once that real read finishes.
    await pumpUntilFound(tester, find.text('开始同步'));

    await tester.runAsync(() async {
      await tester.tap(find.text('开始同步'));
      await tester.pump();
    });
    // The port throws, so `runDeviceSync` replaces the progress dialog with its
    // failure dialog. It returns only after that dialog closes.
    await pumpUntilFound(tester, find.text('同步未完成'));

    // 进度框已经关掉，换成一句能读的说明。
    expect(find.text('正在同步'), findsNothing);
    expect(find.text('同步未完成'), findsOneWidget);
    expect(find.textContaining('连接已断开'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('知道了'));
      await tester.pump();
    });
    // 关闭动画在假时钟里推，`runAsync` 之外才能稳定断言消失。
    await tester.pumpAndSettle();
    expect(find.text('同步未完成'), findsNothing);

    // Safe now: the failure dialog closed, so the future can finish.
    await tester.runAsync(() async {
      expect(await pending.timeout(const Duration(seconds: 10)), isFalse);
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

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
    // The copy was just written through `dart:io`; read it in the real zone.
    await tester.runAsync(() async {
      expect(
        await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
        'one',
      );
    });

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
    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await tester.pump();
    });
    await pumpUntilFound(tester, find.text('开始同步'));

    await tester.runAsync(() async {
      await tester.tap(find.text('开始同步'));
      await tester.pump();
    });
    // The second transfer throws mid-stream; the failure dialog replaces the
    // progress one, and `runDeviceSync` only returns once it closes.
    await pumpUntilFound(tester, find.text('同步未完成'));

    await tester.runAsync(() async {
      await tester.tap(find.text('知道了'));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    // Safe now: the failure dialog closed, so the future can finish.
    // The old copy survives: a half-written file never takes its place.
    await tester.runAsync(() async {
      expect(await pending.timeout(const Duration(seconds: 10)), isFalse);
      expect(
        await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
        'one',
      );
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

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
