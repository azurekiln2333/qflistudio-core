import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/interop/interop_background_transport.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_runner.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';
import 'package:qfli_studio_core/interop/interop_transport.dart';

import 'support/ohos_target.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Bridge bridge;
  late PathProviderPlatform originalPaths;
  const transport = MethodChannelBackgroundInteropTransport(
    startupGrace: Duration.zero,
    cancellationGrace: Duration(milliseconds: 50),
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = ohosPlatform;
    originalPaths = PathProviderPlatform.instance;
    bridge = _Bridge()..install();
    PathProviderPlatform.instance = _Paths(bridge.directory.path);
  });
  tearDown(() async {
    await bridge.close();
    PathProviderPlatform.instance = originalPaths;
    debugDefaultTargetPlatformOverride = null;
  });

  test('probe has no side effect and reports unknown', () async {
    expect(
      (await transport.probe(InteropTargets.java)).status,
      InteropProbeStatus.unknown,
    );
    expect(bridge.calls, isEmpty);
    expect(bridge.listening, isFalse);
  });

  test('an integral double on a numeric field is normalized', () {
    // The OHOS engine delivers channel numbers as `double`. An integral `1.0`
    // would stringify as `"1.0"` and be rejected by the strict reader, so it
    // is converted once, here.
    final normalized = interopWireMap(<String, Object?>{
      'protocol': kInteropProtocol,
      'sessionId': 'backgroundtest01',
      'sessionToken': '1234567890abcdef12345678',
      'seq': 1.0,
      'event': 'done',
      'text': '运行完成',
      'exitCode': 0.0,
    });
    expect(normalized['seq'], isA<int>());
    expect(normalized['exitCode'], isA<int>());
    final event = InteropEvent.fromLaunchParameters(normalized);
    expect(event.seq, 1);
    expect(event.exitCode, 0);
    expect(event.kind, InteropEventKind.done);
  });

  test('non-integral or non-finite numeric fields stay rejected', () {
    // Only a finite, exactly integral double becomes an int. Anything else is
    // handed to the strict reader unchanged so it still fails.
    for (final bad in <Object>[
      1.5,
      0.25,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      'not-a-number',
    ]) {
      final normalized = interopWireMap(<String, Object?>{
        'protocol': kInteropProtocol,
        'sessionId': 'backgroundtest01',
        'sessionToken': '1234567890abcdef12345678',
        'seq': bad,
        'event': 'done',
        'text': 'x',
        'exitCode': 0,
      });
      expect(
        normalized['seq'],
        bad,
        reason: 'an invalid seq must not be rewritten into a valid one',
      );
      expect(
        () => InteropEvent.fromLaunchParameters(normalized),
        throwsA(isA<InteropException>()),
        reason: 'seq $bad must be rejected',
      );
    }
  });

  test('a fractional exit code is not normalized into a valid one', () {
    final normalized = interopWireMap(<String, Object?>{
      'protocol': kInteropProtocol,
      'sessionId': 'backgroundtest01',
      'sessionToken': '1234567890abcdef12345678',
      'seq': 1,
      'event': 'done',
      'text': 'x',
      'exitCode': 0.5,
    });
    expect(normalized['exitCode'], 0.5);
    expect(
      () => InteropEvent.fromLaunchParameters(normalized),
      throwsA(isA<InteropException>()),
    );
  });

  test('wire normalization never rewrites payload text', () {
    // Only `seq` and `exitCode` are touched; a numeric-looking string in the
    // event text must survive byte for byte.
    final normalized = interopWireMap(<String, Object?>{
      'protocol': kInteropProtocol,
      'sessionId': 'backgroundtest01',
      'sessionToken': '1234567890abcdef12345678',
      'seq': 1.0,
      'event': 'stdout',
      'text': '1.0',
    });
    expect(normalized['text'], '1.0');
    expect(normalized['seq'], 1);
  });

  test(
    'early final event survives start and old channels stay untouched',
    () async {
      final oldZip = File(
        p.join(bridge.directory.path, 'qfli_interop', 'out', 'legacy.zip'),
      );
      oldZip.createSync(recursive: true);
      oldZip.writeAsStringSync('legacy payload');
      bridge.onStart = (parameters) async {
        expect(bridge.listening, isTrue);
        await bridge.event(parameters, text: 'real output', exitCode: 7);
      };
      final launch = await transport.start(InteropTargets.java, _request());
      bridge.launch = launch;
      await bridge.started.future;
      // Do not listen until the native start handler has already sent done.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final events = await launch.events.toList();
      expect(events.single.text, 'real output');
      expect(events.single.exitCode, 7);
      await launch.cancel();
      expect(bridge.oldCalls, isEmpty);
      expect(bridge.calls, ['start', 'dispose']);
      expect(oldZip.readAsStringSync(), 'legacy payload');
      expect(File(bridge.zipPath!).existsSync(), isFalse);
      expect(bridge.listening, isFalse);
    },
  );

  test('foreign tokens and sessions cannot finish this run', () async {
    final launch = await transport.start(InteropTargets.java, _request());
    bridge.launch = launch;
    final result = launch.events.toList();
    await bridge.started.future;
    await bridge.event({...bridge.parameters!, 'sessionToken': 'bad-token'});
    await bridge.event({...bridge.parameters!, 'sessionId': 'foreignsession'});
    await bridge.event(bridge.parameters!, text: 'accepted response');
    expect((await result).single.text, 'accepted response');
    await launch.cancel();
  });

  test('sequence gap and authenticated bad protocol fail with 127', () async {
    for (final badFrame in <Map<String, Object?>>[
      {'seq': '2'},
      {'protocol': 'qfli-interop/99'},
    ]) {
      final launch = await transport.start(InteropTargets.java, _request());
      bridge.launch = launch;
      final result = launch.events.toList();
      await _until(() => bridge.parameters != null);
      await bridge.event(bridge.parameters!, overrides: badFrame);
      expect((await result).single.exitCode, 127);
      await launch.cancel();
      bridge.parameters = null;
    }
  });

  test('cancel waits for terminal acknowledgement and is idempotent', () async {
    final project = bridge.project();
    const runner = InteropRunner(transport: transport);
    final run = await runner.run(
      projectRoot: project.path,
      language: 'java',
      entryFile: p.join(project.path, 'Main.java'),
    );
    final out = run.stdout.toList();
    final err = run.stderr.toList();
    await bridge.started.future;
    var stopped = false;
    final first = run.cancel!().then((_) => stopped = true);
    final second = run.cancel!();
    await _until(() => bridge.calls.contains('cancel'));
    expect(stopped, isFalse);
    await bridge.event(bridge.parameters!, exitCode: 130);
    await Future.wait([first, second]);
    expect(await run.exitCode, 130);
    await Future.wait([out, err]);
    expect(bridge.calls.where((call) => call == 'cancel'), hasLength(1));
  });

  test(
    'missing cancellation acknowledgement fails honestly with 127',
    () async {
      final project = bridge.project();
      final run = await const InteropRunner(transport: transport).run(
        projectRoot: project.path,
        language: 'java',
        entryFile: p.join(project.path, 'Main.java'),
      );
      final out = run.stdout.toList();
      final err = run.stderr.toList();
      await bridge.started.future;
      await run.cancel!();
      expect(await run.exitCode, 127);
      expect((await err).join(), contains('未收到后台运行的停止确认'));
      await out;
      expect(bridge.calls, ['start', 'cancel', 'dispose']);
    },
  );

  test('stop() reports confirmed=false without a receiver frame', () async {
    final launch = await transport.start(InteropTargets.java, _request());
    bridge.launch = launch;
    final result = launch.events.toList();
    await bridge.started.future;
    // No terminal frame ever arrives, so the stop cannot be confirmed even
    // though the acknowledgement budget expired cleanly.
    final stop = await launch.stop!();
    expect(stop.confirmed, isFalse);
    expect(stop.exitCode, 127);
    await result;
  });

  test('stop() reports confirmed=true after the receiver terminal frame', () async {
    final launch = await transport.start(InteropTargets.java, _request());
    bridge.launch = launch;
    final result = launch.events.toList();
    await bridge.started.future;
    await bridge.event(bridge.parameters!, exitCode: 130);
    final stop = await launch.stop!();
    expect(stop.confirmed, isTrue);
    expect(stop.exitCode, 130);
    await result;
  });

  test('startup reply timeout reports transport failure', () async {
    final startReply = Completer<void>();
    bridge.onStart = (_) => startReply.future;
    final project = bridge.project();
    final run = await const InteropRunner(transport: transport).run(
      projectRoot: project.path,
      language: 'java',
      entryFile: p.join(project.path, 'Main.java'),
      timeout: const Duration(seconds: 1),
    );
    final out = run.stdout.toList();
    final err = run.stderr.toList();
    final code = await run.exitCode.timeout(const Duration(seconds: 3));
    // A start reply lost after the caller gave up is a transport failure (127),
    // not a run timeout the receiver confirmed, so `_timedOut` must not relabel
    // it as 124.
    expect(code, 127);
    await run.cancel!();
    expect(await run.exitCode, 127);
    // `_startIssued` was set before the platform call, so the native session
    // may already be running and teardown still sends `dispose` to stop it.
    expect(bridge.calls, ['start', 'dispose']);
    final text = (await err).join();
    expect(text, contains('启动'));
    expect(text, isNot(contains('超时。')));
    await out;
    startReply.complete();
  });

  test('total deadline expires without a terminal event and exits 124', () async {
    // Native start succeeds immediately, but no terminal event ever arrives.
    // The independent total deadline (timeoutMs + startupGrace) must fire and,
    // because the receiver never acknowledged the cancel, report 124 with an
    // unconfirmed stop.
    final launch = await transport.start(InteropTargets.java, _request());
    bridge.launch = launch;
    final events = launch.events.toList();
    await bridge.started.future;
    final event = (await events).single;
    expect(event.kind, InteropEventKind.error);
    expect(event.code, InteropErrorCode.timeout);
    expect(event.exitCode, 124);
    final stop = await launch.stop!();
    expect(stop.confirmed, isFalse);
    expect(stop.exitCode, 124);
  });

  test(
    'concurrent background start is refused without another launch',
    () async {
      final launch = await transport.start(InteropTargets.java, _request());
      bridge.launch = launch;
      final result = launch.events.toList();
      await bridge.started.future;
      await expectLater(
        transport.start(InteropTargets.java, _request()),
        throwsA(isA<InteropException>()),
      );
      await bridge.event(bridge.parameters!);
      await result;
      await launch.cancel();
      expect(bridge.calls.where((call) => call == 'start'), hasLength(1));
    },
  );

  test('notification refusal is reported without legacy fallback', () async {
    bridge.onStart = (_) async => throw PlatformException(
      code: 'notification_disabled',
      message: '请先开启通知权限。',
    );
    final launch = await transport.start(InteropTargets.java, _request());
    bridge.launch = launch;
    final event = (await launch.events.toList()).single;
    expect(event.exitCode, 127);
    expect(event.text, '请先开启通知权限。');
    await launch.cancel();
    expect(bridge.oldCalls, isEmpty);
  });

  test('non-Java and non-OHOS requests cannot launch', () async {
    await expectLater(
      transport.start(InteropTargets.python, _request()),
      throwsA(isA<InteropException>()),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(
      transport.start(InteropTargets.java, _request()),
      throwsA(isA<InteropException>()),
    );
    expect(bridge.calls, isEmpty);
  });
}

