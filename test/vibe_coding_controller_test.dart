import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

void main() {
  late Directory root;
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
    root = Directory.systemTemp.createTempSync('vibe-controller-');
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  VibeCodingController build(
    _FakeRelay relay, {
    String? token = 'local-token',
    bool Function()? onlineAllowed,
    int maxRounds = 8,
    void Function(String path)? onFileChanged,
    void Function(String message)? onNotice,
  }) => VibeCodingController(
    api: ApiClient(transport: relay.client),
    tokenProvider: () => token,
    projectRoot: root.path,
    projectName: 'demo',
    language: 'python',
    onlineAllowed: onlineAllowed,
    onFileChanged: onFileChanged,
    onNotice: onNotice,
    maxRounds: maxRounds,
  );

  Future<void> settle(VibeCodingController controller, VibePhase phase) async {
    for (var i = 0; i < 500 && controller.phase != phase; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(
      controller.phase,
      phase,
      reason:
          '${controller.lastError} | '
          '${controller.messages.map((m) => '${m.tool?.toolName}:${m.tool?.status}:${m.tool?.result}').join(', ')}',
    );
  }

  test(
    'keeps the real assistant tool_calls and tool results across rounds',
    () async {
      final changed = <String>[];
      final relay = _FakeRelay()
        ..chatReplies.addAll([
          _toolCall('c1', 'write_file', {
            'path': 'src/main.py',
            'content': 'print("hello")\n',
          }),
          _toolCall('c2', 'run_command', {'command': 'python3 src/main.py'}),
          _textReply('已创建并运行 src/main.py，退出码 0。'),
        ])
        ..terminalRuns.add([
          {'type': 'progress', 'stage': 'running'},
          {'type': 'stdout', 'text': 'hello\n'},
          {'type': 'result', 'exitCode': 0, 'cwd': '/workspace'},
        ]);
      final controller = build(relay, onFileChanged: changed.add);

      controller.send('创建并运行脚本');
      await settle(controller, VibePhase.succeeded);

      expect(
        File(p.join(root.path, 'src', 'main.py')).readAsStringSync(),
        'print("hello")\n',
      );
      expect(changed, ['src/main.py']);

      expect(relay.chatBodies, hasLength(3));
      final first = relay.chatBodies.first;
      expect(first.keys.toSet(), {'messages', 'tools'});
      expect(first.containsKey('model'), isFalse);
      expect(first.containsKey('apiKey'), isFalse);
      expect((first['messages'] as List).first['role'], 'system');
      expect((first['tools'] as List), hasLength(9));
      expect(relay.authorizations.first, 'Bearer local-token');

      // Round two must contain the full assistant tool call and its tool reply.
      final second = (relay.chatBodies[1]['messages'] as List)
          .cast<Map<String, dynamic>>();
      final assistant = second.firstWhere(
        (m) => m['role'] == 'assistant' && m.containsKey('tool_calls'),
      );
      expect(assistant['content'], isNull);
      expect(assistant['tool_calls'][0]['id'], 'c1');
      expect(assistant['tool_calls'][0]['function']['name'], 'write_file');
      final tool = second.last;
      expect(tool['role'], 'tool');
      expect(tool['tool_call_id'], 'c1');
      expect(tool['content'], contains('已创建 src/main.py'));

      final third = (relay.chatBodies[2]['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        third.where((m) => m['role'] == 'tool').map((m) => m['tool_call_id']),
        ['c1', 'c2'],
      );

      // Real terminal call: snapshot upload with base64 content.
      expect(relay.terminalBodies.single['command'], 'python3 src/main.py');
      final files = (relay.terminalBodies.single['files'] as List)
          .cast<Map<String, dynamic>>();
      expect(files.single['path'], 'src/main.py');
      expect(
        utf8.decode(base64Decode(files.single['content'] as String)),
        'print("hello")\n',
      );

      final tools = controller.messages
          .where((m) => m.tool != null)
          .map((m) => m.tool!)
          .toList();
      expect(tools.map((t) => t.toolName), ['write_file', 'run_command']);
      expect(tools.every((t) => !t.isRunning), isTrue);
      expect(tools[0].status, VibeToolStatus.ok);
      expect(tools[1].status, VibeToolStatus.ok);
      expect(tools[1].exitCode, 0);
      expect(tools[1].commandOutput, contains('hello'));
      expect(controller.messages.last.text, contains('退出码 0'));

      controller.dispose();
    },
  );

  test('runs failure -> real error -> fix -> rerun', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('r1', 'run_command', {'command': 'python3 main.py'}),
        _toolCall('rd', 'read_file', {'path': 'main.py'}),
        _toolCall('e1', 'edit_file', {
          'path': 'main.py',
          'oldText': 'print(1 / 0)',
          'newText': 'print(1)',
        }),
        _toolCall('r2', 'run_command', {'command': 'python3 main.py'}),
        _textReply('修复后重新运行成功。'),
      ])
      ..terminalRuns.addAll([
        [
          {'type': 'stderr', 'text': 'Traceback: ZeroDivisionError\n'},
          {'type': 'result', 'exitCode': 1, 'cwd': '/workspace'},
        ],
        [
          {'type': 'stdout', 'text': '1\n'},
          {'type': 'result', 'exitCode': 0, 'cwd': '/workspace'},
        ],
      ]);
    File(p.join(root.path, 'main.py')).writeAsStringSync('print(1 / 0)\n');
    final controller = build(relay);

    controller.send('运行并修复');
    await settle(controller, VibePhase.succeeded);

    // The model saw the real exit code and stderr before editing.
    final secondRequest = (relay.chatBodies[1]['messages'] as List)
        .cast<Map<String, dynamic>>();
    final failure = secondRequest.last;
    expect(failure['role'], 'tool');
    expect(failure['content'], contains('退出码：1'));
    expect(failure['content'], contains('ZeroDivisionError'));

    expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'print(1)\n');
    final tools = controller.messages
        .where((m) => m.tool != null)
        .map((m) => m.tool!)
        .toList();
    expect(tools.map((t) => t.toolName), [
      'run_command',
      'read_file',
      'edit_file',
      'run_command',
    ]);
    expect(tools[0].status, VibeToolStatus.error);
    expect(tools[0].exitCode, 1);
    expect(tools[0].commandOutput, contains('ZeroDivisionError'));
    expect(tools[2].status, VibeToolStatus.ok);
    expect(tools[3].status, VibeToolStatus.ok);
    expect(tools[3].exitCode, 0);
    expect(relay.terminalBodies, hasLength(2));

    controller.dispose();
  });

  test('rejects a write after an external disk change as a conflict', () async {
    File(p.join(root.path, 'main.py')).writeAsStringSync('x = 1\n');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('read', 'read_file', {'path': 'main.py'}),
        _toolCall('write', 'write_file', {
          'path': 'main.py',
          'content': 'x = 3\n',
        }),
        _textReply('写入被拒绝，文件保持不变。'),
      ]);
    relay.onChat = (index, body) async {
      if (index == 1) {
        // The user saves another editor in the middle of the agent turn.
        File(p.join(root.path, 'main.py')).writeAsStringSync('x = 2\n');
      }
    };
    final controller = build(relay);

    controller.send('改成 3');
    await settle(controller, VibePhase.succeeded);

    expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 2\n');
    final write = controller.messages
        .where((m) => m.tool?.toolName == 'write_file')
        .single
        .tool!;
    expect(write.status, VibeToolStatus.conflict);
    expect(write.result, contains('会话外被修改'));
    final toolReply = (relay.chatBodies[2]['messages'] as List).last;
    expect(toolReply['content'], contains('conflict'));

    controller.dispose();
  });

  test(
    'surfaces a buffer guard rejection as a conflict without writing',
    () async {
      File(p.join(root.path, 'main.py')).writeAsStringSync('x = 1\n');
      final guard = _GuardedFiles(projectRoot: root.path);
      final relay = _FakeRelay()
        ..chatReplies.addAll([
          _toolCall('read', 'read_file', {'path': 'main.py'}),
          _toolCall('write', 'write_file', {
            'path': 'main.py',
            'content': 'x = 2\n',
          }),
          _textReply('编辑器中有未保存的修改。'),
        ]);
      final controller = VibeCodingController(
        api: ApiClient(transport: relay.client),
        tokenProvider: () => 'local-token',
        projectRoot: root.path,
        projectName: 'demo',
        language: 'python',
        files: guard,
      );

      controller.send('覆盖');
      await settle(controller, VibePhase.succeeded);

      final write = controller.messages
          .where((m) => m.tool?.toolName == 'write_file')
          .single
          .tool!;
      expect(write.status, VibeToolStatus.conflict);
      expect(write.result, contains('未保存的修改'));
      expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 1\n');

      controller.dispose();
    },
  );

  test('requires a token before contacting the backend', () async {
    final relay = _FakeRelay();
    final controller = build(relay, token: null);

    controller.send('你好');
    await settle(controller, VibePhase.failed);

    expect(controller.lastError, contains('登录'));
    expect(relay.chatBodies, isEmpty);
    expect(controller.messages, isEmpty);
    expect(controller.canSend, isTrue);

    controller.dispose();
  });

  test('denies offline products without a request', () async {
    final relay = _FakeRelay();
    final controller = build(relay, onlineAllowed: () => false);

    controller.send('你好');
    await settle(controller, VibePhase.failed);

    expect(controller.lastError, contains('离线'));
    expect(relay.chatBodies, isEmpty);

    controller.dispose();
  });

  test('keeps the ApiClient offline gate for the AI route', () async {
    StudioProfile.current = const StudioProfile(
      id: 'offline-vibe',
      appTitle: 'Offline',
      templates: [],
      isOffline: true,
    );
    final relay = _FakeRelay();
    final controller = build(relay, onlineAllowed: () => true);

    controller.send('你好');
    await settle(controller, VibePhase.failed);

    expect(controller.lastError, contains('离线模式下不可访问在线服务'));
    expect(relay.chatBodies, isEmpty);

    controller.dispose();
  });

  test('stops at the round limit instead of looping forever', () async {
    final relay = _FakeRelay();
    for (var i = 0; i < 3; i++) {
      File(p.join(root.path, 'f$i.py')).writeAsStringSync('v = $i\n');
    }
    // Every round reads a different real file, so each round learns something.
    relay.chatReplies.addAll([
      for (var i = 0; i < 3; i++)
        _toolCall('c$i', 'read_file', {'path': 'f$i.py'}),
    ]);
    final controller = build(relay, maxRounds: 3);

    controller.send('一直看文件');
    await settle(controller, VibePhase.failed);

    expect(controller.lastError, contains('上限'));
    expect(relay.chatBodies, hasLength(3));

    controller.dispose();
  });

  test('stops a tool call that repeats identical arguments', () async {
    File(p.join(root.path, 'a.txt')).writeAsStringSync('x');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('r1', 'read_file', {'path': 'a.txt'}),
        _toolCall('r2', 'read_file', {'path': 'a.txt'}),
        _toolCall('r3', 'read_file', {'path': 'a.txt'}),
        _toolCall('r4', 'read_file', {'path': 'a.txt'}),
        _textReply('已停止重复读取。'),
      ]);
    final controller = build(relay);

    controller.send('重复读取');
    await settle(controller, VibePhase.succeeded);

    final reads = controller.messages
        .where((m) => m.tool != null)
        .map((m) => m.tool!)
        .toList();
    expect(reads, hasLength(4));
    expect(reads.take(3).every((t) => t.status == VibeToolStatus.ok), isTrue);
    expect(reads[3].status, VibeToolStatus.error);
    expect(reads[3].result, contains('重复'));
    expect(
      (relay.chatBodies[4]['messages'] as List).last['content'],
      contains('error(repeated)'),
    );

    controller.dispose();
  });

  test('lists the project root for . and an empty path', () async {
    File(p.join(root.path, 'index.html')).writeAsStringSync('<!doctype html>');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('l1', 'list_files', {'path': '.'}),
        _toolCall('l2', 'list_files', {'path': ''}),
        _toolCall('l3', 'list_files', <String, dynamic>{}),
        _textReply('根目录看完了。'),
      ]);
    final controller = build(relay);

    controller.send('先看根目录');
    await settle(controller, VibePhase.succeeded);

    final listings = controller.messages
        .where((m) => m.tool?.toolName == 'list_files')
        .map((m) => m.tool!)
        .toList();
    expect(listings, hasLength(3));
    expect(listings.every((t) => t.status == VibeToolStatus.ok), isTrue);
    expect(listings.every((t) => t.commandOutput == null), isTrue);

    controller.dispose();
  });

  test('keeps a planning round alive inside the setup rounds', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('t1', 'todo', {
          'items': [
            {'text': '建 index.html', 'status': 'pending'},
          ],
        }),
        _toolCall('l1', 'list_files', {'path': '.'}),
        _toolCall('l2', 'list_files', {'path': '.'}),
        _toolCall('w1', 'write_file', {
          'path': 'index.html',
          'content': '<!doctype html><title>a</title>',
        }),
        _textReply('已创建 index.html。'),
      ]);
    final controller = build(relay);

    controller.send('做一个网站');
    await settle(controller, VibePhase.succeeded);

    expect(controller.lastError, isNull);
    expect(relay.chatBodies, hasLength(5));
    expect(File(p.join(root.path, 'index.html')).existsSync(), isTrue);

    controller.dispose();
  });

  test('stops setup-only rounds once the setup budget is spent', () async {
    // 前 3 轮只列目录算开工；第 4、5 轮仍只列目录，停滞数满才停。
    final relay = _FakeRelay();
    for (var i = 0; i < 5; i++) {
      relay.chatReplies.add(_toolCall('l$i', 'list_files', {'path': '.'}));
    }
    relay.chatReplies.add(_textReply('看完了。'));
    final controller = build(relay);

    controller.send('一直看根目录');
    await settle(controller, VibePhase.failed);

    expect(controller.lastError, contains('没有进展'));
    expect(relay.chatBodies, hasLength(5));

    controller.dispose();
  });

  test(
    'checks a written page locally instead of asking for a script',
    () async {
      final relay = _FakeRelay()
        ..chatReplies.addAll([
          _toolCall('w1', 'write_file', {
            'path': 'index.html',
            'content':
                '<!doctype html><html><head>'
                '<link rel="stylesheet" href="styles.css"></head>'
                '<body><h1>a</h1></body></html>',
          }),
          _toolCall('w2', 'write_file', {
            'path': 'styles.css',
            'content': 'h1{}',
          }),
          _textReply('页面已检查。'),
        ]);
      final controller = build(relay);

      controller.send('做一个网站');
      await settle(controller, VibePhase.succeeded);

      final write = controller.messages.firstWhere(
        (m) => m.tool?.toolName == 'write_file',
      );
      final text = relay.chatBodies[1]['messages'] as List;
      final toolReply =
          text.firstWhere(
                (m) =>
                    m is Map &&
                    m['role'] == 'tool' &&
                    '${m['content']}'.contains('结构'),
              )
              as Map;
      expect('${toolReply['content']}', contains('标签闭合正常'));
      expect(write.tool!.status, VibeToolStatus.ok);
      // 不再要求模型发 heredoc 脚本。
      expect('${toolReply['content']}', isNot(contains('python3')));
      expect('${toolReply['content']}', isNot(contains('html.parser')));

      controller.dispose();
    },
  );

  test('reports a missing local reference in the write result', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('w1', 'write_file', {
          'path': 'index.html',
          'content':
              '<!doctype html><html><body>'
              '<script src="app.js"></script></body></html>',
        }),
        _textReply('页面已写。'),
      ]);
    final controller = build(relay);

    controller.send('做页面');
    await settle(controller, VibePhase.succeeded);

    final body = relay.chatBodies[1]['messages'] as List;
    final toolReply = body.lastWhere((m) => m is Map && m['role'] == 'tool');
    expect('${(toolReply as Map)['content']}', contains('app.js'));
    expect('${toolReply['content']}', contains('缺少文件'));

    controller.dispose();
  });

  test('points a too long command at a script file', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('c1', 'run_command', {'command': 'echo ${'x' * 2100}'}),
        _textReply('改短命令。'),
      ]);
    final controller = build(relay);

    controller.send('跑检查');
    await settle(controller, VibePhase.succeeded);

    final run = controller.messages.firstWhere(
      (m) => m.tool?.toolName == 'run_command',
    );
    expect(run.tool!.status, VibeToolStatus.error);
    expect(run.tool!.result, contains('write_file'));

    controller.dispose();
  });

  test('tells the model to cite the URLs it actually got', () async {
    final relay = _FakeRelay()..chatReplies.add(_textReply('好的。'));
    final controller = build(relay);

    controller.send('查一下 Dart 的当前版本');
    await settle(controller, VibePhase.succeeded);

    final system = (relay.chatBodies.first['messages'] as List).first as Map;
    final prompt = '${system['content']}';
    expect(prompt, contains('web_search'));
    expect(prompt, contains('web_fetch'));
    expect(prompt, contains('标题'));
    expect(prompt, contains('完整网址'));
    expect(prompt, contains('不得编造'));

    controller.dispose();
  });

  test('stops after two rounds without progress', () async {
    final relay = _FakeRelay();
    for (var i = 0; i < 2; i++) {
      relay.chatReplies.add(
        _toolCall('p$i', 'read_file', {'path': 'missing$i.py'}),
      );
    }
    final controller = build(relay);

    controller.send('打开不存在的文件');
    await settle(controller, VibePhase.failed);

    expect(controller.lastError, contains('没有进展'));
    expect(relay.chatBodies, hasLength(2));

    controller.dispose();
  });

  test('refuses an edit of an existing file this send never read', () async {
    File(p.join(root.path, 'main.py')).writeAsStringSync('x = 1\n');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('e1', 'edit_file', {
          'path': 'main.py',
          'oldText': 'x = 1',
          'newText': 'x = 2',
        }),
        _toolCall('r1', 'read_file', {'path': 'main.py'}),
        _toolCall('e2', 'edit_file', {
          'path': 'main.py',
          'oldText': 'x = 1',
          'newText': 'x = 3',
        }),
        _textReply('已按当前内容修改。'),
      ]);
    final controller = build(relay);

    controller.send('改成 3');
    await settle(controller, VibePhase.succeeded);

    final tools = controller.messages
        .where((m) => m.tool != null)
        .map((m) => m.tool!)
        .toList();
    expect(tools[0].status, VibeToolStatus.error);
    expect(tools[0].result, contains('先 read_file'));
    expect(tools[2].status, VibeToolStatus.ok);
    expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 3\n');

    controller.dispose();
  });

  test('validates a tool call against the seven tool schemas', () async {
    final relay = _FakeRelay()..chatReplies.add(_textReply('好的。'));
    final controller = build(relay);

    controller.send('你好');
    await settle(controller, VibePhase.succeeded);

    final tools = (relay.chatBodies.single['tools'] as List)
        .cast<Map<String, dynamic>>()
        .map((spec) => spec['function']['name'] as String)
        .toList();
    expect(tools, [...kVibeToolNames]);

    controller.dispose();
  });

  test(
    'turns malformed tool arguments into a tool error and continues',
    () async {
      final relay = _FakeRelay()
        ..chatReplies.addAll([
          {
            'model': 'deepseek-v4.1-flash',
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'bad',
                  'type': 'function',
                  'function': {'name': 'write_file', 'arguments': 'not-json'},
                },
              ],
            },
          },
          _textReply('工具参数无效，未写入任何文件。'),
        ]);
      final controller = build(relay);

      controller.send('写文件');
      await settle(controller, VibePhase.succeeded);

      final tool = controller.messages.singleWhere((m) => m.tool != null).tool!;
      expect(tool.status, VibeToolStatus.error);
      expect(tool.result, contains('JSON'));
      expect(
        Directory(root.path).listSync().whereType<File>().where(
          (f) => !p.basename(f.path).startsWith('.'),
        ),
        isEmpty,
      );

      controller.dispose();
    },
  );

  test('cancels a running terminal command for real', () async {
    final hold = StreamController<List<int>>();
    final relay = _FakeRelay()..holdTerminal = hold;
    relay.chatReplies.add(
      _toolCall('r1', 'run_command', {'command': 'python3 loop.py'}),
    );
    final controller = build(relay);

    controller.send('运行长任务');
    for (var i = 0; i < 300; i++) {
      final running = controller.messages.any(
        (m) => m.tool?.toolName == 'run_command' && m.tool!.isRunning,
      );
      if (running) break;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    hold.add(
      utf8.encode('${jsonEncode({'type': 'progress', 'stage': 'running'})}\n'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.canCancel, isTrue);

    final cancelled = controller.cancel();
    await cancelled;
    await settle(controller, VibePhase.cancelled);

    expect(controller.canCancel, isFalse);
    expect(
      controller.messages
          .where((m) => m.tool?.toolName == 'run_command')
          .single
          .tool!
          .isRunning,
      isFalse,
    );
    await hold.close();

    controller.dispose();
  });

  test('ignores duplicate sends while a turn is running', () async {
    final hold = StreamController<List<int>>();
    final relay = _FakeRelay()..holdTerminal = hold;
    relay.chatReplies.add(
      _toolCall('r1', 'run_command', {'command': 'sleep 10'}),
    );
    final notices = <String>[];
    final controller = build(relay, onNotice: notices.add);

    controller.send('第一次');
    for (var i = 0; i < 300; i++) {
      if (controller.messages.any((m) => m.tool?.isRunning == true)) break;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    controller.send('第二次');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(notices, contains('上一条任务仍在执行'));
    expect(controller.messages.where((m) => m.isUser), hasLength(1));

    await controller.cancel();
    await hold.close();
    controller.dispose();
  });

  test('bounds the command output tail', () async {
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('r1', 'run_command', {'command': 'yes'}),
        _textReply('输出很长。'),
      ])
      ..terminalRuns.add([
        for (var i = 0; i < 8; i++) {'type': 'stdout', 'text': 'x' * 5000},
        {'type': 'result', 'exitCode': 0, 'cwd': '/workspace'},
      ]);
    final controller = build(relay);

    controller.send('运行');
    await settle(controller, VibePhase.succeeded);

    final tool = controller.messages
        .where((m) => m.tool?.toolName == 'run_command')
        .single
        .tool!;
    expect(tool.commandOutput, contains('输出已截断'));
    expect(tool.commandOutput!.length, lessThan(30 * 1024));

    controller.dispose();
  });

  test('rejects at the commit point through shouldWrite', () async {
    File(p.join(root.path, 'main.py')).writeAsStringSync('x = 1\n');
    final relay = _FakeRelay()
      ..chatReplies.addAll([
        _toolCall('read', 'read_file', {'path': 'main.py'}),
        _toolCall('write', 'write_file', {
          'path': 'main.py',
          'content': 'x = 2\n',
        }),
        _textReply('编辑器拒绝写入。'),
      ]);
    final controller = VibeCodingController(
      api: ApiClient(transport: relay.client),
      tokenProvider: () => 'local-token',
      projectRoot: root.path,
      projectName: 'demo',
      language: 'python',
      files: VibeProjectFiles(
        projectRoot: root.path,
        shouldWrite: (_) => false,
      ),
    );

    controller.send('覆盖');
    await settle(controller, VibePhase.succeeded);

    final write = controller.messages
        .where((m) => m.tool?.toolName == 'write_file')
        .single
        .tool!;
    expect(write.status, VibeToolStatus.conflict);
    expect(File(p.join(root.path, 'main.py')).readAsStringSync(), 'x = 1\n');

    controller.dispose();
  });

  test('ignores send after dispose without a request', () async {
    final relay = _FakeRelay();
    final controller = build(relay);
    controller.dispose();

    controller.send('丢弃');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(relay.chatBodies, isEmpty);
    expect(controller.messages, isEmpty);
  });

  test(
    'stays cancelling until terminal reset finishes, then allows send',
    () async {
      final hold = StreamController<List<int>>();
      final relay = _FakeRelay()
        ..holdTerminal = hold
        ..holdDelete = Completer<void>();
      relay.chatReplies.addAll([
        _toolCall('r1', 'run_command', {'command': 'sleep 99'}),
        _textReply('继续完成。'),
      ]);
      final controller = build(relay);

      controller.send('运行长任务');
      for (var i = 0; i < 300; i++) {
        if (controller.messages.any((m) => m.tool?.isRunning == true)) break;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      var finished = false;
      final cancelled = controller.cancel().whenComplete(() => finished = true);
      // Wait until the run loop has stopped and reset is pending.
      for (var i = 0; i < 300 && relay.deleteCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(relay.deleteCalls, 1);
      expect(finished, isFalse);
      expect(controller.phase, VibePhase.cancelling);
      expect(controller.canSend, isFalse);

      // A send while reset is in flight must not start a new task.
      controller.send('抢跑');
      expect(relay.chatBodies, hasLength(1));

      relay.holdDelete!.complete();
      relay.holdTerminal = null;
      await cancelled;
      expect(controller.phase, VibePhase.cancelled);
      expect(controller.canSend, isTrue);

      controller.send('继续');
      await settle(controller, VibePhase.succeeded);
      expect(relay.chatBodies, hasLength(2));
      expect(relay.deleteCalls, 1);
      expectValidToolProtocol(relay.chatBodies.last);

      await hold.close();
      controller.dispose();
    },
  );
}

/// Every assistant tool call must have a matching tool reply before the next
/// assistant text, so a resumed conversation stays protocol-valid.
void expectValidToolProtocol(Map<String, dynamic> body) {
  final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
  final pending = <String>[];
  for (final message in messages) {
    final role = message['role'];
    if (role == 'assistant' && message['tool_calls'] is List) {
      expect(pending, isEmpty, reason: 'assistant tool call without replies');
      pending.addAll(
        (message['tool_calls'] as List).map((call) => call['id'] as String),
      );
    } else if (role == 'tool') {
      final id = message['tool_call_id'] as String;
      expect(pending, contains(id));
      pending.remove(id);
    } else if (pending.isNotEmpty) {
      fail('unanswered tool call before role=$role');
    }
  }
  expect(pending, isEmpty);
}

Map<String, dynamic> _toolCall(
  String id,
  String name,
  Map<String, Object?> arguments,
) => {
  'model': 'deepseek-v4.1-flash',
  'message': {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      },
    ],
  },
};

