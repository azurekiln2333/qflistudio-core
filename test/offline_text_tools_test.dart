import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/offline_text_tools.dart';

void main() {
  group('number bases', () {
    test('supports prefixes, signed large integers and digit separators', () {
      final result = OfflineNumberResult.parse('-0xFF_FF', radix: 16);
      expect(result.decimal, '-65535');
      expect(result.hexadecimal, '-FF FF');
      expect(result.bitLength, 16);
      final large = BigInt.one << 200;
      expect(OfflineNumberResult.parse('$large', radix: 10).value, large);
    });

    test('rejects malformed signs, separators and mismatched prefixes', () {
      for (final text in ['_1', '1_', '1__0', '--1', '+-1', '-+1', '0xFF']) {
        expect(
          () => OfflineNumberResult.parse(text, radix: 10),
          throwsFormatException,
          reason: text,
        );
      }
    });

    test('Base64 encodes minimal signed bytes without UTF-8 conversion', () {
      const vectors = {
        0: 'AA==',
        127: 'fw==',
        128: 'AIA=',
        255: 'AP8=',
        256: 'AQA=',
        -1: '/w==',
        -128: 'gA==',
        -129: '/38=',
        -256: '/wA=',
        -32768: 'gAA=',
      };
      for (final entry in vectors.entries) {
        expect(OfflineNumberResult(BigInt.from(entry.key)).base64, entry.value);
      }
      expect(OfflineNumberResult(BigInt.from(255)).base64Magnitude, '/w==');
    });
  });

  test('text statistics count Unicode code points, bytes and line breaks', () {
    final stats = OfflineTextStats.of('Hi 中😀\r\n42');
    expect(stats.codePoints, 9);
    expect(stats.codeUnits, 10);
    expect(stats.utf8Bytes, utf8.encode('Hi 中😀\r\n42').length);
    expect(stats.lines, 2);
    expect(stats.nonEmptyLines, 2);
    expect(stats.cjkCharacters, 1);
    expect(stats.letters, 2);
    expect(stats.digits, 2);
    expect(stats.spaces, 3);
    expect(OfflineTextStats.of('a\rb').nonEmptyLines, 2);
  });

  test('naming styles retain Unicode and split acronym/camel boundaries', () {
    expect(
      OfflineCasing.snake('getURLValue-userName'),
      'get_url_value_user_name',
    );
    expect(
      OfflineCasing.camel('user profile image URL'),
      'userProfileImageUrl',
    );
    expect(OfflineCasing.pascal('élève 中文'), 'Élève中文');
    expect(OfflineCasing.snake("user's name"), 'user_s_name');
    expect(OfflineCasing.pascal('\u{10428}word'), '\u{10400}word');
  });

  test('line processing combines trim, dedupe, sorting and numbering', () {
    expect(
      OfflineLines.process(
        ' b\r\nA\rb\n\na ',
        sort: OfflineLineSort.ascending,
        unique: true,
        trim: true,
        dropEmpty: true,
        ignoreCase: true,
        numbered: true,
      ),
      '1  A\n2  b',
    );
    expect(OfflineLines.duplicates('a\nA\nb', ignoreCase: true), {'a': 2});
  });

  group('passwords', () {
    test('honors every enabled class and excludes ambiguous characters', () {
      final random = math.Random(12);
      for (var i = 0; i < 20; i++) {
        final password = OfflinePassword.generate(
          length: 4,
          excludeAmbiguous: true,
          random: random,
        ).value;
        expect(password, hasLength(4));
        for (final alphabet in [
          OfflinePassword.lowercase,
          OfflinePassword.uppercase,
          OfflinePassword.digits,
          OfflinePassword.symbols,
        ]) {
          expect(password.split('').any(alphabet.contains), isTrue);
        }
        expect(
          password.split('').any(OfflinePassword.ambiguous.contains),
          isFalse,
        );
      }
    });

    test('entropy counts the strings that satisfy the class requirements', () {
      final result = OfflinePassword.generate(
        length: 2,
        upper: false,
        symbol: false,
        random: math.Random(5),
      );
      // One letter and one digit, in either order: 2 * 26 * 10.
      expect(result.entropyBits, closeTo(math.log(520) / math.ln2, 1e-10));
      expect(result.poolSize, 36);
      expect(() => OfflinePassword.generate(length: 3), throwsArgumentError);
      expect(
        () => OfflinePassword.generate(
          length: 8,
          lower: false,
          upper: false,
          digit: false,
          symbol: false,
        ),
        throwsArgumentError,
      );
    });
  });

  test(
    'HTML entities round-trip supplementary Unicode and retain bad entities',
    () {
      const text = '<a title="中😀">&\'</a>';
      final escaped = OfflineHtml.escape(text, nonAscii: true);
      expect(escaped, contains('&#x1F600;'));
      expect(OfflineHtml.unescape(escaped), text);
      expect(OfflineHtml.unescape('&#X41;&#65;&nbsp;'), 'AA\u00A0');
      expect(
        OfflineHtml.unescape('&#xD800;&#1114112;&#xZZ;&unknown;'),
        '&#xD800;&#1114112;&#xZZ;&unknown;',
      );
    },
  );

  group('CSV', () {
    test('round-trips commas, newlines, quotes and empty quoted fields', () {
      final csv = OfflineCsv.fromJson(
        jsonEncode([
          {'name': '中,文', 'note': 'say "hi"\nnext'},
          {'name': '', 'note': 'end'},
        ]),
      );
      expect(csv, contains('\r\n'));
      expect(jsonDecode(OfflineCsv.fromCsv(csv, inferTypes: false)), [
        {'name': '中,文', 'note': 'say "hi"\nnext'},
        {'name': '', 'note': 'end'},
      ]);
      expect(OfflineCsv.parse('""'), [
        [''],
      ]);
      expect(OfflineCsv.parse('\uFEFFa,b\r\n1,\r\n\r\n'), [
        ['a', 'b'],
        ['1', ''],
      ]);
    });

    test('inference retains identifiers and exact large integers', () {
      expect(
        jsonDecode(
          OfflineCsv.fromCsv(
            'id,large,n,b,decimal\n007,999999999999999999999999,12,true,1.5',
            inferTypes: true,
          ),
        ),
        [
          {
            'id': '007',
            'large': '999999999999999999999999',
            'n': 12,
            'b': true,
            'decimal': 1.5,
          },
        ],
      );
    });

    test(
      'duplicate headers keep all values and malformed rows report errors',
      () {
        expect(
          jsonDecode(OfflineCsv.fromCsv('a,a,\n1,2,3', inferTypes: true)),
          [
            {'a': 1, 'a_2': 2, 'column_3': 3},
          ],
        );
        for (final csv in [
          'a\n"unterminated',
          'a\n"b"oops',
          'a\nb"c',
          'a\n1,2',
        ]) {
          expect(
            () => OfflineCsv.fromCsv(csv, inferTypes: true),
            throwsFormatException,
            reason: csv,
          );
        }
      },
    );
  });

  group('URL parsing', () {
    test('preserves encoded paths, fragment, duplicate order and bare flags', () {
      final info = OfflineUrlInfo.parse(
        'https://example.com:8443/a/b%20c?tag=x&flag&tag=y&empty=#top',
      );
      expect(info.host, 'example.com');
      expect(info.parts.last.value, 'a / b c');
      expect(info.parameters.map((e) => e.key), [
        'tag',
        'flag',
        'tag',
        'empty',
      ]);
      expect(info.parameters[1].value, isNull);
      expect(info.parameters[3].value, '');
      final rebuilt = info.withParameters([
        ...info.parameters,
        const MapEntry('中 文', '+&'),
      ]);
      expect(
        rebuilt,
        'https://example.com:8443/a/b%20c?tag=x&flag&tag=y&empty=&%E4%B8%AD+%E6%96%87=%2B%26#top',
      );
    });

    test(
      'rejects invalid UTF-8 paths/queries and invalid ports before render',
      () {
        for (final source in [
          'https://example.com/%FF',
          'https://example.com/?q=%FF',
          'https://example.com:65536/',
          'example.com/path',
        ]) {
          expect(
            () => OfflineUrlInfo.parse(source),
            throwsFormatException,
            reason: source,
          );
        }
      },
    );
  });

  test(
    'line diff reports edits and compares normalized text when requested',
    () {
      final diff = OfflineDiff.of('a\nb\nc', 'a\nc\nd');
      expect(diff.removed, 1);
      expect(diff.added, 1);
      expect(diff.text, ' a\n-b\n c\n+d');
      expect(
        OfflineDiff.of(
          ' Hello  world \n\nDone',
          'hello world\ndone',
          ignoreWhitespace: true,
          ignoreCase: true,
          ignoreBlankLines: true,
        ).identical,
        isTrue,
      );
      expect(OfflineDiff.of('a\n' * 700, 'b\n' * 700).truncated, isTrue);
      expect(OfflineDiff.of('a\n' * 700, 'a\n' * 700).identical, isTrue);
    },
  );
}
