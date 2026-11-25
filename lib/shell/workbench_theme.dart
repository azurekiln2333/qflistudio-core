import 'package:flutter/material.dart';

import '../layout/app_form_factor.dart';

/// Workbench presentation can evolve without changing the phone theme.
abstract final class WorkbenchTheme {
  static ThemeData from(ThemeData base, {required AppFormFactor formFactor}) {
    final desktop = formFactor == AppFormFactor.desktop;
    final scheme = base.colorScheme;
    return base.copyWith(
      visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: desktop
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        minWidth: 80,
        minExtendedWidth: 80,
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      hoverColor: scheme.onSurface.withValues(alpha: 0.08),
      focusColor: scheme.onSurface.withValues(alpha: 0.10),
      highlightColor: scheme.onSurface.withValues(alpha: 0.10),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          // Preserve exact IDE row height instead of applying compact density
          // a second time to the explicitly sized menu items.
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: WidgetStatePropertyAll(Size(64, desktop ? 32 : 48)),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)) {
              return scheme.onSurface.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.onSurface.withValues(alpha: 0.08);
            }
            return null;
          }),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(color: scheme.primary)
                : BorderSide.none,
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        width: 480,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        closeIconColor: scheme.onInverseSurface,
      ),
    );
  }
}

/// Outlines custom workbench controls without adding a second tab stop.
/// Native MD3 controls keep their own focus handling and state layers.
class WorkbenchFocusOutline extends StatefulWidget {
  const WorkbenchFocusOutline({super.key, required this.child});

  final Widget child;

  @override
  State<WorkbenchFocusOutline> createState() => _WorkbenchFocusOutlineState();
}

class _WorkbenchFocusOutlineState extends State<WorkbenchFocusOutline> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) => setState(() => _focused = value),
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_focused)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('workbench-focus-outline'),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
