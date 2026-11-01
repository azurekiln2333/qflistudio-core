/// Offline text, encoding, URL and random utilities for the common tools.
///
/// Pure Dart: no Flutter, no network, no file system. Every entry point is
/// deterministic except [OfflinePassword.generate], which takes its randomness
/// from an optional [math.Random] so tests can pin the output.
///
library;

import 'dart:convert';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Number bases
// ---------------------------------------------------------------------------

/// A number parsed from one base and re-rendered in every supported base.
class OfflineNumberResult {
  OfflineNumberResult(this.value);

  final BigInt value;

  static const List<int> bases = [2, 8, 10, 16];

  /// Parses [source] in [radix], or throws [FormatException] explaining why.
  ///
  /// Accepts an optional `+`/`-` sign, `0x` / `0b` / `0o` / `#` prefixes (which
  /// must agree with [radix]), single `_` digit separators between digits, and
  /// surrounding whitespace.
  factory OfflineNumberResult.parse(String source, {required int radix}) {
    if (!bases.contains(radix)) {
      throw FormatException('仅支持 2、8、10、16 进制，收到 $radix');
    }
    var text = source.trim().toLowerCase();
    if (text.isEmpty) throw const FormatException('请输入一个整数');
    final negative = text.startsWith('-');
    if (negative || text.startsWith('+')) text = text.substring(1);
    final prefix = switch (text) {
      _ when text.startsWith('0x') => 16,
      _ when text.startsWith('0b') => 2,
      _ when text.startsWith('0o') => 8,
      _ when text.startsWith('#') => 16,
      _ => null,
    };
    if (prefix != null) {
      if (prefix != radix) {
        throw FormatException(
          '前缀表示 ${_baseName(prefix)} 进制，与当前选择的 '
          '${_baseName(radix)} 进制不一致',
        );
      }
      text = text.substring(prefix == 16 && text.startsWith('#') ? 1 : 2);
    }
    if (text.isEmpty) throw const FormatException('缺少数字部分');
    final digitClass = switch (radix) {
      2 => '[01]',
      8 => '[0-7]',
      10 => '[0-9]',
      _ => '[0-9a-f]',
    };
    if (!RegExp('^$digitClass+(?:_$digitClass+)*\$').hasMatch(text)) {
      throw FormatException('「$text」不是合法的 ${_baseName(radix)} 进制数字');
    }
    final parsed = BigInt.parse(text.replaceAll('_', ''), radix: radix);
    return OfflineNumberResult(negative ? -parsed : parsed);
  }

  static String _baseName(int radix) => switch (radix) {
    2 => '二',
    8 => '八',
    10 => '十',
    16 => '十六',
    _ => '$radix',
  };

