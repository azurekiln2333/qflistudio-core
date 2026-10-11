import 'dart:async';

import 'package:flutter/material.dart';

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
class AppBootstrap {
  AppBootstrap._();

  static Future<void> run({
    required ProjectStore store,
    required AuthStore auth,
    required SettingsStore settings,
    required ValueNotifier<bool> ready,
    ValueChanged<double>? onProgress,
  }) async {
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
