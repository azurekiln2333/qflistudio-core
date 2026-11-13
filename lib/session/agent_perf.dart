/// 会话性能打点。
///
/// 只输出事件名与毫秒数，不打印标题、路径或消息正文：日志可能进 hilog。
/// 事件名固定为 `sessions.load`、`session.open`、`send.feedback`、
/// `persist.append`，方便真机按前缀过滤。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 打一条 `[agent-perf] <事件> <毫秒>`。
void agentPerf(String event, int elapsedMs) {
  debugPrint('[agent-perf] $event $elapsedMs');
}

/// 计一段异步耗时，结束时打点。事件名与毫秒一起输出。
///
/// 不用 `Stopwatch` 之外的依赖，调用方只负责包住要测的段。
Future<T> measureAgentPerf<T>(
  String event,
  Future<T> Function() body,
) async {
  final watch = Stopwatch()..start();
  try {
    return await body();
  } finally {
    agentPerf(event, watch.elapsedMilliseconds);
  }
}

/// 同步段计时：用于「发送后同一帧就要有反馈」这类要求。
int agentPerfMs(void Function() body) {
  final watch = Stopwatch()..start();
  body();
  return watch.elapsedMilliseconds;
}
