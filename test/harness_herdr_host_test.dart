import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_cli.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_host.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_platform.dart';
import 'package:qfli_studio_core/harness/pty/harness_pty.dart';

const String _agentsJson =
    '{"result":{"type":"agent_list","agents":['
    '{"agent":"pi","agent_status":"working","cwd":"D:\\\\work","focused":true,'
    '"name":"pi-ui","pane_id":"w37:p14","workspace_id":"w37","tab_id":"w37:t1",'
    '"terminal_title":"π - work","terminal_title_stripped":"π - work"},'
    '{"agent":"claude","agent_status":"done","cwd":"D:\\\\work","focused":false,'
    '"pane_id":"w37:p15","workspace_id":"w37","tab_id":"w37:t1",'
    '"terminal_title":"Herdr 会话","terminal_title_stripped":"Herdr 会话"}'
    ']}}';

const String _workspacesJson =
    '{"result":{"type":"workspace_list","workspaces":['
    '{"workspace_id":"w37","label":"qflistudio","number":3,"focused":true,'
    '"agent_status":"done","pane_count":2,"tab_count":1,"active_tab_id":"w37:t1"}'
    ']}}';

/// Canned CLI that records argv, so the tests assert the exact command.
class _FakeHerdrCli {
  final List<List<String>> argv = <List<String>>[];
  final List<List<String>> waitRequests = <List<String>>[];

  Future<HerdrProcessResult> run(
    List<String> command, {
    String? workingDirectory,
    required Duration timeout,
  }) async {
    argv.add(List<String>.unmodifiable(command));
    final key = command.join(' ');
    if (key == '--version') {
      return const HerdrProcessResult(exitCode: 0, stdout: 'herdr 0.9.3\n');
    }
    if (key == 'status') {
      return const HerdrProcessResult(
        exitCode: 0,
        stdout:
            'client:\n  version: 0.9.3\n  protocol: 22\n\n'
            'server:\n  status: running\n  socket: /tmp/herdr.sock\n',
      );
    }
    if (key == 'agent list') {
      return const HerdrProcessResult(exitCode: 0, stdout: _agentsJson);
    }
    if (key == 'workspace list') {
      return const HerdrProcessResult(exitCode: 0, stdout: _workspacesJson);
    }
    if (command.length > 2 && command[0] == 'agent' && command[1] == 'wait') {
      waitRequests.add(List<String>.unmodifiable(command));
      // Behave like a short wait that timed out: the loop refreshes and waits
      // again instead of spinning.
      return const HerdrProcessResult(
        exitCode: 1,
        stdout: '{"error":{"code":"timeout","message":"150ms"}}',
      );
    }
    if (key.startsWith('agent prompt')) {
      return const HerdrProcessResult(
        exitCode: 0,
        stdout:
            '{"result":{"type":"agent_prompted",'
            '"agent":{"pane_id":"w37:p14","workspace_id":"w37",'
            '"tab_id":"w37:t1","agent":"pi","agent_status":"working",'
            '"focused":false}}}',
      );
    }
    if (key.startsWith('pane close')) {
      return const HerdrProcessResult(
        exitCode: 0,
        stdout: '{"result":{"type":"ok"}}',
      );
    }
    if (key.startsWith('workspace create')) {
      return const HerdrProcessResult(
        exitCode: 0,
        stdout:
            '{"result":{"type":"workspace_created",'
            '"workspace":{"workspace_id":"w9","number":9,"label":"new",'
            '"focused":false,"pane_count":1,"tab_count":1,'
            '"active_tab_id":"w9:t1","agent_status":"unknown"},'
            '"tab":{"tab_id":"w9:t1"},'
            '"root_pane":{"pane_id":"w9:p1","terminal_id":"t",'
            '"workspace_id":"w9","tab_id":"w9:t1","focused":false,'
            '"agent_status":"unknown","revision":1}}}',
      );
    }
    if (key.startsWith('agent start')) {
      return const HerdrProcessResult(
        exitCode: 0,
        stdout:
            '{"result":{"type":"agent_started","argv":["claude"],'
            '"agent":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w9:t1",'
            '"agent":"claude","agent_status":"idle","focused":false,'
            '"terminal_title":"新项目","terminal_title_stripped":"新项目"}}}',
      );
    }
    if (key.startsWith('pane send-text') || key.startsWith('pane send-keys')) {
      return const HerdrProcessResult(exitCode: 0);
    }
    if (key.startsWith('pane read')) {
      return const HerdrProcessResult(exitCode: 0, stdout: 'screen\n');
    }
    return const HerdrProcessResult(exitCode: 0, stdout: '{"result":{}}');
  }

