import '../domain/catalog.dart';
import 'fixtures/catalog_fixture.dart';

class MockProductRepository implements ProductRepository {
  MockProductRepository({this.latency = const Duration(milliseconds: 250)})
    : products = catalogFixture();
  final Duration latency;
  final List<Product> products;
  @override
  Future<List<String>> availableColors() async {
    await wait();
    return products
        .where((p) => p.active)
        .expand((p) => p.colors)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<void> consumeStock(
    Map<String, int> quantities, {
    required Map<String, int> expectedPrices,
  }) async {
    await wait();
    final all = products
        .where((p) => p.active)
        .expand((p) => p.variants)
        .toList();
    for (final entry in quantities.entries) {
      final variant = all.where((v) => v.sku == entry.key).firstOrNull;
      if (variant == null || entry.value <= 0 || variant.stock < entry.value) {
        throw StateError(
          'Tồn kho đã thay đổi. Vui lòng kiểm tra lại giỏ hàng.',
        );
      }
      if (variant.price != expectedPrices[entry.key]) {
        throw StateError(
          'Giá đã thay đổi trong lúc đặt hàng. Hãy cập nhật lại giỏ hàng.',
        );
      }
    }
    for (var i = 0; i < products.length; i++) {
      products[i] = products[i].copyWith(
        variants: products[i].variants
            .map(
              (v) => quantities.containsKey(v.sku)
                  ? v.copyWith(stock: v.stock - quantities[v.sku]!)
                  : v,
            )
            .toList(),
      );
    }
  }

  bool offline = false;
  Future<void> wait() async {
    await Future<void>.delayed(latency);
    if (offline) {
      throw StateError(
        'Mất kết nối mô phỏng. Tắt chế độ offline trong cài đặt demo rồi thử lại.',
      );
    }
  }

  @override
  Future<ProductPage> list(ProductQuery q) async {
    await wait();
    var result = products
        .where(
          (p) =>
              (q.includeInactive || p.active) &&
              (q.search.isEmpty ||
                  '${p.name} ${p.material}'.toLowerCase().contains(
                    q.search.trim().toLowerCase(),
                  )) &&
              (q.category.isEmpty || p.category == q.category) &&
              (q.style.isEmpty || p.style == q.style) &&
              p.variants.any(
                (v) =>
                    (q.maxPrice == null || v.price <= q.maxPrice!) &&
                    (q.size.isEmpty || v.size == q.size) &&
                    (q.color.isEmpty || v.color == q.color) &&
                    (!q.inStock || v.stock > 0),
              ),
        )
        .toList();
    if (q.sort == 'price-asc') {
      result.sort((a, b) => a.price.compareTo(b.price));
    }
    if (q.sort == 'price-desc') {
      result.sort((a, b) => b.price.compareTo(a.price));
    }
    if (q.sort == 'name') result.sort((a, b) => a.name.compareTo(b.name));
    return ProductPage(
      result.skip((q.page - 1) * q.limit).take(q.limit).toList(),
      result.length,
    );
  }

  @override
  Future<Product?> bySlug(String slug) async {
    await wait();
    return products.where((p) => p.slug == slug && p.active).firstOrNull;
  }

  @override
  Future<void> save(Product product) async {
    await wait();
    if (product.name.trim().isEmpty ||
        product.variants.isEmpty ||
        product.variants.any((v) => v.price <= 0 || v.stock < 0)) {
      throw ArgumentError('Tên, giá và tồn kho không hợp lệ.');
    }
    final all = products
        .where((p) => p.id != product.id)
        .expand((p) => p.variants)
        .map((v) => v.sku)
        .toSet();
    if (product.variants.map((v) => v.sku).toSet().length !=
            product.variants.length ||
        product.variants.any((v) => all.contains(v.sku))) {
      throw ArgumentError('SKU phải duy nhất.');
    }
    final i = products.indexWhere((p) => p.id == product.id);
    if (i < 0) {
      products.insert(0, product);
    } else {
      products[i] = product;
    }
  }

  @override
  Future<void> delete(String id) async {
    await wait();
    products.removeWhere((p) => p.id == id);
  }
}
