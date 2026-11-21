import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_catalog.dart';
import 'package:nep_storefront/domain/catalog.dart';

void main() {
  const url = String.fromEnvironment('LIVE_API_BASE_URL');
  test(
    'loads unique photographed products through the live PostgreSQL API',
    () async {
      final client = ApiClient(baseUrl: url);
      addTearDown(client.close);
      final repo = RemoteProductRepository(client);
      final page = await repo.list(const ProductQuery(limit: 100));
      expect(page.total, greaterThan(0));
      expect(page.items.length, page.total.clamp(0, 100));
      expect(page.items.map((p) => p.id).toSet().length, page.items.length);
      expect(
        page.items.every((p) => p.media.isNotEmpty && p.variants.isNotEmpty),
        isTrue,
      );
      final product = await repo.bySlug(page.items.first.slug);
      expect(product?.id, page.items.first.id);
      expect(await repo.availableColors(), isNotEmpty);
    },
    skip: url.isEmpty
        ? 'Set LIVE_API_BASE_URL to run the read-only catalog check.'
        : false,
  );
}
