import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/offline_tools.dart';

/// Unit tests for the shared offline conversion logic.
void main() {
  group('OfflineBase64', () {
    test('round-trips ASCII and CJK', () {
      expect(OfflineBase64.encode('hello'), 'aGVsbG8=');
      expect(OfflineBase64.decode('aGVsbG8='), 'hello');
      const cjk = '你好，世界';
      expect(OfflineBase64.decode(OfflineBase64.encode(cjk)), cjk);
    });

    test('uses the URL-safe alphabet without padding', () {
      // A character whose UTF-8 bytes encode to the index-62 and index-63
      // symbols in the standard alphabet but '-' and '_' in the URL-safe one.
      // 'ÿ' is U+00FF -> C3 BF -> "w78=".
      const text = '\u00ff\u00ff\u00fe';
      final standard = OfflineBase64.encode(text);
      final urlSafe = OfflineBase64.encodeUrlSafe(text);
      expect(standard, isNot(urlSafe));
      expect(urlSafe, isNot(contains('+')));
      expect(urlSafe, isNot(contains('/')));
      expect(urlSafe, isNot(contains('=')));
      expect(OfflineBase64.decodeUrlSafe(urlSafe), text);
    });

    test('reports invalid input instead of dropping it', () {
      expect(
        () => OfflineBase64.decode('%%%'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OfflineUrlCodec', () {
    test('encodes spaces as + and escapes the rest', () {
      expect(OfflineUrlCodec.encode('a b'), 'a+b');
      expect(OfflineUrlCodec.encode('café'), 'caf%C3%A9');
      expect(OfflineUrlCodec.encode('a=1&b=2'), 'a%3D1%26b%3D2');
    });

    test('decodes what it encoded', () {
      for (final text in ['a b', 'café', 'a=1&b=2', '中 文']) {
        expect(OfflineUrlCodec.decode(OfflineUrlCodec.encode(text)), text);
      }
    });

    test('rejects a malformed escape', () {
      expect(
        () => OfflineUrlCodec.decode('%ZZ'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OfflineDigest', () {
    // vectors from RFC 1321, RFC 3174 and FIPS 180-4.
    test('matches the published test vectors', () {
      expect(OfflineDigest.md5('abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(
        OfflineDigest.sha1('abc'),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(
        OfflineDigest.sha256('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('matches the empty-input vectors', () {
      expect(OfflineDigest.md5(''), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(
        OfflineDigest.sha1(''),
        'da39a3ee5e6b4b0d3255bfef95601890afd80709',
      );
      expect(
        OfflineDigest.sha256(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('handles input past one 64-byte block', () {
      // 62 bytes pushes the padding into a second block, which catches
      // length-padding mistakes. The expected values are the published ones for
      // this exact input.
      const long =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      expect(
        OfflineDigest.sha256(long),
        'f506898cc7c2e092f9eb9fadae7ba50383f5b46a2a4fe5597dbb553a78981268',
      );
      // The md5 of 1M 'a' is a standard long-vector check.
      expect(
        OfflineDigest.md5('a' * 1000000),
        '7707d6ae4e027c70eea2a935c2296f21',
      );
    });

    test('all() reports the three digests together', () {
      final result = OfflineDigest.all('abc');
      expect(result.keys, ['MD5', 'SHA-1', 'SHA-256']);
      expect(result['MD5'], '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  group('OfflineRegex', () {
    test('finds matches with index and groups', () {
      final result = OfflineRegex.test(r'(\d+)-(\d+)', 'a 12-34 b 56-78');
      expect(result.ok, isTrue);
      expect(result.matches.length, 2);
      expect(result.matches.first.value, '12-34');
      expect(result.matches.first.index, 2);
      expect(result.matches.first.groups, ['12', '34']);
    });

    test('reports an invalid pattern instead of throwing', () {
      final result = OfflineRegex.test('(', 'x');
      expect(result.ok, isFalse);
      expect(result.error, contains('正则无效'));
    });

    test('honours the flags', () {
      expect(OfflineRegex.test('ABC', 'abc').matches, isEmpty);
      expect(
        OfflineRegex.test('ABC', 'abc', caseSensitive: false).matches.length,
        1,
      );
      // Without dotAll a newline is not matched by '.'.
      expect(OfflineRegex.test('a.b', 'a\nb').matches, isEmpty);
      expect(OfflineRegex.test('a.b', 'a\nb', dotAll: true).matches.length, 1);
    });

    test('caps the match list', () {
      final result = OfflineRegex.test('a', 'a' * 500);
      expect(result.truncated, isTrue);
      expect(result.matches.length, OfflineRegex.maxMatches);
    });

    test('replaceAll rewrites every match', () {
      expect(OfflineRegex.replaceAll(r'\d', 'a1b2', '#'), 'a#b#');
    });
  });

  group('OfflineColorInfo', () {
    test('parses the three hex widths', () {
      expect(OfflineColorInfo.parse('#fff').hexArgb, '#FFFFFFFF');
      expect(OfflineColorInfo.parse('#FF0000').hexArgb, '#FFFF0000');
      expect(OfflineColorInfo.parse('#80FF0000').alpha, 0x80);
      expect(OfflineColorInfo.parse('FF0000').hexRgb, '#FF0000');
    });

    test('renders hex and CSS notations', () {
      final color = OfflineColorInfo.parse('#336699');
      expect(color.hexArgb, '#FF336699');
      expect(color.hexRgb, '#336699');
      expect(color.kotlinHex, '0xFF336699');
      expect(color.cssRgb, 'rgb(51, 102, 153)');
      expect(color.red, 0x33);
      expect(color.green, 0x66);
      expect(color.blue, 0x99);
    });

    test('reports an invalid colour', () {
      expect(
        () => OfflineColorInfo.parse('nope'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OfflineColorInfo.parse('#12345'),
        throwsA(isA<FormatException>()),
      );
    });

    test('computes hue/saturation/lightness', () {
      final red = OfflineColorInfo.parse('#FF0000');
      expect(red.hue, 0);
      expect(red.saturation, 1);
      final grey = OfflineColorInfo.parse('#808080');
      expect(grey.saturation, 0);
      expect(grey.cssHsl, contains('%'));
    });

    test('uses HSL saturation below and above half lightness', () {
      final darker = OfflineColorInfo.parse('#336699');
      expect(darker.hue, closeTo(210, 1e-10));
      expect(darker.saturation, closeTo(0.5, 1e-10));
      expect(darker.lightness, closeTo(0.4, 1e-10));
      expect(darker.cssHsl, 'hsl(210, 50%, 40%)');

      final lighter = OfflineColorInfo.parse('#6699CC');
      expect(lighter.hue, closeTo(210, 1e-10));
      expect(lighter.saturation, closeTo(0.5, 1e-10));
      expect(lighter.lightness, closeTo(0.6, 1e-10));
      expect(lighter.cssHsl, 'hsl(210, 50%, 60%)');
    });

    test('renders grey, black and white with zero saturation', () {
      for (final (hex, lightness, css) in [
        ('#808080', 128 / 255, 'hsl(0, 0%, 50%)'),
        ('#000000', 0.0, 'hsl(0, 0%, 0%)'),
        ('#FFFFFF', 1.0, 'hsl(0, 0%, 100%)'),
      ]) {
        final color = OfflineColorInfo.parse(hex);
        expect(color.hue, 0);
        expect(color.saturation, 0);
        expect(color.lightness, closeTo(lightness, 1e-10));
        expect(color.cssHsl, css);
      }
    });

    test('keeps alpha separate from HSL values', () {
      final color = OfflineColorInfo.parse('#80336699');
      expect(color.cssHsl, 'hsl(210, 50%, 40%)');
      expect(color.alpha, 0x80);
      expect(color.hexArgb, '#80336699');
      expect(color.cssRgb, 'rgba(51, 102, 153, 0.502)');
    });
  });

  group('OfflineUuid', () {
    test('v4 has the right shape and version bits', () {
      final uuid = OfflineUuid.v4();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(uuid),
        isTrue,
        reason: uuid,
      );
    });

    test('v4 is not constant', () {
      expect(OfflineUuid.v4(), isNot(OfflineUuid.v4()));
    });

    test('v5 is deterministic for a name in the DNS namespace', () {
      // The well-known reference value for "www.example.com" in the DNS
      // namespace.
      expect(
        OfflineUuid.v5(
          'www.example.com',
          '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
        ),
        '2ed6657d-e927-568b-95e1-2665a8aea6a2',
      );
    });

    test('v3 is deterministic and carries version 3', () {
      final uuid = OfflineUuid.v3('www.example.com', '');
      expect(uuid, OfflineUuid.v3('www.example.com', ''));
      expect(uuid[14], '3');
    });
  });

  group('UnicodeInfo', () {
    test('reports BMP escapes and UTF-8 bytes', () {
      final info = UnicodeInfo(0x4E2D);
      expect(info.hex, 'U+4E2D');
      expect(info.unicodeEscape, r'\u4E2D');
      expect(info.utf8BytesHex, 'E4 B8 AD');
      expect(info.utf16UnitsHex, '4E2D');
    });

    test('splits an astral code point into a surrogate pair', () {
      final info = UnicodeInfo(0x1F600);
      expect(info.utf8BytesHex, 'F0 9F 98 80');
      expect(info.utf16Units.length, 2);
      expect(info.utf16UnitsHex, 'D83D DE00');
    });

    test('escapes non-BMP code points as two UTF-16 units', () {
      final info = UnicodeInfo(0x1F600);
      expect(info.unicodeEscape, r'\uD83D\uDE00');
      expect(UnicodeInfo(0x10FFFF).unicodeEscape, r'\uDBFF\uDFFF');
    });
  });

  group('OfflineTimestamp', () {
    test('formats local time with and without milliseconds', () {
      final time = DateTime(2026, 3, 4, 5, 6, 7, 89);
      expect(
        OfflineTimestamp.toLocal(time, milliseconds: true),
        '2026-03-04 05:06:07.089',
      );
      expect(
        OfflineTimestamp.toLocal(time, milliseconds: false),
        '2026-03-04 05:06:07',
      );
    });

    test('parses back what it formatted', () {
      final parsed = OfflineTimestamp.parseLocal('2026-03-04 05:06:07.089');
      expect(parsed, DateTime(2026, 3, 4, 5, 6, 7, 89));
    });

    test('accepts ISO separators and date-only input', () {
      expect(
        OfflineTimestamp.parseLocal('2026-03-04T05:06:07'),
        DateTime(2026, 3, 4, 5, 6, 7),
      );
      expect(OfflineTimestamp.parseLocal('2026-03-04'), DateTime(2026, 3, 4));
    });

    test('rejects nonsense', () {
      expect(OfflineTimestamp.parseLocal('not a date'), isNull);
      expect(OfflineTimestamp.parseLocal(''), isNull);
    });
  });
}
