import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/interop/interop_payload.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_runner.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';
import 'package:qfli_studio_core/interop/interop_transport.dart';

/// Transport that records the request and replays a scripted event list.
class _FakeTransport implements InteropTransport {
  _FakeTransport({
    this.events = const <InteropEvent>[],
    this.startError,
    this.supported = true,
    this.stopOutcome,
  });

  final List<InteropEvent> events;
  final InteropException? startError;
  final bool supported;

  InteropRequest? lastRequest;
  InteropTarget? lastTarget;
  bool cancelled = false;
  /// When set, the transport can prove its stop and reports this outcome.
  final InteropStop? stopOutcome;

  @override
  bool get isSupported => supported;

  @override
  Future<InteropProbe> probe(InteropTarget target) async =>
      const InteropProbe.missing('未安装');

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    lastTarget = target;
    lastRequest = request;
    final error = startError;
    if (error != null) throw error;
    final controller = StreamController<InteropEvent>();
    scheduleMicrotask(() async {
      for (final event in events) {
        controller.add(event);
      }
      await controller.close();
    });
    return InteropLaunch(
      request: request,
      events: controller.stream,
      cancel: () async {
        cancelled = true;
      },
      stop: stopOutcome == null
          ? null
          : () async {
              cancelled = true;
              return stopOutcome!;
            },
    );
  }
}

