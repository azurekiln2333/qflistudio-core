import 'package:flutter/foundation.dart';

import '../services/studio_profile.dart';
import 'ohos_platform.dart';

/// 请求头 `X-Client-Platform` 的取值来源。
///
/// 服务端按该头记录登录日志的“登录平台”（整改任务书 §3-W3、§4 第 1 条）。
/// 值形如 `harmonyos-app/1.0.0`：前缀是平台，斜杠后是客户端版本号。
///
/// 前缀只接受 contracts.md C 节列出的集合。取值顺序：
/// 1. 构建注入的 `--dart-define=QFLI_CLIENT_PLATFORM=harmonyos`（各语言 App 自己声明）；
/// 2. 运行时平台映射（鸿蒙 → harmonyos，Android → android，……）。
///
/// 版本号来自 [StudioProfile.clientVersion]；未设置时用 [fallbackVersion]。
/// 头值会经过 ASCII 过滤：`http` 库对非 latin-1 头会直接抛错，
/// 而一个坏的版本号不该让整个请求失败。
abstract final class ClientPlatform {
  /// 构建注入的平台名。
  static const String _declared = String.fromEnvironment(
    'QFLI_CLIENT_PLATFORM',
  );

  static const String fallbackVersion = '1.0.0';

  /// 允许的平台前缀；不在此列的值一律回落到运行时映射。
  static const Set<String> knownPlatforms = {
    'harmonyos',
    'android',
    'ios',
    'windows',
    'macos',
    'linux',
    'web',
  };

  /// 当前请求头值，例如 `harmonyos-app/1.0.0`。
  static String get header => '$platform-app/$version';

  /// 平台前缀（不含 `-app` 后缀）。
  static String get platform {
    final declared = _declared.trim().toLowerCase();
    if (knownPlatforms.contains(declared)) return declared;
    return fromTargetPlatform(defaultTargetPlatform);
  }

  /// 客户端版本号；非法值回落到 [fallbackVersion]。
  static String get version {
    final raw = StudioProfile.current?.clientVersion.trim() ?? '';
    return sanitizeVersion(raw);
  }

  /// 运行时平台映射。
  ///
  /// 鸿蒙由 [isOhosTarget] 先行判定：枚举值本身只存在于 Flutter 鸿蒙分支，
  /// 直接写会编译不过官方 Flutter。
  static String fromTargetPlatform(TargetPlatform target) {
    if (isOhosTarget(target)) return 'harmonyos';
    switch (target) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        // fuchsia 没有独立的协议前缀，沿用 linux。
        return 'linux';
      default:
        // 鸿蒙分支的枚举多一个值；官方分支走不到这里。
        return 'linux';
    }
  }

  /// 只保留 ASCII 可见字符（0x21–0x7E），并限制长度。
  ///
  /// 缺失、空白或全部被过滤掉时回落到 [fallbackVersion]，保证头值永不为空。
  @visibleForTesting
  static String sanitizeVersion(
    String raw, {
    String fallback = fallbackVersion,
  }) {
    final filtered = StringBuffer();
    for (final unit in raw.trim().codeUnits) {
      if (unit >= 0x21 && unit <= 0x7e) filtered.writeCharCode(unit);
    }
    final value = filtered.toString();
    if (value.isEmpty) return fallback;
    return value.length <= 40 ? value : value.substring(0, 40);
  }
}
