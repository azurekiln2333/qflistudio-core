// 仅验收用的本机命令执行器：在宿主机上真实执行 `run_command`。
//
// 这条路径只在 e2e 测试里注入，生产应用永远走在线终端或 OHOS 跨应用桥。
// 每次运行都把 `executor=local` 写进标题和诊断，报告据此标明执行位置；
// 需要登录令牌的云终端在缺令牌时仍会如实失败，不会被这里伪装成成功。
//
// 支持的语法故意很窄：只有 `python`/`python3`/`node` 加一个项目内脚本，
// 外加可选的 `2>&1` 重定向。别的命令一律不接，交回上层的真实失败路径。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';
import 'package:qfli_studio_core/interop/interop_transport.dart';

/// 报告里标记执行位置的取值。
const String kVibeE2eLocalExecutor = 'local';

/// 一次本地执行的结果：退出码与尾部输出。
class VibeLocalRun {
  const VibeLocalRun({
    required this.command,
    required this.entry,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.merged,
    required this.duration,
    required this.executor,
  });

  final String command;
  final String entry;
  final int exitCode;
  final String stdout;
  final String stderr;

  /// 合并后的输出，便于直接放进终端与报告。
  final String merged;
  final Duration duration;
  final String executor;

  Map<String, Object?> toJson() => {
    'command': command,
    'entry': entry,
    'exitCode': exitCode,
    'executor': executor,
    'durationMs': duration.inMilliseconds,
  };
}

/// 解析后的本地命令。
class VibeLocalCommand {
  const VibeLocalCommand({
    required this.executable,
    required this.entry,
    required this.mergeStderr,
    required this.raw,
  });

  final String executable;

  /// 相对项目根的脚本路径。
  final String entry;
  final bool mergeStderr;
  final String raw;
}

/// 解析 `python3 verify.py 2>&1` 这类命令；不认识的语法返回 null。
///
/// 支持用 `;` / `&&` 串联的片段，但每个片段都必须在白名单里。
/// 模型很常写成 `python3 verify.py; echo ---; wc -c result.txt`，
/// 拒掉整条会让它落到云终端，从而丢掉真实退出码。
VibeLocalCommand? parseVibeLocalCommand(String command) {
  var text = command.trim();
  if (text.isEmpty) return null;
  // `cd "$(pwd)" && ...` 只是回到当前目录，先剔掉再切片段。
  for (final prefix in const <String>[
    'cd "\$(pwd)" && ',
    'cd \$(pwd) && ',
    'cd . && ',
  ]) {
    while (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
  }
  if (text.isEmpty) return null;
  final segments = text
      .split(RegExp(r'\s*(?:;|&&)\s*'))
      .where((part) => part.isNotEmpty)
      .map(_parseSegment)
      .toList();
  if (segments.isEmpty || segments.any((segment) => segment == null)) {
    return null;
  }
  final first = segments.first!;
  return VibeLocalCommand(
    executable: first.executable,
    entry: first.entry,
    mergeStderr: segments.any((segment) => segment!.mergeStderr),
    raw: text,
  );
}

/// 解析单个片段；不在白名单里返回 null。
VibeLocalCommand? _parseSegment(String segment) {
  var text = segment.trim();
  if (text.isEmpty) return null;
  var mergeStderr = false;
  for (final suffix in const <String>['2>&1', '2> &1']) {
    if (text.endsWith(suffix)) {
      mergeStderr = true;
      text = text.substring(0, text.length - suffix.length).trim();
      break;
    }
  }
  final words = text.split(RegExp(r'\s+'));
  if (words.isEmpty) return null;
  const executables = <String>{'python', 'python3', 'node'};
  if (executables.contains(words.first) && words.length == 2) {
    final entry = words[1].replaceAll('\\', '/');
    if (entry.startsWith('/') || entry.contains('..')) return null;
    return VibeLocalCommand(
      executable: words.first,
      entry: entry,
      mergeStderr: mergeStderr,
      raw: segment.trim(),
    );
  }
  // `echo ...` 只回显，`$?` 由执行器填入上一段的真实退出码。
  if (words.first == 'echo') {
    return VibeLocalCommand(
      executable: 'echo',
      entry: words.skip(1).join(' '),
      mergeStderr: mergeStderr,
      raw: segment.trim(),
    );
  }
  // `wc -c <file>` / `od -c <file>` 只读输出，构不成逃逸。
  // Windows 上没有 wc/od，执行时改在进程内读字节数，不依赖外部命令。
  if (words.first == 'wc' && words.length == 3 && words[1] == '-c') {
    final entry = words[2].replaceAll('\\', '/');
    if (entry.startsWith('/') || entry.contains('..')) return null;
    return VibeLocalCommand(
      executable: 'wc',
      entry: entry,
      mergeStderr: mergeStderr,
      raw: segment.trim(),
    );
  }
  if (words.first == 'od' && words.length == 3 && words[1] == '-c') {
    final entry = words[2].replaceAll('\\', '/');
    if (entry.startsWith('/') || entry.contains('..')) return null;
    return VibeLocalCommand(
      executable: 'od',
      entry: entry,
      mergeStderr: mergeStderr,
      raw: segment.trim(),
    );
  }
  // `xxd <file>` 与 `od -c` 同类，只读字节。
  if (words.first == 'xxd' && words.length == 2) {
    final entry = words[1].replaceAll('\\', '/');
    if (entry.startsWith('/') || entry.contains('..')) return null;
    return VibeLocalCommand(
      executable: 'xxd',
      entry: entry,
      mergeStderr: mergeStderr,
      raw: segment.trim(),
    );
  }
  return null;
}

/// 命令里写的解释器名 → 宿主机上真能跑的可执行文件。
///
/// Windows 的 `python3.exe` 常常只是应用商店占位存根，一跑就返回 9009。
/// 这里按「能真跑」的顺序回落，始终返回真实可用的路径。
Future<String> resolveVibeLocalInterpreter(String requested) async {
  final candidates = requested == 'node'
      ? const <String>['node']
      : const <String>['python', 'python3', 'py'];
  for (final candidate in candidates) {
    if (await _runsAtAll(candidate)) return candidate;
  }
  // 都不可用时原样返回，让真实失败（而不是被伪造的成功）进入报告。
  return requested;
}

Future<bool> _runsAtAll(String executable) async {
  try {
    final probe = await Process.start(executable, const ['-V']);
    final code = await probe.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        probe.kill();
        return 9009;
      },
    );
    return code == 0;
  } on Object {
    return false;
  }
}

