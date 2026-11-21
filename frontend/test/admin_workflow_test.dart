import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/data/mock_catalog.dart';

void main() {
  testWidgets('product table paginates and search resets the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(
            MockProductRepository(latency: Duration.zero),
          ),
        ],
        child: NepApp(router: createRouter(initialLocation: '/admin/products')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Áo cotton không tay Essential'), findsOneWidget);
    expect(find.text('Quần jogger nhẹ Daily'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Trang sau'));
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pumpAndSettle();
    expect(find.text('Quần jogger nhẹ Daily'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(
      find.byType(TextField).first,
      'Áo cotton không tay Essential',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('Áo cotton không tay Essential'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 / 1'), findsOneWidget);
  });
  testWidgets('admin can add a distinct color size variant and save it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MockProductRepository(latency: Duration.zero);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productRepositoryProvider.overrideWithValue(repo)],
        child: NepApp(
          router: createRouter(initialLocation: '/admin/products/p1/edit'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Thêm biến thể'));
    await tester.tap(find.text('Thêm biến thể'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm vào bảng'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lưu sản phẩm demo'));
    await tester.tap(find.text('Lưu sản phẩm demo'));
    await tester.pumpAndSettle();
    final product = repo.products.firstWhere((p) => p.slug == 'nep-1');
    expect(product.variants.length, 9);
    expect(product.variants.last.size, 'XXL');
    expect(product.variants.last.color, 'Trắng');
    expect(product.media.single.color, 'Trắng');
    expect(product.media.single.path, 'assets/images/shirt.jpg');
    expect(tester.takeException(), isNull);
  });
}
