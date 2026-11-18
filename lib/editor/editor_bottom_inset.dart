import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/ohos_platform.dart';

/// 编辑器页底部系统栏避让。
///
/// 编辑器页的 Scaffold 没有 `bottomNavigationBar`，body 直接铺到屏幕底边，
/// 系统导航条（手势条或三键栏）会盖住最后一行代码、终端输入行和 agent
/// 输入卡片。本组件按 `MediaQuery.viewPadding` 的底边留白。
///
/// 只对 Android 生效：HarmonyOS 由宿主窗口避让，iOS 与桌面没有底部导航条，
/// 再加一层就会多出一条空带。
///
/// 留白由本组件统一给出，同时把这段 padding 从子树的 MediaQuery 里扣掉：
/// 里面的 `SafeArea`（agent 输入卡片、终端快捷键栏）已经会读
/// `padding.bottom`，不扣就会垫两次。
class EditorBottomInset extends StatelessWidget {
  const EditorBottomInset({
    super.key,
    required this.inset,
    required this.child,
  });

  /// 需要留出的像素数，由 [insetOf] 在 Scaffold 之外算好。
  ///
  /// 不能在 Scaffold 的 body 里现算：Scaffold 会把 `viewInsets.bottom` 从
  /// body 的 MediaQuery 里去掉，键盘顶起时就分不清「键盘」和「导航条」。
  final double inset;

  final Widget child;

  /// 当前平台是否由编辑器自己让开底部导航条。
  static bool get ownsBottomBar =>
      !kIsWeb &&
      !isOhosPlatform &&
      defaultTargetPlatform == TargetPlatform.android;

  /// 需要留出的高度。
  ///
  /// 软键盘顶起时它盖住导航条，Scaffold 已按 `viewInsets` 缩过 body，
  /// 再留白等于双重留白，所以这时返回 0。
  static double insetOf(BuildContext context) {
    if (!ownsBottomBar) return 0;
    final media = MediaQuery.of(context);
    final bottom = media.viewPadding.bottom - media.viewInsets.bottom;
    return bottom > 0 ? bottom : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!ownsBottomBar) return child;
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: child,
      ),
    );
  }
}