  /// [value] rendered in [radix], with grouping every [group] digits.
  String format(int radix, {int group = 0}) {
    final negative = value.isNegative;
    final digits = value.abs().toRadixString(radix).toUpperCase();
    final buffer = StringBuffer(negative ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (group > 0 && i > 0 && (digits.length - i) % group == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String get binary => format(2, group: 4);

  String get octal => format(8);

  String get decimal => value.toString();

  String get hexadecimal => format(16, group: 2);

  /// Base64 of the value's minimal big-endian two's complement bytes.
  ///
  /// Matches the convention Java's `BigInteger.toByteArray()` uses for the
  /// byte width, so small values may carry a leading zero byte when the top
  /// bit of the highest byte is set.
  String get base64 {
    final bytes = _bigIntBytes(value);
    return base64Encode(bytes);
  }

  /// Base64 of the unsigned magnitude bytes (no sign byte).
  String get base64Magnitude => base64Encode(_magnitudeBytes(value.abs()));

  /// Number of significant bits in the magnitude (0 for zero).
  int get bitLength {
    final bytes = _magnitudeBytes(value.abs());
    if (value == BigInt.zero) return 0;
    return (bytes.length - 1) * 8 + bytes.first.bitLength;
  }

  static List<int> _magnitudeBytes(BigInt magnitude) {
    if (magnitude == BigInt.zero) return const [0];
    final bytes = <int>[];
    var remaining = magnitude;
    final mask = BigInt.from(0xFF);
    while (remaining > BigInt.zero) {
      bytes.add((remaining & mask).toInt());
      remaining = remaining >> 8;
    }
    return bytes.reversed.toList();
  }

  static List<int> _bigIntBytes(BigInt value) {
    var bytes = _magnitudeBytes(value.abs());
    if ((bytes.first & 0x80) != 0) bytes = [0, ...bytes];
    if (value.isNegative) {
      // Two's complement over the fixed width.
      var carry = 1;
      for (var i = bytes.length - 1; i >= 0; i--) {
        final inverted = (~bytes[i] & 0xFF) + carry;
        bytes[i] = inverted & 0xFF;
        carry = inverted >> 8;
      }
      while (bytes.length > 1 && bytes.first == 0xFF && bytes[1] >= 0x80) {
        bytes.removeAt(0);
      }
    }
    return bytes;
  }
}

// ---------------------------------------------------------------------------
// Text statistics and casing
// ---------------------------------------------------------------------------

/// Character, word, line and byte counts for the statistics tool.
class OfflineTextStats {
  OfflineTextStats({
    required this.codePoints,
    required this.codeUnits,
    required this.utf8Bytes,
    required this.utf16Bytes,
    required this.charactersWithoutSpaces,
    required this.lines,
    required this.nonEmptyLines,
    required this.words,
    required this.cjkCharacters,
    required this.letters,
    required this.digits,
    required this.spaces,
    required this.punctuation,
  });

  factory OfflineTextStats.of(String text) {
    var words = 0;
    var inWord = false;
    var cjk = 0;
    var letters = 0;
    var digits = 0;
    var spaces = 0;
    var punctuation = 0;
    // Spaces, tabs and line breaks all count as whitespace for word splitting.
    final whitespace = RegExp(r'\s');
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (whitespace.hasMatch(char)) {
        inWord = false;
        spaces++;
      } else if (_isCjk(rune)) {
        // Each CJK ideograph is one word, as Chinese input tools count it.
        cjk++;
        words++;
        inWord = false;
      } else {
        if (!inWord) {
          words++;
          inWord = true;
        }
        if (RegExp(r'[0-9]').hasMatch(char)) {
          digits++;
        } else if (RegExp(r'[A-Za-z\u00C0-\u024F]').hasMatch(char)) {
          letters++;
        } else {
          punctuation++;
        }
      }
    }
    final textLines = const LineSplitter().convert(text);
    final lines = textLines.length;
    final nonEmptyLines = textLines
        .where((line) => line.trim().isNotEmpty)
        .length;
    return OfflineTextStats(
      codePoints: text.runes.length,
      codeUnits: text.length,
      utf8Bytes: utf8.encode(text).length,
      utf16Bytes: text.length * 2,
      charactersWithoutSpaces: text.runes
          .where((rune) => !whitespace.hasMatch(String.fromCharCode(rune)))
          .length,
      lines: lines,
      nonEmptyLines: nonEmptyLines,
      words: words,
      cjkCharacters: cjk,
      letters: letters,
      digits: digits,
      spaces: spaces,
      punctuation: punctuation,
    );
  }

  final int codePoints;
  final int codeUnits;
  final int utf8Bytes;
  final int utf16Bytes;
  final int charactersWithoutSpaces;
  final int lines;
  final int nonEmptyLines;
  final int words;
  final int cjkCharacters;
  final int letters;
  final int digits;
  final int spaces;
  final int punctuation;

  static bool _isCjk(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x2FA1F);

  /// Thousands separators for readable counts.
  static String grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// Text casing conversions that keep Unicode input intact.
abstract final class OfflineCasing {
  /// Splits [text] into words at spaces, punctuation and camelCase
  /// boundaries; accents and CJK characters stay attached to their neighbours.
  static List<String> words(String text) {
    final normalized = text
        .replaceAllMapped(
          RegExp(r'([A-Z])([A-Z][a-z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll(RegExp(r'[_\-\s]+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
  }

  static String upper(String text) => text.toUpperCase();

  static String lower(String text) => text.toLowerCase();

  /// `Hello World` style.
  static String title(String text) => words(text).map(_capitalize).join(' ');

  /// `helloWorld` style.
  static String camel(String text) {
    final parts = words(text);
    if (parts.isEmpty) return '';
    final buffer = StringBuffer(parts.first.toLowerCase());
    for (final part in parts.skip(1)) {
      buffer.write(_capitalize(part));
    }
    return buffer.toString();
  }

  /// `HelloWorld` style.
  static String pascal(String text) => words(text).map(_capitalize).join();

  /// `hello_world` style.
  static String snake(String text) =>
      words(text).map((word) => word.toLowerCase()).join('_');

  /// `HELLO_WORLD` style.
  static String screamingSnake(String text) =>
      words(text).map((word) => word.toUpperCase()).join('_');

  /// `hello-world` style.
  static String kebab(String text) =>
      words(text).map((word) => word.toLowerCase()).join('-');

  /// Uppercases the first rune and lowercases the rest, so `javaScript` and
  /// `JavaScript` both become `Javascript` in the identifier styles.
  static String _capitalize(String word) {
    if (word.isEmpty) return word;
    final first = String.fromCharCode(word.runes.first);
    return '${first.toUpperCase()}${word.substring(first.length).toLowerCase()}';
  }
}

// ---------------------------------------------------------------------------
// Line processing: sort, dedupe, trim
// ---------------------------------------------------------------------------

/// Options for the line sorter.
enum OfflineLineSort {
  none,
  ascending,
  descending,
  lengthAscending,
  lengthDescending,
}

abstract final class OfflineLines {
  /// Splits [text] into lines. A trailing newline does not create an empty
  /// final line, matching how editors display the buffer.
  static List<String> split(String text) {
    if (text.isEmpty) return const [];
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  /// Result of [process].
  static String process(
    String text, {
    required OfflineLineSort sort,
    required bool unique,
    required bool trim,
    required bool dropEmpty,
    required bool ignoreCase,
    required bool numbered,
  }) {
    var lines = split(text);
    if (trim) lines = lines.map((line) => line.trim()).toList();
    if (dropEmpty) lines = lines.where((line) => line.isNotEmpty).toList();
    if (unique) {
      final seen = <String>{};
      lines = [
        for (final line in lines)
          if (seen.add(ignoreCase ? line.toLowerCase() : line)) line,
      ];
    }
    switch (sort) {
      case OfflineLineSort.ascending:
        lines.sort((a, b) => _compare(a, b, ignoreCase));
      case OfflineLineSort.descending:
        lines.sort((a, b) => _compare(b, a, ignoreCase));
      case OfflineLineSort.lengthAscending:
        lines.sort((a, b) => _compareLength(a, b, ignoreCase));
      case OfflineLineSort.lengthDescending:
        lines.sort((a, b) => _compareLength(b, a, ignoreCase));
      case OfflineLineSort.none:
        break;
    }
    if (numbered) {
      final width = '${lines.length}'.length;
      lines = [
        for (var i = 0; i < lines.length; i++)
          '${'${i + 1}'.padLeft(width)}  ${lines[i]}',
      ];
    }
    return lines.join('\n');
  }

  static int _compare(String a, String b, bool ignoreCase) =>
      ignoreCase ? a.toLowerCase().compareTo(b.toLowerCase()) : a.compareTo(b);

  /// Shorter lines first, then alphabetical, so the order is stable.
  static int _compareLength(String a, String b, bool ignoreCase) {
    final byLength = a.runes.length.compareTo(b.runes.length);
    return byLength != 0 ? byLength : _compare(a, b, ignoreCase);
  }

  /// Number of repeated lines, grouped with their occurrence count.
  static Map<String, int> duplicates(String text, {required bool ignoreCase}) {
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final line in split(text)) {
      if (line.trim().isEmpty) continue;
      final key = ignoreCase ? line.toLowerCase() : line;
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => line);
    }
    return {
      for (final entry in counts.entries)
        if (entry.value > 1) display[entry.key]!: entry.value,
    };
  }
}

// ---------------------------------------------------------------------------
// Password generation
// ---------------------------------------------------------------------------

/// Generated password plus the strength facts the UI shows.
class OfflinePasswordResult {
  OfflinePasswordResult({
    required this.value,
    required this.poolSize,
    required this.entropyBits,
  });

  final String value;
  final int poolSize;
  final double entropyBits;

  /// `weak` / `fair` / `strong` / `very strong`, based on entropy only.
  String get strength {
    if (entropyBits < 40) return '弱';
    if (entropyBits < 60) return '一般';
    if (entropyBits < 90) return '强';
    return '很强';
  }

  /// Estimated seconds to brute force at 1e11 guesses per second.
  double get crackSeconds => math.pow(2, entropyBits - 1).toDouble() / 1e11;
}

abstract final class OfflinePassword {
  static const String lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String digits = '0123456789';
  static const String symbols = r'!@#$%^&*()-_=+[]{};:,.<>?/~';
  static const String ambiguous = 'Il1O0o';

  /// A random password that contains at least one character from every enabled
  /// class, with no ambiguous characters when [excludeAmbiguous] is set.
  ///
  /// Throws [ArgumentError] when no class is enabled, [length] is below the
  /// number of enabled classes.
  static OfflinePasswordResult generate({
    required int length,
    bool lower = true,
    bool upper = true,
    bool digit = true,
    bool symbol = true,
    bool excludeAmbiguous = false,
    math.Random? random,
  }) {
    String pool(String alphabet) => excludeAmbiguous
        ? alphabet.split('').where((char) => !ambiguous.contains(char)).join()
        : alphabet;
    final classes = [
      if (lower) pool(lowercase),
      if (upper) pool(uppercase),
      if (digit) pool(digits),
      if (symbol) pool(symbols),
    ];
    if (classes.isEmpty) {
      throw ArgumentError('请至少选择一种字符类型');
    }
    if (length < 1) throw ArgumentError('长度至少为 1');
    if (length < classes.length) {
      throw ArgumentError('长度为 $length 时无法同时包含 ${classes.length} 种字符类型，请加长');
    }
    final combined = classes.join();
    final rng = random ?? math.Random.secure();
    // Rejection sampling is uniform over passwords that contain every class.
    // Forcing a draw per class and shuffling biases that distribution.
    late List<String> chars;
    do {
      chars = List.generate(
        length,
        (_) => combined[rng.nextInt(combined.length)],
      );
    } while (classes.any((alphabet) => !chars.any(alphabet.contains)));
    // Inclusion/exclusion counts the valid strings, rather than overstating
    // entropy as though passwords missing an enabled class were possible.
    var count = BigInt.zero;
    for (var mask = 0; mask < 1 << classes.length; mask++) {
      var excluded = 0;
      var selections = 0;
      for (var i = 0; i < classes.length; i++) {
        if ((mask & (1 << i)) != 0) {
          excluded += classes[i].length;
          selections++;
        }
      }
      final ways = BigInt.from(combined.length - excluded).pow(length);
      count += selections.isEven ? ways : -ways;
    }
    final shift = math.max(0, count.bitLength - 53);
    final entropy = math.log((count >> shift).toDouble()) / math.ln2 + shift;
    return OfflinePasswordResult(
      value: chars.join(),
      poolSize: combined.length,
      entropyBits: entropy,
    );
  }
}

// ---------------------------------------------------------------------------
// HTML escaping
// ---------------------------------------------------------------------------

abstract final class OfflineHtml {
  static const Map<String, String> _namedEscapes = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  };

  /// Escapes text so it is safe inside HTML element content and attributes.
  ///
  /// With [nonAscii] set, code points above 0x7E become `&#xNNNN;` so the
  /// result is pure ASCII and survives encoding mismatches.
  static String escape(String text, {bool nonAscii = false}) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final named = _namedEscapes[char];
      if (named != null) {
        buffer.write(named);
      } else if (nonAscii && rune > 0x7E) {
        buffer.write('&#x${rune.toRadixString(16).toUpperCase()};');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static const Map<String, String> _namedUnescapes = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': '\u00A0',
  };

  /// Decodes the named entities above plus `&#NNN;` / `&#xNNNN;`.
  ///
  /// Unknown entities are left untouched rather than silently dropped.
  static String unescape(String text) {
    return text.replaceAllMapped(
      RegExp(r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z][a-zA-Z0-9]*);'),
      (match) {
        final body = match[1]!;
        if (body.startsWith('#x') || body.startsWith('#X')) {
          final value = int.tryParse(body.substring(2), radix: 16);
          return _codePoint(value) ?? match[0]!;
        }
        if (body.startsWith('#')) {
          final value = int.tryParse(body.substring(1));
          return _codePoint(value) ?? match[0]!;
        }
        return _namedUnescapes[body.toLowerCase()] ?? match[0]!;
      },
    );
  }

  static String? _codePoint(int? value) {
    if (value == null || value < 0 || value > 0x10FFFF) return null;
    // Lone surrogates cannot be encoded; keep the entity visible.
    if (value >= 0xD800 && value <= 0xDFFF) return null;
    return String.fromCharCode(value);
  }
}

// ---------------------------------------------------------------------------
// JSON <-> CSV
// ---------------------------------------------------------------------------

/// CSV written for spreadsheets: comma separated, CRLF rows, minimal quoting.
abstract final class OfflineCsv {
  static const String _lineEnding = '\r\n';

  /// Converts a JSON array of flat objects to CSV.
  ///
  /// Column order follows the keys of the first object, then any new keys in
  /// later objects. Nested objects and arrays are written as compact JSON.
  /// Throws [FormatException] when the shape cannot be tabulated.
  static String fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON 解析失败：${error.message}');
    }
    final rows = switch (decoded) {
      List<Object?> list => list,
      Map<String, Object?> map => [map],
      _ => throw const FormatException('顶层必须是对象数组或以对象为元素的数组'),
    };
    if (rows.isEmpty) throw const FormatException('数组为空，没有可导出的行');
    final columns = <String>[];
    final objects = <Map<String, Object?>>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map<String, Object?>) {
        throw FormatException('第 ${i + 1} 个元素不是 JSON 对象');
      }
      objects.add(row);
      for (final key in row.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    if (columns.isEmpty) throw const FormatException('对象没有可导出的字段');
    final buffer = StringBuffer(_writeRow(columns));
    for (final object in objects) {
      buffer.write(
        _writeRow([for (final column in columns) _cellValue(object[column])]),
      );
    }
    return buffer.toString();
  }

