import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/local/executable_locator.dart';
import 'package:qfli_studio_core/harness/local/harness_provider.dart';

/// 构造一个只认识给定路径的解析器。
ExecutableLocator locatorFor(
  Set<String> existing, {
  Map<String, String> environment = const <String, String>{},
  bool isWindows = false,
  bool isMacOS = false,
}) {
  return ExecutableLocator(
    environment: environment,
    isWindows: isWindows,
    isMacOS: isMacOS,
    fileExists: existing.contains,
  );
}

HarnessProviderSpec specFor(
  String executable, {
  List<String> detectPaths = const <String>[],
}) {
  return HarnessProviderSpec(
    id: 'x',
    label: 'x',
    executable: executable,
    detectPaths: detectPaths,
  );
}

void main() {
  group('PATH 解析', () {
    test('按 PATH 顺序命中第一个可执行文件', () {
      final locator = locatorFor(
        <String>{'/opt/bin/tool', '/usr/bin/tool'},
        environment: <String, String>{
          'PATH': '/usr/bin:/opt/bin',
          'HOME': '/home/dev',
        },
        isMacOS: true,
      );

      expect(locator.locate(specFor('tool')), '/usr/bin/tool');
    });

    test('跳过不存在的目录', () {
      final locator = locatorFor(
        <String>{'/usr/local/bin/tool'},
        environment: <String, String>{
          'PATH': '/missing/bin:/usr/local/bin',
          'HOME': '/home/dev',
        },
        isMacOS: true,
      );

      expect(locator.locate(specFor('tool')), '/usr/local/bin/tool');
    });

    test('PATH 为空时回落到平台安装目录', () {
      final locator = locatorFor(
        <String>{'/opt/homebrew/bin/tool'},
        environment: <String, String>{'HOME': '/home/dev'},
        isMacOS: true,
      );

      expect(locator.locate(specFor('tool')), '/opt/homebrew/bin/tool');
    });
  });

  group('Windows 扩展名', () {
    test('按 PATHEXT 顺序补全扩展名', () {
      final locator = locatorFor(
        <String>{r'C:\tools\claude.cmd', r'C:\tools\claude.exe'},
        environment: <String, String>{
          'PATH': r'C:\tools',
          'PATHEXT': '.EXE;.CMD',
          'USERPROFILE': r'C:\Users\dev',
        },
        isWindows: true,
      );

      expect(locator.locate(specFor('claude')), r'C:\tools\claude.exe');
    });

    test('只有 .cmd 时命中 .cmd', () {
      final locator = locatorFor(
        <String>{r'C:\tools\claude.cmd'},
        environment: <String, String>{
          'PATH': r'C:\tools',
          'USERPROFILE': r'C:\Users\dev',
        },
        isWindows: true,
      );

      expect(locator.locate(specFor('claude')), r'C:\tools\claude.cmd');
    });

    test('已带扩展名时不再追加', () {
      final locator = locatorFor(
        <String>{r'C:\tools\claude.cmd'},
        environment: <String, String>{
          'PATH': r'C:\tools',
          'USERPROFILE': r'C:\Users\dev',
        },
        isWindows: true,
      );

      expect(locator.locate(specFor(r'claude.cmd')), r'C:\tools\claude.cmd');
    });

    test('未安装时返回 null', () {
      final locator = locatorFor(
        <String>{},
        environment: <String, String>{
          'PATH': r'C:\tools',
          'USERPROFILE': r'C:\Users\dev',
        },
        isWindows: true,
      );

      expect(locator.locate(specFor('claude')), isNull);
    });
  });

  group('配置路径优先', () {
    test('探测路径先于 PATH', () {
      final locator = locatorFor(
        <String>{'/usr/bin/tool', '/home/dev/.tool/bin/tool'},
        environment: <String, String>{'PATH': '/usr/bin', 'HOME': '/home/dev'},
        isMacOS: true,
      );

      expect(
        locator.locate(
          specFor('tool', detectPaths: <String>['~/.tool/bin/tool']),
        ),
        '/home/dev/.tool/bin/tool',
      );
    });

    test('绝对路径直接判断存在性', () {
      final locator = locatorFor(
        <String>{'/custom/claude'},
        environment: <String, String>{'HOME': '/home/dev'},
        isMacOS: true,
      );

      expect(locator.locate(specFor('/custom/claude')), '/custom/claude');
    });

    test('绝对路径不存在时不再回落到 PATH', () {
      final locator = locatorFor(
        <String>{'/usr/bin/claude'},
        environment: <String, String>{'PATH': '/usr/bin', 'HOME': '/home/dev'},
        isMacOS: true,
      );

      expect(locator.locate(specFor('/custom/claude')), isNull);
    });

    test('~ 展开到用户目录', () {
      final locator = locatorFor(
        <String>{'/home/dev/bin/claude'},
        environment: <String, String>{'HOME': '/home/dev'},
        isMacOS: true,
      );

      expect(locator.expandHome('~/bin/claude'), '/home/dev/bin/claude');
    });
  });

  group('配置解析', () {
    test('接受 providers 对象与裸数组', () {
      final wrapped = HarnessProviderConfig.parse(<String, Object?>{
        'providers': <Object?>[
          <String, Object?>{'id': 'aider', 'executable': 'aider'},
        ],
      });
      final bare = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{'id': 'aider', 'executable': 'aider'},
      ]);

      expect(wrapped.providers, hasLength(1));
      expect(bare.providers, hasLength(1));
      expect(wrapped.providers.single.builtIn, isFalse);
    });

    test('缺 executable 的项被跳过并记录原因', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{'id': 'aider'},
      ]);

      expect(config.providers, isEmpty);
      expect(config.warnings.single, contains('executable'));
    });

    test('非法 id 被跳过', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{'id': 'Bad Id', 'executable': 'x'},
      ]);

      expect(config.providers, isEmpty);
      expect(config.warnings.single, contains('id'));
    });

    test('重复 id 保留先出现的项', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{'id': 'aider', 'executable': 'aider'},
        <String, Object?>{'id': 'aider', 'executable': 'other'},
      ]);

      expect(config.providers.single.executable, 'aider');
      expect(config.warnings.single, contains('重复'));
    });

    test('同 id 的 enabled:false 覆盖项会禁用内置项', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{
          'id': 'claude',
          'executable': 'claude',
          'enabled': false,
        },
      ]);

      // 解析阶段必须保留，否则“禁用内置项”永远做不到。
      expect(config.providers.single.enabled, isFalse);
      expect(config.warnings, isEmpty);
    });

    test('requiresTerminal 默认为 true，可显式关掉', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{'id': 'aider', 'executable': 'aider'},
        <String, Object?>{
          'id': 'tui-free',
          'executable': 'tui-free',
          'requiresTerminal': false,
        },
      ]);

      expect(config.providers.first.requiresTerminal, isTrue);
      expect(config.providers.last.requiresTerminal, isFalse);
    });

    test('未知 logFormat 降级为无日志', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{
          'id': 'aider',
          'executable': 'aider',
          'logDirectory': '~/.aider/sessions',
          'logFormat': 'aider',
        },
      ]);

      expect(config.providers.single.hasTranscript, isFalse);
      expect(config.warnings.single, contains('logFormat'));
    });

    test('args 与 env 只保留字符串项', () {
      final config = HarnessProviderConfig.parse(<Object?>[
        <String, Object?>{
          'id': 'aider',
          'executable': 'aider',
          'args': <Object?>['--yes', 7],
          'env': <String, Object?>{'A': '1', 'B': 2},
        },
      ]);

      expect(config.providers.single.args, <String>['--yes']);
      expect(config.providers.single.environment, <String, String>{'A': '1'});
    });

    test('顶层不是数组时整体忽略', () {
      final config = HarnessProviderConfig.parse(<String, Object?>{
        'providers': 'aider',
      });

      expect(config.providers, isEmpty);
      expect(config.warnings.single, contains('providers'));
    });
  });
}
