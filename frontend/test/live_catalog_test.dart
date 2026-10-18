import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_catalog.dart';
import 'package:nep_storefront/domain/catalog.dart';

void main() {
  const url = String.fromEnvironment('LIVE_API_BASE_URL');
  test('loads the seeded catalog through a live NestJS/PostgreSQL API', () async {
    final client = ApiClient(baseUrl: url);
    addTearDown(client.close);
    final repo = RemoteProductRepository(client);
    final page = await repo.list(const ProductQuery(limit: 100));
    expect(page.total, 32);
    expect(page.items.length, 32);
    final product = await repo.bySlug('nep-1');
    expect(product?.variants.length, 8);
    expect(product?.price, 490000);
    expect(await repo.availableColors(), contains('Đen'));
  }, skip: url.isEmpty ? 'Set LIVE_API_BASE_URL to run against the seeded API.' : false);
}
