import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/commerce_state.dart';
import 'package:nep_storefront/domain/commerce.dart';

Order sample(String id, String status) => Order(
  id: id,
  status: status,
  createdAt: DateTime(2026, 10, 16),
  shipping: 30000,
  draft: const CheckoutDraft(
    name: 'Nguyễn An',
    email: 'an@example.com',
    phone: '0901234567',
    address: '12 Nguyễn Huệ, TP.HCM',
  ),
  items: const [
    CartItem(
      slug: 'nep-1',
      sku: 'WRL-1-MAIN-M',
      name:
          'Áo cotton phiên bản đặc biệt với tên sản phẩm dài để kiểm tra nội dung trên điện thoại',
      image: 'assets/images/shirt.jpg',
      color: 'Trắng',
      size: 'M',
      unitPrice: 490000,
      quantity: 1,
      stock: 10,
    ),
  ],
);

void main() {
  testWidgets('customer can search and filter orders then clear filters', (
    t,
  ) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(orderRepositoryProvider).orders.addAll([
      sample('WRL-0001', 'Chờ xác nhận'),
      sample('WRL-0002', 'Đang giao'),
    ]);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(router: createRouter(initialLocation: '/account/orders')),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Tìm mã đơn hoặc tên sản phẩm'),
      '0002',
    );
    await t.pumpAndSettle();
    expect(find.text('WRL-0001'), findsNothing);
    expect(find.text('WRL-0002'), findsOneWidget);
    await t.ensureVisible(find.text('Xóa bộ lọc'));
    await t.tap(find.text('Xóa bộ lọc'));
    await t.pumpAndSettle();
    expect(find.text('WRL-0001'), findsOneWidget);
    final statusField = find.widgetWithText(ChoiceChip, 'Đang giao (1)');
    await t.ensureVisible(statusField);
    await t.tap(statusField);
    await t.pumpAndSettle();
    expect(find.text('WRL-0001'), findsNothing);
    expect(find.text('WRL-0002'), findsOneWidget);
    await t.ensureVisible(find.text('Xóa bộ lọc'));
    await t.tap(find.text('Xóa bộ lọc'));
    await t.pumpAndSettle();
    expect(find.text('WRL-0001'), findsOneWidget);
    expect(find.text('WRL-0002'), findsOneWidget);
  });
  testWidgets(
    'detail shows live status, cancellation and missing ID honestly',
    (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(orderRepositoryProvider)
          .orders
          .add(sample('WRL-0001', 'Chờ xác nhận'));
      final router = createRouter(initialLocation: '/account/orders/WRL-0001');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: NepApp(router: router),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Tiến trình đơn hàng'), findsOneWidget);
      c.read(commerceProvider).setStatus('WRL-0001', 'Đã hủy');
      await t.pumpAndSettle();
      expect(find.text('Đơn đã hủy'), findsOneWidget);
      expect(find.text('Tiến trình đơn hàng'), findsNothing);
      router.go('/account/orders/missing');
      await t.pumpAndSettle();
      expect(find.text('Không tìm thấy đơn hàng'), findsOneWidget);
    },
  );
  testWidgets('long order snapshot fits 320px at 150 percent text', (t) async {
    t.view.physicalSize = const Size(320, 1000);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(orderRepositoryProvider).orders.add(sample('WRL-0001', 'Đang giao'));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(
          router: createRouter(initialLocation: '/account/orders/WRL-0001'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
