import 'dart:io';

import 'package:path/path.dart' as p;

import 'command_parser.dart';
import 'shell_backend.dart';

/// Portable, real-filesystem command set shared by every backend that has
/// `dart:io` available.
///
/// These commands never spawn a process, so they keep working on mobile
/// sandboxes where exec is forbidden. They only ever touch the real files the
/// user can actually access through [cwd]; there is no seeded virtual
/// filesystem. External or compound commands are never handled here.
///
/// The class is intentionally dependency-light: it emits through the
/// [ShellSink] callbacks so it can be unit-tested without a backend and without
/// a widget tree.
class PortableFilesystem {
  PortableFilesystem({
    required this.cwd,
    required this.homeDirectory,
    required this.sink,
    this.resolveOverride,
  });

  /// Current session directory, resolved by the owning backend.
  final String cwd;

  /// Directory `~` expands to, or null when there is no sensible home.
  final String? homeDirectory;

  /// Output sink supplied by the backing [BaseShellBackend].
  final ShellSink sink;

  /// Optional host path resolver (e.g. the sandbox escape-checked resolver).
  /// When supplied, it takes precedence over the default [resolve] logic.
  final String Function(String target)? resolveOverride;

  /// Commands this helper can fully handle. Used by the classifier so a
  /// near-miss (an unsupported flag) still routes here and reports an error
  /// instead of falling through to a shell that would silently mis-run it.
  static const Set<String> commandNames = {
    'ls',
    'dir',
    'pwd',
    'cat',
    'echo',
    'mkdir',
    'touch',
    'rm',
  };

  static bool handles(String name) => commandNames.contains(name);

  /// Runs a tokenized portable command. Returns true when [command] was one of
  /// the portable names (even if it failed) so the caller must not fall back to
  /// a shell.
  bool run(CommandToken name, List<CommandToken> args) {
    switch (name.text) {
      case 'ls':
      case 'dir':
        return _ls(args);
      case 'pwd':
        return _pwd(args);
      case 'cat':
        return _cat(args);
      case 'echo':
        return _echo(args);
      case 'mkdir':
        return _mkdir(args);
      case 'touch':
        return _touch(args);
      case 'rm':
        return _rm(args);
      default:
        return false;
    }
  }

  // ------------------------------------------------------------------- helpers

  /// Resolves [target] against [cwd], expanding a *leading* unquoted `~`.
  ///
  /// The operand text is preserved exactly; it is never trimmed and an empty
  /// operand never silently becomes the home directory. Explicit empty paths
  /// are the caller's responsibility to reject before calling.
  ///
  /// Set [expandTilde] to false when the operand was quoted, so a literal
  /// filename `~` is treated as a name rather than the home directory.
  String resolve(String target, {bool expandTilde = true}) {
    final override = resolveOverride;
    if (override != null) return override(target);
    final path = target;
    final home = homeDirectory;
    if (expandTilde &&
        home != null &&
        home.isNotEmpty &&
        (path == '~' || path.startsWith('~/') || path.startsWith(r'~\'))) {
      final expanded = path.length == 1 ? home : '$home${path.substring(1)}';
      return p.normalize(
        p.isAbsolute(expanded) ? expanded : p.join(cwd, expanded),
      );
    }
    if (p.isAbsolute(path)) return p.normalize(path);
    return p.normalize(p.join(cwd, path));
  }

  /// Rejects an explicit empty or whitespace-only filesystem operand so it can
  /// never resolve to the current or home directory.
  String _requirePath(CommandToken token, String command) {
    if (token.text.trim().isEmpty) {
      _fail('$command: empty path operand');
    }
    return token.text;
  }

  /// Applies `~` expansion but does not force the result under [cwd]; used for
  /// error messages that should echo what the user typed.
  Never _fail(String message) {
    sink.error(message);
    throw const CommandFailure();
  }

  static bool _isDashDash(CommandToken token) => token.text == '--';

  // ------------------------------------------------------------------ commands

  bool _ls(List<CommandToken> args) {
    var showAll = false;
    var long = false;
    final operands = <CommandToken>[];

    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && _isDashDash(arg)) {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        // Accept combined short flags (`-la`). Reject anything else honestly.
        final flags = arg.text.substring(1);
        for (final flag in flags.split('')) {
          switch (flag) {
            case 'a':
              showAll = true;
            case 'l':
              long = true;
            default:
              _fail('ls: unsupported option: -$flag');
          }
        }
        continue;
      }
      operands.add(arg);
    }

    final directories = <String>[];
    final files = <String>[];
    if (operands.isEmpty) {
      directories.add(cwd);
    } else {
      for (final operand in operands) {
        final resolved = resolve(
          _requirePath(operand, 'ls'),
          expandTilde: !operand.quoted,
        );
        final type = FileSystemEntity.typeSync(resolved);
        if (type == FileSystemEntityType.directory) {
          directories.add(resolved);
        } else if (type == FileSystemEntityType.notFound) {
          _fail(
            'ls: cannot access \'${operand.text}\': No such file or directory',
          );
        } else {
          files.add(resolved);
        }
      }
    }

    final multipleTargets = directories.length + files.length > 1;
    var first = true;
    for (final file in files) {
      _listFile(file, long);
      first = false;
    }
    for (final directory in directories) {
      if (multipleTargets) {
        if (!first) sink.line('');
        sink.line('$directory:');
      }
      _listDirectory(directory, showAll: showAll, long: long);
      first = false;
    }
    return true;
  }

