import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/domain/catalog.dart';
import 'package:nep_storefront/data/mock_catalog.dart';

void main() {
  test(
    'catalog has at least thirty products and unique variant SKUs',
    () async {
      final repo = MockProductRepository(latency: Duration.zero);
      final page = await repo.list(const ProductQuery(limit: 100));
      expect(page.total, greaterThanOrEqualTo(30));
      final skus = page.items
          .expand((p) => p.variants)
          .map((v) => v.sku)
          .toList();
      expect(skus.toSet().length, skus.length);
      expect(
        page.items.every(
          (p) => p.variants.every((v) => v.price > 0 && v.stock >= 0),
        ),
        isTrue,
      );
    },
  );
  test(
    'filters and ascending sort respect category, size, stock and price',
    () async {
      final repo = MockProductRepository(latency: Duration.zero);
      final page = await repo.list(
        const ProductQuery(
          category: 'ao',
          size: 'M',
          maxPrice: 800000,
          inStock: true,
          sort: 'price-asc',
          limit: 100,
        ),
      );
      expect(page.items, isNotEmpty);
      expect(
        page.items.every(
          (p) =>
              p.category == 'ao' &&
              p.price <= 800000 &&
              p.variants.any((v) => v.size == 'M' && v.stock > 0),
        ),
        isTrue,
      );
      final prices = page.items.map((p) => p.price).toList();
      expect(prices, orderedEquals([...prices]..sort()));
    },
  );
  test('Vietnamese search and query roundtrip preserve filters', () async {
    final query = ProductQuery.fromParams({
      'q': 'áo',
      'size': 'M',
      'max': '700000',
      'page': '2',
    });
    expect(ProductQuery.fromParams(query.toParams()).search, 'áo');
    expect(ProductQuery.fromParams(query.toParams()).page, 2);
    final repo = MockProductRepository(latency: Duration.zero);
    expect((await repo.list(const ProductQuery(search: 'zzzz'))).total, 0);
    expect(
      (await repo.list(const ProductQuery(search: 'áo'))).total,
      greaterThan(0),
    );
  });
}
