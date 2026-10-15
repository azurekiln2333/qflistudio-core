import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens shared by offline tool cards and detail pages.
///
/// Mirrors the visual language of the sibling `netrix` tool app: Material 3
/// `ColorScheme`, flat cards with a hairline outline, 12 px radii, and a
/// section heading built from a primary-coloured icon plus a title/subtitle
/// pair. Kept in one place so the grid and the details cannot drift apart.
abstract final class ToolsTheme {
  /// Horizontal page padding: tight on phones, wider on tablets.
  static double horizontalPadding(double width) =>
      width < 600 ? 16 : (width >= 1200 ? 32 : 24);

  /// Widest the content column grows before it is centred on a large screen.
  static const double contentMaxWidth = 1000;

  /// Card grid geometry. `maxCrossAxisExtent` lets Flutter pick the column
  /// count, so the same code is a single column on a phone and three or four on
  /// a tablet without a breakpoint table.
  static const double cardMaxWidth = 320;
  static const double cardHeight = 132;
  static const double cardSpacing = 12;

  static const double cardRadius = 12;
  static const double cardPadding = 16;

  /// The card surface: flat, outlined, and tinted from the scheme so it works
  /// in light and dark without hard-coded colours.
  static BoxDecoration cardDecoration(ColorScheme scheme) => BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(cardRadius),
    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
  );
}

/// A section heading: icon, title, optional subtitle and trailing action.
///
/// The same widget heads every group on the tools page, so the hierarchy is
/// identical across groups.
class ToolsSectionHeading extends StatelessWidget {
  const ToolsSectionHeading({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One tool tile: icon, name and a one-line description.
///
/// The whole tile is the tap target, and it is deliberately flat rather than
/// Material-elevated so a grid of them reads as a single surface.
class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ToolsTheme.cardRadius),
          child: Ink(
            decoration: ToolsTheme.cardDecoration(scheme),
            child: Padding(
              padding: const EdgeInsets.all(ToolsTheme.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: scheme.primary),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled result row with its own copy button.
///
/// Used by every tool page, so a value is always one tap from the clipboard.
class ResultRow extends StatelessWidget {
  const ResultRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = true,
    this.allowCopy = true,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool allowCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: monospace ? 13 : null,
                height: 1.4,
              ),
            ),
          ),
          if (allowCopy)
            IconButton(
              tooltip: '复制$label',
              visualDensity: VisualDensity.compact,
              onPressed: () => Copy.copy(context, value),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Clipboard helper shared by the tool pages.
abstract final class Copy {
  static Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制')));
  }
}

/// Scaffold shared by every offline tool detail page.
///
/// Keeps the app bar, the intro line and the responsive content column in one
/// place so each tool only supplies its own fields and results.
class ToolScaffold extends StatelessWidget {
  const ToolScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = ToolsTheme.horizontalPadding(constraints.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ToolsTheme.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...children,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Text field styled like the rest of the page.
class ToolField extends StatelessWidget {
  const ToolField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
    this.monospace = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool monospace;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
    ),
  );
}

/// Inline error line; renders nothing when there is no message.
class ToolError extends StatelessWidget {
  const ToolError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            message!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
}

/// A titled group of result rows inside an outlined surface.
class ToolResultCard extends StatelessWidget {
  const ToolResultCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ToolsTheme.cardRadius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(title!, style: theme.textTheme.titleSmall),
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}
