/// Harness 提供方的静态描述。
///
/// 内置项覆盖常见 harness。用户在应用目录的
/// `qfli_harness_providers.json` 里追加或覆盖同 id 的项。
library;

/// 会话日志格式。读取器按此选择解析器。
enum HarnessLogFormat {
  claude('claude'),
  codex('codex'),
  pi('pi');

  const HarnessLogFormat(this.id);

  /// 配置文件里使用的字符串。
  final String id;

  /// 解析配置值；未知值返回 null。
  static HarnessLogFormat? fromId(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final format in HarnessLogFormat.values) {
      if (format.id == normalized) return format;
    }
    return null;
  }
}

/// 一个 harness 提供方。
///
/// [executable] 是可执行文件名或绝对路径。注册表先按名字在配置路径、PATH
/// 和平台安装目录里解析，启动时使用解析后的绝对路径。
class HarnessProviderSpec {
  const HarnessProviderSpec({
    required this.id,
    required this.label,
    required this.executable,
    this.args = const <String>[],
    this.environment = const <String, String>{},
    this.logDirectory,
    this.logFormat,
    this.detectPaths = const <String>[],
    this.builtIn = true,
    this.enabled = true,
    this.requiresTerminal = true,
  });

  final String id;
  final String label;
  final String executable;
  final List<String> args;
  final Map<String, String> environment;

  /// 会话日志目录，可含 `~`。null 表示没有可读日志。
  final String? logDirectory;

  /// 日志格式；与 [logDirectory] 同时存在才提供 transcript。
  final HarnessLogFormat? logFormat;

  /// 额外探测路径，在 PATH 之前尝试。
  final List<String> detectPaths;
  final bool builtIn;
  final bool enabled;

  /// 该 harness 是否需要真实终端才能工作。
  ///
  /// Claude Code、Codex、Pi 的默认界面是全屏 TUI，靠 `isTTY` 决定是否进入
  /// 交互模式；管道后端下它们会拒绝启动或退化成一次性输出。界面据此隐藏
  /// 启动入口，而不是给用户一个必定卡住的会话。
  final bool requiresTerminal;

  /// 是否提供结构化对话记录。
  bool get hasTranscript => logDirectory != null && logFormat != null;

  /// 解析一条用户配置。
  ///
  /// 非法项返回 null，并把原因写入 [warnings]。未知字段忽略，便于旧版本
  /// 读取新写法。
  static HarnessProviderSpec? fromJson(
    Object? value, {
    required bool builtIn,
    List<String>? warnings,
  }) {
    void warn(String message) => (warnings ?? <String>[]).add(message);
    if (value is! Map) {
      warn('提供方配置不是对象，已跳过');
      return null;
    }
    final rawId = value['id'];
    final id = rawId is String ? rawId.trim() : '';
    if (!_idPattern.hasMatch(id)) {
      warn('提供方 id 无效：$rawId');
      return null;
    }
    final rawExecutable = value['executable'];
    final executable = rawExecutable is String ? rawExecutable.trim() : '';
    if (executable.isEmpty) {
      warn('提供方 $id 缺少 executable，已跳过');
      return null;
    }
    final rawLabel = value['label'];
    final label = rawLabel is String && rawLabel.trim().isNotEmpty
        ? rawLabel.trim()
        : id;
    final logDirectory = _optionalString(value['logDirectory']);
    final rawFormat = value['logFormat'];
    final logFormat = HarnessLogFormat.fromId(rawFormat);
    if (logDirectory != null && logFormat == null) {
      warn('提供方 $id 的 logFormat 无法识别，按无日志处理');
    }
    return HarnessProviderSpec(
      id: id,
      label: label,
      executable: executable,
      args: _stringList(value['args'], '提供方 $id 的 args', warnings),
      environment: _stringMap(
        value['env'] ?? value['environment'],
        '提供方 $id 的 env',
        warnings,
      ),
      logDirectory: logDirectory,
      logFormat: logFormat,
      detectPaths: _stringList(
        value['detectPaths'],
        '提供方 $id 的 detectPaths',
        warnings,
      ),
      builtIn: builtIn,
      enabled: value['enabled'] != false,
      requiresTerminal: value['requiresTerminal'] != false,
    );
  }

