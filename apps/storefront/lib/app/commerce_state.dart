import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../data/mock_commerce.dart';
import '../domain/commerce.dart';
import 'providers.dart';

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => MockCartRepository(ref.watch(productRepositoryProvider)),
);
final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => MockOrderRepository(
    ref.watch(productRepositoryProvider),
    ref.watch(cartRepositoryProvider),
  ),
);
final commerceProvider = ChangeNotifierProvider<CommerceController>(
  (ref) => CommerceController(
    ref.watch(cartRepositoryProvider),
    ref.watch(orderRepositoryProvider),
    onCatalogChanged: () =>
        ref.read(catalogRevisionProvider.notifier).refresh(),
  ),
);

class CommerceController extends ChangeNotifier {
  CommerceController(this.cart, this.orderRepository, {this.onCatalogChanged});
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
  Future<void> add(String slug, String sku, int quantity) async {
    await cart.add(slug, sku, quantity);
    notifyListeners();
  }

  Future<void> update(String sku, int quantity) async {
    await cart.update(sku, quantity);
    notifyListeners();
  }

  void remove(String sku) {
    cart.remove(sku);
    notifyListeners();
  }

  void clear() {
    cart.clear();
    notifyListeners();
  }

  Future<Order> checkout(CheckoutDraft draft) async {
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

  void setStatus(String id, String status) {
    orderRepository.setStatus(id, status);
    notifyListeners();
  }
}
