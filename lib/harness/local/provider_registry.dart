/// 提供方注册表：合并内置项与用户配置，并解析可执行文件。
///
/// 用户配置文件是应用目录下的 `qfli_harness_providers.json`。同 id 的
/// 用户项覆盖内置项，因此用户可以改启动参数或指向自定义安装路径。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/app_paths.dart';
import '../harness_host.dart';
import 'executable_locator.dart';
import 'harness_provider.dart';

/// 解析用户配置文件路径。默认取应用支持目录。
typedef UserConfigPathResolver = Future<String?> Function();

/// 读取配置文件内容。默认读磁盘；测试可注入。
typedef UserConfigReader = Future<String?> Function(String path);

/// 提供方注册表。
///
/// [load] 之前 [resolved] 为空，界面应先等待加载完成。
class ProviderRegistry {
  ProviderRegistry({
    ExecutableLocator? locator,
    UserConfigPathResolver? configPathResolver,
    UserConfigReader? configReader,
    String? configPath,
    this.configFileName = configFileNameDefault,
  }) : locator = locator ?? ExecutableLocator(),
       _configPathResolver = configPathResolver,
       _configReader = configReader ?? _readFile,
       _configPathOverride = configPath;

  /// 用户配置文件名，放在应用支持目录下。
  static const String configFileNameDefault = 'qfli_harness_providers.json';

  /// 配置文件里允许的最大字节数。
  static const int maxConfigBytes = 64 * 1024;

  final ExecutableLocator locator;
  final String configFileName;
  final UserConfigPathResolver? _configPathResolver;
  final UserConfigReader _configReader;
  final String? _configPathOverride;

  final List<String> _warnings = <String>[];
  List<ResolvedHarnessProvider> _resolved = const <ResolvedHarnessProvider>[];
  bool _loaded = false;

  /// 加载期的诊断信息，供设置页显示。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  bool get isLoaded => _loaded;

  /// 已解析的提供方，顺序与界面一致：内置在前，用户项按配置顺序。
  List<ResolvedHarnessProvider> get resolved =>
      List<ResolvedHarnessProvider>.unmodifiable(_resolved);

  /// 以契约类型暴露给界面。
  List<HarnessProviderInfo> get infos => infosFor(allocatesTerminal: true);

  /// 以契约类型暴露给界面，并按后端能力过滤。
  ///
  /// 需要真实终端的 harness（Claude、Codex、Pi 的全屏 TUI）在管道后端下
  /// 标记为不可用，而不是让用户启动一个必定卡住的会话。
  List<HarnessProviderInfo> infosFor({required bool allocatesTerminal}) =>
      <HarnessProviderInfo>[
        for (final provider in _resolved)
          HarnessProviderInfo(
            id: provider.spec.id,
            label: provider.spec.label,
            available:
                provider.available &&
                (!provider.spec.requiresTerminal || allocatesTerminal),
            executable: provider.executable,
            builtIn: provider.spec.builtIn,
          ),
      ];

  ResolvedHarnessProvider? byId(String id) {
    for (final provider in _resolved) {
      if (provider.spec.id == id) return provider;
    }
    return null;
  }

  /// 已安装提供方的启动描述；未安装返回 null。
  HarnessProviderSpec? launchSpec(String id) => byId(id)?.launchSpec;

  /// 提供方日志目录的绝对路径；没有日志或未配置时返回 null。
  String? logDirectory(String id) {
    final spec = byId(id)?.spec;
    final directory = spec?.logDirectory;
    if (directory == null) return null;
    return locator.expandHome(directory);
  }

  /// 读取配置并重新解析。重复调用会丢弃上一轮结果。
  Future<void> load() async {
    _warnings.clear();
    final merged = <String, HarnessProviderSpec>{
      for (final spec in kBuiltInHarnessProviders) spec.id: spec,
    };
    final order = <String>[
      for (final spec in kBuiltInHarnessProviders) spec.id,
    ];

    final config = await _loadUserConfig();
    _warnings.addAll(config.warnings);
    for (final spec in config.providers) {
      if (merged.containsKey(spec.id)) {
        merged[spec.id] = spec;
      } else {
        merged[spec.id] = spec;
        order.add(spec.id);
      }
    }

    final resolved = <ResolvedHarnessProvider>[];
    for (final id in order) {
      final spec = merged[id]!;
      if (!spec.enabled) continue;
      final executable = id == 'shell'
          ? _resolveShell(merged)
          : locator.locate(spec);
      resolved.add(ResolvedHarnessProvider(spec: spec, executable: executable));
    }
    _resolved = List<ResolvedHarnessProvider>.unmodifiable(resolved);
    _loaded = true;
  }

  /// 强制重新读取配置文件。
  Future<void> reload() {
    _loaded = false;
    _resolved = const <ResolvedHarnessProvider>[];
    return load();
  }

  Future<HarnessProviderConfig> _loadUserConfig() async {
    final path = _configPathOverride ?? await _resolveConfigPath();
    if (path == null) return HarnessProviderConfig.empty;
    String? text;
    try {
      text = await _configReader(path);
    } on FileSystemException {
      return HarnessProviderConfig.empty;
    } on FormatException {
      _warnings.add('无法读取提供方配置：$path');
      return HarnessProviderConfig.empty;
    }
    if (text == null || text.trim().isEmpty) return HarnessProviderConfig.empty;
    if (text.length > maxConfigBytes) {
      _warnings.add('提供方配置超过 ${maxConfigBytes ~/ 1024} KB，已忽略');
      return HarnessProviderConfig.empty;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      _warnings.add('提供方配置不是合法 JSON：$path');
      return HarnessProviderConfig.empty;
    }
    return HarnessProviderConfig.parse(decoded);
  }

  Future<String?> _resolveConfigPath() async {
    final resolver = _configPathResolver;
    if (resolver != null) return resolver();
    try {
      final directory = await AppPaths.storageDirectory();
      if (directory == null) return null;
      return p.join(directory, configFileName);
    } catch (_) {
      return null;
    }
  }

  /// 平台默认 shell。
  ///
  /// 用户在配置里给 `shell` 指定 `executable` 时优先用它；解析不到再回到
  /// 平台默认值，避免一个写错的路径让终端完全不可用。
  String? _resolveShell(Map<String, HarnessProviderSpec> merged) {
    final spec = merged['shell'];
    final configured = spec?.executable.trim() ?? '';
    if (configured.isNotEmpty && spec != null) {
      final hit = locator.exists(configured)
          ? configured
          : locator.locate(spec);
      if (hit != null) return hit;
    }
    if (locator.isWindows) {
      return locator.locate(
        HarnessProviderSpec(
          id: 'shell',
          label: 'shell',
          executable: 'powershell.exe',
          detectPaths: spec?.detectPaths ?? const <String>[],
          builtIn: true,
        ),
      );
    }
    final declared = locator.environment['SHELL'];
    if (declared != null && declared.trim().isNotEmpty) {
      final hit = locator.exists(declared.trim())
          ? declared.trim()
          : locator.locate(
              HarnessProviderSpec(
                id: 'shell',
                label: 'shell',
                executable: declared.trim(),
              ),
            );
      if (hit != null) return hit;
    }
    for (final candidate in const <String>[
      '/bin/zsh',
      '/bin/bash',
      '/bin/sh',
      '/usr/bin/bash',
      '/usr/bin/sh',
    ]) {
      if (locator.exists(candidate)) return candidate;
    }
    return locator.locate(
      const HarnessProviderSpec(id: 'shell', label: 'shell', executable: 'sh'),
    );
  }

  static Future<String?> _readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }
}
