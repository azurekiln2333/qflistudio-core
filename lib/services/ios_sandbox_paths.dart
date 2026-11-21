import 'package:path/path.dart' as p;

/// Converts paths in the two durable iOS app directories between absolute
/// paths and names relative to the app container.
class IosSandboxPaths {
  const IosSandboxPaths({required this.documents, required this.support});

  final String? documents;
  final String? support;

  static const relativePathKey = 'iosRelativePath';

  static const _documentsName = 'Documents';
  static const _supportName = 'Library/Application Support';
  static final _containerId = RegExp(
    r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Map<String, String?> get _roots => {
    _documentsName: documents,
    _supportName: support,
  };

  // iOS accepts both spellings of /var for the same location.
  static String _normalize(String path) {
    final normalized = p.posix.normalize(path);
    return normalized.startsWith('/private/var/')
        ? normalized.substring('/private'.length)
        : normalized;
  }

  String? relativePath(String path) {
    if (!p.posix.isAbsolute(path)) return null;
    final normalized = _normalize(path);
    for (final entry in _roots.entries) {
      final root = entry.value;
      if (root == null) continue;
      final base = _normalize(root);
      if (normalized == base) return entry.key;
      if (p.posix.isWithin(base, normalized)) {
        return p.posix.join(
          entry.key,
          p.posix.relative(normalized, from: base),
        );
      }
    }
    return null;
  }

  String? absolutePath(Object? saved) {
    if (saved is! String || saved.contains('\u0000')) return null;
    if (p.posix.normalize(saved) != saved || p.posix.isAbsolute(saved)) {
      return null;
    }
    for (final entry in _roots.entries) {
      final root = entry.value;
      if (root == null) continue;
      if (saved == entry.key) return root;
      if (saved.startsWith('${entry.key}/')) {
        return p.posix.join(root, saved.substring(entry.key.length + 1));
      }
    }
    return null;
  }

  String resolve(String path, {Object? relative}) {
    // An app backup restore may already have rebased the absolute path.
    final current = relativePath(path);
    if (current != null) return absolutePath(current) ?? path;
    return absolutePath(relative) ?? rebaseLegacyPath(path);
  }

  /// Recognize only the same container layout with a different UUID. Paths in
  /// another volume or outside the app's durable directories pass through.
  String rebaseLegacyPath(String path) {
    if (!p.posix.isAbsolute(path) || path.contains('\u0000')) return path;
    final normalized = _normalize(path);
    for (final entry in _roots.entries) {
      final root = entry.value;
      if (root == null) continue;
      final suffix = '/${entry.key}';
      final current = _normalize(root);
      if (!current.endsWith(suffix)) continue;
      final home = current.substring(0, current.length - suffix.length);
      if (!_containerId.hasMatch(p.posix.basename(home))) continue;
      final parent = p.posix.dirname(home);
      if (p.posix.basename(parent) != 'Application' ||
          p.posix.basename(p.posix.dirname(parent)) != 'Data' ||
          !p.posix.isWithin(parent, normalized)) {
        continue;
      }
      final relative = p.posix.relative(normalized, from: parent);
      final split = relative.indexOf('/');
      if (split < 0 || !_containerId.hasMatch(relative.substring(0, split))) {
        continue;
      }
      final withinHome = relative.substring(split + 1);
      if (withinHome == entry.key) return root;
      if (withinHome.startsWith('${entry.key}/')) {
        return p.posix.join(root, withinHome.substring(entry.key.length + 1));
      }
    }
    return path;
  }
}
