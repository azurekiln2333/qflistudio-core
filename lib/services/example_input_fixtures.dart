import 'package:path/path.dart' as p;

/// Portable project-relative files supplied with an offline code example.
/// `stdin` is the catalog alias consumed by language runners as `input.txt`.
abstract final class ExampleInputFixtures {
  static Map<String, String> parse(Object? value, {Object? input}) {
    if (value is String) return {'stdin': value};
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    }
    return input is String && input.isNotEmpty ? {'stdin': input} : const {};
  }

  /// Validates on every write boundary, including imported user JSON.
  static Map<String, String> files(Map<String, String> fixtures) {
    final result = <String, String>{};
    final identities = <String>{};
    for (final entry in fixtures.entries) {
      final name = entry.key == 'stdin' ? 'input.txt' : entry.key;
      final parts = name.split('/');
      if (name.isEmpty ||
          name.contains('\\') ||
          p.posix.isAbsolute(name) ||
          p.windows.isAbsolute(name) ||
          parts.any(
            (part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part != part.trim() ||
                part.endsWith('.') ||
                RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(part) ||
                RegExp(
                  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                  caseSensitive: false,
                ).hasMatch(part),
          ) ||
          {'.git', '.qfli'}.contains(parts.first.toLowerCase()) ||
          !identities.add(name.toLowerCase())) {
        throw FormatException('Invalid example fixture path', entry.key);
      }
      result[name] = entry.value;
    }
    for (final name in identities) {
      if (identities.any((other) => other.startsWith('$name/'))) {
        throw FormatException('Conflicting example fixture paths', name);
      }
    }
    return result;
  }
}
