import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../store/settings_store.dart';

/// Scales the entire navigator, including routes, menus and dialogs.
/// Phone callers disable this layer rather than inheriting a saved desktop zoom.
class UiZoom extends StatefulWidget {
  const UiZoom({
    super.key,
    required this.settings,
    required this.child,
    this.enabled = true,
    this.mouseWheelEnabled = false,
  });

  final SettingsStore settings;
  final Widget child;
  final bool enabled;
  final bool mouseWheelEnabled;

  @override
  State<UiZoom> createState() => _UiZoomState();
}

class _UiZoomState extends State<UiZoom> {
  // Reparent the same navigator when adding/removing the non-identity transform.
  final _contentKey = GlobalKey();
  Timer? _feedbackTimer;
  bool _showFeedback = false;
  late double _scale;

  bool get _macOS => defaultTargetPlatform == TargetPlatform.macOS;

  bool get _primaryModifier {
    final keyboard = HardwareKeyboard.instance;
    return !keyboard.isAltPressed &&
        (_macOS
            ? keyboard.isMetaPressed && !keyboard.isControlPressed
            : keyboard.isControlPressed && !keyboard.isMetaPressed);
  }

  @override
  void initState() {
    super.initState();
    _scale = widget.settings.uiScale;
    widget.settings.addListener(_settingsChanged);
    // Ancestor Shortcuts run too late when an editor consumes the key first.
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  @override
  void didUpdateWidget(covariant UiZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_settingsChanged);
      widget.settings.addListener(_settingsChanged);
    }
    _scale = widget.settings.uiScale;
    if (!widget.enabled) {
      _feedbackTimer?.cancel();
      _showFeedback = false;
    }
  }

  void _settingsChanged() {
    final next = widget.settings.uiScale;
    if (_scale == next) return;
    _feedbackTimer?.cancel();
    setState(() {
      _scale = next;
      _showFeedback = widget.enabled;
    });
    if (widget.enabled) {
      _feedbackTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showFeedback = false);
      });
    }
  }

  void _changeScale(double delta) {
    unawaited(widget.settings.setUiScale(widget.settings.uiScale + delta));
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (!widget.enabled || !_primaryModifier) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final zoomIn =
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd;
    final zoomOut =
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract;
    final reset =
        key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0;
    if ((!zoomIn && !zoomOut && !reset) ||
        (!zoomIn && HardwareKeyboard.instance.isShiftPressed)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (reset) {
        unawaited(widget.settings.setUiScale(1));
      } else {
        _changeScale(zoomIn ? 0.1 : -0.1);
      }
    }
    return KeyEventResult.handled;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.enabled ||
        !widget.mouseWheelEnabled ||
        !_primaryModifier ||
        event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        event.scrollDelta.dy == 0) {
      return;
    }
    // Register before descendant scrollables so zoom does not also scroll them.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _changeScale(event.scrollDelta.dy < 0 ? 0.1 : -0.1);
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    widget.settings.removeListener(_settingsChanged);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final media = MediaQuery.of(context);
    return _ZoomWheelRegion(
      onPointerSignal: _handlePointerSignal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest / _scale;
          final content = SizedBox(
            key: _contentKey,
            width: size.width,
            height: size.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (_showFeedback)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: SafeArea(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Semantics(
                              liveRegion: true,
                              child: Material(
                                borderRadius: BorderRadius.circular(8),
                                color: Theme.of(
                                  context,
                                ).colorScheme.inverseSurface,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    '界面缩放 ${(_scale * 100).round()}%',
                                    key: const ValueKey('ui-zoom-feedback'),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onInverseSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
          return MediaQuery(
            data: media.copyWith(
              size: media.size / _scale,
              padding: media.padding / _scale,
              viewPadding: media.viewPadding / _scale,
              viewInsets: media.viewInsets / _scale,
              systemGestureInsets: media.systemGestureInsets / _scale,
            ),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: size.width,
              maxWidth: size.width,
              minHeight: size.height,
              maxHeight: size.height,
              child: _scale == 1
                  ? content
                  : Transform.scale(
                      key: const ValueKey('ui-zoom-transform'),
                      scale: _scale,
                      alignment: Alignment.topLeft,
                      child: content,
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// First in the hit path, but claims only modified desktop wheel signals.
/// Ordinary scrolls, taps, drags and selection keep their normal targets.
class _ZoomWheelRegion extends SingleChildRenderObjectWidget {
  const _ZoomWheelRegion({required this.onPointerSignal, required super.child});

  final PointerSignalEventListener onPointerSignal;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderZoomWheelRegion(onPointerSignal);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderZoomWheelRegion renderObject,
  ) {
    renderObject.onPointerSignal = onPointerSignal;
  }
}

class _RenderZoomWheelRegion extends RenderProxyBox {
  _RenderZoomWheelRegion(this.onPointerSignal);

  PointerSignalEventListener onPointerSignal;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);
    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerSignalEvent) onPointerSignal(event);
  }
}
