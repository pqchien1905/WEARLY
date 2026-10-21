/// A non-secret marker for a browser login whose outcome is not yet confirmed.
/// Persisted before sending credentials so reload can revoke an abandoned login.
abstract interface class BrowserAuthRecoveryStore {
  String? read();
  void mark(String attempt);
  void clear(String attempt);
}

class MemoryBrowserAuthRecoveryStore implements BrowserAuthRecoveryStore {
  String? _attempt;
  @override
  String? read() => _attempt;
  @override
  void mark(String attempt) => _attempt = attempt;
  @override
  void clear(String attempt) {
    if (_attempt == attempt) _attempt = null;
  }
}
