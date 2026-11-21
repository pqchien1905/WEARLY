import '../core/network/api_client.dart';

const invalidReview = ApiException(
  'INVALID_RESPONSE',
  'Chưa đọc được đánh giá. Vui lòng tải lại.',
);
T _decode<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    throw invalidReview;
  }
}

class ProductReview {
  ProductReview.fromJson(Object? value) {
    final json = value as Map;
    id = json['id'] as String;
    rating = json['rating'] as int;
    comment = json['comment'] as String;
    createdAt = DateTime.parse(json['createdAt'] as String);
    updatedAt = json['updatedAt'] as String;
    DateTime.parse(updatedAt);
    // Present only on the author's own reviews.
    hidden = json['hiddenAt'] != null;
    if (hidden) DateTime.parse(json['hiddenAt'] as String);
    hiddenReason = json['hiddenReason'] as String?;
    if (id.isEmpty ||
        rating < 1 ||
        rating > 5 ||
        comment.trim().isEmpty ||
        comment.runes.length > 2000) {
      throw invalidReview;
    }
  }
  late final String id, comment, updatedAt;
  late final String? hiddenReason;
  late final bool hidden;
  late final int rating;
  late final DateTime createdAt;
}

class ReviewPage {
  ReviewPage.fromJson(Object? value) {
    final json = value as Map;
    items = (json['items'] as List).map(ProductReview.fromJson).toList();
    total = json['total'] as int;
    page = json['page'] as int;
    limit = json['limit'] as int;
    average = (json['average'] as num?)?.toDouble();
    if (total < 0 ||
        page < 1 ||
        limit < 1 ||
        limit > 20 ||
        items.length > limit ||
        (total == 0
            ? average != null
            : average == null ||
                  !average!.isFinite ||
                  average! < 1 ||
                  average! > 5)) {
      throw invalidReview;
    }
  }
  late final List<ProductReview> items;
  late final int total, page, limit;
  late final double? average;
  bool get hasNext => page * limit < total;
}

class MyReview {
  MyReview.fromJson(Object? value) {
    final json = value as Map;
    canReview = json['canReview'] as bool;
    review = json['review'] == null
        ? null
        : ProductReview.fromJson(json['review']);
  }
  late final bool canReview;
  late final ProductReview? review;
}

typedef ReviewedProduct = ({String name, String slug, String? image});

class OwnedReview extends ProductReview {
  OwnedReview.fromJson(Object? value) : super.fromJson(value) {
    final json = value as Map;
    productId = json['productId'] as String;
    canEdit = json['canEdit'] as bool;
    final detail = json['product'] as Map?;
    product = detail == null
        ? null
        : (
            name: detail['name'] as String,
            slug: detail['slug'] as String,
            image: detail['image'] as String?,
          );
    if (productId.isEmpty ||
        (canEdit && product == null) ||
        (product != null && (product!.name.isEmpty || product!.slug.isEmpty))) {
      throw invalidReview;
    }
  }
  late final String productId;
  late final bool canEdit;
  late final ReviewedProduct? product;
}

class OwnedReviewPage {
  OwnedReviewPage.fromJson(Object? value) {
    final json = value as Map;
    items = (json['items'] as List).map(OwnedReview.fromJson).toList();
    total = json['total'] as int;
    page = json['page'] as int;
    limit = json['limit'] as int;
    if (total < items.length ||
        page < 1 ||
        limit < 1 ||
        limit > 20 ||
        items.length > limit) {
      throw invalidReview;
    }
  }
  late final List<OwnedReview> items;
  late final int total, page, limit;
  bool get hasNext => page * limit < total;
}

String _path(String id) => 'products/${Uri.encodeComponent(id)}/reviews';

class PublicReviewRepository {
  PublicReviewRepository(this.api);
  final ApiClient api;
  Future<ReviewPage> list(String id, int page) async {
    final result = await api.request(
      'GET',
      _path(id),
      authenticated: false,
      query: {'page': '$page', 'limit': '5'},
    );
    return _decode(() => ReviewPage.fromJson(result));
  }
}

class OwnerReviewRepository {
  OwnerReviewRepository(this.api, {required this.onSettled})
    : generation = api.tokens.generation;
  final ApiClient api;
  final int generation;
  final void Function(String productId) onSettled;
  bool _disposed = false;
  void dispose() => _disposed = true;
  void _check() {
    if (_disposed || generation != api.tokens.generation) throw sessionChanged;
  }

  Future<MyReview> mine(String id) async {
    _check();
    final result = await api.get('${_path(id)}/me');
    _check();
    return _decode(() => MyReview.fromJson(result));
  }

  Future<OwnedReviewPage> history(
    int page, {
    String query = '',
    int? rating,
  }) async {
    _check();
    final result = await api.get(
      'users/me/reviews',
      query: {
        'page': '$page',
        'limit': '5',
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (rating != null) 'rating': '$rating',
      },
    );
    _check();
    return _decode(() => OwnedReviewPage.fromJson(result));
  }

  Future<Object?> _write(
    String method,
    String id,
    Map<String, Object?> body,
  ) async {
    _check();
    try {
      final value = await api.request(
        method,
        '${_path(id)}${method == 'POST' ? '' : '/me'}',
        body: body,
        onLateCompletion: () => onSettled(id),
      );
      _check();
      return value;
    } finally {
      onSettled(id);
    }
  }

  Future<ProductReview> save(
    String id, {
    required int rating,
    required String comment,
    ProductReview? previous,
  }) async {
    final value = await _write(previous == null ? 'POST' : 'PATCH', id, {
      'rating': rating,
      'comment': comment.trim(),
      if (previous != null) 'expectedUpdatedAt': previous.updatedAt,
    });
    return _decode(() => ProductReview.fromJson(value));
  }

  Future<void> remove(String id, ProductReview previous) async {
    await _write('DELETE', id, {'expectedUpdatedAt': previous.updatedAt});
  }
}
