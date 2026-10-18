import 'dart:math';
import '../core/network/api_client.dart';
import '../domain/commerce.dart';
import 'commerce_json.dart';
import 'remote_cart.dart';

class RemoteOrderRepository implements OrderRepository {
  RemoteOrderRepository(this.api, this.cart, {this.email = ''})
    : _generation = api.tokens.generation;
  final ApiClient api;
  final RemoteCartRepository cart;
  final String email;
  final int _generation;
  bool _disposed = false, _checkingOut = false;
  List<Order> _orders = [];
  int _page = 0, _loaded = 0, _total = 0;
  Future<void> _tail = Future<void>.value();
  ({String key, Map<String, Object?> body})? _attempt;
  @override
  List<Order> get orders => List.unmodifiable(_orders);
  bool get hasMore => _loaded < _total;
  bool get hasPendingCheckout => _attempt != null;

  void _check() {
    if (_disposed || api.tokens.generation != _generation) throw sessionChanged;
  }

  Future<void> _queue(Future<void> Function() action) {
    final result = _tail.then((_) async {
      _check();
      await action();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _upsert(Order order) {
    final index = _orders.indexWhere((item) => item.id == order.id);
    if (index < 0) {
      _orders.insert(0, order);
    } else {
      _orders[index] = order;
    }
  }

  Future<void> _readPage(int page) async {
    final data = commerceMap(
      await api.get('orders', query: {'page': '$page', 'limit': '100'}),
    );
    _check();
    if (data['items'] is! List ||
        data['total'] is! int ||
        data['page'] != page) {
      throw invalidCommerce;
    }
    final items = (data['items'] as List)
        .map((item) => commerceOrder(item, email: email))
        .toList();
    if (page == 1) {
      _orders = items;
      _loaded = items.length;
    } else {
      for (final item in items) {
        if (!_orders.any((order) => order.id == item.id)) _orders.add(item);
      }
      _loaded += items.length;
    }
    _page = page;
    _total = data['total'];
  }

  Future<void> refresh() => _queue(() => _readPage(1));
  Future<void> loadMore() => _queue(() async {
    if (hasMore) await _readPage(_page + 1);
  });
  Future<void> loadOrder(String id) => _queue(() async {
    final order = commerceOrder(
      await api.get('orders/${Uri.encodeComponent(id)}'),
      email: email,
    );
    _check();
    _upsert(order);
  });
  @override
  Future<void> setStatus(String id, String status) => _queue(() async {
    if (status != 'Đã hủy') {
      throw const ApiException(
        'NOT_ALLOWED',
        'Chỉ có thể hủy đơn đang chờ xác nhận.',
      );
    }
    final order = commerceOrder(
      await api.request('POST', 'orders/${Uri.encodeComponent(id)}/cancel'),
      email: email,
    );
    _check();
    _upsert(order);
  });

  @override
  Future<Order> checkout(CheckoutDraft draft) async {
    _check();
    if (_checkingOut || (_attempt == null && cart.locked)) {
      throw const ApiException(
        'BUSY',
        'Vui lòng chờ cập nhật giỏ hàng hoàn tất.',
      );
    }
    if (_attempt == null) {
      if (draft.addressId == null ||
          draft.addressId!.isEmpty ||
          cart.items.isEmpty) {
        throw const ApiException(
          'INVALID_CHECKOUT',
          'Chọn địa chỉ đã lưu và thêm sản phẩm trước khi đặt hàng.',
        );
      }
      final random = Random.secure();
      _attempt = (
        key: List.generate(
          24,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        body: {
          'addressId': draft.addressId,
          'shippingMethod': draft.express ? 'express' : 'standard',
          'expectedSubtotal': cart.subtotal.toString(),
          'cartVersion': cart.version,
        },
      );
    }
    _checkingOut = true;
    cart.setLocked(true);
    try {
      final attempt = _attempt!;
      final data = await api.request(
        'POST',
        'orders',
        body: attempt.body,
        headers: {'Idempotency-Key': attempt.key},
      );
      _check();
      final order = commerceOrder(data, email: email);
      // Drain older history requests before publishing the confirmed order.
      await _queue(() async {
        _upsert(order);
      });
      _check();
      cart.acceptCheckout();
      _attempt = null;
      cart.setLocked(false);
      return order;
    } on ApiException catch (error) {
      // A lost/invalid success response may already have committed. Reuse the
      // original body and key until the server gives a definitive answer.
      if (error.status != null && error.status! >= 400 && error.status! < 500) {
        _attempt = null;
        cart.setLocked(false);
      }
      rethrow;
    } finally {
      _checkingOut = false;
    }
  }

  void dispose() {
    _disposed = true;
    _orders = [];
    _attempt = null;
  }
}
