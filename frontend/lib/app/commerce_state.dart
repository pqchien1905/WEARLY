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
  if (!ref.watch(remoteApiProvider)) {
    return MockCartRepository(ref.watch(productRepositoryProvider));
  }
  ref.watch(accountProvider.select((user) => (user?.id, user?.email)));
  final cart = RemoteCartRepository(ref.watch(apiClientProvider));
  ref.onDispose(cart.dispose);
  return cart;
});
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  if (!ref.watch(remoteApiProvider)) {
    return MockOrderRepository(
      ref.watch(productRepositoryProvider),
      ref.watch(cartRepositoryProvider),
    );
  }
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
    cartState.loaded = historyState.loaded = !remote;
    if (remote && signedIn) {
      Future.microtask(() {
        if (!_disposed) refresh();
      });
    }
  }
  final bool remote, signedIn;
  final cartState = CommerceLoadState(), historyState = CommerceLoadState();
  final _details = <String, CommerceLoadState>{};
  CommerceLoadState detailState(String id) =>
      _details.putIfAbsent(id, () => CommerceLoadState()..loaded = !remote);
  bool get requiresLogin => remote && !signedIn;
  bool get checkoutPending =>
      orderRepository is RemoteOrderRepository &&
      (orderRepository as RemoteOrderRepository).hasPendingCheckout;
  PendingCheckout? get pendingCheckout =>
      orderRepository is RemoteOrderRepository
      ? (orderRepository as RemoteOrderRepository).pendingCheckout
      : null;
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
    if (requiresLogin) {
      throw const ApiException(
        'LOGIN_REQUIRED',
        'Vui lòng đăng nhập để sử dụng giỏ hàng.',
      );
    }
  }

  Future<void> _load(
    CommerceLoadState state,
    Future<void> Function() action,
  ) async {
    if (_disposed || requiresLogin) return;
    state.pending++;
    state.error = null;
    notifyListeners();
    try {
      await action();
      state.loaded = true;
      state.error = null;
    } catch (e) {
      state.error = e;
    } finally {
      state.pending--;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await Future.wait([refreshCart(), refreshOrders()]);
  }

  Future<void> refreshCart() async {
    if (checkoutPending) return;
    await _load(cartState, () async {
      if (cart is RemoteCartRepository) {
        await (cart as RemoteCartRepository).refresh();
      }
    });
  }

  Future<void> refreshOrders() => _load(historyState, () async {
    if (orderRepository is RemoteOrderRepository) {
      await (orderRepository as RemoteOrderRepository).refresh();
    }
  });
  Future<void> loadMoreOrders() => _load(historyState, () async {
    if (orderRepository is RemoteOrderRepository) {
      await (orderRepository as RemoteOrderRepository).loadMore();
    }
  });
  Future<void> loadOrder(String id) => _load(detailState(id), () async {
    if (orderRepository is RemoteOrderRepository) {
      await (orderRepository as RemoteOrderRepository).loadOrder(id);
    }
  });
  Future<void> _mutate(
    Future<void> Function() action, {
    CommerceLoadState? state,
  }) async {
    _requireAccount();
    final pending = action();
    notifyListeners();
    try {
      await pending;
      if (state != null) {
        state.loaded = true;
        state.error = null;
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> add(String slug, String sku, int quantity) async {
    await _mutate(() => cart.add(slug, sku, quantity), state: cartState);
  }

  Future<void> update(String sku, int quantity) async {
    await _mutate(() => cart.update(sku, quantity), state: cartState);
  }

  Future<void> remove(String sku) => _mutate(
    () => Future<void>.sync(() => cart.remove(sku)),
    state: cartState,
  );

  Future<void> clear() =>
      _mutate(() => Future<void>.sync(cart.clear), state: cartState);

  Future<Order> checkout(CheckoutDraft draft) async {
    _requireAccount();
    final pending = orderRepository.checkout(draft);
    notifyListeners();
    try {
      final o = await pending;
      cartState.loaded = true;
      cartState.error = null;
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
  }, state: detailState(id));
}

class CommerceLoadState {
  bool loaded = false;
  int pending = 0;
  Object? error;
  bool get loading => pending > 0 || (!loaded && error == null);
  bool get needsFeedback => loading || error != null;
}
