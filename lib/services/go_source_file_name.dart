/// Chooses an import default without executing or rewriting Go source.
/// The Go toolchain remains responsible for validating the complete program.
abstract final class GoSourceFileName {
  static final _identifier = RegExp(
    r'^[\p{L}_][\p{L}\p{Nd}_]*$',
    unicode: true,
  );
  static final _lowercase = RegExp(r'^\p{Ll}', unicode: true);

  static String suggested(String source) {
    final tokens = _tokens(source);
    final aliases = <String>{};
    var depth = 0;
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (depth == 0 && token.text == 'import') {
        var spec = index + 1;
        final grouped = spec < tokens.length && tokens[spec].text == '(';
        if (grouped) spec++;
        while (spec < tokens.length) {
          if (tokens[spec].text == ')') break;
          if (tokens[spec].text == ';') {
            spec++;
            continue;
          }
          var alias = 'testing';
          if (!tokens[spec].stringLiteral) alias = tokens[spec++].text;
          if (spec >= tokens.length || !tokens[spec].stringLiteral) break;
          if (_importPath(tokens[spec].text) == 'testing' && alias != '_') {
            aliases.add(alias);
          }
          spec++;
          if (!grouped) break;
        }
      }
      if (token.text == '{') depth++;
      if (token.text == '}') depth--;
    }
    if (aliases.isEmpty) return 'main.go';

    depth = 0;
    for (var index = 0; index + 3 < tokens.length; index++) {
      final token = tokens[index].text;
      if (depth == 0 && token == 'func') {
        final types = _parameterTypes(tokens[index + 1].text);
        if (types.isNotEmpty && tokens[index + 2].text == '(') {
          var end = index + 3;
          while (end < tokens.length && tokens[end].text != ')') {
            end++;
          }
          if (end + 1 < tokens.length && tokens[end + 1].text == '{') {
            final parameter = [
              for (var part = index + 3; part < end; part++) tokens[part].text,
            ];
            if (parameter.isNotEmpty && parameter.last == ',') {
              parameter.removeLast();
            }
            if (parameter.length >= 2 &&
                _identifier.hasMatch(parameter.first) &&
                parameter[1] == '*') {
              parameter.removeAt(0);
            }
            if ((parameter.length == 4 &&
                    parameter[0] == '*' &&
                    aliases.contains(parameter[1]) &&
                    parameter[2] == '.' &&
                    types.contains(parameter[3])) ||
                (parameter.length == 2 &&
                    parameter[0] == '*' &&
                    aliases.contains('.') &&
                    types.contains(parameter[1]))) {
              return 'snippet_test.go';
            }
          }
        }
      }
      if (token == '{') depth++;
      if (token == '}') depth--;
    }
    return 'main.go';
  }

  static Set<String> _parameterTypes(String name) {
    if (!_identifier.hasMatch(name)) return const {};
    for (final entry in const {
      'Test': 'T',
      'Benchmark': 'B',
      'Fuzz': 'F',
    }.entries) {
      if (!name.startsWith(entry.key)) continue;
      final suffix = name.substring(entry.key.length);
      if (suffix.isNotEmpty && _lowercase.hasMatch(suffix)) return const {};
      return {entry.value, if (name == 'TestMain') 'M'};
    }
    return const {};
  }

  static String? _importPath(String literal) {
    if (literal.startsWith('`')) {
      return literal.substring(1, literal.length - 1).replaceAll('\r', '');
    }
    final value = StringBuffer();
    for (var index = 1; index < literal.length - 1; index++) {
      final unit = literal[index];
      if (unit != '\\') {
        value.write(unit);
        continue;
      }
      if (++index >= literal.length - 1) return null;
      final escape = literal[index];
      final count = switch (escape) {
        'x' => 2,
        'u' => 4,
        'U' => 8,
        _ => 0,
      };
      if (count > 0) {
        if (index + count >= literal.length - 1) return null;
        final code = int.tryParse(
          literal.substring(index + 1, index + count + 1),
          radix: 16,
        );
        if (code == null || code > 0x10ffff) return null;
        value.writeCharCode(code);
        index += count;
      } else if (RegExp(r'^[0-7]$').hasMatch(escape)) {
        if (index + 2 >= literal.length - 1) return null;
        final code = int.tryParse(
          literal.substring(index, index + 3),
          radix: 8,
        );
        if (code == null || code > 255) return null;
        value.writeCharCode(code);
        index += 2;
      } else if (escape == '\\' || escape == '"' || escape == "'") {
        value.write(escape);
      } else {
        return null;
      }
    }
    return value.toString();
  }

  static List<_GoToken> _tokens(String source) {
    final result = <_GoToken>[];
    var index = 0;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit <= 32) {
        index++;
        continue;
      }
      if (source.startsWith('//', index)) {
        final end = source.indexOf('\n', index + 2);
        index = end < 0 ? source.length : end + 1;
        continue;
      }
      if (source.startsWith('/*', index)) {
        final end = source.indexOf('*/', index + 2);
        index = end < 0 ? source.length : end + 2;
        continue;
      }
      final start = index++;
      if (unit == 34 || unit == 39 || unit == 96) {
        var closed = false;
        while (index < source.length) {
          final next = source.codeUnitAt(index++);
          if (unit != 96 && next == 92) {
            if (index < source.length) index++;
          } else if (next == unit) {
            closed = true;
            break;
          }
        }
        // Do not expose unfinished literal contents as declarations.
        if (!closed) break;
        result.add(_GoToken(source.substring(start, index), unit != 39));
      } else {
        bool word(int char) =>
            char >= 128 ||
            char == 95 ||
            (char >= 48 && char <= 57) ||
            (char >= 65 && char <= 90) ||
            (char >= 97 && char <= 122);
        if (word(unit)) {
          while (index < source.length && word(source.codeUnitAt(index))) {
            index++;
          }
        }
        result.add(_GoToken(source.substring(start, index), false));
      }
    }
    return result;
  }
}

class _GoToken {
  const _GoToken(this.text, this.stringLiteral);
  final String text;
  final bool stringLiteral;
}
