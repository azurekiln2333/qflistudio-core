/// Trellis 会话上下文：把项目状态压成一段精简文本，注入会话开头。
///
/// 桌面版可以先调用 `python ./.trellis/scripts/get_context.py` 取官方上下文，
/// 失败或超时再回退到 [TrellisProject] 的 Dart 解析。两条路径都只读文件。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/process_supervisor.dart';
import 'trellis_project.dart';

/// 注入的系统提示上下文上限（字符）。
const int kTrellisContextMaxChars = 1600;

/// 上下文里最多列多少个活跃任务。
const int kTrellisContextMaxTasks = 8;

/// 单条任务标题的字符上限。
const int kTrellisContextMaxTaskTitleChars = 40;

/// 脚本上下文的字符上限。
const int kTrellisScriptContextMaxChars = 4000;

/// 能提供 Trellis 上下文的代理上下文来源。
///
/// 控制器只在来源实现本接口时注入，测试里的假上下文不受影响。
abstract interface class VibeTrellisContextSource {
  /// 会话开头要注入的精简上下文；不是 Trellis 项目时返回空串。
  Future<String> trellisContext();
}

/// 生成精简上下文；不是 Trellis 项目时调用方拿到空串。
String buildTrellisContext(
  TrellisProject project, {
  int maxTasks = kTrellisContextMaxTasks,
  int maxChars = kTrellisContextMaxChars,
}) {
  final buffer = StringBuffer()
    ..writeln('### Trellis 项目上下文')
    ..writeln(
      '本项目使用 Trellis。改代码前先用 read_file 读 '
      '${TrellisProject.workflowPath}。',
    );
  if (project.developer.isNotEmpty) {
    buffer.writeln('开发者：${project.developer}');
  }
  final current = project.currentTask;
  if (current == null) {
    buffer.writeln('当前任务：未确定');
  } else {
    final step = current.phase.step.isEmpty ? '' : '，下一步 ${current.phase.step}';
    buffer.writeln(
      '当前任务：${current.dirName}（${current.status}，'
      '${current.phase.label}$step）',
    );
    buffer.writeln(
      '  标题：${_clip(current.title, kTrellisContextMaxTaskTitleChars * 2)}',
    );
    final docs = [
      for (final doc in current.docs) doc.exists ? doc.name : '${doc.name}（缺）',
    ];
    if (docs.isNotEmpty) buffer.writeln('  产物：${docs.join('、')}');
    buffer.writeln('  任务目录：${current.relativePath}');
  }
  final active = project.activeTasks;
  if (active.isNotEmpty) {
    final shown = active.take(maxTasks).toList();
    final more = shown.length < active.length ? '，列出前 ${shown.length} 个' : '';
    buffer.writeln('活跃任务（共 ${active.length} 个$more）：');
    for (final task in shown) {
      buffer.writeln(
        '- ${task.dirName}：'
        '${_clip(task.title, kTrellisContextMaxTaskTitleChars)}'
        '（${task.status}）',
      );
    }
  }
  if (project.specIndexes.isNotEmpty) {
    final indexes = [
      for (final index in project.specIndexes) index.relativePath,
    ];
    buffer.writeln('规范索引：${indexes.join('、')}');
  }
  buffer.writeln('只按当前改动读取对应的规范与任务文件，不要一次加载全部。');
  return clampTrellisContext(buffer.toString(), maxChars);
}

/// 按字符上限截断上下文，尽量停在整行。
String clampTrellisContext(
  String text, [
  int maxChars = kTrellisContextMaxChars,
]) {
  if (text.length <= maxChars) return text;
  const mark = '（Trellis 上下文已截断）';
  final room = maxChars - mark.length - 1;
  if (room <= 0) return mark;
  final cut = text.substring(0, room);
  final newline = cut.lastIndexOf('\n');
  final body = newline > room ~/ 2 ? cut.substring(0, newline) : cut;
  return '$body\n$mark';
}

