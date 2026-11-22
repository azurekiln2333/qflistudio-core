import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/executable_locator.dart';
import 'package:qfli_studio_core/harness/local/local_harness_host.dart';
import 'package:qfli_studio_core/harness/local/provider_registry.dart';
import 'package:qfli_studio_core/harness/local/studio_mux.dart';

import 'support/fake_pty.dart';

String get _fixtureHome =>
    '${Directory.current.path}/test/harness/local/fixtures/home';

/// 内置项齐全、claude 与 pi 已安装的注册表。
ProviderRegistry registryFor({String home = ''}) {
  final root = home.isEmpty ? _fixtureHome : home;
  return ProviderRegistry(
    locator: ExecutableLocator(
      environment: <String, String>{'HOME': root, 'PATH': '/usr/bin'},
      isWindows: false,
      isMacOS: true,
      fileExists: (String path) =>
          path == '/usr/local/bin/claude' ||
          path == '/usr/local/bin/pi' ||
          path == '/usr/local/bin/opencode' ||
          path == '/bin/sh',
    ),
    configPathResolver: () async => null,
  );
}

void main() {
  group('支持的平台', () {
    test('状态为 online 并列出 provider 与历史会话', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      final providers = await host.providers();
      await host.refreshLogSessions();
      final sessions = await host.watchSessions().first;

      expect(host.id, 'local');
      expect(host.kind, HarnessHostKind.local);
      expect(host.state.value, HarnessHostState.online);
      expect(providers, hasLength(8));
      expect(providers.firstWhere((p) => p.id == 'claude').available, isTrue);
      expect(sessions, hasLength(4));
      expect(sessions.every((s) => s.hostId == 'local'), isTrue);
      expect(sessions.where((s) => s.providerId == 'codex'), hasLength(2));
    });

    test('历史会话只提供 transcript 能力', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      await host.refreshLogSessions();
      final sessions = await host.watchSessions().first;
      final logSession = sessions.firstWhere((s) => s.providerId == 'claude');

      expect(logSession.capabilities, <HarnessCapability>{
        HarnessCapability.transcript,
      });

      final handle = await host.open(logSession.id);
      addTearDown(handle.detach);
      expect(handle.terminal, isNull);
      final events = await handle.transcript!.toList();
      expect(events, isNotEmpty);
      expect(events.first.role, TranscriptRole.user);
    });

    test('历史会话不能发送提示词', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      await host.refreshLogSessions();
      final sessions = await host.watchSessions().first;
      final handle = await host.open(sessions.first.id);

      await expectLater(
        handle.sendPrompt('hi'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('launch 启动会话并返回终端句柄', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      final handle = await host.launch(
        HarnessLaunchRequest(
          providerId: 'claude',
          cwd: cwd.path,
          args: <String>['--resume'],
        ),
      );

      expect(handle.terminal, isNotNull);
      expect(handle.transcript, isNotNull);
      expect(handle.info.providerId, 'claude');
      expect(handle.info.cwd, cwd.path);
      expect(handle.info.capabilities, contains(HarnessCapability.terminal));
      expect(handle.info.capabilities, contains(HarnessCapability.stop));
      expect(launcher.launches.single['executable'], '/usr/local/bin/claude');
      expect(launcher.launches.single['arguments'], <String>['--resume']);

      final reopened = await host.open(handle.info.id);
      expect(reopened.info.id, handle.info.id);
      expect(identical(reopened, handle), isTrue, reason: '同一个会话只应有一个已打开的句柄');
    });

    test('detach 之后重开，对话记录仍能继续推送', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      final handle = await host.launch(
        HarnessLaunchRequest(providerId: 'claude', cwd: cwd.path),
      );
      expect(handle.transcript, isNotNull);
      await handle.detach();

      final reopened = await host.open(handle.info.id);
      expect(reopened.transcript, isNotNull);
      // 旧的 detach 把广播流关掉了；新句柄必须是活的流（订阅后不会立刻 done）。
      var done = false;
      final subscription = reopened.transcript!.listen(
        (_) {},
        onDone: () => done = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse, reason: '重开后拿到的是已关闭的旧流');
      await subscription.cancel();
      await reopened.detach();
    });

    test('detach 之后再 stop 仍然结束会话', () async {
      final launcher = FakePtyLauncher();
      final mux = StudioMux(launcher: launcher);
      addTearDown(mux.dispose);
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: mux,
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      final handle = await host.launch(
        HarnessLaunchRequest(providerId: 'shell', cwd: cwd.path),
      );
      await handle.detach();
      await handle.stop();

      expect(launcher.spawned.single.terminateCount, 1);
    });

    test('晚挂载的订阅者也能拿到当前列表', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      await host.refreshLogSessions();
      final first = await host.watchSessions().first;
      final second = await host.watchSessions().first;

      expect(first, isNotEmpty);
      expect(
        second.map((HarnessSessionInfo s) => s.id),
        first.map((HarnessSessionInfo s) => s.id),
        reason: '第二个订阅者不应看到空列表',
      );
    });

    test('管道后端不提供需要终端的 harness', () async {
      final launcher = FakePtyLauncher(allocatesTerminal: false);
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      final providers = await host.providers();
      expect(providers.firstWhere((p) => p.id == 'claude').available, isFalse);
      expect(
        providers.firstWhere((p) => p.id == 'opencode').available,
        isFalse,
        reason: '默认 requiresTerminal 为 true',
      );
      expect(providers.firstWhere((p) => p.id == 'shell').available, isTrue);

      await expectLater(
        host.launch(HarnessLaunchRequest(providerId: 'claude', cwd: cwd.path)),
        throwsA(isA<StateError>()),
      );
      expect(launcher.spawned, isEmpty);
    });

    test('没有日志配置的 provider 只有终端', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      final handle = await host.launch(
        HarnessLaunchRequest(providerId: 'opencode', cwd: cwd.path),
      );

      expect(handle.terminal, isNotNull);
      expect(handle.transcript, isNull);
      expect(
        handle.info.capabilities,
        isNot(contains(HarnessCapability.transcript)),
      );
      await handle.detach();
    });

    test('launch 拒绝未安装的 provider', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      await expectLater(
        host.launch(HarnessLaunchRequest(providerId: 'gemini', cwd: cwd.path)),
        throwsA(isA<StateError>()),
      );
    });

    test('launch 拒绝不存在的工作目录', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      await expectLater(
        host.launch(
          HarnessLaunchRequest(
            providerId: 'claude',
            cwd: '/definitely/missing',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('未知会话 id 抛 StateError', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      await expectLater(host.open('nope'), throwsA(isA<StateError>()));
    });

    test('重复刷新不会累积重复的历史会话', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);

      await host.refreshLogSessions();
      await host.refreshLogSessions();
      final sessions = await host.watchSessions().first;

      expect(sessions, hasLength(4));
      expect(sessions.map((s) => s.id).toSet(), hasLength(4));
    });

    test('结束直播会话后状态为 exited', () async {
      final launcher = FakePtyLauncher();
      final host = LocalHarnessHost(
        registry: registryFor(),
        mux: StudioMux(launcher: launcher),
        launcher: launcher,
        supported: true,
      );
      addTearDown(host.dispose);
      final cwd = Directory.systemTemp.createTempSync('harness_host_');
      addTearDown(() => cwd.deleteSync(recursive: true));

      final handle = await host.launch(
        HarnessLaunchRequest(providerId: 'pi', cwd: cwd.path),
      );
      await handle.stop();

      expect(handle.status.value, HarnessSessionStatus.exited);
    });
  });

  group('不支持的平台', () {
    test('状态为 unsupported 且没有会话', () async {
      final host = LocalHarnessHost(registry: registryFor(), supported: false);
      addTearDown(host.dispose);

      expect(host.state.value, HarnessHostState.unsupported);
      expect(await host.watchSessions().first, isEmpty);
    });
    test('launch 抛 UnsupportedError', () async {
      final host = LocalHarnessHost(registry: registryFor(), supported: false);
      addTearDown(host.dispose);

      await expectLater(
        host.launch(HarnessLaunchRequest(providerId: 'shell', cwd: '/tmp')),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
