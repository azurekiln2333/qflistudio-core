import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'api_client.dart';

class OnlineProgram {
  const OnlineProgram({required this.command, required this.files});

  final String command;
  final List<Map<String, String>> files;

  /// Entry extensions whose toolchain is in the cloud sandbox image.
  /// `.rb` needs sandbox toolchains version 3 or newer.
  static const Set<String> _extensions = {
    '.py',
    '.js',
    '.ts',
    '.c',
    '.cpp',
    '.java',
    '.lua',
    '.sh',
    '.go',
    '.rs',
    '.dart',
    '.php',
    '.rb',
  };

  static bool supports(String entry) =>
      _extensions.contains(p.extension(entry).toLowerCase());

  static Future<OnlineProgram> prepare(
    String projectPath,
    String entryFile,
  ) async {
    final entry = p
        .relative(entryFile, from: projectPath)
        .replaceAll('\\', '/');
    if (!p.isWithin(projectPath, entryFile) || !supports(entryFile)) {
      throw ApiException('在线镜像未提供此入口所需的运行时');
    }
    final files = <Map<String, String>>[];
    var bytes = 0;
    var visited = 0;
    const excluded = {
      'node_modules',
      'build',
      'target',
      'vendor',
      '__pycache__',
    };
    Future<void> collect(Directory directory) async {
      await for (final entity in directory.list(followLinks: false)) {
        if (++visited > 512) throw ApiException('项目目录过大，在线运行只支持小型项目');
        final name = p.basename(entity.path);
        if (name.startsWith('.') || excluded.contains(name)) continue;
        if (entity is Directory) {
          await collect(entity);
        } else if (entity is File) {
          if (files.length >= 64) throw ApiException('在线运行最多传送 64 个文件');
          final relative = p
              .relative(entity.path, from: projectPath)
              .replaceAll('\\', '/');
          final content = <int>[];
          await for (final chunk in entity.openRead()) {
            bytes += chunk.length;
            if (bytes > 256 * 1024) throw ApiException('在线运行项目副本不能超过 256 KiB');
            content.addAll(chunk);
          }
          files.add({'path': relative, 'content': base64Encode(content)});
        }
      }
    }

    await collect(Directory(projectPath));
    if (!files.any((file) => file['path'] == entry)) {
      throw ApiException('在线项目副本缺少入口文件');
    }
    final paths = files.map((file) => file['path']).toSet();
    final command = _command(entry, paths);
    final stdin = paths.contains('input.txt') ? ' < input.txt' : '';
    return OnlineProgram(command: '$command$stdin', files: files);
  }

  /// Shell command run from the snapshot root. The sandbox has no network, so
  /// module-aware builds must never try to fetch toolchains or dependencies.
  static String _command(String entry, Set<String?> paths) {
    final quoted = _quote('./$entry');
    return switch (p.extension(entry).toLowerCase()) {
      '.py' => 'python3 -u $quoted',
      '.js' => 'node $quoted',
      // Node 24 strips types natively; transform mode also covers enum/namespace.
      '.ts' =>
        'node --experimental-transform-types --disable-warning=ExperimentalWarning $quoted',
      '.lua' => 'lua5.4 $quoted',
      '.java' =>
        'java -XX:ActiveProcessorCount=1 -XX:ReservedCodeCacheSize=32m -XX:CompressedClassSpaceSize=32m -Xmx96m $quoted',
      '.c' => 'gcc $quoted -o .qfli-program && ./.qfli-program',
      '.cpp' => 'g++ $quoted -o .qfli-program && ./.qfli-program',
      '.sh' => 'bash $quoted',
      '.go' =>
        paths.contains('go.mod')
            ? 'GOTOOLCHAIN=local GOPROXY=off go build -o .qfli-program '
                  '${_quote('./${p.posix.dirname(entry)}')} && ./.qfli-program'
            : 'GOTOOLCHAIN=local GOPROXY=off go build -o .qfli-program $quoted '
                  '&& ./.qfli-program',
      '.rs' =>
        paths.contains('Cargo.toml')
            ? 'cargo run --offline --quiet'
            : 'rustc --edition 2021 $quoted -o .qfli-program && ./.qfli-program',
      '.dart' => 'dart run $quoted',
      '.php' => 'php $quoted',
      '.rb' => 'ruby $quoted',
      _ => throw ApiException('在线镜像未提供此入口所需的运行时'),
    };
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
}
