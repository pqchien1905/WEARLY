import '../core/network/api_client.dart';
import '../domain/commerce.dart';
import 'commerce_json.dart';

class RemoteCartRepository implements CartRepository {
  RemoteCartRepository(this.api) : _generation = api.tokens.generation;
  final ApiClient api;
  final int _generation;
  bool _disposed = false, _checkoutLocked = false;
  int _pending = 0, _version = 0;
  Future<void> _tail = Future<void>.value();
  List<CartItem> _items = [];
  int get version => _version;
  @override
  List<CartItem> get items => List.unmodifiable(_items);
  @override
  int get subtotal => _items.fold(0, (sum, item) => sum + item.total);
  @override
  bool get locked => _checkoutLocked || _pending > 0;
  @override
  void setLocked(bool value) => _checkoutLocked = value;

  void _check() {
    if (_disposed || api.tokens.generation != _generation) throw sessionChanged;
  }

  Future<void> _queue(Future<void> Function() action) {
    try {
      _check();
      if (_checkoutLocked)
        throw const ApiException(
          'CART_LOCKED',
          'Đang xác nhận đơn hàng. Hãy thử lại yêu cầu đặt hàng trước khi sửa giỏ.',
        );
    } catch (error, stack) {
      return Future<void>.error(error, stack);
    }
    _pending++;
    final future = _tail.then((_) async {
      _check();
      await action();
    });
    final result = future.whenComplete(() => _pending--);
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    _check();
    final data = commerceMap(await api.request(method, path, body: body));
    _check();
    final version = data['version'];
    if (data['currency'] != 'VND' ||
        data['items'] is! List ||
        version is! int ||
        version < 0)
      throw invalidCommerce;
    final items = (data['items'] as List)
        .map((item) => commerceItem(item, cart: true))
        .toList();
    if (items.fold<int>(0, (sum, item) => sum + item.total) !=
            vnd(data['subtotal']) ||
        items.map((item) => item.sku).toSet().length != items.length)
      throw invalidCommerce;
    _items = items;
    _version = version;
  }

  String _itemPath(String sku) {
    final item = _items.where((item) => item.sku == sku).firstOrNull;
    if (item == null)
      throw const ApiException(
        'ITEM_MISSING',
        'Sản phẩm không còn trong giỏ. Hãy tải lại.',
      );
    return 'cart/items/${Uri.encodeComponent(item.id)}';
  }

  Future<void> refresh() => _queue(() => _request('GET', 'cart'));
  @override
  Future<void> add(String slug, String sku, int quantity) => _queue(
    () => _request(
      'POST',
      'cart/items',
      body: {'sku': sku, 'quantity': quantity},
    ),
  );
  @override
  Future<void> update(String sku, int quantity) => _queue(
    () => _request('PATCH', _itemPath(sku), body: {'quantity': quantity}),
  );
  @override
  Future<void> remove(String sku) =>
      _queue(() => _request('DELETE', _itemPath(sku)));
  @override
  Future<void> clear() => _queue(() async {
    for (final item in List<CartItem>.of(_items)) {
      await _request('DELETE', _itemPath(item.sku));
    }
  });
  // Checkout clears the server cart transactionally. Never DELETE here: a
  // replayed order response can coexist with a new cart on another device.
  void acceptCheckout() {
    _check();
    _items = [];
    _version++;
  }

  void dispose() {
    _disposed = true;
    _items = [];
  }
}
