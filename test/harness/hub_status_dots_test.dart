@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/ui/hub_status.dart';

/// 状态圆点：固定语义色、彼此可分辨、未知画空心圈。
void main() {
  test('六种状态的颜色互不相同', () {
    final colors = <Color>{};
    for (final status in HarnessSessionStatus.values) {
      final color = harnessStatusDotColor(status);
      if (color != null) colors.add(color);
    }
    expect(colors.length, 5, reason: '五个实心色加一个空心圈，实心色不能重复');
  });

  test('语义色按裁定固定', () {
    expect(
      harnessStatusDotColor(HarnessSessionStatus.blocked),
      const Color(0xFFF59E0B),
    );
    expect(
      harnessStatusDotColor(HarnessSessionStatus.working),
      const Color(0xFF22C55E),
    );
    expect(
      harnessStatusDotColor(HarnessSessionStatus.idle),
      const Color(0xFF9CA3AF),
    );
    expect(
      harnessStatusDotColor(HarnessSessionStatus.done),
      const Color(0xFF3B82F6),
    );
    expect(
      harnessStatusDotColor(HarnessSessionStatus.exited),
      const Color(0xFFEF4444),
    );
  });

  test('未知状态没有实心色', () {
    expect(harnessStatusDotColor(HarnessSessionStatus.unknown), isNull);
  });

  test('未知状态的描边用固定语义灰', () {
    // 裁定 R3：圆点颜色不跟主题变，未知状态也不能回落主题前景色，
    // 否则深浅主题下同一状态颜色不同（见下一条用例）。
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF123456));
    expect(
      harnessStatusDotBorderColor(scheme, HarnessSessionStatus.unknown),
      const Color(0xFF6B7280),
    );
  });

  test('实心状态的描边与填充同色', () {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF123456));
    for (final status in HarnessSessionStatus.values) {
      final fill = harnessStatusDotColor(status);
      if (fill == null) continue;
      expect(harnessStatusDotBorderColor(scheme, status), fill);
    }
  });

  test('颜色不随主题变', () {
    final light = ColorScheme.fromSeed(seedColor: const Color(0xFF123456));
    final dark = ColorScheme.fromSeed(
      seedColor: const Color(0xFF123456),
      brightness: Brightness.dark,
    );
    for (final status in HarnessSessionStatus.values) {
      expect(
        harnessStatusDotBorderColor(light, status),
        harnessStatusDotBorderColor(dark, status),
        reason: '${status.name} 的描边在深浅主题下相同',
      );
    }
  });
}
