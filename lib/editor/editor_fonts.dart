import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class EditorFonts {
  static const defaultFont = 'RobotoMono';
  static const bundledFamily = 'packages/qfli_studio_core/RobotoMono';
  static const defaultSize = 13.5;
  static const minSize = 9.0;
  static const maxSize = 30.0;

  static Map<String, String> get choices => {
    defaultFont: 'Roboto Mono',
    'platformMono': '系统等宽',
    'sans': '系统无衬线',
    'serif': '系统衬线',
    if (Platform.isWindows) ...{
      'Consolas': 'Consolas',
      'Cascadia Mono': 'Cascadia Mono',
      'Courier New': 'Courier New',
    },
    if (Platform.isMacOS || Platform.isIOS) ...{
      'Menlo': 'Menlo',
      'Courier': 'Courier',
    },
    if (Platform.isLinux) 'DejaVu Sans Mono': 'DejaVu Sans Mono',
  };

  static String family(String choice) => switch (choice) {
    defaultFont || 'systemMono' => bundledFamily,
    'platformMono' =>
      Platform.isWindows
          ? 'Consolas'
          : Platform.isMacOS || Platform.isIOS
          ? 'Menlo'
          : 'monospace',
    'sans' =>
      Platform.isWindows
          ? 'Segoe UI'
          : Platform.isMacOS || Platform.isIOS
          ? 'Helvetica Neue'
          : 'sans-serif',
    'serif' =>
      Platform.isWindows
          ? 'Georgia'
          : Platform.isMacOS || Platform.isIOS
          ? 'Times New Roman'
          : 'serif',
    _ => choice,
  };

  static const fallbacks = [bundledFamily, 'monospace'];

  static bool _licenseRegistered = false;

  static void registerLicense() {
    if (_licenseRegistered) return;
    _licenseRegistered = true;
    LicenseRegistry.addLicense(() async* {
      final license = await rootBundle.loadString(
        'packages/qfli_studio_core/assets/fonts/roboto_mono/OFL.txt',
      );
      yield LicenseEntryWithLineBreaks(const ['Roboto Mono'], license);
    });
  }

  static TextStyle style({
    required String font,
    required double size,
    required double height,
    required bool bold,
    required bool italic,
  }) => TextStyle(
    fontFamily: family(font),
    fontFamilyFallback: font == 'sans' || font == 'serif' ? null : fallbacks,
    fontSize: size,
    height: height,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  );
}