  void _listDirectory(
    String directory, {
    required bool showAll,
    required bool long,
  }) {
    final dir = Directory(directory);
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException catch (error) {
      _fail('ls: cannot open directory \'$directory\': ${_reason(error)}');
    }
    final names = <_Entry>[];
    for (final entity in entries) {
      final base = p.basename(entity.path);
      if (!showAll && base.startsWith('.')) continue;
      names.add(_Entry(base, entity));
    }
    names.sort((a, b) => a.name.compareTo(b.name));
    if (names.isEmpty) return;
    for (final entry in names) {
      if (long) {
        sink.line(_longLine(entry.entity, entry.name));
      } else {
        sink.line(entry.name);
      }
    }
  }

  void _listFile(String path, bool long) {
    final name = p.basename(path);
    if (long) {
      sink.line(_longLine(File(path), name));
    } else {
      sink.line(name);
    }
  }

  String _longLine(FileSystemEntity entity, String name) {
    FileStat stat;
    try {
      stat = entity.statSync();
    } on FileSystemException {
      stat = FileStat.statSync(entity.path);
    }
    final type = switch (stat.type) {
      FileSystemEntityType.directory => 'd',
      FileSystemEntityType.link => 'l',
      _ => '-',
    };
    final size = stat.size.toString().padLeft(8);
    final modified = stat.modified
        .toIso8601String()
        .split('.')
        .first
        .replaceFirst('T', ' ');
    return '$type$size  $modified  $name';
  }

