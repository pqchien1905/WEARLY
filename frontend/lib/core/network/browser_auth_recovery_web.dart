import 'dart:js_interop';
import 'browser_auth_recovery_store.dart';

@JS('window.localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

BrowserAuthRecoveryStore browserAuthRecoveryStore(String key) =>
    _BrowserAuthRecoveryStore(key);

class _BrowserAuthRecoveryStore implements BrowserAuthRecoveryStore {
  _BrowserAuthRecoveryStore(this.key);
  final String key;
  @override
  String? read() => _storage.getItem(key);
  @override
  void mark(String attempt) => _storage.setItem(key, attempt);
  @override
  void clear(String attempt) {
    if (read() == attempt) _storage.removeItem(key);
  }
}
