import '../domain/catalog.dart';
import '../domain/commerce.dart';
import '../app/config.dart';

class MockCartRepository implements CartRepository {
  MockCartRepository(this.catalog);
  final ProductRepository catalog;
  @override
  List<CartItem> get items => List.unmodifiable(_items);
  final List<CartItem> _items = [];
  @override
  bool locked = false;
  @override
  void setLocked(bool value) {
    locked = value;
  }

  void _checkLock() {
    if (locked) {
      throw StateError(
        'Đơn đang được tạo. Đợi hoàn tất rồi thay đổi giỏ hàng.',
      );
    }
  }

  @override
  int get subtotal => items.fold(0, (sum, i) => sum + i.total);
  @override
  Future<void> add(String slug, String sku, int quantity) async {
    _checkLock();
    final p = await catalog.bySlug(slug);
    _checkLock();
    final v = p?.variants.where((v) => v.sku == sku).firstOrNull;
    if (p == null || v == null || quantity < 1) {
      throw StateError('Biến thể không hợp lệ.');
    }
    final index = items.indexWhere((i) => i.sku == sku);
    final count = quantity + (index < 0 ? 0 : items[index].quantity);
    if (count > v.stock) {
      throw StateError('Chỉ còn ${v.stock} sản phẩm cho size ${v.size}.');
    }
    final item = CartItem(
      slug: slug,
      sku: sku,
      name: p.name,
      image: p.image,
      color: v.color,
      size: v.size,
      unitPrice: v.price,
      quantity: count,
      stock: v.stock,
    );
    if (index < 0) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
  }

  @override
  Future<void> update(String sku, int quantity) async {
    _checkLock();
    final index = items.indexWhere((i) => i.sku == sku);
    if (index < 0) {
      throw StateError('Sản phẩm không có trong giỏ.');
    }
    final p = await catalog.bySlug(items[index].slug);
    _checkLock();
    final v = p?.variants.where((v) => v.sku == sku).firstOrNull;
    if (v == null || quantity < 1 || quantity > v.stock) {
      throw StateError('Số lượng vượt tồn kho hiện tại.');
    }
    final currentIndex = _items.indexWhere((i) => i.sku == sku);
    if (currentIndex < 0) {
      throw StateError('Sản phẩm đã được xóa khỏi giỏ.');
    }
    _items[currentIndex] = _items[currentIndex].withQuantity(quantity);
  }

  @override
  void remove(String sku) {
    _checkLock();
    _items.removeWhere((i) => i.sku == sku);
  }

  @override
  void clear() {
    _checkLock();
    _items.clear();
  }
}

class MockOrderRepository implements OrderRepository {
  MockOrderRepository(this.catalog, this.cart);
  final ProductRepository catalog;
  final CartRepository cart;
  @override
  final List<Order> orders = [];
  bool _busy = false;
  @override
  Future<Order> checkout(CheckoutDraft draft) async {
    if (_busy) {
      throw StateError('Đơn đang được tạo.');
    }
    _busy = true;
    cart.setLocked(true);
    try {
      if (cart.items.isEmpty) {
        throw StateError('Giỏ hàng đang trống.');
      }
      if (draft.name.trim().isEmpty ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(draft.email) ||
          !RegExp(r'^0\d{9}$').hasMatch(draft.phone) ||
          draft.address.trim().length < 8) {
        throw ArgumentError('Kiểm tra lại thông tin nhận hàng.');
      }
      final snapshot = List<CartItem>.unmodifiable(cart.items);
      for (final item in snapshot) {
        final p = await catalog.bySlug(item.slug);
        final v = p?.variants.where((v) => v.sku == item.sku).firstOrNull;
        if (v == null || v.stock < item.quantity) {
          throw StateError(
            'Tồn kho ${item.name} đã thay đổi. Hãy giảm số lượng trong giỏ.',
          );
        }
        if (v.price != item.unitPrice) {
          throw StateError(
            'Giá ${item.name} đã thay đổi. Hãy xóa và thêm lại sản phẩm để xác nhận giá mới.',
          );
        }
      }
      await catalog.consumeStock(
        {for (final item in snapshot) item.sku: item.quantity},
        expectedPrices: {for (final item in snapshot) item.sku: item.unitPrice},
      );
      final subtotal = snapshot.fold(0, (sum, i) => sum + i.total);
      final order = Order(
        id: 'WRL-${(orders.length + 1).toString().padLeft(4, '0')}',
        items: snapshot,
        draft: draft,
        shipping: draft.express
            ? BrandConfig.expressFee
            : subtotal >= BrandConfig.freeShippingAt
            ? 0
            : BrandConfig.shippingFee,
        createdAt: DateTime.now(),
      );
      orders.insert(0, order);
      cart.setLocked(false);
      cart.clear();
      return order;
    } finally {
      _busy = false;
      cart.setLocked(false);
    }
  }

  @override
  void setStatus(String id, String status) {
    final i = orders.indexWhere((o) => o.id == id);
    if (i >= 0) {
      orders[i] = orders[i].withStatus(status);
    }
  }
}