  /// 复制一份，可替换可执行文件与启用状态。
  HarnessProviderSpec copyWith({
    String? executable,
    List<String>? args,
    bool? enabled,
    bool? requiresTerminal,
    Map<String, String>? environment,
  }) {
    return HarnessProviderSpec(
      id: id,
      label: label,
      executable: executable ?? this.executable,
      args: args ?? this.args,
      environment: environment ?? this.environment,
      logDirectory: logDirectory,
      logFormat: logFormat,
      detectPaths: detectPaths,
      builtIn: builtIn,
      enabled: enabled ?? this.enabled,
      requiresTerminal: requiresTerminal ?? this.requiresTerminal,
    );
  }

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9_.-]{0,63}$');

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _stringList(
    Object? value,
    String field,
    List<String>? warnings,
  ) {
    if (value == null) return const <String>[];
    if (value is! List) {
      warnings?.add('$field 不是数组，已忽略');
      return const <String>[];
    }
    final result = <String>[];
    for (final item in value) {
      if (item is String) result.add(item);
    }
    return List<String>.unmodifiable(result);
  }

  static Map<String, String> _stringMap(
    Object? value,
    String field,
    List<String>? warnings,
  ) {
    if (value == null) return const <String, String>{};
    if (value is! Map) {
      warnings?.add('$field 不是对象，已忽略');
      return const <String, String>{};
    }
    final result = <String, String>{};
    value.forEach((Object? key, Object? item) {
      if (key is String && item is String) result[key] = item;
    });
    return Map<String, String>.unmodifiable(result);
  }
}

/// 内置提供方，按界面展示顺序排列。
///
/// `shell` 的可执行文件在运行时按平台解析。
const List<HarnessProviderSpec> kBuiltInHarnessProviders =
    <HarnessProviderSpec>[
      HarnessProviderSpec(
        id: 'claude',
        label: 'Claude Code',
        executable: 'claude',
        logDirectory: '~/.claude/projects',
        logFormat: HarnessLogFormat.claude,
        detectPaths: <String>['~/.claude/local/claude'],
      ),
      HarnessProviderSpec(
        id: 'codex',
        label: 'Codex',
        executable: 'codex',
        logDirectory: '~/.codex/sessions',
        logFormat: HarnessLogFormat.codex,
      ),
      HarnessProviderSpec(
        id: 'pi',
        label: 'Pi',
        executable: 'pi',
        logDirectory: '~/.pi/agent/sessions',
        logFormat: HarnessLogFormat.pi,
      ),
      HarnessProviderSpec(
        id: 'opencode',
        label: 'OpenCode',
        executable: 'opencode',
      ),
      HarnessProviderSpec(
        id: 'gemini',
        label: 'Gemini CLI',
        executable: 'gemini',
      ),
      HarnessProviderSpec(id: 'zcode', label: 'ZCode', executable: 'zcode'),
      HarnessProviderSpec(id: 'dsh', label: 'dsh', executable: 'dsh'),
      HarnessProviderSpec(
        id: 'shell',
        label: '终端',
        executable: '',
        requiresTerminal: false,
      ),
    ];

/// 用户配置文件里解析出的提供方与诊断信息。
class HarnessProviderConfig {
  const HarnessProviderConfig({
    required this.providers,
    required this.warnings,
  });

  static const HarnessProviderConfig empty = HarnessProviderConfig(
    providers: <HarnessProviderSpec>[],
    warnings: <String>[],
  );

  final List<HarnessProviderSpec> providers;
  final List<String> warnings;

  /// 解析配置文件内容。
  ///
  /// 接受 `{"providers": [...]}` 与裸数组两种写法。顶层格式错误时返回空配置
  /// 并记录原因，不抛异常。
  static HarnessProviderConfig parse(Object? decoded) {
    final warnings = <String>[];
    final Object? rawProviders = decoded is Map
        ? decoded['providers']
        : decoded;
    if (rawProviders == null) {
      return HarnessProviderConfig(
        providers: const <HarnessProviderSpec>[],
        warnings: List<String>.unmodifiable(warnings),
      );
    }
    if (rawProviders is! List) {
      warnings.add('providers 不是数组，已忽略用户配置');
      return HarnessProviderConfig(
        providers: const <HarnessProviderSpec>[],
        warnings: List<String>.unmodifiable(warnings),
      );
    }
    final providers = <HarnessProviderSpec>[];
    final seen = <String>{};
    for (final item in rawProviders) {
      final spec = HarnessProviderSpec.fromJson(
        item,
        builtIn: false,
        warnings: warnings,
      );
      // `enabled: false` 的项必须保留：同 id 时它就是“禁用这个内置项”的意思。
      // 只有新增 id 的禁用项才直接丢弃。
      if (spec == null) continue;
      if (!seen.add(spec.id)) {
        warnings.add('提供方 ${spec.id} 重复，保留先出现的项');
        continue;
      }
      providers.add(spec);
    }
    return HarnessProviderConfig(
      providers: List<HarnessProviderSpec>.unmodifiable(providers),
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}
