import 'dart:io' show Platform;

/// 把快捷键写法转成当前系统的显示文字。
///
/// [keys] 统一用 `Ctrl` 书写，例如 `Ctrl+Shift+E`。macOS 上 `Ctrl` 显示为 `⌘`。
/// 按钮提示文字用它拼接，例如 `'保存 (${shortcutLabel('Ctrl+S')})'`。
String shortcutLabel(String keys, {bool? macOS}) {
  final mac = macOS ?? Platform.isMacOS;
  return mac ? keys.replaceAll('Ctrl', '⌘') : keys;
}
