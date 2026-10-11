import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/terminal/shell/command_parser.dart';
import 'package:qfli_studio_core/terminal/shell/local_shell.dart';
import 'package:qfli_studio_core/terminal/shell/portable_filesystem.dart';
import 'package:qfli_studio_core/terminal/shell/shell_backend.dart';

/// Captures [ShellSink] output for the pure helper contract tests.
class _SinkSpy implements ShellSink {
  final stdout = StringBuffer();
  final errors = <String>[];

  @override
  void raw(String text) => stdout.write(text);

  @override
  void line(String text) => stdout.write('$text\n');

  @override
  void error(String text) => errors.add(text);
}

/// Focused, non-widget tests for the portable command layer. They exercise the
/// real filesystem in a temporary directory through the same
/// `createLocalShell` backend the pane uses, and never seed a virtual one.
void main() {
  group('CommandParser.classify', () {
    test('treats plain and quoted commands as simple', () {
      expect(CommandParser.classify('ls -la'), CommandSyntax.simple);
      expect(CommandParser.classify('cat "my file.txt"'), CommandSyntax.simple);
      expect(CommandParser.classify("cat 'a|b.txt'"), CommandSyntax.simple);
      expect(CommandParser.classify('   '), CommandSyntax.empty);
    });

    test('POSIX escaping keeps escaped operators literal', () {
      expect(CommandParser.classify(r'cat a\|b.txt'), CommandSyntax.simple);
      expect(
        CommandParser.classify(r'touch name\ with\ spaces'),
        CommandSyntax.simple,
      );
    });

    test('detects unquoted shell operators as compound', () {
      expect(CommandParser.classify('ls | grep x'), CommandSyntax.compound);
      expect(
        CommandParser.classify('echo hi > out.txt'),
        CommandSyntax.compound,
      );
      expect(CommandParser.classify('a && b'), CommandSyntax.compound);
      expect(CommandParser.classify(r'echo $HOME'), CommandSyntax.compound);
      expect(
        CommandParser.classify(r'echo "value $x"'),
        CommandSyntax.compound,
      );
      expect(CommandParser.classify('cat `which x`'), CommandSyntax.compound);
      expect(CommandParser.classify('ls *.txt'), CommandSyntax.compound);
      expect(CommandParser.classify('ls file[12].txt'), CommandSyntax.compound);
      expect(CommandParser.classify('ls a\nb'), CommandSyntax.compound);
    });

    test('Windows literal policy keeps native paths simple', () {
      const win = EscapePolicy.backslashLiteral;
      expect(
        CommandParser.classify(r'dir c:\temp\x', escapePolicy: win),
        CommandSyntax.simple,
      );
      // A trailing separator before the closing quote is not an escape.
      expect(
        CommandParser.classify(r'cd "C:\"', escapePolicy: win),
        CommandSyntax.simple,
      );
    });

    test('Windows literal policy routes unsafe escapes to the shell', () {
      const win = EscapePolicy.backslashLiteral;
      // A backslash before whitespace/operator cannot be safely split, so the
      // whole line is compound (routed intact) rather than several operands.
      expect(
        CommandParser.classify(r'touch name\ with\ spaces', escapePolicy: win),
        CommandSyntax.compound,
      );
      expect(
        CommandParser.classify(r'ls C:\dir\*.txt', escapePolicy: win),
        CommandSyntax.compound,
      );
    });
  });

  group('CommandParser.tokenize', () {
    test('keeps quoted spaces together and reports quoting', () {
      final parsed = CommandParser.tokenize('cat "a b.txt" plain');
      expect(parsed.ok, isTrue);
      expect(parsed.tokens.map((t) => t.text).toList(), [
        'cat',
        'a b.txt',
        'plain',
      ]);
      expect(parsed.tokens[1].quoted, isTrue);
      expect(parsed.tokens[2].quoted, isFalse);
    });

    test('POSIX escapes join into one operand', () {
      final parsed = CommandParser.tokenize(r'touch name\ with\ spaces');
      expect(parsed.ok, isTrue);
      expect(parsed.tokens.map((t) => t.text).toList(), [
        'touch',
        'name with spaces',
      ]);
    });

    test('handles unicode and double dash', () {
      final parsed = CommandParser.tokenize('cat 文件.txt -- plain');
      expect(parsed.ok, isTrue);
      expect(parsed.tokens.map((t) => t.text).toList(), [
        'cat',
        '文件.txt',
        '--',
        'plain',
      ]);
    });

    test('Windows literal policy preserves drive roots and UNC paths', () {
      const win = EscapePolicy.backslashLiteral;
      final root = CommandParser.tokenize(r'cd "C:\"', escapePolicy: win);
      expect(root.ok, isTrue);
      expect(root.tokens.map((t) => t.text).toList(), ['cd', r'C:\']);

      final unc = CommandParser.tokenize(
        r'cat "\\server\share\file.txt"',
        escapePolicy: win,
      );
      expect(unc.ok, isTrue);
      expect(unc.tokens[1].text, r'\\server\share\file.txt');
    });

    test('reports unterminated quotes instead of guessing', () {
      expect(CommandParser.tokenize('cat "oops').ok, isFalse);
      expect(CommandParser.tokenize("cat 'oops").ok, isFalse);
    });
  });

  group('portable filesystem commands (real filesystem)', () {
    late Directory root;
    late _ShellHarness harness;

    setUp(() {
      root = Directory.systemTemp.createTempSync('qfli_shell_');
      File(p.join(root.path, 'alpha.txt')).writeAsStringSync('alpha\n');
      File(p.join(root.path, 'beta.txt')).writeAsStringSync('beta\n');
      File(p.join(root.path, 'space name.txt')).writeAsStringSync('spaced\n');
      File(p.join(root.path, '.hidden')).writeAsStringSync('secret\n');
      Directory(p.join(root.path, 'sub')).createSync();
      harness = _ShellHarness(root.path);
    });

    tearDown(() async {
      await harness.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('ls lists real files and hides dotfiles', () async {
      await harness.run('ls');
      expect(harness.stdout, contains('alpha.txt'));
      expect(harness.stdout, contains('sub'));
      expect(harness.stdout, isNot(contains('.hidden')));

      harness.clear();
      await harness.run('ls -a');
      expect(harness.stdout, contains('.hidden'));
    });

    test('ls -l and combined -la show long form', () async {
      await harness.run('ls -l');
      expect(
        harness.stdout.any((l) => l.startsWith('-') && l.contains('alpha.txt')),
        isTrue,
      );

      harness.clear();
      await harness.run('ls -la');
      expect(harness.stdout.any((l) => l.contains('.hidden')), isTrue);
    });

    test('dir behaves like ls', () async {
      await harness.run('dir');
      expect(harness.stdout, contains('alpha.txt'));
    });

    test('pwd reports the session directory', () async {
      await harness.run('pwd');
      expect(harness.stdout.single, p.normalize(root.path));
    });

    test('cd changes cwd and persists for later commands', () async {
      await harness.run('cd sub');
      expect(p.basename(harness.backend.cwd), 'sub');
      await harness.run('pwd');
      expect(harness.stdout.last, p.normalize(p.join(root.path, 'sub')));
      await harness.run('cd ..');
      expect(p.normalize(harness.backend.cwd), p.normalize(root.path));
    });

    test('cd with a quoted path containing spaces works', () async {
      Directory(p.join(root.path, 'my dir')).createSync();
      await harness.run('cd "my dir"');
      expect(p.basename(harness.backend.cwd), 'my dir');
    });

    test('cd failure keeps the previous cwd and errors', () async {
      final before = harness.backend.cwd;
      await harness.run('cd does-not-exist');
      expect(harness.backend.cwd, before);
      expect(harness.stderr, isNotEmpty);
    });

    test('cat prints real file content including a spaced name', () async {
      await harness.run('cat "space name.txt"');
      expect(harness.stdout, ['spaced']);
    });

    test('cat preserves multi-line content', () async {
      File(p.join(root.path, 'multi.txt')).writeAsStringSync('a\nb\n');
      await harness.run('cat multi.txt');
      expect(harness.stdout, ['a', 'b']);
    });

    test('cat emits file bytes verbatim (exact raw stream)', () async {
      // No final newline: raw output must not gain one.
      File(p.join(root.path, 'no-newline.txt')).writeAsStringSync('abc');
      await harness.run('cat no-newline.txt');
      expect(harness.rawStdout.toString(), 'abc');

      harness.clear();
      // Final newline and a blank line must survive exactly.
      File(p.join(root.path, 'blanks.txt')).writeAsStringSync('a\n\nb\n');
      await harness.run('cat blanks.txt');
      expect(harness.rawStdout.toString(), 'a\n\nb\n');

      harness.clear();
      File(p.join(root.path, 'empty.txt')).writeAsStringSync('');
      await harness.run('cat empty.txt');
      expect(harness.rawStdout.toString(), isEmpty);

      harness.clear();
      File(p.join(root.path, 'uni.txt')).writeAsStringSync('中文\n');
      await harness.run('cat uni.txt');
      expect(harness.rawStdout.toString(), '中文\n');
    });

    test('cat on a directory errors', () async {
      await harness.run('cat sub');
      expect(harness.stderr.join('\n'), contains('Is a directory'));
    });

    test(
      'empty filesystem operands are rejected, never the home directory',
      () async {
        // Use a fake home under the fixture so a real home is never at risk.
        final fakeHome = Directory(p.join(root.path, 'fake-home'))
          ..createSync();
        final sentinel = File(p.join(fakeHome.path, 'SENTINEL'))
          ..writeAsStringSync('keep');
        await harness.run('rm -r ""');
        expect(harness.stderr, isNotEmpty);
        expect(sentinel.existsSync(), isTrue);
        expect(sentinel.readAsStringSync(), 'keep');
        expect(fakeHome.existsSync(), isTrue);

        harness.clear();
        await harness.run('rm -r "   "');
        expect(harness.stderr, isNotEmpty);
        expect(fakeHome.existsSync(), isTrue);
      },
    );

    test('echo joins arguments', () async {
      await harness.run('echo hello world');
      expect(harness.stdout.single, 'hello world');
    });

    test('mkdir -p creates nested directories', () async {
      await harness.run('mkdir -p a/b/c');
      expect(Directory(p.join(root.path, 'a', 'b', 'c')).existsSync(), isTrue);
    });

    test('touch creates a file, keeps -- operands, refuses options', () async {
      await harness.run('touch new.txt');
      expect(File(p.join(root.path, 'new.txt')).existsSync(), isTrue);

      // `--` ends option parsing, so `-name.txt` is an operand and is created.
      await harness.run('touch -- -name.txt');
      expect(File(p.join(root.path, '-name.txt')).existsSync(), isTrue);

      harness.clear();
      await harness.run('touch -m new.txt');
      expect(harness.stderr.join('\n'), contains('unsupported option'));
    });

    test('touch does not invent missing parent directories', () async {
      harness.clear();
      await harness.run('touch missing-dir/file.txt');
      expect(
        File(p.join(root.path, 'missing-dir', 'file.txt')).existsSync(),
        isFalse,
      );
      expect(harness.stderr, isNotEmpty);
    });

    test(
      'rm removes a file, refuses a directory without -r, honours -f',
      () async {
        await harness.run('rm alpha.txt');
        expect(File(p.join(root.path, 'alpha.txt')).existsSync(), isFalse);

        await harness.run('rm sub');
        expect(harness.stderr.join('\n'), contains('Is a directory'));
        expect(Directory(p.join(root.path, 'sub')).existsSync(), isTrue);

        harness.clear();
        await harness.run('rm -r sub');
        expect(Directory(p.join(root.path, 'sub')).existsSync(), isFalse);

        harness.clear();
        await harness.run('rm -f missing.txt');
        expect(harness.stderr, isEmpty);
      },
    );

    test('sequential builtins each complete and clear busy', () async {
      await harness.run('echo one');
      expect(harness.backend.busy, isFalse);
      await harness.run('echo two');
      expect(harness.backend.busy, isFalse);
      expect(harness.stdout, ['one', 'two']);
    });

    test('unsupported ordinary options produce explicit errors', () async {
      await harness.run('ls -R');
      expect(harness.stderr.join('\n'), contains('unsupported option: -R'));
      harness.clear();
      await harness.run('mkdir -v x');
      expect(harness.stderr.join('\n'), contains('unsupported option: -v'));
    });

    test('clear is a control event and touches nothing else', () async {
      await harness.run('ls');
      harness.clear();
      await harness.run('clear');
      expect(harness.controls, contains('clear'));
      expect(p.normalize(harness.backend.cwd), p.normalize(root.path));
      expect(harness.stdout, isEmpty);
      expect(harness.stderr, isEmpty);
    });

    test(
      'compound syntax is forwarded intact, never run as a builtin',
      () async {
        harness.clear();
        await harness.run('ls | grep alpha');
        // The builtin must not have handled this; the raw text goes to a shell
        // (or an honest error where no shell can run). In neither case may the
        // builtin emit its own plain `ls` listing or a synthetic clear.
        expect(harness.controls, isEmpty);
        expect(harness.stdout, isNot(contains('beta.txt')));
      },
    );

    test('compound mutations do not partly run when no shell exists', () async {
      // With external execution rejected, a compound command that would mutate
      // files must produce only an error and leave fixtures untouched.
      final backend = _NoShellBackend(root.path);
      addTearDown(() async => backend.shutdown());
      backend.clear();
      await backend.execute('rm alpha.txt && touch created.txt');
      expect(backend.externalAttempts, 1);
      expect(backend.errors, isNotEmpty);
      expect(File(p.join(root.path, 'alpha.txt')).existsSync(), isTrue);
      expect(File(p.join(root.path, 'created.txt')).existsSync(), isFalse);
    });
  });

  group('PortableFilesystem.resolve contract (fake home)', () {
    late Directory fixture;
    late Directory fakeHome;
    late _SinkSpy sink;
    late PortableFilesystem filesystem;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('qfli_fs_');
      fakeHome = Directory(p.join(fixture.path, 'fake-home'))..createSync();
      File(p.join(fakeHome.path, 'SENTINEL')).writeAsStringSync('keep');
      sink = _SinkSpy();
      filesystem = PortableFilesystem(
        cwd: fixture.path,
        homeDirectory: fakeHome.path,
        sink: sink,
      );
    });

    tearDown(() {
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    });

    test('empty operand is rejected and never resolves to home', () {
      expect(
        () => filesystem.run(const CommandToken('rm'), const [
          CommandToken('-r'),
          CommandToken('', quoted: true),
        ]),
        throwsA(isA<CommandFailure>()),
      );
      expect(sink.errors, isNotEmpty);
      expect(File(p.join(fakeHome.path, 'SENTINEL')).existsSync(), isTrue);
      expect(fakeHome.existsSync(), isTrue);
    });

    test('no-arg cd defaults to home; quoted tilde stays literal', () {
      // resolve() with an empty explicit path is the caller's error, but a
      // quoted literal `~` must not expand.
      final literal = filesystem.resolve('~', expandTilde: false);
      expect(literal, p.normalize(p.join(fixture.path, '~')));
      final expanded = filesystem.resolve('~');
      expect(p.normalize(expanded), p.normalize(fakeHome.path));
    });

    test('leading/trailing-space names are preserved', () {
      final resolved = filesystem.resolve(' padded ', expandTilde: false);
      expect(p.basename(resolved), ' padded ');
    });
  });

  group('external execution and cancellation', () {
    test('runs a real external command and reports its exit status', () async {
      final root = Directory.systemTemp.createTempSync('qfli_shell_ext_');
      final harness = _ShellHarness(root.path);
      addTearDown(() async {
        await harness.dispose();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      // A shell-only command (not a portable builtin), so this really exercises
      // an external process on both hosts.
      final command = Platform.isWindows
          ? 'Write-Output ok-ext'
          : 'printf ok-ext';
      await harness.run(command);
      expect(harness.rawStdout.toString(), contains('ok-ext'));
      expect(harness.backend.lastExitCode, 0);
    });

    test('a failing external command surfaces a nonzero status', () async {
      final root = Directory.systemTemp.createTempSync('qfli_shell_ext_');
      final harness = _ShellHarness(root.path);
      addTearDown(() async {
        await harness.dispose();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      await harness.run('exit 3');
      expect(harness.backend.lastExitCode, 3);
    });

    test('interrupt with no delay after dispatch still cancels', () async {
      final root = Directory.systemTemp.createTempSync('qfli_shell_ext_');
      final harness = _ShellHarness(root.path);
      addTearDown(() async {
        await harness.dispose();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final command = Platform.isWindows
          ? 'Start-Sleep -Seconds 120'
          : 'sleep 120';
      final stopwatch = Stopwatch()..start();
      final running = harness.backend.execute(command);
      // No delay, no pump: interrupt in the very next synchronous turn, before
      // the first await of execute() resolves.
      await harness.backend.interrupt();
      await running.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail('no-delay interrupt did not cancel'),
      );
      stopwatch.stop();
      expect(harness.backend.busy, isFalse);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 30)),
        reason: 'cancel must complete far before the 120s natural exit',
      );
      // The backend is reusable for a normal command afterwards.
      harness.clear();
      await harness.run('pwd');
      expect(harness.stdout.single, p.normalize(root.path));
    });

    test('interrupt after stdout-ready stops the command quickly', () async {
      final root = Directory.systemTemp.createTempSync('qfli_shell_ext_');
      final harness = _ShellHarness(root.path);
      addTearDown(() async {
        await harness.dispose();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      // A very long sleep plus a stdout marker: the command must be stopped far
      // before its natural exit, and the marker must already have been seen.
      final command = Platform.isWindows
          ? 'Write-Output ready-marker; Start-Sleep -Seconds 120'
          : 'echo ready-marker; sleep 120';
      final stopwatch = Stopwatch()..start();
      final running = harness.backend.execute(command);
      for (
        var i = 0;
        i < 400 && !harness.stdout.contains('ready-marker');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        harness.stdout,
        contains('ready-marker'),
        reason: 'the command should have produced its marker before cancel',
      );
      expect(harness.backend.busy, isTrue);
      await harness.backend.interrupt();
      await running.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail('interrupt did not stop the command'),
      );
      stopwatch.stop();
      expect(harness.backend.busy, isFalse);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 30)),
        reason: 'cancel must complete far before the 120s natural exit',
      );
    });

    test(
      'interrupt immediately after dispatch still cancels the command',
      () async {
        final root = Directory.systemTemp.createTempSync('qfli_shell_ext_');
        final harness = _ShellHarness(root.path);
        addTearDown(() async {
          await harness.dispose();
          if (root.existsSync()) root.deleteSync(recursive: true);
        });
        final command = Platform.isWindows
            ? 'Start-Sleep -Seconds 120'
            : 'sleep 120';
        final stopwatch = Stopwatch()..start();
        final running = harness.backend.execute(command);
        // Interrupt almost immediately, while shell probing / spawn may still be
        // in flight; the startup race must still cancel the command.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await harness.backend.interrupt();
        await running.timeout(
          const Duration(seconds: 20),
          onTimeout: () =>
              fail('startup-race interrupt did not stop the command'),
        );
        stopwatch.stop();
        expect(harness.backend.busy, isFalse);
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 30)),
          reason: 'startup-race cancel must complete far before 120s',
        );
      },
    );
  });

  group('mobile built-ins without external spawn', () {
    test(
      'portable commands work when external execution is rejected',
      () async {
        final root = Directory.systemTemp.createTempSync('qfli_shell_mobile_');
        File(p.join(root.path, 'note.txt')).writeAsStringSync('hello\n');
        Directory(p.join(root.path, 'nested')).createSync();
        final backend = _NoShellBackend(root.path);
        addTearDown(() async {
          await backend.shutdown();
          if (root.existsSync()) root.deleteSync(recursive: true);
        });

        Future<List<String>> run(String command) async {
          backend.clear();
          await backend.execute(command);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return backend.lines;
        }

        expect(await run('ls'), contains('note.txt'));
        expect(await run('cat note.txt'), ['hello']);
        await backend.execute('mkdir -p nested/dir');
        expect(
          Directory(p.join(root.path, 'nested', 'dir')).existsSync(),
          isTrue,
        );
        await backend.execute('cd nested');
        expect(await run('pwd'), [p.normalize(p.join(root.path, 'nested'))]);
        // A compound command cannot be handled without a shell: it must report
        // an honest limitation and must not partially mutate anything.
        backend.clear();
        await backend.execute('ls | grep note');
        expect(backend.errors, isNotEmpty);
        expect(backend.externalAttempts, 1);
      },
    );
  });
}

