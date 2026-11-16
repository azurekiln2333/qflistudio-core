import 'package:flutter/material.dart';

/// Toolbar height that fits [CollapsedSearchField] at the current text scale.
///
/// A toolbar hosting a [TextField] must grow with the platform text scale, or
/// the outlined field clips on large accessibility fonts. Callers use the same
/// value for their [AppBar.toolbarHeight] so the field never overflows the bar.
double collapsedSearchToolbarHeight(BuildContext context) {
  final style = Theme.of(context).textTheme.bodyLarge;
  final line =
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 16) *
      (style?.height ?? 1.5);
  return (line + 32).clamp(kToolbarHeight, double.infinity).toDouble();
}

/// The search text field shared by Home, Tutorials and any other list page.
///
/// The look is the one the tutorial filter bar already used: an outlined field
/// with a leading magnifier and a clear button once there is text. It is not a
/// collapsed control by itself; pair it with [CollapsedSearchButton] to hide it
/// behind an icon.
///
/// The widget owns no query state: [onChanged] reports every edit and the
/// caller re-filters. Pass [controller] when the caller needs to clear it (for
/// example on reset); passing [initialQuery] only seeds the internal controller.
class CollapsedSearchField extends StatefulWidget {
  const CollapsedSearchField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.clearTooltip,
    this.controller,
    this.initialQuery = '',
    this.autofocus = true,
    required this.onChanged,
    this.onSubmitted,
  });

  /// Key placed on the [TextField] so tests and focused widgets can find it
  /// regardless of how the caller wraps the search.
  final Key? fieldKey;

  /// Floating label; also the accessibility label of the field.
  final String label;

  /// Tooltip of the clear button.
  final String clearTooltip;

  /// Optional external controller. When null the field keeps its own.
  final TextEditingController? controller;

  /// Seeds the internal controller when [controller] is null.
  final String initialQuery;

  final bool autofocus;

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CollapsedSearchField> createState() => _CollapsedSearchFieldState();
}

class _CollapsedSearchFieldState extends State<CollapsedSearchField> {
  TextEditingController? _own;
  bool _empty = true;

  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    final controller = _controller;
    if (widget.controller == null && widget.initialQuery.isNotEmpty) {
      controller.text = widget.initialQuery;
    }
    _empty = controller.text.isEmpty;
    controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant CollapsedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _own)?.removeListener(_onTextChanged);
      _controller.addListener(_onTextChanged);
      _empty = _controller.text.isEmpty;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _own?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final empty = _controller.text.isEmpty;
    if (empty != _empty && mounted) setState(() => _empty = empty);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      maxLines: 1,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        isDense: true,
        // Keeps the <Icons.close> clear button the collapsed search already had.
        // The tutorial field uses <Icons.clear>, which shares the leading
        // magnifier glyph until text is typed, so looking it up by icon alone
        // could not tell the two apart. The look still matches that field.
        suffixIcon: _empty
            ? null
            : IconButton(
                tooltip: widget.clearTooltip,
                icon: const Icon(Icons.close),
                onPressed: _clear,
              ),
      ),
    );
  }
}

/// The icon that expands a collapsed search bar.
class CollapsedSearchButton extends StatelessWidget {
  const CollapsedSearchButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.search),
    onPressed: onPressed,
  );
}
