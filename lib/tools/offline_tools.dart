/// Language-neutral offline codecs, digests, generators and conversions.
///
/// Pure Dart logic shared by every product. No Flutter or network dependency.
library;

import 'dart:convert';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------

/// UTF-8 text encoding with the standard and URL-safe Base64 alphabets.
abstract final class OfflineBase64 {
  /// Encodes UTF-8 bytes with the standard alphabet.
  static String encode(String text) => base64.encode(utf8.encode(text));

  /// Decodes the standard alphabet; throws [FormatException] on invalid input.
  static String decode(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s'), '');
    return utf8.decode(base64.decode(normalized));
  }

  /// URL-safe alphabet without padding.
  static String encodeUrlSafe(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  /// URL-safe alphabet, padding restored.
  static String decodeUrlSafe(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s'), '');
    final padding = (4 - normalized.length % 4) % 4;
    return utf8.decode(base64Url.decode('$normalized${'=' * padding}'));
  }
}

// ---------------------------------------------------------------------------
// URL encoding
// ---------------------------------------------------------------------------

/// UTF-8 form URL encoding (`application/x-www-form-urlencoded`).
abstract final class OfflineUrlCodec {
  /// Spaces become `+`; bytes outside `A-Za-z0-9-_.*` are percent-encoded.
  static String encode(String text) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(text)) {
      final char = String.fromCharCode(byte);
      if (RegExp(r'[A-Za-z0-9\-_.*]').hasMatch(char)) {
        buffer.write(char);
      } else if (char == ' ') {
        buffer.write('+');
      } else {
        buffer.write(
          '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
        );
      }
    }
    return buffer.toString();
  }

  /// Decodes [encode]'s form notation, including `+` for spaces.
  static String decode(String text) {
    final bytes = <int>[];
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '+') {
        bytes.add(0x20);
      } else if (char == '%' && i + 2 < text.length) {
        final hex = text.substring(i + 1, i + 3);
        final value = int.tryParse(hex, radix: 16);
        if (value == null) throw FormatException('无效的百分号转义：%$hex');
        bytes.add(value);
        i += 2;
      } else {
        bytes.add(char.codeUnitAt(0));
      }
    }
    return utf8.decode(bytes);
  }
}

// ---------------------------------------------------------------------------
// Message digests
// ---------------------------------------------------------------------------

/// Pure-Dart MD5, SHA-1 and SHA-256 digests of UTF-8 input.
///
/// Byte-oriented entry points support binary namespace hashing for UUIDs.
abstract final class OfflineDigest {
  static String md5(String text) => _hex(_md5(utf8.encode(text)));

  static String sha1(String text) => _hex(_sha1(utf8.encode(text)));

  static String sha256(String text) => _hex(_sha256(utf8.encode(text)));

  /// Raw-byte entry points, used by the UUID generators which hash binary
  /// namespace bytes rather than text.
  static List<int> md5Bytes(List<int> bytes) => _md5(bytes);

  static List<int> sha1Bytes(List<int> bytes) => _sha1(bytes);

  static List<int> sha256Bytes(List<int> bytes) => _sha256(bytes);

  /// MD5, SHA-1 and SHA-256 for one input, in the order the UI lists them.
  static Map<String, String> all(String text) => {
    'MD5': md5(text),
    'SHA-1': sha1(text),
    'SHA-256': sha256(text),
  };

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // -- MD5 (RFC 1321) ------------------------------------------------------

