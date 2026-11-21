import 'dart:typed_data';
import '../core/network/api_client.dart';
import 'commerce_json.dart';

typedef AdminRecord = Map<String, dynamic>;

class AdminPage {
  AdminPage(AdminRecord json)
    : items = (json['items'] as List).map(commerceMap).toList(),
      total = json['total'] as int,
      page = json['page'] as int,
      limit = json['limit'] as int;
  final List<AdminRecord> items;
  final int total, page, limit;
  bool get hasNext => page * limit < total;
}

class AdminOrderPage extends AdminPage {
  AdminOrderPage(super.json)
    : statusCounts = Map<String, int>.from(
        json['statusCounts'] as Map? ?? const {},
      );
  final Map<String, int> statusCounts;
}

class AdminInventoryPage extends AdminPage {
  AdminInventoryPage(super.json)
    : summary = Map<String, dynamic>.from(json['summary'] as Map? ?? const {});
  final AdminRecord summary;
}

/// Private administration contracts intentionally retain disabled SKUs and
/// version numbers, unlike the public storefront catalog representation.
class AdminRepository {
  AdminRepository(this.api) : _generation = api.tokens.generation;
  final ApiClient api;
  final int _generation;
  bool _disposed = false;
  void dispose() => _disposed = true;
  void _check() {
    if (_disposed || api.tokens.generation != _generation) throw sessionChanged;
  }

  Future<AdminRecord> _call(
    String method,
    String path, {
    AdminRecord? body,
    Map<String, String>? query,
    void Function()? onLateCompletion,
  }) async {
    _check();
    final value = await api.request(
      method,
      path,
      body: body,
      query: query,
      onLateCompletion: onLateCompletion,
    );
    _check();
    return commerceMap(value);
  }