/// 把真实进程输出按行推给 `InteropRun`。
Stream<String> _lines(Stream<List<int>> bytes) => bytes
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .map((line) => '$line\n');

/// 三个八进制位，与 `od -c` 的单字节显示一致。
String _octal(int byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}';

/// 把一条命令拆成已校验的片段序列。
List<VibeLocalCommand> _segmentsOf(String command) => command
    .trim()
    .split(RegExp(r'\s*(?:;|&&)\s*'))
    .where((part) => part.isNotEmpty)
    .map(_parseSegment)
    .whereType<VibeLocalCommand>()
    .toList();

/// 在宿主机上跑一条被支持的命令。
///
/// [executableOverride] 用来测试；默认按解析结果找 `python`/`python3`/`node`。
Future<VibeLocalRun> runVibeLocalCommand({
  required String projectRoot,
  required String command,
  Duration timeout = const Duration(seconds: 120),
  String? executableOverride,
}) async {
  final parsed = parseVibeLocalCommand(command);
  if (parsed == null) {
    throw ArgumentError.value(
      command,
      'command',
      '本地执行器只支持 python/python3/node 加一个项目内脚本',
    );
  }
  final started = DateTime.now();
  final out = StringBuffer();
  final err = StringBuffer();
  final merged = StringBuffer();
  var code = 0;
  // `$?` 只指紧邻上一条命令的退出码，单独记录。
  var previousCode = 0;
  var timedOut = false;
  for (final part in _segmentsOf(command)) {
    // echo 不调外部进程，`$?` 填上一段的真实退出码。
    if (part.executable == 'echo') {
      final text = '${part.entry.replaceAll(r'$?', '$previousCode')}\n';
      out.write(text);
      merged.write(text);
      continue;
    }
    // wc/od 在 Windows 上不存在，这里直接读文件，语义一致。
    if (part.executable == 'wc' ||
        part.executable == 'od' ||
        part.executable == 'xxd') {
      final file = File(p.join(projectRoot, part.entry));
      if (!file.existsSync()) {
        merged.write('${part.executable}: ${part.entry}: 文件不存在\n');
        code = 1;
        break;
      }
      final bytes = file.readAsBytesSync();
      final text = part.executable == 'wc'
          ? '${bytes.length} ${part.entry}\n'
          : '${bytes.map(_octal).join(' ')} ${part.entry}\n';
      out.write(text);
      merged.write(text);
      code = 0;
      previousCode = 0;
      continue;
    }
    final executable = part.executable == parsed.executable
        ? (executableOverride ??
              await resolveVibeLocalInterpreter(part.executable))
        : part.executable;
    final args = <String>[part.entry];
    final process = await Process.start(
      executable,
      args,
      workingDirectory: projectRoot,
    );
    final outDone = _lines(process.stdout).forEach((line) {
      out.write(line);
      merged.write(line);
    });
    final errDone = _lines(process.stderr).forEach((line) {
      err.write(line);
      merged.write(line);
    });
    code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        process.kill();
        return 124;
      },
    );
    await Future.wait([outDone, errDone]);
    previousCode = code;
    // 与 shell 一致：任一段失败就停，退出码取该段。
    if (code != 0) break;
  }
  if (timedOut) merged.write('执行超时（${timeout.inSeconds} 秒）\n');
  return VibeLocalRun(
    command: command,
    entry: parsed.entry,
    exitCode: code,
    stdout: out.toString(),
    stderr: err.toString(),
    merged: merged.toString(),
    duration: DateTime.now().difference(started),
    executor: kVibeE2eLocalExecutor,
  );
}