InteropRequest _request() => InteropRequest(
  sessionId: 'backgroundtest01',
  sessionToken: '1234567890abcdef12345678',
  language: 'java',
  entry: 'Main.java',
  action: InteropAction.run,
  callerBundle: InteropStudio.bundleName,
  bridgeAction: InteropStudio.bridgeAction,
  files: [
    InteropPayloadFile(
      path: 'Main.java',
      content: utf8.encode('class Main {}'),
    ),
  ],
  timeoutMs: 1000,
);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _Bridge {
  final directory = Directory.systemTemp.createTempSync(
    'qfli_background_test_',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  final oldCalls = <String>[];
  final started = Completer<void>();
  bool listening = false;
  String? zipPath;
  Map<String, Object?>? parameters;
  InteropLaunch? launch;
  Future<void> Function(Map<String, Object?>)? onStart;

  void install() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('qfli_interop/background/events'),
      (call) async {
        listening = call.method == 'listen';
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      MethodChannelBackgroundInteropTransport.methods,
      (call) async {
        calls.add(call.method);
        if (call.method == 'start') {
          final args = Map<String, Object?>.from(call.arguments as Map);
          expect(args['abilityName'], 'InteropBackgroundAbility');
          parameters = Map<String, Object?>.from(args['parameters'] as Map);
          zipPath = parameters!['zipPath'] as String;
          if (!started.isCompleted) started.complete();
          await onStart?.call(parameters!);
          return <String, Object?>{'notificationEnabled': true};
        }
        return null;
      },
    );
    for (final channel in [
      'qfli_interop/bridge',
      'qfli_interop/bridge/events',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        oldCalls.add(call.method);
        return null;
      });
    }
  }

  Future<void> event(
    Map<String, Object?> parameters, {
    String text = '',
    int exitCode = 0,
    Map<String, Object?> overrides = const {},
  }) async {
    await messenger.handlePlatformMessage(
      'qfli_interop/background/events',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'protocol': kInteropProtocol,
        'sessionId': parameters['sessionId'],
        'sessionToken': parameters['sessionToken'],
        'seq': '1',
        'event': 'done',
        'text': text,
        'exitCode': '$exitCode',
        ...overrides,
      }),
      (_) {},
    );
  }

  Directory project() {
    final project = Directory(p.join(directory.path, 'project'))..createSync();
    File(p.join(project.path, 'Main.java')).writeAsStringSync('class Main {}');
    return project;
  }

  Future<void> close() async {
    await launch?.cancel();
    for (final channel in [
      'qfli_interop/background',
      'qfli_interop/background/events',
      'qfli_interop/bridge',
      'qfli_interop/bridge/events',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    directory.deleteSync(recursive: true);
  }
}