Future<Directory> _project(Map<String, String> files) async {
  final directory = await Directory.systemTemp.createTemp('qfli-interop-');
  for (final entry in files.entries) {
    final file = File(p.join(directory.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  return directory;
}

InteropEvent _event(
  int seq,
  InteropEventKind kind, {
  String text = '',
  int? exitCode,
  String? code,
}) => InteropEvent(
  sessionId: 'ignored',
  seq: seq,
  kind: kind,
  text: text,
  exitCode: exitCode,
  code: code,
);

void main() {
  group('payload collection', () {
    test('collects nested files with relative POSIX paths', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
        'src/util/Helper.java': 'class Helper {}',
        'README.md': '# demo',
      });
      addTearDown(() => root.delete(recursive: true));
      final files = await InteropProjectPayload.collect(root.path);
      expect(files.map((file) => file.path).toList(), <String>[
        'README.md',
        'src/Main.java',
        'src/util/Helper.java',
      ]);
      expect(utf8.decode(files[1].content), 'class Main {}');
    });

    test('skips build directories and hidden files', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
        'build/out.class': 'x',
        'node_modules/x/index.js': 'x',
        '.git/config': 'x',
        '.env': 'x',
      });
      addTearDown(() => root.delete(recursive: true));
      final files = await InteropProjectPayload.collect(root.path);
      expect(files.map((file) => file.path), <String>['src/Main.java']);
    });

    test('refuses a project over the file cap', () async {
      final root = await _project(<String, String>{
        for (var index = 0; index <= InteropLimits.maxFiles; index++)
          'f$index.java': '',
      });
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        InteropProjectPayload.collect(root.path),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.payloadTooLarge,
          ),
        ),
      );
    });

    test('refuses a project over the byte cap', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'a' * (InteropLimits.maxPayloadBytes + 1),
      });
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        InteropProjectPayload.collect(root.path),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.payloadTooLarge,
          ),
        ),
      );
    });

    test('finds the entry file by language', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
        'lib/Other.java': 'class Other {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final files = await InteropProjectPayload.collect(root.path);
      expect(
        InteropProjectPayload.findEntry(files, language: 'java'),
        'lib/Other.java',
      );
      expect(
        InteropProjectPayload.findEntry(
          files,
          language: 'java',
          configuredEntry: 'src/Main.java',
        ),
        'src/Main.java',
      );
      expect(
        InteropProjectPayload.findEntry(files, language: 'python'),
        isNull,
      );
    });
  });

  group('targets', () {
    test(
      'maps languages and entry extensions to the observed bundle names',
      () {
        expect(
          InteropTargets.forLanguage('java')?.bundleName,
          'com.azurekiln.qfli.java',
        );
        expect(
          InteropTargets.forLanguage('cpp')?.bundleName,
          'com.azurekiln.qfli.cpp',
        );
        expect(
          InteropTargets.forLanguage('python')?.bundleName,
          'com.azurekiln.qfli.pyflow',
        );
        expect(InteropTargets.forLanguage('ruby'), isNull);
        expect(InteropTargets.forEntryFile('Main.java')?.language, 'java');
        expect(InteropTargets.forEntryFile('main.c')?.language, 'c');
        expect(InteropTargets.forEntryFile('main.go'), isNull);
      },
    );

    test('install hint names the product that must be installed', () {
      expect(InteropTargets.installHint('java'), contains('QFLIJVMX'));
      expect(
        InteropTargets.installHint('java'),
        contains('com.azurekiln.qfli.java'),
      );
      expect(InteropTargets.installHint('ruby'), contains('ruby'));
    });

    test('the Bridge allowlist holds exactly the sibling receivers', () {
      expect(InteropTargets.allowedCallerBundles, <String>{
        'com.azurekiln.qfli.java',
        'com.azurekiln.qfli.cpp',
        'com.azurekiln.qfli.pyflow',
      });
    });
  });

  group('runner', () {
    test('streams real output and returns the real exit code', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[
          _event(1, InteropEventKind.accepted, text: '已接收'),
          _event(2, InteropEventKind.stdout, text: 'hello'),
          _event(3, InteropEventKind.stderr, text: 'warning'),
          _event(4, InteropEventKind.done, exitCode: 0),
        ],
      );
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      final out = await run.stdout.toList();
      final err = await run.stderr.toList();
      expect(out.join('\n'), contains('hello'));
      expect(err.join('\n'), contains('warning'));
      expect(await run.exitCode, 0);
      expect(run.diagnostics, isEmpty);
      expect(transport.lastRequest?.entry, 'src/Main.java');
      expect(transport.lastTarget?.bundleName, 'com.azurekiln.qfli.java');
    });

    test('a missing app yields exit 127 and the install hint', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        startError: const InteropException(
          InteropErrorCode.appMissing,
          '未检测到 QFLIJVMX',
        ),
      );
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      expect(await run.exitCode, kInteropNotRunExitCode);
      expect(run.diagnostics.single, contains('QFLIJVMX'));
      expect(await run.stdout.toList(), isEmpty);
    });

    test('an oversized project never starts the receiver', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'a' * (InteropLimits.maxPayloadBytes + 1),
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport();
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      expect(await run.exitCode, kInteropNotRunExitCode);
      expect(run.diagnostics.single, contains('KiB'));
      expect(transport.lastRequest, isNull);
    });

    test('an entry outside the project is refused locally', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      final outside = await _project(<String, String>{
        'Other.java': 'class Other {}',
      });
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final transport = _FakeTransport();
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(outside.path, 'Other.java'),
      );
      expect(await run.exitCode, kInteropNotRunExitCode);
      expect(run.diagnostics.single, contains('入口文件'));
      expect(transport.lastRequest, isNull);
    });

    test('a receiver error surfaces its code and maps the exit code', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[
          _event(1, InteropEventKind.stderr, text: 'Main.java:1: error'),
          _event(
            2,
            InteropEventKind.error,
            text: '编译失败',
            code: InteropErrorCode.compileFailed,
          ),
        ],
      );
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      expect(await run.exitCode, kInteropNotRunExitCode);
      final err = (await run.stderr.toList()).join('\n');
      expect(err, contains('compile_failed'));
      expect(err, contains('编译失败'));
    });

    test('a timeout maps to exit 124', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[
          _event(
            1,
            InteropEventKind.error,
            text: '运行超时',
            code: InteropErrorCode.timeout,
          ),
        ],
      );
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      expect(await run.exitCode, 124);
    });

    test('cancel asks the receiver and finishes with 130', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[
          _event(1, InteropEventKind.accepted, text: '已接收'),
        ],
      );
      // A transport that cannot confirm a stop keeps the legacy request path.
      expect(transport.stopOutcome, isNull);
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      await run.cancel?.call();
      expect(transport.cancelled, isTrue);
      expect(await run.exitCode, 130);
    });

    test('a confirming transport reports its own stop, not 130', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[
          _event(1, InteropEventKind.accepted, text: '已接收'),
        ],
        stopOutcome: const InteropStop(
          exitCode: kInteropNotRunExitCode,
          message: '未收到后台运行的停止确认。',
          confirmed: false,
        ),
      );
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      final err = run.stderr.toList();
      await run.cancel?.call();
      // An unacknowledged stop must not be promoted to a clean cancellation.
      expect(await run.exitCode, kInteropNotRunExitCode);
      expect((await err).join(), contains('停止确认'));
    });

    test('an unsupported platform refuses without a transport call', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(supported: false);
      final run = await InteropRunner(transport: transport).run(
        projectRoot: root.path,
        language: 'java',
        entryFile: p.join(root.path, 'src', 'Main.java'),
      );
      expect(await run.exitCode, kInteropNotRunExitCode);
      expect(transport.lastRequest, isNull);
    });

    test('probe reports the missing receiver without throwing', () async {
      final transport = _FakeTransport();
      final probe = await InteropRunner(transport: transport).probe('java');
      expect(probe.available, isFalse);
      expect(probe.diagnostic, '未安装');
    });
  });

  group('agent command routing', () {
    test('a bare javac is routed as a compile', () async {
      final root = await _project(<String, String>{
        'src/Main.java': 'class Main {}',
      });
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[_event(1, InteropEventKind.done, exitCode: 0)],
      );
      final run = await InteropRunner(transport: transport).tryRunCommand(
        projectRoot: root.path,
        language: 'java',
        command: 'javac',
      );
      expect(run, isNotNull);
      expect(transport.lastRequest?.action, InteropAction.compile);
      expect(await run!.exitCode, 0);
    });

    test('a python file run is routed with its entry', () async {
      final root = await _project(<String, String>{'main.py': 'print(1)'});
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport(
        events: <InteropEvent>[
          _event(1, InteropEventKind.stdout, text: '1'),
          _event(2, InteropEventKind.done, exitCode: 0),
        ],
      );
      final run = await InteropRunner(transport: transport).tryRunCommand(
        projectRoot: root.path,
        language: 'python',
        command: 'python main.py',
      );
      expect(run, isNotNull);
      expect(transport.lastRequest?.action, InteropAction.run);
      expect(transport.lastRequest?.entry, 'main.py');
    });

    test('a shell pipeline is not routed and keeps the caller path', () async {
      final root = await _project(<String, String>{'main.py': 'print(1)'});
      addTearDown(() => root.delete(recursive: true));
      final transport = _FakeTransport();
      final run = await InteropRunner(transport: transport).tryRunCommand(
        projectRoot: root.path,
        language: 'python',
        command: 'python main.py && rm -rf /',
      );
      expect(run, isNull);
      expect(transport.lastRequest, isNull);
    });
  });
}
