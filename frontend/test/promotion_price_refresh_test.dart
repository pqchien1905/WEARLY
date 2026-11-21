import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_catalog_test.dart' show productJson;

void main() {
  test(
    'returning to a product fetches its current automatic promotion price',
    () async {
      var active = true;
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((request) async {
          requests++;
          final product = productJson();
          final variant = (product['variants'] as List).first as Map;
          if (active) {
            variant['price'] = {'amount': '390000', 'currency': 'VND'};
            variant['originalPrice'] = {'amount': '490000', 'currency': 'VND'};
            variant['promotion'] = {'id': 'offer', 'name': 'Ưu đãi tự động'};
          }
          return http.Response(
            jsonEncode(product),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(api.close);
      final provider = productProvider('nep-1');
      final firstVisit = container.listen(provider, (_, _) {});
      final discounted = await container.read(provider.future);
      expect(discounted!.variants.first.price, 390000);
      expect(discounted.variants.first.promotionName, 'Ưu đãi tự động');
      firstVisit.close();
      await container.pump();
      active = false;
      final nextVisit = container.listen(provider, (_, _) {});
      final restored = await container.read(provider.future);
      expect(restored!.variants.first.price, 490000);
      expect(restored.variants.first.promotionName, isNull);
      expect(requests, 2);
      nextVisit.close();
    },
  );
}
