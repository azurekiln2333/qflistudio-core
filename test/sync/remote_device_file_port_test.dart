@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';

/// 同步服务给的是相对路径；电脑要的是自己那一侧的绝对路径。
void main() {
  group('resolveDevicePath', () {
    test('拼上 POSIX 根', () {
      expect(
        resolveDevicePath('/home/me/demo', 'lib/a.dart'),
        '/home/me/demo/lib/a.dart',
      );
    });

    test('拼上 Windows 根，并用它自己的分隔符', () {
      expect(
        resolveDevicePath(r'C:\work\demo', 'lib/a.dart'),
        r'C:\work\demo\lib\a.dart',
      );
    });

    test('根末尾带分隔符时不重复', () {
      expect(
        resolveDevicePath('/home/me/demo/', 'a.dart'),
        '/home/me/demo/a.dart',
      );
      expect(
        resolveDevicePath(r'C:\work\demo\', 'a.dart'),
        r'C:\work\demo\a.dart',
      );
    });

    test('已经是绝对路径就原样传', () {
      expect(resolveDevicePath('/home/me/demo', '/home/me/x'), '/home/me/x');
      expect(resolveDevicePath(r'C:\work', r'D:\other\x'), r'D:\other\x');
    });

    test('空路径就是根本身', () {
      expect(resolveDevicePath('/home/me/demo', ''), '/home/me/demo');
    });

    test('还不知道根时原样传', () {
      expect(resolveDevicePath(null, 'lib/a.dart'), 'lib/a.dart');
      expect(resolveDevicePath('', 'lib/a.dart'), 'lib/a.dart');
    });
  });
}
