import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../data/mock_commerce.dart';
import '../data/remote_commerce.dart';
import '../core/network/api_client.dart';
import '../domain/commerce.dart';
import 'account_state.dart';
import 'api_providers.dart';
import 'providers.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  if (!ref.watch(remoteApiProvider))
    return MockCartRepository(ref.watch(productRepositoryProvider));
  ref.watch(accountProvider.select((user) => (user?.id, user?.email)));
  final cart = RemoteCartRepository(ref.watch(apiClientProvider));
  ref.onDispose(cart.dispose);
  return cart;
});
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  if (!ref.watch(remoteApiProvider))
    return MockOrderRepository(
      ref.watch(productRepositoryProvider),
      ref.watch(cartRepositoryProvider),
    );
  final identity = ref.watch(
    accountProvider.select((user) => (user?.id, user?.email)),
  );
  final orders = RemoteOrderRepository(
    ref.watch(apiClientProvider),
    ref.watch(cartRepositoryProvider) as RemoteCartRepository,
    email: identity.$2 ?? '',
  );
  ref.onDispose(orders.dispose);
  return orders;
});
final commerceProvider = ChangeNotifierProvider<CommerceController>(
  (ref) => CommerceController(
    ref.watch(cartRepositoryProvider),
    ref.watch(orderRepositoryProvider),
    remote: ref.watch(remoteApiProvider),
    signedIn: ref.watch(accountProvider.select((user) => user != null)),
    onCatalogChanged: () =>
        ref.read(catalogRevisionProvider.notifier).refresh(),
  ),
);

class CommerceController extends ChangeNotifier {
  CommerceController(
    this.cart,
    this.orderRepository, {
    this.onCatalogChanged,
    this.remote = false,
    this.signedIn = false,
  }) {
    if (remote && signedIn)
      Future.microtask(() {
        if (!_disposed) refresh();
      });
  }
  final bool remote, signedIn;
  bool loading = false;
  int _loads = 0;
  Object? error;
  bool get requiresLogin => remote && !signedIn;
  bool get checkoutPending =>
      orderRepository is RemoteOrderRepository &&
      (orderRepository as RemoteOrderRepository).hasPendingCheckout;
  bool get hasMoreOrders =>
      orderRepository is RemoteOrderRepository &&
      (orderRepository as RemoteOrderRepository).hasMore;
  final VoidCallback? onCatalogChanged;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  final CartRepository cart;
  final OrderRepository orderRepository;
  List<CartItem> get items => List.unmodifiable(cart.items);
  List<Order> get orders => List.unmodifiable(orderRepository.orders);
  int get count => items.fold(0, (sum, i) => sum + i.quantity);
  void _requireAccount() {
    if (_disposed) throw sessionChanged;
    if (requiresLogin)
      throw const ApiException(
        'LOGIN_REQUIRED',
        'Vui lòng đăng nhập để sử dụng giỏ hàng.',
      );
  }

  Future<void> _load(Future<void> Function() action) async {
    if (_disposed || requiresLogin) return;
    _loads++;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = e;
    } finally {
      loading = --_loads > 0;
      notifyListeners();
    }
  }

  Future<void> refresh() => _load(() async {
    if (cart is RemoteCartRepository && !checkoutPending)
      await (cart as RemoteCartRepository).refresh();
    if (orderRepository is RemoteOrderRepository)
      await (orderRepository as RemoteOrderRepository).refresh();
  });
  Future<void> loadMoreOrders() => _load(() async {
    if (orderRepository is RemoteOrderRepository)
      await (orderRepository as RemoteOrderRepository).loadMore();
  });
  Future<void> loadOrder(String id) => _load(() async {
    if (orderRepository is RemoteOrderRepository)
      await (orderRepository as RemoteOrderRepository).loadOrder(id);
  });
  Future<void> _mutate(Future<void> Function() action) async {
    _requireAccount();
    final pending = action();
    notifyListeners();
    try {
      await pending;
      error = null;
    } finally {
      notifyListeners();
    }
  }

  Future<void> add(String slug, String sku, int quantity) async {
    await _mutate(() => cart.add(slug, sku, quantity));
  }

  Future<void> update(String sku, int quantity) async {
    await _mutate(() => cart.update(sku, quantity));
  }

  Future<void> remove(String sku) =>
      _mutate(() => Future<void>.sync(() => cart.remove(sku)));

  Future<void> clear() => _mutate(() => Future<void>.sync(cart.clear));

  Future<Order> checkout(CheckoutDraft draft) async {
    _requireAccount();
    final pending = orderRepository.checkout(draft);
    notifyListeners();
    try {
      final o = await pending;
      if (!_disposed) {
        onCatalogChanged?.call();
      }
      return o;
    } finally {
      notifyListeners();
    }
  }

  Future<void> setStatus(String id, String status) => _mutate(() async {
    await Future<void>.sync(() => orderRepository.setStatus(id, status));
    if (!_disposed) onCatalogChanged?.call();
  });
}
