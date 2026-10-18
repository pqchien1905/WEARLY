import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/data/mock_commerce.dart';
import 'package:nep_storefront/data/mock_ai.dart';
import 'package:nep_storefront/domain/commerce.dart';
import 'package:nep_storefront/domain/ai.dart';

const draft = CheckoutDraft(
  name: 'Demo',
  email: 'demo@example.com',
  phone: '0901234567',
  address: '123 Demo Hà Nội',
);
void main() {
  test(
    'removing preceding cart row cannot retarget a pending SKU update',
    () async {
      final catalog = MockProductRepository(
        latency: const Duration(milliseconds: 10),
      );
      final cart = MockCartRepository(catalog);
      await cart.add('nep-1', 'WRL-1-MAIN-M', 1);
      await cart.add('nep-2', 'WRL-2-MAIN-M', 1);
      final update = cart.update('WRL-2-MAIN-M', 2);
      cart.remove('WRL-1-MAIN-M');
      await update;
      expect(cart.items.single.sku, 'WRL-2-MAIN-M');
      expect(cart.items.single.quantity, 2);
    },
  );
  test('checkout prevents cart edits while its snapshot is pending', () async {
    final catalog = MockProductRepository(
      latency: const Duration(milliseconds: 20),
    );
    final cart = MockCartRepository(catalog);
    final orders = MockOrderRepository(catalog, cart);
    await cart.add('nep-1', 'WRL-1-MAIN-M', 1);
    final pending = orders.checkout(draft);
    await expectLater(cart.add('nep-2', 'WRL-2-MAIN-M', 1), throwsStateError);
    await pending;
    expect(orders.orders.single.items.length, 1);
  });
  test(
    'price change during final checkout latency rejects without consuming stock',
    () async {
      final catalog = MockProductRepository(
        latency: const Duration(milliseconds: 40),
      );
      final cart = MockCartRepository(catalog);
      final orders = MockOrderRepository(catalog, cart);
      await cart.add('nep-1', 'WRL-1-MAIN-M', 1);
      final p = (await catalog.bySlug('nep-1'))!;
      final pending = orders.checkout(draft);
      final rejection = expectLater(pending, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await catalog.save(
        p.copyWith(
          variants: p.variants.map((v) => v.copyWith(price: 990000)).toList(),
        ),
      );
      await rejection;
      expect(orders.orders, isEmpty);
      expect(
        (await catalog.bySlug(
          'nep-1',
        ))!.variants.firstWhere((v) => v.size == 'M').stock,
        12,
      );
    },
  );
  test(
    'stylist budgets the requested size after admin changes variant prices',
    () async {
      final catalog = MockProductRepository(latency: Duration.zero);
      for (final p in [...catalog.products]) {
        await catalog.save(
          p.copyWith(
            active: p.id == 'p1' || p.id == 'p3',
            variants: p.variants
                .map((v) => v.copyWith(price: v.size == 'M' ? 850000 : v.price))
                .toList(),
          ),
        );
      }
      final reply = await MockStylistRepository(catalog, latency: Duration.zero)
          .reply(
            const StylistRequest(prompt: 'Phối đồ', budget: 1500000, size: 'M'),
          );
      expect(reply.products.length, 1);
      expect(reply.total, 850000);
    },
  );
}
