/// The ignore table the phone uses when it compares manifests.
///
/// It repeats the computer's table on purpose: the phone must be able to say
/// "this file is old, delete it" without asking the agent again, and a table
/// fetched over the wire would let a buggy or compromised computer widen what
/// the phone deletes. Both ends record the version in the manifest, so a
/// mismatch is detected instead of silently mixing rules.
library;

/// Version of this table. Bumping it invalidates stored manifests.
const int kSyncIgnoreVersion = 1;

/// Directory names skipped at any depth.
const Set<String> kIgnoredDirectoryNames = <String>{
  // dependencies
  'node_modules',
  '.venv',
  'Pods',
  '.gradle',
  // build outputs
  'build',
  'dist',
  'out',
  'target',
  '.dart_tool',
  'DerivedData',
  '.next',
  // caches
  '__pycache__',
  '.cache',
  // logs
  'logs',
  // harness transcripts, named instead of globbing *.jsonl project wide
  'agent_sessions',
  'transcripts',
  // version control
  '.git',
};

/// File suffixes skipped at any depth.
const List<String> kIgnoredFileSuffixes = <String>['.pyc', '.log'];

/// Whether a directory entry is skipped.
bool isIgnoredDirectoryName(String name) =>
    kIgnoredDirectoryNames.contains(name);

/// Whether a file entry is skipped.
bool isIgnoredFileName(String name) =>
    kIgnoredFileSuffixes.any((suffix) => name.endsWith(suffix));

/// Whether any segment of [relative] falls under the ignore table.
///
/// Used on a local listing so a file that the table would exclude is never
/// treated as "present locally, missing remotely" and therefore deleted.
bool isIgnoredRelativePath(String relative) {
  final segments = relative.split('/');
  if (segments.isEmpty) return false;
  for (final segment in segments.take(segments.length - 1)) {
    if (isIgnoredDirectoryName(segment)) return true;
  }
  return isIgnoredFileName(segments.last);
}

/// Reject a path that could leave the project directory.
///
/// Mirrors the computer's rule so the phone never writes outside the copy
/// directory even when a manifest lies: no absolute path, no `..`, no
/// backslash, no colon and no control character.
bool isSafeRelativePath(String relative) {
  if (relative.isEmpty) return false;
  if (relative.startsWith('/')) return false;
  if (relative.contains('\\')) return false;
  if (relative.contains(':')) return false;
  for (final unit in relative.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return false;
  }
  for (final segment in relative.split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
  }
  return true;
}
