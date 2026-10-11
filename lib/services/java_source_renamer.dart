/// Token-aware Java source renamer for the entry class.
///
/// Renames only the entry class declaration, its constructors and `new
/// EntryClass(...)` self-references. Comments, string/char literals and text
/// blocks are preserved verbatim, and helper type names or unrelated identifiers
/// are never touched. Package statements, line breaks and indentation are kept.
///
/// It is deliberately conservative: if no matching top-level declaration can be
/// found (or the identifier appears as a different helper type), it throws
/// [JavaSourceRenameException] rather than producing broken code.
library;

/// The runnable entry class name inferred from Java source.
class JavaEntryInfo {
  const JavaEntryInfo({
    required this.className,
    required this.packageName,
    required this.hasMain,
  });

  final String className;
  final String? packageName;
  final bool hasMain;
}

class JavaSourceRenameException implements Exception {
  const JavaSourceRenameException(this.message);

  final String message;

  @override
  String toString() => 'JavaSourceRenameException: $message';
}

/// Lexed Java source as a list of spans so rewriters can act on code only.
class _Span {
  const _Span(this.start, this.end, this.isCode);

  final int start;
  final int end;
  final bool isCode;
}

abstract final class JavaSourceRenamer {
  static final RegExp _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  /// Infers the entry class, package and whether a `main` method exists.
  ///
  /// Picks the top-level class that declares `public static void main`; if none
  /// does, the first top-level `public class`, else the first top-level class.
  static JavaEntryInfo analyze(String source) {
    final code = _codeOnly(source);
    final packageName = RegExp(
      r'\bpackage\s+([\w$.]+)\s*;',
    ).firstMatch(code)?.group(1);

    final classes = _topLevelClasses(source);
    if (classes.isEmpty) {
      throw const JavaSourceRenameException(
        'no top-level class declaration found',
      );
    }
    _TopLevelClass selected = classes.first;
    for (final candidate in classes) {
      final body = _classBody(source, candidate);
      if (body != null &&
          RegExp(
            r'static\s+void\s+main\s*\(',
          ).hasMatch(_codeOnly(body))) {
        selected = candidate;
        break;
      }
      if (candidate.isPublic) selected = candidate;
    }
    final body = _classBody(source, selected);
    final hasMain =
        body != null &&
        RegExp(r'static\s+void\s+main\s*\(').hasMatch(_codeOnly(body));
    return JavaEntryInfo(
      className: selected.name,
      packageName: packageName,
      hasMain: hasMain,
    );
  }

  /// Renames the entry class from [oldName] to [newName].
  ///
  /// Returns the rewritten source. Throws when [oldName] is not the declared
  /// entry class or when the declaration cannot be located unambiguously.
  static String renameEntryClass(
    String source, {
    required String oldName,
    required String newName,
  }) {
    if (oldName == newName) return source;
    final classes = _topLevelClasses(source);
    _TopLevelClass? target;
    for (final candidate in classes) {
      if (candidate.name == oldName) {
        target = candidate;
        break;
      }
    }
    if (target == null) {
      throw JavaSourceRenameException(
        'entry class $oldName is not declared at the top level',
      );
    }
    // Collision: another declared top-level type already uses the new name, or
    // the new name appears as a code-position type identifier we would clobber.
    for (final candidate in classes) {
      if (candidate.name == newName) {
        throw JavaSourceRenameException(
          'the new class name $newName is already declared in this file',
        );
      }
    }
    for (final match in _identifier.allMatches(source)) {
      if (match.group(0) != newName) continue;
      if (!_isCodePosition(source, match.start)) continue;
      throw JavaSourceRenameException(
        'the new class name $newName is already used in code and would collide',
      );
    }

    // Reject genuinely ambiguous source: if the entry class name is also bound
    // as a local variable, parameter or field, a text-level rename would
    // silently rename that value binding. Reject with a clear error instead of
    // guessing (a conservative outcome is preferred to a broken rewrite).
    if (_hasShadowingValueBinding(source, target, oldName)) {
      throw JavaSourceRenameException(
        '$oldName is also used as a value binding (variable/parameter/field); '
        'rename is ambiguous and was not applied',
      );
    }

    // Rewrite every code-position occurrence of the class name. In Java the
    // entry class name cannot be shadowed by a different *type* of the same
    // simple name within the file, so a code-position identifier equal to
    // [oldName] is the class declaration, a constructor, `new Entry(...)`, a
    // self-type reference, or `Entry.class`. Comments and string/char/text-block
    // literals are excluded by the lexer, so they are never touched.
    final spans = <(int, int)>[(target.nameStart, target.nameEnd)];
    for (final match in _identifier.allMatches(source)) {
      if (match.start == target.nameStart) continue;
      if (match.group(0) != oldName) continue;
      if (!_isCodePosition(source, match.start)) continue;
      spans.add((match.start, match.end));
    }

    spans.sort((a, b) => b.$1.compareTo(a.$1));
    final buffer = source;
    var result = buffer;
    for (final (start, end) in spans) {
      result = result.replaceRange(start, end, newName);
    }
    return result;
  }

