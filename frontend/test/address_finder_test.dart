import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_geo.dart';
import 'package:nep_storefront/features/account/address_finder.dart';
import 'remote_session_test.dart' show jsonResponse;

const place = {
  'title': 'Vincom Center Bà Triệu, 191 Phố Bà Triệu',
  'subtitle': 'Hai Bà Trưng, Hà Nội',
  'address': 'Vincom Center Bà Triệu, 191 Phố Bà Triệu, Hai Bà Trưng, Hà Nội',
  'latitude': 21.0113,
  'longitude': 105.8494,
};

void main() {
  test('reads places and ignores malformed rows', () async {
    final queries = <Map<String, String>>[];
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        queries.add(r.url.queryParameters);
        return r.url.path.endsWith('/reverse')
            ? jsonResponse({'place': place})
            : jsonResponse([
                place,
                {'address': 'thiếu toạ độ'},
              ]);
      }),
    );
    addTearDown(api.close);
    final geo = GeoRepository(api);
    final found = await geo.suggest(
      ' Vincom Bà Triệu ',
      nearLat: 21,
      nearLng: 105.8,
    );
    expect(found.single.title, place['title']);
    expect(queries.last, {
      'q': 'Vincom Bà Triệu',
      'lat': '21.00000',
      'lng': '105.80000',
    });
    expect((await geo.reverse(21.0113, 105.8494))?.address, place['address']);
  });

  testWidgets(
    'typing suggests places and picking one fills the address and pin',
    (tester) async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => jsonResponse([place])),
      );
      addTearDown(api.close);
      final address = TextEditingController();
      addTearDown(address.dispose);
      double? lat, lng;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      TextField(controller: address),
                      AddressFinder(
                        address: address,
                        latitude: lat,
                        longitude: lng,
                        onPin: (a, b) => setState(() {
                          lat = a;
                          lng = b;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Chưa ghim vị trí trên bản đồ.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Vincom Bà Triệu');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Hai Bà Trưng, Hà Nội'), findsOneWidget);
      await tester.tap(find.text(place['title']! as String));
      await tester.pump();
      expect(address.text, place['address']);
      expect((lat, lng), (21.0113, 105.8494));
      expect(find.text('Đã ghim vị trí nhận hàng.'), findsOneWidget);
      // Filling the field ourselves must not open a new round of suggestions.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Hai Bà Trưng, Hà Nội'), findsNothing);
      await tester.tap(find.text('Bỏ ghim'));
      await tester.pump();
      expect((lat, lng), (null, null));
    },
  );
}