/// 载入一次会话上下文。
///
/// 默认只做 Dart 解析，不执行任何项目自带代码。官方脚本
/// `get_context.py` 属于“打开仓库就执行仓库里的代码”，因此需要两道开关同时
/// 打开：[preferPython]（桌面版才接）与 [allowProjectScript]（用户在设置里
/// 显式允许运行项目脚本）。少一道就走 Dart 解析。
class TrellisContextLoader {
  const TrellisContextLoader({
    this.preferPython = false,
    this.allowProjectScript = false,
    this.pythonExecutable = 'python',
    this.timeout = const Duration(seconds: 8),
  });

  /// 桌面版愿意尝试脚本；单独为 true 不会执行脚本。
  final bool preferPython;

  /// 用户显式允许运行项目自带的 `.trellis/scripts/get_context.py`。
  ///
  /// 只有 [preferPython] 也为 true 时才生效。移动端与网页恒为 false。
  final bool allowProjectScript;

  final String pythonExecutable;

  /// 调用脚本的总时限；超时后杀掉进程并回退。
  final Duration timeout;

  /// 是否真的会执行项目脚本。
  bool get runsProjectScript => preferPython && allowProjectScript;

  /// 取上下文；项目不是 Trellis 时返回空串。
  Future<String> load(String projectRoot) async {
    if (!TrellisProject.hasWorkflow(projectRoot)) return '';
    if (runsProjectScript) {
      final text = await _runScript(projectRoot);
      if (text != null && text.trim().isNotEmpty) {
        return compactScriptContext(text);
      }
    }
    final project = await TrellisProject.load(projectRoot);
    if (project == null) return '';
    return buildTrellisContext(project);
  }

  /// 运行官方脚本；任何失败都返回 null，不打断会话。
  Future<String?> _runScript(String projectRoot) async {
    final script = File(
      '$projectRoot${Platform.pathSeparator}.trellis'
      '${Platform.pathSeparator}scripts'
      '${Platform.pathSeparator}get_context.py',
    );
    // 只认 `.trellis/scripts` 下的普通文件：符号链接与目录都拒绝，避免把
    // 项目里的任意可执行文件当脚本跑。
    if (FileSystemEntity.typeSync(script.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final supervisor = ProcessSupervisor();
    try {
      final process = await supervisor.start(pythonExecutable, [
        script.path,
      ], workingDirectory: projectRoot);
      final stdoutText = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final stderrDrained = process.stderr.drain<void>();
      final exit = process.exitCode;
      final completed = await Future.any<Object?>([
        stdoutText,
        Future<Object?>.delayed(timeout, () => null),
      ]);
      if (completed is! String) {
        await process.cancel();
        return null;
      }
      final code = await exit;
      await stderrDrained;
      if (code != 0) return null;
      return completed;
    } on Object {
      return null;
    } finally {
      await supervisor.dispose();
    }
  }
}

/// 压缩脚本输出：去掉横幅、截短改动清单、限制总长度。
String compactScriptContext(
  String text, {
  int maxChars = kTrellisScriptContextMaxChars,
}) {
  final out = <String>[];
  var inChanges = false;
  var changeLines = 0;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.startsWith('=====')) continue;
    if (trimmed == 'SESSION CONTEXT') continue;
    if (trimmed == 'Changes:') {
      inChanges = true;
      changeLines = 0;
      out.add(line);
      continue;
    }
    if (inChanges) {
      if (trimmed.isEmpty) {
        inChanges = false;
        out.add(line);
        continue;
      }
      changeLines++;
      if (changeLines <= 5) {
        out.add(line);
      } else if (changeLines == 6) {
        out.add('…（其余改动未列出）');
      }
      continue;
    }
    out.add(line);
  }
  return clampTrellisContext(out.join('\n').trim(), maxChars);
}

String _clip(String value, int maxChars) {
  final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= maxChars ? flat : '${flat.substring(0, maxChars)}…';
}