  /// True when [index] lies in a code span (not a comment or literal).
  static bool _isCodePosition(String source, int index) {
    for (final span in _lex(source)) {
      if (index >= span.start && index < span.end) return span.isCode;
    }
    return true;
  }

  /// True when [name] is bound as a value (local variable, parameter or field)
  /// rather than used as the entry type. A value binding is detected by a code
  /// occurrence of [name] that is NOT part of a type use: a type use is preceded
  /// by `new`, `.`, `<`, `::`, is a declaration keyword target, or is followed by
  /// `(`/`.`/`::`/`[]`/`<` (constructor call, static member, generic). Anything
  /// that looks like `Name =`, `Name;`, `Name,`, `Name)` after a type token, or
  /// `Name` as a bare statement is treated as ambiguous.
  static bool _hasShadowingValueBinding(
    String source,
    _TopLevelClass target,
    String name,
  ) {
    for (final match in _identifier.allMatches(source)) {
      if (match.group(0) != name) continue;
      if (match.start == target.nameStart) continue; // the declaration itself
      if (!_isCodePosition(source, match.start)) continue;
      if (_isTypeUse(source, match, name)) continue;
      // A qualified unrelated type (`pkg.Main` or `Outer.Main`) is a type use.
      return true;
    }
    return false;
  }

  /// Heuristic: is the identifier a type use (self-type, ctor, `new`, `.class`,
  /// `::new`, generic arg, array element type) rather than a value binding?
  static bool _isTypeUse(String source, RegExpMatch match, String name) {
    // Preceding non-space token.
    var i = match.start - 1;
    while (i >= 0 && _isSpace(source.codeUnitAt(i))) {
      i--;
    }
    final before = i >= 0 ? source.codeUnitAt(i) : -1;
    if (before == 0x2e || before == 0x3c) return true; // `.` or `<`
    if (i >= 1 && source.substring(i - 1, i + 1) == '::') return true;
    if (i >= 2 && source.substring(i - 2, i + 1) == 'new') return true;
    final precedingWord = _wordBefore(source, match.start);
    if (precedingWord == 'new') return true;
    // Following non-space char.
    var j = match.end;
    while (j < source.length && _isSpace(source.codeUnitAt(j))) {
      j++;
    }
    final after = j < source.length ? source.codeUnitAt(j) : -1;
    // `Name.class`, `Name::`, `Name(` (ctor), `Name[` (array), `Name<` (generic),
    // `Name.` (static member) are type uses. A bare `Name` followed by `=`,
    // `;`, `,`, `)`, `.` assignment etc. is a value binding.
    if (after == 0x28) return true; // (
    if (after == 0x5b) return true; // [
    if (after == 0x3c) return true; // <
    if (after == 0x2e) return true; // `.` (static member call / class literal)
    if (j + 1 < source.length && source.substring(j, j + 2) == '::') return true;
    // `Name <identifier>` is a declaration whose type is `Name` (e.g. `Main
    // helper;` or `Main self() {...}`), i.e. a type use, not a value binding.
    final afterWord = _wordAt(source, j);
    if (afterWord.isNotEmpty && !_isValueKeyword(afterWord)) return true;
    return false;
  }

  static bool _isValueKeyword(String word) =>
      word == 'instanceof' || word == 'return' || word == 'else';

