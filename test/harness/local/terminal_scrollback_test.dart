import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/local/terminal_scrollback.dart';

void main() {
  group('TerminalScrollback', () {
    test('保留写入顺序并可拼回字节', () {
      final scrollback = TerminalScrollback(maxBytes: 16);
      scrollback.add(<int>[1, 2, 3]);
      scrollback.add(<int>[4, 5]);

      expect(scrollback.byteLength, 5);
      expect(scrollback.toBytes(), <int>[1, 2, 3, 4, 5]);
    });

    test('超限时从最早的块开始丢弃', () {
      final scrollback = TerminalScrollback(maxBytes: 6);
      scrollback.add(<int>[1, 2, 3]);
      scrollback.add(<int>[4, 5, 6]);
      scrollback.add(<int>[7, 8]);

      expect(scrollback.byteLength, 5);
      expect(scrollback.toBytes(), <int>[4, 5, 6, 7, 8]);
    });

    test('单块超限时只保留尾部', () {
      final scrollback = TerminalScrollback(maxBytes: 4);
      scrollback.add(<int>[1, 2, 3, 4, 5, 6]);

      expect(scrollback.byteLength, 4);
      expect(scrollback.toBytes(), <int>[3, 4, 5, 6]);
    });

    test('sublist 视图不会改动源块', () {
      final scrollback = TerminalScrollback(maxBytes: 3);
      final source = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      scrollback.add(source);
      source[4] = 9;

      expect(scrollback.toBytes(), <int>[3, 4, 5]);
    });

    test('上限为 0 时不保留输出', () {
      final scrollback = TerminalScrollback(maxBytes: 0);
      scrollback.add(<int>[1, 2, 3]);

      expect(scrollback.isEmpty, isTrue);
      expect(scrollback.toBytes(), isEmpty);
    });

    test('clear 清空缓冲', () {
      final scrollback = TerminalScrollback(maxBytes: 8)..add(<int>[1, 2]);
      scrollback.clear();

      expect(scrollback.isEmpty, isTrue);
      expect(scrollback.chunks, isEmpty);
    });

    test('负数上限被拒绝', () {
      expect(
        () => TerminalScrollback(maxBytes: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
