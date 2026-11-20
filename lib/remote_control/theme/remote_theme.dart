// Provenance: adapted from CloudTerminal `lib/theme/app_theme.dart`
// (source HEAD 49b2aac781858929a19307faeb808b83f8154410).
//
// Only the two helpers the remote screens actually need were kept: the
// monospace text style and the session status colour. The source file also
// built a whole `ThemeData` plus a seed palette, but that duplicated the host
// app's global appearance controller, so it is deliberately not carried over.
// Colours come from `Theme.of(context)` and typography from the shared
// `EditorFonts` bundle, so the remote screens follow the host theme instead of
// imposing their own.

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../editor/editor_fonts.dart';

/// Theme helpers shared by the remote-control screens.
abstract final class RemoteTheme {
  /// Extra fallbacks so Chinese output and emoji do not render as tofu.
  ///
  /// `EditorFonts.fallbacks` only carries the bundled family and the generic
  /// `monospace` alias, which is enough for the editor but not for a PTY that
  /// prints CJK paths. The host's own terminal has the same gap; this list is
  /// local to the remote module so the shared font config stays untouched.
  static const List<String> _fallbacks = <String>[
    EditorFonts.bundledFamily,
    'Cascadia Mono',
    'Consolas',
    'SF Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'Noto Sans Mono CJK SC',
    'Noto Sans Mono CJK TC',
    'Microsoft YaHei',
    'PingFang SC',
    'monospace',
  ];

  /// Monospace text style used for paths, commands and tool output.
  static TextStyle mono(
    double fontSize, {
    Color? color,
    FontWeight? fontWeight,
    double height = 1.45,
  }) {
    return TextStyle(
      fontFamily: EditorFonts.bundledFamily,
      fontFamilyFallback: _fallbacks,
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: fontWeight,
    );
  }

  /// Terminal renderer style for the bundled monospace family.
  ///
  /// The renderer measures cells from the resolved font, so it needs the same
  /// family and fallbacks the rest of the module uses.
  static TerminalStyle terminalStyle({
    double fontSize = 13,
    double height = 1.2,
  }) {
    return TerminalStyle(
      fontSize: fontSize,
      height: height,
      fontFamily: EditorFonts.bundledFamily,
      fontFamilyFallback: _fallbacks,
    );
  }

  /// Colour for a session status dot, chip or spinner.
  ///
  /// `status` is the wire name (`SessionStatus.name`), so a future server-side
  /// status degrades to `scheme.secondary` instead of throwing.
  static Color statusColor(ColorScheme scheme, String status) {
    switch (status) {
      case 'running':
        return scheme.primary;
      case 'waiting':
        return scheme.tertiary;
      case 'error':
        return scheme.error;
      case 'closed':
        return scheme.outline;
      default:
        return scheme.secondary;
    }
  }
}
