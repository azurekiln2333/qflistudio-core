part of re_editor;

final kIsMacOS = defaultTargetPlatform == TargetPlatform.macOS;
final kIsAndroid = defaultTargetPlatform == TargetPlatform.android;
final kIsIOS = defaultTargetPlatform == TargetPlatform.iOS;

/// ohos 平台判定：flutter_ohos fork 的 defaultTargetPlatform 返回枚举值
/// `ohos`（标准枚举之外的值）。re_editor 的 IME 前缀退格
/// （usePrefix）与移动选择手柄都依赖 kIsAndroid/kIsIOS，ohos 上均为
/// false，导致软键盘在空行无法退格、长按无选择手柄。一并按移动端处理。
///
/// 这里比对枚举名而不是枚举值：官方 Flutter 没有 ohos，写枚举值会让
/// 官方构建编译失败。本文件刻意复制一份判定，不从上游包导入。
final bool kIsOhosMobileLike =
    !kIsWeb && defaultTargetPlatform.name == 'ohos';
