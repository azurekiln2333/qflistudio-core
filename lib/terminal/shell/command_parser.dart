/// How backslashes are treated when classifying and tokenizing a line.
///
/// The choice is deliberate and host-appropriate, and classification and
/// tokenization must always use the same value so they cannot disagree:
///
/// * [backslashEscapes] — POSIX host. A backslash escapes the next character,
///   so `touch name\ with\ spaces` is one operand and `a\|b` is literal.
/// * [backslashLiteral] — Windows host, where `\` is a path separator, not an
///   escape. To stay safe, a `\` immediately followed by whitespace or an
///   operator is treated as *uninterpretable* and the whole line is routed to
///   the external shell instead of being split into several file mutations.
enum EscapePolicy { backslashEscapes, backslashLiteral }

/// Classification of a raw terminal line before any built-in dispatch happens.
///
/// The terminal must not treat shell metacharacters as literal operands: a
/// quoted path may legitimately contain `|`, and a pipeline such as
/// `ls | grep foo` is a single command for a real shell, not a `ls` invocation
/// with three operands. Everything in this file is pure Dart with no `dart:io`
/// import so the web stub can use the same rules.
enum CommandSyntax {
  /// Nothing but whitespace.
  empty,

  /// A single command with no shell metacharacters; safe to tokenize and
  /// dispatch as a portable built-in.
  simple,

  /// Contains unquoted shell syntax (`|`, `>`, `<`, `&`, `;`, backticks,
  /// `$(...)`) and must be forwarded intact to a real shell.
  compound,
}

/// One parsed token together with whether it came from a quoted segment.
class CommandToken {
  const CommandToken(this.text, {this.quoted = false});

  /// The unescaped text of the token.
  final String text;

  /// True when any part of the token was quoted or backslash-escaped.
  final bool quoted;

  @override
  String toString() => quoted ? '"$text"' : text;
}

/// Result of splitting a [CommandSyntax.simple] line.
class ParsedCommand {
  const ParsedCommand(this.tokens, {this.error});

  final List<CommandToken> tokens;

  /// Non-null when tokenizing failed (for example an unterminated quote). The
  /// message is user-facing and the command must not be executed.
  final String? error;

  bool get ok => error == null;
}

/// Classifies and tokenizes [line].
///
/// Order matters: [classify] only looks at *unquoted* characters, so
/// `cat "a|b.txt"` is [CommandSyntax.simple] while `cat a | b` is
/// [CommandSyntax.compound].
abstract final class CommandParser {
  /// Characters that, when unquoted, make a line shell syntax.
  ///
  /// Globs (`*?[`) also need a shell to expand, so they force the external
  /// path rather than being treated as literal operands. A backslash is always
  /// a literal character (a Windows path separator), never an escape, so
  /// classification and tokenization agree.
  static const String _operators = '|&;<>`*?[';

