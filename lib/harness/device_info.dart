// 设备信息：当前设备的名字、系统与系统版本。
//
// 只读平台常量，不碰网络，也不起额外进程。平台通道版本留作后续：通道名
// `qflistudio/platform`，方法 `deviceInfo`，返回 `{hostName, os, osVersion}`，
// 字段名与本文件的线上字段一致（见 design.md §2.2）。

import 'dart:io';

import 'harness_host.dart';

/// 平台系统名到枚举。认不出的返回 [HarnessDeviceOs.unknown]。
///
/// [platformSystem] 取 [Platform.operatingSystem] 的写法：`android`、`ios`、
/// `ohos`、`macos`、`windows`、`linux`。
HarnessDeviceOs harnessDeviceOsOf(String platformSystem) {
  switch (platformSystem.trim().toLowerCase()) {
    case 'android':
      return HarnessDeviceOs.android;
    case 'ios':
      return HarnessDeviceOs.ios;
    case 'ohos':
    case 'harmonyos':
      return HarnessDeviceOs.ohos;
    case 'macos':
      return HarnessDeviceOs.macos;
    case 'windows':
      return HarnessDeviceOs.windows;
    case 'linux':
      return HarnessDeviceOs.linux;
    default:
      return HarnessDeviceOs.unknown;
  }
}

/// 当前设备的信息。
///
/// 读取失败时返回空对象，不让详情页因为取不到名字就报错。
HarnessDeviceInfo currentDeviceInfo() {
  try {
    return HarnessDeviceInfo(
      hostName: Platform.localHostname,
      os: harnessDeviceOsOf(Platform.operatingSystem),
      osVersion: Platform.operatingSystemVersion,
    );
  } on Object {
    return const HarnessDeviceInfo();
  }
}