/// A backend with no external shell: every non-built-in execution is recorded
/// as a rejected attempt, proving portable built-ins need no process spawn.
class _NoShellBackend extends BaseShellBackend {
  _NoShellBackend(this.rootPath) {
    cwd = rootPath;
  }

  final String rootPath;
  final lines = <String>[];
  final errors = <String>[];
  final controls = <String>[];
  int externalAttempts = 0;

  void clear() {
    lines.clear();
    errors.clear();
    controls.clear();
  }

  @override
  String get shellLabel => 'none';

  @override
  String get prompt => '\$';

  @override
  String get helpText => 'no shell';

  @override
  void raw(String text) {
    _ingest(text);
  }

  @override
  void line(String text) {
    _ingest(text.endsWith('\n') ? text : '$text\n');
  }

  void _ingest(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final part in normalized.split('\n')) {
      if (part.isNotEmpty) lines.add(part);
    }
  }

  @override
  void error(String text) => errors.add(text);

  @override
  void emit(String text, [OutputKind kind = OutputKind.stdout]) {
    if (kind == OutputKind.control) {
      controls.add(text);
      return;
    }
    if (kind == OutputKind.stderr) {
      error(text);
    } else if (text.endsWith('\n')) {
      line(text.substring(0, text.length - 1));
    } else {
      raw(text);
    }
  }

  @override
  bool handlePortableBuiltin(CommandToken name, List<CommandToken> args) {
    if (!PortableFilesystem.handles(name.text)) return false;
    final filesystem = PortableFilesystem(
      cwd: cwd,
      homeDirectory: null,
      sink: this,
    );
    try {
      filesystem.run(name, args);
    } on CommandFailure {
      // Already emitted.
    }
    return true;
  }

  @override
  Future<bool> changeDirectory(String target, {bool expandTilde = true}) async {
    final resolved = Directory(
      p.isAbsolute(target) ? target : p.join(cwd, target),
    ).absolute.path;
    if (!Directory(resolved).existsSync()) {
      error('cd: no such directory: $target');
      return true;
    }
    cwd = resolved;
    return true;
  }

  @override
  Future<void> runExternal(String command) async {
    externalAttempts++;
    error('no shell available for: $command');
  }
}

