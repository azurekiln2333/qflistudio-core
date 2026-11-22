import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_cli.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_models.dart';

/// Records argv and replays canned responses, so the tests assert the exact
/// command Herdr receives without spawning anything.
class _FakeHerdr {
  _FakeHerdr({this.responses = const <String, HerdrProcessResult>{}});

  final Map<String, HerdrProcessResult> responses;
  final List<List<String>> argv = <List<String>>[];

  Future<HerdrProcessResult> run(
    List<String> command, {
    String? workingDirectory,
    required Duration timeout,
  }) async {
    argv.add(List<String>.unmodifiable(command));
    final key = command.join(' ');
    for (final entry in responses.entries) {
      if (key.startsWith(entry.key)) return entry.value;
    }
    return const HerdrProcessResult(exitCode: 0, stdout: '{"result":{}}');
  }

  HerdrCli cli() => HerdrCli(executable: 'C:/herdr/herdr.exe', runner: run);
}

HerdrProcessResult ok(String stdout) =>
    HerdrProcessResult(exitCode: 0, stdout: stdout);

void main() {
  test('parses the success envelope and unwraps result', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'agent list': ok(
          '{"id":"cli:agent:list","result":{"agents":[{"pane_id":"w1:p1",'
          '"workspace_id":"w1","tab_id":"w1:t1","agent":"pi",'
          '"agent_status":"idle","focused":false}],"type":"agent_list"}}',
        ),
      },
    );
    final agents = await fake.cli().agents();
    expect(agents, hasLength(1));
    expect(agents.single.paneId, 'w1:p1');
    expect(fake.argv.single, <String>['agent', 'list']);
  });

  test('a void mutation may print nothing', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'pane send-keys': const HerdrProcessResult(exitCode: 0),
      },
    );
    await fake.cli().sendKeys('w1:p1', <String>['enter']);
    expect(fake.argv.single, <String>['pane', 'send-keys', 'w1:p1', 'enter']);
  });

  test(
    'a named agent uses agent send-keys, a pane uses pane send-keys',
    () async {
      final fake = _FakeHerdr();
      final cli = fake.cli();
      await cli.sendKeys('pi-ui', <String>['esc']);
      await cli.sendKeys('w37:p14', <String>['ctrl+c']);
      expect(fake.argv[0], <String>['agent', 'send-keys', 'pi-ui', 'esc']);
      expect(fake.argv[1], <String>['pane', 'send-keys', 'w37:p14', 'ctrl+c']);
    },
  );

  test('prompt passes the text as one argv element and can wait', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'agent prompt': ok(
          '{"result":{"type":"agent_prompted","agent":{"pane_id":"w1:p1",'
          '"workspace_id":"w1","tab_id":"w1:t1","agent":"pi",'
          '"agent_status":"working","focused":false}}}',
        ),
      },
    );
    final report = await fake.cli().prompt(
      'w1:p1',
      '修复 登录 页面 ; rm -rf /',
      wait: true,
      timeoutMs: 1000,
    );
    expect(fake.argv.single.take(2), <String>['agent', 'prompt']);
    expect(fake.argv.single[3], '修复 登录 页面 ; rm -rf /');
    expect(fake.argv.single, contains('--wait'));
    expect(fake.argv.single, contains('1000'));
    expect(report.action, 'agent_prompted');
  });

  test('wait sends every requested until state and a budget', () async {
    final fake = _FakeHerdr();
    await fake.cli().wait(
      'w1:p1',
      until: const <HerdrAgentStatus>[
        HerdrAgentStatus.idle,
        HerdrAgentStatus.done,
        HerdrAgentStatus.blocked,
      ],
      budget: const Duration(milliseconds: 1500),
    );
    expect(fake.argv.single, <String>[
      'agent',
      'wait',
      'w1:p1',
      '--until',
      'idle',
      '--until',
      'done',
      '--until',
      'blocked',
      '--timeout',
      '1500',
    ]);
  });

  test('pane read returns raw screen text, not JSON', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'pane read': ok('line one\r\nline two\r\n'),
      },
    );
    final text = await fake.cli().readPane('w1:p1', lines: 120);
    expect(text, 'line one\r\nline two\r\n');
    expect(fake.argv.single, <String>[
      'pane',
      'read',
      'w1:p1',
      '--source',
      'recent',
      '--lines',
      '120',
    ]);
  });

  test('an error envelope inside pane read becomes a HerdrException', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'pane read': ok(
          '{"error":{"code":"pane_not_found","message":"w1:p9"}}',
        ),
      },
    );
    await expectLater(
      fake.cli().readPane('w1:p1'),
      throwsA(
        isA<HerdrException>()
            .having((e) => e.failure, 'failure', HerdrFailure.notFound)
            .having((e) => e.herdrCode, 'code', 'pane_not_found'),
      ),
    );
  });

  test('a blocked prompt keeps the raw code for the UI', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'agent prompt': ok(
          '{"error":{"code":"agent_blocked","message":"等待确认"}}',
        ),
      },
    );
    await expectLater(
      fake.cli().prompt('w1:p1', '继续'),
      throwsA(
        isA<HerdrException>()
            .having((e) => e.failure, 'failure', HerdrFailure.agentBlocked)
            .having((e) => e.herdrCode, 'code', 'agent_blocked')
            .having((e) => e.message, 'message', contains('等待确认')),
      ),
    );
  });

  test('a spawn failure is reported as unavailable', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'agent list': const HerdrProcessResult(
          exitCode: -1,
          spawnError: 'ENOENT',
        ),
      },
    );
    await expectLater(
      fake.cli().agents(),
      throwsA(
        isA<HerdrException>().having(
          (e) => e.failure,
          'failure',
          HerdrFailure.unavailable,
        ),
      ),
    );
  });

  test('invalid targets and pane ids never reach the CLI', () async {
    final fake = _FakeHerdr();
    final cli = fake.cli();
    await expectLater(cli.prompt('-rf', 'x'), throwsA(isA<HerdrException>()));
    await expectLater(
      cli.readPane('not-a-pane'),
      throwsA(isA<HerdrException>()),
    );
    await expectLater(
      cli.sendKeys('w1:p1', <String>['f13']),
      throwsA(isA<HerdrException>()),
    );
    expect(fake.argv, isEmpty);
  });

  test('version and status come from herdr text output', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        '--version': ok('herdr 0.9.3\n'),
        'status': ok(
          'client:\n'
          '  version: 0.9.3\n'
          '  channel: stable\n'
          '  protocol: 22\n\n'
          'server:\n'
          '  status: running\n'
          '  version: 0.9.3\n'
          "  socket: D:\\AppData\\Roaming\\herdr\\herdr.sock\n",
        ),
      },
    );
    final cli = fake.cli();
    expect(await cli.version(), '0.9.3');
    final status = await cli.serverStatus();
    expect(status.serverRunning, isTrue);
    expect(status.clientProtocol, 22);
    expect(status.socket, r'D:\AppData\Roaming\herdr\herdr.sock');
  });

  test('workspace create returns the root pane id', () async {
    final fake = _FakeHerdr(
      responses: <String, HerdrProcessResult>{
        'workspace create': ok(
          '{"result":{"type":"workspace_created",'
          '"workspace":{"workspace_id":"w9","number":9,"label":"qflistudio",'
          '"focused":false,"pane_count":1,"tab_count":1,"active_tab_id":"w9:t1",'
          '"agent_status":"unknown"},'
          '"tab":{"tab_id":"w9:t1"},'
          '"root_pane":{"pane_id":"w9:p1","terminal_id":"t","workspace_id":"w9",'
          '"tab_id":"w9:t1","focused":false,"agent_status":"unknown",'
          '"revision":1}}}',
        ),
      },
    );
    final paneId = await fake.cli().createWorkspace(
      cwd: r'D:\MyNewProjects\qflistudio',
      label: 'qflistudio',
    );
    expect(paneId, 'w9:p1');
    expect(fake.argv.single, <String>[
      'workspace',
      'create',
      '--cwd',
      r'D:\MyNewProjects\qflistudio',
      '--label',
      'qflistudio',
      '--no-focus',
    ]);
  });
}
