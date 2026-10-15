import 'package:flutter/material.dart';

/// Presentation modes of the floating restore control.
enum RestoreControlMode {
  /// Full label: `返回编辑器 · <project name>`, plus the session selector.
  expanded,

  /// Draggable small circle. Tapping it expands back to [expanded].
  collapsed,
}

/// Where the control rests inside its host, in logical pixels, measured from
/// the top-left of the layout box the host hands it.
///
/// Stored rather than recomputed from an alignment enum so a drag can survive
/// hide/show cycles and editor transitions unchanged.
@immutable
class RestoreControlPosition {
  const RestoreControlPosition(this.dx, this.dy);

  final double dx;
  final double dy;

  RestoreControlPosition clampTo(Size max) => RestoreControlPosition(
    dx.clamp(0.0, max.width < 0 ? 0.0 : max.width),
    dy.clamp(0.0, max.height < 0 ? 0.0 : max.height),
  );

  @override
  bool operator ==(Object other) =>
      other is RestoreControlPosition && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}

/// The floating control that restores a hidden retained editor session.
///
/// Deliberately **continuously mounted**: the host keeps this widget in a fixed
/// keyed slot and only flips [visible]. That is what lets the user's dragged
/// position and collapsed/expanded choice survive hide/show cycles, editor
/// switches and route transitions for the whole app lifetime — a widget built
/// fresh per restore would snap back to its default corner every time.
///
/// Layout is done by [RestoreControlLayout]: the delegate receives the child's
/// actual measured size, so clamping to the real bounds (safe area, keyboard,
/// large text, long project names) needs no post-frame measurement and no
/// second layout pass.
class RetainedEditorRestoreControl extends StatefulWidget {
  const RetainedEditorRestoreControl({
    super.key,
    required this.visible,
    required this.projectName,
    required this.hasMultipleSessions,
    required this.onRestore,
    required this.onSelect,
    this.interactive = true,
    this.reserveBottom,
    this.initialMode = RestoreControlMode.expanded,
    this.initialPosition,
  });

  /// Logical visibility. The widget stays mounted and keeps its state when
  /// false; it is wrapped in `Offstage` and fully isolated from input, focus,
  /// semantics and tickers so a hidden control can neither be tapped nor
  /// steal keyboard focus.
  final bool visible;

  /// Currently restorable project name, shown in the expanded label.
  ///
  /// Null when no session is retained (the control is mounted but hidden so its
  /// slot and state stay stable).
  final String? projectName;

  /// Whether the session selector button is offered.
  final bool hasMultipleSessions;

  /// Resumes the last active session.
  final VoidCallback onRestore;

  /// Opens the retained-session selector.
  ///
  /// Receives the control surface's own [BuildContext] so the host can anchor
  /// the popup menu to the real button instead of re-deriving an anchor from
  /// the host (the control is a sibling of the root Navigator).
  final ValueChanged<BuildContext> onSelect;

  /// Whether the control accepts input. Kept separate from [visible] so the
  /// host can freeze it during a modal without unmounting it (state survives).
  final bool interactive;

  /// Space reserved at the bottom of the host box for Home's primary-action
  /// tier (navigation bar + FAB). The control is clamped above it so the two
  /// never overlap.
  final double? reserveBottom;

  final RestoreControlMode initialMode;
  final RestoreControlPosition? initialPosition;

  @override
  State<RetainedEditorRestoreControl> createState() =>
      RetainedEditorRestoreControlState();
}