  /// Parses RFC 4180-style CSV (quoted fields, doubled quotes, CRLF or LF).
  ///
  /// Returns rows trimmed of the leading UTF-8 BOM and of blank trailing lines.
  static List<List<String>> parse(String source) {
    final text = source.startsWith('\uFEFF') ? source.substring(1) : source;
    final rows = <List<String>>[];
    final blankRows = <bool>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var justClosedQuote = false;
    var fieldStarted = false;
    void finishRow() {
      blankRows.add(row.isEmpty && field.isEmpty && !fieldStarted);
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field.clear();
      fieldStarted = false;
      justClosedQuote = false;
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
            justClosedQuote = true;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      switch (char) {
        case '"':
          if (!fieldStarted) {
            inQuotes = true;
            fieldStarted = true;
          } else {
            throw FormatException('第 ${i + 1} 个字符的引号不在字段开头');
          }
        case ',':
          row.add(field.toString());
          field.clear();
          fieldStarted = false;
          justClosedQuote = false;
        case '\r':
          if (i + 1 < text.length && text[i + 1] == '\n') i++;
          finishRow();
        case '\n':
          finishRow();
        default:
          if (justClosedQuote) {
            throw FormatException('第 ${i + 1} 个字符位于已闭合的引号之后');
          }
          field.write(char);
          fieldStarted = true;
      }
    }
    if (inQuotes) throw const FormatException('引号未闭合');
    if (fieldStarted || row.isNotEmpty) finishRow();
    while (rows.isNotEmpty && blankRows.last) {
      rows.removeLast();
      blankRows.removeLast();
    }
    if (rows.isEmpty) throw const FormatException('没有可解析的内容');
    return rows;
  }

