/// What this session has learned about the sibling apps, keyed by language.
///
/// Run goes straight to the sibling app instead of probing it first, so the
/// first start call is the only honest test of whether that app is installed.
/// When it answers `app_missing`, the answer is kept here: later runs and the
/// Run tooltip use Studio's own path at once, instead of opening a dialog that
/// can only fail. Nothing is persisted — installing the app is picked up by the
/// next app start, and a stale "missing" would cost the user the toolchain.
library;

/// Session memory of sibling apps already found to be missing.
class InteropSiblingMemory {
  InteropSiblingMemory._();

  /// The one memory of this process: a Studio app runs one session at a time.
  static final InteropSiblingMemory instance = InteropSiblingMemory._();

  final Set<String> _missing = <String>{};

  /// Whether [language]'s sibling app was already found not installed.
  bool isMissing(String language) => _missing.contains(_key(language));

  /// Records that [language]'s sibling app is not installed.
  void markMissing(String language) => _missing.add(_key(language));

  /// Forgets every recorded answer. Tests use it to start a clean session.
  void clear() => _missing.clear();

  static String _key(String language) => language.toLowerCase().trim();
}
