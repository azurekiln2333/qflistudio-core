// Explicit opt-in acceptance using the actual agent, backend relay and isolated
// executor. No upstream credential enters this process or the app source.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

void main() {
  final origin = Platform.environment['QFLI_VIBE_LIVE_ORIGIN'];
  test(
    'live model creates, edits, observes failure and reruns real project',
    () async {
      final previous = StudioProfile.current;
      StudioProfile.current = null;
      final root = await Directory.systemTemp.createTemp('qfli-vibe-live-');
      final transport = _LocalTransport(Uri.parse(origin!));
      final api = ApiClient(transport: transport);
      final changed = <String>[];
      final controller = VibeCodingController(
        api: api,
        tokenProvider: () => 'qfli-live-fixture',
        projectRoot: root.path,
        projectName: 'Live acceptance fixture',
        language: 'python',
        onFileChanged: changed.add,
      );
      try {
        await File(
          p.join(root.path, 'math_ops.py'),
        ).writeAsString('def add(a, b):\n    return a - b\n');
        await File(p.join(root.path, 'verify.py')).writeAsString(
          'from pathlib import Path\n'
          'from math_ops import add\n'
          'assert add(20, 22) == 42\n'
          'assert Path("result.txt").read_bytes() == b"42\\n"\n'
          'print("QFLI_VIBE_VERIFIED_42")\n',
        );
        final finished = Completer<void>();
        var started = false;
        void observe() {
          if (controller.phase == VibePhase.running) started = true;
          if (!started || !controller.canSend || finished.isCompleted) return;
          finished.complete();
        }

        controller.addListener(observe);
        controller.send(
          '完成以下真实调试任务。首先用 run_command 执行 python3 verify.py。'
          '必须先看到这次真实失败。然后读取 math_ops.py。'
          '使用 edit_file 修复 add 函数。创建 result.txt。'
          'content 参数使用 JSON 字符串 "42\\n"，文件必须恰好三个字节。'
          '最后再次执行 python3 verify.py。必须看到 QFLI_VIBE_VERIFIED_42。'
          '完成实际工具操作后再回复。',
        );
        await finished.future.timeout(const Duration(minutes: 5));
        controller.removeListener(observe);

        final tools = controller.messages
            .map((message) => message.tool)
            .whereType<VibeToolCall>()
            .toList();
        final runs = tools
            .where((tool) => tool.toolName == 'run_command')
            .toList();
        expect(
          controller.phase,
          VibePhase.succeeded,
          reason: controller.lastError,
        );
        expect(runs.length, greaterThanOrEqualTo(2));
        expect(
          runs.first.exitCode,
          isNot(0),
          reason: 'The original failing program must run first.',
        );
        expect(runs.first.commandOutput, contains('AssertionError'));
        expect(runs.last.exitCode, 0);
        expect(runs.last.commandOutput, contains('QFLI_VIBE_VERIFIED_42'));
        expect(changed, containsAll(['math_ops.py', 'result.txt']));
        expect(
          await File(p.join(root.path, 'result.txt')).readAsString(),
          '42\n',
        );
        expect(
          await Directory(
            p.join(root.path, '.qfli', 'vibe-backups'),
          ).list().isEmpty,
          isFalse,
          reason: 'Overwritten source must retain a real backup.',
        );
        final evidence = {
          'model': 'deepseek-v4.1-flash',
          'phase': controller.phase.name,
          'changed': changed,
          'tools': tools
              .map(
                (tool) => {
                  'name': tool.toolName,
                  'status': tool.status.name,
                  if (tool.exitCode != null) 'exitCode': tool.exitCode,
                  if (tool.commandOutput != null) 'output': tool.commandOutput,
                },
              )
              .toList(),
        };
        final output = Directory('build/vibe-live')
          ..createSync(recursive: true);
        await File(
          p.join(output.path, 'evidence.json'),
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
      } finally {
        if (controller.canCancel) await controller.cancel();
        try {
          await api.resetTerminal('qfli-live-fixture');
        } catch (_) {}
        controller.dispose();
        api.close();
        StudioProfile.current = previous;
        await root.delete(recursive: true);
      }
    },
    skip: origin == null
        ? 'Set QFLI_VIBE_LIVE_ORIGIN to the loopback fixture.'
        : false,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

class _LocalTransport extends http.BaseClient {
  _LocalTransport(this.origin)
    : _delegate = HttpOverrides.runWithHttpOverrides(
        () => IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
        _RealHttpOverrides(),
      );

  final Uri origin;
  final http.Client _delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (origin.scheme != 'http' || origin.host != '127.0.0.1') {
      throw StateError('Live fixture must use IPv4 loopback.');
    }
    final uri = origin.replace(
      path: request.url.path,
      query: request.url.query,
    );
    final local = request is http.AbortableRequest
        ? http.AbortableRequest(
            request.method,
            uri,
            abortTrigger: request.abortTrigger,
          )
        : http.Request(request.method, uri);
    local.followRedirects = false;
    local.headers.addAll(request.headers);
    local.bodyBytes = await request.finalize().toBytes();
    return _delegate.send(local);
  }

  @override
  void close() => _delegate.close();
}

class _RealHttpOverrides extends HttpOverrides {}
