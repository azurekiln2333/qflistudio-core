import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/terminal/shell/local_shell_io.dart';
import 'package:qfli_studio_core/terminal/shell/sandbox_shell_backend.dart';
import 'package:qfli_studio_core/terminal/shell/shell_backend.dart';

/// Collects [SandboxShellBackend] output for assertions.
class _Harness {
  _Harness(String root, {String? start, TerminalCommandDelegate? delegate}) {
    backend = SandboxShellBackend(
      sandboxRoot: root,
      startDirectory: start,
      delegate: delegate,
    );
    _sub = backend.output.listen((chunk) {
      switch (chunk.kind) {
        case OutputKind.stdout:
          out.addAll(chunk.text.replaceAll('\r\n', '\n').split('\n').where((l) => l.isNotEmpty));
        case OutputKind.stderr:
          err.addAll(chunk.text.replaceAll('\r\n', '\n').split('\n').where((l) => l.isNotEmpty));
        case OutputKind.system:
          out.addAll(chunk.text.replaceAll('\r\n', '\n').split('\n').where((l) => l.isNotEmpty));
        case OutputKind.control:
          controls.add(chunk.text);
      }
    });
  }

  late final SandboxShellBackend backend;
  late final StreamSubscription<ShellChunk> _sub;
  final out = <String>[];
  final err = <String>[];
  final controls = <String>[];

  void clear() {
    out.clear();
    err.clear();
    controls.clear();
  }

  Future<void> run(String command) async {
    await backend.execute(command);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await backend.shutdown();
  }
}

