import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/data/mock_catalog.dart';

void main() {
  for (final width in [375.0, 1440.0]) {
    testWidgets('shopping completes demo checkout at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = createRouter(initialLocation: '/products/nep-1');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(
              MockProductRepository(latency: Duration.zero),
            ),
          ],
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('M').first);
      await tester.tap(find.text('M').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Thêm vào giỏ'));
      await tester.tap(find.text('Thêm vào giỏ'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ hàng của bạn'), findsOneWidget);
      await tester.ensureVisible(find.text('Tiến hành đặt hàng'));
      await tester.tap(find.text('Tiến hành đặt hàng'));
      await tester.pumpAndSettle();
      for (final entry in {
        'Họ và tên': 'Người thử demo',
        'Email': 'demo@example.com',
        'Số điện thoại': '0901234567',
        'Địa chỉ đầy đủ': '123 Đường Demo, Hà Nội',
      }.entries) {
        final field = find.widgetWithText(TextFormField, entry.key);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      final agree = find.text(
        'Tôi hiểu đây là đơn mô phỏng, không thanh toán thật.',
      );
      await tester.ensureVisible(agree);
      await tester.tap(agree);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tạo đơn hàng demo'));
      await tester.tap(find.text('Tạo đơn hàng demo'));
      await tester.pumpAndSettle();
      expect(find.text('Đã tạo đơn demo WRL-0001'), findsOneWidget);
      expect(find.text('520.000 ₫'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
