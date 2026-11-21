import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/commerce_state.dart';
import 'package:nep_storefront/domain/commerce.dart';
import 'package:nep_storefront/features/account/account_components.dart';
import 'package:nep_storefront/features/account/orders_page.dart';
import 'order_journeys_test.dart' show sample;

void main() {
  test('order date uses Vietnam time when UTC is on the previous day', () {
    expect(orderDate(DateTime.parse('2026-10-23T18:30:00Z')), '24/10/2026');
  });
  for (final width in [375.0, 1440.0, 2560.0]) {
    testWidgets('populated orders use readable full-width columns at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final source = sample(
        '76b5deb1-4367-4e3a-9586-ce58998e4646',
        'Chờ xác nhận',
      );
      c
          .read(orderRepositoryProvider)
          .orders
          .add(
            Order(
              id: source.id,
              code: 'WR00001F',
              items: source.items,
              draft: source.draft,
              shipping: source.shipping,
              createdAt: source.createdAt,
              isSample: true,
            ),
          );
      final router = createRouter(initialLocation: '/account/orders');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: NepApp(router: router),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('WR00001F'), findsOneWidget);
      expect(find.text(source.id), findsNothing);
      expect(find.text('Dữ liệu mẫu'), findsNothing);
      if (width >= 1440) {
        expect(find.byType(Table), findsOneWidget);
        final table = t.getRect(find.byType(Table));
        expect(table.left, closeTo(344, 2));
        expect(table.right, closeTo(width - 56, 2));
      }
      await t.enterText(
        find.widgetWithText(TextField, 'Tìm mã đơn hoặc tên sản phẩm'),
        'wr00001f',
      );
      await t.pumpAndSettle();
      expect(find.text('1 đơn hàng'), findsOneWidget);
      router.go('/account/orders/${source.id}');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('WR00001F'), findsOneWidget);
      Finder panel(String title) =>
          find.byWidgetPredicate((w) => w is AccountCard && w.title == title);
      final products = t.getRect(panel('Sản phẩm trong đơn'));
      final recipient = t.getRect(panel('Thông tin nhận hàng'));
      if (width >= 1440) {
        expect(products.top, closeTo(recipient.top, 1));
        expect(products.left, closeTo(344, 1));
        expect(recipient.right, closeTo(width - 56, 1));
        expect(recipient.left - products.right, closeTo(24, 1));
      } else {
        expect(products.left, closeTo(20, 1));
        expect(products.width, closeTo(width - 40, 1));
        expect(recipient.top, greaterThan(products.bottom));
        expect(
          t.getTopLeft(find.text('WR00001F')).dy,
          closeTo(t.getTopLeft(find.text(orderDate(source.createdAt))).dy, 1),
        );
      }
    });
  }
}
