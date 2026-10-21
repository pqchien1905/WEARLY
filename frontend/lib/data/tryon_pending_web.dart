import 'dart:js_interop';
import 'tryon_pending_store.dart';

@JS('window.localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}
TryOnPendingStore tryOnPendingStore(String namespace) =>
    _BrowserPending(namespace);

class _BrowserPending implements TryOnPendingStore {
  _BrowserPending(this.namespace);
  final String namespace;
  String storageKey(String owner, String kind) =>
      'wearly.tryon-pending.v1:${Uri.encodeComponent(namespace)}:${Uri.encodeComponent(owner)}:$kind';
  @override
  PendingTryOn? read(String owner, String kind) {
    try {
      final value = PendingTryOn.decode(
        _storage.getItem(storageKey(owner, kind)),
      );
      if (value != null && ((kind == 'job') != (value.imageId != null))) {
        throw recoveryUnavailable;
      }
      return value;
    } catch (_) {
      throw recoveryUnavailable;
    }
  }

  @override
  void save(String owner, String kind, PendingTryOn value) {
    try {
      _storage.setItem(storageKey(owner, kind), value.encode());
    } catch (_) {
      throw recoveryUnavailable;
    }
  }

  @override
  void clear(String owner, String kind, String key) {
    try {
      if (read(owner, kind)?.key == key) {
        _storage.removeItem(storageKey(owner, kind));
      }
    } catch (_) {
      throw recoveryUnavailable;
    }
  }
}