Map<String, dynamic> _textReply(String content) => {
  'model': 'deepseek-v4.1-flash',
  'message': {'role': 'assistant', 'content': content},
  'usage': {'total_tokens': 10},
};

/// Mirrors the editor-side guard: dirty buffers reject before any disk write.
class _GuardedFiles extends VibeProjectFiles {
  _GuardedFiles({required super.projectRoot});

  @override
  Future<VibeWriteResult> write(
    String path,
    String content, {
    bool createOnly = false,
  }) async {
    resolve(path);
    throw const VibeToolException('编辑器中有未保存的修改，已拒绝覆盖', code: 'conflict');
  }
}

class _FakeRelay {
  _FakeRelay() {
    client = MockClient.streaming((request, bodyStream) async {
      final body = await utf8.decoder.bind(bodyStream).join();
      authorizations.add(request.headers['authorization']);
      if (request.url.path == '/api/terminal/exec/stream') {
        terminalBodies.add(jsonDecode(body) as Map<String, dynamic>);
        if (holdTerminal != null) {
          // 真实的中断会关闭字节流；这里照做，让控制器看到流已结束。
          final abort = request is http.AbortableRequest
              ? request.abortTrigger
              : null;
          abort?.whenComplete(() {
            if (!holdTerminal!.isClosed) holdTerminal!.close();
          });
          final response = http.StreamedResponse(
            holdTerminal!.stream,
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
          return response;
        }
        final run = terminalRuns.removeAt(0);
        final lines = run.map((e) => '${jsonEncode(e)}\n').join();
        return http.StreamedResponse(
          Stream.value(utf8.encode(lines)),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      }
      if (request.url.path == '/api/ai/chat') {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final index = chatBodies.length;
        chatBodies.add(decoded);
        await onChat?.call(index, decoded);
        final reply = chatReplies.removeAt(0);
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(reply))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE') {
        deleteCalls++;
        await holdDelete?.future;
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          204,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  late final http.Client client;
  final chatReplies = <Map<String, dynamic>>[];
  final terminalRuns = <List<Map<String, Object?>>>[];
  final chatBodies = <Map<String, dynamic>>[];
  final terminalBodies = <Map<String, dynamic>>[];
  final authorizations = <String?>[];
  StreamController<List<int>>? holdTerminal;
  Completer<void>? holdDelete;
  int deleteCalls = 0;
  Future<void> Function(int index, Map<String, dynamic> body)? onChat;
}
