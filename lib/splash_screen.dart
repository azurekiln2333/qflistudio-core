import 'dart:async';

import 'package:flutter/material.dart';

import 'services/app_backup_service.dart';
import 'services/app_restore_gate.dart';
import 'store/auth_store.dart';
import 'store/project_store.dart';
import 'store/settings_store.dart';

/// Flutter startup fallback for entry shells without a native loading layer.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;
    return Scaffold(
      backgroundColor: background,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/app_icon.png',
                width: 96,
                height: 96,
                cacheWidth: (96 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(32, 0, 32, 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const LinearProgressIndicator(minHeight: 4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 三份本地数据并行加载。单项失败不阻止进入主页。
///
/// 在任何 Store 加载之前，先应用上一次会话中暂存的全量恢复。这是全量备份
/// 唯一安全的落地时机：此时没有活动编辑器会话、没有排队写盘、没有后台运行，
/// 交换失败还能回滚到原数据。
///
/// 若成功应用了一次恢复，本次启动**不进入主页**：调用方已在主进程之前缓存了
/// 原生运行布局（例如 Java 运行树的链接），本进程继续运行会用到与磁盘不再一致的
/// 运行环境。此时改为要求用户完全关闭并重新启动应用，下次冷启动会重建原生链接。
class AppBootstrap {
  AppBootstrap._();

  static Future<void> run({
    required ProjectStore store,
    required AuthStore auth,
    required SettingsStore settings,
    required ValueNotifier<bool> ready,
    ValueChanged<double>? onProgress,
  }) async {
    var restoreApplied = false;
    var needsRecovery = false;
    try {
      final result = await AppBackupService.applyPendingRestore();
      restoreApplied = result != null;
    } catch (error, stack) {
      debugPrint('应用待处理的恢复失败：$error\n$stack');
      // 中断的事务或未完成的回滚可能留下部分数据：保守地要求恢复。
      needsRecovery = true;
    }
    if (restoreApplied || needsRecovery) {
      // 不加载任何 Store，也不进入主页；由恢复完成页面引导用户完全重启。
      if (needsRecovery) {
        AppRestoreGate.requireRecovery();
      } else {
        AppRestoreGate.requireRestart();
      }
      onProgress?.call(1);
      ready.value = true;
      return;
    }

    var completed = 0;
    Future<void> loadSafely(Future<void> Function() load) async {
      try {
        await load();
      } catch (error, stack) {
        debugPrint('本地配置加载失败：$error\n$stack');
      } finally {
        onProgress?.call(++completed / 3);
      }
    }

    await Future.wait([
      loadSafely(store.load),
      loadSafely(auth.load),
      loadSafely(settings.load),
    ]);
    ready.value = true;
  }
}
