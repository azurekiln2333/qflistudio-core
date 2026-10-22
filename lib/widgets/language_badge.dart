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

/// Shared circular language marker for project and offline content titles.
class LanguageBadge extends StatelessWidget {
  const LanguageBadge({super.key, required this.language, this.size = 30});

  final String language;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = languageLabel(language);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
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
