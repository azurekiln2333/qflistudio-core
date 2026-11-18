import 'package:flutter/material.dart';

/// Normalize catalog types and project display names to one chip identity.
String languageKey(String value) {
  final key = value.trim().toLowerCase();
  return key == 'c++' ? 'cpp' : key;
}

String languageLabel(String value) => switch (languageKey(value)) {
  'c' => 'C',
  'cpp' => 'C++',
  'javascript' || 'js' => 'JavaScript',
  'typescript' || 'ts' => 'TypeScript',
  'python' => 'Python',
  'java' => 'Java',
  'dart' => 'Dart',
  'lua' => 'Lua',
  'rust' => 'Rust',
  'go' => 'Go',
  'shell' => 'Shell',
  'markdown' => 'MD',
  'web' => 'Web',
  'kotlin' => 'Kotlin',
  _ => value.trim().toUpperCase(),
};

/// Shared capsule language marker for project and offline content titles.
///
/// The pill's height is [size] and its width follows the localised label, so a
/// long name such as "TypeScript" stays readable instead of being shrunk to fit
/// a fixed circle. Text is single-line and never clipped: the container grows.
class LanguageBadge extends StatelessWidget {
  const LanguageBadge({super.key, required this.language, this.size = 26});

  /// Font size of the label. Sits below the previous fixed 11 so the marker
  /// reads as a secondary annotation next to the project name.
  static const double labelFontSize = 9.5;

  final String language;

  /// Badge height. The width is intrinsic.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = languageLabel(language);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('language-badge'),
          height: size,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          constraints: const BoxConstraints(minWidth: 0),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(size / 2),
          ),
          // widthFactor 1 keeps the capsule as wide as its label while still
          // centring the text in the fixed height. A bare `alignment` would
          // stretch the box to the incoming width instead.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: labelFontSize,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
