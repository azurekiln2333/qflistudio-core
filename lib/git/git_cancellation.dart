/// Cancellation belongs to the operation, not to a page's lifetime.
class GitCloneCancellation {
  bool _cancelled = false;
  bool _disposed = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  void addListener(void Function() listener) {
    if (_cancelled || _disposed) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    cancel();
    _disposed = true;
    _listeners.clear();
  }
}
