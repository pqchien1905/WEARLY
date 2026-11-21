import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/api_providers.dart';
import '../core/network/api_client.dart';

/// One address the shopper can pick: from type-ahead or from a dropped pin.
class GeoPlace {
  const GeoPlace({
    required this.title,
    required this.subtitle,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
  final String title, subtitle, address;
  final double latitude, longitude;

  static GeoPlace? fromJson(Object? data) {
    if (data is! Map) return null;
    final lat = data['latitude'], lng = data['longitude'];
    final address = data['address'];
    if (lat is! num || lng is! num || address is! String || address.isEmpty) {
      return null;
    }
    return GeoPlace(
      title: data['title'] as String? ?? address,
      subtitle: data['subtitle'] as String? ?? '',
      address: address,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
  }
}

/// Address search through the shop API (which talks to the map provider).
class GeoRepository {
  GeoRepository(this.api);
  final ApiClient api;

  Future<List<GeoPlace>> suggest(
    String query, {
    double? nearLat,
    double? nearLng,
  }) async {
    final data = await api.request(
      'GET',
      'geo/suggest',
      query: {
        'q': query.trim(),
        if (nearLat != null && nearLng != null) ...{
          'lat': nearLat.toStringAsFixed(5),
          'lng': nearLng.toStringAsFixed(5),
        },
      },
    );
    return [
      if (data is List)
        for (final row in data) ?GeoPlace.fromJson(row),
    ];
  }

  Future<GeoPlace?> reverse(double lat, double lng) async {
    final data = await api.request(
      'GET',
      'geo/reverse',
      query: {'lat': lat.toStringAsFixed(6), 'lng': lng.toStringAsFixed(6)},
    );
    return data is Map ? GeoPlace.fromJson(data['place']) : null;
  }
}

final geoRepositoryProvider = Provider(
  (ref) => GeoRepository(ref.watch(apiClientProvider)),
);
