@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/device_info.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';

import '../support/fake_harness_host.dart';

/// 设备信息契约：枚举映射、空值判断与可选接口的读取。
void main() {
  group('harnessDeviceOsOf', () {
    test('认识六种系统名', () {
      expect(harnessDeviceOsOf('android'), HarnessDeviceOs.android);
      expect(harnessDeviceOsOf('ios'), HarnessDeviceOs.ios);
      expect(harnessDeviceOsOf('ohos'), HarnessDeviceOs.ohos);
      expect(harnessDeviceOsOf('macos'), HarnessDeviceOs.macos);
      expect(harnessDeviceOsOf('windows'), HarnessDeviceOs.windows);
      expect(harnessDeviceOsOf('linux'), HarnessDeviceOs.linux);
    });

    test('忽略大小写与首尾空白', () {
      expect(harnessDeviceOsOf(' MacOS '), HarnessDeviceOs.macos);
      expect(harnessDeviceOsOf('WINDOWS'), HarnessDeviceOs.windows);
    });

    test('认不出的系统名退到 unknown', () {
      expect(harnessDeviceOsOf('fuchsia'), HarnessDeviceOs.unknown);
      expect(harnessDeviceOsOf(''), HarnessDeviceOs.unknown);
    });

    test('HarmonyOS 归到 ohos', () {
      expect(harnessDeviceOsOf('harmonyos'), HarnessDeviceOs.ohos);
    });
  });

  group('HarnessDeviceInfo', () {
    test('三个字段都缺时为空', () {
      expect(const HarnessDeviceInfo().isEmpty, isTrue);
      expect(const HarnessDeviceInfo(hostName: '  ').isEmpty, isTrue);
      expect(const HarnessDeviceInfo(osVersion: '').isEmpty, isTrue);
    });

    test('任一个字段有值就不为空', () {
      expect(const HarnessDeviceInfo(hostName: 'Pixel').isEmpty, isFalse);
      expect(
        const HarnessDeviceInfo(os: HarnessDeviceOs.android).isEmpty,
        isFalse,
      );
      expect(const HarnessDeviceInfo(osVersion: '14').isEmpty, isFalse);
    });

    test('系统默认 unknown', () {
      expect(const HarnessDeviceInfo().os, HarnessDeviceOs.unknown);
    });
  });

  group('currentDeviceInfo', () {
    test('读当前平台，不抛错', () {
      final info = currentDeviceInfo();
      expect(
        info.os,
        harnessDeviceOsOf(Platform.operatingSystem),
        reason: '系统名要和平台常量一致',
      );
    });
  });

  group('harnessDeviceOf', () {
    test('没实现接口的主机返回 null', () {
      final host = FakeHarnessHost(
        id: 'remote:plain',
        label: 'Plain',
        kind: HarnessHostKind.remote,
      );
      expect(harnessDeviceOf(host), isNull);
      addTearDown(host.dispose);
    });

    test('实现接口的主机返回设备信息', () {
      final host = _DeviceHost();
      expect(
        harnessDeviceOf(host),
        const HarnessDeviceInfo(
          hostName: 'MacBook Pro',
          os: HarnessDeviceOs.macos,
          osVersion: '14.5',
        ),
      );
      addTearDown(host.dispose);
    });

    test('设备信息可以推送更新', () {
      final host = _DeviceHost();
      host.device.value = const HarnessDeviceInfo(hostName: '改过的名字');
      expect(harnessDeviceOf(host)?.hostName, '改过的名字');
      addTearDown(host.dispose);
    });
  });
}

/// 可选接口的最小实现：只多一个 device 取值器。
class _DeviceHost extends FakeHarnessHost implements HarnessDeviceHost {
  _DeviceHost()
    : super(id: 'remote:device', label: 'Device', kind: HarnessHostKind.remote);

  @override
  final ValueNotifier<HarnessDeviceInfo> device =
      ValueNotifier<HarnessDeviceInfo>(
        const HarnessDeviceInfo(
          hostName: 'MacBook Pro',
          os: HarnessDeviceOs.macos,
          osVersion: '14.5',
        ),
      );

  @override
  Future<void> dispose() async {
    device.dispose();
    await super.dispose();
  }
}
