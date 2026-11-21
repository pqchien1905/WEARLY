import 'dart:js_interop';

@JS('window.open')
external _Window? _open(String url, String target);

@JS('window.location.assign')
external void _assign(String url);

extension type _Window(JSObject _) implements JSObject {
  external set opener(JSAny? value);
}

/// Opens the gateway in a new tab so the shop tab can keep watching the
/// result. The new tab is cut off from this page (`opener = null`). If the
/// browser blocks the pop-up, the gateway opens in this tab instead.
void openPaymentWindow(Uri url) {
  final tab = _open(url.toString(), '_blank');
  if (tab == null) {
    _assign(url.toString());
    return;
  }
  tab.opener = null;
}