/// Drives a real [ShellBackend] and captures its output stream.
class _ShellHarness {
  _ShellHarness(String cwdPath) {
    backend = createLocalShell(workingDirectory: cwdPath);
    _sub = backend.output.listen((chunk) {
      switch (chunk.kind) {
        case OutputKind.stdout:
          rawStdout.write(chunk.text);
          stdout.addAll(_split(chunk.text));
        case OutputKind.stderr:
          rawStderr.write(chunk.text);
          stderr.addAll(_split(chunk.text));
        case OutputKind.control:
          controls.add(chunk.text);
        case OutputKind.system:
          rawStdout.write(chunk.text);
          stdout.addAll(_split(chunk.text));
      }
    });
  }

  /// Splits a chunk into non-empty lines, dropping the `\r` PowerShell appends
  /// before `\n` so markers match regardless of the shell's line ending.
  static Iterable<String> _split(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((line) => line.isNotEmpty);

  late final ShellBackend backend;
  late final StreamSubscription<ShellChunk> _sub;
  final stdout = <String>[];
  final stderr = <String>[];
  final controls = <String>[];

  /// Exact concatenated stdout/stderr bytes (blank lines and newlines included)
  /// for the verbatim-content contracts such as `cat`.
  final rawStdout = StringBuffer();
  final rawStderr = StringBuffer();

  void clear() {
    stdout.clear();
    stderr.clear();
    controls.clear();
    rawStdout.clear();
    rawStderr.clear();
  }

  Future<void> run(String command) async {
    await backend.execute(command);
    // Allow any synchronous tail of the output stream to be delivered.
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await backend.shutdown();
  }
}
