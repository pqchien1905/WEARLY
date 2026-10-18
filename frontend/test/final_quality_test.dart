import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/app/commerce_state.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/data/mock_commerce.dart';
import 'package:nep_storefront/domain/commerce.dart';

void main() {
  testWidgets('declining order cancellation restores the displayed status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final products = MockProductRepository(latency: Duration.zero);
    final orders = MockOrderRepository(products, MockCartRepository(products));
    orders.orders.add(
      Order(
        id: 'WRL-0001',
        items: const [],
        draft: const CheckoutDraft(
          name: 'Demo',
          email: 'demo@example.com',
          phone: '0901234567',
          address: '123 Demo Street',
        ),
        shipping: 30000,
        createdAt: DateTime(2026, 10, 16),
      ),
    );
    final router = createRouter(initialLocation: '/admin/orders');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [orderRepositoryProvider.overrideWithValue(orders)],
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    final status = find.byKey(const ValueKey('order-status-WRL-0001'));
    await tester.ensureVisible(status);
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã hủy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giữ lại'));
    await tester.pumpAndSettle();
    expect(orders.orders.single.status, 'Chờ xác nhận');
    final field = tester.widget<DropdownButton<String>>(status);
    expect(field.value, 'Chờ xác nhận');
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã hủy').last);
    await tester.pumpAndSettle();
    router.go('/admin/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(orders.orders.single.status, 'Chờ xác nhận');
    expect(tester.takeException(), isNull);
  });
  testWidgets('search dialog wraps its heading at enlarged mobile text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(
            MockProductRepository(latency: Duration.zero),
          ),
        ],
        child: NepApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tìm kiếm'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final path in [
    '/',
    '/shop',
    '/products/nep-1',
    '/ai-stylist',
    '/login',
  ]) {
    testWidgets('$path handles enlarged text on narrow mobile', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(
              MockProductRepository(latency: Duration.zero),
            ),
          ],
          child: NepApp(router: createRouter(initialLocation: path)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
