import 'dart:js_interop';

@JS('window.open')
external JSAny? _open(String url, String target, String features);
void openPaymentWindow(Uri url) {
  _open(url.toString(), '_blank', 'noopener,noreferrer');
}
