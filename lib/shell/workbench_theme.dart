import 'package:flutter/material.dart';

/// Workbench presentation can evolve without changing the phone theme.
abstract final class WorkbenchTheme {
  static ThemeData from(ThemeData base) => base.copyWith(
    // Tablet touch targets remain as generous as phone controls.
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: base.colorScheme.surface,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: base.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
  );
}
