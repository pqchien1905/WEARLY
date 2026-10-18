import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/data/mock_commerce.dart';
import 'package:nep_storefront/domain/commerce.dart';

void main() {
  late MockProductRepository catalog;
  late MockCartRepository cart;
  late MockOrderRepository orders;
  setUp(() {
    catalog = MockProductRepository(latency: Duration.zero);
    cart = MockCartRepository(catalog);
    orders = MockOrderRepository(catalog, cart);
  });
  test(
    'cart merges same SKU and refuses quantity above available stock',
    () async {
      await cart.add('nep-1', 'WRL-1-MAIN-S', 2);
      await cart.add('nep-1', 'WRL-1-MAIN-S', 1);
      expect(cart.items.single.quantity, 3);
      await expectLater(cart.add('nep-1', 'WRL-1-MAIN-S', 1), throwsStateError);
      expect(cart.subtotal, 1470000);
    },
  );
  test(
    'checkout computes shipping, snapshots items and decrements stock',
    () async {
      await cart.add('nep-1', 'WRL-1-MAIN-M', 2);
      final order = await orders.checkout(
        const CheckoutDraft(
          name: 'Khách demo',
          email: 'demo@example.com',
          phone: '0901234567',
          address: '123 Đường Demo, Hà Nội',
        ),
      );
      expect(order.total, 1010000);
      expect(order.shipping, 30000);
      expect(order.items.single.unitPrice, 490000);
      expect(cart.items, isEmpty);
      expect(
        (await catalog.bySlug(
          'nep-1',
        ))!.variants.firstWhere((v) => v.sku == 'WRL-1-MAIN-M').stock,
        10,
      );
      final p = (await catalog.bySlug('nep-1'))!;
      await catalog.save(p.copyWith(name: 'Tên đã đổi'));
      expect(order.items.single.name, 'Áo cotton không tay Essential');
    },
  );
  test('stale inventory rejects checkout and keeps the cart', () async {
    await cart.add('nep-1', 'WRL-1-MAIN-S', 3);
    final p = (await catalog.bySlug('nep-1'))!;
    await catalog.save(
      p.copyWith(
        variants: p.variants
            .map((v) => v.sku == 'WRL-1-MAIN-S' ? v.copyWith(stock: 1) : v)
            .toList(),
      ),
    );
    await expectLater(
      orders.checkout(
        const CheckoutDraft(
          name: 'Demo',
          email: 'demo@example.com',
          phone: '0901234567',
          address: '123 Demo',
        ),
      ),
      throwsStateError,
    );
    expect(cart.items.single.quantity, 3);
    expect(orders.orders, isEmpty);
  });
}
