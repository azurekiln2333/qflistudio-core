/// 模型请求的并发门闸与 429 退避。
///
/// 一个会话一次只发一个模型请求，但多个会话可以同时跑。服务端每用户并发
/// 默认 2（`QFLI_AI_CONCURRENCY`），超出的请求在这里排队，界面显示「排队中」。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_client.dart';

/// 一次模型请求的调度器。
///
/// 用法：`run(sessionId, () => api.aiChat(...))`。名额在请求结束后归还，
/// 429 按 [retryDelays] 退避重试，最多重试 [retryDelays].length 次。
class AgentRequestScheduler {
  AgentRequestScheduler({
    this.maxConcurrent = 2,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
    Future<void> Function(Duration delay)? sleep,
  }) : _sleep = sleep ?? _defaultSleep;

  /// 同时进行的模型请求上限。
  final int maxConcurrent;

  /// 429 的退避间隔；长度即最多重试次数。
  final List<Duration> retryDelays;

  final Future<void> Function(Duration delay) _sleep;

  int _active = 0;
  final List<Completer<bool>> _waiters = [];
  final Set<String> _waiting = {};

  /// 排队状态变化时通知（界面据此刷新「排队中」）。
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 当前正在进行的请求数。
  int get activeCount => _active;

  /// 正在排队的会话数。
  int get waitingCount => _waiting.length;

  /// 这个会话是否在等名额。
  bool isWaiting(String sessionKey) => _waiting.contains(sessionKey);

  /// 取名额执行一次模型请求；429 自动退避重试。
  ///
  /// [isCancelled] 返回真时不再重试，直接把最后一次异常抛给调用方。
  Future<T> run<T>(
    String sessionKey,
    Future<T> Function() request, {
    bool Function()? isCancelled,
  }) async {
    final acquired = await _acquire(sessionKey);
    if (!acquired) {
      // 排队被取消（全部停止）：当作已取消，不占名额也不发请求。
      throw ApiException('请求已取消', details: const {'code': 'ABORTED'});
    }
    try {
      var attempt = 0;
      while (true) {
        try {
          return await request();
        } on ApiException catch (error) {
          final retryable = error.statusCode == 429;
          if (!retryable || attempt >= retryDelays.length) rethrow;
          if (isCancelled?.call() == true) rethrow;
          await _sleep(retryDelays[attempt]);
          attempt++;
          if (isCancelled?.call() == true) rethrow;
        }
      }
    } finally {
      _release();
    }
  }

  /// 停止排队：所有等待者拿到 false，不再占用名额。
  void cancelWaiting() {
    final waiters = List<Completer<bool>>.of(_waiters);
    _waiters.clear();
    _waiting.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(false);
    }
    changes.value++;
  }

  /// 取名额；true 表示可以请求，false 表示排队期间被取消。
  Future<bool> _acquire(String sessionKey) async {
    if (_active < maxConcurrent) {
      _active++;
      return true;
    }
    final waiter = Completer<bool>();
    _waiters.add(waiter);
    _waiting.add(sessionKey);
    changes.value++;
    final granted = await waiter.future;
    _waiting.remove(sessionKey);
    changes.value++;
    return granted;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // 名额直接转给下一个等待者，不经过 0。
      final waiter = _waiters.removeAt(0);
      if (!waiter.isCompleted) waiter.complete(true);
      return;
    }
    if (_active > 0) _active--;
    changes.value++;
  }

  static Future<void> _defaultSleep(Duration delay) =>
      Future<void>.delayed(delay);
}
