import 'dart:async' show Completer;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/layout/app_form_factor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Builds a channel whose native side answers [reply], or throws [error].
  MethodChannel stubChannel({
    Object? reply,
    Object? error,
    List<MethodCall>? log,
  }) {
    final channel = MethodChannel('qflistudio/form_factor_test');
    messenger.setMockMethodCallHandler(channel, (call) async {
      log?.add(call);
      if (error != null) throw error;
      return reply;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return channel;
  }

  group('桌面系统', () {
    for (final os in ['windows', 'macOS', 'Linux', ' Windows ']) {
      test('$os 直接判为桌面，不问原生', () async {
        final calls = <MethodCall>[];
        final channel = stubChannel(reply: 'phone', log: calls);
        final form = await resolveAppFormFactor(
          operatingSystem: os,
          displaySize: const Size(400, 800),
          channel: channel,
        );
        expect(form, AppFormFactor.desktop);
        expect(calls, isEmpty);
      });
    }
  });

  group('原生报告优先', () {
    test('原生报 phone：显示区域再大也是手机', () async {
      final channel = stubChannel(reply: 'phone');
      final form = await resolveAppFormFactor(
        operatingSystem: 'android',
        displaySize: const Size(2000, 3000),
        channel: channel,
      );
      expect(form, AppFormFactor.phone);
    });

    test('原生报 tablet：显示区域再窄也是平板', () async {
      final channel = stubChannel(reply: 'tablet');
      final form = await resolveAppFormFactor(
        operatingSystem: 'ios',
        displaySize: const Size(320, 700),
        channel: channel,
      );
      expect(form, AppFormFactor.tablet);
    });

    test('原生报 tablet：分屏后窗口变窄仍是平板', () async {
      final channel = stubChannel(reply: 'Tablet');
      for (final size in const [Size(700, 1000), Size(360, 1000)]) {
        final form = await resolveAppFormFactor(
          operatingSystem: 'ohos',
          displaySize: size,
          channel: channel,
        );
        expect(form, AppFormFactor.tablet, reason: '$size');
      }
    });

    test('原生回值忽略大小写与空白', () async {
      final channel = stubChannel(reply: ' PHONE ');
      final form = await resolveAppFormFactor(
        operatingSystem: 'android',
        displaySize: const Size(1200, 1600),
        channel: channel,
      );
      expect(form, AppFormFactor.phone);
    });
  });

  group('原生不可用时的回退', () {
    test('缺通道：短边 >= 600 判平板', () async {
      final channel = stubChannel(error: MissingPluginException('none'));
      final form = await resolveAppFormFactor(
        operatingSystem: 'android',
        displaySize: const Size(800, 1280),
        channel: channel,
      );
      expect(form, AppFormFactor.tablet);
    });

    test('缺通道：短边 < 600 判手机', () async {
      final channel = stubChannel(error: MissingPluginException('none'));
      final form = await resolveAppFormFactor(
        operatingSystem: 'ios',
        displaySize: const Size(390, 844),
        channel: channel,
      );
      expect(form, AppFormFactor.phone);
    });

    test('原生抛错：按显示区域回退', () async {
      final channel = stubChannel(
        error: PlatformException(code: 'UNAVAILABLE'),
      );
      final form = await resolveAppFormFactor(
        operatingSystem: 'ohos',
        displaySize: const Size(1200, 1920),
        channel: channel,
      );
      expect(form, AppFormFactor.tablet);
    });

    test('原生回未知值：不切大屏，按显示区域回退', () async {
      final channel = stubChannel(reply: '2in1');
      final form = await resolveAppFormFactor(
        operatingSystem: 'ohos',
        displaySize: const Size(360, 780),
        channel: channel,
      );
      expect(form, AppFormFactor.phone);
    });

    test('原生回空串：按显示区域回退', () async {
      final channel = stubChannel(reply: '');
      final form = await resolveAppFormFactor(
        operatingSystem: 'android',
        displaySize: const Size(800, 1280),
        channel: channel,
      );
      expect(form, AppFormFactor.tablet);
    });
  });

  group('短边阈值边界', () {
    test('599 判手机，600 判平板，异或也只看短边', () async {
      final channel = stubChannel(error: MissingPluginException('none'));
      final below = await resolveAppFormFactor(
        operatingSystem: 'android',
        displaySize: const Size(1600, 599),
        channel: channel,
      );
      final at = await resolveAppFormFactor(
        operatingSystem: 'android',
        displaySize: const Size(1600, 600),
        channel: channel,
      );
      expect(below, AppFormFactor.phone);
      expect(at, AppFormFactor.tablet);
    });
  });

  group('原生回错类型不阻断启动', () {
    final wrongReplies = <String, Object?>{
      '布尔': true,
      '整数': 1,
      '列表': ['tablet'],
      '表': {'type': 'tablet'},
      'null': null,
    };
    wrongReplies.forEach((label, reply) {
      test('$label：按显示区域回退，不抛错', () async {
        final channel = stubChannel(reply: reply);
        final form = await resolveAppFormFactor(
          operatingSystem: 'android',
          displaySize: const Size(800, 1280),
          channel: channel,
        );
        expect(form, AppFormFactor.tablet);
      });
    });

    test('原生不回：超时后按显示区域回退', () async {
      final channel = MethodChannel('qflistudio/form_factor_silent');
      messenger.setMockMethodCallHandler(channel, (call) {
        // 永远不完成的回值。
        return Completer<Object?>().future;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final form = await resolveAppFormFactor(
        operatingSystem: 'ios',
        displaySize: const Size(390, 844),
        channel: channel,
      );
      expect(form, AppFormFactor.phone);
    });
  });

  group('无效显示尺寸', () {
    for (final size in const [
      Size.zero,
      Size(0, 900),
      Size(double.infinity, 900),
      Size(double.nan, 900),
    ]) {
      test('$size 判手机', () async {
        final channel = stubChannel(error: MissingPluginException('none'));
        final form = await resolveAppFormFactor(
          operatingSystem: 'android',
          displaySize: size,
          channel: channel,
        );
        expect(form, AppFormFactor.phone);
      });
    }
  });

  test('未知系统名按手机类回退，不抛错', () async {
    final channel = stubChannel(error: MissingPluginException('none'));
    final form = await resolveAppFormFactor(
      operatingSystem: 'fuchsia',
      displaySize: const Size(390, 844),
      channel: channel,
    );
    expect(form, AppFormFactor.phone);
  });

  test('手机类系统都发 getFormFactor', () async {
    for (final os in ['android', 'ios', 'ohos', 'harmonyos']) {
      final calls = <MethodCall>[];
      final channel = stubChannel(reply: 'phone', log: calls);
      await resolveAppFormFactor(
        operatingSystem: os,
        displaySize: const Size(390, 844),
        channel: channel,
      );
      expect(calls.map((c) => c.method), ['getFormFactor'], reason: os);
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