  bool _pwd(List<CommandToken> args) {
    final operands = <CommandToken>[];
    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && _isDashDash(arg)) {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        _fail('pwd: unsupported option: ${arg.text}');
      }
      operands.add(arg);
    }
    if (operands.isNotEmpty) {
      _fail('pwd: too many arguments');
    }
    sink.line(cwd);
    return true;
  }

  bool _cat(List<CommandToken> args) {
    final operands = <CommandToken>[];
    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && _isDashDash(arg)) {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        _fail('cat: unsupported option: ${arg.text}');
      }
      operands.add(arg);
    }
    if (operands.isEmpty) {
      _fail('cat: missing file operand');
    }
    final buffer = StringBuffer();
    for (final operand in operands) {
      final path = resolve(
        _requirePath(operand, 'cat'),
        expandTilde: !operand.quoted,
      );
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        _fail('cat: ${operand.text}: Is a directory');
      }
      if (type == FileSystemEntityType.notFound) {
        _fail('cat: ${operand.text}: No such file or directory');
      }
      try {
        buffer.write(File(path).readAsStringSync());
      } on FileSystemException catch (error) {
        _fail('cat: ${operand.text}: ${_reason(error)}');
      }
    }
    // `cat` prints file contents verbatim: emit the exact bytes and leave any
    // newline/row presentation to the consumer. Do not append a newline.
    final text = buffer.toString();
    if (text.isEmpty) return true;
    sink.raw(text);
    return true;
  }

  bool _echo(List<CommandToken> args) {
    // `echo -n` suppresses the trailing newline; any other option is echoed
    // literally, matching a shell's default `echo` without options.
    var noNewline = false;
    final parts = <String>[];
    var first = true;
    for (final arg in args) {
      if (first && arg.text == '-n') {
        noNewline = true;
        first = false;
        continue;
      }
      first = false;
      parts.add(arg.text);
    }
    final text = parts.join(' ');
    if (noNewline) {
      sink.raw(text);
    } else {
      sink.line(text);
    }
    return true;
  }

  bool _mkdir(List<CommandToken> args) {
    var parents = false;
    final operands = <CommandToken>[];
    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && _isDashDash(arg)) {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        final flags = arg.text.substring(1);
        for (final flag in flags.split('')) {
          if (flag == 'p') {
            parents = true;
          } else {
            _fail('mkdir: unsupported option: -$flag');
          }
        }
        continue;
      }
      operands.add(arg);
    }
    if (operands.isEmpty) {
      _fail('mkdir: missing operand');
    }
    for (final operand in operands) {
      final path = resolve(
        _requirePath(operand, 'mkdir'),
        expandTilde: !operand.quoted,
      );
      try {
        if (parents) {
          Directory(path).createSync(recursive: true);
        } else {
          Directory(path).createSync();
        }
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode == 17 || error.osError?.errorCode == 183) {
          _fail(
            'mkdir: cannot create directory \'${operand.text}\': File exists',
          );
        }
        _fail(
          'mkdir: cannot create directory \'${operand.text}\': ${_reason(error)}',
        );
      }
    }
    return true;
  }

  bool _touch(List<CommandToken> args) {
    final operands = <CommandToken>[];
    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && _isDashDash(arg)) {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        _fail('touch: unsupported option: ${arg.text}');
      }
      operands.add(arg);
    }
    if (operands.isEmpty) {
      _fail('touch: missing file operand');
    }
    final now = DateTime.now();
    for (final operand in operands) {
      final path = resolve(
        _requirePath(operand, 'touch'),
        expandTilde: !operand.quoted,
      );
      final file = File(path);
      try {
        if (file.existsSync()) {
          file.setLastModifiedSync(now);
        } else {
          // No `recursive: true`: `touch` must not invent missing parents.
          file.createSync();
        }
      } on FileSystemException catch (error) {
        _fail('touch: cannot touch \'${operand.text}\': ${_reason(error)}');
      }
    }
    return true;
  }

  bool _rm(List<CommandToken> args) {
    var force = false;
    var recursive = false;
    final operands = <CommandToken>[];
    var optionsDone = false;
    for (final arg in args) {
      if (!optionsDone && _isDashDash(arg)) {
        optionsDone = true;
        continue;
      }
      if (!optionsDone && arg.text.startsWith('-') && arg.text.length > 1) {
        final flags = arg.text.substring(1);
        for (final flag in flags.split('')) {
          switch (flag) {
            case 'f':
              force = true;
            case 'r':
            case 'R':
              recursive = true;
            default:
              _fail('rm: unsupported option: -$flag');
          }
        }
        continue;
      }
      operands.add(arg);
    }
    if (operands.isEmpty) {
      if (force) return true;
      _fail('rm: missing operand');
    }
    for (final operand in operands) {
      final path = resolve(
        _requirePath(operand, 'rm'),
        expandTilde: !operand.quoted,
      );
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        if (force) continue;
        _fail(
          'rm: cannot remove \'${operand.text}\': No such file or directory',
        );
      }
      try {
        if (type == FileSystemEntityType.directory) {
          if (!recursive) {
            _fail('rm: cannot remove \'${operand.text}\': Is a directory');
          }
          Directory(path).deleteSync(recursive: true);
        } else {
          File(path).deleteSync();
        }
      } on FileSystemException catch (error) {
        // `-f` only silences "not found" (handled above); real I/O failures
        // such as permission errors must still surface.
        _fail('rm: cannot remove \'${operand.text}\': ${_reason(error)}');
      }
    }
    return true;
  }

  static String _reason(FileSystemException error) {
    final os = error.osError;
    if (os != null && os.message.isNotEmpty) return os.message;
    return error.message;
  }
}

class _Entry {
  _Entry(this.name, this.entity);

  final String name;
  final FileSystemEntity entity;
}

/// Internal marker so a failed portable command returns to the caller without
/// being reported twice. The user-facing message is already emitted. Public so
/// the backend can catch exactly this and not swallow unrelated errors.
class CommandFailure implements Exception {
  const CommandFailure();
}