  /// Converts CSV to a JSON array of objects, using the first row as headers.
  ///
  /// Duplicate or empty header names become `column_1`, `column_2`, ... so no
  /// cell is dropped. Cells become numbers when they parse unambiguously and
  /// stay strings otherwise, and empty cells become `null`.
  static String fromCsv(String source, {required bool inferTypes}) {
    final rows = parse(source);
    if (rows.isEmpty) throw const FormatException('没有可解析的内容');
    final headers = <String>[];
    for (var i = 0; i < rows.first.length; i++) {
      final name = rows.first[i].trim();
      final candidate = name.isEmpty ? 'column_${i + 1}' : name;
      var unique = candidate;
      var suffix = 2;
      while (headers.contains(unique)) {
        unique = '${candidate}_$suffix';
        suffix++;
      }
      headers.add(unique);
    }
    final objects = <Map<String, Object?>>[];
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      if (row.length > headers.length) {
        throw FormatException(
          '第 ${index + 1} 行有 ${row.length} 列，超过表头的 ${headers.length} 列',
        );
      }
      objects.add({
        for (var i = 0; i < headers.length; i++)
          headers[i]: _cellFromCsv(i < row.length ? row[i] : '', inferTypes),
      });
    }
    return const JsonEncoder.withIndent('  ').convert(objects);
  }

  static Object? _cellFromCsv(String cell, bool inferTypes) {
    if (!inferTypes) return cell;
    final text = cell.trim();
    if (text.isEmpty) return null;
    if (text == 'true') return true;
    if (text == 'false') return false;
    // Leading zeros ("007") stay strings so identifiers are not mangled.
    if (RegExp(r'^[+-]?0\d').hasMatch(text)) return cell;
    if (RegExp(r'^[+-]?\d+$').hasMatch(text)) {
      // Keep integers that cannot be represented by Dart's int exactly.
      return int.tryParse(text) ?? cell;
    }
    if (!RegExp(
      r'^[+-]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][+-]?\d+)?$',
    ).hasMatch(text)) {
      return cell;
    }
    final number = double.tryParse(text);
    if (number != null && number.isFinite) {
      return number;
    }
    return cell;
  }

  static String _cellValue(Object? value) => switch (value) {
    null => '',
    String text => text,
    Map() || List() => jsonEncode(value),
    _ => value.toString(),
  };

  static String _writeRow(List<Object?> cells) {
    final encoded = cells.map((cell) {
      final text = switch (cell) {
        null => '',
        String value => value,
        _ => cell.toString(),
      };
      if (text.contains(RegExp(r'[",\r\n]'))) {
        return '"${text.replaceAll('"', '""')}"';
      }
      return text;
    });
    return '${encoded.join(',')}$_lineEnding';
  }
}