  static const List<int> _md5Shift = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static List<int> _md5(List<int> input) {
    final message = _pad(input, littleEndianLength: true);
    var a0 = 0x67452301;
    var b0 = 0xefcdab89;
    var c0 = 0x98badcfe;
    var d0 = 0x10325476;
    const k = <int>[
      0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, //
      0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
      0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
      0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
      0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
      0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
      0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
      0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
      0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
      0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
      0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
      0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
      0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
      0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
      0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
      0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ];
    for (var offset = 0; offset < message.length; offset += 64) {
      final m = List<int>.generate(
        16,
        (i) => _readInt32(message, offset + i * 4, littleEndian: true),
      );
      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;
      for (var i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = (b & c) | (~b & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | (~d & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | ~d);
          g = (7 * i) % 16;
        }
        f = _add32(_add32(_add32(f, a), k[i]), m[g]);
        a = d;
        d = c;
        c = b;
        b = _add32(b, _rotateLeft(f, _md5Shift[i]));
      }
      a0 = _add32(a0, a);
      b0 = _add32(b0, b);
      c0 = _add32(c0, c);
      d0 = _add32(d0, d);
    }
    final out = <int>[];
    for (final word in [a0, b0, c0, d0]) {
      out.addAll(_writeInt32(word, littleEndian: true));
    }
    return out;
  }

  // -- SHA-1 (RFC 3174) ----------------------------------------------------

