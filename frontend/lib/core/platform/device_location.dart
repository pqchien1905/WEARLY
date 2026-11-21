import 'device_location_stub.dart'
    if (dart.library.js_interop) 'device_location_web.dart'
    as platform;

/// The browser's current position, or null when unavailable or refused.
Future<({double latitude, double longitude})?> currentLocation() =>
    platform.currentLocation();

/// Opens a map link in a new browser tab (no-op outside the web).
void openMapLink(Uri url) => platform.openMapLink(url);

/// OpenStreetMap link centred on a delivery pin.
Uri pinMapLink(double latitude, double longitude) => Uri.https(
  'www.openstreetmap.org',
  '/',
  {'mlat': '$latitude', 'mlon': '$longitude'},
).replace(fragment: 'map=18/$latitude/$longitude');
