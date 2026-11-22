import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_platform_io.dart';

/// Discovery must describe an optional installation honestly; these tests drive
/// it with probes so no real file has to exist.
void main() {
  group('locateHerdrExecutable', () {
    test('prefers an explicit user path', () async {
      final path = await locateHerdrExecutable(
        explicitPath: r'D:\tools\herdr\herdr.exe',
        environment: const <String, String>{'PATH': ''},
        isExecutable: (candidate) => candidate == r'D:\tools\herdr\herdr.exe',
        isWindows: true,
        isMacOS: false,
      );
      expect(path, r'D:\tools\herdr\herdr.exe');
    });

    test(
      'a broken explicit path reports missing instead of guessing',
      () async {
        final path = await locateHerdrExecutable(
          explicitPath: r'D:\gone\herdr.exe',
          environment: const <String, String>{'PATH': ''},
          isExecutable: (_) => false,
          isWindows: true,
          isMacOS: false,
        );
        expect(path, isNull);
      },
    );

    test('honours QFLI_HERDR_PATH before PATH', () async {
      final path = await locateHerdrExecutable(
        environment: const <String, String>{
          'QFLI_HERDR_PATH': r'D:\custom\herdr.exe',
          'PATH': r'D:\bin',
        },
        isExecutable: (candidate) =>
            candidate == r'D:\custom\herdr.exe' ||
            candidate == r'D:\bin\herdr.exe',
        isWindows: true,
        isMacOS: false,
      );
      expect(path, r'D:\custom\herdr.exe');
    });

    test('falls back to PATH and handles quoted Windows entries', () async {
      final path = await locateHerdrExecutable(
        environment: const <String, String>{
          'PATH': r'"D:\Program Files\herdr";D:\other',
        },
        isExecutable: (candidate) =>
            candidate == r'D:\Program Files\herdr\herdr.exe',
        isWindows: true,
        isMacOS: false,
      );
      expect(path, r'D:\Program Files\herdr\herdr.exe');
    });

    test('finds a versioned herdr-* directory under Program Files', () async {
      final path = await locateHerdrExecutable(
        environment: const <String, String>{
          'PATH': '',
          'ProgramFiles': r'D:\ProgramFiles',
        },
        listDirectory: (directory) => directory == r'D:\ProgramFiles'
            ? <String>[
                r'D:\ProgramFiles\herdr-windows-x86_64',
                r'D:\ProgramFiles\flutter',
              ]
            : const <String>[],
        isExecutable: (candidate) =>
            candidate == r'D:\ProgramFiles\herdr-windows-x86_64\herdr.exe',
        isWindows: true,
        isMacOS: false,
      );
      expect(path, r'D:\ProgramFiles\herdr-windows-x86_64\herdr.exe');
    });

    test('uses the POSIX install directories when PATH is empty', () async {
      final path = await locateHerdrExecutable(
        environment: const <String, String>{'PATH': '', 'HOME': '/home/dev'},
        isExecutable: (candidate) => candidate == '/opt/homebrew/bin/herdr',
        isWindows: false,
        isMacOS: true,
      );
      expect(path, '/opt/homebrew/bin/herdr');
    });

    test('reports herdr as missing when nothing matches', () async {
      final path = await locateHerdrExecutable(
        environment: const <String, String>{'PATH': '', 'HOME': '/home/dev'},
        isExecutable: (_) => false,
        listDirectory: (_) => const <String>[],
        isWindows: false,
        isMacOS: false,
      );
      expect(path, isNull);
    });
  });

  group('executableOnPath', () {
    test('accepts a Windows npm shim', () {
      final available = executableOnPath(
        'claude',
        environment: const <String, String>{
          'PATH': r'C:\Users\dev\AppData\Roaming\npm',
        },
        isExecutable: (candidate) =>
            candidate == r'C:\Users\dev\AppData\Roaming\npm\claude.cmd',
        isWindows: true,
        isMacOS: false,
      );
      expect(available, isTrue);
    });

    test('rejects an agent that is not installed', () {
      final available = executableOnPath(
        'codex',
        environment: const <String, String>{'PATH': '/usr/local/bin'},
        isExecutable: (_) => false,
        listDirectory: (_) => const <String>[],
        isWindows: false,
        isMacOS: false,
      );
      expect(available, isFalse);
    });
  });
}
