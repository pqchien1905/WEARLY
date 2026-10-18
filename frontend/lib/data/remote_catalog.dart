import '../core/network/api_client.dart';
import '../domain/catalog.dart';

class RemoteProductRepository implements ProductRepository {
  RemoteProductRepository(this.api);
  final ApiClient api;

  @override
  Future<ProductPage> list(ProductQuery query) async {
    if (query.includeInactive) {
      throw UnsupportedError('Danh mục quản trị chưa được kết nối API.');
    }
    final response = await api.get(
      'products',
      query: {
        if (query.search.isNotEmpty) 'q': query.search,
        if (query.category.isNotEmpty) 'category': query.category,
        if (query.size.isNotEmpty) 'size': query.size,
        if (query.color.isNotEmpty) 'color': query.color,
        if (query.style.isNotEmpty) 'style': query.style,
        if (query.maxPrice != null) 'maxPrice': '${query.maxPrice}',
        if (query.inStock) 'inStock': 'true',
        'sort': query.sort,
        'page': '${query.page}',
        'limit': '${query.limit}',
      },
    );
    try {
      final data = response as Map<String, dynamic>;
      return ProductPage(
        (data['items'] as List)
            .map((e) => _product(e as Map<String, dynamic>))
            .toList(),
        data['total'] as int,
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw _invalid;
    }
  }

  @override
  Future<Product?> bySlug(String slug) async {
    try {
      final data = await api.get('products/${Uri.encodeComponent(slug)}');
      return _product(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    } catch (_) {
      throw _invalid;
    }
  }

  @override
  Future<List<String>> availableColors() async {
    final response = await api.get('products/facets');
    try {
      return List<String>.from((response as Map)['colors'] as List);
    } catch (_) {
      throw _invalid;
    }
  }

  static const _invalid = ApiException(
    'INVALID_RESPONSE',
    'Dữ liệu sản phẩm chưa hợp lệ. Hãy tải lại.',
  );
  static int _money(Map<String, dynamic> price) {
    final text = price['amount'].toString();
    if (price['currency'] != 'VND' || !RegExp(r'^\d+$').hasMatch(text)) {
      throw _invalid;
    }
    final amount = int.tryParse(text);
    if (amount == null || amount > 9007199254740991) throw _invalid;
    return amount;
  }

  static Product _product(Map<String, dynamic> p) {
    try {
      final media = (p['images'] as List)
          .map(
            (e) => ProductMedia(
              path: e['url'] as String,
              label: e['alt'] as String,
              color: e['color'] as String?,
            ),
          )
          .toList();
      final variants = (p['variants'] as List)
          .map(
            (v) => ProductVariant(
              sku: v['sku'] as String,
              size: v['size'] as String,
              color: v['color'] as String,
              colorHex: int.parse(
                'FF${(v['colorHex'] as String).replaceFirst('#', '')}',
                radix: 16,
              ),
              price: _money(v['price'] as Map<String, dynamic>),
              stock: v['available'] as int,
            ),
          )
          .toList();
      if (variants.isEmpty || variants.any((v) => v.stock < 0)) throw _invalid;
      return Product(
        id: p['id'] as String,
        slug: p['slug'] as String,
        name: p['name'] as String,
        category: p['categoryId'] as String,
        image: media.isEmpty ? '' : media.first.path,
        description: p['description'] as String,
        material: p['material'] as String,
        style: p['style'] as String,
        variants: variants,
        media: media,
        active: p['active'] as bool,
        tryOn: p['tryOnSupported'] as bool,
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw _invalid;
    }
  }

  @override
  Future<void> save(Product product) async => throw UnsupportedError(
    'Chỉnh sửa sản phẩm qua API chưa được bật trong giao diện.',
  );
  @override
  Future<void> delete(String id) async => throw UnsupportedError(
    'Ẩn sản phẩm qua API chưa được bật trong giao diện.',
  );
  @override
  Future<void> consumeStock(
    Map<String, int> quantities, {
    required Map<String, int> expectedPrices,
  }) async => throw UnsupportedError(
    'Chế độ catalog API chỉ hỗ trợ xem sản phẩm. Đặt hàng thật cần kết nối tài khoản và giỏ hàng API.',
  );
}
