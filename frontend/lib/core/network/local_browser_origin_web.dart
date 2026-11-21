import 'dart:js_interop';

@JS('window.location.replace')
external void _replace(String destination);

bool replaceBrowserLocation(String destination) {
  _replace(destination);
  return true;
}
