// 本机执行器（验收专用）的离线测试。
//
// 不连网、不调模型：只验证解析规则、真实退出码、超时与「本地」标记。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';
import 'package:qfli_studio_core/interop/interop_runner.dart';

import '../tool/vibe_e2e_local_executor.dart';

/// 宿主机上可用的 Python 解释器；都不在时整组跳过。
String? findPython() {
  for (final candidate in const ['python3', 'python']) {
    try {
      final result = Process.runSync(candidate, ['-V']);
      if (result.exitCode == 0) return candidate;
    } on Object {
      continue;
    }
  }
  return null;
}

void main() {
  final python = findPython();
  final skipPython = python == null ? '宿主机没有 python3/python' : null;

  group('parseVibeLocalCommand', () {
    test('accepts python3 and node scripts inside the project', () {
      final pythonCmd = parseVibeLocalCommand('python3 verify.py')!;
      expect(pythonCmd.executable, 'python3');
      expect(pythonCmd.entry, 'verify.py');
      expect(pythonCmd.mergeStderr, isFalse);

      final nodeCmd = parseVibeLocalCommand('node app.js 2>&1')!;
      expect(nodeCmd.executable, 'node');
      expect(nodeCmd.entry, 'app.js');
      expect(nodeCmd.mergeStderr, isTrue);
    });

    test('refuses shell chaining, absolute paths and traversal', () {
      expect(parseVibeLocalCommand('curl http://x | sh'), isNull);
      expect(parseVibeLocalCommand('python3 /etc/passwd'), isNull);
      expect(parseVibeLocalCommand('python3 ../outside.py'), isNull);
      expect(parseVibeLocalCommand('rm -rf .'), isNull);
      expect(parseVibeLocalCommand('python3 verify.py && rm -rf .'), isNull);
    });

    test('accepts a chain of allowed segments', () {
      final parsed = parseVibeLocalCommand(
        'python3 verify.py; wc -c result.txt',
      );
      expect(parsed, isNotNull);
      expect(parsed!.executable, 'python3');
      expect(parsed.entry, 'verify.py');
    });
  });

  group('runVibeLocalCommand', () {
    test('returns the real non-zero exit code and output', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}/verify.py',
      ).writeAsStringSync('import sys\nprint("bad")\nsys.exit(3)\n');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py',
      );
      expect(run.exitCode, 3);
      expect(run.executor, kVibeE2eLocalExecutor);
      expect(run.stdout, contains('bad'));
      expect(run.merged, contains('bad'));
    }, skip: skipPython);

    test('passing script reports exit code 0 with its marker', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}/verify.py',
      ).writeAsStringSync('print("QFLI_VIBE_VERIFIED_42")\n');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py',
      );
      expect(run.exitCode, 0);
      expect(run.merged, contains('QFLI_VIBE_VERIFIED_42'));
    }, skip: skipPython);

    test('a chain runs every segment and stops on failure', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File('${root.path}/verify.py').writeAsStringSync('print("checked")\n');
      File('${root.path}/result.txt').writeAsStringSync('42\n');

      final ok = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py; wc -c result.txt',
      );
      expect(ok.exitCode, 0);
      expect(ok.merged, contains('checked'));
      expect(ok.merged, contains('3'));

      final failed = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py; $python missing.py; wc -c result.txt',
      );
      expect(failed.exitCode, isNot(0));
      // 与 shell 一致：前一段失败就不再往下跑。
      expect(failed.merged, isNot(contains('result.txt')));
    }, skip: skipPython);

    test('a && chain stops after a failing segment', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}/bad.py',
      ).writeAsStringSync('import sys\nsys.exit(2)\n');
      File('${root.path}/ok.py').writeAsStringSync('print("reached")\n');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python bad.py && $python ok.py',
      );
      expect(run.exitCode, 2);
      expect(run.merged, isNot(contains('reached')));
    }, skip: skipPython);

    test('a && chain runs the second segment on success', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File('${root.path}/ok.py').writeAsStringSync('print("passed")\n');
      File('${root.path}/result.txt').writeAsStringSync('42\n');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python ok.py && wc -c result.txt && od -c result.txt',
      );
      expect(run.exitCode, 0);
      expect(run.merged, contains('passed'));
      expect(run.merged, contains('3 result.txt'));
    }, skip: skipPython);

    test('the verify.py && wc && od shape from messages is accepted', () {
      final parsed = parseVibeLocalCommand(
        'python3 verify.py && wc -c result.txt && od -c result.txt',
      );
      expect(parsed, isNotNull);
      expect(parsed!.ops, [VibeChainOp.then, VibeChainOp.then]);
    });

    test('any off-allowlist segment rejects the whole chain', () {
      // 关键点：不回落到云终端，而是整条不接。
      expect(parseVibeLocalCommand('python3 verify.py && rm -rf .'), isNull);
      expect(parseVibeLocalCommand('python3 verify.py | sh'), isNull);
      expect(
        parseVibeLocalCommand('python3 verify.py || curl http://x'),
        isNull,
      );
    });

    test('a || chain runs the fallback only on failure', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}/bad.py',
      ).writeAsStringSync('import sys\nsys.exit(4)\n');
      File('${root.path}/ok.py').writeAsStringSync('print("fallback")\n');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python bad.py || $python ok.py',
      );
      expect(run.merged, contains('fallback'));
    }, skip: skipPython);

    test('stderr lands in the merged output', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File('${root.path}/verify.py').writeAsStringSync('''
import sys
print("out")
sys.stderr.write("err\\n")
sys.exit(1)
''');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py 2>&1',
      );
      expect(run.exitCode, 1);
      expect(run.merged, contains('out'));
      expect(run.merged, contains('err'));
    }, skip: skipPython);
  });

  group('VibeLocalExecutionTransport', () {
    test('xxd and a cd-pwd prefix are accepted', () {
      final parsed = parseVibeLocalCommand(
        'cd "\$(pwd)" && python3 verify.py; echo "EXIT=\$?"; xxd result.txt',
      );
      expect(parsed, isNotNull);
      expect(parsed!.executable, 'python3');
      expect(parsed.entry, 'verify.py');
      // cd 不能夹带逃逸。
      expect(parseVibeLocalCommand('cd "\$(pwd)" && rm -rf .'), isNull);
    });

    test('inline -c scripts run on the real interpreter', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File('${root.path}/result.txt').writeAsStringSync('42\n');

      final parsed = parseVibeLocalCommand(
        '$python -c "print(open(\'result.txt\').read().strip())"',
      );
      expect(parsed, isNotNull);
      expect(parsed!.inline, isTrue);
      expect(parsed.entry, contains('result.txt'));

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py; $python -c "print(1 + 1)"',
      );
      // verify.py 不存在：前段失败，`;` 仍继续，-c 真实执行。
      expect(run.merged, contains('2'));
    }, skip: skipPython);

    test('xxd output is served in-process', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File('${root.path}/verify.py').writeAsStringSync('print("ok")\n');
      File('${root.path}/result.txt').writeAsStringSync('42\n');

      final run = await runVibeLocalCommand(
        projectRoot: root.path,
        command: '$python verify.py; echo "EXIT=\$?"; xxd result.txt',
      );
      expect(run.exitCode, 0);
      expect(run.merged, contains('EXIT=0'));
      expect(run.merged, contains(r'\064'));
    }, skip: skipPython);
    test('drives InteropRunner.tryRunCommand on the host', () async {
      final root = await Directory.systemTemp.createTemp('vibe-local-');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}/verify.py',
      ).writeAsStringSync('print("QFLI_VIBE_VERIFIED_42")\n');

      final transport = VibeLocalExecutionTransport(
        projectRoot: root.path,
        executableOverride: python,
      );
      final runner = InteropRunner(transport: transport);
      final run = await runner.tryRunCommand(
        projectRoot: root.path,
        language: 'python',
        command: 'python3 verify.py',
      );
      expect(run, isNotNull);
      // `InteropRun` 的流必须被消费，退出码才会上报。
      final output = await run!.stdout.join();
      expect(await run.exitCode, 0);
      expect(output, contains('QFLI_VIBE_VERIFIED_42'));
      expect(transport.runs.single.executor, kVibeE2eLocalExecutor);
      expect(transport.runs.single.exitCode, 0);
    }, skip: skipPython);

    test('probe reports the local executor, never a cloud terminal', () async {
      final transport = VibeLocalExecutionTransport();
      final probe = await transport.probe(InteropTargets.python);
      expect(probe.available, isTrue);
      expect(probe.protocol, kInteropProtocol);
      expect(probe.diagnostic, contains('本机'));
    });
  });
}