  static List<int> _sha1(List<int> input) {
    final message = _pad(input, littleEndianLength: false);
    var h0 = 0x67452301;
    var h1 = 0xefcdab89;
    var h2 = 0x98badcfe;
    var h3 = 0x10325476;
    var h4 = 0xc3d2e1f0;
    for (var offset = 0; offset < message.length; offset += 64) {
      final w = List<int>.filled(80, 0);
      for (var i = 0; i < 16; i++) {
        w[i] = _readInt32(message, offset + i * 4, littleEndian: false);
      }
      for (var i = 16; i < 80; i++) {
        w[i] = _rotateLeft(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      }
      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      for (var i = 0; i < 80; i++) {
        int f;
        int k;
        if (i < 20) {
          f = (b & c) | (~b & d);
          k = 0x5a827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ed9eba1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8f1bbcdc;
        } else {
          f = b ^ c ^ d;
          k = 0xca62c1d6;
        }
        final temp = _add32(
          _add32(_add32(_add32(_rotateLeft(a, 5), f), e), k),
          w[i],
        );
        e = d;
        d = c;
        c = _rotateLeft(b, 30);
        b = a;
        a = temp;
      }
      h0 = _add32(h0, a);
      h1 = _add32(h1, b);
      h2 = _add32(h2, c);
      h3 = _add32(h3, d);
      h4 = _add32(h4, e);
    }
    return [
      for (final word in [h0, h1, h2, h3, h4])
        ..._writeInt32(word, littleEndian: false),
    ];
  }

  // -- SHA-256 (FIPS 180-4) ------------------------------------------------

  static const List<int> _sha256K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static List<int> _sha256(List<int> input) {
    final message = _pad(input, littleEndianLength: false);
    final h = <int>[
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    for (var offset = 0; offset < message.length; offset += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        w[i] = _readInt32(message, offset + i * 4, littleEndian: false);
      }
      for (var i = 16; i < 64; i++) {
        final s0 =
            _rotateRight(w[i - 15], 7) ^
            _rotateRight(w[i - 15], 18) ^
            (w[i - 15] >> 3);
        final s1 =
            _rotateRight(w[i - 2], 17) ^
            _rotateRight(w[i - 2], 19) ^
            (w[i - 2] >> 10);
        w[i] = _add32(_add32(_add32(w[i - 16], s0), w[i - 7]), s1);
      }
      var a = h[0];
      var b = h[1];
      var c = h[2];
      var d = h[3];
      var e = h[4];
      var f = h[5];
      var g = h[6];
      var hh = h[7];
      for (var i = 0; i < 64; i++) {
        final s1 =
            _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
        final ch = (e & f) ^ (~e & g);
        final temp1 = _add32(
          _add32(_add32(_add32(hh, s1), ch), _sha256K[i]),
          w[i],
        );
        final s0 =
            _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = _add32(s0, maj);
        hh = g;
        g = f;
        f = e;
        e = _add32(d, temp1);
        d = c;
        c = b;
        b = a;
        a = _add32(temp1, temp2);
      }
      h[0] = _add32(h[0], a);
      h[1] = _add32(h[1], b);
      h[2] = _add32(h[2], c);
      h[3] = _add32(h[3], d);
      h[4] = _add32(h[4], e);
      h[5] = _add32(h[5], f);
      h[6] = _add32(h[6], g);
      h[7] = _add32(h[7], hh);
    }
    return [for (final word in h) ..._writeInt32(word, littleEndian: false)];
  }

  // -- shared helpers ------------------------------------------------------

  /// Appends the `10…0` padding and the 64-bit big/little-endian length.
  static List<int> _pad(List<int> input, {required bool littleEndianLength}) {
    final bitLength = input.length * 8;
    final out = List<int>.from(input)..add(0x80);
    while (out.length % 64 != 56) {
      out.add(0);
    }
    out.addAll(_writeInt64(bitLength, littleEndian: littleEndianLength));
    return out;
  }

  static int _add32(int a, int b) => (a + b) & 0xFFFFFFFF;

  static int _rotateLeft(int value, int count) =>
      ((value << count) | (value >> (32 - count))) & 0xFFFFFFFF;

  static int _rotateRight(int value, int count) =>
      ((value >> count) | (value << (32 - count))) & 0xFFFFFFFF;

  static int _readInt32(
    List<int> bytes,
    int offset, {
    required bool littleEndian,
  }) {
    if (littleEndian) {
      return bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static List<int> _writeInt32(int value, {required bool littleEndian}) =>
      littleEndian
      ? [
          value & 0xFF,
          (value >> 8) & 0xFF,
          (value >> 16) & 0xFF,
          (value >> 24) & 0xFF,
        ]
      : [
          (value >> 24) & 0xFF,
          (value >> 16) & 0xFF,
          (value >> 8) & 0xFF,
          value & 0xFF,
        ];

  static List<int> _writeInt64(int value, {required bool littleEndian}) {
    final low = value & 0xFFFFFFFF;
    final high = (value >> 32) & 0xFFFFFFFF;
    final bytes = <int>[];
    if (littleEndian) {
      bytes.addAll(_writeInt32(low, littleEndian: true));
      bytes.addAll(_writeInt32(high, littleEndian: true));
    } else {
      bytes.addAll(_writeInt32(high, littleEndian: false));
      bytes.addAll(_writeInt32(low, littleEndian: false));
    }
    return bytes;
  }
}

// ---------------------------------------------------------------------------
// Regular expressions
// ---------------------------------------------------------------------------

/// One `RegExp` match, flattened for display.
class OfflineRegexMatch {
  OfflineRegexMatch({
    required this.index,
    required this.value,
    required this.groups,
    required this.namedGroups,
  });

  final int index;
  final String value;
  final List<String?> groups;
  final Map<String, String?> namedGroups;
}

/// Result of running a pattern over an input, or the reason it failed.
class OfflineRegexResult {
  OfflineRegexResult.error(this.error) : matches = const [], truncated = false;

  OfflineRegexResult.success(this.matches, {required this.truncated})
    : error = null;

  final List<OfflineRegexMatch> matches;
  final String? error;
  final bool truncated;

  bool get ok => error == null;
}

/// Pattern matching with Dart's [RegExp] syntax and flags.
abstract final class OfflineRegex {
  static const int maxMatches = 200;

  static OfflineRegexResult test(
    String pattern,
    String input, {
    bool multiLine = false,
    bool dotAll = false,
    bool caseSensitive = true,
  }) {
    final RegExp expression;
    try {
      expression = RegExp(
        pattern,
        multiLine: multiLine,
        dotAll: dotAll,
        caseSensitive: caseSensitive,
      );
    } on FormatException catch (error) {
      return OfflineRegexResult.error('正则无效：${error.message}');
    }
    final matches = <OfflineRegexMatch>[];
    var count = 0;
    for (final match in expression.allMatches(input)) {
      if (count++ >= maxMatches) {
        return OfflineRegexResult.success(matches, truncated: true);
      }
      matches.add(
        OfflineRegexMatch(
          index: match.start,
          value: match.group(0) ?? '',
          groups: [for (var i = 1; i <= match.groupCount; i++) match.group(i)],
          namedGroups: match.groupNames.isEmpty
              ? const {}
              : {
                  for (final name in match.groupNames)
                    name: match.namedGroup(name),
                },
        ),
      );
    }
    return OfflineRegexResult.success(matches, truncated: false);
  }

  /// Replaces every match using Dart's [String.replaceAll] semantics.
  static String replaceAll(String pattern, String input, String replacement) {
    return input.replaceAll(RegExp(pattern), replacement);
  }
}

// ---------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------

/// A colour represented as packed ARGB, hex, RGB and HSL values.
class OfflineColorInfo {
  OfflineColorInfo(this.argb);

  /// Constructs from `#RGB`, `#RRGGBB` or `#AARRGGBB`, with or without `#`.
  factory OfflineColorInfo.parse(String text) {
    var hex = text.trim().replaceFirst('#', '').toUpperCase();
    if (hex.startsWith('0X')) hex = hex.substring(2);
    final value = int.tryParse(hex, radix: 16);
    if (value == null) throw FormatException('无效的十六进制颜色：$text');
    switch (hex.length) {
      case 3:
        // #RGB expands each nibble, as CSS does.
        final r = hex[0], g = hex[1], b = hex[2];
        return OfflineColorInfo(int.parse('FF$r$r$g$g$b$b', radix: 16));
      case 6:
        return OfflineColorInfo(0xFF000000 | value);
      case 8:
        return OfflineColorInfo(value);
      default:
        throw const FormatException('颜色应为 #RGB、#RRGGBB 或 #AARRGGBB');
    }
  }

  factory OfflineColorInfo.fromArgb(int a, int r, int g, int b) =>
      OfflineColorInfo(
        ((a & 0xFF) << 24) |
            ((r & 0xFF) << 16) |
            ((g & 0xFF) << 8) |
            (b & 0xFF),
      );

  /// The packed `0xAARRGGBB` value.
  final int argb;

  int get alpha => (argb >> 24) & 0xFF;
  int get red => (argb >> 16) & 0xFF;
  int get green => (argb >> 8) & 0xFF;
  int get blue => argb & 0xFF;

  /// `#AARRGGBB`, including the alpha component.
  String get hexArgb =>
      '#${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  /// `#RRGGBB`, the CSS/Flutter notation when the value is opaque.
  String get hexRgb =>
      '#${(argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  /// A `0xAARRGGBB` hexadecimal literal.
  String get kotlinHex =>
      '0x${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  /// `rgb(r, g, b)` / `rgba(...)`.
  String get cssRgb => alpha == 255
      ? 'rgb($red, $green, $blue)'
      : 'rgba($red, $green, $blue, ${(alpha / 255).toStringAsFixed(3)})';

  /// Hue in degrees, 0-360.
  double get hue {
    final r = red / 255;
    final g = green / 255;
    final b = blue / 255;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;
    if (delta == 0) return 0;
    double h;
    if (max == r) {
      h = ((g - b) / delta) % 6;
    } else if (max == g) {
      h = (b - r) / delta + 2;
    } else {
      h = (r - g) / delta + 4;
    }
    return (h * 60 + 360) % 360;
  }

  /// HSL saturation in the range 0-1.
  double get saturation {
    final max = math.max(red, math.max(green, blue)) / 255;
    final min = math.min(red, math.min(green, blue)) / 255;
    final delta = max - min;
    if (delta == 0) return 0;
    return delta / (1 - (2 * lightness - 1).abs());
  }

  /// HSL lightness in the range 0-1.
  double get lightness =>
      (math.max(red, math.max(green, blue)) +
          math.min(red, math.min(green, blue))) /
      (2 * 255);

  /// `hsl(h, s%, l%)`, rounded for display.
  String get cssHsl =>
      'hsl(${hue.round()}, ${(saturation * 100).round()}%, ${(lightness * 100).round()}%)';
}

// ---------------------------------------------------------------------------
// UUID
// ---------------------------------------------------------------------------

/// UUID generation, including the deterministic v3/v5 (name-based) forms.
abstract final class OfflineUuid {
  /// A random version-4 UUID, `8-4-4-4-12` lowercase.
  static String v4([math.Random? random]) {
    final rng = random ?? math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 1
    return _format(bytes);
  }

  /// A version-3 (MD5 name-based) UUID for [name] in [namespace].
  static String v3(String name, String namespace) {
    final input = _namespaceBytes(namespace) + utf8.encode(name);
    final digest = OfflineDigest.md5Bytes(input);
    digest[6] = (digest[6] & 0x0F) | 0x30;
    digest[8] = (digest[8] & 0x3F) | 0x80;
    return _format(digest);
  }

  /// A version-5 (SHA-1 name-based) UUID for [name] in [namespace].
  static String v5(String name, String namespace) {
    final input = _namespaceBytes(namespace) + utf8.encode(name);
    final digest = OfflineDigest.sha1Bytes(input).sublist(0, 16);
    digest[6] = (digest[6] & 0x0F) | 0x50;
    digest[8] = (digest[8] & 0x3F) | 0x80;
    return _format(digest);
  }

  /// Parses a UUID's namespace argument, or the RFC 4122 DNS namespace by
  /// default when the text is not a UUID.
  static List<int> _namespaceBytes(String namespace) {
    final hex = namespace.trim().replaceAll('-', '');
    if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
      return _hexToBytes(hex);
    }
    // 6ba7b810-9dad-11d1-80b4-00c04fd430c8 (DNS namespace).
    return _hexToBytes('6ba7b8109dad11d180b400c04fd430c8');
  }

  static List<int> _hexToBytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];

  static String _format(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}

/// One code point's representations, as the character tool displays them.
class UnicodeInfo {
  UnicodeInfo(this.codePoint);

  final int codePoint;

  String get hex =>
      'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// One four-digit Unicode escape for each UTF-16 code unit.
  String get unicodeEscape => utf16Units
      .map(
        (unit) => '\\u${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
      )
      .join();

  /// UTF-8 bytes for this code point.
  List<int> get utf8Bytes => _utf8(codePoint);

  /// UTF-16 code units. A code point above the BMP becomes a surrogate pair.
  List<int> get utf16Units {
    if (codePoint <= 0xFFFF) return [codePoint];
    final offset = codePoint - 0x10000;
    return [0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF)];
  }

  String get utf8BytesHex => utf8Bytes
      .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join(' ');

  String get utf16UnitsHex => utf16Units
      .map((u) => u.toRadixString(16).toUpperCase().padLeft(4, '0'))
      .join(' ');

  static List<int> _utf8(int codePoint) {
    if (codePoint <= 0x7F) return [codePoint];
    if (codePoint <= 0x7FF) {
      return [0xC0 | (codePoint >> 6), 0x80 | (codePoint & 0x3F)];
    }
    if (codePoint <= 0xFFFF) {
      return [
        0xE0 | (codePoint >> 12),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    }
    return [
      0xF0 | (codePoint >> 18),
      0x80 | ((codePoint >> 12) & 0x3F),
      0x80 | ((codePoint >> 6) & 0x3F),
      0x80 | (codePoint & 0x3F),
    ];
  }
}

/// Timestamp conversion between epoch values and local date/time.
abstract final class OfflineTimestamp {
  /// Formats local date/time as `yyyy-MM-dd HH:mm:ss[.SSS]`.
  ///
  /// [milliseconds] includes the three-digit fractional part when true.
  static String toLocal(DateTime local, {required bool milliseconds}) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-'
        '${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
        '${milliseconds ? '.${local.millisecond.toString().padLeft(3, '0')}' : ''}';
  }

  /// Parses `yyyy-MM-dd HH:mm:ss[.SSS]` (and `T`-separated ISO input) as local
  /// time, returning null when the text is not a date this tool accepts.
  static DateTime? parseLocal(String source) {
    final text = source.trim().replaceFirst('T', ' ');
    if (text.isEmpty) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d{1,3}))?$',
    ).firstMatch(text);
    if (match == null) {
      final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
      if (dateOnly == null) return null;
      return DateTime(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
      );
    }
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
      int.parse(match.group(7)?.padRight(3, '0') ?? '0'),
    );
  }
}