void main() {
  late Directory appData;
  late Directory project;
  _FakeProcessShell? registeredShell;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('qfli_sandbox_app_');
    project = Directory(p.join(appData.path, 'projects', 'demo'))
      ..createSync(recursive: true);
    File(p.join(project.path, 'Main.java')).writeAsStringSync('class Main {}\n');
    File(p.join(appData.path, 'notes.txt')).writeAsStringSync('root note\n');
  });

  tearDown(() {
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  group('sandbox root by entry point', () {
    test('editor entry starts in the project and can cd back to app data', () async {
      final h = _Harness(appData.path, start: project.path);
      addTearDown(h.dispose);
      await h.run('pwd');
      expect(h.out.last, contains('demo'));
      // Cross-project: cd up to the app data dir and list the root note.
      await h.run('cd ${appData.path}');
      expect(h.backend.cwd, appData.path);
      await h.run('ls');
      expect(h.out, contains('notes.txt'));
    });

    test('app entry starts at the app data directory', () async {
      final h = _Harness(appData.path, start: appData.path);
      addTearDown(h.dispose);
      await h.run('ls');
      expect(h.out, contains('notes.txt'));
      await h.run('cd projects/demo');
      expect(h.backend.cwd, project.path);
      await h.run('ls');
      expect(h.out, contains('Main.java'));
    });
  });

  group('sandbox cannot escape the root', () {
    test('cd .. above the root is rejected and cwd is kept', () async {
      final h = _Harness(appData.path, start: appData.path);
      addTearDown(h.dispose);
      await h.run('cd ../../..'); // nothing to escape on temp; still inside
      // Explicit escape via an absolute system path must be rejected.
      h.clear();
      final outside = Directory.systemTemp.createTempSync('qfli_outside_');
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      await h.run('cd "${outside.path}"');
      expect(h.err.join('\n'), contains('沙盒'));
      expect(h.backend.cwd, appData.path);
    });
  });

  group('sandbox file commands and options', () {
    test('ls -a / cat / mkdir -p / touch / rm work on real files', () async {
      final h = _Harness(appData.path, start: appData.path);
      addTearDown(h.dispose);
      File(p.join(appData.path, '.hidden')).writeAsStringSync('h\n');
      await h.run('ls');
      expect(h.out, isNot(contains('.hidden')));
      h.clear();
      await h.run('ls -a');
      expect(h.out, contains('.hidden'));

      h.clear();
      await h.run('cat notes.txt');
      expect(h.out, ['root note']);

      h.clear();
      await h.run('mkdir -p a/b');
      expect(Directory(p.join(appData.path, 'a', 'b')).existsSync(), isTrue);

      await h.run('touch a/b/empty.txt');
      expect(File(p.join(appData.path, 'a', 'b', 'empty.txt')).existsSync(), isTrue);

      await h.run('rm -r a');
      expect(Directory(p.join(appData.path, 'a')).existsSync(), isFalse);
    });

    test('cp and mv operate within the sandbox', () async {
      final h = _Harness(appData.path, start: appData.path);
      addTearDown(h.dispose);
      await h.run('cp notes.txt copy.txt');
      expect(File(p.join(appData.path, 'copy.txt')).readAsStringSync(),
          'root note\n');
      await h.run('mv copy.txt moved.txt');
      expect(File(p.join(appData.path, 'copy.txt')).existsSync(), isFalse);
      expect(File(p.join(appData.path, 'moved.txt')).existsSync(), isTrue);
    });
  });

  group('delegate and unsupported commands', () {
    test('a delegate handles java/javac and its output is streamed', () async {
      var seen = '';
      final h = _Harness(
        appData.path,
        start: appData.path,
        delegate: (backend, command) async {
          if (!command.startsWith('javac')) return false;
          seen = command;
          await backend.runStreams(
            title: 'javac Main.java',
            stdout: Stream<String>.value('compiled'),
            stderr: const Stream<String>.empty(),
            exitCode: Future<int>.value(0),
          );
          return true;
        },
      );
      addTearDown(h.dispose);
      await h.run('javac Main.java');
      expect(seen, 'javac Main.java');
      expect(h.out, contains('compiled'));
    });

    test('delegate exit status is recorded and nonzero is visible', () async {
      final h = _Harness(
        appData.path,
        start: appData.path,
        delegate: (backend, command) async {
          if (!command.startsWith('java ')) return false;
          await backend.runStreams(
            title: 'java Main',
            stdout: const Stream<String>.empty(),
            stderr: Stream<String>.value('boom'),
            exitCode: Future<int>.value(3),
          );
          return true;
        },
      );
      addTearDown(h.dispose);
      await h.run('java Main');
      expect(h.err, contains('boom'));
      expect(h.backend.lastExitCode, 3);
    });

    test('unknown system command without a delegate reports honestly', () async {
      final h = _Harness(appData.path, start: appData.path);
      addTearDown(h.dispose);
      await h.run('git status');
      expect(h.err.join('\n'), contains('不支持'));
      expect(h.out, isEmpty);
    });

    test('an unclaimed command with a delegate still reports honestly', () async {
      final h = _Harness(
        appData.path,
        start: appData.path,
        delegate: (backend, command) async => false,
      );
      addTearDown(h.dispose);
      await h.run('grep x notes.txt');
      expect(h.err.join('\n'), contains('不支持'));
    });
  });

  group('compound shell syntax is refused by construct, not by name', () {
    Future<_Harness> mobile() async {
      final h = _Harness(
        appData.path,
        start: project.path,
        // A delegate that claims a plain java/javac line only; a compound line
        // falls through to the honest construct message, which is exactly what
        // the sandbox must report when nobody claims it.
        delegate: (backend, command) async {
          if (RegExp(r'[|&;<>`*?\[\]]|\$\(').hasMatch(command)) return false;
          return command.startsWith('javac') ||
              command.startsWith('java ') ||
              command == 'java';
        },
      );
      addTearDown(h.dispose);
      return h;
    }

    void expectNoGenericWording(_Harness h) {
      final message = h.err.join('\n');
      // The generic "this command is unsupported" text must not be used: it
      // mislabels a pipeline as an unknown tool named by the first token.
      expect(message, isNot(contains('不支持该命令')));
      expect(message, contains('当前平台的内置终端不支持'));
    }

    test('a pipeline names the pipeline, not the first token', () async {
      final h = await mobile();
      await h.run('javac Main.java | tail -n 5');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('管道'));
      // The command token must not be blamed as an unknown command.
      expect(h.err.join('\n'), isNot(contains('javac:')));
    });

    test('output redirection names redirection', () async {
      final h = await mobile();
      await h.run('ls > listing.txt');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('重定向'));
    });

    test('input redirection names redirection', () async {
      final h = await mobile();
      await h.run('cat < notes.txt');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('重定向'));
    });

    test('chaining names chaining', () async {
      final h = await mobile();
      await h.run('ls && pwd');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('串联'));
    });

    test('semicolon chaining names chaining', () async {
      final h = await mobile();
      await h.run('ls; pwd');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('串联'));
    });

    test('command substitution names command substitution', () async {
      final h = await mobile();
      await h.run('echo \$(pwd)');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('命令替换'));
    });

    test('a glob names wildcard expansion', () async {
      final h = await mobile();
      await h.run('ls *.java');
      expectNoGenericWording(h);
      expect(h.err.join('\n'), contains('通配符'));
    });

    test('a quoted operator is a literal operand, not syntax', () async {
      final h = await mobile();
      // The operator sits inside quotes, so the line is a simple command and
      // must reach the built-in instead of the compound refusal.
      await h.run('echo "a|b"');
      expect(h.out.join('\n'), contains('a|b'));
      expect(h.err, isEmpty);
    });

    test('a plain unknown command keeps the generic honest message', () async {
      final h = await mobile();
      await h.run('frobnicate --now');
      expect(h.err.join('\n'), contains('不支持该命令'));
      expect(h.err.join('\n'), contains('frobnicate'));
    });

    test('an accepted delegate still gets first refusal for a compound line',
        () async {
      var claimed = '';
      final h = _Harness(
        appData.path,
        start: project.path,
        delegate: (backend, command) async {
          claimed = command;
          return true;
        },
      );
      addTearDown(h.dispose);
      await h.run('git log | head');
      expect(claimed, 'git log | head');
      expect(h.err, isEmpty);
    });
  });

  group('terminal cwd contract', () {
    test('the delegate sees the cwd the user cd-ed into', () async {
      File(p.join(project.path, 'nested.txt')).writeAsStringSync('nested\n');
      Directory(p.join(project.path, 'src')).createSync();
      final seenCwd = <String>[];
      late SandboxShellBackend captured;
      final h = _Harness(
        appData.path,
        start: project.path,
        delegate: (backend, command) async {
          captured = backend;
          seenCwd.add(backend.cwd);
          return command.startsWith('javac') || command.startsWith('java ');
        },
      );
      addTearDown(h.dispose);

      // Before cd: the delegate sees the start directory.
      await h.run('javac Main.java');
      expect(seenCwd.last, project.path);

      // After cd: the delegate must see the new directory, not a stale one.
      await h.run('cd src');
      final expected = p.join(project.path, 'src');
      expect(h.backend.cwd, expected);
      await h.run('java Main');
      expect(seenCwd.last, expected);
      expect(captured.cwd, h.backend.cwd);
      expect(p.equals(seenCwd.last, h.backend.cwd), isTrue,
          reason: 'toolchain cwd must be the directory the prompt shows');
    });

    test('the delegate sees the cwd after cd back above the start directory',
        () async {
      final seenCwd = <String>[];
      final h = _Harness(
        appData.path,
        start: project.path,
        delegate: (backend, command) async {
          seenCwd.add(backend.cwd);
          return command.startsWith('javac');
        },
      );
      addTearDown(h.dispose);
      await h.run('cd ${appData.path}');
      expect(h.backend.cwd, appData.path);
      await h.run('javac Main.java');
      expect(p.equals(seenCwd.single, appData.path), isTrue);
    });

    test('desktop fallback is offered a compound line before the refusal',
        () async {
      // `createSandboxShell` wraps the Java delegate and then the real desktop
      // shell, so on a platform with a real shell a compound line is claimed
      // by the shell and the construct message must not appear. A host without
      // a usable shell legitimately produces the refusal instead.
      final claimed = <String>[];
      final backend = createSandboxShell(
        sandboxRoot: appData.path,
        startDirectory: appData.path,
        delegate: (backend, command) async {
          claimed.add(command);
          return false;
        },
      );
      addTearDown(backend.shutdown);
      final err = <String>[];
      final out = <String>[];
      final sub = backend.output.listen((chunk) {
        if (chunk.kind == OutputKind.stderr) {
          err.add(chunk.text);
        } else if (chunk.kind == OutputKind.stdout) {
          out.add(chunk.text);
        }
      });
      addTearDown(sub.cancel);

      await backend.execute('echo hi | cat');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // The Java/app delegate always got first look at the raw compound line.
      expect(claimed, contains('echo hi | cat'));
      if (localShellAvailable()) {
        // Desktop: the real shell handled the pipeline; no refusal at all and
        // its output must actually reach the terminal (not be silently
        // swallowed by the fallback wrapper).
        expect(err.join('\n'), isNot(contains('不支持')));
        expect(err.join('\n'), isNot(contains('管道')));
        expect(out.join('\n'), contains('hi'));
      }
    });
  });

  group('desktop fallback forwards the real shell output', () {
    test('delegateToProcessShell mirrors stdout/stderr and the exit status',
        () async {
      final h = _Harness(appData.path, start: appData.path);
      addTearDown(h.dispose);
      final shell = _FakeProcessShell();
      addTearDown(shell.shutdown);

      // The real shell emits on its OWN stream; without forwarding the sandbox
      // would see nothing and report no exit status. Emit from inside execute
      // so the chunks land while the sandbox subscription is still live.
      shell.onExecute = () async {
        shell.push('hello-from-shell\n', OutputKind.stdout);
        shell.push('warn-text\n', OutputKind.stderr);
      };
      await h.backend.delegateToProcessShell(shell, 'whoami');

      expect(h.out, contains('hello-from-shell'));
      expect(h.err, contains('warn-text'));
      expect(h.backend.lastExitCode, 7);
    });

    test('the fallback is used through execute() for an unknown command',
        () async {
      final h = _Harness(
        appData.path,
        start: appData.path,
        delegate: (backend, command) async {
          // Simulate the desktop wrapper: unknown command -> real shell.
          await backend.delegateToProcessShell(_FakeProcessShell(), command);
          return true;
        },
      );
      addTearDown(h.dispose);
      await h.run('git status');
      expect(h.backend.lastExitCode, 7);
    });

    test('a cancelled fallback does not publish a program exit status',
        () async {
      final h = _Harness(
        appData.path,
        start: appData.path,
        delegate: (backend, command) async {
          final shell = _FakeProcessShell(exitCode: 3);
          addTearDown(shell.shutdown);
          // Interrupt the sandbox mid-command; it must reach the real shell and
          // the cancelled status must not be shown as the program's result.
          shell.onExecute = () => backend.interrupt();
          await backend.delegateToProcessShell(shell, command);
          registeredShell = shell;
          return true;
        },
      );
      addTearDown(h.dispose);
      await h.run('sleep 10');
      expect(h.backend.lastExitCode, isNull);
      expect(registeredShell!.interrupted, isTrue);
    });
  });
}

/// A [ShellBackend] double that emits canned output and a fixed exit status,
/// used to pin the desktop process-shell forwarding contract without spawning a
/// real process.
class _FakeProcessShell extends BaseShellBackend {
  _FakeProcessShell({this.exitCode = 7});

  final int exitCode;
  bool interrupted = false;
  Future<void> Function()? onExecute;

  void push(String text, OutputKind kind) =>
      emitLine(text.trimRight(), kind);

  @override
  String get shellLabel => 'fake';

  @override
  String get prompt => '> ';

  @override
  String get helpText => 'fake';

  @override
  Future<bool> changeDirectory(String target, {bool expandTilde = true}) async =>
      true;

  @override
  Future<void> runExternal(String command) async {
    final hook = onExecute;
    if (hook != null) await hook();
    lastExitCode = exitCode;
  }

  @override
  Future<void> onInterrupt() async {
    interrupted = true;
  }
}