  static String _wordAt(String source, int index) {
    var j = index;
    while (j < source.length && _isSpace(source.codeUnitAt(j))) {
      j++;
    }
    final start = j;
    while (j < source.length) {
      final c = source.codeUnitAt(j);
      final isWordChar =
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5a) ||
          (c >= 0x61 && c <= 0x7a) ||
          c == 0x5f ||
          c == 0x24;
      if (!isWordChar) break;
      j++;
    }
    return source.substring(start, j);
  }

  static String _wordBefore(String source, int index) {
    var i = index - 1;
    while (i >= 0 && _isSpace(source.codeUnitAt(i))) {
      i--;
    }
    final end = i + 1;
    while (i >= 0) {
      final c = source.codeUnitAt(i);
      final isWordChar =
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5a) ||
          (c >= 0x61 && c <= 0x7a) ||
          c == 0x5f ||
          c == 0x24;
      if (!isWordChar) break;
      i--;
    }
    return source.substring(i + 1, end);
  }

  static bool _isSpace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;

  /// Returns only the code regions with comments/strings replaced by spaces,
  /// preserving offsets so matches align with the original source.
  static String _codeOnly(String source) {
    final units = source.codeUnits.toList();
    for (final span in _lex(source)) {
      if (!span.isCode) {
        for (var i = span.start; i < span.end; i++) {
          units[i] = 0x20;
        }
      }
    }
    return String.fromCharCodes(units);
  }

  static List<_TopLevelClass> _topLevelClasses(String source) {
    final code = _codeOnly(source);
    final result = <_TopLevelClass>[];
    final keyword = RegExp(
      r'(?:(public|protected|private)\s+)?(?:(abstract|final|static|sealed|non-sealed|strictfp)\s+)*(class|interface|enum|record)\s+([A-Za-z_$][A-Za-z0-9_$]*)',
    );
    var depth = 0;
    var i = 0;
    while (i < code.length) {
      final c = code.codeUnitAt(i);
      if (c == 0x7b) {
        depth++;
        i++;
        continue;
      }
      if (c == 0x7d) {
        depth--;
        i++;
        continue;
      }
      if (depth == 0) {
        final match = keyword.matchAsPrefix(code, i);
        if (match != null) {
          final nameGroup = match.group(4)!;
          final nameStart = match.start + match.group(0)!.lastIndexOf(nameGroup);
          result.add(
            _TopLevelClass(
              name: nameGroup,
              nameStart: nameStart,
              nameEnd: nameStart + nameGroup.length,
              declarationStart: match.start,
              isPublic: match.group(1) == 'public',
            ),
          );
        }
      }
      i++;
    }
    return result;
  }

  /// Extracts the body of [target] (from its first `{` to the matching `}`),
  /// or null when it cannot be located.
  static String? _classBody(String source, _TopLevelClass target) {
    final code = _codeOnly(source);
    var i = target.declarationStart;
    while (i < code.length && code.codeUnitAt(i) != 0x7b) {
      i++;
    }
    if (i >= code.length) return null;
    var depth = 0;
    final start = i;
    while (i < code.length) {
      final c = code.codeUnitAt(i);
      if (c == 0x7b) depth++;
      if (c == 0x7d) {
        depth--;
        if (depth == 0) return source.substring(start, i + 1);
      }
      i++;
    }
    return null;
  }

  /// Lexes source into code and non-code spans (comments, strings, chars).
  static List<_Span> _lex(String source) {
    final spans = <_Span>[];
    var i = 0;
    final n = source.length;
    var codeStart = 0;
    while (i < n) {
      final c = source[i];
      if (c == '/' && i + 1 < n && source[i + 1] == '/') {
        _flushCode(spans, codeStart, i);
        var j = i + 2;
        while (j < n && source[j] != '\n') {
          j++;
        }
        spans.add(_Span(i, j, false));
        i = j;
        codeStart = i;
        continue;
      }
      if (c == '/' && i + 1 < n && source[i + 1] == '*') {
        _flushCode(spans, codeStart, i);
        var j = i + 2;
        while (j + 1 < n && !(source[j] == '*' && source[j + 1] == '/')) {
          j++;
        }
        j = j + 2 <= n ? j + 2 : n;
        spans.add(_Span(i, j, false));
        i = j;
        codeStart = i;
        continue;
      }
      if (c == '"') {
        // Text block `"""`?
        if (i + 2 < n && source[i + 1] == '"' && source[i + 2] == '"') {
          _flushCode(spans, codeStart, i);
          var j = i + 3;
          while (j + 2 < n &&
              !(source[j] == '"' && source[j + 1] == '"' && source[j + 2] == '"')) {
            j++;
          }
          j = j + 3 <= n ? j + 3 : n;
          spans.add(_Span(i, j, false));
          i = j;
          codeStart = i;
          continue;
        }
        _flushCode(spans, codeStart, i);
        var j = i + 1;
        while (j < n) {
          if (source[j] == r'\') {
            j += 2;
            continue;
          }
          if (source[j] == '"') {
            j++;
            break;
          }
          if (source[j] == '\n') break;
          j++;
        }
        spans.add(_Span(i, j, false));
        i = j;
        codeStart = i;
        continue;
      }
      if (c == "'") {
        _flushCode(spans, codeStart, i);
        var j = i + 1;
        while (j < n) {
          if (source[j] == r'\') {
            j += 2;
            continue;
          }
          if (source[j] == "'") {
            j++;
            break;
          }
          if (source[j] == '\n') break;
          j++;
        }
        spans.add(_Span(i, j, false));
        i = j;
        codeStart = i;
        continue;
      }
      i++;
    }
    _flushCode(spans, codeStart, n);
    return spans;
  }

  static void _flushCode(List<_Span> spans, int start, int end) {
    if (end > start) spans.add(_Span(start, end, true));
  }
}

class _TopLevelClass {
  const _TopLevelClass({
    required this.name,
    required this.nameStart,
    required this.nameEnd,
    required this.declarationStart,
    required this.isPublic,
  });

  final String name;
  final int nameStart;
  final int nameEnd;
  final int declarationStart;
  final bool isPublic;
}