  Future<AdminPage> list(
    String kind,
    int page, {
    String query = '',
    String status = '',
  }) async => AdminPage(
    await _call(
      'GET',
      'admin/$kind',
      query: {
        'page': '$page',
        'limit': '10',
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (status.isNotEmpty) 'status': status,
      },
    ),
  );
  Future<AdminRecord> detail(String kind, String id) =>
      _call('GET', 'admin/$kind/${Uri.encodeComponent(id)}');
  Future<AdminRecord> summary() => _call('GET', 'admin/summary');
  Future<AdminPage> categories(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/categories', query: query));
  Future<AdminRecord> categorySummary() =>
      _call('GET', 'admin/categories/summary');
  Future<AdminPage> brands(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/brands', query: query));
  Future<AdminRecord> brandSummary() => _call('GET', 'admin/brands/summary');
  Future<AdminOrderPage> orders(Map<String, String> query) async =>
      AdminOrderPage(await _call('GET', 'admin/orders', query: query));
  Future<AdminPage> customers(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/users', query: query));
  Future<AdminRecord> customerSummary() => _call('GET', 'admin/users/summary');
  Future<AdminRecord> createCustomer(AdminRecord data) =>
      _call('POST', 'admin/users', body: data);
  Future<AdminRecord> resetCustomerPassword(
    String id, {
    required String password,
    required String expectedUpdatedAt,
  }) => _call(
    'POST',
    'admin/users/${Uri.encodeComponent(id)}/reset-password',
    body: {'password': password, 'expectedUpdatedAt': expectedUpdatedAt},
  );
  Future<AdminRecord> deleteCustomer(String id, String expectedUpdatedAt) =>
      _call(
        'DELETE',
        'admin/users/${Uri.encodeComponent(id)}',
        body: {'expectedUpdatedAt': expectedUpdatedAt},
      );
  Future<AdminRecord> updateCustomer(
    String id,
    AdminRecord data, {
    bool status = false,
  }) => _call(
    'PATCH',
    'admin/users/${Uri.encodeComponent(id)}${status ? '/status' : ''}',
    body: data,
  );
  Future<AdminPage> staff({
    String? email,
    int page = 1,
    int limit = 10,
  }) async => AdminPage(
    await _call(
      'GET',
      'admin/staff',
      query: {
        'page': '$page',
        'limit': '$limit',
        if (email != null && email.isNotEmpty)
          'email': email.trim().toLowerCase(),
      },
    ),
  );
  Future<AdminRecord> updateStaff(
    String id, {
    required String role,
    required bool active,
    required int version,
  }) => _call(
    'PATCH',
    'admin/staff/${Uri.encodeComponent(id)}',
    body: {'role': role, 'active': active, 'expectedVersion': version},
  );
  Future<AdminRecord> content() => _call('GET', 'admin/content');
  Future<AdminRecord> saveContent(
    AdminRecord body, {
    void Function()? onLateCompletion,
  }) => _call(
    'PUT',
    'admin/content',
    body: body,
    onLateCompletion: onLateCompletion,
  );
  Future<AdminRecord> restoreContent(
    int version, {
    void Function()? onLateCompletion,
  }) => _call(
    'POST',
    'admin/content/restore',
    body: {'expectedVersion': version},
    onLateCompletion: onLateCompletion,
  );
  Future<AdminPage> contentHistory(int page) async => AdminPage(
    await _call(
      'GET',
      'admin/content/history',
      query: {'page': '$page', 'limit': '10'},
    ),
  );
  Future<AdminRecord> publishContent(
    int version, {
    void Function()? onLateCompletion,
  }) => _call(
    'POST',
    'admin/content/publish',
    body: {'expectedVersion': version},
    onLateCompletion: onLateCompletion,
  );
  Future<AdminRecord> references() async {
    _check();
    Future<List<AdminRecord>> load(String kind) async {
      final items = <AdminRecord>[];
      for (var page = 1; ; page++) {
        final result = AdminPage(
          await _call(
            'GET',
            'admin/$kind',
            query: {'page': '$page', 'limit': '100'},
          ),
        );
        items.addAll(result.items);
        if (!result.hasNext) return items;
        if (result.items.isEmpty) {
          throw const ApiException(
            'INVALID_RESPONSE',
            'Chưa tải đủ danh mục. Hãy thử lại.',
          );
        }
      }
    }

    final values = await Future.wait([load('categories'), load('brands')]);
    _check();
    return {'categories': values[0], 'brands': values[1]};
  }

  Future<AdminRecord> saveProduct(String? id, AdminRecord body) => _call(
    id == null ? 'POST' : 'PATCH',
    id == null ? 'admin/products' : 'admin/products/${Uri.encodeComponent(id)}',
    body: body,
  );
  Future<AdminPage> products(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/products', query: query));
  Future<AdminRecord> deleteProduct(String id, String expectedUpdatedAt) =>
      _call(
        'DELETE',
        'admin/products/${Uri.encodeComponent(id)}',
        body: {'expectedUpdatedAt': expectedUpdatedAt},
      );
  Future<AdminRecord> productSummary() =>
      _call('GET', 'admin/products/summary');
  Future<AdminInventoryPage> inventory(Map<String, String> query) async =>
      AdminInventoryPage(await _call('GET', 'admin/inventory', query: query));
  Future<AdminRecord> inventorySummary() =>
      _call('GET', 'admin/inventory/summary');
  Future<AdminInventoryPage> inventoryHistory(
    String id,
    Map<String, String> query,
  ) async => AdminInventoryPage(
    await _call(
      'GET',
      'admin/inventory/${Uri.encodeComponent(id)}/movements',
      query: query,
    ),
  );
  Future<AdminRecord> initializeInventory(String variantId) => _call(
    'POST',
    'admin/inventory/variants/${Uri.encodeComponent(variantId)}/initialize',
  );
  Future<AdminPage> collections(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/collections', query: query));
  Future<AdminRecord> collectionSummary() =>
      _call('GET', 'admin/collections/summary');
  Future<AdminRecord> collectionStyles() =>
      _call('GET', 'admin/collections/styles');
  Future<AdminPage> collectionCovers(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/collections/covers', query: query));
  Future<AdminRecord> deleteCollection(
    String id,
    int version, {
    void Function()? onLateCompletion,
  }) => _call(
    'DELETE',
    'admin/collections/${Uri.encodeComponent(id)}',
    body: {'expectedVersion': version},
    onLateCompletion: onLateCompletion,
  );
  Future<AdminRecord> saveCollection(
    String? id,
    AdminRecord body, {
    void Function()? onLateCompletion,
  }) => _call(
    id == null ? 'POST' : 'PATCH',
    id == null
        ? 'admin/collections'
        : 'admin/collections/${Uri.encodeComponent(id)}',
    body: body,
    onLateCompletion: onLateCompletion,
  );
  Future<AdminPage> promotions(Map<String, String> query) async =>
      AdminPage(await _call('GET', 'admin/promotions', query: query));
  Future<AdminRecord> promotionSummary() =>
      _call('GET', 'admin/promotions/summary');
  Future<AdminPage> promotionHistory(String id, int page) async => AdminPage(
    await _call(
      'GET',
      'admin/promotions/${Uri.encodeComponent(id)}/redemptions',
      query: {'page': '$page', 'limit': '10'},
    ),
  );
  Future<AdminRecord> deletePromotion(
    String id,
    int version, {
    void Function()? onLateCompletion,
  }) => _call(
    'DELETE',
    'admin/promotions/${Uri.encodeComponent(id)}',
    body: {'expectedVersion': version},
    onLateCompletion: onLateCompletion,
  );
  Future<AdminRecord> savePromotion(
    String? id,
    AdminRecord body, {
    void Function()? onLateCompletion,
  }) => _call(
    id == null ? 'POST' : 'PATCH',
    id == null
        ? 'admin/promotions'
        : 'admin/promotions/${Uri.encodeComponent(id)}',
    body: body,
    onLateCompletion: onLateCompletion,
  );
  Future<AdminRecord> uploadImage(
    String id, {
    required Uint8List bytes,
    required String mimeType,
    required String alt,
    required String key,
    void Function()? onLateCompletion,
  }) async {
    _check();
    final result = await api.uploadImage(
      'admin/products/${Uri.encodeComponent(id)}/images',
      bytes: bytes,
      mimeType: mimeType,
      fields: {'alt': alt},
      key: key,
      onLateCompletion: onLateCompletion,
    );
    _check();
    return commerceMap(result);
  }

  Future<AdminRecord> saveTaxonomy(
    String kind,
    String? id,
    AdminRecord body, {
    void Function()? onLateCompletion,
  }) {
    if (!['categories', 'brands'].contains(kind)) {
      throw ArgumentError.value(kind);
    }
    return _call(
      id == null ? 'POST' : 'PATCH',
      id == null ? 'admin/$kind' : 'admin/$kind/${Uri.encodeComponent(id)}',
      body: body,
      onLateCompletion: onLateCompletion,
    );
  }

  Future<AdminRecord> deleteTaxonomy(
    String kind,
    String id,
    String expectedUpdatedAt, {
    void Function()? onLateCompletion,
  }) {
    if (!['categories', 'brands'].contains(kind)) {
      throw ArgumentError.value(kind);
    }
    return _call(
      'DELETE',
      'admin/$kind/${Uri.encodeComponent(id)}',
      body: {'expectedUpdatedAt': expectedUpdatedAt},
      onLateCompletion: onLateCompletion,
    );
  }

  Future<AdminRecord> saveSku(String? id, AdminRecord body) => _call(
    id == null ? 'POST' : 'PATCH',
    id == null ? 'admin/skus' : 'admin/skus/${Uri.encodeComponent(id)}',
    body: body,
  );
  Future<AdminRecord> adjust(
    String id, {
    required int delta,
    required int version,
    required String reason,
    String? operation,
  }) => _call(
    'POST',
    'admin/inventory/${Uri.encodeComponent(id)}/adjust',
    body: {
      'delta': delta,
      'expectedVersion': version,
      'reason': reason,
      'operation': ?operation,
    },
  );
  Future<AdminRecord> status(
    String id, {
    required String status,
    required int version,
  }) => _call(
    'PATCH',
    'admin/orders/${Uri.encodeComponent(id)}/status',
    body: {'status': status, 'expectedVersion': version},
  );
  Future<AdminRecord> settleCod(
    String id, {
    required String amount,
    required String reference,
    required int version,
  }) => _call(
    'POST',
    'admin/orders/${Uri.encodeComponent(id)}/settle-cod',
    body: {
      'amount': amount,
      'reference': reference,
      'expectedVersion': version,
    },
  );
  Future<AdminRecord> shipmentEvent(
    String id, {
    required String status,
    required String note,
    required String eventKey,
    required int version,
  }) => _call(
    'POST',
    'admin/orders/${Uri.encodeComponent(id)}/shipment-events',
    body: {
      'status': status,
      'note': note,
      'eventKey': eventKey,
      'expectedVersion': version,
    },
  );
  Future<AdminRecord> cancelOrder(
    String id, {
    required int version,
    required String reason,
  }) => _call(
    'POST',
    'admin/orders/${Uri.encodeComponent(id)}/cancel',
    body: {'expectedVersion': version, 'reason': reason},
  );
  Future<AdminRecord> returnAction(
    String id,
    String returnId, {
    required int version,
    required String action,
    required String note,
  }) => _call(
    'POST',
    'admin/orders/${Uri.encodeComponent(id)}/returns/${Uri.encodeComponent(returnId)}/${action == 'RECEIVED' ? 'receive' : 'decision'}',
    body: {
      'expectedVersion': version,
      'note': note,
      if (action != 'RECEIVED') 'status': action,
    },
  );
}
