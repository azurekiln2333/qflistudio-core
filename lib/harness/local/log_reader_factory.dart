/// 按日志格式创建读取器。
///
/// 注册表只认识 [HarnessLogFormat]，具体实现留在这里，读取器之间不互相
/// 依赖。
library;

import 'claude_code_log_reader.dart';
import 'codex_log_reader.dart';
import 'harness_provider.dart';
import 'pi_log_reader.dart';
import 'transcript_log_reader.dart';

/// 创建读取器；目录为空或格式未知时返回 null。
TranscriptLogReader? createLogReader({
  required String providerId,
  required HarnessLogFormat format,
  required String? rootPath,
}) {
  final root = rootPath?.trim();
  if (root == null || root.isEmpty) return null;
  return switch (format) {
    HarnessLogFormat.claude => ClaudeCodeLogReader(
      providerId: providerId,
      rootPath: root,
    ),
    HarnessLogFormat.codex => CodexLogReader(
      providerId: providerId,
      rootPath: root,
    ),
    HarnessLogFormat.pi => PiLogReader(providerId: providerId, rootPath: root),
  };
}
