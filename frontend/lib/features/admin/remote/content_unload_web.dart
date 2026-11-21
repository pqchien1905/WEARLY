import 'dart:js_interop';

@JS('window.addEventListener')
external void _addListener(String type, JSFunction listener);
@JS('window.removeEventListener')
external void _removeListener(String type, JSFunction listener);
extension type _BeforeUnloadEvent._(JSObject _) implements JSObject {
  external void preventDefault();
  external set returnValue(String value);
}

class ContentUnloadGuard {
  bool active = false;
  final listener = ((_BeforeUnloadEvent event) {
    event.preventDefault();
    event.returnValue = '';
  }).toJS;
  void update(bool enabled) {
    if (active == enabled) return;
    active = enabled;
    if (enabled) {
      _addListener('beforeunload', listener);
    } else {
      _removeListener('beforeunload', listener);
    }
  }

  void dispose() => update(false);
}
