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

  Future<AdminPage> list(String kind, int page) async => AdminPage(
    await _call('GET', 'admin/$kind', query: {'page': '$page', 'limit': '20'}),
  );
  Future<AdminRecord> detail(String kind, String id) =>
      _call('GET', 'admin/$kind/${Uri.encodeComponent(id)}');
  Future<AdminRecord> summary() => _call('GET', 'admin/summary');
  Future<AdminRecord> content() => _call('GET', 'admin/content');
  Future<AdminRecord> saveContent(AdminRecord body) =>
      _call('PUT', 'admin/content', body: body);
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
    final values = await Future.wait([
      api.get('categories'),
      api.get('brands'),
    ]);
    _check();
    return {'categories': values[0], 'brands': values[1]};
  }

  Future<AdminRecord> saveProduct(String? id, AdminRecord body) => _call(
    id == null ? 'POST' : 'PATCH',
    id == null ? 'admin/products' : 'admin/products/${Uri.encodeComponent(id)}',
    body: body,
  );
  Future<AdminRecord> savePromotion(String? id, AdminRecord body) => _call(
    id == null ? 'POST' : 'PATCH',
    id == null
        ? 'admin/promotions'
        : 'admin/promotions/${Uri.encodeComponent(id)}',
    body: body,
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

  Future<AdminRecord> saveTaxonomy(String kind, String? id, AdminRecord body) {
    if (!['categories', 'brands'].contains(kind)) {
      throw ArgumentError.value(kind);
    }
    return _call(
      id == null ? 'POST' : 'PATCH',
      id == null ? 'admin/$kind' : 'admin/$kind/${Uri.encodeComponent(id)}',
      body: body,
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
  }) => _call(
    'POST',
    'admin/inventory/${Uri.encodeComponent(id)}/adjust',
    body: {'delta': delta, 'expectedVersion': version, 'reason': reason},
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