class RetainedEditorRestoreControlState
    extends State<RetainedEditorRestoreControl> {
  RestoreControlMode _mode = RestoreControlMode.expanded;

  /// Last position the user chose, or null before the control has ever been
  /// laid out visibly. Null means "use the default resting corner".
  ///
  /// Never seeded from a hidden (zero-size) layout: that would poison the
  /// first visible default with an off-screen coordinate.
  RestoreControlPosition? _position;

  /// Top-left the control is actually painted at, in host-local coordinates,
  /// as reported by the layout delegate.
  Rect _paintedBounds = Rect.zero;

  /// Reachable top-left coordinates, measured by the layout delegate.
  Rect _movementBounds = Rect.zero;

  /// Current clamped pointer position. Several pointer updates may arrive
  /// before the next frame, so it must advance independently of layout.
  Offset? _dragPosition;

  RestoreControlMode get mode => _mode;
  RestoreControlPosition? get position => _position;

  /// Diameter of the collapsed circle; re-exported for tests.
  static double get debugCircleDiameter => _CollapsedCircle.circleDiameter;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _position = widget.initialPosition;
  }

  void collapse() {
    if (_mode == RestoreControlMode.collapsed) return;
    setState(() => _mode = RestoreControlMode.collapsed);
  }

  void expand() {
    if (_mode == RestoreControlMode.expanded) return;
    setState(() => _mode = RestoreControlMode.expanded);
  }

  void _onDragStart() {
    _dragPosition = _paintedBounds.topLeft;
  }

  /// Accumulates every pointer delta while discarding movement beyond an edge.
  /// Using only the previous painted bounds would lose all but the last update
  /// when input arrives faster than frames. Clamping each update also avoids
  /// accumulating invisible overshoot that must later be dragged back.
  void _onDragUpdate(Offset delta) {
    final current = _dragPosition ?? _paintedBounds.topLeft;
    final next = Offset(
      (current.dx + delta.dx).clamp(
        _movementBounds.left,
        _movementBounds.right,
      ),
      (current.dy + delta.dy).clamp(
        _movementBounds.top,
        _movementBounds.bottom,
      ),
    );
    _dragPosition = next;
    setState(() {
      _position = RestoreControlPosition(next.dx, next.dy);
    });
  }

  void _onDragEnd() {
    _dragPosition = null;
  }

  /// Adopts the delegate's clamped position so the stored value never diverges
  /// from where the control is painted.
  ///
  /// The delegate runs during layout, so assigning here would mutate state
  /// mid-layout. When the available box shrinks under a stationary control —
  /// opening the keyboard, a resize, or a larger text scale — the stored
  /// coordinate would otherwise stay behind the keyboard while the paint moved
  /// above it. Rebuild once after the frame only when the value really changed.
  void _adoptResolved(RestoreControlPosition resolved) {
    if (_position == resolved) return;
    final first = _position == null;
    _position = resolved;
    if (first || _adopting) return;
    _adopting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adopting = false;
      if (mounted) setState(() {});
    });
  }

  bool _adopting = false;

  @override
  Widget build(BuildContext context) {
    // The control stays mounted in its fixed keyed slot at all times; only the
    // *inner* content changes. A zero-size stand-in is used when there is
    // nothing to restore, and the delegate ignores that placeholder so a
    // zero-size layout can never seed the position.
    final restorable = widget.visible && widget.projectName != null;
    final control = restorable
        ? _buildControl(context)
        : const SizedBox.shrink();
    return Offstage(
      offstage: !restorable,
      child: TickerMode(
        enabled: restorable && widget.interactive,
        child: ExcludeFocus(
          excluding: !restorable || !widget.interactive,
          child: ExcludeSemantics(
            excluding: !restorable,
            child: IgnorePointer(
              ignoring: !restorable || !widget.interactive,
              child: CustomSingleChildLayout(
                delegate: _RestoreControlLayout(
                  position: _position,
                  reserveBottom: widget.reserveBottom,
                  measure: restorable,
                  onLaidOut: (bounds, movementBounds) {
                    _paintedBounds = bounds;
                    _movementBounds = movementBounds;
                    if (_dragPosition != null) {
                      _dragPosition = bounds.topLeft;
                    }
                  },
                  onPositionResolved: _adoptResolved,
                ),
                child: control,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControl(BuildContext context) {
    final name = widget.projectName!;
    return switch (_mode) {
      RestoreControlMode.collapsed => _CollapsedCircle(
        key: const ValueKey('restore-control-collapsed'),
        projectName: name,
        // Tapping the circle expands the control; it does not restore. The
        // restore action requires the expanded bar, so an accidental tap on a
        // small target cannot silently resume a session.
        onTap: expand,
        onDragStart: _onDragStart,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
      ),
      RestoreControlMode.expanded => _ExpandedBar(
        key: const ValueKey('restore-control-expanded'),
        projectName: name,
        hasMultipleSessions: widget.hasMultipleSessions,
        onRestore: widget.onRestore,
        onSelect: widget.onSelect,
        onCollapse: collapse,
        onDragStart: _onDragStart,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
      ),
    };
  }
}

/// Positions and constrains the floating control inside the host box.
///
/// Uses the child's **actual** size, so the clamp accounts for the real control
/// (long project names, 2x text, narrow windows) instead of a guessed constant.
class _RestoreControlLayout extends SingleChildLayoutDelegate {
  _RestoreControlLayout({
    required this.position,
    required this.reserveBottom,
    required this.measure,
    required this.onLaidOut,
    required this.onPositionResolved,
  });

  final RestoreControlPosition? position;
  final double? reserveBottom;

  /// False while the control shows its placeholder (no session / hidden). The
  /// placeholder's zero size must never define the default position.
  final bool measure;

  final void Function(Rect bounds, Rect movementBounds) onLaidOut;
  final ValueChanged<RestoreControlPosition> onPositionResolved;

  /// Gap kept from the edges so the control never touches a safe-area border.
  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Hand the child the box the control may actually occupy, so a long project
    // name or 2x text wraps/shrinks to fit instead of being laid out at full
    // screen and then positioned partly off-screen.
    final maxWidth = constraints.maxWidth - _margin * 2;
    final maxHeight =
        constraints.maxHeight - _margin * 2 - (reserveBottom ?? 0.0);
    return BoxConstraints(
      maxWidth: maxWidth < 0 ? 0 : maxWidth,
      maxHeight: maxHeight < 0 ? 0 : maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // `size` is the host box; the child is already constrained to fit inside
    // the margins and the reserved bottom band, so the reachable range is the
    // leftover space at each edge.
    final maxX = size.width - childSize.width - _margin;
    final maxY =
        size.height - childSize.height - _margin - (reserveBottom ?? 0.0);

    final upperX = maxX < _margin ? _margin : maxX;
    final upperY = maxY < _margin ? _margin : maxY;

    if (!measure) {
      // Placeholder: report nothing, so a zero-size layout cannot seed the
      // stored position before the control is first shown for real.
      return Offset(_margin, _margin);
    }

    final chosen =
        position ??
        // Default resting place: the bottom-right corner, exactly where the
        // control used to sit before it became draggable.
        RestoreControlPosition(upperX, upperY);
    final clamped = RestoreControlPosition(
      chosen.dx.clamp(_margin, upperX).toDouble(),
      chosen.dy.clamp(_margin, upperY).toDouble(),
    );
    // Report the *clamped* value, not the requested one: the caller stores this
    // back as the current position, and reporting the unclamped value would
    // leave the stored coordinate permanently behind the clamp (for example
    // still below a keyboard that has already pushed the control up).
    onPositionResolved(clamped);
    final offset = Offset(clamped.dx, clamped.dy);
    onLaidOut(
      offset & childSize,
      Rect.fromLTRB(_margin, _margin, upperX, upperY),
    );
    return offset;
  }

  @override
  bool shouldRelayout(_RestoreControlLayout oldDelegate) =>
      position != oldDelegate.position ||
      reserveBottom != oldDelegate.reserveBottom ||
      measure != oldDelegate.measure;
}

/// Small draggable circle shown after an explicit collapse.
///
/// Tapping the circle **expands** the control back to its labelled bar; it does
/// not resume the session. Dragging moves the control without changing mode.
class _CollapsedCircle extends StatelessWidget {
  const _CollapsedCircle({
    super.key,
    required this.projectName,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final String projectName;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  /// Diameter of the collapsed circle, exposed for layout tests and for hosts
  /// that want to reserve its footprint.
  static const double circleDiameter = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '展开返回编辑器控制 · $projectName',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: onDragEnd,
        child: Tooltip(
          message: '展开返回编辑器控制 · $projectName',
          child: Material(
            elevation: 4,
            shape: const CircleBorder(),
            color: scheme.secondaryContainer,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: circleDiameter,
                height: circleDiameter,
                child: Icon(Icons.code, color: scheme.onSecondaryContainer),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The labelled bar: restore button, session selector and a collapse action.
class _ExpandedBar extends StatelessWidget {
  const _ExpandedBar({
    super.key,
    required this.projectName,
    required this.hasMultipleSessions,
    required this.onRestore,
    required this.onSelect,
    required this.onCollapse,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final String projectName;
  final bool hasMultipleSessions;
  final VoidCallback onRestore;
  final ValueChanged<BuildContext> onSelect;
  final VoidCallback onCollapse;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onDragStart(),
      onPanUpdate: (details) => onDragUpdate(details.delta),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        color: scheme.secondaryContainer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.code),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    '返回编辑器 · $projectName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (hasMultipleSessions)
              // Builder supplies the button's own context so the host anchors
              // the popup menu to this surface rather than the host context.
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: '切换编辑器',
                  icon: const Icon(Icons.expand_less),
                  onPressed: () => onSelect(buttonContext),
                ),
              ),
            IconButton(
              tooltip: '收起为圆形按钮',
              icon: const Icon(Icons.close_fullscreen),
              onPressed: onCollapse,
            ),
          ],
        ),
      ),
    );
  }
}