// ---------------------------------------------------------------------------
// URL parsing and query editing
// ---------------------------------------------------------------------------

/// One component of a URL, labelled the way the tool displays it.
class OfflineUrlPart {
  const OfflineUrlPart({required this.label, required this.value});

  final String label;
  final String value;
}

/// A parsed absolute URL plus decoded query parameters.
class OfflineUrlInfo {
  OfflineUrlInfo({
    required this.scheme,
    required this.userInfo,
    required this.host,
    required this.port,
    required this.path,
    required this.query,
    required this.fragment,
    required this.parameters,
  });

  final String scheme;
  final String userInfo;
  final String host;
  final int port;
  final String path;
  final String query;
  final String fragment;
  final List<MapEntry<String, String?>> parameters;

  factory OfflineUrlInfo.parse(String source) {
    final text = source.trim();
    if (text.isEmpty) throw const FormatException('请输入 URL');
    final uri = Uri.tryParse(text);
    if (uri == null) throw const FormatException('URL 格式无法解析');
    if (!uri.hasScheme) {
      throw const FormatException('请输入带协议前缀的完整 URL，例如 https://');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'ftp') {
      throw FormatException('暂不支持 ${uri.scheme} 协议，请使用 http / https / ftp');
    }
    if (uri.host.isEmpty) throw const FormatException('URL 缺少主机名');
    if (uri.port > 65535) throw const FormatException('端口必须在 0 到 65535 之间');
    // Validate decoded paths here, so invalid UTF-8 is caught by the input
    // error handler rather than throwing later while rendering [parts].
    for (final segment in uri.path.split('/')) {
      Uri.decodeComponent(segment);
    }
    final parameters = <MapEntry<String, String?>>[];
    if (uri.query.isNotEmpty) {
      for (final parameter in uri.query.split('&')) {
        final separator = parameter.indexOf('=');
        parameters.add(
          MapEntry(
            Uri.decodeQueryComponent(
              separator < 0 ? parameter : parameter.substring(0, separator),
            ),
            separator < 0
                ? null
                : Uri.decodeQueryComponent(parameter.substring(separator + 1)),
          ),
        );
      }
    }
    return OfflineUrlInfo(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.port,
      path: uri.path.isEmpty ? '/' : uri.path,
      query: uri.query,
      fragment: uri.fragment,
      parameters: parameters,
    );
  }

