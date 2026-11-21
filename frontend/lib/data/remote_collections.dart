import '../core/network/api_client.dart';
import '../domain/catalog.dart';
import 'remote_catalog.dart';

class StoreCollection {
  StoreCollection.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      slug = json['slug'] as String,
      title = json['title'] as String,
      description = json['description'] as String,
      style = json['style'] as String,
      productCount = json['productCount'] as int,
      image = (json['cover'] as Map?)?['url'] as String?,
      imageLabel =
          (json['cover'] as Map?)?['alt'] as String? ?? json['title'] as String;
  final String id, slug, title, description, style, imageLabel;
  final String? image;
  final int productCount;
}

class CollectionListing {
  CollectionListing.fromJson(Map<String, dynamic> json)
    : items = (json['items'] as List)
          .map((row) => StoreCollection.fromJson(row as Map<String, dynamic>))
          .toList(),
      total = json['total'] as int,
      page = json['page'] as int,
      limit = json['limit'] as int;
  final List<StoreCollection> items;
  final int total, page, limit;
}

class CollectionDetail {
  CollectionDetail.fromJson(Map<String, dynamic> json)
    : collection = StoreCollection.fromJson(
        json['collection'] as Map<String, dynamic>,
      ),
      items = (json['items'] as List)
          .map(
            (row) => RemoteProductRepository.productFromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList(),
      total = json['total'] as int,
      page = json['page'] as int,
      limit = json['limit'] as int;
  final StoreCollection collection;
  final List<Product> items;
  final int total, page, limit;
}

class CollectionsRepository {
  CollectionsRepository(this.api);
  final ApiClient api;
  Future<CollectionListing> list(String query) async {
    final parameters = Uri.splitQueryString(query);
    final data = await api.request(
      'GET',
      'collections',
      authenticated: false,
      query: {
        'page':
            '${(int.tryParse(parameters['page'] ?? '') ?? 1).clamp(1, 10000)}',
        'limit': '12',
      },
    );
    try {
      return CollectionListing.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      throw _invalid;
    }
  }

  Future<CollectionDetail?> detail(String location) async {
    final uri = Uri.parse(location);
    final parameters = uri.queryParameters;
    try {
      final data = await api.request(
        'GET',
        'collections/${Uri.encodeComponent(uri.pathSegments.last)}',
        authenticated: false,
        query: {
          'page':
              '${(int.tryParse(parameters['page'] ?? '') ?? 1).clamp(1, 10000)}',
          'limit': '12',
          'sort':
              const [
                'newest',
                'price-asc',
                'price-desc',
                'name',
              ].contains(parameters['sort'])
              ? parameters['sort']!
              : 'newest',
          if (parameters['stock'] == 'true') 'inStock': 'true',
        },
      );
      try {
        return CollectionDetail.fromJson(data as Map<String, dynamic>);
      } catch (_) {
        throw _invalid;
      }
    } on ApiException catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  static const _invalid = ApiException(
    'INVALID_RESPONSE',
    'Dữ liệu bộ sưu tập chưa hợp lệ. Hãy tải lại.',
  );
}
