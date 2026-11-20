import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads only HEAD metadata, without starting Git or loading native libraries.
Future<String?> readProjectGitBranch(String projectRoot) async {
  if (projectRoot.trim().isEmpty) return null;
  try {
    var gitDirectory = p.join(projectRoot, '.git');
    final type = await FileSystemEntity.type(gitDirectory);
    if (type == FileSystemEntityType.file) {
      final pointer = (await File(gitDirectory).readAsString()).trim();
      if (!pointer.startsWith('gitdir:')) return null;
      final target = pointer.substring('gitdir:'.length).trim();
      if (target.isEmpty || RegExp(r'[\r\n\x00]').hasMatch(target)) {
        return null;
      }
      gitDirectory = p.normalize(
        p.isAbsolute(target) ? target : p.join(projectRoot, target),
      );
    } else if (type != FileSystemEntityType.directory) {
      return null;
    }

    final head = (await File(
      p.join(gitDirectory, 'HEAD'),
    ).readAsString()).trim();
    const prefix = 'ref: refs/heads/';
    if (head.startsWith(prefix)) {
      final branch = head.substring(prefix.length);
      if (branch.isEmpty ||
          RegExp(r'[\x00-\x20\x7f~^:?*\[\\]').hasMatch(branch) ||
          branch.contains('..') ||
          branch.contains('@{') ||
          branch.endsWith('.') ||
          branch
              .split('/')
              .any(
                (part) =>
                    part.isEmpty ||
                    part.startsWith('.') ||
                    part.endsWith('.lock'),
              )) {
        return null;
      }
      return branch;
    }
    if (RegExp(r'^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$').hasMatch(head)) {
      return '分离 HEAD · ${head.substring(0, 7)}';
    }
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  return null;
}
