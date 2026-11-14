import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/vibe_coding/project_write_leases.dart';

void main() {
  group('路径键：大小写折叠', () {
    test('折叠开启时 a.txt 与 A.TXT 是同一个租约', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      expect(
        leases
            .acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'a.txt')
            .granted,
        isTrue,
      );

      final second = leases.acquire(
        sessionId: 'b',
        sessionLabel: '会话 B',
        path: 'A.TXT',
      );

      expect(second.granted, isFalse);
      expect(second.conflict, contains('会话 A'));
      expect(leases.holderOf('a.txt'), '会话 A');
      expect(leases.isHeldByOther('b', 'A.Txt'), isTrue);
    });

    test('折叠关闭时 a.txt 与 A.TXT 是两个租约', () {
      final leases = ProjectWriteLeases(caseInsensitive: false);
      leases.acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'a.txt');

      final second = leases.acquire(
        sessionId: 'b',
        sessionLabel: '会话 B',
        path: 'A.TXT',
      );

      expect(second.granted, isTrue);
      expect(leases.heldCount, 2);
    });

    test('同一个会话重复申请：大小写不同也放行', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      leases.acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'a.txt');

      expect(
        leases
            .acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'A.TXT')
            .granted,
        isTrue,
      );
      expect(leases.heldCount, 1);
    });

    test('释放时大小写不同也能释放', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      leases.acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'a.txt');

      leases.release('a', 'A.TXT');

      expect(leases.heldCount, 0);
      expect(leases.holderOf('a.txt'), isNull);
    });
  });

  group('路径键：分隔符与 ./ 统一', () {
    test('sub\\a.txt 与 sub/a.txt 是同一个租约', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      leases.acquire(
        sessionId: 'a',
        sessionLabel: '会话 A',
        path: r'sub\a.txt',
      );

      final second = leases.acquire(
        sessionId: 'b',
        sessionLabel: '会话 B',
        path: 'sub/a.txt',
      );

      expect(second.granted, isFalse);
      expect(leases.heldCount, 1);
    });

    test('反斜杠与大小写同时不同，仍然冲突', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      leases.acquire(
        sessionId: 'a',
        sessionLabel: '会话 A',
        path: r'Sub\A.TXT',
      );

      expect(leases.isHeldByOther('b', 'sub/a.txt'), isTrue);
    });

    test('./a.txt 与 a.txt 是同一个租约', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      leases.acquire(sessionId: 'a', sessionLabel: '会话 A', path: './a.txt');

      final second = leases.acquire(
        sessionId: 'b',
        sessionLabel: '会话 B',
        path: 'a.txt',
      );

      expect(second.granted, isFalse);
      expect(leases.holderOf('a.txt'), '会话 A');
    });

    test('冲突文案带占用会话名', () {
      final leases = ProjectWriteLeases(caseInsensitive: true);
      leases.acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'a.txt');

      final second = leases.acquire(
        sessionId: 'b',
        sessionLabel: '会话 B',
        path: 'A.TXT',
      );

      expect(second.conflict, '文件正被会话「会话 A」修改，稍后再试');
    });

    test('两个会话写同一个文件：后到的被拒绝，先到的仍持有', () {
      final leases = ProjectWriteLeases(projectRoot: '', caseInsensitive: true);
      expect(
        leases
            .acquire(sessionId: 'a', sessionLabel: '会话 A', path: 'lib/a.txt')
            .granted,
        isTrue,
      );
      expect(
        leases
            .acquire(sessionId: 'b', sessionLabel: '会话 B', path: r'LIB\A.TXT')
            .granted,
        isFalse,
      );
      expect(leases.holderOf('lib/a.txt'), '会话 A');
    });
  });
}
