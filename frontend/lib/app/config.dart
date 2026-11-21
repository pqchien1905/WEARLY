abstract final class BrandConfig {
  static const name = 'wearly';
  static const displayName = 'Wearly';
  static const title = '$displayName — Tủ đồ đương đại';
  static const email = 'hello@wearly.example';
  static const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);
  static const useRemoteCatalog = bool.fromEnvironment('USE_REMOTE_CATALOG');
  static const useRemoteApi = bool.fromEnvironment('USE_REMOTE_API');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const shippingFee = 30000;
  static const freeShippingAt = 1500000;
  static const expressFee = 50000;

  /// Map tiles for the address picker. Stadia Maps works on localhost without
  /// a key; a deployed domain needs a free Stadia account (or another
  /// provider's template, e.g. with ?api_key=...). {r} adds @2x on retina.
  static const mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue:
        'https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png',
  );
  static const mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© Stadia Maps © OpenMapTiles © OpenStreetMap',
  );
}
