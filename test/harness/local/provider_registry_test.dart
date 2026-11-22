/// 每个用例都限时：卡住时要尽快报错。
@Timeout(Duration(seconds: 20))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/local/executable_locator.dart';
import 'package:qfli_studio_core/harness/local/provider_registry.dart';

/// 只认识给定路径的解析器。
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

ProviderRegistry registryFor({
  Set<String> existing = const <String>{},
  String? config,
  Map<String, String> environment = const <String, String>{'HOME': '/home/dev'},
  bool isWindows = false,
  bool isMacOS = true,
}) {
  return ProviderRegistry(
    locator: locatorFor(
      existing,
      environment: environment,
      isWindows: isWindows,
      isMacOS: isMacOS,
    ),
    configPathResolver: () async => null,
    configReader: (String path) async => config,
    configPath: config == null ? null : '/home/dev/qfli_harness_providers.json',
  );
}

void main() {
  group('内置提供方', () {
    test('八个内置项按声明顺序出现', () async {
      final registry = registryFor();
      await registry.load();

      expect(
        registry.resolved.map((ResolvedHarnessProvider p) => p.spec.id),
        <String>[
          'claude',
          'codex',
          'pi',
          'opencode',
          'gemini',
          'zcode',
          'dsh',
          'shell',
        ],
      );
    });

    test('未安装的提供方 available 为 false 且没有路径', () async {
      final registry = registryFor();
      await registry.load();

      final claude = registry.byId('claude')!;
      expect(claude.available, isFalse);
      expect(claude.executable, isNull);
      expect(claude.launchSpec.executable, 'claude');
    });

    test('安装后返回绝对路径与 builtIn 标记', () async {
      final registry = registryFor(
        existing: <String>{'/usr/local/bin/claude', '/usr/local/bin/pi'},
      );
      await registry.load();

      expect(registry.launchSpec('claude'), isNotNull);
      expect(
        registry.launchSpec('claude')!.executable,
        '/usr/local/bin/claude',
      );
      final info = registry.infos.firstWhere(
        (HarnessProviderInfo item) => item.id == 'claude',
      );
      expect(info.available, isTrue);
      expect(info.builtIn, isTrue);
      expect(info.label, 'Claude Code');
    });

    test('日志目录展开 ~', () async {
      final registry = registryFor();
      await registry.load();

      expect(registry.logDirectory('claude'), '/home/dev/.claude/projects');
      expect(registry.logDirectory('shell'), isNull);
    });

    test('没有日志配置的提供方不提供 transcript', () async {
      final registry = registryFor();
      await registry.load();

      expect(registry.byId('opencode')!.spec.hasTranscript, isFalse);
      expect(registry.byId('codex')!.spec.hasTranscript, isTrue);
    });
  });

  group('Windows shell', () {
    test('默认 shell 解析到 PowerShell', () async {
      final registry = registryFor(
        existing: <String>{
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        },
        environment: <String, String>{
          'PATH': r'C:\Windows\System32\WindowsPowerShell\v1.0',
          'USERPROFILE': r'C:\Users\dev',
        },
        isWindows: true,
        isMacOS: false,
      );
      await registry.load();

      expect(
        registry.byId('shell')!.executable,
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
    });

    test('没有 PowerShell 时 shell 不可用', () async {
      final registry = registryFor(
        environment: <String, String>{'USERPROFILE': r'C:\Users\dev'},
        isWindows: true,
        isMacOS: false,
      );
      await registry.load();

      expect(registry.byId('shell')!.available, isFalse);
    });
  });

  group('POSIX shell', () {
    test('优先使用 SHELL 环境变量', () async {
      final registry = registryFor(
        existing: <String>{'/usr/local/bin/fish', '/bin/zsh'},
        environment: <String, String>{
          'HOME': '/home/dev',
          'SHELL': '/usr/local/bin/fish',
        },
      );
      await registry.load();

      expect(registry.byId('shell')!.executable, '/usr/local/bin/fish');
    });

    test('SHELL 缺失时回落到 zsh', () async {
      final registry = registryFor(existing: <String>{'/bin/zsh'});
      await registry.load();

      expect(registry.byId('shell')!.executable, '/bin/zsh');
    });
  });

  group('用户配置', () {
    test('新增 provider 追加在内置项之后', () async {
      final registry = registryFor(
        config: '''
{
  "providers": [
    {"id": "aider", "label": "Aider", "executable": "aider"}
  ]
}
''',
      );
      await registry.load();

      expect(registry.resolved.last.spec.id, 'aider');
      expect(registry.resolved.last.spec.builtIn, isFalse);
      expect(registry.warnings, isEmpty);
    });

    test('同 id 覆盖内置项并保持原位置', () async {
      final registry = registryFor(
        existing: <String>{'/opt/agents/claude'},
        config: '''
{
  "providers": [
    {
      "id": "claude",
      "label": "Claude Code (自定义)",
      "executable": "/opt/agents/claude",
      "args": ["--permission-mode", "plan"]
    }
  ]
}
''',
      );
      await registry.load();

      final claude = registry.byId('claude')!;
      expect(registry.resolved.first.spec.id, 'claude');
      expect(claude.spec.label, 'Claude Code (自定义)');
      expect(claude.executable, '/opt/agents/claude');
      expect(claude.launchSpec.args, <String>['--permission-mode', 'plan']);
      expect(claude.spec.builtIn, isFalse);
    });

    test('非法 JSON 只留下诊断信息', () async {
      final registry = registryFor(config: '{"providers": [');
      await registry.load();

      expect(registry.warnings.single, contains('JSON'));
      expect(registry.resolved, hasLength(8));
    });

    test('超长配置被拒绝', () async {
      final registry = registryFor(
        config:
            '{"providers": [${' ' * (ProviderRegistry.maxConfigBytes + 1)}]}',
      );
      await registry.load();

      expect(registry.warnings.single, contains('KB'));
    });

    test('缺省配置文件时静默使用内置项', () async {
      final registry = ProviderRegistry(
        locator: locatorFor(<String>{}),
        configPathResolver: () async => null,
      );
      await registry.load();

      expect(registry.warnings, isEmpty);
      expect(registry.resolved, hasLength(8));
    });

    test('同 id 的 enabled:false 覆盖项禁用内置 provider', () async {
      final registry = registryFor(
        config: '''
{"providers": [{"id": "claude", "executable": "claude", "enabled": false}]}
''',
      );
      await registry.load();

      expect(registry.byId('claude'), isNull);
      expect(registry.resolved, hasLength(7));
    });

    test('用户给 shell 指定的可执行文件优先', () async {
      final registry = registryFor(
        existing: <String>{'/opt/custom/sh'},
        config: '''
{"providers": [{"id": "shell", "executable": "/opt/custom/sh"}]}
''',
      );
      await registry.load();

      expect(registry.byId('shell')?.executable, '/opt/custom/sh');
    });

    test('需要终端的 provider 在管道后端下标记不可用', () async {
      final registry = registryFor(
        existing: <String>{'/usr/local/bin/claude', '/bin/sh'},
      );
      await registry.load();

      final withTerminal = registry.infosFor(allocatesTerminal: true);
      final pipeOnly = registry.infosFor(allocatesTerminal: false);

      expect(
        withTerminal
            .firstWhere((HarnessProviderInfo p) => p.id == 'claude')
            .available,
        isTrue,
      );
      expect(
        pipeOnly
            .firstWhere((HarnessProviderInfo p) => p.id == 'claude')
            .available,
        isFalse,
        reason: 'TUI 在管道下跑不起来，不能给用户一个必定卡住的入口',
      );
      expect(
        pipeOnly
            .firstWhere((HarnessProviderInfo p) => p.id == 'shell')
            .available,
        isTrue,
        reason: 'shell 不需要 TUI',
      );
    });

    test('reload 丢弃上一轮结果', () async {
      var config = '''
{"providers": [{"id": "aider", "executable": "aider"}]}
''';
      final registry = ProviderRegistry(
        locator: locatorFor(<String>{'/usr/bin/aider'}),
        configPathResolver: () async => '/home/dev/qfli_harness_providers.json',
        configReader: (String path) async => config,
      );
      await registry.load();
      expect(registry.byId('aider'), isNotNull);

      config = '{"providers": []}';
      await registry.reload();

      expect(registry.byId('aider'), isNull);
      expect(registry.resolved, hasLength(8));
    });
  });
}
