import 'dart:math';
import '../app/config.dart';
import '../core/network/api_client.dart';
import '../domain/commerce.dart';
import 'checkout_pending_store.dart';
import 'commerce_json.dart';
import 'remote_cart.dart';

class RemoteOrderRepository implements OrderRepository {
  RemoteOrderRepository(
    this.api,
    this.cart, {
    this.email = '',
    this.owner,
    CheckoutPendingStore? pendingStore,
    this.autoRetries = 2,
    this.retryDelay = const Duration(milliseconds: 1500),
  }) : _generation = api.tokens.generation,
       _store = pendingStore ?? MemoryCheckoutPendingStore() {
    _restore();
  }
  final ApiClient api;
  final RemoteCartRepository cart;
  final String email;

  /// Account the unresolved checkout belongs to; null disables persistence.
  final String? owner;
  final CheckoutPendingStore _store;

  /// Same-key resends after a lost/5xx response, before reporting uncertainty.
  /// Safe: the idempotency key makes the server return the original order.
  final int autoRetries;
  final Duration retryDelay;
  final int _generation;
  bool _disposed = false, _checkingOut = false;
  List<Order> _orders = [];
  List<String> _historyIds = [];
  int _page = 0, _loaded = 0, _total = 0;
  Future<void> _tail = Future<void>.value();
  ({String key, Map<String, Object?> body, PendingCheckout snapshot})? _attempt;
  @override
  List<Order> get orders => List.unmodifiable(_orders);
  List<Order> get history => List.unmodifiable(
    _historyIds.map((id) => _orders.firstWhere((order) => order.id == id)),
  );
  bool get hasMore => _loaded < _total;
  int get total => _total;
  bool get hasPendingCheckout => _attempt != null;
  PendingCheckout? get pendingCheckout => _attempt?.snapshot;

  /// A reload must keep re-checking the unresolved request, never start anew.
  void _restore() {
    final account = owner;
    if (account == null) return;
    final stored = StoredCheckout.decode(_store.read(account));
    if (stored == null) {
      _store.clear(account);
      return;
    }
    _attempt = (key: stored.key, body: stored.body, snapshot: stored.snapshot);
    cart.setLocked(true);
  }

  void _persist() {
    final account = owner, attempt = _attempt;
    if (account == null) return;
    if (attempt == null) {
      _store.clear(account);
    } else {
      _store.save(
        account,
        StoredCheckout(
          key: attempt.key,
          body: attempt.body,
          snapshot: attempt.snapshot,
          savedAt: DateTime.now(),
        ).encode(),
      );
    }
  }

  static bool _uncertain(ApiException e) =>
      e.code != sessionChanged.code &&
      e.code != 'PAYMENT_UNAVAILABLE' &&
      (e.status == null || e.status! >= 500);

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
      // A list refresh must not evict a directly opened older order's detail.
      _historyIds = items.map((order) => order.id).toList();
      _loaded = items.length;
    } else {
      for (final item in items) {
        if (!_historyIds.contains(item.id)) _historyIds.add(item.id);
      }
      _loaded += items.length;
    }
    for (final item in items) {
      final index = _orders.indexWhere((order) => order.id == item.id);
      if (index < 0) {
        _orders.add(item);
      } else {
        _orders[index] = item;
      }
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
    if (order.id != id) throw invalidCommerce;
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
        snapshot: PendingCheckout(
          draft: draft,
          subtotal: cart.subtotal,
          shipping: draft.express
              ? BrandConfig.expressFee
              : cart.subtotal >= BrandConfig.freeShippingAt
              ? 0
              : BrandConfig.shippingFee,
        ),
        key: List.generate(
          24,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        body: {
          'addressId': draft.addressId,
          'shippingMethod': draft.express ? 'express' : 'standard',
          'expectedSubtotal': cart.subtotal.toString(),
          'cartVersion': cart.version,
          if (draft.paymentMethod != 'cod')
            'paymentMethod': draft.paymentMethod,
          if (draft.couponCode != null) ...{
            'couponCode': draft.couponCode,
            'expectedDiscount': draft.discount.toString(),
          },
        },
      );
      // Saved before sending: a reload during the request still re-checks it.
      _persist();
    }
    _checkingOut = true;
    cart.setLocked(true);
    try {
      final attempt = _attempt!;
      Object? data;
      for (var retry = 0; ; retry++) {
        try {
          data = await api.request(
            'POST',
            'orders',
            body: attempt.body,
            headers: {'Idempotency-Key': attempt.key},
          );
          break;
        } on ApiException catch (e) {
          if (!_uncertain(e) || retry >= autoRetries) rethrow;
          await Future<void>.delayed(retryDelay * (retry + 1));
          _check();
        }
      }
      _check();
      final order = commerceOrder(data, email: email);
      // Drain older history requests before publishing the confirmed order.
      await _queue(() async {
        _upsert(order);
      });
      _check();
      cart.acceptCheckout();
      _attempt = null;
      _persist();
      cart.setLocked(false);
      return order;
    } on ApiException catch (error) {
      // A lost/invalid success response may already have committed. Reuse the
      // original body and key until the server gives a definitive answer.
      if ([400, 404, 409, 422].contains(error.status) ||
          error.code == 'PAYMENT_UNAVAILABLE') {
        _attempt = null;
        _persist();
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
    _historyIds = [];
    _attempt = null;
  }
}
