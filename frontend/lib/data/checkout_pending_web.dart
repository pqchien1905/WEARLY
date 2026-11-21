import 'dart:js_interop';
import 'checkout_pending_store.dart';

@JS('window.localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// localStorage so the guard also covers a closed and reopened tab. Storage
/// failures fall back to the in-memory guard instead of blocking checkout.
CheckoutPendingStore checkoutPendingStore(String namespace) =>
    _BrowserCheckoutPending(namespace);

class _BrowserCheckoutPending implements CheckoutPendingStore {
  _BrowserCheckoutPending(this.namespace);
  final String namespace;
  final _fallback = MemoryCheckoutPendingStore();
  String _key(String owner) =>
      'wearly.checkout-pending.v1:${Uri.encodeComponent(namespace)}:${Uri.encodeComponent(owner)}';
  @override
  String? read(String owner) {
    try {
      return _storage.getItem(_key(owner)) ?? _fallback.read(owner);
    } catch (_) {
      return _fallback.read(owner);
    }
  }

  @override
  void save(String owner, String value) {
    _fallback.save(owner, value);
    try {
      _storage.setItem(_key(owner), value);
    } catch (_) {}
  }

  @override
  void clear(String owner) {
    _fallback.clear(owner);
    try {
      _storage.removeItem(_key(owner));
    } catch (_) {}
  }
}
