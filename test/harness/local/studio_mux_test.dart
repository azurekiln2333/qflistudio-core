/// 每个用例都限时：卡住要尽快报错，不能把整个 CI 拖到超时。
@Timeout(Duration(seconds: 20))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/pty_process.dart';
import 'package:qfli_studio_core/harness/local/studio_mux.dart';

import 'support/fake_pty.dart';

void main() {
  group('StudioMux', () {
    test('启动会话后状态为 working 且把参数交给 launcher', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);

      final session = await mux.start(
        providerId: 'claude',
        executable: '/usr/local/bin/claude',
        arguments: <String>['--resume'],
        workingDirectory: '/home/dev/proj',
        title: 'Claude Code',
        columns: 120,
        rows: 40,
      );

      expect(session.status.value, HarnessSessionStatus.working);
      expect(session.providerId, 'claude');
      expect(session.title, 'Claude Code');
      expect(session.workingDirectory, '/home/dev/proj');
      expect(session.columns, 120);
      expect(session.rows, 40);
      expect(mux.sessions, hasLength(1));
      expect(mux.sessionFor(session.id), same(session));
      expect(launcher.launches.single['executable'], '/usr/local/bin/claude');
      expect(launcher.launches.single['arguments'], <String>['--resume']);
      expect(launcher.launches.single['columns'], 120);
    });

    test('输出进入滚动缓冲并转发给订阅者', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );
      final received = <Uint8List>[];
      final subscription = session.output.listen(received.add);
      addTearDown(subscription.cancel);

      launcher.spawned.single.emit(<int>[0x1b, 0x5b, 0x41]);
      await Future<void>.delayed(Duration.zero);

      expect(received.single, <int>[0x1b, 0x5b, 0x41]);
      expect(session.scrollback.toBytes(), <int>[0x1b, 0x5b, 0x41]);
    });

    test('安静超过阈值后状态变为 idle，再次输出回到 working', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(
        launcher: launcher,
        idleAfter: const Duration(milliseconds: 10),
      );
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(session.status.value, HarnessSessionStatus.idle);

      launcher.spawned.single.emit(<int>[0x41]);
      await Future<void>.delayed(Duration.zero);
      expect(session.status.value, HarnessSessionStatus.working);
    });

    test('进程退出后状态为 exited 并保留退出码', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      launcher.spawned.single.finish(0);
      expect(await session.exited, 0);
      await Future<void>.delayed(Duration.zero);

      expect(session.status.value, HarnessSessionStatus.exited);
      expect(session.exitCode, 0);
    });

    test('stop 幂等且只结束一次进程', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      await Future.wait<void>(<Future<void>>[session.stop(), session.stop()]);

      expect(launcher.spawned.single.terminateCount, 1);
      expect(session.status.value, HarnessSessionStatus.exited);
    });

    test('sendLine 写入文本并回车', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      session.sendLine('ls');

      expect(launcher.spawned.single.writes.single, <int>[0x6c, 0x73, 13]);
    });

    test('sendLine 按 UTF-8 编码，中文不会被截断', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      session.sendLine('你好');

      final written = launcher.spawned.single.writes.single;
      expect(written, <int>[...utf8.encode('你好'), 13]);
      // 旧实现用 UTF-16 码元，'复' 这类字符的低字节恰好是 0x0D（回车），
      // 一条中文提示词会被拆成多行。除了末尾那一个回车，中间不能出现 0x0D。
      expect(written.sublist(0, written.length - 1), isNot(contains(0x0d)));
    });

    test('外部注入的 launcher 不由 mux 释放', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);

      await mux.dispose();

      expect(launcher.disposeCount, 0, reason: '谁创建谁释放，mux 不能替调用方关掉共享后端');
    });

    test('退出会话超过保留上限后被回收', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher, maxExitedSessions: 1);
      addTearDown(mux.dispose);

      final first = await mux.start(providerId: 'shell', executable: '/bin/sh');
      await first.stop();
      final second = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
      );
      await second.stop();
      final third = await mux.start(providerId: 'shell', executable: '/bin/sh');
      await third.stop();
      // 第四个会话启动前，最旧的两个已退出会话应被淘汰。
      await mux.start(providerId: 'shell', executable: '/bin/sh');

      expect(
        mux.sessions.map((MuxSession s) => s.id),
        isNot(contains(first.id)),
      );
      expect(mux.sessions.map((MuxSession s) => s.id), contains(third.id));
    });

    test('后端不支持改尺寸时 resize 返回 false 且不改记录', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      expect(session.resize(100, 30), isFalse);
      expect(session.columns, 80);
      expect(session.rows, 24);
    });

    test('后端支持改尺寸时记录新的行列', () async {
      final launcher = FakePtyLauncher(resizeSupported: true);
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      expect(session.resize(100, 30), isTrue);
      expect(session.columns, 100);
      expect(session.rows, 30);
      expect(launcher.spawned.single.resizes.single, <int>[100, 30]);
    });

    test('事件流报告 started 与 exited', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final kinds = <MuxEventKind>[];
      final subscription = mux.events.listen(
        (MuxEvent event) => kinds.add(event.kind),
      );
      addTearDown(subscription.cancel);

      final session = await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );
      launcher.spawned.single.finish(0);
      await session.exited;
      await Future<void>.delayed(Duration.zero);

      expect(kinds.first, MuxEventKind.started);
      expect(kinds, contains(MuxEventKind.exited));
    });

    test('dispose 结束全部会话', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      await mux.start(
        providerId: 'shell',
        executable: '/bin/sh',
        workingDirectory: '/tmp',
      );

      await mux.dispose();

      expect(mux.sessions, isEmpty);
      expect(launcher.spawned.single.terminateCount, 1);
    });

    test('进程不响应终止时，dispose 受 stopTimeout 限制', () async {
      // 释放会逐个会话串行等退出码。进程卡死时每次等待必须有上限，否则
      // 一个卡住的会话就能把 teardown 拖到平台的默认超时。
      final launcher = _NeverExitLauncher();
      final mux = StudioMux(
        launcher: launcher,
        stopTimeout: const Duration(milliseconds: 50),
      );
      await mux.start(providerId: 'shell', executable: '/bin/sh');

      final stopwatch = Stopwatch()..start();
      await mux.dispose();
      stopwatch.stop();

      // 默认上限是 5 秒；注入 50 毫秒后必须明显短于默认值。
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(mux.sessions, isEmpty);
    });

    test('无后端时 isSupported 为 false 且 start 抛出 UnsupportedError', () async {
      final mux = StudioMux(launcher: const UnsupportedPtyLauncher());
      addTearDown(mux.dispose);

      expect(mux.isSupported, isFalse);
      await expectLater(
        mux.start(
          providerId: 'shell',
          executable: '/bin/sh',
          workingDirectory: '/tmp',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('ScriptPtyLauncher', () {
    test('命令以 stty 初始化并 exec 子进程', () {
      final command = ScriptPtyLauncher.buildCommand(
        executable: '/usr/local/bin/claude',
        arguments: <String>['--resume', 'session 1'],
        columns: 120,
        rows: 40,
      );

      expect(
        command,
        "stty cols 120 rows 40 2>/dev/null; exec /usr/local/bin/claude --resume 'session 1'",
      );
    });

    test('引号内的单引号被转义', () {
      expect(ScriptPtyLauncher.quoteArgument("it's"), r"'it'\''s'");
      expect(ScriptPtyLauncher.quoteArgument(''), "''");
      expect(ScriptPtyLauncher.quoteArgument('plain-1.0'), 'plain-1.0');
    });

    test('声明终端设备但不支持运行期改尺寸', () {
      final launcher = ScriptPtyLauncher(isMacOS: false);
      expect(launcher.allocatesTerminal, isTrue);
      expect(launcher.supportsResize, isFalse);
      expect(launcher.strategy, 'script');
    });
  });

  group('PipePtyLauncher', () {
    test('Windows 批处理命令经过 cmd.exe', () {
      final (
        String command,
        List<String> arguments,
      ) = PipePtyLauncher.buildInvocation(
        executable: r'C:\tools\claude.cmd',
        arguments: <String>['--resume'],
        isWindows: true,
      );

      expect(command, 'cmd.exe');
      expect(arguments, <String>['/c', r'C:\tools\claude.cmd', '--resume']);
    });

    test('.bat 同样经过 cmd.exe', () {
      final (String command, _) = PipePtyLauncher.buildInvocation(
        executable: r'C:\tools\claude.BAT',
        arguments: const <String>[],
        isWindows: true,
      );

      expect(command, 'cmd.exe');
    });

    test('可执行文件直接启动', () {
      final (
        String command,
        List<String> arguments,
      ) = PipePtyLauncher.buildInvocation(
        executable: 'powershell.exe',
        arguments: const <String>[],
        isWindows: true,
      );

      expect(command, 'powershell.exe');
      expect(arguments, isEmpty);
    });

    test('POSIX 上不经过解释器', () {
      final (
        String command,
        List<String> arguments,
      ) = PipePtyLauncher.buildInvocation(
        executable: '/bin/sh',
        arguments: <String>['-l'],
        isWindows: false,
      );

      expect(command, '/bin/sh');
      expect(arguments, <String>['-l']);
    });

    test('不声明终端设备', () {
      final launcher = PipePtyLauncher(isWindows: true);
      expect(launcher.allocatesTerminal, isFalse);
      expect(launcher.supportsResize, isFalse);
    });
  });

  group('createPtyLauncher', () {
    test('Windows 使用 pipe 后端', () {
      final launcher = createPtyLauncher(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
      );
      expect(launcher.strategy, 'pipe');
      expect(launcher.allocatesTerminal, isFalse);
    });

    test('macOS 与 Linux 使用 script 后端', () {
      expect(
        createPtyLauncher(
          isWindows: false,
          isMacOS: true,
          isLinux: false,
        ).strategy,
        'script',
      );
      expect(
        createPtyLauncher(
          isWindows: false,
          isMacOS: false,
          isLinux: true,
        ).strategy,
        'script',
      );
    });

    test('移动端没有后端', () {
      final launcher = createPtyLauncher(
        isWindows: false,
        isMacOS: false,
        isLinux: false,
      );
      expect(launcher.strategy, 'unsupported');
    });
  });
}

/// 永不退出的 launcher：把 terminate 当作没回应。
class _NeverExitLauncher implements PtyLauncher {
  @override
  String get strategy => 'fake';

  @override
  bool get allocatesTerminal => true;

  @override
  bool get supportsResize => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<PtyProcess> spawn({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async => FakePtyProcess(neverExits: true);
}
