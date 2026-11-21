import 'dart:async';
import 'dart:js_interop';

extension type _Coords(JSObject _) implements JSObject {
  external double get latitude;
  external double get longitude;
}

extension type _Position(JSObject _) implements JSObject {
  external _Coords get coords;
}

extension type _Geolocation(JSObject _) implements JSObject {
  external void getCurrentPosition(
    JSFunction success, [
    JSFunction? error,
    JSObject? options,
  ]);
}

@JS('navigator.geolocation')
external _Geolocation? get _geolocation;

@JS('window.open')
external JSObject? _open(String url, String target, String features);

Future<({double latitude, double longitude})?> currentLocation() {
  final geo = _geolocation;
  if (geo == null) return Future.value(null);
  final done = Completer<({double latitude, double longitude})?>();
  geo.getCurrentPosition(
    ((_Position p) {
      if (!done.isCompleted) {
        done.complete((
          latitude: p.coords.latitude,
          longitude: p.coords.longitude,
        ));
      }
    }).toJS,
    ((JSAny? _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS,
    {'enableHighAccuracy': true, 'timeout': 10000, 'maximumAge': 60000}.jsify()
        as JSObject,
  );
  return done.future;
}

void openMapLink(Uri url) {
  _open(url.toString(), '_blank', 'noopener,noreferrer');
}