/// 走 `InteropRunner` 那条代码路径的本机执行器。
///
/// 复用 `tryRunCommand` 的语法判断与输出缓冲，只把最后一跳换成
/// [Process.start]，因此验收覆盖到控制器真实使用的分支。
class VibeLocalExecutionTransport implements InteropTransport {
  VibeLocalExecutionTransport({String? projectRoot, String? executableOverride})
    : _projectRoot = projectRoot,
      _executableOverride = executableOverride;

  final String? _projectRoot;
  final String? _executableOverride;

  /// 本次会话的每一次执行，供报告取证。
  final List<VibeLocalRun> runs = [];

  @override
  bool get isSupported => true;

  @override
  Future<InteropProbe> probe(InteropTarget target) async => InteropProbe(
    available: true,
    protocol: kInteropProtocol,
    languages: target.languages,
    diagnostic: '本机执行器（验收专用）',
  );

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    final root = _projectRoot;
    if (root == null) {
      throw const InteropException('local_root_missing', '本地执行器缺少项目根目录');
    }
    final entry = request.entry.isNotEmpty
        ? request.entry
        : (request.files.isEmpty ? '' : request.files.first.path);
    if (entry.isEmpty) {
      throw const InteropException('local_entry_missing', '本地执行器没有可执行的入口');
    }
    final command = '${_interpreterFor(target, entry)} $entry';
    final run = await runVibeLocalCommand(
      projectRoot: root,
      command: command,
      executableOverride: _executableOverride,
    );
    runs.add(run);

    final controller = StreamController<InteropEvent>();
    var seq = 0;
    controller.add(
      InteropEvent(
        sessionId: request.sessionId,
        seq: ++seq,
        kind: InteropEventKind.progress,
        text: 'executor=$kVibeE2eLocalExecutor 在宿主机执行 $command',
      ),
    );
    if (run.merged.isNotEmpty) {
      controller.add(
        InteropEvent(
          sessionId: request.sessionId,
          seq: ++seq,
          kind: InteropEventKind.stdout,
          text: run.merged,
        ),
      );
    }
    controller.add(
      InteropEvent(
        sessionId: request.sessionId,
        seq: ++seq,
        kind: InteropEventKind.done,
        exitCode: run.exitCode,
      ),
    );
    // 监听者在 `start` 返回后才接上，不能在这里 await 关闭。
    unawaited(controller.close());
    return InteropLaunch(
      request: request,
      events: controller.stream,
      cancel: () async {},
    );
  }

  /// 按语言与入口后缀选解释器；`InteropRunner` 只放行 python 与 java。
  static String _interpreterFor(InteropTarget target, String entry) {
    if (p.extension(entry).toLowerCase() == '.js') return 'node';
    if (target.languages.contains('python')) return 'python3';
    return 'python3';
  }
}
