import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../store/auth_store.dart';
import 'api_client.dart';
import 'app_paths.dart';

/// 注销结果。
enum AccountErasureOutcome {
  /// 服务端已永久删除账号；本地登录态和本地缓存已清理。
  deactivated,

  /// 用户取消。
  cancelled,

  /// 服务端拒绝或网络失败；登录态保留，可以重试。
  failed,
}

/// 一次注销的结果。[message] 仅在 [AccountErasureOutcome.failed] 时有意义。
@immutable
class AccountErasureResult {
  const AccountErasureResult(this.outcome, {this.message});

  final AccountErasureOutcome outcome;
  final String? message;

  bool get succeeded => outcome == AccountErasureOutcome.deactivated;
}

/// 永久注销账号（整改任务书 §3-W3、§4 第 7 条）。
///
/// 顺序刻意固定：
/// 1. 调 `POST /api/users/me/deactivate`，服务端负责业务表级联删除、删除
///    `data/cloud/u<id>` 与 `data/terminals/u<id>`、调用网关注销统一账号、
///    吊销所有会话。**服务端失败就不清理本地任何东西**，否则用户以为注销了，
///    账号却还在。
/// 2. 成功后清本地登录态（`auth.json`）与本账号的本地缓存目录。
///
/// 网络不可用时不允许“假注销”：失败结果会带着服务端文案返回，界面照实展示。
class AccountErasureService {
  AccountErasureService({
    ApiClient? client,
    @visibleForTesting this.storageResolverOverride,
    @visibleForTesting this.directoryDeleterOverride,
  }) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// 测试注入的本地存储目录解析；为 null 时走 [AppPaths.storageDirectory]。
  @visibleForTesting
  final Future<String?> Function()? storageResolverOverride;

  /// 测试注入的目录删除；为 null 时用 [Directory.delete]。
  @visibleForTesting
  final Future<void> Function(Directory directory)? directoryDeleterOverride;

  /// 只有这个确认词会被发送；二次确认由界面负责收集。
  static const String confirmWord = 'DEACTIVATE';

  /// 注销成功后需要清理的本地目录（相对应用私有存储目录）。
  ///
  /// 只包含本机会话产物：登录态、头像缓存、本地审计与统计、最近打开的会话。
  /// **不含** `projects/`：本地项目是用户自己的文件，不属于账号数据；
  /// 把它们一起删掉会超出“注销账号”的授权范围。
  static const List<String> localCacheDirectories = [
    'avatars',
    'local_audit.json',
    'local_stats.json',
    'workspaces.json',
  ];

  Future<AccountErasureResult> erase(AuthStore auth) async {
    final token = auth.token;
    if (token == null || token.isEmpty) {
      return const AccountErasureResult(
        AccountErasureOutcome.failed,
        message: '请先登录后再注销账号',
      );
    }
    try {
      await _client.deactivateAccount(token, confirm: confirmWord);
    } on ApiException catch (error) {
      return AccountErasureResult(
        AccountErasureOutcome.failed,
        message: error.message,
      );
    } on Object catch (error) {
      return AccountErasureResult(
        AccountErasureOutcome.failed,
        message: '注销失败：$error',
      );
    }

    // 服务端已删除账号，本机的登录态不能再留着。
    await auth.clearLocalData();
    await _clearLocalCaches();
    return const AccountErasureResult(AccountErasureOutcome.deactivated);
  }

  /// 清理本机会话产物。删除失败不影响注销结果：账号已经在服务端删掉了。
  Future<void> _clearLocalCaches() async {
    final base =
        await (storageResolverOverride?.call() ?? AppPaths.storageDirectory());
    if (base == null || base.isEmpty) return;
    for (final name in localCacheDirectories) {
      final path = p.join(base, name);
      // 只删存储目录的直接子项，避免路径拼接逃逸。
      if (!p.isWithin(base, path)) continue;
      final entity = FileSystemEntity.typeSync(path, followLinks: false);
      if (entity == FileSystemEntityType.notFound) continue;
      try {
        final target = entity == FileSystemEntityType.directory
            ? Directory(path)
            : null;
        if (target != null) {
          final deleter = directoryDeleterOverride;
          if (deleter != null) {
            await deleter(target);
          } else {
            await target.delete(recursive: true);
          }
        } else {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } on FileSystemException {
        // 单个缓存清理失败不阻塞注销；登录态已在外部清除。
      }
    }
  }
}