  /// Query parameters added to [parameters], re-encoded.
  String withParameters(Iterable<MapEntry<String, String?>> entries) {
    final base = Uri(
      scheme: scheme,
      userInfo: userInfo.isEmpty ? null : userInfo,
      host: host,
      port: _isDefaultPort ? null : port,
      path: path,
      fragment: fragment.isEmpty ? null : fragment,
    );
    final query = <String>[];
    for (final entry in entries) {
      final key = Uri.encodeQueryComponent(entry.key);
      query.add(
        entry.value == null
            ? key
            : '$key=${Uri.encodeQueryComponent(entry.value!)}',
      );
    }
    if (query.isEmpty) return base.toString();
    // Uri.replace keeps the fragment and escapes the assembled query once.
    return base.replace(query: query.join('&')).toString();
  }

  bool get _isDefaultPort => switch (scheme) {
    'http' => port == 80,
    'https' => port == 443,
    'ftp' => port == 21,
    _ => false,
  };

  /// Components in display order, skipping the ones that are absent.
  List<OfflineUrlPart> get parts => [
    OfflineUrlPart(label: '协议', value: scheme),
    if (userInfo.isNotEmpty) OfflineUrlPart(label: '用户信息', value: userInfo),
    OfflineUrlPart(label: '主机', value: host),
    OfflineUrlPart(label: '端口', value: _isDefaultPort ? '$port（默认）' : '$port'),
    OfflineUrlPart(label: '路径', value: path),
    if (query.isNotEmpty) OfflineUrlPart(label: '查询串', value: query),
    if (fragment.isNotEmpty) OfflineUrlPart(label: '片段', value: fragment),
    OfflineUrlPart(
      label: '路径段',
      value: path
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .map(Uri.decodeComponent)
          .join(' / '),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Line diff
// ---------------------------------------------------------------------------

enum OfflineDiffKind { equal, removed, added }

class OfflineDiffLine {
  const OfflineDiffLine({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final OfflineDiffKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;

  String get prefix => switch (kind) {
    OfflineDiffKind.equal => ' ',
    OfflineDiffKind.removed => '-',
    OfflineDiffKind.added => '+',
  };
}

/// A line diff in unified form, with counts for the summary card.
class OfflineDiff {
  OfflineDiff({
    required this.lines,
    required this.removed,
    required this.added,
    required this.truncated,
  });

  final List<OfflineDiffLine> lines;
  final int removed;
  final int added;
  final bool truncated;

  bool get identical => removed == 0 && added == 0;

  /// Unified-diff text with `-` / `+` / ` ` prefixes.
  String get text =>
      lines.map((line) => '${line.prefix}${line.text}').join('\n');

  /// Longest common subsequence line diff, capped for large inputs.
  ///
  /// The cap keeps the O(n·m) table bounded on a phone; when the combined line
  /// count exceeds [maxCells] the diff reports [truncated] instead of stalling.
  static const int maxCells = 400000;

  factory OfflineDiff.of(
    String before,
    String after, {
    bool ignoreWhitespace = false,
    bool ignoreCase = false,
    bool ignoreBlankLines = false,
  }) {
    List<String> prepare(String text) {
      var lines = OfflineLines.split(text);
      if (ignoreBlankLines) {
        lines = lines.where((line) => line.trim().isNotEmpty).toList();
      }
      return lines;
    }

    String key(String line) {
      var value = ignoreWhitespace
          ? line.trim().replaceAll(RegExp(r'\s+'), ' ')
          : line;
      if (ignoreCase) value = value.toLowerCase();
      return value;
    }

    final oldLines = prepare(before);
    final newLines = prepare(after);
    final oldKeys = oldLines.map(key).toList();
    final newKeys = newLines.map(key).toList();
    final n = oldKeys.length;
    final m = newKeys.length;
    if (n == m && Iterable.generate(n).every((i) => oldKeys[i] == newKeys[i])) {
      return OfflineDiff(
        lines: [
          for (var i = 0; i < n; i++)
            OfflineDiffLine(
              kind: OfflineDiffKind.equal,
              text: oldLines[i],
              oldLine: i + 1,
              newLine: i + 1,
            ),
        ],
        removed: 0,
        added: 0,
        truncated: false,
      );
    }
    if (n * m > maxCells) {
      // Too large to align: report every line as a replacement, honestly.
      final lines = <OfflineDiffLine>[
        for (var i = 0; i < n; i++)
          OfflineDiffLine(
            kind: OfflineDiffKind.removed,
            text: oldLines[i],
            oldLine: i + 1,
          ),
        for (var i = 0; i < m; i++)
          OfflineDiffLine(
            kind: OfflineDiffKind.added,
            text: newLines[i],
            newLine: i + 1,
          ),
      ];
      return OfflineDiff(lines: lines, removed: n, added: m, truncated: true);
    }
    final table = List.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = oldKeys[i] == newKeys[j]
            ? table[i + 1][j + 1] + 1
            : math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
    final lines = <OfflineDiffLine>[];
    var removed = 0;
    var added = 0;
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (oldKeys[i] == newKeys[j]) {
        lines.add(
          OfflineDiffLine(
            kind: OfflineDiffKind.equal,
            text: oldLines[i],
            oldLine: i + 1,
            newLine: j + 1,
          ),
        );
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        lines.add(
          OfflineDiffLine(
            kind: OfflineDiffKind.removed,
            text: oldLines[i],
            oldLine: i + 1,
          ),
        );
        removed++;
        i++;
      } else {
        lines.add(
          OfflineDiffLine(
            kind: OfflineDiffKind.added,
            text: newLines[j],
            newLine: j + 1,
          ),
        );
        added++;
        j++;
      }
    }
    while (i < n) {
      lines.add(
        OfflineDiffLine(
          kind: OfflineDiffKind.removed,
          text: oldLines[i],
          oldLine: i + 1,
        ),
      );
      removed++;
      i++;
    }
    while (j < m) {
      lines.add(
        OfflineDiffLine(
          kind: OfflineDiffKind.added,
          text: newLines[j],
          newLine: j + 1,
        ),
      );
      added++;
      j++;
    }
    return OfflineDiff(
      lines: lines,
      removed: removed,
      added: added,
      truncated: false,
    );
  }
}
