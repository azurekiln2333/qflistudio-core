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
          shadowColor: WidgetStatePropertyAll(scheme.shadow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(2),
          side: const WidgetStatePropertyAll(BorderSide.none),
          // The outer 8dp is a transparent menu-only gutter. The visible
          // surface then has the MD3 8dp vertical content padding.
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          ),
          shape: const WidgetStatePropertyAll(_WorkbenchMenuBorder()),
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: scheme.shadow,
        menuPadding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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

/// Keeps menu surfaces inside every overlay edge without moving shell content.
///
/// Flutter's MenuAnchor reservedPadding constrains size, but its edge fallback
/// can still place the panel at coordinate zero or the overlay's far edge.
/// Inset only the surface/shadow path, not the anchor or its hit-test geometry.
/// MenuStyle adds the same gutter to its content padding. This also applies to
/// nested editor overlays and submenus through the scoped MenuTheme.
class _WorkbenchMenuBorder extends RoundedRectangleBorder {
  const _WorkbenchMenuBorder({
    super.side,
    super.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.gutter = 8,
  });

  final double gutter;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      super.getOuterPath(rect.deflate(gutter), textDirection: textDirection);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      super.getInnerPath(rect.deflate(gutter), textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => super.paintInterior(
    canvas,
    rect.deflate(gutter),
    paint,
    textDirection: textDirection,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      super.paint(canvas, rect.deflate(gutter), textDirection: textDirection);

  @override
  _WorkbenchMenuBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => _WorkbenchMenuBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
    gutter: gutter,
  );

  @override
  ShapeBorder scale(double t) => _WorkbenchMenuBorder(
    side: side.scale(t),
    borderRadius: borderRadius * t,
    gutter: gutter * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is _WorkbenchMenuBorder) {
      return _WorkbenchMenuBorder(
        side: BorderSide.lerp(a.side, side, t),
        borderRadius: BorderRadiusGeometry.lerp(
          a.borderRadius,
          borderRadius,
          t,
        )!,
        gutter: a.gutter + (gutter - a.gutter) * t,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is _WorkbenchMenuBorder) return b.lerpFrom(this, t);
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _WorkbenchMenuBorder && super == other && gutter == other.gutter;

  @override
  int get hashCode => Object.hash(super.hashCode, gutter);
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
