// 设备类别：手机、平板、桌面。
//
// 类别只看硬件形态，不看窗口宽度，也不看是否接了鼠标。手机接了鼠标还是手机，
// 平板分屏变窄还是平板。窗口宽度只决定侧栏常驻还是抽屉，见 breakpoints.dart。
//
// 桌面系统由操作系统名直接判定。手机类系统走原生通道
// `qflistudio/form_factor` 的 `getFormFactor`，原生读硬件标识：
// iOS 读 `UIDevice.current.userInterfaceIdiom`，安卓读完整显示区域的逻辑短边，
// 鸿蒙读 `deviceInfo.deviceType`。原生不可用时退回显示面积判定。

import 'dart:async' show TimeoutException;

import 'package:flutter/services.dart';

/// 工作台的设备类别。
enum AppFormFactor {
  /// 手机：保留原有界面。
  phone,

  /// 平板：使用大屏工作台。
  tablet,

  /// 桌面：使用大屏工作台。
  desktop,
}

/// 原生设备类别通道。
const MethodChannel appFormFactorChannel = MethodChannel(
  'qflistudio/form_factor',
);

/// 平板的最小逻辑短边。
///
/// 用完整显示区域而不是窗口：分屏与外接显示器都不该改变类别。
const double _tabletShortestSide = 600;

/// 直接判为桌面的系统名。
const Set<String> _desktopSystems = {'windows', 'macos', 'linux'};

/// 需要问原生的系统名。
const Set<String> _mobileSystems = {'android', 'ios', 'ohos', 'harmonyos'};

/// 等原生回值的上限。
///
/// 原生卡住不该拖住启动，到点就用显示面积回退。
const Duration _nativeProbeTimeout = Duration(milliseconds: 400);

/// 解析当前设备类别。
///
/// [operatingSystem] 取 `Platform.operatingSystem` 的写法。
/// [displaySize] 是 `FlutterView.display` 的完整尺寸除以 DPR，不是窗口尺寸。
/// [channel] 供测试注入，默认用 [appFormFactorChannel]。
///
/// 桌面系统立刻返回 [AppFormFactor.desktop]。手机类系统先问原生。原生缺席、
/// 抛错、超时或给出无法识别（含类型不对）的值时，用完整显示区域的逻辑短边
/// 判定：短边不小于 600 视为平板，否则视为手机。
/// 显示尺寸无效或为零时按手机处理。
Future<AppFormFactor> resolveAppFormFactor({
  required String operatingSystem,
  required Size displaySize,
  MethodChannel? channel,
}) async {
  final system = operatingSystem.trim().toLowerCase();
  if (_desktopSystems.contains(system)) return AppFormFactor.desktop;

  final fallback = _formFactorFromDisplay(displaySize);
  if (!_mobileSystems.contains(system)) return fallback;

  final probe = channel ?? appFormFactorChannel;
  try {
    // 按 Object 取，再自己判类型：原生回了布尔、数字或表时不抛类型转换错误。
    final reported = await probe
        .invokeMethod<Object?>('getFormFactor')
        .timeout(_nativeProbeTimeout);
    final native = reported is String ? _formFactorFromNative(reported) : null;
    if (native != null) return native;
  } on MissingPluginException {
    // 原生没装这个通道，退回显示面积。
  } on PlatformException {
    // 原生读不到硬件标识，退回显示面积。
  } on TimeoutException {
    // 原生迟迟不回，退回显示面积，不让启动等下去。
  }
  return fallback;
}

/// 把原生回值映射成类别。
///
/// 只认 `phone` 与 `tablet`。其它写法一律返回 null，由调用方走回退，
/// 避免原生回了个未知值就把界面切成大屏。
AppFormFactor? _formFactorFromNative(String? reported) {
  switch (reported?.trim().toLowerCase()) {
    case 'phone':
      return AppFormFactor.phone;
    case 'tablet':
      return AppFormFactor.tablet;
    default:
      return null;
  }
}

/// 按完整显示区域的逻辑短边判定类别。
AppFormFactor _formFactorFromDisplay(Size displaySize) {
  final width = displaySize.width;
  final height = displaySize.height;
  if (!width.isFinite || !height.isFinite) return AppFormFactor.phone;
  if (width <= 0 || height <= 0) return AppFormFactor.phone;
  final shortest = width < height ? width : height;
  return shortest >= _tabletShortestSide
      ? AppFormFactor.tablet
      : AppFormFactor.phone;
}
