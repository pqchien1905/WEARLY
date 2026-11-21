class ProductVariant {
  const ProductVariant({
    required this.sku,
    required this.size,
    required this.color,
    required this.colorHex,
    required this.price,
    required this.stock,
    this.originalPrice,
    this.promotionName,
  });
  final String sku, size, color;
  final int colorHex, price, stock;
  final int? originalPrice;
  final String? promotionName;
  bool get discounted => originalPrice != null && originalPrice! > price;
  ProductVariant copyWith({int? price, int? stock}) => ProductVariant(
    sku: sku,
    size: size,
    color: color,
    colorHex: colorHex,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    originalPrice: originalPrice,
    promotionName: promotionName,
  );
}

class ProductMedia {
  const ProductMedia({required this.path, required this.label, this.color});
  final String path, label;
  final String? color;
}

class Product {
  const Product({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.image,
    required this.description,
    required this.material,
    required this.style,
    required this.variants,
    this.active = true,
    this.tryOn = true,
    this.media = const [],
  });
  final String id, slug, name, category, image, description, material, style;
  final List<ProductVariant> variants;
  final List<ProductMedia> media;
  final bool active, tryOn;
  int get price => variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  ProductVariant get cheapestVariant =>
      variants.reduce((a, b) => a.price <= b.price ? a : b);
  List<String> get colors => variants.map((v) => v.color).toSet().toList();
  Product copyWith({
    String? name,
    String? description,
    List<ProductVariant>? variants,
    bool? active,
  }) => Product(
    id: id,
    slug: slug,
    name: name ?? this.name,
    category: category,
    image: image,
    description: description ?? this.description,
    material: material,
    style: style,
    variants: variants ?? this.variants,
    active: active ?? this.active,
    tryOn: tryOn,
    media: media,
  );
}

class ProductQuery {
  const ProductQuery({
    this.search = '',
    this.category = '',
    this.brand = '',
    this.size = '',
    this.color = '',
    this.style = '',
    this.maxPrice,
    this.inStock = false,
    this.sort = 'newest',
    this.page = 1,
    this.limit = 12,
    this.includeInactive = false,
  });
  final String search, category, brand, size, color, style, sort;
  final int? maxPrice;
  final int page, limit;
  final bool inStock;
  final bool includeInactive;
  factory ProductQuery.fromParams(Map<String, String> p) => ProductQuery(
    search: p['q'] ?? '',
    category: p['category'] ?? '',
    brand: p['brand'] ?? '',
    size: p['size'] ?? '',
    color: p['color'] ?? '',
    style: p['style'] ?? '',
    maxPrice: int.tryParse(p['max'] ?? '')?.clamp(0, 9007199254740991),
    inStock: p['stock'] == 'true',
    sort: p['sort'] ?? 'newest',
    page: (int.tryParse(p['page'] ?? '') ?? 1).clamp(1, 1000),
  );
  Map<String, String> toParams() => {
    if (search.isNotEmpty) 'q': search,
    if (category.isNotEmpty) 'category': category,
    if (brand.isNotEmpty) 'brand': brand,
    if (size.isNotEmpty) 'size': size,
    if (color.isNotEmpty) 'color': color,
    if (style.isNotEmpty) 'style': style,
    if (maxPrice != null) 'max': '$maxPrice',
    if (inStock) 'stock': 'true',
    if (sort != 'newest') 'sort': sort,
    if (page != 1) 'page': '$page',
  };
}

class ProductPage {
  const ProductPage(this.items, this.total);
  final List<Product> items;
  final int total;
}

abstract interface class ProductRepository {
  Future<List<String>> availableColors();
  Future<ProductPage> list(ProductQuery query);
  Future<Product?> bySlug(String slug);
  Future<void> save(Product product);
  Future<void> delete(String id);
  Future<void> consumeStock(
    Map<String, int> quantities, {
    required Map<String, int> expectedPrices,
  });
}