  HerdrCli cli() => HerdrCli(executable: 'herdr', runner: run);
}

/// PTY factory that records the attach command and streams output.
class _FakePtyFactory implements HarnessPtyFactory {
  final List<List<String>> starts = <List<String>>[];
  final StreamController<Uint8List> output =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> writes = <Uint8List>[];
  final List<(int, int)> resizes = <(int, int)>[];
  bool killed = false;

  @override
  Future<HarnessPty> start({
    required List<String> argv,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async {
    starts.add(List<String>.unmodifiable(argv));
    return _FakePty(this);
  }
}

class _FakePty implements HarnessPty {
  _FakePty(this.owner);

  final _FakePtyFactory owner;

  @override
  int? get pid => 4242;

  @override
  Stream<Uint8List> get output => owner.output.stream;

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  void write(Uint8List data) => owner.writes.add(data);

  @override
  void resize(int columns, int rows) => owner.resizes.add((columns, rows));

  @override
  Future<void> kill() async {
    owner.killed = true;
  }
}

class _FailingPtyFactory implements HarnessPtyFactory {
  @override
  Future<HarnessPty> start({
    required List<String> argv,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async => throw const HarnessPtyException('没有可用的 PTY');
}

/// Fails the first `agent list` with an error the CLI layer does not model.
class _FlakyHerdrCli extends _FakeHerdrCli {
  bool broken = true;

  @override
  Future<HerdrProcessResult> run(
    List<String> command, {
    String? workingDirectory,
    required Duration timeout,
  }) {
    if (broken && command.join(' ') == 'agent list') {
      broken = false;
      throw StateError('unexpected shape');
    }
    return super.run(
      command,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }
}

HerdrHost _host(
  _FakeHerdrCli fake, {
  HarnessPtyFactory? pty,
  Duration idleRefresh = const Duration(milliseconds: 20),
  Duration waitBudget = const Duration(milliseconds: 150),
  Duration waitFloor = const Duration(milliseconds: 20),
}) {
  final host = HerdrHost(
    cli: fake.cli(),
    ptyFactory: pty,
    locator: ({String? explicitPath}) async => 'herdr',
    idleRefresh: idleRefresh,
    waitBudget: waitBudget,
    waitFloor: waitFloor,
  );
  // 断言失败也要释放：刷新循环与快照定时器不会自己停，留一个就能把
  // 整个测试进程拖住。
  addTearDown(host.dispose);
  return host;
}

/// 每个用例都带超时：一旦哪个 await 永远不回来，要失败得又快又准。
void testT(String description, Future<void> Function() body) =>
    test(description, () => body().timeout(const Duration(seconds: 15)));

/// The host publishes its first list after the first refresh; poll the snapshot
/// instead of depending on which event a broadcast stream happens to deliver.
Future<List<HarnessSessionInfo>> _sessions(
  HerdrHost host, {
  int min = 1,
}) async {
  // 订阅只用来启动刷新循环，读快照就够了：用完取消，不留给后面用例。
  final subscription = host.watchSessions().listen((_) {});
  try {
    for (var attempt = 0; attempt < 200; attempt++) {
      final list = host.currentSessions;
      if (list.length >= min) return list;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return host.currentSessions;
  } finally {
    await subscription.cancel();
  }
}

void main() {
  testT(
    'reports unsupported with an install hint when herdr is missing',
    () async {
      final host = HerdrHost(locator: ({String? explicitPath}) async => null);
      addTearDown(host.dispose);
      expect(host.state.value, HarnessHostState.offline);
      await host.providers();
      expect(host.state.value, HarnessHostState.unsupported);
      expect(host.installHint, isNotNull);
      expect(host.installHint!.message, contains('herdr'));
      await host.dispose();
    },
  );

  testT('lists agent panes with mapped status, cwd and provider', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake);
    final list = await _sessions(host, min: 2);
    expect(list, hasLength(2));
    final byId = <String, HarnessSessionInfo>{
      for (final info in list) info.id: info,
    };
    final pi = byId['w37:p14']!;
    expect(pi.providerId, 'pi');
    expect(pi.status, HarnessSessionStatus.working);
    expect(pi.cwd, r'D:\work');
    expect(pi.title, 'π - work');
    expect(
      pi.capabilities,
      containsAll(<HarnessCapability>[
        HarnessCapability.terminal,
        HarnessCapability.prompt,
        HarnessCapability.stop,
      ]),
    );
    expect(
      byId['w37:p15']!.status,
      HarnessSessionStatus.done,
      reason: 'done means the turn finished and needs attention',
    );
    expect(
      list.first.id,
      'w37:p15',
      reason: 'a finished turn ranks above a busy one: it needs the user',
    );
    expect(host.state.value, HarnessHostState.online);
    await host.dispose();
  });

  testT(
    'drives status refresh through agent wait, not tight polling',
    () async {
      final fake = _FakeHerdrCli();
      // 用够长的地板观察节流：400 ms 里最多几次，而不是上千次。
      final host = _host(fake, waitFloor: const Duration(milliseconds: 100));
      await _sessions(host, min: 2);
      for (var attempt = 0; attempt < 100; attempt++) {
        if (fake.waitRequests.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(fake.waitRequests, isNotEmpty);
      expect(fake.waitRequests.first[2], 'pi-ui');
      expect(
        fake.waitRequests.first,
        containsAllInOrder(<String>['agent', 'wait', 'pi-ui', '--until']),
      );

      // 这个假 CLI 让 `agent wait` 立即超时返回。没有地板时循环会空转：
      // 400 ms 能塞进上千次，有地板时最多几次。
      final before = fake.waitRequests.length;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fake.waitRequests.length - before, lessThan(6));

      await host.dispose();
    },
  );

  testT('dispose stops the refresh loop', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake);
    await _sessions(host);

    await host.dispose();
    // 放正在飞的那次读取跑完，再记基准。
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final calls = fake.argv.length;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // 释放之后不该再跑任何 CLI 调用。
    expect(fake.argv.length, calls);
  });

  testT('providers list herdr agent kinds, not a bare shell', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake);
    final providers = await host.providers();
    expect(providers, isNotEmpty);
    final ids = providers.map((provider) => provider.id).toList();
    expect(ids, containsAll(<String>['pi', 'claude', 'codex', 'opencode']));
    expect(
      ids,
      isNot(contains('shell')),
      reason: 'agent list never shows a bare shell pane',
    );
    await host.dispose();
  });

  testT('open attaches the pane in a PTY and forwards bytes', () async {
    final fake = _FakeHerdrCli();
    final pty = _FakePtyFactory();
    final host = _host(fake, pty: pty);
    await _sessions(host, min: 2);

    final handle = await host.open('w37:p14');
    expect(handle.info.title, 'π - work');
    expect(handle.transcript, isNull);
    expect(handle.terminal, isNotNull);
    expect(pty.starts.single.take(3), <String>['herdr', 'agent', 'attach']);
    expect(pty.starts.single[3], 'pi-ui');

    handle.terminal!.write(Uint8List.fromList(<int>[0x6c, 0x73]));
    expect(pty.writes.single, <int>[0x6c, 0x73]);
    handle.terminal!.resize(120, 40);
    expect(pty.resizes.single, (120, 40));

    // Detaching releases the view only: no pane command is sent.
    await handle.detach();
    expect(pty.killed, isTrue);
    expect(
      fake.argv.any((argv) => argv.join(' ').startsWith('pane close')),
      isFalse,
    );
    await host.dispose();
  });

  testT(
    'sendPrompt submits through agent prompt; reply needs a terminal',
    () async {
      final fake = _FakeHerdrCli();
      final host = _host(fake, pty: _FakePtyFactory());
      await _sessions(host, min: 2);
      final handle = await host.open('w37:p14');

      await handle.sendPrompt('继续 修复');
      final prompt = fake.argv.firstWhere(
        (argv) => argv.length > 1 && argv[0] == 'agent' && argv[1] == 'prompt',
      );
      expect(prompt[2], 'pi-ui');
      expect(prompt[3], '继续 修复');

      await expectLater(
        handle.reply(const HarnessReply(requestId: 'r1', choice: 'allow')),
        throwsA(isA<UnsupportedError>()),
      );
      await handle.detach();
      await host.dispose();
    },
  );

  testT('stop closes the pane after an explicit call', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake, pty: _FakePtyFactory());
    await _sessions(host, min: 2);
    final handle = await host.open('w37:p14');
    await handle.stop();
    expect(
      fake.argv.where((argv) => argv.join(' ') == 'pane close w37:p14'),
      hasLength(1),
    );
    await host.dispose();
  });

  testT('launch creates a workspace and starts the requested agent', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake, pty: _FakePtyFactory());
    await _sessions(host, min: 2);

    final handle = await host.launch(
      const HarnessLaunchRequest(
        providerId: 'claude',
        cwd: r'D:\work\new-project',
        title: '新项目',
      ),
    );
    expect(handle.info.id, 'w9:p1');
    expect(handle.info.providerId, 'claude');

    final create = fake.argv.firstWhere(
      (argv) => argv.join(' ').startsWith('workspace create'),
    );
    expect(
      create,
      containsAllInOrder(<String>['workspace', 'create', '--cwd']),
    );
    expect(create, contains('--no-focus'));
    final start = fake.argv.firstWhere(
      (argv) => argv.join(' ').startsWith('agent start'),
    );
    expect(start, containsAllInOrder(<String>['--kind', 'claude']));
    expect(start, containsAllInOrder(<String>['--pane', 'w9:p1']));
    await host.dispose();
  });

  testT('a plain shell is refused on the herdr host', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake);
    await _sessions(host, min: 2);
    await expectLater(
      host.launch(
        const HarnessLaunchRequest(providerId: 'shell', cwd: r'D:\work'),
      ),
      throwsA(isA<HerdrException>()),
    );
    expect(
      fake.argv.any((argv) => argv.join(' ').startsWith('workspace create')),
      isFalse,
    );
    await host.dispose();
  });

  testT('a failing PTY falls back to the snapshot terminal', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake, pty: _FailingPtyFactory());
    await _sessions(host, min: 2);
    final handle = await host.open('w37:p14');
    expect(handle.terminal, isNotNull);
    for (var attempt = 0; attempt < 100; attempt++) {
      if (fake.argv.any((argv) => argv.join(' ').startsWith('pane read'))) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      fake.argv.any((argv) => argv.join(' ').startsWith('pane read')),
      isTrue,
      reason: 'the snapshot fallback reads the pane text',
    );
    await handle.detach();
    await host.dispose();
  });

  testT('a broken executable is reported as unsupported, not online', () async {
    final host = HerdrHost(
      locator: ({String? explicitPath}) async => 'C:/broken/herdr.exe',
      runner: _MissingRunner(),
    );
    addTearDown(host.dispose);
    host.watchSessions().listen((_) {});
    for (var attempt = 0; attempt < 100; attempt++) {
      if (host.state.value == HarnessHostState.unsupported) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(host.state.value, HarnessHostState.unsupported);
    expect(host.installHint, isNotNull);
    await host.dispose();
  });

  testT(
    'an explicit path that cannot run is not called "not installed"',
    () async {
      final host = HerdrHost(
        executablePath: 'D:/tools/herdr.exe',
        locator: ({String? explicitPath}) async => null,
      );
      addTearDown(host.dispose);
      await host.providers();
      expect(host.state.value, HarnessHostState.unsupported);
      expect(host.installHint!.title, 'Herdr 路径无效');
      expect(host.installHint!.resolvedPath, 'D:/tools/herdr.exe');
      await host.dispose();
    },
  );

  testT('a stopped pane reopens with a live terminal', () async {
    final fake = _FakeHerdrCli();
    final host = _host(fake);
    await _sessions(host, min: 2);

    final handle = await host.open('w37:p14');
    await handle.stop();
    expect(
      fake.argv.where((argv) => argv.join(' ') == 'pane close w37:p14'),
      hasLength(1),
    );

    // The pane is still in the agent list while the desktop catches up; the
    // second open must not return the closed handle.
    final again = await host.open('w37:p14');
    expect(identical(again, handle), isFalse);
    expect(again.terminal, isNotNull);

    await again.detach();
    await host.dispose();
  });

  testT('a kind herdr knows but we do not is not hidden', () async {
    final host = _host(_FakeHerdrCli());
    final providers = await host.providers();
    final byId = <String, HarnessProviderInfo>{
      for (final provider in providers) provider.id: provider,
    };
    // The table has no executable name for these, so a PATH probe would be a
    // guess; `agent start --kind` is what actually decides.
    for (final kind in const <String>[
      'agy',
      'maki',
      'muse',
      'hermes',
      'kilo',
      'qodercli',
      'letta',
      'mastracode',
      'kiro',
    ]) {
      expect(byId[kind]?.available, isTrue, reason: kind);
    }
    await host.dispose();
  });

  testT('an unexpected refresh error does not stop the loop', () async {
    final host = _host(_FlakyHerdrCli());
    // The first `agent list` throws a plain StateError; the list still arrives.
    final list = await _sessions(host, min: 2);
    expect(list, hasLength(2));
    await host.dispose();
  });

  testT('dispose releases the injected pty factory', () async {
    // 工厂握着 PTY 启动器与进程订阅：主机不释放它，每关一个编辑页就漏一套。
    final fake = _FakeHerdrCli();
    var disposed = 0;
    final host = HerdrHost(
      cli: fake.cli(),
      ptyFactory: _FakePtyFactory(),
      disposePtyFactory: () async => disposed++,
      locator: ({String? explicitPath}) async => 'herdr',
      idleRefresh: const Duration(milliseconds: 20),
      waitBudget: const Duration(milliseconds: 150),
    );
    addTearDown(host.dispose);
    await _sessions(host);

    await host.dispose();

    expect(disposed, 1);
  });

  testT('dispose survives a factory that throws on release', () async {
    final fake = _FakeHerdrCli();
    final host = HerdrHost(
      cli: fake.cli(),
      disposePtyFactory: () async => throw StateError('boom'),
      locator: ({String? explicitPath}) async => 'herdr',
    );
    addTearDown(host.dispose);
    await host.providers();

    // 工厂释放失败不能把主机的其它收尾（会话流、状态）挡住。
    await host.dispose();
  });
}

/// A runner whose binary cannot be started; the host must report `unsupported`.
class _MissingRunner extends HerdrCliRunner {
  @override
  Future<HerdrProcessResult> call(
    List<String> argv, {
    String? workingDirectory,
    required Duration timeout,
  }) async => const HerdrProcessResult(exitCode: -1, spawnError: 'ENOENT');

  @override
  Future<void> dispose() async {}
}
