import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/project.dart';
import '../session/agent_session.dart';
import 'share_inbox.dart';
import 'share_intake.dart';
import 'share_intake_sheet.dart';

/// 把一批文件放进项目。[subdirectory] 为空表示项目根。
typedef ShareIntakeCopy =
    Future<ShareIntakeResult> Function(
      ShareInboxBatch batch,
      Project project,
      String subdirectory,
    );

/// 把一批文件附到会话。[sessionId] 为空表示新建会话。
typedef ShareIntakeAttach =
    Future<void> Function(
      ShareInboxBatch batch,
      Project project,
      String? sessionId,
    );

/// 收件箱到达时弹选择面板。
///
/// 只做三件事：排队、等首帧就绪、把用户选择交给回调。
class ShareIntakeHost {
  ShareIntakeHost({
    required this.inbox,
    required this.navigatorKey,
    required this.projects,
    required this.sessionsOf,
    required this.ready,
    required this.onCopy,
    required this.onAttach,
    this.onError,
  });

  final ShareInbox inbox;
  final GlobalKey<NavigatorState> navigatorKey;
  final List<Project> Function() projects;
  final List<AgentSessionMeta> Function(String projectId) sessionsOf;

  /// 首页就绪信号。为假时只排队，不弹面板。
  final ValueListenable<bool> ready;

  final ShareIntakeCopy onCopy;
  final ShareIntakeAttach onAttach;

  /// 复制或打开编辑器失败时的提示。
  final void Function(String message)? onError;

  final List<ShareInboxBatch> _queue = [];
  StreamSubscription<ShareInboxBatch>? _subscription;
  bool _showing = false;
  bool _started = false;
  bool _disposed = false;
  bool _retryScheduled = false;
  int _retries = 0;

  /// 导航器迟迟不出现时最多重试这么多帧，避免空转掉帧。
  static const int _maxRetries = 30;

  /// 订阅收件箱，取回冷启动批次，并清理超期批次。
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subscription = inbox.incoming.listen(_enqueue);
    ready.addListener(_drain);
    await inbox.start();
    unawaited(inbox.sweep());
    _drain();
  }

  void _enqueue(ShareInboxBatch batch) {
    if (_disposed || batch.isEmpty) return;
    _queue.add(batch);
    _drain();
  }

  void _drain() {
    if (_disposed || _showing) return;
    if (!ready.value) return;
    if (_queue.isEmpty) return;
    final context = navigatorKey.currentContext;
    if (context == null) {
      // 冷启动时批次可能早于导航器就绪：下一帧再试，不让批次卡死。
      _scheduleRetry();
      return;
    }
    _showing = true;
    unawaited(_present(context, _queue.removeAt(0)));
  }

  void _scheduleRetry() {
    if (_retryScheduled || _disposed) return;
    if (_retries >= _maxRetries) return;
    _retries++;
    _retryScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      _drain();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  Future<void> _present(BuildContext context, ShareInboxBatch batch) async {
    try {
      final choice = await showShareIntakeSheet(
        context,
        batch: batch,
        projects: projects(),
        sessionsOf: sessionsOf,
      );
      if (choice == null) return;
      // 面板已经出现，下一批重新计次数。
      _retries = 0;
      switch (choice) {
        case ShareIntakeIntoProject(:final project, :final subdirectory):
          final result = await onCopy(batch, project, subdirectory);
          if (result.isEmpty) {
            // 一个都没放进去：批次留在收件箱，用户还能在 7 天内再处理。
            _report('没有文件放进项目');
            return;
          }
          // 有文件被跳过的批次不删：删了用户就再也拿不到那几个文件。
          if (result.skipped.isNotEmpty) {
            _report('${result.skipped.length} 个文件没放进项目，已留在收件箱');
            return;
          }
          await inbox.discard(batch.id);
        case ShareIntakeIntoSession(:final project, :final sessionId):
          await onAttach(batch, project, sessionId);
          await inbox.discard(batch.id);
      }
    } on Object catch (error) {
      _report('处理分享文件失败：$error');
    } finally {
      _showing = false;
      // 每处理完一批清一次超期与超额批次（设计 6）。
      unawaited(inbox.sweep());
      _drain();
    }
  }

  void _report(String? message) {
    if (message == null) return;
    onError?.call(message);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ready.removeListener(_drain);
    unawaited(_subscription?.cancel());
    _subscription = null;
    _queue.clear();
  }
}
