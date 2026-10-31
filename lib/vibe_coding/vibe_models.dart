/// AI 编程会话的只读快照模型。控制器负责创建，UI 只读。
library;

import 'vibe_plan.dart';

export 'vibe_plan.dart' show VibePlanItem, VibePlanStatus, vibePlanAllDone;

enum VibePhase { idle, running, cancelling, succeeded, failed, cancelled }

enum VibeToolStatus { running, ok, error, conflict }

const Set<String> kVibeToolNames = {
  'list_files',
  'read_file',
  'write_file',
  'edit_file',
  'run_command',
  'todo',
  'use_skill',
};

class VibeToolCall {
  const VibeToolCall({
    required this.id,
    required this.toolName,
    required this.summary,
    this.status = VibeToolStatus.running,
    this.result,
    this.commandOutput,
    this.exitCode,
    this.plan,
  });

  final String id;
  final String toolName;

  /// 已缩略的参数，可直接显示（路径或命令）。
  final String summary;
  final VibeToolStatus status;

  /// 已缩略的结果或进行中的阶段文案。
  final String? result;

  /// run_command 的真实 stdout/stderr 尾部，原始文本。
  final String? commandOutput;
  final int? exitCode;

  /// todo 调用提交的计划快照；其余工具为 null。
  final List<VibePlanItem>? plan;

  bool get isRunning => status == VibeToolStatus.running;

  VibeToolCall copyWith({
    VibeToolStatus? status,
    String? result,
    String? commandOutput,
    int? exitCode,
    List<VibePlanItem>? plan,
  }) => VibeToolCall(
    id: id,
    toolName: toolName,
    summary: summary,
    status: status ?? this.status,
    result: result ?? this.result,
    commandOutput: commandOutput ?? this.commandOutput,
    exitCode: exitCode ?? this.exitCode,
    plan: plan ?? this.plan,
  );
}

class VibeMessage {
  const VibeMessage({
    required this.isUser,
    required this.text,
    this.tool,
    this.pending = false,
  });

  final bool isUser;
  final String text;

  /// 助手发起的工具调用条目；普通文本消息为 null。
  final VibeToolCall? tool;

  /// 该条目是否仍在进行。
  final bool pending;

  VibeMessage copyWith({String? text, VibeToolCall? tool, bool? pending}) =>
      VibeMessage(
        isUser: isUser,
        text: text ?? this.text,
        tool: tool ?? this.tool,
        pending: pending ?? this.pending,
      );
}

/// 一次 send 的默认工具轮数上限；控制器按任务规模放宽到
/// [vibeRoundBudget] 的预算，这里的值只作兜底。
const int kVibeMaxRounds = 8;

/// 单条工具结果发给模型的上限；超出保留尾部。
const int kVibeMaxToolResultChars = 32 * 1024;

/// run_command 单路输出保留的尾部字符数。
const int kVibeMaxCommandTailChars = 24 * 1024;