  static CommandSyntax classify(
    String line, {
    EscapePolicy escapePolicy = EscapePolicy.backslashEscapes,
  }) {
    if (line.trim().isEmpty) return CommandSyntax.empty;
    final hasNewline = line.contains('\n') || line.contains('\r');
    if (hasNewline) return CommandSyntax.compound;
    final escapes = escapePolicy == EscapePolicy.backslashEscapes;
    var quote = _Quote.none;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote == _Quote.single) {
        if (char == "'") quote = _Quote.none;
        continue;
      }
      if (quote == _Quote.double) {
        if (char == '"') {
          quote = _Quote.none;
          continue;
        }
        if (escapes && char == '\\' && i + 1 < line.length) {
          // Inside double quotes only `"` and `\\` are escapes (POSIX).
          final next = line[i + 1];
          if (next == '"' || next == '\\') i++;
          continue;
        }
        // `$` and backticks expand even inside double quotes.
        if (char == r'$' || char == '`') return CommandSyntax.compound;
        continue;
      }
      if (char == "'") {
        quote = _Quote.single;
        continue;
      }
      if (char == '"') {
        quote = _Quote.double;
        continue;
      }
      if (escapes) {
        if (char == '\\') {
          // A backslash escapes the next character (POSIX), so an escaped
          // operator is literal and the line can still be a simple command.
          if (i + 1 < line.length) i++;
          continue;
        }
        if (char == r'$') return CommandSyntax.compound;
        if (_operators.contains(char)) return CommandSyntax.compound;
        continue;
      }
      // Windows-literal policy: `\` is a path separator. A backslash followed
      // by whitespace or an operator cannot be safely tokenized as a single
      // operand, so route the whole line to the external shell instead of
      // splitting it into several filesystem mutations.
      if (char == '\\') {
        if (i + 1 < line.length) {
          final next = line[i + 1];
          if (next == ' ' || next == '\t' || _operators.contains(next)) {
            return CommandSyntax.compound;
          }
        }
        continue;
      }
      if (char == r'$') return CommandSyntax.compound;
      if (_operators.contains(char)) return CommandSyntax.compound;
    }
    return CommandSyntax.simple;
  }

  /// Splits a [CommandSyntax.simple] line into tokens.
  ///
  /// Quoted segments keep their inner spaces. Under [EscapePolicy.backslashEscapes]
  /// a backslash escapes the next character outside single quotes; under
  /// [EscapePolicy.backslashLiteral] it is a literal path separator. An
  /// unterminated quote or trailing escape produces [ParsedCommand.error].
  static ParsedCommand tokenize(
    String line, {
    EscapePolicy escapePolicy = EscapePolicy.backslashEscapes,
  }) {
    final escapes = escapePolicy == EscapePolicy.backslashEscapes;
    final tokens = <CommandToken>[];
    final buffer = StringBuffer();
    var quoted = false;
    var hasToken = false;
    var quote = _Quote.none;

    void flush() {
      if (!hasToken) return;
      tokens.add(CommandToken(buffer.toString(), quoted: quoted));
      buffer.clear();
      quoted = false;
      hasToken = false;
    }

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote == _Quote.single) {
        if (char == "'") {
          quote = _Quote.none;
        } else {
          buffer.write(char);
        }
        quoted = true;
        continue;
      }
      if (quote == _Quote.double) {
        if (char == '"') {
          quote = _Quote.none;
        } else if (escapes && char == '\\' && i + 1 < line.length) {
          final next = line[i + 1];
          if (next == '"' || next == '\\') {
            i++;
            buffer.write(next);
          } else {
            buffer.write(char);
          }
        } else {
          // Windows-literal double quotes keep every backslash, so `"C:\"` and
          // `"\\server\share"` retain their native separators.
          buffer.write(char);
        }
        quoted = true;
        continue;
      }
      if (char == ' ' || char == '\t') {
        flush();
        continue;
      }
      if (char == "'") {
        quote = _Quote.single;
        hasToken = true;
        quoted = true;
        continue;
      }
      if (char == '"') {
        quote = _Quote.double;
        hasToken = true;
        quoted = true;
        continue;
      }
      if (escapes && char == '\\') {
        // POSIX: a backslash escapes the next character. A trailing backslash
        // is an error rather than a silent drop.
        if (i + 1 >= line.length) {
          return const ParsedCommand([], error: 'unterminated escape sequence');
        }
        i++;
        buffer.write(line[i]);
        hasToken = true;
        quoted = true;
        continue;
      }
      // Windows-literal policy: a backslash is a path separator and stays put.
      buffer.write(char);
      hasToken = true;
    }

    if (quote != _Quote.none) {
      return const ParsedCommand([], error: 'unterminated quote');
    }
    flush();
    return ParsedCommand(tokens);
  }

  /// Convenience: classifies, and tokenizes only when [CommandSyntax.simple].
  ///
  /// Returns `null` for [CommandSyntax.compound] / [CommandSyntax.empty] so the
  /// caller must choose the shell path (compound) or do nothing (empty).
  static ParsedCommand? parseSimple(String line) {
    if (classify(line) != CommandSyntax.simple) return null;
    return tokenize(line);
  }
}

enum _Quote { none, single, double }
