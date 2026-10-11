import 'dart:io';

import 'package:path/path.dart' as p;

import 'studio_profile.dart';

/// A preview session that can resolve one project file into a browser URL.
///
/// Normal preview only needs [WebPreviewSession]. Long press runs the active
/// file, so the editor then requires this capability; a session without it
/// reports an error instead of opening the default page.
abstract interface class WebFilePreviewSession implements WebPreviewSession {
  /// Absolute URL serving [absolutePath] through this session.
  ///
  /// Throws [FileSystemException] when the file does not exist, is not
  /// accessible, or lies outside the document root. There is no default-page
  /// fallback: a failed resolution stays visible to the caller.
  String urlForFile(String absolutePath);
}

/// Resolves [filePath] to a browser URL under [baseUrl] / [documentRoot].
///
/// Shared by product sessions so an HTML entry maps to the exact URL the server
/// serves. Checks are strict so the result is never a URL the server rejects:
///
/// - [documentRoot] must exist and [filePath] must be an existing regular file;
/// - both are canonicalized and the file must stay inside the canonical root,
///   rejecting `..` and symlink escapes;
/// - hidden path segments (except `.well-known`), backslashes and NUL are
///   rejected because the servers refuse them;
/// - the URL is built from `Uri.parse(baseUrl)` with root-relative
///   [Uri.pathSegments], letting [Uri] encode each segment once.
///
/// Throws [FileSystemException] with a short message; never returns the default
/// page URL.
String webPreviewUrlForFile({
  required String baseUrl,
  required String documentRoot,
  required String filePath,
}) {
  final root = Directory(documentRoot);
  if (!root.existsSync()) {
    throw FileSystemException('preview root does not exist', documentRoot);
  }
  final canonicalRoot = root.resolveSymbolicLinksSync();
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('file does not exist', filePath);
  }
  final String canonicalFile;
  try {
    canonicalFile = file.resolveSymbolicLinksSync();
  } on FileSystemException {
    throw FileSystemException('file does not exist', filePath);
  }
  if (canonicalFile == canonicalRoot ||
      !p.isWithin(canonicalRoot, canonicalFile)) {
    throw FileSystemException('file is outside the preview root', filePath);
  }
  final stat = File(canonicalFile).statSync();
  if (stat.type != FileSystemEntityType.file) {
    throw FileSystemException('file does not exist', filePath);
  }
  final rawSegments = p
      .split(p.relative(canonicalFile, from: canonicalRoot))
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList();
  if (rawSegments.isEmpty ||
      rawSegments.any(
        (segment) =>
            segment.contains('\\') ||
            segment.contains('\x00') ||
            (segment.startsWith('.') && segment != '.well-known'),
      )) {
    throw FileSystemException('file is outside the preview root', filePath);
  }
  return Uri.parse(baseUrl)
      .replace(pathSegments: ['', ...rawSegments])
      .toString();
}
