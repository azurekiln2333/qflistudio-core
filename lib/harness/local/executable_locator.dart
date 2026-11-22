/// 可执行文件查找。
///
/// 顺序固定：配置里的绝对路径 → 配置里的探测路径 → PATH → 平台常见安装
/// 目录。Windows 按 PATHEXT 补全扩展名，因此 `claude` 能命中 `claude.cmd`。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'harness_provider.dart';

/// 判断一个路径是否是文件。测试注入后不触碰真实磁盘。
typedef FileExistsProbe = bool Function(String path);

/// 一个 harness 的解析结果。
class ResolvedHarnessProvider {
  const ResolvedHarnessProvider({required this.spec, this.executable});

  final HarnessProviderSpec spec;

  /// 解析出的绝对路径；null 表示未安装。
  final String? executable;

  bool get available => executable != null;

  /// 启动可用项时使用绝对路径，避免每个子进程再走一次 PATH。
  HarnessProviderSpec get launchSpec =>
      executable == null ? spec : spec.copyWith(executable: executable);
}

/// 按平台规则解析 harness 可执行文件。
class ExecutableLocator {
  ExecutableLocator({
    Map<String, String>? environment,
    bool? isWindows,
    bool? isMacOS,
    FileExistsProbe? fileExists,
  }) : environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       isWindows = isWindows ?? Platform.isWindows,
       isMacOS = isMacOS ?? Platform.isMacOS,
       _fileExists = fileExists ?? _defaultFileExists;

  final Map<String, String> environment;
  final bool isWindows;
  final bool isMacOS;
  final FileExistsProbe _fileExists;

  /// 路径拼接与规范化的上下文。
  ///
  /// 跟随目标平台而不是宿主平台：测试可以在 Linux 上验证 Windows 路径。
  p.Context get pathContext => isWindows ? p.windows : p.posix;

  static bool _defaultFileExists(String path) {
    if (path.isEmpty) return false;
    return FileSystemEntity.typeSync(path, followLinks: true) ==
        FileSystemEntityType.file;
  }

  /// 用户主目录；平台未导出时返回空串。
  String get homeDirectory {
    final home = isWindows
        ? (environment['USERPROFILE'] ?? environment['HOMEDRIVE'] ?? '')
        : (environment['HOME'] ?? '');
    return home;
  }

  /// PATH 里的目录，按出现顺序去重。
  List<String> get pathDirectories => _splitPath(
    environment['PATH'] ?? '',
    isWindows ? ';' : ':',
  ).map(expandHome).where((String dir) => dir.isNotEmpty).toList();

  /// 平台常见安装目录，PATH 之后尝试。
  List<String> get commonDirectories {
    final home = homeDirectory;
    final context = pathContext;
    final List<String> raw = isWindows
        ? <String>[
            if (environment['APPDATA'] != null)
              context.join(environment['APPDATA']!, 'npm'),
            if (environment['LOCALAPPDATA'] != null)
              context.join(environment['LOCALAPPDATA']!, 'Programs'),
            if (environment['LOCALAPPDATA'] != null)
              context.join(
                environment['LOCALAPPDATA']!,
                'Microsoft',
                'WindowsApps',
              ),
            if (home.isNotEmpty) context.join(home, '.local', 'bin'),
            if (home.isNotEmpty) context.join(home, '.bun', 'bin'),
            if (home.isNotEmpty) context.join(home, '.cargo', 'bin'),
            if (environment['ProgramFiles'] != null)
              context.join(environment['ProgramFiles']!, 'nodejs'),
          ]
        : isMacOS
        ? <String>[
            '/opt/homebrew/bin',
            '/usr/local/bin',
            '/opt/local/bin',
            '/usr/bin',
            if (home.isNotEmpty) context.join(home, '.local', 'bin'),
            if (home.isNotEmpty) context.join(home, '.bun', 'bin'),
            if (home.isNotEmpty) context.join(home, '.cargo', 'bin'),
            if (home.isNotEmpty) context.join(home, '.npm-global', 'bin'),
          ]
        : <String>[
            '/usr/local/bin',
            '/usr/bin',
            '/bin',
            '/snap/bin',
            if (home.isNotEmpty) context.join(home, '.local', 'bin'),
            if (home.isNotEmpty) context.join(home, '.bun', 'bin'),
            if (home.isNotEmpty) context.join(home, '.cargo', 'bin'),
          ];
    final seen = <String>{};
    final result = <String>[];
    for (final dir in raw) {
      final normalized = context.normalize(dir);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(normalized);
    }
    return result;
  }

  /// Windows 的扩展名候选；其他平台只有空串。
  List<String> get extensions {
    if (!isWindows) return const <String>[''];
    final raw = environment['PATHEXT'];
    final declared = raw == null
        ? const <String>['.COM', '.EXE', '.BAT', '.CMD']
        : raw
              .split(';')
              .map((String value) => value.trim())
              .where((String value) => value.startsWith('.'))
              .toList();
    final normalized = <String>{
      for (final value in declared) value.toLowerCase(),
    }.toList();
    return <String>['', ...normalized];
  }

  /// 展开开头的 `~`。
  String expandHome(String path) {
    final home = homeDirectory;
    if (home.isEmpty) return path;
    if (path == '~') return home;
    if (path.startsWith('~/') || path.startsWith(r'~\')) {
      return pathContext.join(home, path.substring(2));
    }
    return path;
  }

  /// 判断一个绝对或相对路径是否存在。
  bool exists(String path) => _fileExists(expandHome(path));

  /// 解析提供方，返回可执行文件的绝对路径。
  String? locate(HarnessProviderSpec spec) {
    final name = spec.executable.trim();
    if (name.isEmpty) return null;
    if (_isPath(name)) {
      return _probePath(expandHome(name));
    }
    for (final detectPath in spec.detectPaths) {
      final hit = _probePath(expandHome(detectPath));
      if (hit != null) return hit;
    }
    for (final dir in pathDirectories) {
      final hit = _probeInDirectory(dir, name);
      if (hit != null) return hit;
    }
    for (final dir in commonDirectories) {
      final hit = _probeInDirectory(dir, name);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 在 [directory] 下按扩展名候选查找 [name]。
  String? _probeInDirectory(String directory, String name) {
    final context = pathContext;
    final lower = context.basename(name).toLowerCase();
    final hasExtension = extensions.any(
      (String extension) => extension.isNotEmpty && lower.endsWith(extension),
    );
    final candidates = hasExtension
        ? <String>[name]
        : <String>[for (final extension in extensions) '$name$extension'];
    for (final candidate in candidates) {
      final path = context.normalize(context.join(directory, candidate));
      if (_fileExists(path)) return path;
    }
    return null;
  }

  String? _probePath(String path) {
    final context = pathContext;
    final normalized = context.normalize(path);
    if (_fileExists(normalized)) return normalized;
    final hasExtension = extensions.any(
      (String extension) =>
          extension.isNotEmpty && normalized.toLowerCase().endsWith(extension),
    );
    if (hasExtension || !isWindows) return null;
    for (final extension in extensions) {
      if (extension.isEmpty) continue;
      final candidate = '$normalized$extension';
      if (_fileExists(candidate)) return context.normalize(candidate);
    }
    return null;
  }

  bool _isPath(String value) {
    if (value.startsWith('~')) return true;
    if (value.contains('/') || value.contains('\\')) return true;
    return RegExp(r'^[a-zA-Z]:').hasMatch(value);
  }

  List<String> _splitPath(String value, String separator) {
    if (value.isEmpty) return const <String>[];
    return value
        .split(separator)
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }
}
