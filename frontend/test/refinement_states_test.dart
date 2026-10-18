import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/core/widgets/primitives.dart';
import 'package:nep_storefront/core/widgets/product_card.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/domain/catalog.dart';
import 'package:nep_storefront/features/product_detail/product_gallery.dart';
import 'package:nep_storefront/features/virtual_tryon/tryon_results.dart';

void main() {
  testWidgets('catalog card with eight colors fits a narrow mobile column', (
    tester,
  ) async {
    final p = MockProductRepository(latency: Duration.zero).products.first
        .copyWith(
          variants: [
            for (var i = 0; i < 8; i++)
              ProductVariant(
                sku: 'test-$i',
                size: 'M',
                color: 'Color $i',
                colorHex: 0xFF111111,
                price: 490000,
                stock: 1,
              ),
          ],
        );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 160, child: ProductCard(p))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('8 màu'), findsOneWidget);
  });
  testWidgets('gallery thumbnail and keyboard change the displayed media', (
    tester,
  ) async {
    const p = Product(
      id: 'test',
      slug: 'test',
      name: 'Gallery fixture',
      category: 'ao',
      image: 'assets/images/shirt.jpg',
      description: '',
      material: '',
      style: '',
      variants: [],
      media: [
        ProductMedia(
          path: 'assets/images/shirt.jpg',
          label: 'Test view one',
          color: 'Trắng',
        ),
        ProductMedia(
          path: 'assets/images/outerwear.jpg',
          label: 'Test view two',
          color: 'Trắng',
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: ProductGallery(product: p, color: 'Trắng'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton).last);
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<FashionImage>(find.byType(FashionImage)).first.label,
      'Test view two',
    );
    await tester.tap(find.byTooltip('Phóng to ảnh'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Test view one'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session result can be removed and no longer reopened', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(tryOnResultsProvider.notifier)
        .save(
          const TryOnResult(
            id: 'session-test',
            slug: 'nep-1',
            sku: 'WRL-1-MAIN-M',
          ),
        );
    final router = createRouter(
      initialLocation: '/virtual-try-on/session-test',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Biến thể: WRL-1-MAIN-M'), findsOneWidget);
    await tester.ensureVisible(find.text('Xóa kết quả demo'));
    await tester.tap(find.text('Xóa kết quả demo'));
    await tester.pumpAndSettle();
    expect(find.text('Phiên thử đồ không còn ở đây'), findsOneWidget);
    expect(container.read(tryOnResultsProvider), isEmpty);
  });

  for (final width in [375.0, 1440.0]) {
    for (final route in [
      '/contact',
      '/faq',
      '/collections',
      '/collections/everyday',
      '/virtual-try-on/missing',
      '/admin/inventory',
    ]) {
      testWidgets('$route at $width supports enlarged text without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
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
            child: NepApp(router: createRouter(initialLocation: route)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
